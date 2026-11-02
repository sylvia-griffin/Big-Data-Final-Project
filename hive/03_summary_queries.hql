-- =====================================================================
-- 03_summary_queries.hql
-- First look at the research question on the final table.
-- Screenshot each query with its output.
-- =====================================================================

USE crash;

-- Q1. KSI rate by sex
SELECT sex,
       COUNT(*)                     AS n,
       SUM(ksi)                     AS n_ksi,
       ROUND(100 * AVG(ksi), 2)     AS ksi_pct
FROM occupants_final
GROUP BY sex;

-- Q2. KSI rate by sex and seating position
SELECT seating_position, sex,
       COUNT(*) AS n,
       ROUND(100 * AVG(ksi), 2) AS ksi_pct
FROM occupants_final
GROUP BY seating_position, sex
ORDER BY seating_position, sex;

-- Q3. KSI rate by sex and vehicle era (the key question)
SELECT era, sex,
       COUNT(*) AS n,
       ROUND(100 * AVG(ksi), 2) AS ksi_pct
FROM (
  SELECT sex, ksi,
         CASE
           WHEN vehicle_year_manuf IS NULL OR vehicle_year_manuf < 1960
                OR vehicle_year_manuf > 2025 THEN 'unknown'
           WHEN vehicle_year_manuf < 2000 THEN '1: pre-2000'
           WHEN vehicle_year_manuf < 2010 THEN '2: 2000-2009'
           WHEN vehicle_year_manuf < 2016 THEN '3: 2010-2015'
           ELSE '4: 2016+'
         END AS era
  FROM occupants_final
) t
GROUP BY era, sex
ORDER BY era, sex;

-- Q4. KSI rate by sex and vehicle weight quartile (tare 0/NULL excluded)
SELECT tare_quartile, sex,
       COUNT(*)                 AS n,
       MIN(tare_weight)         AS min_kg,
       MAX(tare_weight)         AS max_kg,
       ROUND(100 * AVG(ksi), 2) AS ksi_pct
FROM (
  SELECT sex, ksi, tare_weight,
         NTILE(4) OVER (ORDER BY tare_weight) AS tare_quartile
  FROM occupants_final
  WHERE tare_weight > 0
) t
GROUP BY tare_quartile, sex
ORDER BY tare_quartile, sex;

-- Q5. KSI rate by sex and accident type
SELECT accident_type, sex,
       COUNT(*) AS n,
       ROUND(100 * AVG(ksi), 2) AS ksi_pct
FROM occupants_final
GROUP BY accident_type, sex
ORDER BY accident_type, sex;

-- Q6. Median-ish vehicle weight by sex (do women drive lighter cars?)
SELECT sex,
       PERCENTILE_APPROX(tare_weight, 0.5) AS median_tare_kg,
       ROUND(AVG(tare_weight), 0)          AS mean_tare_kg
FROM occupants_final
WHERE tare_weight > 0
GROUP BY sex;

-- Q7. Sensitivity: same as Q1 but including seatbelt unknown
SELECT helmet_belt_worn, sex,
       COUNT(*) AS n,
       ROUND(100 * AVG(ksi), 2) AS ksi_pct
FROM occupants_sensitivity
GROUP BY helmet_belt_worn, sex
ORDER BY helmet_belt_worn, sex;
