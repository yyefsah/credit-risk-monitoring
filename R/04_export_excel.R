# Classeur de pilotage Excel : synthèse, hypothèses modifiables, simulateur de seuil à formules vivantes, cohortes, segments, qualité.
suppressPackageStartupMessages({ library(openxlsx); library(dplyr); library(tidyr) })
source("R/00_config.R"); source("R/functions.R")
marts <- readRDS(file.path(DIR_CACHE, "marts.rds")); m <- readRDS(file.path(DIR_CACHE, "model.rds"))
wb <- createWorkbook(creator = "Y. Yefsah"); modifyBaseFont(wb, fontSize = 10, fontName = "Calibri")
NAVY <- "#1F3A5F"; hdr <- createStyle(fontColour = "#FFFFFF", fgFill = NAVY, textDecoration = "bold", halign = "center", valign = "center", wrapText = TRUE, border = "TopBottomLeftRight", borderColour = "#B8C2CC")
title <- createStyle(fontSize = 16, textDecoration = "bold", fontColour = NAVY); sub <- createStyle(fontColour = "#52514e", wrapText = TRUE, valign = "top")
inp <- createStyle(fgFill = "#FFF4CC", border = "TopBottomLeftRight", borderColour = "#C9A227", textDecoration = "bold")
pct1 <- createStyle(numFmt = "0.0%"); pct2 <- createStyle(numFmt = "0.00%"); int0 <- createStyle(numFmt = "#,##0"); dec3 <- createStyle(numFmt = "0.000"); dat <- createStyle(numFmt = "yyyy-mm-dd")
lab <- createStyle(textDecoration = "bold"); note <- createStyle(fontColour = "#52514e", fontSize = 9, wrapText = TRUE, valign = "top")
write_tbl <- function(sheet, df, r0, c0 = 1) { writeData(wb, sheet, df, startRow = r0, startCol = c0, headerStyle = hdr, borders = "rows", borderColour = "#E6E5E1"); addStyle(wb, sheet, hdr, rows = r0, cols = c0:(c0 + ncol(df) - 1), gridExpand = TRUE); setRowHeights(wb, sheet, r0, 32) }

d  <- m$d; te <- m$test_full; pm <- marts$portfolio_monthly; last <- pm[nrow(pm), ]
tot_bad <- sum(d$is_bad); n_all <- nrow(d)

# ---------------------------------------------------------------- Hypothèses (cellules d'entrée nommées)
addWorksheet(wb, "Hypothèses", tabColour = "#C9A227")
writeData(wb, "Hypothèses", "Hypothèses et paramètres de décision", startCol = 1, startRow = 1); addStyle(wb, "Hypothèses", title, rows = 1, cols = 1)
writeData(wb, "Hypothèses", data.frame(Paramètre = c("LGD (perte en cas de défaut)", "Marge nette annuelle sur encours (illustratif)", "Seuil de PD : refus au-dessus", "Règle KO active (1 = oui, 0 = non)"),
  Valeur = c(LGD, 0.03, round(m$cut_ref, 4), 1),
  Commentaire = c("HYPOTHÈSE : valeur réglementaire Bâle F-IRB (créance senior non garantie). La base ne contient aucune donnée de recouvrement.",
                  "ILLUSTRATIF, non issu des données : à remplacer par la marge réelle de la banque. Sert seulement au solde net du simulateur.",
                  "Par défaut : 80e centile des PD de l'apprentissage 1993-1996 (fixé sans regarder la cohorte 1997).",
                  "KO = compte déjà à découvert avant l'octroi (refus automatique).")), startRow = 3, headerStyle = hdr)
