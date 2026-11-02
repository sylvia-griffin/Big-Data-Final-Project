-- =====================================================================
-- 01_create_tables.hql
-- Creates the project database and external tables over the raw CSVs.
-- Run after uploading the CSVs to /crashdata/<table>/ (see RUN_STEPS.md).
-- Codes are kept as STRING so leading zeros (e.g. '01', '060') survive.
-- Empty values in INT columns load as NULL.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS crash;
USE crash;

-- ---------- person ----------
DROP TABLE IF EXISTS person_raw;
CREATE EXTERNAL TABLE person_raw (
  accident_no         STRING,
  person_id           STRING,
  vehicle_id          STRING,
  sex                 STRING,
  age_group           STRING,
  inj_level           STRING,
  inj_level_desc      STRING,
  seating_position    STRING,
  helmet_belt_worn    STRING,
  road_user_type      STRING,
  road_user_type_desc STRING,
  licence_state       STRING,
  taken_hospital      STRING,
  ejected_code        STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/crashdata/person/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- ---------- vehicle ----------
DROP TABLE IF EXISTS vehicle_raw;
CREATE EXTERNAL TABLE vehicle_raw (
  accident_no            STRING,
  vehicle_id             STRING,
  vehicle_year_manuf     INT,
  vehicle_dca_code       STRING,
  initial_direction      STRING,
  road_surface_type      STRING,
  road_surface_type_desc STRING,
  reg_state              STRING,
  vehicle_body_style     STRING,
  vehicle_make           STRING,
  vehicle_model          STRING,
  vehicle_power          INT,
  vehicle_type           STRING,
  vehicle_type_desc      STRING,
  vehicle_weight         INT,
  construction_type      STRING,
  fuel_type              STRING,
  no_of_wheels           INT,
  no_of_cylinders        INT,
  seating_capacity       INT,
  tare_weight            INT,
  total_no_occupants     INT,
  carry_capacity         INT,
  cubic_capacity         INT,
  final_direction        STRING,
  driver_intent          STRING,
  vehicle_movement       STRING,
  trailer_type           STRING,
  vehicle_colour_1       STRING,
  vehicle_colour_2       STRING,
  caught_fire            STRING,
  initial_impact         STRING,
  lamps                  STRING,
  level_of_damage        STRING,
  towed_away_flag        STRING,
  traffic_control        STRING,
  traffic_control_desc   STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/crashdata/vehicle/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- ---------- accident ----------
DROP TABLE IF EXISTS accident_raw;
CREATE EXTERNAL TABLE accident_raw (
  accident_no         STRING,
  accident_date       STRING,
  accident_time       STRING,
  accident_type       STRING,
  accident_type_desc  STRING,
  day_of_week         STRING,
  day_week_desc       STRING,
  dca_code            STRING,
  dca_desc            STRING,
  light_condition     STRING,
  node_id             STRING,
  no_of_vehicles      INT,
  no_persons_killed   INT,
  no_persons_inj_2    INT,
  no_persons_inj_3    INT,
  no_persons_not_inj  INT,
  no_persons          INT,
  police_attend       STRING,
  road_geometry       STRING,
  road_geometry_desc  STRING,
  severity            STRING,
  speed_zone          STRING,
  rma                 STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/crashdata/accident/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- ---------- load checks (screenshot these) ----------
-- Expected: person 425352, vehicle 331992, accident 182039
SELECT 'person'   AS tbl, COUNT(*) AS n FROM person_raw
UNION ALL
SELECT 'vehicle'  AS tbl, COUNT(*) AS n FROM vehicle_raw
UNION ALL
SELECT 'accident' AS tbl, COUNT(*) AS n FROM accident_raw;

-- Quick preview of each table
SELECT * FROM person_raw   LIMIT 5;
SELECT * FROM vehicle_raw  LIMIT 5;
SELECT * FROM accident_raw LIMIT 5;
