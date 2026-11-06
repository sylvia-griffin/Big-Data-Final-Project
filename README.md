# Sex Differences in Crash Injury Severity (COS80023 D/HD Project)

## Research question
Are female occupants more likely to be seriously injured than male occupants in comparable crashes in Victoria, and has newer vehicle design closed or widened that gap?

Sub-questions:
1. After controlling for crash circumstances, do belted female drivers and front passengers have higher odds of being killed or seriously injured (KSI) than males?
2. How does this difference change with vehicle year of manufacture and vehicle weight?
3. Does the gap hold within different crash scenarios (frontal, side impact, rear-end, run-off-road)?
4. Does the gap differ between drivers and front-seat passengers?

## Team and responsibilities
| Person | Responsibilities |
|---|---|
| Person A: Sylvia | Data preparation (joins and filtering), data log, cleaning, exploratory analysis (Steps 1 to 5) |
| Person B: Adrian | Clustering, logistic regression, random forest, model evaluation (Steps 6 and 7) |
| Both | Introduction, Conclusion, Summary, unexpected findings, final edit |

## Data
Victorian Road Crash Data (2012-01-01 to 2024-09-30), 9 CSV tables, about 168 MB in total.
Raw files are **not committed** to this repo. Download them from https://opendata.transport.vic.gov.au/dataset/victoria-road-crash-data into `data/raw/`.

## Tools
All data preparation and analysis is done in **R** (packages: `dplyr`, `readr`, `ggplot2`, plus `klaR` and `cluster` for Step 6 and `sandwich` and `ranger` for Step 7). Our tutor confirmed on 2 Nov 2026 that the joining and filtering can be done in R instead of Hive on HDInsight.

## How to run
1. Put the raw CSVs in `data/raw/`.
2. Open the project folder in RStudio (so the working directory is the project folder).
3. Install any missing packages once: `install.packages(c("dplyr", "readr", "ggplot2", "klaR", "cluster", "sandwich", "ranger"))`.
4. Run the following from the project root, in order. The cleaning and EDA scripts currently live at the root; preparation and clustering live in `R/`.

```r
source("R/01_prepare_data.R")
source("02_clean.R")
source("03_explore.R")
source("R/04_cluster.R")
source("R/05_crash_scenarios.R")
source("R/06_model.R")
source("R/07_vehicle_year_interaction.R")
source("R/08_weight_interaction.R")
source("R/09_seat_interaction.R")
source("R/10_crash_configuration_interaction.R")
source("R/11_year_robustness.R")
source("R/12_predictive_evaluation.R")
source("R/13_confusion_matrices.R")
source("R/14_recall_threshold.R")
source("R/15_balanced_threshold.R")
```

Step 6 fits k-modes to vehicle-level crash features, chooses a cluster count with a documented elbow heuristic, and compares occupants' KSI rates within the resulting scenarios. It saves `06_` tables and charts under `outputs/`, plus `occupants_clustered.csv`, `occupants_clustered.rds`, `vehicle_cluster_assignments.csv` and `cluster_model.rds` under `data/processed/`. Occupants with missing clustering features are retained with an unassigned status. These comparisons are descriptive; adjusted modelling is Step 7.

The follow-up `R/05_crash_scenarios.R` starts from the full clean dataset, maps documented DCA codes into predefined configurations, and compares KSI by sex separately for configuration and impact. It saves mapping audits, counts, rates, gaps and charts under `outputs/`, and `occupants_scenarios.csv/.rds` under `data/processed/`. This is the enriched dataset for subsequent modelling; see `docs/codebook.md` for the definitions.

`R/06_model.R` fits the baseline logistic regression to the complete-case cohort, with crash-cluster-robust confidence intervals. It saves `07_baseline_` tables for exclusions, odds ratios, reference levels, diagnostics and standardised KSI probabilities, plus `data/processed/baseline_logistic_model.rds`. The baseline estimates associations using the full eligible cohort. Subsequent scripts add interactions and a separate predictive evaluation.

`R/07_vehicle_year_interaction.R` adds sex by manufacturing-year interaction using the identical baseline cohort and controls. It saves the crash-robust interaction test, sex odds ratios by year, standardised probability curves/gaps, support counts, two charts and `vehicle_year_interaction_model.rds`. Probability curves use the same reference occupants in 2020-2024 crashes for every plotted year (1995-2020), avoiding manufacture years later than reference crash dates. Later scripts assess other interactions, nonlinear sensitivity and predictive performance.

`R/08_weight_interaction.R` retains the year interaction and adds sex by tare weight on the same cohort. It saves `07_weight_interaction_` tests, coefficients, probabilities, gaps, support counts and one chart, plus `weight_interaction_model.rds`. Conditional sex odds ratios are reported at manufacture year 2010; probability comparisons average over the full baseline cohort's observed years and controls. The odds-scale interaction test and the absolute probability-gap change answer different questions.

