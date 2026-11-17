# Score d'octroi : règle KO (découvert avant octroi) + régression logistique pénalisée sur le reste du portefeuille.
# Validation TEMPORELLE : apprentissage 1993-1996, validation 1997, cohorte 1998 exclue (immature).
suppressPackageStartupMessages({ library(glmnet); library(pROC); library(dplyr) })
source("R/00_config.R"); source("R/functions.R")
set.seed(SEED)
marts <- readRDS(file.path(DIR_CACHE, "marts.rds"))
d <- marts$loan_features %>%
  left_join(marts$loan_base %>% select(loan_id, ead_at_default_czk, default_date_imputed), by = "loan_id") %>%
  mutate(y = as.integer(is_bad), ko = n_neg_balance_days_before > 0,
         sample = case_when(vintage_year %in% TRAIN_YEARS ~ "train", vintage_year %in% TEST_YEARS ~ "test", TRUE ~ "immature"))

# ---- 1) Règle KO : valeur et limites --------------------------------------------------------------------------
ko_tab <- d %>% group_by(sample) %>% summarise(n = n(), n_ko = sum(ko), bad_in_ko = sum(is_bad & ko), bad_total = sum(is_bad),
                                               bad_outside_ko = sum(is_bad & !ko), n_outside_ko = sum(!ko), .groups = "drop")
print(as.data.frame(ko_tab))

# ---- 2) Modèle sur le périmètre hors-KO ------------------------------------------------------------------------
sc <- d %>% filter(!ko)
tr <- sc %>% filter(sample == "train"); te <- sc %>% filter(sample == "test")
cat(sprintf("\nPérimètre modèle : apprentissage n=%d (%d défauts), validation n=%d (%d défauts)\n", nrow(tr), sum(tr$y), nrow(te), sum(te$y)))

prep <- fit_prep(tr); Xtr <- apply_prep(tr, prep); Xte <- apply_prep(te, prep)
# CV groupée par cohorte (1993-94 | 1995 | 1996) : on n'évalue jamais un prêt avec un modèle qui a vu sa cohorte
foldid <- ifelse(tr$vintage_year <= 1994, 1L, ifelse(tr$vintage_year == 1995, 2L, 3L))

grid <- lapply(c(ridge = 0, enet = 0.5, lasso = 1), function(a)
  cv.glmnet(Xtr, tr$y, family = "binomial", alpha = a, foldid = foldid, type.measure = "auc", standardize = FALSE))
cv_auc <- sapply(grid, function(g) max(g$cvm))
best <- names(which.max(cv_auc)); cvfit <- grid[[best]]
cat("AUC CV groupée par cohorte :", paste(sprintf("%s=%.3f", names(cv_auc), cv_auc), collapse = "  "), "-> retenu:", best, "\n")
alpha_sel <- c(ridge = 0, enet = 0.5, lasso = 1)[[best]]
fit <- glmnet(Xtr, tr$y, family = "binomial", alpha = alpha_sel, lambda = cvfit$lambda.1se, standardize = FALSE)
coefs <- data.frame(variable = rownames(coef(fit)), coef = as.numeric(coef(fit)))
coefs <- coefs[coefs$variable != "(Intercept)", ]; coefs <- coefs[order(-abs(coefs$coef)), ]
print(coefs, row.names = FALSE)

# Références de comparaison (mêmes données, même découpage)
b_terms <- glm(y ~ log_amount + duration_months, data = cbind(y = tr$y, as.data.frame(Xtr)), family = binomial)   # conditions du contrat seules
pd_terms_te <- predict(b_terms, newdata = as.data.frame(Xte), type = "response")
pd_te <- as.numeric(predict(fit, Xte, type = "response"))
pd_tr <- as.numeric(predict(fit, Xtr, type = "response"))
pd_cash_te <- Xte[, "cash_share"]  # règle univariée : part des retraits en espèces

