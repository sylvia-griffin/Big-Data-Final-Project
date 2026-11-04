# Final research results

Outcome: killed or seriously injured (KSI), not fatality alone. All main estimates below come from the same final primary model, including sex interactions with manufacturing year, weight, seat, crash configuration and impact location. Age band, speed band, vehicle-count group and crash year are also adjusted for. The same 175,453 occupants from 100,085 crashes are used for both fitted specifications; no new exclusions were introduced.

## Consistent primary results table

Values are model-standardised probabilities, not raw observed rates. Positive gaps and odds ratios above one indicate higher female estimates. Intervals are pointwise 95% intervals using crash-cluster-robust HC1 covariance and the delta method. The odds ratio is calculated from the two standardised mean probabilities (a marginal OR), not a single regression coefficient.

| Research topic | Comparison | Male KSI | Female KSI | Female-minus-male gap, percentage points (95% CI) | Marginal female/male OR (95% CI) |
|---|---|---:|---:|---:|---:|
| Q1 Overall | All eligible complete cases | 14.65% | 18.87% | 4.22 (3.89 to 4.56) | 1.36 (1.32 to 1.39) |
| Q2 Vehicle year | 1995 | 15.92% | 19.71% | 3.80 (3.08 to 4.52) | 1.30 (1.24 to 1.36) |
| Q2 Vehicle year | 2000 | 15.03% | 19.01% | 3.98 (3.47 to 4.49) | 1.33 (1.28 to 1.37) |
| Q2 Vehicle year | 2010 | 13.37% | 17.65% | 4.28 (3.93 to 4.63) | 1.39 (1.35 to 1.43) |
| Q2 Vehicle year | 2020 | 11.86% | 16.37% | 4.51 (3.92 to 5.10) | 1.45 (1.38 to 1.53) |
| Q2 Vehicle weight | 1000 kg | 18.20% | 23.28% | 5.09 (4.42 to 5.75) | 1.36 (1.31 to 1.42) |
| Q2 Vehicle weight | 1500 kg | 14.31% | 18.47% | 4.16 (3.82 to 4.50) | 1.36 (1.32 to 1.39) |
| Q2 Vehicle weight | 2000 kg | 11.10% | 14.42% | 3.32 (2.75 to 3.90) | 1.35 (1.28 to 1.42) |
| Q3 Configuration | Rear-end | 7.48% | 12.07% | 4.59 (4.06 to 5.11) | 1.70 (1.60 to 1.80) |
| Q3 Configuration | Head-on (not overtaking) | 28.28% | 35.25% | 6.97 (5.13 to 8.80) | 1.38 (1.27 to 1.50) |
| Q3 Configuration | Adjacent-direction intersection | 12.81% | 18.35% | 5.54 (4.85 to 6.23) | 1.53 (1.45 to 1.61) |
| Q3 Configuration | Opposing-direction turning | 10.99% | 17.84% | 6.85 (5.96 to 7.73) | 1.76 (1.63 to 1.89) |
| Q3 Configuration | Run-off-road | 41.16% | 39.86% | -1.29 (-2.66 to 0.07) | 0.95 (0.90 to 1.00) |
| Q3 Configuration | Loss of control on carriageway | 16.88% | 11.98% | -4.91 (-9.96 to 0.14) | 0.67 (0.44 to 1.03) |
| Q3 Configuration | Other known configurations | 10.87% | 14.18% | 3.32 (2.69 to 3.95) | 1.36 (1.28 to 1.44) |
| Q3 Impact | Front | 16.52% | 21.21% | 4.69 (4.25 to 5.13) | 1.36 (1.32 to 1.40) |
| Q3 Impact | Side | 18.02% | 21.43% | 3.41 (2.42 to 4.41) | 1.24 (1.17 to 1.32) |
| Q3 Impact | Rear | 7.66% | 11.26% | 3.60 (3.06 to 4.15) | 1.53 (1.43 to 1.63) |
| Q3 Impact | Other | 17.91% | 18.66% | 0.75 (-2.13 to 3.63) | 1.05 (0.87 to 1.27) |
| Q4 Seating | Driver | 14.86% | 18.66% | 3.81 (3.43 to 4.18) | 1.31 (1.28 to 1.35) |
| Q4 Seating | Front passenger | 13.60% | 20.01% | 6.40 (5.56 to 7.25) | 1.59 (1.49 to 1.69) |

