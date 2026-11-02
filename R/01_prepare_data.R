# =====================================================================
# 01_prepare_data.R  (Step 3: Data preparation)
#
# What this script does:
#   1. Reads the three raw crash tables (person, vehicle, accident)
#   2. Works out details about the OTHER vehicle in each crash
#   3. Joins everything into one table with one row per person
#   4. Filters down to our study group, one step at a time,
#      printing how many people are left after each step
#   5. Saves the final tables to data/processed/ for the next steps
#
# How to run it:
#   Open the project folder in RStudio (File > Open Project, or set the
#   working directory to the project folder), then click "Source".
#   The raw CSVs must be in data/raw/.
# =====================================================================

library(dplyr)   # for filtering, joining and summarising tables
library(readr)   # for reading and writing CSV files


# ---------------------------------------------------------------------
# 1. Read the raw tables
# ---------------------------------------------------------------------
# We read every column as text ("c" = character) first. This keeps codes
# like "01" or "060" exactly as they are (otherwise R would turn "01"
# into the number 1). We convert the real number columns afterwards.
# rename_with(tolower) makes all column names lower case, so they are
# easier to type.

person   <- read_csv("data/raw/person.csv",   col_types = cols(.default = "c")) %>% rename_with(tolower)
vehicle  <- read_csv("data/raw/vehicle.csv",  col_types = cols(.default = "c")) %>% rename_with(tolower)
accident <- read_csv("data/raw/accident.csv", col_types = cols(.default = "c")) %>% rename_with(tolower)

# Check the row counts match the data log (expected: 425352, 331992, 182039)
cat("Rows read - person:", nrow(person),
    "| vehicle:", nrow(vehicle),
    "| accident:", nrow(accident), "\n")

# Turn the number columns in the vehicle table into actual numbers.
# A weight of 0 kg is impossible, so we treat it as missing (NA).
vehicle <- vehicle %>%
  mutate(
    vehicle_year_manuf = as.integer(vehicle_year_manuf),
    tare_weight        = as.integer(tare_weight),
    tare_weight        = ifelse(tare_weight == 0, NA, tare_weight),
    total_no_occupants = as.integer(total_no_occupants)
  )


# ---------------------------------------------------------------------
# 2. Details about the OTHER vehicle(s) in each crash
# ---------------------------------------------------------------------
# Being hit by a truck is very different to being hit by a small car,
# so for every vehicle we record:
#   n_other_vehicles : how many other vehicles were in the same crash
#   other_max_tare   : weight (kg) of the heaviest other vehicle
#   other_heavy_flag : 1 if any other vehicle was a truck, bus or
#                      light commercial vehicle, otherwise 0

heavy_types <- c("06", "07", "08", "09", "60", "61", "62", "63", "71", "72")

veh_small <- vehicle %>%
  select(accident_no, vehicle_id, vehicle_type, tare_weight)

other_vehicle <- veh_small %>%
  # pair each vehicle with every vehicle in the same crash...
  inner_join(veh_small, by = "accident_no",
             suffix = c("", "_other"), relationship = "many-to-many") %>%
  # ...then drop the pairs where a vehicle is matched with itself
  filter(vehicle_id != vehicle_id_other) %>%
  group_by(accident_no, vehicle_id) %>%
  summarise(
    n_other_vehicles = n(),
    other_max_tare   = if (all(is.na(tare_weight_other))) NA_integer_
                       else max(tare_weight_other, na.rm = TRUE),
    other_heavy_flag = as.integer(any(vehicle_type_other %in% heavy_types)),
    .groups = "drop"
  )

# Single-vehicle crashes have no "other" vehicle, so add them back with 0s
vehicle <- vehicle %>%
  left_join(other_vehicle, by = c("accident_no", "vehicle_id")) %>%
  mutate(
    n_other_vehicles = coalesce(n_other_vehicles, 0L),
    other_heavy_flag = coalesce(other_heavy_flag, 0L)
  )


# ---------------------------------------------------------------------
# 3. Join person + vehicle + accident into one table
# ---------------------------------------------------------------------
# Each person is matched to their vehicle (using accident_no AND
# vehicle_id) and to their crash (using accident_no).
# inner_join keeps only people who have a matching vehicle, so people
# with no vehicle (mostly pedestrians) drop out here.

