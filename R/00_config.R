# Configuration commune (chemins, connexion PostgreSQL, hypothèses de modélisation)
suppressPackageStartupMessages({ library(DBI); library(RPostgreSQL) })

PROJECT_ROOT <- normalizePath(Sys.getenv("PROJECT_ROOT", unset = getwd()))
DIR_OUT   <- file.path(PROJECT_ROOT, "outputs")
DIR_FIG   <- file.path(DIR_OUT, "figures")
DIR_PBI   <- file.path(DIR_OUT, "powerbi")
DIR_CACHE <- file.path(PROJECT_ROOT, "outputs", "cache")
for (d in c(DIR_OUT, DIR_FIG, DIR_PBI, DIR_CACHE)) dir.create(d, showWarnings = FALSE, recursive = TRUE)

SEED        <- 42
TRAIN_YEARS <- 1993:1996      # apprentissage
TEST_YEARS  <- 1997           # validation hors période (temporelle)
IMMATURE_YEARS <- 1998        # cohorte trop récente : exclue de l'évaluation (défauts non encore observés)
N_BOOT      <- 2000
LGD         <- 0.45           # HYPOTHÈSE (cf. sql/04_marts.sql, table mart.assumption)

pg_connect <- function() {
  dbConnect(PostgreSQL(),
            host     = Sys.getenv("PGHOST", "localhost"),
            port     = as.integer(Sys.getenv("PGPORT", "5432")),
            user     = Sys.getenv("PGUSER", "yacine"),
            password = Sys.getenv("PGPASSWORD", ""),
            dbname   = Sys.getenv("PGDATABASE", "bankrisk"))
}
