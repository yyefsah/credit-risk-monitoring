# Tables prêtes pour Power BI / Tableau : CSV UTF-8 (séparateur virgule, point décimal) + dictionnaire de données.
suppressPackageStartupMessages(library(dplyr))
source("R/00_config.R")
marts <- readRDS(file.path(DIR_CACHE, "marts.rds")); m <- readRDS(file.path(DIR_CACHE, "model.rds"))
out <- list(
  fact_loan      = m$d %>% select(loan_id, loan_date, vintage_year, sample, ko, is_bad, amount_czk, duration_months, ead_at_default_czk, pd_model, pd, band) %>% left_join(marts$loan_base %>% select(loan_id, district_name, region, default_date), by = "loan_id"),
  fact_portfolio_monthly = marts$portfolio_monthly,
  fact_vintage   = marts$vintage,
  dim_segment_kpi = marts$segment_kpi,
  dq_result      = marts$dq_result,
  assumption     = marts$assumption)
for (n in names(out)) write.csv(out[[n]], file.path(DIR_PBI, paste0(n, ".csv")), row.names = FALSE, fileEncoding = "UTF-8", na = "")
dic <- data.frame(table = c("fact_loan", "fact_portfolio_monthly", "fact_vintage", "dim_segment_kpi", "dq_result", "assumption"),
  grain = c("1 ligne par prêt", "1 ligne par fin de mois", "1 ligne par cohorte et pas de 3 mois", "1 ligne par segment", "1 ligne par contrôle", "1 ligne par hypothèse"),
  key = c("loan_id", "month_end", "vintage_year + months_on_book", "dimension + segment", "check_id", "key"),
  note = c("Relier à fact_portfolio_monthly par date. sample = train/test/immature ; ko = règle de refus automatique ; pd = 1 pour les prêts KO, sinon PD du modèle.",
           "Encours estimé par amortissement linéaire ; coût du risque avec LGD de la table assumption.",
           "Estimateur actuariel du défaut cumulé.", "Taux de défaut et montants par segment (GROUPING via ROLLUP).",
           "Résultats des contrôles qualité SQL.", "Hypothèses modifiables (LGD...)."))
write.csv(dic, file.path(DIR_PBI, "_dictionnaire.csv"), row.names = FALSE, fileEncoding = "UTF-8")
cat("Power BI CSV OK :", paste(names(out), collapse = ", "), "\n")
