# Data Log

Record every step that changes the data. This becomes the Data Preparation section of the report.

## Raw tables (as supplied)
Row counts exclude the header. `R/01_prepare_data.R` prints these when it reads the files; they should match.

| Table | Rows | Columns | Joins on | Used in project? |
|---|---:|---:|---|---|
| accident.csv | 182,039 | 23 | ACCIDENT_NO | Yes |
| person.csv | 425,352 | 14 | ACCIDENT_NO, VEHICLE_ID | Yes |
| vehicle.csv | 331,992 | 37 | ACCIDENT_NO, VEHICLE_ID | Yes |
| accident_event.csv | 301,710 | 13 | ACCIDENT_NO, VEHICLE_ID | Maybe (impact type) |
| accident_location.csv | 182,039 | 9 | ACCIDENT_NO | No |
| atmospheric_cond.csv | 184,408 | 4 | ACCIDENT_NO | Maybe (control) |
| road_surface_cond.csv | 183,053 | 4 | ACCIDENT_NO | Maybe (control) |
| node.csv | 184,828 | 11 | ACCIDENT_NO | No |
| sub_dca.csv | 261,416 | 4 | ACCIDENT_NO | No |

## Processing steps
Counts come from `R/01_prepare_data.R` (it prints them and saves them to `outputs/tables/step3_filter_counts.csv`). Add the date when you run it and check your numbers match.

| # | Date | Who | Step | Tool | Rows before | Rows after | Rows removed | Reason |
|---:|---|---|---|---|---:|---:|---:|---|
| 1 | 02/11/2026 | Sylvia | Join person + vehicle + accident (inner join on vehicle) | R | 425,352 | 408,264 | 17,088 | People with no vehicle (mostly pedestrians) are not occupants |
| 2 | 02/11/2026 | Sylvia | Keep drivers (D) and left-front passengers (LF) | R | 408,264 | 363,984 | 44,280 | Research focus is front-seat occupants |
| 3 | 02/11/2026 | Sylvia | Keep cars, station wagons and utes (types 01, 02, 04) | R | 363,984 | 288,823 | 75,161 | Light passenger vehicles with comparable safety design |
| 4 | 02/11/2026 | Sylvia | Keep sex = M or F | R | 288,823 | 282,399 | 6,424 | Sex is the main variable; unknown cannot be used |
| 5 | 02/11/2026 | Sylvia | Keep seatbelt worn (code 1) | R | 282,399 | 194,061 | 88,338 | Removes the effect of belt use on injury. Belt = 1 or 9 kept separately for the sensitivity check |
| 6 | 02/11/2026 | Sylvia | Handle missing or zero tare weight | R | 194,061 | 194,061 | 0 | 3,019 set to NA (2,907 blank or 0 kg, 112 under 600 kg or over 3,500 kg). Kept in table, excluded from weight comparisons |
| 7 | 02/11/2026 | Sylvia | Handle missing or invalid vehicle year | R | 194,061 | 194,061 | 0 | 2,597 set to NA (492 blank, 2,105 before 1960 or after 2025). Kept in table, excluded from era comparisons |
| 8 | 02/11/2026 | Sylvia | Group ages into 4 bands | R | 194,061 | 194,061 | 0 | 4,093 set to NA (3,544 children under 16, 549 unknown age). Children excluded from age comparisons because their bodies differ |
| 9 | 02/11/2026 | Sylvia | Group speed zones into 4 bands | R | 194,061 | 194,061 | 0 | 5,501 set to NA (speed codes 777 other, 888 off road, 999 not known) |
| 10 | 02/11/2026 | Sylvia | Group impact point into Front / Side / Rear / Other | R | 194,061 | 194,061 | 0 | 4,753 set to NA (codes 9 not known, 0 towed unit, S sidecar, blank) |
| 11 | 02/11/2026 | Sylvia | Group accident type into 4 crash types; flag single vs multi-vehicle | R | 194,061 | 194,061 | 0 | No missing values. 175,500 people (90%) have all grouped variables filled in |

Sensitivity table (seatbelt worn OR not known, codes 1 and 9): 273,850 rows. Saved as `data/processed/occupants_sensitivity.csv`.

## Decisions and assumptions
Write down any judgement call and why you made it.

| Date | Decision | Reason | Agreed by |
|---|---|---|---|
| 02/11/2026 | Do joining and filtering in R instead of Hive on HDInsight | No access to the COS80023 Azure subscription; tutor (Afzaal) confirmed R is fine | Sylvia, tutor |
| 02/11/2026 | Treat tare weight of 0 kg as missing | A vehicle cannot weigh 0 kg; done in `R/01_prepare_data.R` | Sylvia |
| 02/11/2026 | Missing or invalid values set to NA, not removed | Keeps the full 194,061 people; each analysis uses whoever has the values it needs | Sylvia |
| 02/11/2026 | Sensitivity check including seatbelt unknown (code 9) | Gap remains (ratio 1.20 vs 1.25 for belted only), so excluding unknowns does not drive the result | Sylvia |
| | | | |

## Questions to check
| Question | Answer | Source |
|---|---|---|
| Which HELMET_BELT_WORN code means "seatbelt worn"? | 1 = Seatbelt worn (9 = not known) | Person data dictionary |
| Which INJ_LEVEL codes are fatal and serious? | 1 = Fatality, 2 = Serious injury | Person data dictionary |
| Are "not injured" people recorded for all crashes or only some? | Yes for occupants. For about 96% of cars, wagons and utes, the number of person records matches TOTAL_NO_OCCUPANTS. But only crashes with at least one injury are in the dataset (just 4 non-injury crashes). | Data check, 19/10 |
| Which vehicle types count as light passenger vehicles? | 01 Car, 02 Station wagon, 04 Utility | Vehicle data dictionary |

