# Extraction des marts PostgreSQL vers des fichiers locaux (cache RDS + CSV prêts pour Power BI)
source("R/00_config.R")
con <- pg_connect(); on.exit(dbDisconnect(con), add = TRUE)

marts <- c("loan_base", "loan_features", "portfolio_monthly", "vintage", "segment_kpi")
tabs <- lapply(setNames(marts, marts), function(m) dbGetQuery(con, sprintf("SELECT * FROM mart.%s", m)))
tabs$dq_result  <- dbGetQuery(con, "SELECT check_id, layer, check_name, description, severity, n_checked, n_failed, passed FROM dq.result ORDER BY check_id")
tabs$assumption <- dbGetQuery(con, "SELECT * FROM mart.assumption")
# les colonnes numeric de PostgreSQL arrivent en numeric R ; les dates en Date
saveRDS(tabs, file.path(DIR_CACHE, "marts.rds"))
cat(sprintf("Extraction OK : %s\n", paste(sprintf("%s (%d)", names(tabs), vapply(tabs, nrow, 1L)), collapse = ", ")))
