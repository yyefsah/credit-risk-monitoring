suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(scales) })
source("R/00_config.R"); source("R/functions.R"); source("R/theme_viz.R")
marts <- readRDS(file.path(DIR_CACHE, "marts.rds")); m <- readRDS(file.path(DIR_CACHE, "model.rds"))
src <- "Source : base bancaire tchèque PKDD'99 (1993-1998)."
src_exp <- paste(src, "Encours estimé par amortissement linéaire (hypothèse).")

# 1) Portefeuille mensuel : trois panneaux, trois unités, aucun double axe
pm <- marts$portfolio_monthly %>% filter(month_end >= as.Date("1993-12-31")) %>%
  transmute(month_end, `Encours estimé (M CZK)` = outstanding_czk / 1e6, `Part de l'encours en défaut (%)` = 100 * npl_ratio,
            `Coût du risque proxy, 12 mois glissants (%)` = 100 * cost_of_risk_12m_proxy) %>%
  pivot_longer(-month_end) %>% mutate(name = factor(name, levels = unique(name)))
p1 <- ggplot(pm, aes(month_end, value)) + geom_line(colour = PAL["blue"], linewidth = 0.9) +
  facet_wrap(~name, ncol = 1, scales = "free_y") + labs(title = "Portefeuille de prêts : encours, encours en défaut et coût du risque", x = NULL, y = NULL,
  subtitle = "Coût du risque = EAD des nouveaux défauts x LGD (hypothèse 45 %) / encours moyen", caption = src_exp) + theme_bank()
save_fig(p1, "fig1_portfolio.png", 9, 7.5)

# 2) Cohortes : défaut cumulé par ancienneté (estimateur actuariel ; points avec >= 15 prêts à risque)
v <- marts$vintage %>% filter(n_at_risk >= 15) %>% mutate(vintage = ifelse(vintage_year == 1998, "1998 (immature)", as.character(vintage_year)))
lab <- v %>% group_by(vintage) %>% slice_max(months_on_book, n = 1)
cols <- setNames(unname(PAL[1:6]), c("1993", "1994", "1995", "1996", "1997", "1998 (immature)"))
p2 <- ggplot(v, aes(months_on_book, 100 * cum_default_rate, colour = vintage, linetype = vintage == "1998 (immature)")) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.8) +
  geom_text(data = lab, aes(label = vintage), hjust = -0.1, size = 3.3, show.legend = FALSE, colour = INK) +
  scale_colour_manual(values = cols) + scale_linetype_manual(values = c("solid", "dashed"), guide = "none") +
  scale_x_continuous(breaks = seq(0, 60, 12), expand = expansion(mult = c(0.02, 0.15))) +
  labs(title = "Défaut cumulé par cohorte d'octroi", x = "Mois depuis l'octroi", y = "Prêts défaillants (%)", colour = NULL,
       subtitle = "Défaut = premier solde négatif depuis l'octroi (proxy). Estimateur actuariel par pas de 3 mois.", caption = src) + theme_bank()
save_fig(p2, "fig2_vintages.png", 9, 5)

# 3) ROC hors période
rocdf <- function(r, nm) data.frame(fpr = 1 - r$specificities, tpr = r$sensitivities, model = nm)
perf <- m$perf
nm <- c(sprintf("Score (AUC %.2f [%.2f-%.2f])", perf$auc[1], perf$auc_lo[1], perf$auc_hi[1]),
        sprintf("Conditions du contrat seules (AUC %.2f [%.2f-%.2f])", perf$auc[2], perf$auc_lo[2], perf$auc_hi[2]))
R <- bind_rows(rocdf(m$roc_s, nm[1]), rocdf(m$roc_c, nm[2]))
p3 <- ggplot(R, aes(fpr, tpr, colour = model)) + geom_abline(slope = 1, intercept = 0, colour = GRID, linewidth = 0.5) +
  geom_step(linewidth = 1) + scale_colour_manual(values = setNames(unname(PAL[1:2]), nm)) + coord_equal() +
  labs(title = "Discrimination hors période (cohorte 1997, hors règle KO)", x = "Taux de faux positifs", y = "Taux de vrais positifs", colour = NULL,
       subtitle = sprintf("n = %d prêts dont %d défaillants : l'intervalle de confiance (bootstrap 95 %%) est large.", m$n_test, m$bad_test), caption = src) +
  theme_bank() + theme(legend.direction = "vertical")
save_fig(p3, "fig3_roc_test.png", 7.5, 6.5)