## Data quality findings (Step 2)
Checked 19/10 on drivers and left-front passengers of cars, wagons and utes (288,823 people before any other filter).

| Issue | Size | Plan |
|---|---|---|
| Seatbelt status unknown (code 9) | 83,011 (29%) | Big. Main analysis uses belt = 1 only. Run a sensitivity check that includes unknowns, because the female vs male gap looks much smaller in this group (13.5% vs 13.1% KSI), so this choice could affect results. Discuss in the report. |
| Sex unknown (U) or blank | 6,424 (2%) | Drop |
| Vehicle year = 0 | about 3,000 | Treat as missing |
| Vehicle year before 1960 or after 2025 | about 900 | Check, probably treat as missing or as a "pre-1990" band |
| Tare weight = 0 or NULL | about 5,700 (2%) | Treat as missing |
| Tare weight < 600 kg or > 3,500 kg | 167 | Check for errors |
| Speed zone 777 / 888 / 999 | about 13,000 crashes (7%) | Treat as unknown category |
| INITIAL_IMPACT mixes letters (F, R) and numbered corners | n/a | Group into frontal / side / rear / other (see codebook) |
| 2024 only covers Jan to Sep | n/a | Note it. Fine for vehicle-year analysis. |
| Pedestrians have no VEHICLE_ID | 17,088 person rows | Not a problem, removed by the front-seat filter |
| No duplicate keys in person, vehicle or accident | 0 | None needed |

Note: the person dictionary describes SEX as "the driver's sex", but in practice it is filled in for passengers and pedestrians too. Mention this in the data section.

## Step 6: Crash scenario clustering (02/11/2026)

`R/04_cluster.R` clusters one row per `ACCIDENT_NO + VEHICLE_ID`, then attaches each vehicle's cluster to its occupants. This prevents vehicles with two eligible occupants receiving extra weight. Vehicles in the same crash can have different impact points and therefore different scenarios.

| Stage | Vehicles | Occupants |
|---|---:|---:|
| Clean input | 163,141 | 194,061 |
| Complete clustering features | 153,177 | 182,531 |
| Unassigned because a clustering feature is missing | 9,964 | 11,530 |

All 194,061 occupants remain in `occupants_clustered.csv/.rds`; unassigned records have a missing cluster ID and an explicit status. The original clean files are unchanged. Counts are generated in `outputs/tables/06_cluster_filter_counts.csv`.

| Clustering feature | Missing vehicles | Missing occupants | Decision |
|---|---:|---:|---|
| Speed band | 4,863 | 5,501 | Use the Step 4 bands; missing values remain missing |
| Crash type | 0 | 0 | Use the Step 4 categories |
| Impact | 3,964 | 4,753 | Use the Step 4 categories; missing values remain missing |
| Road context | 187 | 222 | Geometry 1-4 = intersection; 5-6 = non-intersection; 7-9 or missing = unknown |
| Lighting | 1,591 | 1,764 | Code 1 = daylight; 2 = dusk/dawn; 3-6 = dark; 9 or missing = unknown |

Missing counts overlap and must not be added together. Only these five features determine eligibility. Missing age, vehicle era or weight does not exclude a record from clustering. Sex, KSI and other occupant characteristics are excluded from fitting and choosing the cluster count. Single/multi-vehicle status is reported in the profiles but excluded from fitting because it largely repeats the crash-type distinction.

The script compares k = 1-8 on the same seeded random sample of 10,000 vehicles, using 10 starts per k (one for the k = 1 baseline). It selects the largest normalised elbow distance and refits the selected k on all 153,177 eligible vehicles with five starts, including the best sample modes as one starting point. Equal-weight category mismatches are the objective; silhouettes on a 2,000-vehicle subsample and cluster sizes are supplementary diagnostics. The elbow is a heuristic rather than a uniquely optimal solution. The model settings, seeds, input checksum and package versions are saved with the model.

This run selected **k = 2** (sample mean silhouette 0.364). The two clusters separate intersection and non-intersection contexts exactly. They are broad contexts rather than tightly matched crash scenarios; both still contain different speed zones, impact points and crash types.

| Cluster | Vehicles | Female occupants | Male occupants | Female KSI | Male KSI |
|---|---:|---:|---:|---:|---:|
| C1: intersection | 83,392 | 50,943 | 48,801 | 16.76% | 11.50% |
| C2: non-intersection | 69,785 | 39,455 | 43,332 | 21.38% | 18.96% |

Profiles describe vehicles; KSI comparisons use occupant counts. Full category proportions accompany the modal scenario names, and coverage/KSI rates are also reported for unassigned occupants by sex. Gaps and ratios are calculated before rounding. These are descriptive within-scenario comparisons, not evidence that all confounding or dependence between people in the same crash has been removed; adjusted inference belongs in Step 7.

## Crash scenario preparation (02/11/2026)

`R/05_crash_scenarios.R` starts from all 194,061 clean occupants and adds the supplied DCA descriptions from the raw accident table. Every occupant matched an accident, and the raw and clean DCA codes agree. An exact equality check confirms that original rows, order, values and column types are preserved. No occupants are removed, and the existing impact variable remains separate.

