# Rebuild the PNGs used by the GitHub Pages dashboard.
# The source data is private; place it in DATA/ before running.
# Usage: Rscript scripts/rebuild_site_figures.R

if (!file.exists("social_burden_dashboard.Rmd")) {
  stop("Run this script from the repository root.", call. = FALSE)
}

if (!requireNamespace("rmarkdown", quietly = TRUE)) {
  stop("Install rmarkdown to render the analyses.", call. = FALSE)
}

# Each report writes its figures to assets/img/ as well as its own output.
rmarkdown::render("social_burden_dashboard.Rmd", quiet = TRUE)
rmarkdown::render("agentic_datafest_patients.Rmd", quiet = TRUE)

message("Rebuilt site figures in assets/img/.")