addStyle(wb, "Hypothèses", inp, rows = 4:7, cols = 2); addStyle(wb, "Hypothèses", pct1, rows = 4:5, cols = 2); addStyle(wb, "Hypothèses", dec3, rows = 6, cols = 2)
addStyle(wb, "Hypothèses", sub, rows = 4:7, cols = 3, gridExpand = TRUE)
setColWidths(wb, "Hypothèses", cols = 1:3, widths = c(46, 14, 95)); setRowHeights(wb, "Hypothèses", 4:7, 30)
createNamedRegion(wb, "Hypothèses", cols = 2, rows = 4, name = "LGD"); createNamedRegion(wb, "Hypothèses", cols = 2, rows = 5, name = "MARGE")
createNamedRegion(wb, "Hypothèses", cols = 2, rows = 6, name = "SEUIL"); createNamedRegion(wb, "Hypothèses", cols = 2, rows = 7, name = "KO_ON")
writeData(wb, "Hypothèses", "Cellules jaunes = modifiables ; le simulateur et la feuille Scoring_1997 se recalculent.", startRow = 9)

# ---------------------------------------------------------------- Scoring_1997 (une ligne par prêt, formules en colonnes calculées)
addWorksheet(wb, "Scoring_1997")
sc <- te %>% arrange(loan_id) %>% transmute(`Prêt` = loan_id, Cohorte = vintage_year, `Montant (CZK)` = amount_czk, `Durée (mois)` = duration_months,
                                             `Défaillant (0/1)` = as.integer(is_bad), `EAD au défaut (CZK)` = ifelse(is_bad, round(ead_at_default_czk), 0),
                                             `KO (0/1)` = as.integer(ko), `PD modèle` = round(pd_model, 5), Bande = band)
n <- nrow(sc); r1 <- 5; rN <- r1 + n - 1
writeData(wb, "Scoring_1997", "Cohorte 1997 : décision simulée prêt par prêt", startRow = 1); addStyle(wb, "Scoring_1997", title, rows = 1, cols = 1)
writeData(wb, "Scoring_1997", "Colonnes A-I = données et scores ; J-L = formules pilotées par la feuille Hypothèses. PD des prêts KO : valeur du modèle indicative (la règle KO prime).", startRow = 2)
write_tbl("Scoring_1997", sc, r1 - 1)
writeData(wb, "Scoring_1997", data.frame(`Refusé (0/1)` = NA, `Perte évitée (CZK)` = NA, `Marge perdue illustrative (CZK)` = NA, check.names = FALSE), startRow = r1 - 1, startCol = 10, headerStyle = hdr)
rows <- r1:rN
writeFormula(wb, "Scoring_1997", sprintf("IF(OR(AND(KO_ON=1,G%d=1),H%d>SEUIL),1,0)", rows, rows), startRow = r1, startCol = 10)
writeFormula(wb, "Scoring_1997", sprintf("IF(AND(J%d=1,E%d=1),F%d*LGD,0)", rows, rows, rows), startRow = r1, startCol = 11)
writeFormula(wb, "Scoring_1997", sprintf("IF(AND(J%d=1,E%d=0),C%d*D%d/12*0.5*MARGE,0)", rows, rows, rows, rows), startRow = r1, startCol = 12)
addStyle(wb, "Scoring_1997", int0, rows = rows, cols = c(3, 6, 11, 12), gridExpand = TRUE); addStyle(wb, "Scoring_1997", dec3, rows = rows, cols = 8, gridExpand = TRUE)
setColWidths(wb, "Scoring_1997", cols = 1:12, widths = c(9, 9, 14, 10, 12, 16, 8, 10, 8, 11, 16, 20)); freezePane(wb, "Scoring_1997", firstActiveRow = r1)
addFilter(wb, "Scoring_1997", row = r1 - 1, cols = 1:12)
rg <- function(col) sprintf("Scoring_1997!$%s$%d:$%s$%d", col, r1, col, rN)

