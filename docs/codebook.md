# Codebook

Codes for the fields used in this project, taken from the official data dictionaries on the Victorian Department of Transport open data portal and checked against the actual values in the CSVs.

Sources:
- Person: https://opendata.transport.vic.gov.au/dataset/victoria-road-crash-data/resource/60c8fc0c-2806-40f3-bb33-5c52691120e8
- Vehicle: https://opendata.transport.vic.gov.au/dataset/victoria-road-crash-data/resource/6d0b21f7-583a-4991-a168-f15a70c13ec4
- Accident: https://opendata.transport.vic.gov.au/dataset/victoria-road-crash-data/resource/20772c1a-8b19-424a-a733-eb84f725f611

## Join keys
| Table | Primary key | Joins to |
|---|---|---|
| accident | ACCIDENT_NO | person, vehicle (ACCIDENT_NO) |
| vehicle | ACCIDENT_NO + VEHICLE_ID | person (ACCIDENT_NO + VEHICLE_ID) |
| person | ACCIDENT_NO + PERSON_ID | vehicle via VEHICLE_ID (blank for pedestrians) |

No duplicate keys were found in any of the three tables.

## Person table

**SEX**: M = Male, F = Female, U = Not known

**AGE_GROUP**: 0-4, 5-12, 13-15, 16-17, 18-21, 22-25, 26-29, 30-39, 40-49, 50-59, 60-64, 65-69, 70+, Unknown (text bands, not exact ages)

**INJ_LEVEL** (derived from police assessment and hospital status)
| Code | Meaning | Project use |
|---|---|---|
| 1 | Fatality | KSI = 1 |
| 2 | Serious injury | KSI = 1 |
| 3 | Other injury | KSI = 0 |
| 4 | Not injured | KSI = 0 |

**SEATING_POSITION**
| Code | Meaning | Project use |
|---|---|---|
| D | Driver or rider | Keep |
| LF | Left-front passenger | Keep |
| CF | Centre-front | Drop |
| LR, RR, CR, OR | Rear seats | Drop |
| PL, PS | Pillion / sidecar | Drop |
| NA, NK | Not applicable / not known | Drop |

**HELMET_BELT_WORN**
| Code | Meaning | Project use |
|---|---|---|
| 1 | Seatbelt worn | Keep (main analysis) |
| 2 | Seatbelt not worn | Drop |
| 3 / 4 | Child restraint worn / not worn | Drop |
| 5 | Seatbelt/restraint not fitted | Drop |
| 6 / 7 | Crash helmet worn / not worn | Drop |
| 8 | Not appropriate | Drop |
| 9 | Not known | Drop from main analysis, use in sensitivity check |

**ROAD_USER_TYPE**: 1 Pedestrian, 2 Driver, 3 Passenger, 4 Motorcyclist, 5 Pillion, 6 Bicyclist, 7 Other driver, 8 Other passenger, 9 Not known

## Vehicle table

**VEHICLE_TYPE** (light passenger vehicles in bold)
| Code | Meaning | Project use |
|---|---|---|
| **01** | Car | Keep |
| **02** | Station wagon (includes most SUVs) | Keep |
| **04** | Utility | Keep |
| 03 | Taxi | Drop (professional drivers, different exposure) |
| 05 | Panel van | Drop |
| 10, 11, 12 | Motorcycle, moped, scooter | Drop |
| 13 | Bicycle | Drop |
| 71, 72, 06, 07, 60-63 | Light commercial, trucks, prime movers | Drop, but use as "other vehicle" |
| 99 | Not known | Drop |

**VEHICLE_YEAR_MANUF**: year as yyyy. Watch for 0 (missing) and implausible values.

**TARE_WEIGHT**: unladen weight in kg, from registration (VRIS) match. Can be NULL or 0.

**INITIAL_IMPACT** (proposed grouping in brackets)
| Code | Meaning | Group |
|---|---|---|
| F | Front | Frontal |
| 1, 5 | Right / left front corner | Frontal |
| 2, 3 | Right side forwards / rearwards | Side (right) |
| 6, 7 | Left side forwards / rearwards | Side (left) |
| R, 4, 8 | Rear / right rear corner / left rear corner | Rear |
| T, U | Top/roof, undercarriage | Other (rollover etc.) |
| N | None | Other |
| 0, S, 9, blank | Towed unit, sidecar, not known | Unknown |

Side impact could be split into near side vs far side relative to the occupant (right side = driver's side in Australia). This is an option if time allows.

**LEVEL_OF_DAMAGE**: 1 Minor, 2 Moderate (driveable), 3 Moderate (towed), 4 Major (towed), 5 Extensive (unrepairable), 6 Nil, 9 Not known. Possible proxy for crash severity, but see caution in the data log.

## Accident table

**ACCIDENT_TYPE**: 1 Collision with vehicle, 2 Struck pedestrian, 3 Struck animal, 4 Collision with fixed object, 5 Collision with other object, 6 Vehicle overturned, 7 Fall from/in moving vehicle, 8 No collision and no object struck, 9 Other

**SEVERITY** (of the whole crash): 1 Fatal, 2 Serious injury, 3 Other injury, 4 Non-injury. Do not use as a predictor, because it is defined by the outcome.

**SPEED_ZONE**: 030, 040, 050, 060, 070, 075, 080, 090, 100, 110 (km/h). 777 = Other, 888 = Camping grounds / off road, 999 = Not known. Treat 777/888/999 as unknown.

**LIGHT_CONDITION**: 1 Day, 2 Dusk/dawn, 3 Dark street lights on, 4 Dark street lights off, 5 Dark no street lights, 6 Dark unknown lighting, 9 Unknown

**ROAD_GEOMETRY**: 1 Cross intersection, 2 T intersection, 3 Y intersection, 4 Multiple intersections, 5 Not at intersection, 6 Dead end, 7 Road closure, 8 Private property, 9 Unknown

**DCA_CODE**: crash configuration, distinct from the vehicle's initial impact point. Definitions checked on 03/11/2026 against the [official VicRoads DCA chart](https://opendata.transport.vic.gov.au/dataset/bb77800e-1857-4edc-bf9e-e188437a1c8e/resource/b658d974-4ff1-4de2-9c12-e47bb0fdbbac/download/dca_chart_and_sub_dca_codes.pdf). The following combinations are project-defined groups:

| Project configuration | DCA codes |
|---|---|
| Rear-end | 130, 154 |
| Head-on (not overtaking) | 120 |
| Adjacent-direction intersection | 110-119 |
| Opposing-direction turning | 121-125 |
| Run-off-road | 170-173, 175, 180-183 |
| Loss of control on carriageway | 174, 184 |
| Other known configurations | 100-109, 129, 131-137, 139, 140-149, 150-153, 159, 160-167, 169, 179, 189, 190-194, 198 |
| Unknown | 199 |

The executable whitelist in `R/05_crash_scenarios.R` is authoritative. `outputs/tables/06_dca_mapping_audit.csv` connects every observed code and supplied description to its group and counts. Missing or unfamiliar codes remain explicit categories.

Code 150 includes overtaking sideswipes in the chart, so the head-on analysis uses only 120. Codes 131/132 remain in Other rather than extending the strict rear-end definition. Run-off-road requires explicit departure: 151, 174/184 and nonspecific 179/189 are not included. The Other group is heterogeneous and should not be interpreted as one scenario. DCA describes the crash configuration; front/side/rear impact remains a separate vehicle-level variable.
