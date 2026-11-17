# Hospital Readmission Analysis

**Journey escalation, social burden, and readmission in a real hospital dataset.**

[![Live Dashboard](https://img.shields.io/badge/dashboard-live-0f7b8a)](https://summerkirbs.github.io/Hospital-Readmission-Analysis/)
[![R](https://img.shields.io/badge/R-analysis-276DC3?logo=r&logoColor=white)](https://www.r-project.org/)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

This project analyzes social determinants of health, readmission frequency, and care-gap escalation in a large hospital dataset. It combines the original DataFest analysis with a stricter patient-level rebuild and a deeper look at what happens when chronic-care follow-up stops.

The public dashboard is a static site built from the same R code in this repository. No patient-level data is published.

## Features

- **Social Burden Score:** Counts positive domains across nine SDOH domains (food, transportation, housing, financial strain, utilities, stress, depression, alcohol, inactivity).
- **Patient-level cohort:** Keeps 70,791 patients with at least one usable survey answer, rather than counting questionnaire rows.
- **Readmission analysis:** Compares 1–2, 3–5, and 6+ inpatient admissions with social barriers and smoking status.
- **Follow-up analysis:** Measures face-to-face outpatient follow-up within 90 days of the first outpatient visit.
- **Care-gap escalation:** Follows 262,585 transitions after chronic-condition outpatient visits and identifies when the next contact is an ED visit or hospital admission.
- **Adjusted model:** Estimates patient-level odds ratios for social, demographic, and utilization predictors.
- **Compound risk:** Shows how smoking and transportation barriers combine.
- **Reproducible visuals:** Every chart on the dashboard is written by the R Markdown code in this repository.
- **Static dashboard:** A dependency-free GitHub Pages site with responsive charts and plain-language captions.

## Tech Stack

- **Language:** R
- **Data handling:** tidyverse, DuckDB, DBI
- **Modeling:** broom, base `glm`
- **Visualization:** ggplot2, scales
- **Reporting:** R Markdown, knitr, flexdashboard
- **Site:** HTML, CSS, GitHub Pages
- **License:** Apache 2.0

## Table of Contents

- [Overview](#overview)
- [Data](#data)
- [Methodology](#methodology)
- [Results](#results)
- [Project Structure](#project-structure)
- [Reproducing the Analysis](#reproducing-the-analysis)
- [Dashboard](#dashboard)
- [Limitations](#limitations)
- [License](#license)
- [Important Links](#important-links)
- [Team](#team)

## Overview

Two linked questions drive the project:

1. **Does social burden compound hospital use?** Patients with more social barriers have more inpatient admissions and less timely follow-up. The relationship is not a simple step: follow-up peaks in the middle of the score and then falls sharply for the highest-burden patients.
2. **What happens when chronic-care follow-up stops?** After a chronic-condition outpatient visit, the next care contact is sometimes an ED visit or hospital admission. Escalation risk is U-shaped: highest in the first month, lowest around 6–9 months, and highest again after a year.

The dashboard tells both stories with eight charts, short captions, and the definitions needed to read them.

## Data

The dataset is **private outside of the hackathon and is not included in this repository**. It spans multiple CSVs and hundreds of features across millions of rows; only the fields used in this analysis were selected and compiled into working tables. No patient-level records are published.

To rerun the analysis with authorized access, place these files in `DATA/`:

```text
DATA/
├── full_encounters.csv        # merged encounter table (care-gap analysis)
├── encounters.csv             # encounter-level table (dashboard cohort)
├── patients.csv               # demographics and smoking status
└── social_determinants.csv    # raw questionnaire responses
```

The scripts also look for the files in `../DATA/` and the working directory.

The data includes encounter dates from 2022 through 2025, inpatient and outpatient encounter flags, diagnosis groups, demographics, smoking status, and SDOH questionnaire responses. There is no data download link in this repository.

## Methodology

### Social Burden Score

The score adds one point per positive domain across nine SDOH domains. A patient enters the score only if they answered at least one domain; missing domains add zero, so the score is a lower bound on burden.

| Domain | Positive threshold |
|---|---|
| Food insecurity | “Sometimes true” or “Often true” on either food question |
| Transportation | “Yes” to either transportation question |
| Housing instability | Homeless, no steady place to sleep in the past year, or 3+ moves |
| Financial strain | Paying for basics is somewhat hard, hard, or very hard, or unable to pay rent on time |
| Utility shut-off risk | Threatened shut-off or already shut off |
| High stress | “Rather much” or “Very much” |
| Depression | Edinburgh score ≥ 10 or PHQ-2 score ≥ 3 |
| Heavy alcohol use | Drinking 2–3 times a week or more, or weekly binge drinking |
| Physical inactivity | Zero days of moderate exercise per week |

### Readmission and follow-up

- An **inpatient admission** is a distinct inpatient stay. Consecutive inpatient days count once.
- **Readmission bands** are 1–2, 3–5, and 6+ stays.
- **Follow-up** means a face-to-face outpatient visit within 90 days of the patient's first outpatient visit.
- The social score is cross-sectional: it uses the most recent positive answer available, not a time-varying exposure.

### Care-gap escalation

- An **anchor** is a face-to-face outpatient visit coded to a chronic condition.
- **Escalation** means the next care contact after the anchor is an ED visit, hospital admission, or inpatient stay.
- The **gap** is days from the anchor to that next contact. Same-day contacts and lab/imaging-only days are excluded.
- The patient-level outcome is whether a patient ever escalated.

### Model

A logistic regression estimates the odds of ever escalating, adjusting for smoking, MyChart activation, race, age, condition count, and visit count. Each SDOH variable is added separately because questionnaire coverage is incomplete, so the reported N varies by row. Odds ratios are descriptive associations, not causal effects. The compound-risk chart is unadjusted by design.

## Results

### Social burden and readmission

| Metric | Value |
|---|---|
| Patients with a usable SDOH survey | 70,791 |
| Average inpatient admissions per patient | 0.59 |
| Outpatient follow-up within 90 days | 60% |
| Patients with 6+ inpatient admissions | 1.8% |
| Average admissions, score 0 → score 7 | 0.40 → 3.39 |
| Relative rise across the score | ~8.5× |
| Follow-up, score 0 → score 7 | 58% → 41% |
| Follow-up gap at score 7 | −16 percentage points |

The score gradient is strongest at the top: score 0 has 31,953 patients, while score 7 has 335. The final follow-up drop should therefore be read as directional.

### Readmission frequency

| Factor | 1–2 admissions | 6+ admissions | Change |
|---|---:|---:|---:|
| No risk factors | 75.14% | 57.32% | −17.8 pp |
| Financial strain | 16.95% | 31.61% | +14.7 pp |
| Transportation barrier | 6.82% | 25.16% | +18.3 pp |
| Heavy smoker | 14.15% | 18.11% | +4.0 pp |
| Light smoker | 2.74% | 3.62% | +0.9 pp |
| Former smoker | 26.17% | 44.74% | +18.6 pp |
| Never smoker | 56.94% | 33.53% | −23.4 pp |

The no-risk share falls while social barriers rise. The average rise across financial strain and transportation barriers is about **16.5 percentage points**, compared with a **17.8-point** drop for patients with no risk factors.

### Care-gap escalation

| Metric | Value |
|---|---|
| Chronic-condition patients | 90,836 |
| Outpatient anchors | 279,749 |
| Anchors with a later care contact | 262,585 |
| Escalations | 13,014 |
| Escalation rate per transition | 5.0% |
| Patients ever escalating | 14.6% |
| Base model patients | 62,014 |

Escalation by time to the next care contact:

| Gap (days) | Transitions | Escalations | Rate |
|---|---:|---:|---:|
| 1–30 | 128,103 | 7,454 | 5.8% |
| 31–60 | 45,105 | 2,212 | 4.9% |
| 61–90 | 24,767 | 1,099 | 4.4% |
| 91–120 | 23,065 | 643 | 2.8% |
| 121–180 | 17,898 | 730 | 4.1% |
| 181–270 | 16,473 | 417 | 2.5% |
| 271–365 | 3,461 | 159 | 4.6% |
| 365+ | 3,713 | 300 | 8.1% |

The pattern is U-shaped, not monotonic. A single 90-day cut would miss both the early spike and the late rise.

Strongest adjusted predictors of ever escalating:

| Predictor | OR | 95% CI | N |
|---|---:|---|---:|
| Unstable housing | 2.76 | 2.01–3.80 | 13,314 |
| Transportation barrier | 2.09 | 1.75–2.49 | 18,682 |
| Outpatient visits (per 5) | 1.76 | 1.72–1.81 | 62,014 |
| Current smoker | 1.51 | 1.42–1.62 | 62,014 |
| Chronic conditions (count) | 1.49 | 1.45–1.54 | 62,014 |
| Racial minority | 1.44 | 1.36–1.53 | 62,014 |
| Food insecure | 1.29 | 1.13–1.48 | 18,474 |
| Financial strain | 1.23 | 1.09–1.38 | 16,020 |
| High stress | 1.03 | 0.94–1.12 | 18,144 |
| Depression screen positive | 0.80 | 0.50–1.26 | 767 |
| MyChart activated | 0.69 | 0.64–0.73 | 62,014 |
| Age 40–64 (vs under 40) | 0.67 | 0.61–0.72 | 62,014 |
| Age 65+ (vs under 40) | 0.63 | 0.58–0.68 | 62,014 |

Smoking and transportation barriers compound:

| Group | Patients | Escalated | Rate |
|---|---:|---:|---:|
| Neither | 16,070 | 3,318 | 20.6% |
| Current smoker only | 2,055 | 559 | 27.2% |
| Transportation barrier only | 457 | 177 | 38.7% |
| Both | 198 | 85 | 42.9% |

The “both” group is small (n=198), so treat the exact gap as directional; the ordering is the useful signal.

### Two escalation rates

**5.0%** is the share of transitions that escalate; **14.6%** is the share of patients who ever escalate. They answer different questions.

## Project Structure

```text
.
├── index.html                     # static GitHub Pages dashboard
├── assets/
│   ├── css/style.css              # dashboard styling
│   └── img/*.png                  # charts written by the R analysis
├── social_burden_dashboard.Rmd    # Act I: social burden and readmission
├── social_burden_dashboard.html   # rendered flexdashboard (generated)
├── dashboard_data.R               # cohort and SDOH table builder
├── dashboard.css                  # flexdashboard styling
├── agentic_datafest_patients.Rmd  # Act II: care-gap escalation
├── agentic_datafest_patients.pdf  # rendered analysis report (generated)
├── scripts/
│   └── rebuild_site_figures.R     # rebuild all dashboard PNGs
├── .gitignore
├── .nojekyll
├── LICENSE
└── README.md
```

`social_burden_dashboard.html` and `agentic_datafest_patients.pdf` are generated artifacts kept for reference. The source of truth is the R Markdown and R code.

## Reproducing the Analysis

### Requirements

- R (4.x recommended)
- The packages below
- Authorized access to the private source CSVs

```r
install.packages(c(
  "tidyverse", "broom", "DBI", "duckdb",
  "flexdashboard", "scales", "knitr", "rmarkdown"
))
```

### Rebuild the reports and dashboard figures

Place the private CSVs in `DATA/`, then run from the repository root:

```bash
Rscript scripts/rebuild_site_figures.R
```

This renders both R Markdown reports and writes the eight dashboard PNGs to `assets/img/`.

Individual reports can also be rendered directly:

```bash
Rscript -e 'rmarkdown::render("social_burden_dashboard.Rmd")'
Rscript -e 'rmarkdown::render("agentic_datafest_patients.Rmd")'
```

The first render scans the encounter file once and caches the result in `cache/`. Delete `cache/dashboard_data.rds` to force a rebuild. Generated `cache/` and `figures/` folders are ignored by git.

## Dashboard

The dashboard is served by GitHub Pages from the repository root:

**https://summerkirbs.github.io/Hospital-Readmission-Analysis/**

It is plain HTML and CSS with one small progressive-enhancement script for the active navigation link. There are no external fonts, CDNs, or tracking scripts. `.nojekyll` disables Jekyll so the site is served as-is.

Every chart is reproducible from code:

| Dashboard image | Code | What it shows |
|---|---|---|
| `domain-prevalence.png` | `social_burden_dashboard.Rmd` | Prevalence of each SDOH domain |
| `admissions-by-score.png` | `social_burden_dashboard.Rmd` | Admissions by Social Burden Score |
| `followup-by-score.png` | `social_burden_dashboard.Rmd` | 90-day follow-up by score |
| `sdoh-by-readmission.png` | `social_burden_dashboard.Rmd` | SDOH by readmission band |
| `smoking-by-readmission.png` | `social_burden_dashboard.Rmd` | Smoking status by readmission band |
| `escalation-by-gap.png` | `agentic_datafest_patients.Rmd` | Escalation by care-gap length |
| `escalation-odds-ratios.png` | `agentic_datafest_patients.Rmd` | Adjusted odds ratios |
| `compound-risk.png` | `agentic_datafest_patients.Rmd` | Smoking + transportation risk |

## Limitations

- The social score is cross-sectional and depends on questionnaire coverage; it is not a time-varying exposure.
- The highest score group is small (n=335), so the final follow-up drop is directional.
- The “both risk factors” group in the compound chart is small (n=198).
- Odds ratios are adjusted associations, not causal effects. Unmeasured confounding remains.
- The data cannot be redistributed, so external readers cannot rerun the analysis without authorized access. The code and aggregate results are public.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.

## Important Links

- **Live Dashboard:** [summerkirbs.github.io/Hospital-Readmission-Analysis](https://summerkirbs.github.io/Hospital-Readmission-Analysis/)
- **Repository:** [SummerKirbs/Hospital-Readmission-Analysis](https://github.com/SummerKirbs/Hospital-Readmission-Analysis)
- **Full escalation report:** [agentic_datafest_patients.pdf](agentic_datafest_patients.pdf)
- **Rendered social-burden dashboard:** [social_burden_dashboard.html](social_burden_dashboard.html)

## Team

**Team Databased**, DataFest 2026

Angela Huang, Euleena Trinh, Kaelynn Cadiz, Nathan Truong, Will Prawira