# ---------------------------------------------------------------- Simulateur (formules)
addWorksheet(wb, "Simulateur", tabColour = NAVY)
writeData(wb, "Simulateur", "Simulateur de politique d'octroi (cohorte 1997)", startRow = 1); addStyle(wb, "Simulateur", title, rows = 1, cols = 1)
writeData(wb, "Simulateur", "Modifiez le seuil de PD, la LGD ou la marge dans la feuille Hypothèses : tous les résultats ci-dessous se recalculent.", startRow = 2)
kp <- data.frame(Indicateur = c("Seuil de PD appliqué", "Règle KO active", "Prêts de la cohorte", "Prêts acceptés", "Taux d'acceptation", "Défaillants refusés", "Défaillants acceptés",
                                "Bons dossiers refusés", "Taux de défaut parmi les prêts acceptés", "Taux de défaut sans politique", "Perte évitée (EAD x LGD, CZK)", "Marge perdue sur bons dossiers refusés (illustrative, CZK)", "Solde net illustratif (CZK)"))
writeData(wb, "Simulateur", kp, startRow = 4, headerStyle = hdr); writeData(wb, "Simulateur", data.frame(Valeur = NA), startRow = 4, startCol = 2, headerStyle = hdr)
f <- c("SEUIL", "KO_ON", sprintf("COUNTA(%s)", rg("A")), sprintf("COUNTIF(%s,0)", rg("J")), "B9/B7", sprintf("COUNTIFS(%s,1,%s,1)", rg("J"), rg("E")),
       sprintf("COUNTIFS(%s,0,%s,1)", rg("J"), rg("E")), sprintf("COUNTIFS(%s,1,%s,0)", rg("J"), rg("E")), "IF(B8=0,0,B11/B8)", sprintf("SUM(%s)/B7", rg("E")),
       sprintf("SUM(%s)", rg("K")), sprintf("SUM(%s)", rg("L")), "B15-B16")
f[5] <- "B8/B7"; f[9] <- "IF(B8=0,0,B11/B8)"
writeFormula(wb, "Simulateur", f, startRow = 5, startCol = 2)
addStyle(wb, "Simulateur", dec3, rows = 5, cols = 2); addStyle(wb, "Simulateur", pct1, rows = c(9, 13, 14), cols = 2, gridExpand = TRUE); addStyle(wb, "Simulateur", int0, rows = c(7, 8, 10, 11, 12, 15, 16, 17), cols = 2, gridExpand = TRUE)
setColWidths(wb, "Simulateur", cols = 1:8, widths = c(58, 16, 16, 16, 16, 16, 18, 20))
# grille de seuils : formules indépendantes du seuil courant
g0 <- 21; writeData(wb, "Simulateur", "Grille de seuils (valeurs de PD prises sur les centiles de l'apprentissage ; formules vivantes)", startRow = g0 - 1); addStyle(wb, "Simulateur", lab, rows = g0 - 1, cols = 1)
grid <- data.frame(`Seuil de PD` = round(m$policy_te$cutoff, 4), check.names = FALSE)
grid[, c("Taux d'acceptation", "Prêts acceptés", "Taux de défaut des acceptés", "Défaillants refusés", "Bons dossiers refusés", "Perte évitée (CZK)")] <- NA
write_tbl("Simulateur", grid, g0)
gr <- (g0 + 1):(g0 + nrow(grid))
appr <- sprintf("IF(KO_ON=1,COUNTIFS(%s,0,%s,\"<=\"&A%d),COUNTIFS(%s,\"<=\"&A%d))", rg("G"), rg("H"), gr, rg("H"), gr)
appr_bad <- sprintf("IF(KO_ON=1,COUNTIFS(%s,0,%s,\"<=\"&A%d,%s,1),COUNTIFS(%s,\"<=\"&A%d,%s,1))", rg("G"), rg("H"), gr, rg("E"), rg("H"), gr, rg("E"))
writeFormula(wb, "Simulateur", sprintf("C%d/$B$7", gr), startRow = g0 + 1, startCol = 2)
writeFormula(wb, "Simulateur", appr, startRow = g0 + 1, startCol = 3)
writeFormula(wb, "Simulateur", sprintf("IF(C%d=0,0,%s/C%d)", gr, appr_bad, gr), startRow = g0 + 1, startCol = 4)
writeFormula(wb, "Simulateur", sprintf("SUM(%s)-%s", rg("E"), appr_bad), startRow = g0 + 1, startCol = 5)
writeFormula(wb, "Simulateur", sprintf("($B$7-C%d)-E%d", gr, gr), startRow = g0 + 1, startCol = 6)
writeFormula(wb, "Simulateur", sprintf("LGD*(SUMIFS(%s,%s,1)-IF(KO_ON=1,SUMIFS(%s,%s,1,%s,0,%s,\"<=\"&A%d),SUMIFS(%s,%s,1,%s,\"<=\"&A%d)))",
             rg("F"), rg("E"), rg("F"), rg("E"), rg("G"), rg("H"), gr, rg("F"), rg("E"), rg("H"), gr), startRow = g0 + 1, startCol = 7)
