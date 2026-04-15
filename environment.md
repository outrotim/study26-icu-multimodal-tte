# Computational environment

The results reported in the manuscript were produced in the following environment.
Readers reproducing the analysis should use package versions compatible with these;
newer versions may yield numerically close but not bit-identical results.

## Core software

| Component | Version |
|---|---|
| R | 4.5.1 (2025-06-13) |
| DuckDB | 1.5.1 |
| Platform | aarch64-apple-darwin20 (macOS Apple silicon) — not required for reproducibility; any platform supporting R ≥ 4.4 should work |

## R packages (primary)

| Package | Version | Purpose |
|---|---|---|
| `duckdb` | ≥ 1.5.1 | Database engine for CSV.gz querying |
| `DBI` | ≥ 1.2.0 | Database interface |
| `dplyr` | ≥ 1.1.0 | Data manipulation |
| `dbplyr` | ≥ 2.4.0 | Database-backed dplyr |
| `arrow` | ≥ 14.0 | Parquet I/O (if caching intermediate results locally) |
| `WeightIt` | ≥ 0.14 | Inverse probability of treatment weighting |
| `cobalt` | ≥ 4.5 | Covariate balance diagnostics |
| `survival` | ≥ 3.5 | Cox proportional hazards, Schoenfeld residuals |
| `cmprsk` | ≥ 2.2 | Competing-risk Fine-Gray estimator (sensitivity) |
| `meta` | ≥ 7.0 | Random-effects pooling (DerSimonian-Laird) |
| `gbm` | ≥ 2.1 | Gradient boosting for propensity score ensemble |

## R packages (plotting)

| Package | Version |
|---|---|
| `ggplot2` | ≥ 3.5 |
| `patchwork` | ≥ 1.2 |
| `scales` | ≥ 1.3 |

## Data access requirements

The PhysioNet credentialed access for MIMIC-IV v3.x and eICU-CRD v2.0 must be in place before running the SQL and R scripts. Set the following environment variables (or define equivalents at the top of each R script):

```r
Sys.setenv(
  STUDY_MIMIC_PATH = "/path/to/mimiciv",   # contains hosp/ and icu/
  STUDY_EICU_PATH  = "/path/to/eicu_crd"   # contains patient.csv.gz, diagnosis.csv.gz, etc.
)
```

The analytic scripts read these environment variables rather than hardcoded paths, so the same scripts work across contributors and systems.

## Approximate runtime on a standard laptop

| Stage | Time |
|---|---|
| Environment setup + package install | ~10 min |
| DuckDB view registration + cohort SQL (steps 1–2) | ~1 min |
| Primary IPTW + CCW Cox analysis | ~5 min |
| Figure regeneration | <1 min |

## Reproducibility notes

- Random seeds are hardcoded in `scripts/primary_analysis.R` for IPTW ensemble draws, bootstrap resampling, and Cox model fitting. Changing the seed will produce numerically nearby but not identical estimates.
- The DuckDB engine's query optimizer is version-sensitive; running on DuckDB versions substantially older than 1.5 may produce different SQL execution plans but should yield the same final counts.
- Package versions older than listed above may lack key arguments; please use the listed versions or newer.