`R/09_seat_interaction.R` adds sex by seating position while retaining year and weight interactions. It uses the same cohort and saves `07_seat_interaction_` tables, one probability chart and `seat_interaction_model.rds`. All four sex/seat combinations use the same reference covariate distribution; conditional sex ORs refer to manufacture year 2010 and tare weight 1,500 kg.

`R/10_crash_configuration_interaction.R` adds sex by crash configuration while retaining the preceding interactions. It saves a joint six-degree-of-freedom crash-robust test, scenario-specific ORs (drivers, 2010, 1,500 kg), support counts, standardised probabilities/gaps, one OR chart and `configuration_interaction_model.rds`. Probabilities use each scenario's own covariate distribution for both sexes; reference populations differ across scenarios. Seven sex-OR tests include Holm-adjusted p-values, while displayed confidence intervals are pointwise.

`R/11_year_robustness.R` compares the fully adjusted linear-year model with a natural cubic spline allowing separate year curves by sex. It retains the cohort and other interactions, saving curvature tests, matched probability curves, endpoint contrasts, one comparison chart and `year_robustness_model.rds`. **The earlier widening-gap conclusion is sensitive to specification:** the curved model does not establish a 1995-to-2020 increase. Read the latest data-log interpretation before reporting the earlier year model. Missing-data sensitivity remains outstanding.

`R/12_predictive_evaluation.R` refits logistic regression and probability random forest on an 80/20 split by crash ID, with five-fold crash-grouped cross-validation inside the training set. Training out-of-fold log loss selects the linear/curved logistic specification and one of two forest settings; spline knots are learned separately in each training fit. It saves and reuses `predictive_split.rds`, and saves `predictive_cv.rds` and `predictive_models.rds` under processed data. The `07_predictive_` tables include CV scores, test AUC/average precision/Brier/log loss, confusion matrices at 0.5 and a training-selected threshold, calibration and sex-specific performance. ROC and calibration charts are under `outputs/figures/`. Earlier full-cohort work informed the candidate models, so this is retrospective internal validation, not untouched external or future-crash validation. Prediction does not establish causal sex or vehicle-design effects.

`R/13_confusion_matrices.R` displays the saved test predictions as confusion matrices for both models, at the training-selected cutoffs and at 0.5. It saves `07_predictive_confusion_selected.png`, `07_predictive_confusion_fixed_05.png` and `07_predictive_confusion_matrices.csv`. Rows are actual outcomes and columns are predictions; percentages are within each actual class. It checks counts against the previous evaluation without refitting models.

`R/14_recall_threshold.R` defines the current illustrative screening scenario: at least 80% recall in pooled training out-of-fold predictions. It selects the highest qualifying cutoff for each existing model and applies it unchanged to the saved test predictions. Use the full-precision cutoffs in `data/processed/predictive_screening_thresholds.rds` for this scenario (approximately 0.1192 logistic and 0.1164 forest). The new `07_recall_target_` tables and confusion chart show about 79.6% test recall, alongside more false positives and precision around 25.6%. The 80% target is a project assumption, not a Victorian authority requirement. This follow-up uses an already-inspected test set and needs fresh validation before operational use. Earlier Youden and 0.5 results remain as comparison scenarios; the models and their probability predictions are unchanged.

`R/15_balanced_threshold.R` adds a separate precision/recall compromise by maximising pooled training out-of-fold F1 for each model. It applies those frozen cutoffs to the existing test predictions, saving `07_balanced_f1_` comparison tables, sex-specific metrics and a confusion chart, plus `predictive_balanced_thresholds.rds`. F1 balances precision and recall through their harmonic mean; it does not imply equal performance, equal error costs, or balanced sensitivity/specificity. Test precision is about 35%, with recall 56–57%, so this scenario misses more KSI cases than the 80%-recall scenario. All three threshold objectives (Youden, 80% recall and F1) remain available; results are retrospective.

## Folder structure

| Folder | What goes in it |
|---|---|
| `data/raw/` | Original CSVs, never edited |
| `data/processed/` | Tables made by the R scripts (e.g. `occupants_final.csv`) |
| `R/` | Preparation, clustering, scenario and modelling scripts (`01_prepare_data.R`, `04_cluster.R`, `05_crash_scenarios.R`, `06_model.R`, `07_vehicle_year_interaction.R`, `08_weight_interaction.R`); `02_clean.R` and `03_explore.R` currently live at the project root |
| `outputs/figures/` | Charts for the report |
| `outputs/tables/` | Summary tables and model outputs (CSV) |
| `screenshots/` | Screenshots of practical work for the Methodology section |
| `report/` | Report drafts |
| `docs/` | Data log and codebook |