addStyle(wb, "Simulateur", dec3, rows = gr, cols = 1, gridExpand = TRUE); addStyle(wb, "Simulateur", pct1, rows = gr, cols = c(2, 4), gridExpand = TRUE); addStyle(wb, "Simulateur", int0, rows = gr, cols = c(3, 5, 6, 7), gridExpand = TRUE)
writeData(wb, "Simulateur", "Lecture : la perte évitée est une proxy (EAD estimée x LGD supposée). Aucun revenu n'est observé dans la base : le solde net dépend entièrement de la marge illustrative saisie.", startRow = g0 + nrow(grid) + 3)
addStyle(wb, "Simulateur", note, rows = g0 + nrow(grid) + 3, cols = 1)

# ---------------------------------------------------------------- Portefeuille mensuel
addWorksheet(wb, "Portefeuille")
writeData(wb, "Portefeuille", "Photographie mensuelle du portefeuille (encours estimé par amortissement linéaire)", startRow = 1); addStyle(wb, "Portefeuille", title, rows = 1, cols = 1)
pmx <- pm %>% transmute(`Fin de mois` = month_end, `Prêts en vie` = n_live_loans, `Encours (CZK)` = round(outstanding_czk), `Encours en défaut (CZK)` = round(defaulted_outstanding_czk),
                        `Part en défaut` = npl_ratio, `Prêts octroyés` = n_originated, `Montant octroyé (CZK)` = originated_czk, `Nouveaux défauts` = n_new_defaults,
                        `EAD nouveaux défauts (CZK)` = round(new_default_ead_czk), `Coût du risque proxy 12 m` = cost_of_risk_12m_proxy)
write_tbl("Portefeuille", pmx, 3); rr <- 4:(3 + nrow(pmx))
addStyle(wb, "Portefeuille", dat, rows = rr, cols = 1, gridExpand = TRUE); addStyle(wb, "Portefeuille", int0, rows = rr, cols = c(2, 3, 4, 6, 7, 9), gridExpand = TRUE); addStyle(wb, "Portefeuille", pct1, rows = rr, cols = c(5, 10), gridExpand = TRUE)
setColWidths(wb, "Portefeuille", cols = 1:10, widths = c(12, 10, 15, 16, 12, 11, 17, 11, 17, 16)); freezePane(wb, "Portefeuille", firstActiveRow = 4)
writeData(wb, "Portefeuille", "Coût du risque proxy = EAD des nouveaux défauts sur 12 mois x LGD / encours moyen ; valeurs partielles avant fin 1993+11 mois.", startRow = 3 + nrow(pmx) + 2)
insertImage(wb, "Portefeuille", file.path(DIR_FIG, "fig1_portfolio.png"), startRow = 3, startCol = 12, width = 8.5, height = 7, units = "in", dpi = 150)