The inventory contains 81 raw code/description pairs, with study occupant, vehicle and crash counts in `outputs/tables/06_dca_code_inventory.csv`. There are 193,998 occupants with known manoeuvre descriptions and 63 with unknown manoeuvre code 199, retained explicitly. The enriched data is saved as `data/processed/occupants_scenario_ready.rds`. Crash-configuration grouping is pending validation against the official DCA definitions; no scenario comparisons or new models have been run at this stage.

## Defined crash scenarios completed (03/11/2026)

Extended `R/05_crash_scenarios.R` using the official DCA chart linked in the codebook. The project groups were defined from manoeuvre descriptions before calculating their KSI comparisons. Exact code whitelists, including exclusions from strict rear-end/head-on/run-off-road definitions, are saved in `06_dca_mapping.csv`; the audit adds original descriptions and counts. Configuration and impact are analysed separately.

| Configuration | Occupants |
|---|---:|
| Rear-end | 51,054 |
| Head-on (not overtaking) | 9,512 |
| Adjacent-direction intersection | 41,714 |
| Opposing-direction turning | 24,200 |
| Run-off-road | 22,246 |
| Loss of control on carriageway | 839 |
| Other known configurations | 44,433 |
| Unknown DCA | 63 |
| Total | 194,061 |

No rows were removed and no observed DCA codes were left unmapped. Original values, types and row order are unchanged. All 4,753 missing/not-applicable impact records remain missing in the enriched dataset and appear explicitly in the impact summaries. `occupants_scenarios.csv/.rds` contains the full dataset with the new factor, ready for modelling; the intermediate `occupants_scenario_ready.rds` is retained.

Both comparisons save sex-specific occupant denominators, KSI counts, rates, percentage-point gaps and rate ratios without intermediate rounding. Unknown groups remain visible, with sample sizes on charts. Independent checks reproduced all counts and rates and verified easily confused boundary codes. Female KSI rates exceed male rates in most configurations, with a small gap for run-off-road and a reversed gap in the smaller loss-of-control-on-carriageway group. These descriptive differences do not establish adjusted effects or statistical significance. Adjusted modelling remains the next stage.

## Step 7 baseline logistic regression (03/11/2026)

`R/06_model.R` models KSI using sex, age band, seat, speed band, crash configuration, impact, vehicle count (1/2/3+), manufacturing year and tare weight. Crash calendar year is also included as a categorical control for changes during the study period. Manufacturing year is centred at 2010 and scaled per decade; tare is centred at 1,500 kg and scaled per 500 kg. These continuous effects are linear on the log-odds scale in the baseline; no interactions are fitted yet.

The input has 194,061 occupants. Complete-case selection retains 175,453 occupants from 100,085 crashes, with 29,630 KSI cases; 18,608 occupants are excluded from this fit only. Existing missing values remain missing, including under-16/unknown age bands. Unknown DCA is treated as missing for this model. Two manufacturing years later than their crash year are additionally set to missing locally. Counts of missing values overlap; the saved sequential filter table gives additive exclusions:

| Requirement | Removed at this stage | Remaining |
|---|---:|---:|
| Age band | 4,093 | 189,968 |
| Speed band | 5,415 | 184,553 |
| Known crash configuration | 55 | 184,498 |
| Impact | 4,411 | 180,087 |
| Valid manufacturing year | 2,380 | 177,707 |
| Tare weight | 2,254 | 175,453 |

Sex, outcome, seat, vehicle count and crash year introduce no further exclusions. Source data is unchanged. The coverage table reports excluded and included KSI rates by sex so that complete-case selection is visible.