# ---- 3) Performance hors période -------------------------------------------------------------------------------
perf <- bind_rows(
  data.frame(model = "Score (régression pénalisée)", t(boot_ci(te$y, pd_te, auc_rank, N_BOOT, seed = SEED)), ks = ks_stat(te$y, pd_te)),
  data.frame(model = "Référence : conditions du contrat seules", t(boot_ci(te$y, pd_terms_te, auc_rank, N_BOOT, seed = SEED)), ks = ks_stat(te$y, pd_terms_te)),
  data.frame(model = "Référence : part des retraits en espèces seule", t(boot_ci(te$y, pd_cash_te, auc_rank, N_BOOT, seed = SEED)), ks = ks_stat(te$y, pd_cash_te))) %>%
  rename(auc = est, auc_lo = lo, auc_hi = hi) %>% mutate(gini = gini_from_auc(auc))
perf$brier <- c(mean((pd_te - te$y)^2), mean((pd_terms_te - te$y)^2), NA)
print(perf, row.names = FALSE)
roc_s <- roc(te$y, pd_te, quiet = TRUE, direction = "<"); roc_c <- roc(te$y, pd_terms_te, quiet = TRUE, direction = "<")
delong <- roc.test(roc_s, roc_c, method = "delong", paired = TRUE)
cat(sprintf("Test de DeLong (score vs contrat seul) : p = %.3f\n", delong$p.value))
oof_auc <- cvfit$cvm[cvfit$lambda == cvfit$lambda.1se]
cat(sprintf("AUC en validation croisée par cohorte (lambda 1se) : %.3f ; en validation 1997 : %.3f [%.3f ; %.3f]\n", oof_auc, perf$auc[1], perf$auc_lo[1], perf$auc_hi[1]))

# ---- 4) Population complète (KO + score) : PD pour tous les prêts, bandes, politique d'octroi -----------------------
all_X <- apply_prep(d, prep)
d$pd <- as.numeric(predict(fit, all_X, type = "response"))
# Prêts KO : PD "non modélisée" -> 1 par construction de la règle (100 % de défaut observé dans la base, cf. dq)
d$pd_model <- d$pd; d$pd <- ifelse(d$ko, 1, d$pd)
cuts <- make_bands(d$pd_model[d$sample == "train" & !d$ko], 4)
d$band <- as.character(band_of(d$pd_model, cuts)); d$band[d$ko] <- "KO"
bands_te <- band_table(d %>% filter(sample == "test", !ko) %>% mutate(pd = pd_model))
bands_tr <- band_table(d %>% filter(sample == "train", !ko) %>% mutate(pd = pd_model))
cat("\nBandes (validation 1997, hors KO) :\n"); print(bands_te, row.names = FALSE)

full_te <- d %>% filter(sample == "test")
cut_ref <- unname(quantile(d$pd_model[d$sample == "train" & !d$ko], 0.80))   # seuil de référence fixé sur l'apprentissage : refus des 20 % les plus risqués du périmètre
grid_c <- sort(unique(c(quantile(d$pd_model[d$sample == "train" & !d$ko], seq(0.5, 0.95, 0.05)), cut_ref)))
policy_te <- policy_table(full_te %>% mutate(pd = ifelse(ko, 1, pd_model)), grid_c, LGD)
policy_te$is_reference <- policy_te$cutoff == cut_ref
cat("\nPolitique d'octroi, validation 1997 (KO + seuil de PD) :\n"); print(round(policy_te, 3), row.names = FALSE)
policy_ko_only <- policy_table(full_te %>% mutate(pd = 0), 0.5, LGD)

out <- list(d = d, coefs = coefs, perf = perf, bands_te = bands_te, bands_tr = bands_tr, policy_te = policy_te,
            ko_tab = ko_tab, cut_ref = cut_ref, cuts = cuts, prep = prep, alpha = best, lambda = cvfit$lambda.1se,
            cv_auc = cv_auc, oof_auc = oof_auc, delong_p = delong$p.value, roc_s = roc_s, roc_c = roc_c,
            n_train = nrow(tr), bad_train = sum(tr$y), n_test = nrow(te), bad_test = sum(te$y),
            policy_ko_only = policy_ko_only, test_full = full_te)
saveRDS(out, file.path(DIR_CACHE, "model.rds"))
write.csv(d %>% select(loan_id, loan_date, vintage_year, sample, ko, is_bad, amount_czk, duration_months, ead_at_default_czk, pd_model, pd, band),
          file.path(DIR_OUT, "scored_loans.csv"), row.names = FALSE)
cat("\nModèle enregistré.\n")