# A small table to record how many people are left after each step.
# This becomes the data log table in the report.
steps <- tibble(step = character(), description = character(), rows = integer())
log_step <- function(steps, step, description, data) {
  cat(sprintf("Step %-2s | %-55s | %s rows\n",
              step, description, format(nrow(data), big.mark = ",")))
  add_row(steps, step = step, description = description, rows = nrow(data))
}

steps <- log_step(steps, "0", "All people in person table", person)

occupants <- person %>%
  inner_join(vehicle,  by = c("accident_no", "vehicle_id")) %>%
  inner_join(accident, by = "accident_no") %>%
  mutate(
    # Outcome: 1 = killed or seriously injured (KSI), 0 = not
    ksi = ifelse(inj_level %in% c("1", "2"), 1L, 0L),
    accident_year = as.integer(substr(accident_date, 1, 4))
  ) %>%
  # keep only the columns we need, in a sensible order
  select(
    # person
    accident_no, person_id, vehicle_id, sex, age_group, inj_level, ksi,
    seating_position, helmet_belt_worn, road_user_type, taken_hospital, ejected_code,
    # vehicle
    vehicle_year_manuf, vehicle_type, vehicle_body_style, vehicle_make, vehicle_model,
    tare_weight, total_no_occupants, initial_impact, level_of_damage, vehicle_movement,
    # crash
    accident_date, accident_year, accident_time, day_of_week, accident_type, dca_code,
    light_condition, no_of_vehicles, road_geometry, speed_zone,
    # other vehicle
    n_other_vehicles, other_max_tare, other_heavy_flag
  )

steps <- log_step(steps, "1", "Joined to a vehicle and crash", occupants)


# ---------------------------------------------------------------------
# 4. Filter to our study group, one step at a time
# ---------------------------------------------------------------------

# Step 2: drivers (D) and left-front passengers (LF) only
occupants <- occupants %>% filter(seating_position %in% c("D", "LF"))
steps <- log_step(steps, "2", "Drivers and front passengers", occupants)

# Step 3: cars (01), station wagons (02) and utes (04) only
occupants <- occupants %>% filter(vehicle_type %in% c("01", "02", "04"))
steps <- log_step(steps, "3", "Cars, station wagons and utes", occupants)

# Step 4: sex recorded as male or female
occupants <- occupants %>% filter(sex %in% c("M", "F"))
steps <- log_step(steps, "4", "Sex recorded as M or F", occupants)

# How many people have each seatbelt code at this point?
# (1 = worn, 9 = not known; see docs/codebook.md for the rest)
cat("\nSeatbelt codes before the last filter:\n")
print(count(occupants, helmet_belt_worn, sort = TRUE))

# Sensitivity table: seatbelt worn OR not known.
# Used later to check whether dropping the "not known" group changes results.
occupants_sensitivity <- occupants %>% filter(helmet_belt_worn %in% c("1", "9"))

# Step 5: seatbelt worn (code 1) = our main analysis table
occupants_final <- occupants %>% filter(helmet_belt_worn == "1")
steps <- log_step(steps, "5", "Seatbelt worn (FINAL TABLE)", occupants_final)

cat("Sensitivity table (belt worn or not known):",
    format(nrow(occupants_sensitivity), big.mark = ","), "rows\n")


# ---------------------------------------------------------------------
# 5. Quick check that the table looks sensible
# ---------------------------------------------------------------------
# Percentage of women and men killed or seriously injured.
# Expected: about 18.4% for F and 14.7% for M.
cat("\nKSI rate by sex (final table):\n")
occupants_final %>%
  group_by(sex) %>%
  summarise(people = n(), ksi_count = sum(ksi), ksi_pct = round(100 * mean(ksi), 2)) %>%
  print()


# ---------------------------------------------------------------------
# 6. Save the results
# ---------------------------------------------------------------------
dir.create("data/processed",  showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/tables",  showWarnings = FALSE, recursive = TRUE)

write_csv(occupants_final,       "data/processed/occupants_final.csv")
write_csv(occupants_sensitivity, "data/processed/occupants_sensitivity.csv")
write_csv(steps,                 "outputs/tables/step3_filter_counts.csv")

cat("\nSaved:\n",
    " data/processed/occupants_final.csv\n",
    " data/processed/occupants_sensitivity.csv\n",
    " outputs/tables/step3_filter_counts.csv\n")