# 4) Taux de défaut par bande (validation 1997) + prêts KO
ko_te <- m$test_full %>% filter(ko) %>% summarise(band = "KO", n = n(), n_bad = sum(is_bad), bad_rate = mean(is_bad))
bt <- bind_rows(m$bands_te %>% select(band, n, n_bad, bad_rate), ko_te) %>% mutate(band = factor(band, levels = c(sort(setdiff(band, "KO")), "KO")))
p4 <- ggplot(bt, aes(band, 100 * bad_rate)) + geom_col(fill = PAL["blue"], width = 0.55) +
  geom_text(aes(label = sprintf("%d / %d", n_bad, n)), vjust = -0.5, colour = INK, size = 3.6) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(title = "Taux de défaut par bande de risque, cohorte 1997", x = "B1 = moins risqué ... B4 = plus risqué ; KO = compte à découvert avant l'octroi", y = "Prêts défaillants (%)",
       subtitle = "Étiquettes : défaillants / prêts. Bornes des bandes fixées sur l'apprentissage 1993-1996.", caption = src) + theme_bank()
save_fig(p4, "fig4_bands.png", 8, 5)

# 5) Politique d'octroi
pol <- m$policy_te %>% mutate(ref = ifelse(is_reference, "Seuil de référence (80e centile de l'apprentissage)", "Autres seuils"))
p5a <- ggplot(pol, aes(100 * approval_rate, 100 * bad_rate_approved, colour = ref, size = is_reference)) + geom_line(aes(group = 1), colour = GRID, linewidth = 0.6) + geom_point() +
  scale_colour_manual(values = c(PAL[["orange"]], PAL[["blue"]]), breaks = c("Seuil de référence (80e centile de l'apprentissage)", "Autres seuils")) +
  scale_size_manual(values = c(2, 4), guide = "none") +
  labs(title = "Politique d'octroi simulée sur la cohorte 1997 (règle KO + seuil de PD)", x = "Taux d'acceptation (%)", y = "Taux de défaut parmi les prêts acceptés (%)", colour = NULL,
       subtitle = "Plus le seuil est strict, plus le taux de défaut des prêts acceptés baisse, au prix de bons dossiers refusés.", caption = src) + theme_bank()
save_fig(p5a, "fig5_policy.png", 8.5, 5)

# 6) Coefficients (variables standardisées)
lab_var <- c(cash_share = "Part des retraits en espèces (90 j)", log_min_balance = "Solde minimum (90 j, log)", has_disponent = "Compte avec co-titulaire/mandataire",
             log_account_age = "Ancienneté du compte (log)", payment_to_inflow = "Mensualité / entrées mensuelles", log_n_tx = "Nombre d'opérations (90 j, log)",
             log_avg_balance = "Solde moyen (90 j, log)", log_amount = "Montant du prêt (log)", unemployment_96_pct = "Chômage du district 1996",
             duration_months = "Durée", log_inflow = "Entrées mensuelles (log)", has_card_before = "Carte avant octroi", log_salary = "Salaire moyen du district (log)")
cf <- m$coefs %>% mutate(label = factor(lab_var[variable], levels = rev(lab_var[variable])), sign = ifelse(coef > 0, "Augmente le risque", "Diminue le risque")) %>% filter(abs(coef) > 0)
p6 <- ggplot(cf, aes(coef, label, fill = sign)) + geom_col(width = 0.6) + geom_vline(xintercept = 0, colour = INK2, linewidth = 0.4) +
  scale_fill_manual(values = c("Augmente le risque" = PAL[["orange"]], "Diminue le risque" = PAL[["blue"]])) +
  labs(title = "Variables du score et sens de leur effet", x = "Coefficient (variables standardisées, régression logistique pénalisée)", y = NULL, fill = NULL,
       subtitle = "Variables à coefficient nul (écartées par la pénalisation) non affichées. Lecture indicative : variables corrélées.", caption = src) + theme_bank()
save_fig(p6, "fig6_coefficients.png", 9, 5)

# 7) Segments
sk <- marts$segment_kpi %>% filter(dimension %in% c("Durée", "Montant (CZK)", "Région")) %>%
  mutate(label = sprintf("%d / %d", n_bad, n_loans), segment = factor(segment, levels = unique(segment[order(dimension, segment)])))
p7 <- ggplot(sk, aes(100 * bad_rate, reorder(segment, -as.integer(segment)))) + geom_col(fill = PAL["blue"], width = 0.6) +
  geom_text(aes(label = label), hjust = -0.15, colour = INK, size = 3.2) +
  geom_vline(xintercept = 100 * 76 / 682, colour = PAL["orange"], linetype = "dashed") +
  facet_grid(dimension ~ ., scales = "free_y", space = "free_y") + scale_x_continuous(expand = expansion(mult = c(0, 0.18))) +
  labs(title = "Taux de défaut par segment (tous prêts, 1993-1998)", x = "Prêts défaillants (%) ; trait orange = moyenne du portefeuille (11,1 %)", y = NULL,
       subtitle = "Étiquettes : défaillants / prêts. Cohortes récentes en partie non mûries.", caption = src) + theme_bank()
save_fig(p7, "fig7_segments.png", 9, 8)
cat("Figures OK :", paste(list.files(DIR_FIG), collapse = ", "), "\n")
