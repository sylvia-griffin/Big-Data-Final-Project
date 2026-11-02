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
