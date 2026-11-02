-- =====================================================================
-- 02_build_occupants.hql
-- Builds the occupant-level analysis table, one filter per step.
-- After each step a COUNT(*) is printed: copy these into docs/data_log.md
-- and screenshot the query + result.
-- =====================================================================

USE crash;

-- ---------------------------------------------------------------------
-- Step A: "other vehicle" features for each vehicle in a crash
-- For every vehicle, look at the OTHER vehicles in the same accident:
--   n_other_vehicles   number of other vehicles
--   other_max_tare     heaviest other vehicle (kg), 0 treated as missing
--   other_heavy_flag   1 if any other vehicle is a truck, bus or light commercial
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS vehicle_other;
CREATE TABLE vehicle_other STORED AS ORC AS
SELECT
  v1.accident_no,
  v1.vehicle_id,
  COUNT(v2.vehicle_id) AS n_other_vehicles,
  MAX(CASE WHEN v2.tare_weight > 0 THEN v2.tare_weight END) AS other_max_tare,
  MAX(CASE WHEN v2.vehicle_type IN ('06','07','08','09','60','61','62','63','71','72')
           THEN 1 ELSE 0 END) AS other_heavy_flag
FROM vehicle_raw v1
LEFT JOIN vehicle_raw v2
  ON  v1.accident_no = v2.accident_no
  AND v1.vehicle_id <> v2.vehicle_id
GROUP BY v1.accident_no, v1.vehicle_id;

SELECT COUNT(*) AS n_vehicle_other FROM vehicle_other;   -- expect 331992

-- ---------------------------------------------------------------------
-- Step 1: join person + vehicle + accident (+ other-vehicle features)
-- Inner join on vehicle drops people with no vehicle (mostly pedestrians).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS occ_s1_joined;
CREATE TABLE occ_s1_joined STORED AS ORC AS
SELECT
  -- person
  p.accident_no, p.person_id, p.vehicle_id,
  p.sex, p.age_group, p.inj_level, p.seating_position, p.helmet_belt_worn,
  p.road_user_type, p.taken_hospital, p.ejected_code,
  -- vehicle
  v.vehicle_year_manuf, v.vehicle_type, v.vehicle_body_style, v.vehicle_make,
  v.vehicle_model, v.tare_weight, v.total_no_occupants, v.initial_impact,
  v.level_of_damage, v.vehicle_movement,
  -- accident
  a.accident_date, CAST(SUBSTR(a.accident_date,1,4) AS INT) AS accident_year,
  a.accident_time, a.day_of_week, a.accident_type, a.dca_code,
  a.light_condition, a.no_of_vehicles, a.road_geometry, a.speed_zone,
  -- other vehicle
  o.n_other_vehicles, o.other_max_tare, o.other_heavy_flag,
  -- outcome: killed or seriously injured
  CASE WHEN p.inj_level IN ('1','2') THEN 1 ELSE 0 END AS ksi
FROM person_raw p
JOIN vehicle_raw   v ON p.accident_no = v.accident_no AND p.vehicle_id = v.vehicle_id
JOIN accident_raw  a ON p.accident_no = a.accident_no
JOIN vehicle_other o ON p.accident_no = o.accident_no AND p.vehicle_id = o.vehicle_id;

SELECT COUNT(*) AS n_step1 FROM occ_s1_joined;

-- ---------------------------------------------------------------------
-- Step 2: drivers and left-front passengers only
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS occ_s2_front;
CREATE TABLE occ_s2_front STORED AS ORC AS
SELECT * FROM occ_s1_joined
WHERE seating_position IN ('D','LF');

SELECT COUNT(*) AS n_step2 FROM occ_s2_front;

-- ---------------------------------------------------------------------
-- Step 3: light passenger vehicles (01 car, 02 station wagon, 04 utility)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS occ_s3_light;
CREATE TABLE occ_s3_light STORED AS ORC AS
SELECT * FROM occ_s2_front
WHERE vehicle_type IN ('01','02','04');

SELECT COUNT(*) AS n_step3 FROM occ_s3_light;

-- ---------------------------------------------------------------------
-- Step 4: sex recorded as M or F
-- This table (all seatbelt codes) is kept for the sensitivity check.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS occ_s4_sex;
CREATE TABLE occ_s4_sex STORED AS ORC AS
SELECT * FROM occ_s3_light
WHERE sex IN ('M','F');

SELECT COUNT(*) AS n_step4 FROM occ_s4_sex;

-- Seatbelt code breakdown at this point (for the data log / report)
SELECT helmet_belt_worn, COUNT(*) AS n
FROM occ_s4_sex
GROUP BY helmet_belt_worn
ORDER BY n DESC;

-- ---------------------------------------------------------------------
-- Step 5: seatbelt worn (code 1) = main analysis table
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS occupants_final;
CREATE TABLE occupants_final STORED AS ORC AS
SELECT * FROM occ_s4_sex
WHERE helmet_belt_worn = '1';

SELECT COUNT(*) AS n_final FROM occupants_final;

-- Sensitivity table: belt worn OR belt not known
DROP TABLE IF EXISTS occupants_sensitivity;
CREATE TABLE occupants_sensitivity STORED AS ORC AS
SELECT * FROM occ_s4_sex
WHERE helmet_belt_worn IN ('1','9');

SELECT COUNT(*) AS n_sensitivity FROM occupants_sensitivity;
