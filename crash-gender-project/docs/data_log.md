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
| Which HELMET_BELT_WORN code means "seatbelt worn"? | | Person data dictionary |
| Which INJ_LEVEL codes are fatal and serious? | | Person data dictionary |
| Are "not injured" people recorded for all crashes or only some? | | Data dictionary / exploration |