The fit converged in five iterations with 34 identifiable coefficients. Confidence intervals use `sandwich::vcovCL`, clustering on ACCIDENT_NO with HC1 and the cluster-count adjustment; [method documentation](https://sandwich.r-forge.r-project.org/reference/vcovCL.html). An independent calculation from crash-summed score vectors reproduced this covariance within numerical tolerance (maximum absolute difference below 2e-9). The adjusted female-versus-male odds ratio is approximately 1.41 (95% CI 1.37-1.45). This describes higher odds, not a 41-percentage-point increase or a 41% increase in probability.

Standardisation over the same complete-case covariate distribution gives approximately 14.8% KSI for males and 19.0% for females. Confidence intervals use the clustered covariance and a delta method with the covariate distribution treated as fixed. These are model-based associations, not causal effects or held-out predictions. Use `07_baseline_odds_ratios.csv` for inference; the separate base-R summary is explicitly labelled as using ordinary model-based standard errors. Interaction models, functional-form checks, sensitivity analysis, random forest and crash-separated predictive evaluation remain outstanding.

## Sex by vehicle-year interaction (03/11/2026)

`R/07_vehicle_year_interaction.R` adds one sex-by-manufacturing-year term to the baseline formula. It uses the identical 175,453 occupants from 100,085 crashes, without additional exclusions or changes to other controls. Year remains centred at 2010 and scaled by decade. The main sex coefficient now applies at manufacture year 2010; the interaction describes change in the female/male odds ratio per decade. The one-degree-of-freedom Wald test uses crash-cluster-robust HC1 covariance, rather than an ordinary likelihood-ratio test assuming independent occupants.

The female/male odds ratio multiplies by approximately 1.093 per ten newer manufacturing years (95% CI 1.055-1.133; p approximately 1.15e-6). Estimated sex odds ratios rise from 1.27 (95% CI 1.20-1.33) for 1995 vehicles to 1.58 (1.50-1.67) for 2020 vehicles. This is evidence of an increasing relative odds gap under the fitted linear interaction model.

For standardised probabilities, all six plotted years (1995, 2000, 2005, 2010, 2015, 2020) and both sexes use the same 62,244 reference occupants in 2020-2024 crashes. This prevents assigning a newer vehicle to an earlier crash date and keeps the reference covariate distribution constant. The model itself is fitted to the full baseline cohort. These curves should not be directly compared with the baseline's probabilities averaged over a different reference population.

| Manufacture year | Male adjusted KSI | Female adjusted KSI | Gap (percentage points) |
|---|---:|---:|---:|
| 1995 | 16.37% | 19.44% | 3.07 |
| 2000 | 15.35% | 18.88% | 3.53 |
| 2005 | 14.38% | 18.32% | 3.95 |
| 2010 | 13.45% | 17.78% | 4.33 |
| 2015 | 12.58% | 17.25% | 4.68 |
| 2020 | 11.75% | 16.73% | 4.99 |

The 1995-to-2020 probability-gap increase is 1.92 percentage points (95% CI 0.83-3.00; p approximately 0.000526), calculated using the joint covariance of both endpoint contrasts. Pointwise probability intervals use a delta method with the empirical reference distribution fixed; shaded bands are not simultaneous confidence bands. Probability falls for both sexes, more steeply for males in this model.

Validation confirmed identical cohort keys, full rank and convergence, independently reproduced the clustered covariance, and checked every plotted probability and odds ratio against model predictions. Both charts were visually inspected. These are adjusted associations: manufacturing year remains a proxy that cannot isolate vehicle design from vehicle age or other unmeasured differences. Nonlinear year sensitivity, other planned interactions, missing-data sensitivity and predictive evaluation remain outstanding.

## Sex by weight interaction, retaining the year interaction (03/11/2026)

`R/08_weight_interaction.R` adds sex by tare weight to the year-interaction model, retaining all controls and the identical 175,453 occupants from 100,085 crashes. There are no further exclusions. Weight is linear on the log-odds scale, centred at 1,500 kg and scaled per 500 kg. The fit converged with 36 identifiable coefficients; crash-cluster-robust HC1 covariance was independently verified.

The sex odds-ratio multiplier per 500 kg is 0.983 (95% CI approximately 0.941-1.027; p = 0.437). There is no clear evidence of weight modifying the female/male odds ratio in this model; this does not prove the effect is absent. The retained sex-by-year interaction remains positive (approximately 1.097 per decade; p approximately 8.74e-7). Conditional sex ORs in the weight table explicitly use manufacture year 2010: about 1.47 at 1,000 kg and 1.42 at 2,000 kg.

Standardised probabilities use the full baseline cohort's observed manufacturing years and controls for both sexes at each weight, rather than the recent-crash reference population used for the preceding year chart. At 1,000 kg, male/female KSI probabilities are 18.21%/23.39%; at 2,000 kg they are 11.27%/14.52%. The absolute gap changes from 5.18 to 3.25 percentage points, a change of -1.93 points (95% CI approximately -2.98 to -0.88). This absolute-scale change is compatible with the nonsignificant odds-scale interaction: probability differences can vary with baseline risk even when an odds ratio is constant. The chart explicitly explains this distinction.

Outputs include coefficients, both interaction tests, weight-support counts, conditional ORs, standardised rates and gaps, endpoint gap-change uncertainty, diagnostics, one chart and `weight_interaction_model.rds`. Independent predictions reproduced all reported rates and ORs, and cohort identity was checked. These are adjusted associations under linear year/weight assumptions, not causal estimates. Seating-position/scenario interactions, nonlinear checks, missing-data sensitivity and predictive evaluation remain outstanding.

## Sex by seating position interaction (03/11/2026)

`R/09_seat_interaction.R` adds sex by seat, retaining both year and weight interactions and all other controls. The same 175,453 occupants from 100,085 crashes are used, with no new exclusions. Observed counts are 78,459 male/70,269 female drivers and 9,871 male/16,854 female front passengers.

The passenger-to-driver ratio of female/male odds ratios is approximately 1.21 (95% CI 1.12-1.31; crash-robust Wald p approximately 3.02e-6). At manufacture year 2010 and tare weight 1,500 kg, female/male odds ratios are 1.40 for drivers (95% CI 1.36-1.45) and 1.69 for front passengers (1.57-1.82). These conditional reference values are explicit because the year/weight interactions remain in the model.

Standardisation over the same full-cohort covariate distribution for all four combinations gives approximately 14.9% male versus 18.7% female KSI for drivers and 13.9% versus 20.0% for front passengers. The female-male gaps are 3.85 percentage points (95% CI 3.48-4.22) and 6.17 points (5.32-7.02), respectively. Their difference is 2.32 points (95% CI 1.38-3.26), using the joint covariance of the contrasts. Intervals use crash-cluster-robust HC1 covariance; probability intervals use a delta method with the empirical covariate distribution fixed.

The model converged with full rank. Independent checks verified cohort identity, clustered covariance, all four probabilities and both conditional ORs; the chart was visually checked. This supports a larger adjusted sex gap among front passengers under the model assumptions, not a causal effect of moving seats. Saved outputs include support counts, coefficients, interaction test, ORs, standardised rates/gaps, gap contrast, diagnostics, one chart and `seat_interaction_model.rds`. Scenario interactions, nonlinear sensitivity, missing-data checks and predictive evaluation remain outstanding.

## Sex by crash configuration interaction (03/11/2026)

`R/10_crash_configuration_interaction.R` adds six sex-by-configuration terms while retaining the year, weight and seating interactions and all prior controls. No new exclusions: 175,453 occupants from 100,085 crashes. The 43-parameter model converged in five iterations with full rank. The joint crash-robust HC1 Wald test gives chi-square 257.87 on 6 degrees of freedom (p approximately 8.53e-53), indicating that the conditional female/male odds ratio is not constant across configurations.

| Configuration | Female/male adjusted OR | Pointwise 95% CI |
|---|---:|---|
| Rear-end | 1.70 | 1.60-1.82 |
| Head-on (not overtaking) | 1.38 | 1.26-1.52 |
| Adjacent-direction intersection | 1.53 | 1.44-1.62 |
| Opposing-direction turning | 1.77 | 1.63-1.91 |
| Run-off-road | 0.93 | 0.87-1.00 |
| Loss of control on carriageway | 0.64 | 0.41-1.02 |
| Other known configurations | 1.36 | 1.27-1.44 |

These ORs refer to drivers in vehicles manufactured in 2010 with tare weight 1,500 kg, because sex interactions with those variables remain in the model. The ratio between scenario-specific sex ORs is shared across those controls under the assumed model (no three-way interactions). The joint test does not imply that every pair of configurations differs.

Holm-adjusted p-values are supplied for the seven tests of a sex OR equal to one. Run-off-road has an unadjusted p of approximately 0.040 but adjusted p of 0.081; loss of control also has adjusted p approximately 0.081. These should not be described as established lower female odds after multiplicity adjustment. The loss-of-control group is smaller (641 occupants, 95 KSI cases). The Other category remains heterogeneous. Confidence intervals in the chart are pointwise, not multiplicity-adjusted.

For probability summaries, each configuration's observed covariate distribution is used for both sexes within that configuration. This avoids imposing unrealistic combinations of scenario and vehicle count. Different configurations therefore have different reference populations: absolute probabilities/gaps across configurations are not effects of changing crash type. Standardised female-minus-male gaps are 4.58 points for rear-end, 6.97 head-on, 5.54 adjacent intersection, 6.85 opposing turning, -1.29 run-off-road, -4.91 loss of control and 3.32 Other. Both negative-gap pointwise intervals include zero. Delta-method uncertainty treats reference covariates as fixed.

Independent checks reproduced the covariance, joint Wald statistic, all 14 standardised probabilities, seven conditional ORs and Holm adjustment; identical cohort keys and chart readability were verified. Model and tables are saved with the `07_configuration_interaction_` prefix, with `configuration_interaction_model.rds` under processed data. All four planned interaction topics have now been fitted. Nonlinear robustness, missing-data sensitivity and crash-separated predictive evaluation remain outstanding.

## Vehicle-year functional-form robustness (03/11/2026)

`R/11_year_robustness.R` compares the current fully adjusted linear-year model with a four-degree-of-freedom natural cubic spline for year, interacted with sex. Both use the identical 175,453 occupants and retain sex interactions with weight, seating and crash configuration. The spline's outcome-independent interior knots are manufacturing years 2003, 2008 and 2013 (cohort quartiles); boundaries are 1961 and 2024. It is reparameterised into a linear term and three curvature terms per sex, allowing explicit nested Wald tests. This spans the same model as `splines::ns`; [R spline documentation](https://stat.ethz.ch/R-manual/R-devel/library/splines/help/ns.html).

Crash-robust HC1 tests give p = 0.0897 for any curvature (6 df), p = 0.293 for curvature in the sex log-odds gap (3 df), and p = 0.0270 for any sex-by-year association in the flexible model (4 df). The latter tests variation anywhere across years, not a monotonic trend or a particular endpoint change. There is no clear evidence at the 5% level that the curved model is needed; it is a plausible sensitivity specification, not a proven superior model.

Both models' probability curves use exactly the same 62,244 reference occupants in 2020-2024 crashes, retaining valid chronology for all plotted manufacturing years (1995-2020).

| Model | 1995 female-male gap | 2020 female-male gap | Change, with pointwise 95% CI |
|---|---:|---:|---|
| Fully adjusted linear year | 3.80 points | 4.50 points | +0.70 points (-0.43 to 1.83), p = 0.225 |
| Fully adjusted curved year | 4.11 points | 4.10 points | -0.01 points (-1.45 to 1.44), p = 0.990 |

On the relative-odds scale, the ratio of 2020 to 1995 sex ORs is 1.145 (95% CI 1.043-1.257, p = 0.00456) for the linear model and 1.073 (0.949-1.214, p = 0.261) for the curved model. These endpoint tests use the joint covariance, not overlap of separate confidence intervals.

**Updated interpretation:** the average adjusted female-male probability gap remains positive in this reference population, but a steady widening with newer vehicle years is not robustly established. The curved model's interval allows both widening and narrowing, so this is not proof of no change. Earlier results used fewer sex interactions; adding seating/configuration interactions already weakens the absolute-gap trend before allowing curvature. The old increase of 1.92 points and the new linear increase of 0.70 points are therefore not a pure functional-form comparison. Manufacturing year remains a proxy, not an identified causal vehicle-design effect.

Saved outputs include knot locations, curvature tests, annual standardised probabilities/gaps, endpoint changes, diagnostics, a comparison chart and `year_robustness_model.rds`. Validation checks compare the reparameterised model directly with a conventional `splines::ns` fit, verify the cohort and robust covariance, and reproduce probabilities independently. This is a vehicle-year functional-form check; missing-data sensitivity, alternative spline choices and crash-separated predictive evaluation are not completed by it.

## Crash-grouped predictive evaluation (03/11/2026)

`R/12_predictive_evaluation.R` uses the same 175,453 complete-case occupants from 100,085 crashes, with no further exclusions. The outcome is killed or seriously injured (KSI), not fatality alone. Inputs are sex, age band, seat, speed band, crash configuration, impact, vehicle-count group, manufacturing year, tare weight and crash year. IDs are used only for grouping and audit; no injury-severity-derived features are predictors.

With seed 20261103, crashes were stratified by any KSI among eligible cohort members and randomly split approximately 80/20. Training contains 140,148 occupants from 80,068 crashes; test contains 35,305 occupants from 20,017 crashes, including 5,962 KSI cases (16.89%). Every crash is wholly assigned to one partition. Within training, five folds were stratified and assigned by crash in the same way. Saved assignments in `data/processed/predictive_split.rds` are reused on reruns, with source-data and cohort-key checks. All reported performance metrics weight occupants equally.

Both model families were fitted from scratch within each fold. Logistic candidates retain the sex-by-year, weight, seat and configuration interactions, using either linear year or a four-df natural spline. Spline knots/boundaries are learned using only the relevant fold's training rows, then reused to predict its assessment rows. The random forest uses the same ten input variables, with interactions learned by its trees. Its small prespecified grid tests mtry 3 or 6, keeping 300 trees, minimum split-node size 50 and minimum terminal-node size 10. Probability forests and factor handling follow the [ranger documentation](https://imbs-hl.github.io/ranger/reference/ranger.html); unordered factor ordering is learned inside each fit. No class weighting or resampling to balance outcomes was applied.

The lowest pooled training out-of-fold log loss selects one candidate per family. This is a modest tuning exercise, not an exhaustive search. A separate probability threshold is selected per family by maximising training out-of-fold sensitivity + specificity - 1 (Youden's J). This gives sensitivity and specificity equal weight; it is an illustrative operating point, not a threshold optimised for a real-world intervention's costs. A fixed 0.5 threshold is also reported. All these choices were fixed before test evaluation. Selection CV scores are tuning results; the final test set assesses the selected models.

Each selected model is refitted on all training crashes and evaluated on the same test occupants. Metrics are ROC AUC, average precision (stepwise precision-recall summary), Brier score and log loss, plus threshold-specific confusion counts, sensitivity, specificity, precision, F1 and accuracy. A constant training-prevalence predictor provides a benchmark. Calibration-in-the-large (slope fixed to 1), joint calibration intercept/slope and ten-bin calibration curves are descriptive test measurements; they are not used to recalibrate the models. Sex-specific test metrics describe predictive performance and do not replace the adjusted sex-association analyses. Results are point estimates without confidence intervals or significance tests.

Ranger permutation importance is saved for exploratory interpretation. Its internal out-of-bag resampling is by occupant, so it is not a crash-independent validation estimate and must not replace the held-out/CV results. Importance does not measure causal effects or direction.

Earlier full-cohort exploration and inference informed the cohort and candidate specifications. This is therefore **retrospective internal validation**, despite proper crash separation during the new model fitting and tuning. It does not establish performance on untouched external data, future years, occupants excluded for missing data, or the general population outside recorded crashes. Crash year is among the predictors, and a random crash split is not a temporal validation. Predictive performance also does not establish that vehicle design caused changes in the sex gap. Missing-data sensitivity remains outstanding.

Training CV selected the linear logistic model (log loss 0.401169 versus 0.401212 for the curved version) and mtry 3 for the forest (0.398842 versus 0.401833 for mtry 6). The linear/curved difference is extremely small. Selecting the linear version for prediction does not overturn the earlier finding that a widening sex gap is sensitive to the year specification.

| Model | Test ROC AUC | Average precision | Brier score | Log loss |
|---|---:|---:|---:|---:|
| Logistic regression | 0.7387 | 0.3682 | 0.1248 | 0.4023 |
| Random forest | 0.7426 | 0.3804 | 0.1236 | 0.3989 |
| Constant training prevalence | 0.5000 | 0.1689 | 0.1404 | 0.4541 |

Higher AUC/average precision and lower Brier/log loss are better. Random forest has a small advantage on this test set; no claim of statistical significance is made. Both discriminate substantially better than the constant benchmark. Calibration-in-the-large is -0.0030 for logistic and -0.0074 for forest (ideal 0); joint calibration slopes are 0.9801 and 0.9596 respectively (ideal 1). Binned plots broadly follow the diagonal, with some overprediction in the highest-risk bin.

At threshold 0.5, test accuracy is 83.2% for logistic and 83.4% for forest, but KSI sensitivity is only about 10.6% for both. Always predicting no KSI already yields 83.1% accuracy, illustrating why accuracy alone is misleading here. At training-selected thresholds approximately 0.162 and 0.176, logistic detects 66.3% of KSI cases with 69.4% specificity and 30.6% precision; forest detects 65.3% with 71.3% specificity and 31.6% precision. These operating points trade more KSI detection for more false positives, and are not a matched-sensitivity comparison.

Test AUC is higher among males than females for both models (logistic 0.7596 versus 0.7117; forest 0.7658 versus 0.7122). This describes discrimination within the test subgroups, not proof of a biological explanation or a formal fairness conclusion. Their different baseline KSI rates also affect precision and Brier scores.

The script ran successfully. Independent checks confirmed disjoint crash IDs in train/test and each CV fold, aligned cohort keys, training sample sizes, ROC AUC against `pROC`, losses, confusion counts, and predictions reproduced from saved models. Both charts were visually inspected. Outputs use the `07_predictive_` prefix; fitted training models, held-out predictions and provenance are saved in `data/processed/predictive_models.rds`, with out-of-fold predictions and selection records in `predictive_cv.rds`. The full-cohort inferential models were not replaced.

### Confusion-matrix displays (03/11/2026)

`R/13_confusion_matrices.R` converts the saved test predictions into two side-by-side model charts: one using training-selected thresholds and one using 0.5. Actual outcomes are rows; predicted outcomes are columns. Cells show counts and percentages within the actual outcome class. Non-KSI includes occupants who were neither killed nor seriously injured; it does not mean uninjured. Counts are checked against the existing confusion metrics. No fitting, threshold selection or new test-set evaluation choices were introduced. Outputs are `07_predictive_confusion_selected.png`, `07_predictive_confusion_fixed_05.png` and `07_predictive_confusion_matrices.csv`.

### Recall-focused screening scenario (03/11/2026)

Following discussion of missed KSI cases, `R/14_recall_threshold.R` uses an illustrative 80% recall target for screening. This is a project decision favouring fewer missed KSI cases, not an authority-endorsed threshold or an established cost-optimal policy. With no specified investigation capacity or false-positive cost, 80% is a transparent starting scenario rather than a proven operational optimum.

The models are unchanged. For each model, the highest probability cutoff reaching at least 80% recall in the saved pooled training out-of-fold predictions is selected. This minimises the false-positive count among cutoffs satisfying that training target. Tied scores are included together, and full-precision thresholds are retained. Logistic regression uses 0.1191636918133009; random forest uses 0.1164066362899325. Each detects 18,935 of 23,668 training KSI cases (80.0025%). No test labels are used in cutoff selection, and cutoffs are not adjusted to force the test results to reach 80%.

| Test outcome | Logistic regression | Random forest |
|---|---:|---:|
| True positives | 4,743 | 4,747 |
| False negatives | 1,219 | 1,215 |
| False positives | 13,832 | 13,806 |
| True negatives | 15,511 | 15,537 |
| Recall | 79.6% | 79.6% |
| Specificity | 52.9% | 52.9% |
| Precision | 25.5% | 25.6% |

Relative to the earlier training-Youden cutoffs, logistic identifies 788 additional KSI cases with 4,842 additional false positives; forest identifies 853 additional KSI cases with 5,376 additional false positives. Both now flag about 52.6% of test occupants. Roughly one in five actual KSI cases is still missed, while roughly three in four flagged occupants are non-KSI. This is a change in the operating point, not improved underlying discrimination: ROC AUC, average precision, Brier score and log loss remain unchanged.

The same cutoff per model is applied to both sexes. Logistic recall is 74.7% for males and 83.3% for females; forest recall is 76.6% and 82.0%, respectively. These subgroup results are descriptive, and the overall 80% training target does not guarantee equal detection across groups or populations. Full sex-specific counts and metrics are saved.

The target was adopted after inspecting earlier test performance, so the new test results are a retrospective follow-up, not a fresh confirmatory validation. Operational use would require independent validation, a defined intervention, capacity/cost assessment and subgroup review. The outcome is severity conditional on recorded crashes, not crash occurrence or injuries prevented by an intervention.

Saved outputs: `07_recall_target_training.csv`, `07_recall_target_test_comparison.csv`, `07_recall_target_test_by_sex.csv`, `07_recall_target_confusion_matrices.csv`, `07_recall_target_confusion.png` and `data/processed/predictive_screening_thresholds.rds`. The last file stores the new decision rules, source hashes and results; original fitted models and evaluation files remain intact for comparison. Validation independently reproduced cutoffs with empirical quantiles, checked confusion counts/recall against direct tables and verified source hashes. The chart was visually inspected.

### Balanced precision/recall scenario (03/11/2026)

The requested additional balanced version is implemented in `R/15_balanced_threshold.R`. Here, balanced means maximising F1, the harmonic mean of KSI precision and recall. It does not mean equal sensitivity/specificity (the earlier Youden objective maximises their sum), identical precision/recall, or equal real-world error costs. The models are unchanged. Every distinct pooled training out-of-fold probability is considered as a cutoff, with tied scores classified together; maximum F1 is selected, with exact ties favouring higher recall and then higher threshold. No test outcomes enter cutoff selection.

Selected cutoffs are 0.2022707716273104 for logistic and 0.2155250063389475 for forest; training F1 is approximately 0.428 and 0.435, respectively. Applied unchanged to the existing test set:

| Test outcome | Logistic regression | Random forest |
|---|---:|---:|
| True positives | 3,354 | 3,401 |
| False negatives | 2,608 | 2,561 |
| False positives | 6,215 | 6,281 |
| True negatives | 23,128 | 23,062 |
| Recall | 56.3% | 57.0% |
| Precision | 35.1% | 35.1% |
| Specificity | 78.8% | 78.6% |
| F1 | 0.432 | 0.435 |

Compared with the 80%-recall scenario, false positives fall by 7,617 for logistic and 7,525 for forest, while missed KSI cases increase by 1,389 and 1,346. About 27% of occupants are flagged, versus 53% previously. This is a precision/recall compromise, not a superior screening rule when preventing missed KSI is the overriding objective. Probability-based metrics remain unchanged. Because the existing test results have already informed discussion, this is another retrospective scenario; it is not fresh confirmation of an optimal operating policy.

Outputs use the `07_balanced_f1_` prefix and include training scores, test comparisons with the previous two objectives, confusion counts/chart and sex-specific metrics. `data/processed/predictive_balanced_thresholds.rds` preserves full-precision cutoffs, rules, source hashes and results, without replacing the recall-focused thresholds. Independent verification used a sorted-vector exhaustive F1 calculation including ties, reproduced confusion counts and checked source hashes. The chart was visually inspected.

## Final sex-by-impact analysis and consolidated research results (03/11/2026)

At the user's request, exclusion/missing-data sensitivity is deferred. `R/16_impact_interaction.R` adds sex by initial impact location (Front, Side, Rear, Other) to the configuration-interaction model, retaining all previous controls and sex interactions. The same 175,453 occupants, 100,085 crashes and 29,630 KSI outcomes remain. The final primary model has 46 coefficients and linear manufacturing year; a matched four-df natural-spline sensitivity model has 52 coefficients. Both converged with full rank. The primary specification is retained for continuity, not chosen by searching for significant results.

The sex-by-impact joint crash-robust HC1 Wald test is chi-square 16.014 on 3 df, p = 0.001126. Holm adjustment across the five interaction topics gives p = 0.003379. The curved-year model gives a similar impact result (p = 0.001200; adjusted p = 0.003599). This supports variation in the conditional female/male odds ratio by impact, while retaining DCA crash configuration as a separate variable. It does not establish differences between every pair of impact groups.

`R/17_final_results.R` supplies one consistent primary-model table spanning all research topics, with probabilities, female-minus-male percentage-point gaps and marginal sex odds ratios from standardised mean probabilities. These marginal ORs must not be confused with single conditional regression coefficients. Pointwise 95% intervals use the paired prediction gradients and crash-robust covariance, treating reference covariates as fixed. Raw gap p-values and Holm adjustments within each section are in the CSV; the five conditional interaction tests have their own Holm correction.

| Initial impact | Standardised female-minus-male KSI gap (percentage points) | Pointwise 95% CI |
|---|---:|---|
| Front | 4.69 | 4.25 to 5.13 |
| Side | 3.41 | 2.42 to 4.41 |
| Rear | 3.60 | 3.06 to 4.15 |
| Other | 0.75 | -2.13 to 3.63 |

Each impact/configuration row uses that group's observed covariates for both sexes, retaining plausible combinations of the other crash variables. These reference populations differ across rows, so the numerical probability-gap differences across impact groups are not pure effects of changing impact. The within-model joint interaction tests address heterogeneity after adjustment. Counts by impact, configuration and sex are supplied to expose sparse combinations.

The final overall standardised probabilities are 14.65% male and 18.87% female: gap 4.22 points (95% CI 3.89 to 4.56), marginal OR 1.36 (1.32 to 1.39). Seating comparisons use the same full reference cohort with seat set to Driver or Front passenger: gaps 3.81 and 6.40 points, a difference of 2.60 (1.66 to 3.53). The weight odds interaction remains unsupported (p = 0.837), while the absolute gap decreases from 5.09 points at 1,000 kg to 3.32 at 2,000 kg; the gap change is -1.76 (-2.81 to -0.72). Relative-odds and absolute-probability scales answer different questions. The configuration interaction remains strong (p = 1.46e-51); run-off-road and loss-of-control gap intervals include zero and should not be reported as established reversals.

The refreshed year comparison retains the new impact interaction in both models and standardises to the same 62,244 occupants in 2020-2024 crashes. The 2020-minus-1995 absolute sex-gap change is +0.71 points (-0.42 to 1.84, p = 0.216) for the primary model and +0.02 (-1.42 to 1.47, p = 0.975) for the curved model. A steady widening or narrowing remains unestablished. The primary conditional year interaction has p = 0.00416 (Holm p = 0.00831); the curved joint sex-by-year test has p = 0.0263 (Holm p = 0.0526), which tests variation anywhere rather than a monotonic endpoint trend. Any year curvature has p = 0.0937. Manufacturing year remains an observational proxy for design era.

Use `report/final_research_results.md` and `outputs/tables/07_final_research_results.csv` for consolidated reporting, rather than mixing earlier sequential-model estimates. The separate curved results, gap changes, all interaction tests, coefficients, diagnostics and impact support files use `07_final_` or `07_impact_` prefixes. Model objects, covariance matrices, cohort keys, spline metadata and provenance are in `final_association_models.rds`; standardised outputs are also saved as `final_research_results.rds`. The impact chart is `07_final_impact_probability_gaps.png`.

Verification confirmed identical cohort values/keys, independently reconstructed both clustered covariance matrices and impact Wald tests, checked the spline model against conventional `splines::ns`, reproduced all 84 standardised sex-specific probabilities and 42 gaps/ORs with independent prediction calls, and verified impact confidence intervals. The chart was visually inspected. Scripts 12-15 and their predictions remain unchanged: their performance results do not validate the newly extended association model. No exclusion-sensitivity analysis was performed.