## Tests of differences in the sex association

These joint tests concern conditional odds-ratio interactions. They are different from tests of the standardised probability gap. Raw p-values and Holm adjustments across the five primary interaction questions are shown; neither establishes causation.

| Interaction | Degrees of freedom | p-value | Holm-adjusted p-value |
|---|---:|---:|---:|
| Sex x manufacture year | 1 | 0.004 | 0.008 |
| Sex x weight | 1 | 0.837 | 0.837 |
| Sex x seat | 1 | <0.001 | <0.001 |
| Sex x configuration | 6 | <0.001 | <0.001 |
| Sex x impact | 3 | 0.001 | 0.003 |

## Interpretation of the current results

The overall standardised comparison supports higher female KSI odds/probability in this cohort, but the association is not uniform across circumstances. Front, side and rear impact groups have positive female-minus-male gaps; the Other impact interval includes zero. Run-off-road and loss-of-control configuration intervals also include zero, so an established reversal should not be claimed. A significant joint interaction does not establish a difference between every pair of categories.

The seating comparison supports a larger female-minus-male gap among front passengers. Weight illustrates the importance of scale: the conditional sex-by-weight odds interaction has little evidence of variation, while the absolute probability gap falls with weight. These statements can both hold as baseline KSI probability changes. The absolute weight and seating gap-change intervals are supplied in `07_final_gap_changes.csv`.

The primary model's relative sex odds vary with year, but the absolute 1995-to-2020 gap-change interval includes zero. The matched curved-year model also permits either narrowing or widening at those endpoints. A steady widening or closing of the gap with newer design is therefore not robustly established. Observed associations do not identify a causal vehicle-design effect.

## Vehicle-year sensitivity, retaining sex x impact

The sensitivity model permits a four-df natural spline for year with separate curves by sex and keeps all other controls/interactions. It is compared against the current primary model, not the earlier year-only interaction model.

| Model | Change in female-minus-male gap, 2020 minus 1995 (percentage points, 95% CI) | p-value |
|---|---:|---:|
| Primary | 0.71 (-0.42 to 1.84) | 0.216 |
| Curved | 0.02 (-1.42 to 1.47) | 0.975 |

All curved-model comparisons are saved in `outputs/tables/07_final_sensitivity_results.csv`; year, weight and seating gap contrasts with joint uncertainty are in `07_final_gap_changes.csv`.

## How to read the reference populations

For every row, exactly the same reference occupants/covariates are used for male and female predictions. Overall estimates use the full cohort. Year rows use the same 62,244 occupants in 2020-2024 crashes with manufacture year set to the indicated value. Weight and seat rows use the full cohort with the named variable set to the indicated value. Configuration and impact rows use each group's observed covariate distribution, retaining plausible combinations with other crash characteristics. Therefore reference populations differ across configuration/impact rows: comparing their absolute gaps is not a causal effect of changing crash circumstances. The joint interaction tests assess heterogeneity after adjustment.

## Scope and limitations

These are adjusted associations among belted male/female drivers and left-front passengers aged 16+ with complete data in cars, station wagons and utes in recorded Victorian crashes. Manufacturing year is a proxy for design era and is not an identified design intervention. Broad age/speed categories and other unmeasured circumstances leave possible residual confounding. Other impact/configuration categories are heterogeneous, and some configuration-by-impact cells are sparse (see the support table). No three-way interactions are fitted.

The reference-covariate distributions are treated as fixed in the delta-method intervals. Displayed intervals are pointwise; within-section Holm-adjusted gap p-values are provided in the CSVs. Exclusion/missing-data sensitivity is deferred at the user's request, not completed. The separate predictive evaluation/threshold scenarios remain based on their previously fitted models and were not rerun or relabelled as validation of this updated association model.

Reproduce with `R/16_impact_interaction.R` followed by `R/17_final_results.R`. Detailed coefficients, all interaction tests, support counts and model diagnostics are under `outputs/tables/`. Model provenance and covariance matrices are in `data/processed/final_association_models.rds`.
