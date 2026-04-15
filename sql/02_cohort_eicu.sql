-- =====================================================================
-- eICU-CRD cohort derivation (DuckDB dialect)
--
-- Input  : DuckDB view named eicu_patient registered from the eICU-CRD
--          v2.0 patient.csv.gz file
-- Output : view s26_eicu_cohort (one row per first eligible unit stay)
--
-- Eligibility applied in this SQL:
--   - Adult (age_num >= 18; eICU "> 89" top-code mapped to 90)
--   - Unit length of stay >= 24 hours (unitdischargeoffset >= 1440 min)
--   - Non-null unit discharge status (i.e., patient actually left the unit)
--
-- Note: eICU-CRD stores times as integer minute-offsets from unit
-- admission (time zero = unit admission; 0 in unitdischargeoffset means
-- still in unit at data export).
--
-- Additional eligibility (chronic opioid exposure, pre-unit ventilation,
-- acute drug toxicity, comfort-measures-only) is applied by downstream
-- scripts. See manuscript Methods section 2.3 for the complete specification.
-- =====================================================================

-- ---- Step 1: First unit stay per uniquepid (cross-hospital) ---------
CREATE OR REPLACE TEMP VIEW _eicu_first_unit AS
SELECT
    p.patientunitstayid,
    p.uniquepid,
    p.patienthealthsystemstayid,
    p.hospitalid,
    p.unittype,
    p.unitadmitsource,
    p.unitdischargeoffset,            -- minutes from unit admit
    p.unitdischargestatus,
    p.hospitaldischargeoffset,
    p.hospitaldischargestatus,
    p.age,
    p.gender,
    p.ethnicity,
    p.admissionheight,
    p.admissionweight,
    p.dischargeweight,
    p.hospitaladmitsource,
    p.hospitalid AS center_id,
    ROW_NUMBER() OVER (PARTITION BY p.uniquepid
                       ORDER BY p.hospitaladmitoffset, p.patientunitstayid) AS unit_seq
FROM eicu_patient p
QUALIFY unit_seq = 1;

-- ---- Step 2: Apply inclusion / exclusion ----------------------------
-- Note: eICU `age` is stored as text ("> 89" for top-coded values); coerce.
CREATE OR REPLACE VIEW s26_eicu_cohort AS
SELECT *,
    CASE
       WHEN age = '> 89' THEN 90
       WHEN TRY_CAST(age AS INTEGER) IS NOT NULL THEN CAST(age AS INTEGER)
       ELSE NULL
    END AS age_num,
    unitdischargeoffset / 1440.0 AS unit_los_days
FROM _eicu_first_unit
WHERE (CASE WHEN age = '> 89' THEN 90
            WHEN TRY_CAST(age AS INTEGER) IS NOT NULL THEN CAST(age AS INTEGER)
            ELSE NULL END) >= 18
  AND unitdischargeoffset >= 1440      -- >= 24h
  AND unitdischargestatus IS NOT NULL;

-- ---- Cohort summary (validation query; run separately) --------------
-- SELECT COUNT(*) AS n_cohort,
--        SUM(CASE WHEN hospitaldischargestatus='Expired' THEN 1 ELSE 0 END) AS n_died,
--        AVG(age_num) AS mean_age,
--        AVG(unit_los_days) AS mean_los_d,
--        COUNT(DISTINCT hospitalid) AS n_centers
-- FROM s26_eicu_cohort;

-- =====================================================================
-- Edge cases documented for reviewers:
--   E1: age "> 89" is top-coded in eICU-CRD; mapped to integer 90
--   E2: uniquepid may have multiple hospital encounters; the first by
--       hospitaladmitoffset is retained
--   E3: weight and height are frequently missing and in mixed units
--       (kg/lb, cm/in); downstream R scripts perform unit harmonization
--       and imputation
--   E4: ethnicity includes "Other/Unknown" and many NAs
--   E5: hospitaladmitoffset can be negative (hospital admission prior to
--       unit admission) — expected behavior in eICU-CRD
--   E6: unitdischargestatus NULL indicates the patient was still in the
--       unit at data export and is therefore excluded
--   E7: hospitalid is retained as the only center-level identifier;
--       hospital-level metadata from hospital.csv.gz is not used in the
--       present analysis (noted as a Limitation in the manuscript)
-- =====================================================================
