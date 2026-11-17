# Fonctions réutilisables (testées dans tests/testthat) : métriques de discrimination, intervalles de confiance,
# prétraitement ajusté sur l'apprentissage uniquement, tableaux de bandes de risque et de seuil de décision.

gini_from_auc <- function(auc) 2 * auc - 1

# Statistique de Kolmogorov-Smirnov entre les scores des défaillants et des non-défaillants
ks_stat <- function(y, p) {
  stopifnot(length(y) == length(p), all(y %in% c(0, 1)))
  if (length(unique(y)) < 2) return(NA_real_)
  thr <- sort(unique(p))
  max(abs(ecdf(p[y == 1])(thr) - ecdf(p[y == 0])(thr)))
}

# AUC par rang (équivalent Mann-Whitney), sans dépendance : sert aussi de test de pROC
auc_rank <- function(y, p) {
  n1 <- sum(y == 1); n0 <- sum(y == 0)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  r <- rank(p)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

# Bootstrap stratifié (on rééchantillonne séparément défaillants et sains) : intervalle percentile
boot_ci <- function(y, p, stat = auc_rank, n_boot = 2000, level = 0.95, seed = 42) {
  set.seed(seed)
  i1 <- which(y == 1); i0 <- which(y == 0)
  v <- replicate(n_boot, { idx <- c(sample(i1, replace = TRUE), sample(i0, replace = TRUE)); stat(y[idx], p[idx]) })
  a <- (1 - level) / 2
  c(est = stat(y, p), lo = unname(quantile(v, a, na.rm = TRUE)), hi = unname(quantile(v, 1 - a, na.rm = TRUE)))
}

# Prétraitement : tous les paramètres (bornes de winsorisation, médianes, moyennes, écarts-types) sont estimés sur
# l'APPRENTISSAGE puis appliqués tels quels à la validation et aux cohortes récentes (aucune fuite de distribution).
feature_spec <- function() {
  c("log_amount", "duration_months", "payment_to_inflow", "log_inflow", "log_avg_balance", "log_min_balance",
    "cash_share", "log_n_tx", "log_account_age", "has_disponent", "has_card_before", "unemployment_96_pct", "log_salary")
}

raw_features <- function(d, prep = NULL) {
  q99 <- if (is.null(prep)) NA else prep$q99_p2i
  med_cash <- if (is.null(prep)) NA else prep$med_cash
  p2i <- d$monthly_payment_czk / pmax(d$inflow_month_90d, 1)
  data.frame(
    log_amount = log(d$amount_czk), duration_months = d$duration_months,
    payment_to_inflow = if (is.null(prep)) p2i else pmin(p2i, q99),
    log_inflow = log(pmax(d$inflow_month_90d, 1)),
    log_avg_balance = log1p(pmax(d$avg_balance_90d, 0)), log_min_balance = log1p(pmax(d$min_balance_90d, 0)),
    cash_share = if (is.null(prep)) d$cash_withdrawal_share_90d else ifelse(is.na(d$cash_withdrawal_share_90d), med_cash, d$cash_withdrawal_share_90d),
    log_n_tx = log1p(d$n_tx_90d), log_account_age = log1p(d$account_age_months),
    has_disponent = as.numeric(d$has_disponent), has_card_before = as.numeric(d$has_card_before),
    unemployment_96_pct = d$unemployment_96_pct, log_salary = log(d$avg_salary_czk))
}

fit_prep <- function(d_train) {
  p2i <- d_train$monthly_payment_czk / pmax(d_train$inflow_month_90d, 1)
  prep <- list(q99_p2i = unname(quantile(p2i, 0.99)), med_cash = median(d_train$cash_withdrawal_share_90d, na.rm = TRUE))
  X <- raw_features(d_train, prep)[, feature_spec()]
  prep$center <- colMeans(X); prep$scale <- apply(X, 2, sd); prep$scale[prep$scale == 0] <- 1
  prep
}

apply_prep <- function(d, prep) {
  X <- as.matrix(raw_features(d, prep)[, feature_spec()])
  sweep(sweep(X, 2, prep$center, "-"), 2, prep$scale, "/")
}

# Bandes de risque : bornes fixées sur les scores de l'apprentissage, appliquées ensuite à toute population
make_bands <- function(p_train, n_bands = 4) unique(quantile(p_train, seq(0, 1, length.out = n_bands + 1), names = FALSE))
band_of <- function(p, cuts) {
  cuts[1] <- -Inf; cuts[length(cuts)] <- Inf
  cut(p, cuts, labels = paste0("B", seq_len(length(cuts) - 1)), include.lowest = TRUE)
}
band_table <- function(df, band_col = "band") {
  do.call(rbind, lapply(split(df, df[[band_col]]), function(g) data.frame(
    band = g[[band_col]][1], n = nrow(g), n_bad = sum(g$is_bad), bad_rate = mean(g$is_bad),
    mean_pd = mean(g$pd), amount_czk = sum(g$amount_czk), ead_bad_czk = sum(g$ead_at_default_czk[g$is_bad], na.rm = TRUE))))
}

# Simulation d'une politique d'octroi : refus automatique (KO) + refus si PD au-dessus du seuil.
# Pertes évitées = EAD au défaut x LGD des prêts défaillants refusés ; aucun revenu n'est inventé (cf. simulateur Excel).
policy_table <- function(df, cutoffs, lgd = 0.45) {
  do.call(rbind, lapply(cutoffs, function(c) {
    refused <- df$ko | df$pd > c
    app <- df[!refused, ]; ref <- df[refused, ]
    data.frame(cutoff = c, approval_rate = nrow(app) / nrow(df), n_approved = nrow(app),
               bad_rate_approved = if (nrow(app)) mean(app$is_bad) else NA_real_,
               bad_refused = sum(ref$is_bad), good_refused = sum(!ref$is_bad),
               loss_avoided_czk = lgd * sum(ref$ead_at_default_czk[ref$is_bad], na.rm = TRUE),
               good_refused_amount_czk = sum(ref$amount_czk[!ref$is_bad]))
  }))
}
