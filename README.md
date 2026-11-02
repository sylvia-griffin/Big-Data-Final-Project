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
Raw files are **not committed** to this repo. Download them from https://liveswinburneeduau-my.sharepoint.com/:f:/r/personal/106064277_student_swin_edu_au/Documents/Big%20Data%20HD%20Project!/COS80023%20crash%20data?d=wa0ef3d96307b4731bcc9655f8be5fe3f&csf=1&web=1&e=NCzYqk into `data/raw/`.

## Tools
All data preparation and analysis is done in **R** (packages: `dplyr`, `readr`, `ggplot2`). Our tutor confirmed on 2 Nov 2026 that the joining and filtering can be done in R instead of Hive on HDInsight.

## How to run
1. Put the raw CSVs in `data/raw/`.
2. Open the project folder in RStudio (so the working directory is the project folder).
3. Run the scripts in `R/` in number order. Each one saves its outputs for the next.

## Folder structure
| Folder | What goes in it |
|---|---|
| `data/raw/` | Original CSVs, never edited |
| `data/processed/` | Tables made by the R scripts (e.g. `occupants_final.csv`) |
| `R/` | R scripts, numbered in run order (`01_prepare_data.R`, `02_clean.R`, `03_explore.R`, ...) |
| `outputs/figures/` | Charts for the report |
| `outputs/tables/` | Summary tables and model outputs (CSV) |
| `screenshots/` | Screenshots of practical work for the Methodology section |
| `report/` | Report drafts |
| `docs/` | Data log and codebook |

## Conventions
- **Screenshots:** name them `step_description_date.png`, e.g. `03_prepare_data_counts_2026-11-02.png`. The template asks for screenshots of practical work, so take them as you go.
- **Data log:** every time you filter, drop or recode data, add a row to `docs/data_log.md` with the row count before and after.
- **Scripts:** each script should run top to bottom from the raw data without manual steps.
- **Commits:** small and descriptive, e.g. "Add vehicle era bands to cleaning script".
