# Rebuild the PNGs used by the GitHub Pages dashboard.
# The source data is private; place it in DATA/ before running.
# Usage: Rscript scripts/rebuild_site_figures.R

if (!file.exists("analysis/social_burden_dashboard.Rmd")) {
  stop("Run this script from the repository root.", call. = FALSE)
}

if (!requireNamespace("rmarkdown", quietly = TRUE)) {
  stop("Install rmarkdown to render the analyses.", call. = FALSE)
}

reports_dir <- normalizePath("reports", winslash = "/", mustWork = FALSE)
dir.create(reports_dir, showWarnings = FALSE)

# Each report writes its figures to assets/img/ as well as its own output.
rmarkdown::render(
  "analysis/social_burden_dashboard.Rmd",
  output_file = file.path(reports_dir, "social_burden_dashboard.html"),
  quiet = TRUE
)
rmarkdown::render(
  "analysis/agentic_datafest_patients.Rmd",
  output_file = file.path(reports_dir, "agentic_datafest_patients.pdf"),
  quiet = TRUE
)

message("Rebuilt site figures in assets/img/ and reports.")
