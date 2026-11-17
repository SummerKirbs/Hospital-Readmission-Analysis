# Builds the patient-level tables used by the dashboard.
# The encounter scan is cached; delete cache/dashboard_data.rds to rebuild.

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(readr)
})

find_data_file <- function(filename, doc_dir) {
  candidates <- c(
    file.path(doc_dir, "..", "DATA", filename),
    file.path(doc_dir, "DATA", filename),
    file.path("DATA", filename),
    filename
  )
  hit <- candidates[file.exists(candidates)]
  if (!length(hit)) stop("Could not find ", filename, call. = FALSE)
  normalizePath(hit[1], winslash = "/")
}

build_patient_metrics <- function(encounters_csv, cache_file) {
  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  dbExecute(con, sprintf("
    CREATE TABLE enc AS
    SELECT
      TRY_CAST(PatientDurableKey AS INTEGER) AS PatientDurableKey,
      TRY_CAST(EncounterKey AS INTEGER) AS EncounterKey,
      TRY_CAST(strptime(Date, '%%m/%%d/%%y') AS DATE) AS Date,
      TRY_CAST(IsEdVisit AS TINYINT) AS ed,
      TRY_CAST(IsInpatientAdmission AS TINYINT) AS inp,
      TRY_CAST(IsOutpatientFaceToFaceVisit AS TINYINT) AS outp
    FROM read_csv_auto('%s', header = true, all_varchar = true,
                       nullstr = ['NA', ''], sample_size = 200000)
    WHERE PatientDurableKey IS NOT NULL AND Date IS NOT NULL
  ", encounters_csv))

  dbExecute(con, "
    CREATE TABLE pd AS
    SELECT PatientDurableKey, Date,
           MAX(outp) AS outp, MAX(ed) AS ed, MAX(inp) AS inp
    FROM enc GROUP BY 1, 2
  ")

  dbExecute(con, "
    CREATE TABLE pd2 AS
    SELECT *,
      MIN(Date) OVER (
        PARTITION BY PatientDurableKey ORDER BY Date
        ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
      ) AS next_any,
      MIN(CASE WHEN outp = 1 THEN Date END) OVER (
        PARTITION BY PatientDurableKey ORDER BY Date
        ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
      ) AS next_out,
      MIN(Date) OVER (PARTITION BY PatientDurableKey) AS first_any,
      MIN(CASE WHEN outp = 1 THEN Date END) OVER (PARTITION BY PatientDurableKey) AS first_out
    FROM pd
  ")

  dbExecute(con, "
    CREATE TABLE ordered AS
    SELECT *, ROW_NUMBER() OVER (
      PARTITION BY PatientDurableKey ORDER BY Date, EncounterKey
    ) AS overall_rn
    FROM enc
  ")
  dbExecute(con, "
    CREATE TABLE inp_only AS
    SELECT *, ROW_NUMBER() OVER (
      PARTITION BY PatientDurableKey ORDER BY Date, EncounterKey
    ) AS inp_rn
    FROM ordered WHERE inp = 1
  ")
  dbExecute(con, "
    CREATE TABLE stays AS
    SELECT PatientDurableKey, overall_rn - inp_rn AS stay_group,
           COUNT(*) AS stay_len
    FROM inp_only GROUP BY 1, 2
  ")

  metrics <- dbGetQuery(con, "
    SELECT
      p.PatientDurableKey,
      MIN(p.Date) AS first_date,
      MAX(p.Date) AS last_date,
      COUNT(*) AS n_care_days,
      COALESCE(SUM(p.outp), 0) AS n_outpatient_days,
      COALESCE(SUM(p.ed), 0) AS n_ed_days,
      COALESCE(SUM(p.inp), 0) AS n_inpatient_days,
      MAX(CASE WHEN p.Date = p.first_any AND p.next_any - p.Date <= 30 THEN 1 ELSE 0 END) AS ret30_any,
      MAX(CASE WHEN p.Date = p.first_any AND p.next_any - p.Date <= 90 THEN 1 ELSE 0 END) AS ret90_any,
      MAX(CASE WHEN p.Date = p.first_out AND p.next_out - p.Date <= 30 THEN 1 ELSE 0 END) AS ret30_out,
      MAX(CASE WHEN p.Date = p.first_out AND p.next_out - p.Date <= 90 THEN 1 ELSE 0 END) AS ret90_out,
      MAX(CASE WHEN p.ed = 1 AND p.next_out - p.Date <= 7 THEN 1 ELSE 0 END) AS fu7_ed,
      MAX(CASE WHEN p.ed = 1 AND p.next_out - p.Date <= 30 THEN 1 ELSE 0 END) AS fu30_ed,
      COALESCE(SUM(CASE WHEN p.ed = 1 AND p.next_out - p.Date <= 7 THEN 1 ELSE 0 END), 0) AS ed_fu7,
      COALESCE(SUM(CASE WHEN p.ed = 1 AND p.next_out - p.Date <= 30 THEN 1 ELSE 0 END), 0) AS ed_fu30,
      COALESCE(SUM(CASE WHEN p.inp = 1 AND p.next_out - p.Date <= 30 THEN 1 ELSE 0 END), 0) AS inp_fu30
    FROM pd2 p
    GROUP BY p.PatientDurableKey
  ") %>% as_tibble()

  stays <- dbGetQuery(con, "
    SELECT PatientDurableKey, COUNT(*) AS n_stays, SUM(stay_len) AS n_inpatient_encounters
    FROM stays GROUP BY 1
  ") %>% as_tibble()

  metrics %>%
    left_join(stays, by = "PatientDurableKey") %>%
    mutate(
      n_stays = coalesce(n_stays, 0L),
      n_inpatient_encounters = coalesce(n_inpatient_encounters, 0L)
    )
}

build_sdoh_flags <- function(sdoh_csv) {
  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  sd <- dbGetQuery(con, sprintf("
    SELECT
      TRY_CAST(PatientDurableKey AS INTEGER) AS PatientDurableKey,
      DisplayName,
      AnswerText
    FROM read_csv_auto('%s', header = true, all_varchar = true,
                       nullstr = ['NA', ''], sample_size = 200000)
    WHERE DisplayName <> '*Unspecified'
  ", sdoh_csv)) %>% as_tibble()

  sd <- sd %>%
    mutate(
      question = case_when(
        DisplayName == "Edinburgh Depression Scale Total" ~ "edinburgh",
        DisplayName == "PHQ-2 Total Score" ~ "phq2",
        str_detect(DisplayName, regex("food would run out", ignore_case = TRUE)) ~ "food_worry",
        str_detect(DisplayName, regex("food you bought", ignore_case = TRUE)) ~ "food_lasted",
        str_detect(DisplayName, regex("medical appointments", ignore_case = TRUE)) ~ "transport_med",
        str_detect(DisplayName, regex("meetings, work", ignore_case = TRUE)) ~ "transport_daily",
        str_detect(DisplayName, regex("pay for the very basics", ignore_case = TRUE)) ~ "pay_basics",
        str_detect(DisplayName, regex("pay the mortgage or rent", ignore_case = TRUE)) ~ "pay_rent",
        str_detect(DisplayName, regex("feel stress", ignore_case = TRUE)) ~ "stress",
        str_detect(DisplayName, regex("homeless or living in a shelter", ignore_case = TRUE)) ~ "homeless",
        str_detect(DisplayName, regex("steady place to sleep", ignore_case = TRUE)) ~ "steady_sleep",
        str_detect(DisplayName, regex("times have you moved", ignore_case = TRUE)) ~ "moves",
        str_detect(DisplayName, regex("electric, gas, oil, or water", ignore_case = TRUE)) ~ "utilities",
        str_detect(DisplayName, regex("six or more drinks", ignore_case = TRUE)) ~ "alcohol_binge",
        str_detect(DisplayName, regex("How often do you have a drink", ignore_case = TRUE)) ~ "alcohol_freq",
        str_detect(DisplayName, regex("days per week do you engage", ignore_case = TRUE)) ~ "exercise_days",
        str_detect(DisplayName, regex("afraid of your partner", ignore_case = TRUE)) ~ "ipv_afraid",
        str_detect(DisplayName, regex("kicked, hit, slapped", ignore_case = TRUE)) ~ "ipv_hit",
        str_detect(DisplayName, regex("humiliated or emotionally abused", ignore_case = TRUE)) ~ "ipv_emotional",
        str_detect(DisplayName, regex("raped or forced", ignore_case = TRUE)) ~ "ipv_sexual",
        TRUE ~ NA_character_
      ),
      num = suppressWarnings(as.numeric(AnswerText)),
      valid = !is.na(AnswerText) &
        !AnswerText %in% c("Patient declined", "Patient unable to answer", "*Unknown")
    ) %>%
    filter(!is.na(question))

  # one row per patient and domain
  domain <- sd %>%
    mutate(
      domain = case_when(
        question %in% c("food_worry", "food_lasted") ~ "food",
        question %in% c("transport_med", "transport_daily") ~ "transport",
        question %in% c("homeless", "steady_sleep", "moves") ~ "housing",
        question %in% c("pay_basics", "pay_rent") ~ "financial",
        question == "utilities" ~ "utilities",
        question == "stress" ~ "stress",
        question %in% c("edinburgh", "phq2") ~ "depression",
        question %in% c("alcohol_freq", "alcohol_binge") ~ "alcohol",
        question == "exercise_days" ~ "inactive",
        str_starts(question, "ipv_") ~ "ipv",
        TRUE ~ NA_character_
      ),
      positive = case_when(
        domain == "food" & AnswerText %in% c("Sometimes true", "Often true") ~ 1L,
        domain == "food" ~ 0L,
        domain == "transport" & AnswerText == "Yes" ~ 1L,
        domain == "transport" ~ 0L,
        domain == "housing" & question %in% c("homeless", "steady_sleep") & AnswerText == "Yes" ~ 1L,
        domain == "housing" & question == "moves" & !is.na(num) & num >= 3 ~ 1L,
        domain == "housing" ~ 0L,
        domain == "financial" & question == "pay_basics" &
          AnswerText %in% c("Somewhat hard", "Hard", "Very hard") ~ 1L,
        domain == "financial" & question == "pay_rent" & AnswerText == "Yes" ~ 1L,
        domain == "financial" ~ 0L,
        domain == "utilities" & AnswerText %in% c("Yes", "Already shut off") ~ 1L,
        domain == "utilities" ~ 0L,
        domain == "stress" & AnswerText %in% c("To some extent", "Rather much", "Very much") ~ 1L,
        domain == "stress" ~ 0L,
        domain == "depression" & question == "edinburgh" & !is.na(num) & num >= 10 ~ 1L,
        domain == "depression" & question == "phq2" & !is.na(num) & num >= 3 ~ 1L,
        domain == "depression" ~ 0L,
        domain == "alcohol" & question == "alcohol_freq" &
          AnswerText %in% c("2-3 times a week", "4 or more times a week") ~ 1L,
        domain == "alcohol" & question == "alcohol_binge" &
          AnswerText %in% c("Weekly", "Daily or almost daily") ~ 1L,
        domain == "alcohol" ~ 0L,
        domain == "inactive" & AnswerText == "0 days" ~ 1L,
        domain == "inactive" ~ 0L,
        domain == "ipv" & AnswerText == "Yes" ~ 1L,
        domain == "ipv" ~ 0L,
        TRUE ~ NA_integer_
      )
    ) %>%
    filter(!is.na(domain), valid) %>%
    group_by(PatientDurableKey, domain) %>%
    summarise(flag = max(positive, na.rm = TRUE), .groups = "drop")

  # screened = replied to at least one question in the domain
  screened <- sd %>%
    filter(valid) %>%
    mutate(
      domain = case_when(
        question %in% c("food_worry", "food_lasted") ~ "food",
        question %in% c("transport_med", "transport_daily") ~ "transport",
        question %in% c("homeless", "steady_sleep", "moves") ~ "housing",
        question %in% c("pay_basics", "pay_rent") ~ "financial",
        question == "utilities" ~ "utilities",
        question == "stress" ~ "stress",
        question %in% c("edinburgh", "phq2") ~ "depression",
        question %in% c("alcohol_freq", "alcohol_binge") ~ "alcohol",
        question == "exercise_days" ~ "inactive",
        str_starts(question, "ipv_") ~ "ipv",
        TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(domain)) %>%
    distinct(PatientDurableKey, domain) %>%
    mutate(screened = 1L)

  domain %>%
    full_join(screened, by = c("PatientDurableKey", "domain")) %>%
    mutate(flag = coalesce(flag, 0L), screened = coalesce(screened, 0L)) %>%
    pivot_wider(
      names_from = domain,
      values_from = c(flag, screened),
      names_glue = "{domain}_{.value}",
      values_fill = 0L
    ) %>%
    left_join(build_panel_flags(sd), by = "PatientDurableKey")
}

# Item-level flags for the readmission panels.
build_panel_flags <- function(sd) {
  sd %>%
    mutate(
      transport_med_flag = case_when(
        question == "transport_med" & AnswerText == "Yes" ~ 1L,
        question == "transport_med" ~ 0L,
        TRUE ~ NA_integer_
      ),
      transport_med_screened = as.integer(question == "transport_med" & valid),
      pay_basics_flag = case_when(
        question == "pay_basics" & AnswerText %in% c("Somewhat hard", "Hard", "Very hard") ~ 1L,
        question == "pay_basics" ~ 0L,
        TRUE ~ NA_integer_
      ),
      pay_basics_screened = as.integer(question == "pay_basics" & valid),
      food_any_flag = case_when(
        question %in% c("food_worry", "food_lasted") &
          AnswerText %in% c("Sometimes true", "Often true") ~ 1L,
        question %in% c("food_worry", "food_lasted") ~ 0L,
        TRUE ~ NA_integer_
      ),
      food_any_screened = as.integer(question %in% c("food_worry", "food_lasted") & valid),
      ipv_any_flag = case_when(
        str_starts(question, "ipv_") & AnswerText == "Yes" ~ 1L,
        str_starts(question, "ipv_") ~ 0L,
        TRUE ~ NA_integer_
      ),
      ipv_any_screened = as.integer(str_starts(question, "ipv_") & valid)
    ) %>%
    group_by(PatientDurableKey) %>%
    summarise(
      across(ends_with("_flag"), ~ if (all(is.na(.x))) NA_integer_ else as.integer(any(.x == 1, na.rm = TRUE))),
      across(ends_with("_screened"), ~ as.integer(any(.x == 1, na.rm = TRUE))),
      .groups = "drop"
    )
}

load_dashboard_data <- function(doc_dir = getwd(), refresh = FALSE) {
  cache_dir <- file.path(doc_dir, "cache")
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  cache_file <- file.path(cache_dir, "dashboard_data.rds")

  encounters_csv <- find_data_file("encounters.csv", doc_dir)
  sdoh_csv <- find_data_file("social_determinants.csv", doc_dir)
  patients_csv <- find_data_file("patients.csv", doc_dir)

  source_newest <- max(file.mtime(c(encounters_csv, sdoh_csv, patients_csv)))

  if (!refresh && file.exists(cache_file) && file.mtime(cache_file) >= source_newest) {
    return(readRDS(cache_file))
  }

  message("Building dashboard cache. The first run scans the encounter file once.")
  metrics <- build_patient_metrics(encounters_csv, cache_file)
  sdoh <- build_sdoh_flags(sdoh_csv)

  smoking <- read_csv(
    patients_csv,
    show_col_types = FALSE,
    col_types = cols(.default = col_character())
  ) %>%
    transmute(
      PatientDurableKey = suppressWarnings(as.integer(DurableKey)),
      smoking_group = case_when(
        SmokingStatus %in% c("Every Day", "Heavy Smoker") ~ "Heavy Smoker",
        SmokingStatus %in% c("Some Days", "Light Smoker", "Smoker, Current Status Unknown") ~ "Light Smoker",
        SmokingStatus == "Former" ~ "Former Smoker",
        SmokingStatus %in% c("Never", "Passive Smoke Exposure - Never Smoker") ~ "Never",
        TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(PatientDurableKey)) %>%
    distinct(PatientDurableKey, .keep_all = TRUE)

  score_domains <- c(
    "food", "transport", "housing", "financial", "utilities",
    "stress", "depression", "alcohol", "inactive"
  )

  d <- metrics %>%
    left_join(sdoh, by = "PatientDurableKey") %>%
    left_join(smoking, by = "PatientDurableKey") %>%
    mutate(
      across(ends_with("_flag"), ~ coalesce(.x, 0L)),
      across(ends_with("_screened"), ~ coalesce(.x, 0L)),
      # domains outside the score are kept for the no-risk definition
      screened_any = as.integer(rowSums(across(paste0(score_domains, "_screened"))) > 0),
      social_burden = rowSums(across(paste0(score_domains, "_flag"))),
      no_risk_panel = as.integer(
        transport_med_flag == 0 & pay_basics_flag == 0 &
          food_any_flag == 0 & ipv_any_flag == 0
      ),
      no_risk_panel_screened = as.integer(
        transport_med_screened == 1 & pay_basics_screened == 1 &
          food_any_screened == 1 & ipv_any_screened == 1
      )
    )

  out <- list(
    patients = d,
    score_domains = score_domains,
    meta = list(
      n_patients = nrow(d),
      n_surveyed = sum(d$screened_any == 1),
      encounter_start = min(d$first_date, na.rm = TRUE),
      encounter_end = max(d$last_date, na.rm = TRUE),
      built = Sys.time()
    )
  )
  saveRDS(out, cache_file)
  out
}
