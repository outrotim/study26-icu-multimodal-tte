# Early Multimodal Analgesia and Mortality in the Intensive Care Unit — Code Supplement

This repository provides the minimal analytic code accompanying the manuscript:

> *Early Multimodal Analgesia and Mortality in the Intensive Care Unit: An Association Analysis via Target Trial Emulation in MIMIC-IV and eICU-CRD* (submitted 2026)

It contains **code only**. No patient-level data are included.

---

## Repository contents

| Path | Purpose |
|---|---|
| `README.md` | This file |
| `LICENSE` | MIT license for the R / SQL code |
| `environment.md` | R version and package list used to generate the reported results |
| `sql/01_cohort_mimic.sql` | DuckDB SQL for MIMIC-IV cohort derivation |
| `sql/02_cohort_eicu.sql` | DuckDB SQL for eICU-CRD cohort derivation |
| `scripts/primary_analysis.R` | Merged, cleaned analytic pipeline — IPTW + clone-censor-weight + cause-specific Cox for primary 30-day in-hospital mortality, with E-value and grace-period sensitivity |
| `scripts/figures_main.R` | ggplot2 code to re-draw Figures 2 and 3 from saved result objects |
| `dictionaries/itemid_dictionary.csv` | MIMIC-IV item identifiers and eICU-CRD HICL codes used to classify exposures and outcomes (CC-BY 4.0) |

---

## Data availability

The analyses in the manuscript use two publicly available databases, **not bundled in this repository**:

- **MIMIC-IV** (version 3.x) — Johnson AEW et al., Sci Data 2023. Available at <https://physionet.org/content/mimiciv/> after completion of credentialed data use agreements and CITI training.
- **eICU-CRD** (version 2.0) — Pollard TJ et al., Sci Data 2018. Available at <https://physionet.org/content/eicu-crd/> under the same credentialing.

No patient-level data, intermediate parquet files, DuckDB databases, or analytic logs from the authors' local environment are redistributed here. Researchers wishing to reproduce the analyses must obtain the source databases independently through PhysioNet.

---

## How to reproduce

1. **Obtain the data**. Download MIMIC-IV v3.x and eICU-CRD v2.0 from PhysioNet and place them at local paths.
2. **Set up R 4.5.1** with the packages listed in `environment.md`.
3. **Edit the path constants** at the top of `scripts/primary_analysis.R` and `scripts/figures_main.R` to point to your local data.
4. **Run the SQL** (`sql/01_cohort_mimic.sql` and `sql/02_cohort_eicu.sql`) against a DuckDB connection registered with the MIMIC-IV `hosp` + `icu` views and eICU-CRD `patient` view. These produce the eligible-cohort tables referenced downstream.
5. **Run `scripts/primary_analysis.R`**. This produces the central hazard-ratio estimates reported in the manuscript's Table 2 Panel A.
6. **Run `scripts/figures_main.R`** to regenerate Figures 2 and 3 from the saved result objects of step 5.

Note that SQL scripts for exposure classification, outcome derivation, and covariate extraction (Supplementary Methods 2–4 of the manuscript) are documented in the manuscript's Supplementary Methods but are **not bundled here** to keep the repository minimal. Readers who wish to fully reproduce every table can reconstruct these from the dictionary (`dictionaries/itemid_dictionary.csv`) and the descriptions in Supplementary Methods.

---

## Important caveats

- **Association-level analysis**. The manuscript and this code implement an observational association analysis structured via target trial emulation (Hernán & Robins, 2016). The framework does not confer causal identifiability beyond the assumptions of no unmeasured confounding and correct model specification. See the manuscript's Limitations for an extended discussion.
- **Population specificity**. Estimates apply to adult ICU patients with length of stay ≥ 24 hours who received a classifiable analgesia strategy within the first 24 hours. They do not apply to the broader ICU population (see manuscript Limitation #15 on the unclassifiable subset).
- **Magnitude interpretation**. The hazard-ratio magnitudes reported (MIMIC-IV HR 0.33; eICU-CRD HR 0.51) exceed those observed in prior randomized trial meta-analyses; the direction — not a single point estimate — is the primary finding. The code as written reproduces the reported point estimates under the manuscript's analytic choices; readers transporting this code to other settings should plan for the residual confounding discussion in Methods §2.7 and Discussion §4.2 to remain central.
- **No predictive model is distributed**. This is not a prognostic model for clinical use. Do not deploy outputs of `primary_analysis.R` for individual patient decisions.

---

## License

- **Code** (all `.R` and `.sql` files): MIT License (see `LICENSE`)
- **Dictionary** (`dictionaries/itemid_dictionary.csv`): CC-BY 4.0

The MIMIC-IV and eICU-CRD databases themselves are governed by the PhysioNet Credentialed Health Data License 1.5.0 and the relevant Data Use Agreements; nothing in this repository confers any additional rights over those databases.

---

## Citation

If you use this code, please cite the manuscript:

> [Citation to be inserted upon publication.]

---

## Contact

Issues and reproducibility questions may be raised via the GitHub issue tracker for this repository.
