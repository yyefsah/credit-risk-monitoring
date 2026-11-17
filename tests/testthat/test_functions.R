source("../../R/functions.R")

test_that("auc_rank vaut 1 pour un classement parfait et 0.5 pour des scores constants", {
  y <- c(0, 0, 0, 1, 1); expect_equal(auc_rank(y, c(.1, .2, .3, .8, .9)), 1)
  expect_equal(auc_rank(y, rep(.5, 5)), 0.5); expect_equal(auc_rank(y, c(.9, .8, .7, .2, .1)), 0)
})
test_that("auc_rank est identique à pROC", {
  skip_if_not_installed("pROC"); set.seed(1); y <- rbinom(200, 1, .2); p <- runif(200) + .3 * y
  expect_equal(auc_rank(y, p), as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE, direction = "<"))))
})
test_that("ks_stat est 1 si séparation parfaite, 0 si distributions identiques", {
  expect_equal(ks_stat(c(0, 0, 1, 1), c(.1, .2, .8, .9)), 1); expect_equal(ks_stat(c(0, 1, 0, 1), c(.1, .1, .5, .5)), 0)
})
test_that("gini = 2 AUC - 1", expect_equal(gini_from_auc(0.9), 0.8))
test_that("boot_ci : intervalle encadrant l'estimation, reproductible", {
  set.seed(3); y <- rbinom(150, 1, .25); p <- runif(150) + .4 * y
  a <- boot_ci(y, p, n_boot = 300, seed = 7); b <- boot_ci(y, p, n_boot = 300, seed = 7)
  expect_equal(a, b); expect_lte(a[["lo"]], a[["est"]]); expect_gte(a[["hi"]], a[["est"]])
})
test_that("prétraitement : paramètres estimés sur l'apprentissage seulement (pas de fuite)", {
  mk <- function(n, shift = 0) data.frame(amount_czk = runif(n, 1e4, 3e5) + shift, duration_months = sample(c(12, 24, 36), n, TRUE), monthly_payment_czk = runif(n, 1e3, 8e3),
    inflow_month_90d = runif(n, 5e3, 6e4), avg_balance_90d = runif(n, 1e3, 5e4), min_balance_90d = runif(n, 0, 2e4), cash_withdrawal_share_90d = runif(n),
    n_tx_90d = rpois(n, 20), account_age_months = runif(n, 1, 60), has_disponent = runif(n) < .2, has_card_before = runif(n) < .05, unemployment_96_pct = runif(n, 1, 7), avg_salary_czk = runif(n, 8e3, 12e3))
  set.seed(5); tr <- mk(200); te <- mk(50, shift = 5e5)
  prep <- fit_prep(tr); Xtr <- apply_prep(tr, prep); Xte <- apply_prep(te, prep)
  expect_equal(unname(colMeans(Xtr)), rep(0, ncol(Xtr)), tolerance = 1e-8)
  expect_gt(mean(Xte[, "log_amount"]), 1)    # la validation décalée reste décalée : elle n'est pas recentrée
  expect_identical(colnames(Xtr), feature_spec())
})
test_that("bandes de risque : bornes de l'apprentissage, toute valeur est classée", {
  cuts <- make_bands(c(.01, .02, .05, .1, .2, .4, .6, .8), 4); b <- band_of(c(0, .03, .5, 1), cuts)
  expect_false(anyNA(b)); expect_equal(as.character(b[c(1, 4)]), c("B1", "B4"))
})
test_that("politique d'octroi : cohérence des comptages et monotonie", {
  df <- data.frame(is_bad = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE), ko = c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE), pd = c(1, .6, .3, .1, .05, .02),
                   ead_at_default_czk = c(1000, 2000, NA, NA, NA, NA), amount_czk = rep(10000, 6))
  p <- policy_table(df, c(.5, .2, .08), lgd = .5)
  expect_equal(p$n_approved + p$bad_refused + p$good_refused, rep(6, 3))
  expect_equal(p$bad_refused, c(2, 2, 2)); expect_equal(p$good_refused, c(0, 1, 2)); expect_equal(p$loss_avoided_czk, rep(1500, 3))
  expect_true(all(diff(p$approval_rate) <= 0))
})