# ---------------------------------------------------------------- Cohortes (taux cumulés, pivot)
addWorksheet(wb, "Cohortes")
writeData(wb, "Cohortes", "Défaut cumulé par cohorte et ancienneté (estimateur actuariel)", startRow = 1); addStyle(wb, "Cohortes", title, rows = 1, cols = 1)
vw <- marts$vintage %>% filter(n_at_risk >= 15) %>% select(vintage_year, months_on_book, cum_default_rate) %>% pivot_wider(names_from = vintage_year, values_from = cum_default_rate) %>% arrange(months_on_book)
names(vw)[1] <- "Mois depuis l'octroi"; names(vw)[-1] <- paste0("Cohorte ", names(vw)[-1], ifelse(names(vw)[-1] == "1998", " (immature)", ""))
write_tbl("Cohortes", vw, 3); addStyle(wb, "Cohortes", pct1, rows = 4:(3 + nrow(vw)), cols = 2:ncol(vw), gridExpand = TRUE)
conditionalFormatting(wb, "Cohortes", cols = 2:ncol(vw), rows = 4:(3 + nrow(vw)), type = "colourScale", style = c("#FFFFFF", "#2a78d6"))
setColWidths(wb, "Cohortes", cols = 1:ncol(vw), widths = c(18, rep(18, ncol(vw) - 1)))
writeData(wb, "Cohortes", "Cellules vides = moins de 15 prêts à risque à cette ancienneté (non affichées). Défaut = premier solde négatif depuis l'octroi (proxy).", startRow = 5 + nrow(vw))
insertImage(wb, "Cohortes", file.path(DIR_FIG, "fig2_vintages.png"), startRow = 8 + nrow(vw), startCol = 1, width = 8.5, height = 4.7, units = "in", dpi = 150)

# ---------------------------------------------------------------- Segments & bandes
addWorksheet(wb, "Segments")
writeData(wb, "Segments", "Indicateurs par segment (tous prêts 1993-1998)", startRow = 1); addStyle(wb, "Segments", title, rows = 1, cols = 1)
sk <- marts$segment_kpi %>% transmute(Dimension = dimension, Segment = segment, `Prêts` = n_loans, `Défaillants` = n_bad, `Taux de défaut` = bad_rate, `Montant (CZK)` = amount_czk, `Montant défaillant (CZK)` = bad_amount_czk, `Part du montant en défaut` = bad_amount_share)
write_tbl("Segments", sk, 3); rr <- 4:(3 + nrow(sk))
addStyle(wb, "Segments", pct1, rows = rr, cols = c(5, 8), gridExpand = TRUE); addStyle(wb, "Segments", int0, rows = rr, cols = c(3, 4, 6, 7), gridExpand = TRUE)
setColWidths(wb, "Segments", cols = 1:8, widths = c(16, 20, 10, 12, 14, 18, 22, 20)); freezePane(wb, "Segments", firstActiveRow = 4)
bt <- bind_rows(m$bands_te %>% mutate(Echantillon = "Validation 1997"), m$bands_tr %>% mutate(Echantillon = "Apprentissage 1993-1996")) %>%
  transmute(`Échantillon` = Echantillon, Bande = band, `Prêts` = n, `Défaillants` = n_bad, `Taux de défaut` = bad_rate, `PD moyenne` = mean_pd, `Montant (CZK)` = amount_czk)
writeData(wb, "Segments", "Bandes de risque du score (hors prêts KO ; bornes fixées sur l'apprentissage)", startRow = 6 + nrow(sk), startCol = 1); addStyle(wb, "Segments", lab, rows = 6 + nrow(sk), cols = 1)
write_tbl("Segments", bt, 7 + nrow(sk)); addStyle(wb, "Segments", pct1, rows = (8 + nrow(sk)):(7 + nrow(sk) + nrow(bt)), cols = c(5, 6), gridExpand = TRUE); addStyle(wb, "Segments", int0, rows = (8 + nrow(sk)):(7 + nrow(sk) + nrow(bt)), cols = 7, gridExpand = TRUE)

