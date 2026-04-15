# =====================================================================
# Primary analysis — merged, cleaned pipeline accompanying the manuscript
#   "Early Multimodal Analgesia and Mortality in the ICU: A TTE Analysis"
#
# This script reproduces the central results reported in Table 2 Panel A:
#   - MIMIC-IV mortality HR (clone-censor-weight, IPTW-adjusted)
#   - eICU-CRD mortality HR
#   - Random-effects pooled estimate
#   - E-values
#   - Grace-period sensitivity
#   - Schoenfeld PH test
#   - Unweighted CCW decomposition
#
# Prerequisites:
#   1. PhysioNet credentialed access to MIMIC-IV v3.x and eICU-CRD v2.0
#   2. R 4.5.1 with packages listed in environment.md
#   3. Environment variables STUDY_MIMIC_PATH and STUDY_EICU_PATH set
#   4. DuckDB views registered per sql/01_cohort_mimic.sql and 02_cohort_eicu.sql
#   5. Exposure/outcome/covariate SQL per Supplementary Methods 2-4 executed
#      to produce analytic_panel.parquet and mortality_precise.parquet files
#
# Run time: approximately 5 minutes on a modern laptop.
# =====================================================================

suppressPackageStartupMessages({
  library(dplyr); library(arrow); library(survival)
  library(WeightIt); library(meta)
})

# ---- Paths (adapt via environment variables) -----------------------
STUDY_ROOT <- Sys.getenv("STUDY_ROOT", unset = ".")
DATA_HARM  <- file.path(STUDY_ROOT, "data/harmonized")
DATA_MIMIC <- file.path(STUDY_ROOT, "data/mimic")
DATA_EICU  <- file.path(STUDY_ROOT, "data/eicu")

stopifnot(
  "analytic_panel.parquet not found - run exposure+outcome SQL per S-Methods 2-4 first" =
    file.exists(file.path(DATA_HARM, "analytic_panel.parquet"))
)

set.seed(20260414)  # master seed; per-step seeds defined below for reproducibility

# ---- Load harmonized analytic panel --------------------------------
panel <- read_parquet(file.path(DATA_HARM, "analytic_panel.parquet"))
mimic_mort <- read_parquet(file.path(DATA_MIMIC, "s26_mimic_mortality_precise.parquet")) |>
  rename(subject_uid = stay_id) |> mutate(subject_uid = as.character(subject_uid))
eicu_mort <- read_parquet(file.path(DATA_EICU, "s26_eicu_mortality_precise.parquet")) |>
  rename(subject_uid = unitid) |> mutate(subject_uid = as.character(subject_uid))

# ---- Prep per-database frames --------------------------------------
prep <- function(df) {
  df |>
    mutate(treat = as.integer(exposure_group == "A")) |>
    filter(!is.na(age), !is.na(creatinine_max), !is.na(hemoglobin_min)) |>
    mutate(across(c(lactate_max, wbc_max, ph_min, sodium_max),
                  ~ ifelse(is.na(.), median(., na.rm = TRUE), .)))
}
mimic <- panel |> filter(db_source == "MIMIC") |>
  left_join(mimic_mort, by = "subject_uid") |> prep()
eicu <- panel |> filter(db_source == "eICU") |>
  left_join(eicu_mort, by = "subject_uid") |> prep()

# ---- IPTW ensemble (logistic + GBM) --------------------------------
covs <- c("age", "female", "comorb_chf", "comorb_copd", "comorb_ckd",
          "comorb_dm", "comorb_liver", "comorb_dementia", "sepsis",
          "creatinine_max", "lactate_max", "wbc_max", "hemoglobin_min",
          "ph_min", "sodium_max")
f_treat <- as.formula(paste("treat ~", paste(covs, collapse = " + ")))

fit_ps <- function(df, seed) {
  set.seed(seed)
  w_log <- weightit(f_treat, data = df, method = "ps",
                    estimand = "ATE", stabilize = TRUE)
  w_gbm <- weightit(f_treat, data = df, method = "gbm",
                    estimand = "ATE", stabilize = TRUE,
                    n.trees = 500, interaction.depth = 3, shrinkage = 0.05)
  # Ensemble: arithmetic mean of the two predicted propensities
  ps_ens <- (w_log$ps + w_gbm$ps) / 2
  df$ps_ens <- pmax(pmin(ps_ens, 0.99), 0.01)
  df
}
mimic <- fit_ps(mimic, seed = 2026)
eicu  <- fit_ps(eicu,  seed = 2027)

# ---- Clone-censor-weight helper ------------------------------------
ccw_hr <- function(df, grace_h = 24, weighted = TRUE) {
  a <- df |> mutate(clone = "A", match = treat == 1, ps_clone = ps_ens)
  b <- df |> mutate(clone = "B", match = treat == 0, ps_clone = 1 - ps_ens)
  cl <- bind_rows(a, b) |>
    mutate(
      eff_time  = ifelse(match, time_to_death_h, pmin(time_to_death_h, grace_h)),
      eff_event = ifelse(eff_time == time_to_death_h & death_30d == 1, 1, 0),
      clone_A   = as.integer(clone == "A"),
      ipw_raw   = ifelse(clone == "A",
                         mean(df$treat) / ps_clone,
                         mean(1 - df$treat) / ps_clone)
    ) |>
    filter(eff_time > 0)
  qs <- quantile(cl$ipw_raw, c(0.01, 0.99), na.rm = TRUE)
  cl$ipw_trim <- pmin(pmax(cl$ipw_raw, qs[1]), qs[2])
  if (weighted) {
    coxph(Surv(eff_time, eff_event) ~ clone_A,
          data = cl, weights = ipw_trim,
          cluster = subject_uid, robust = TRUE)
  } else {
    coxph(Surv(eff_time, eff_event) ~ clone_A,
          data = cl, cluster = subject_uid, robust = TRUE)
  }
}

