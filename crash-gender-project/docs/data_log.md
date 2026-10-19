# Data Log

Record every step that changes the data. This becomes the Data Preparation section of the report.

## Raw tables (as supplied)
Row counts exclude the header. Re-check these after loading into Hive; they should match.

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
| # | Date | Who | Step | Tool | Rows before | Rows after | Rows removed | Reason |
|---:|---|---|---|---|---:|---:|---:|---|
| 1 | | | Join person + vehicle + accident | Hive | 425,352 | | | |
| 2 | | | Keep drivers and left-front passengers only | Hive | | | | Research focus is front-seat occupants |
| 3 | | | Keep seatbelt worn only | Hive | | | | Removes effect of belt use on injury |
| 4 | | | Keep light passenger vehicles (car, station wagon, utility) | Hive | | | | |
| 5 | | | Keep sex = M or F (drop U / blank) | Hive | | | | |
| 6 | | | Handle missing or zero tare weight | R | | | | |
| 7 | | | Handle missing or invalid vehicle year | R | | | | |
| | | | | | | | | |

## Decisions and assumptions
Write down any judgement call and why you made it.

| Date | Decision | Reason | Agreed by |
|---|---|---|---|
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