# ---------------------------------------------------------------- Qualité des données & dictionnaire
addWorksheet(wb, "Qualité données")
writeData(wb, "Qualité données", "Contrôles qualité exécutés en SQL (schéma dq)", startRow = 1); addStyle(wb, "Qualité données", title, rows = 1, cols = 1)
dq <- marts$dq_result %>% transmute(`N°` = check_id, Couche = layer, Contrôle = check_name, Description = description, Gravité = severity, `Éléments testés` = n_checked, `En échec` = n_failed,
                                    Statut = ifelse(passed, "OK", ifelse(severity == "error", "ÉCHEC", "À noter")))
write_tbl("Qualité données", dq, 3); setColWidths(wb, "Qualité données", cols = 1:8, widths = c(5, 10, 32, 90, 10, 14, 10, 10)); addStyle(wb, "Qualité données", sub, rows = 4:(3 + nrow(dq)), cols = 4, gridExpand = TRUE)
conditionalFormatting(wb, "Qualité données", cols = 8, rows = 4:(3 + nrow(dq)), rule = "=\"OK\"", style = createStyle(fontColour = "#006100", bgFill = "#C6EFCE"))
conditionalFormatting(wb, "Qualité données", cols = 8, rows = 4:(3 + nrow(dq)), rule = "=\"À noter\"", style = createStyle(fontColour = "#7F6000", bgFill = "#FFEB9C"))
conditionalFormatting(wb, "Qualité données", cols = 8, rows = 4:(3 + nrow(dq)), rule = "=\"ÉCHEC\"", style = createStyle(fontColour = "#9C0006", bgFill = "#FFC7CE"))

addWorksheet(wb, "Dictionnaire")
writeData(wb, "Dictionnaire", "Dictionnaire des principales mesures", startRow = 1); addStyle(wb, "Dictionnaire", title, rows = 1, cols = 1)
dic <- data.frame(Mesure = c("Défaut (proxy)", "Date de défaut", "EAD au défaut", "Part de l'encours en défaut", "Coût du risque proxy", "Règle KO", "PD modèle", "Bande de risque", "Cohorte immature"),
  Définition = c("Prêt au statut B ou D dans la base ; équivaut dans la base à un compte à découvert au moins une fois (contrôle label_equals_ever_overdrawn).",
                 "Premier solde négatif à partir de la date d'octroi ; imputée à la date d'octroi pour 12 prêts dont le découvert précède l'octroi.",
                 "Encours estimé à la date de défaut (montant x part non amortie, amortissement linéaire : aucun échéancier dans la base).",
                 "Encours estimé des prêts déjà en défaut / encours estimé total, en fin de mois.",
                 "Somme sur 12 mois glissants de l'EAD des nouveaux défauts x LGD (hypothèse) / encours moyen.",
                 "Refus automatique si le compte a été à découvert avant l'octroi (100 % de défaut observé dans la base).",
                 "Probabilité estimée par régression logistique pénalisée (variables observées avant l'octroi, fenêtre de 90 jours).",
                 "Quartiles de PD de l'apprentissage 1993-1996 : B1 = moins risqué, B4 = plus risqué.",
                 "Cohorte 1998 : moins de 12 mois d'observation en moyenne ; ses défauts à venir ne sont pas observés."))
write_tbl("Dictionnaire", dic, 3); setColWidths(wb, "Dictionnaire", cols = 1:2, widths = c(30, 120)); addStyle(wb, "Dictionnaire", sub, rows = 4:12, cols = 2, gridExpand = TRUE)