# ---- Primary mortality estimates (grace 24h) -----------------------
m_mimic <- ccw_hr(mimic, grace_h = 24, weighted = TRUE)
m_eicu  <- ccw_hr(eicu,  grace_h = 24, weighted = TRUE)
cat("\n=== Primary mortality HR (IPTW + CCW, grace 24h) ===\n")
cat("MIMIC-IV:\n"); print(summary(m_mimic)$conf.int)
cat("eICU-CRD:\n"); print(summary(m_eicu)$conf.int)

# ---- Random-effects pooling ----------------------------------------
logHR_m <- summary(m_mimic)$coefficients[1, "coef"]
se_m    <- summary(m_mimic)$coefficients[1, "robust se"]
logHR_e <- summary(m_eicu)$coefficients[1, "coef"]
se_e    <- summary(m_eicu)$coefficients[1, "robust se"]
pool <- metagen(TE = c(logHR_m, logHR_e),
                seTE = c(se_m, se_e),
                studlab = c("MIMIC-IV", "eICU-CRD"),
                sm = "HR", method.tau = "DL")
cat(sprintf("\n=== Pooled ===\n  FE: HR %.3f (%.3f, %.3f)  I2=%.1f%%\n",
            exp(pool$TE.common), exp(pool$lower.common), exp(pool$upper.common),
            pool$I2 * 100))
cat(sprintf("  RE: HR %.3f (%.3f, %.3f)  tau2=%.3f\n",
            exp(pool$TE.random), exp(pool$lower.random), exp(pool$upper.random),
            pool$tau2))

# ---- E-values ------------------------------------------------------
evalue <- function(hr) {
  if (hr < 1) hr <- 1 / hr
  round(hr + sqrt(hr * (hr - 1)), 2)
}
cat(sprintf("\n=== E-values ===\n  MIMIC-IV HR %.3f  E=%.2f (upper CI %.3f  E=%.2f)\n",
            exp(logHR_m), evalue(exp(logHR_m)),
            exp(logHR_m + 1.96 * se_m), evalue(exp(logHR_m + 1.96 * se_m))))
cat(sprintf("  eICU-CRD HR %.3f  E=%.2f (upper CI %.3f  E=%.2f)\n",
            exp(logHR_e), evalue(exp(logHR_e)),
            exp(logHR_e + 1.96 * se_e), evalue(exp(logHR_e + 1.96 * se_e))))

# ---- Grace-period sensitivity --------------------------------------
cat("\n=== Grace-period sensitivity ===\n")
for (g in c(6, 12, 24, 48)) {
  m <- ccw_hr(mimic, grace_h = g); e <- ccw_hr(eicu, grace_h = g)
  cat(sprintf("  grace %2dh: MIMIC HR %.3f | eICU HR %.3f\n", g,
              summary(m)$conf.int[1, 1], summary(e)$conf.int[1, 1]))
}

# ---- Unweighted CCW decomposition (Results section 3.2) ------------
cat("\n=== Unweighted clone-censor mortality ===\n")
cat(sprintf("  MIMIC-IV: HR %.3f\n", summary(ccw_hr(mimic, weighted = FALSE))$conf.int[1, 1]))
cat(sprintf("  eICU-CRD: HR %.3f\n", summary(ccw_hr(eicu,  weighted = FALSE))$conf.int[1, 1]))

# ---- Schoenfeld proportional hazards test --------------------------
cat("\n=== Schoenfeld test for primary Cox ===\n")
cat(sprintf("  MIMIC-IV  p = %.4f\n", cox.zph(m_mimic)$table[1, "p"]))
cat(sprintf("  eICU-CRD  p = %.4f\n", cox.zph(m_eicu)$table[1, "p"]))

# ---- Save final result object for figure script -------------------
results_obj <- list(
  mimic_HR = round(exp(logHR_m), 3),
  mimic_CI = round(exp(c(logHR_m - 1.96 * se_m, logHR_m + 1.96 * se_m)), 3),
  eicu_HR  = round(exp(logHR_e), 3),
  eicu_CI  = round(exp(c(logHR_e - 1.96 * se_e, logHR_e + 1.96 * se_e)), 3),
  pooled_RE_HR = round(exp(pool$TE.random), 3),
  pooled_RE_CI = round(exp(c(pool$lower.random, pool$upper.random)), 3),
  I2 = round(pool$I2 * 100, 1),
  evalue_mimic = evalue(exp(logHR_m)),
  evalue_eicu  = evalue(exp(logHR_e))
)
saveRDS(results_obj, file.path(STUDY_ROOT, "primary_results.rds"))
cat("\nSaved: primary_results.rds - consumed by scripts/figures_main.R\n")
