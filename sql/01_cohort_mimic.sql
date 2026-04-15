-- =====================================================================
-- MIMIC-IV cohort derivation (DuckDB dialect)
--
-- Input  : DuckDB views named mimic_icustays, mimic_admissions, mimic_patients
--          registered from the corresponding MIMIC-IV v3.x CSV.gz files
-- Output : view s26_mimic_cohort (one row per first eligible ICU stay)
--
-- Eligibility applied in this SQL:
--   - Adult (age_at_icu >= 18)
--   - ICU length of stay >= 1 day (i.e., >= 24 hours)
--   - No death within 24 hours of ICU admission
--
-- Additional eligibility (chronic opioid exposure, pre-ICU ventilation >24h,
-- primary acute drug toxicity, comfort-measures-only, acute drug poisoning)
-- is applied by downstream scripts. See manuscript Methods section 2.3 for
-- the complete eligibility specification.
-- =====================================================================

-- ---- Step 1: First ICU stay per patient -----------------------------
CREATE OR REPLACE TEMP VIEW _mimic_first_icu AS
SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.first_careunit,
    icu.intime  AS icu_intime,
    icu.outtime AS icu_outtime,
    icu.los     AS icu_los_days,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS icu_seq
FROM mimic_icustays icu
QUALIFY icu_seq = 1;

-- ---- Step 2: Join admission + patient demographics ------------------
CREATE OR REPLACE TEMP VIEW _mimic_demo AS
SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.first_careunit,
    f.icu_intime,
    f.icu_outtime,
    f.icu_los_days,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.race,
    a.hospital_expire_flag,
    -- Age at ICU admission (MIMIC-IV anchor-shifted)
    p.anchor_age + EXTRACT(YEAR FROM f.icu_intime) - p.anchor_year AS age_at_icu
FROM _mimic_first_icu f
LEFT JOIN mimic_admissions a ON f.hadm_id    = a.hadm_id
LEFT JOIN mimic_patients   p ON f.subject_id = p.subject_id;

-- ---- Step 3: Apply inclusion / exclusion ----------------------------
CREATE OR REPLACE VIEW s26_mimic_cohort AS
SELECT *,
    -- exclusion flags (1 = excluded); kept for audit / flow diagram
    CASE WHEN age_at_icu < 18 THEN 1 ELSE 0 END         AS excl_age,
    CASE WHEN icu_los_days < 1 THEN 1 ELSE 0 END        AS excl_short_stay,
    CASE WHEN deathtime IS NOT NULL
         AND deathtime <= icu_intime + INTERVAL 24 HOUR THEN 1 ELSE 0 END AS excl_early_death
FROM _mimic_demo
WHERE age_at_icu >= 18
  AND icu_los_days >= 1
  AND (deathtime IS NULL
       OR deathtime > icu_intime + INTERVAL 24 HOUR);

-- ---- Step 4: Validation query (run after creation) ------------------
-- SELECT COUNT(*) AS n_cohort,
--        SUM(hospital_expire_flag) AS n_died,
--        AVG(age_at_icu) AS mean_age,
--        AVG(icu_los_days) AS mean_los_d
-- FROM s26_mimic_cohort;

-- =====================================================================
-- Edge cases documented for reviewers:
--   E1: anchor_age + year shift can produce age 90+; MIMIC-IV caps at 91
--   E2: Patients with multiple ICU re-admissions in one hadm_id are
--       represented by the first ICU stay only (ordered by intime)
--   E3: admissions.deathtime and patients.dod may disagree; deathtime
--       is preferred here because it is minute-level and ICU-anchored
--   E4: race has 30+ raw categories; harmonization to a reduced set is
--       performed by downstream R scripts
--   E5: anchor_year groups (2008-2010, 2011-2013, ..., 2020-2022)
--       introduce a potential era effect that enters the covariate set
--       as calendar year
--   E6: A subject_id with multiple hadm_id values is represented by the
--       hadm_id associated with the first qualifying ICU stay
-- =====================================================================