# ---------------------------------------------------------------- Synthèse (créée en dernier, placée en premier)
addWorksheet(wb, "Synthèse", tabColour = "#1baf7a")
writeData(wb, "Synthèse", "Pilotage du risque de crédit : synthèse", startRow = 1); addStyle(wb, "Synthèse", title, rows = 1, cols = 1)
writeData(wb, "Synthèse", "Portefeuille de 682 prêts d'une banque de détail tchèque (1993-1998, données réelles anonymisées PKDD'99). Détail des contrôles de qualité : feuille Qualité données.", startRow = 2)
perf <- m$perf; pol <- m$policy_te[m$policy_te$is_reference, ]
syn <- data.frame(Indicateur = c("Prêts (1993-1998)", "Prêts défaillants (proxy)", "Taux de défaut global", paste0("Encours estimé au ", format(last$month_end)), "Part de l'encours en défaut", "Coût du risque proxy, 12 mois",
                                 "Prêts KO (découvert avant octroi) : défaillants / prêts", "AUC du score, cohorte 1997 (IC 95 %)", "Taux d'acceptation au seuil de référence", "Taux de défaut des acceptés au seuil de référence"),
  Valeur = NA)
vals <- list(n_all, tot_bad, tot_bad / n_all, round(last$outstanding_czk), last$npl_ratio, last$cost_of_risk_12m_proxy,
             sprintf("%d / %d", sum(d$is_bad & d$ko), sum(d$ko)), sprintf("%.2f [%.2f ; %.2f]", perf$auc[1], perf$auc_lo[1], perf$auc_hi[1]), pol$approval_rate, pol$bad_rate_approved)
write_tbl("Synthèse", syn, 4); for (i in seq_along(vals)) writeData(wb, "Synthèse", vals[[i]], startRow = 4 + i, startCol = 2, colNames = FALSE)
addStyle(wb, "Synthèse", int0, rows = c(5, 6, 8), cols = 2); addStyle(wb, "Synthèse", pct1, rows = c(7, 9, 10, 13, 14), cols = 2, gridExpand = TRUE)
addStyle(wb, "Synthèse", createStyle(halign = "right"), rows = 5:14, cols = 2, gridExpand = TRUE, stack = TRUE)
setColWidths(wb, "Synthèse", cols = 1:2, widths = c(58, 24))
msg <- c(sprintf("1. Un compte à découvert avant l'octroi précède systématiquement un défaut dans cette base (%d prêts sur %d) : règle de refus simple, sans modèle.", sum(d$is_bad & d$ko), sum(d$ko)),
         sprintf("2. Hors règle KO, le score sépare bien les cohortes hors période (AUC %.2f), mais avec seulement %d défauts en validation l'intervalle est large [%.2f ; %.2f].", perf$auc[1], m$bad_test, perf$auc_lo[1], perf$auc_hi[1]),
         "3. Le défaut est mesuré par un découvert (proxy) : la performance est probablement supérieure à celle d'un vrai défaut de paiement. La cohorte 1998 est trop récente pour être jugée.")
writeData(wb, "Synthèse", "Messages clés", startRow = 16); addStyle(wb, "Synthèse", lab, rows = 16, cols = 1)
for (i in seq_along(msg)) { writeData(wb, "Synthèse", msg[i], startRow = 16 + i); mergeCells(wb, "Synthèse", cols = 1:2, rows = 16 + i); addStyle(wb, "Synthèse", sub, rows = 16 + i, cols = 1); setRowHeights(wb, "Synthèse", 16 + i, 32) }
insertImage(wb, "Synthèse", file.path(DIR_FIG, "fig4_bands.png"), startRow = 4, startCol = 4, width = 6, height = 3.75, units = "in", dpi = 150)
worksheetOrder(wb) <- c(which(names(wb) == "Synthèse"), which(names(wb) != "Synthèse"))
for (s in names(wb)) showGridLines(wb, s, FALSE)
saveWorkbook(wb, file.path(DIR_OUT, "pilotage_risque_credit.xlsx"), overwrite = TRUE)
cat("Excel OK\n")
