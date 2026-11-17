-- ============================================================================
-- MARTS : tables d'analyse. Hypothèses métier regroupées dans mart.assumption (modifiables).
-- ============================================================================
CREATE TABLE mart.assumption (key text PRIMARY KEY, value numeric NOT NULL, comment text NOT NULL);
INSERT INTO mart.assumption VALUES
 ('lgd', 0.45, 'Perte en cas de défaut. HYPOTHÈSE (valeur réglementaire Bâle F-IRB, créance senior non garantie) : la base ne contient aucune donnée de recouvrement.'),
 ('data_end_date', 19981231, 'Date de fin de l''historique (AAAAMMJJ), observée sur la table des transactions.');

-- ----------------------------------------------------------------------------
-- 1) Un prêt = une ligne : contrat + titulaire + zone géographique + événement de défaut
-- Événement de défaut (proxy) : premier solde négatif à partir de la date d'octroi.
-- Dans la base, statut B/D <=> compte à découvert au moins une fois (vérifié en dq).
-- 12 prêts défaillants n'ont un découvert qu'AVANT l'octroi : date de défaut imputée = date d'octroi (hypothèse conservatrice, tracée).
-- ----------------------------------------------------------------------------
CREATE TABLE mart.loan_base AS
WITH owner AS (
  SELECT d.account_id, c.client_id, c.gender, c.birth_date, c.district_id AS client_district_id
  FROM stg.disp d JOIN stg.client c USING (client_id) WHERE d.disp_type = 'owner'),
first_neg AS (
  SELECT l.loan_id,
         min(t.tx_date) FILTER (WHERE t.tx_date >= l.loan_date) AS first_neg_after,
         bool_or(t.tx_date < l.loan_date)                       AS neg_before
  FROM stg.loan l JOIN stg.trans t ON t.account_id = l.account_id AND t.balance_czk < 0
  GROUP BY l.loan_id)
SELECT l.loan_id, l.account_id, o.client_id,
       l.loan_date, extract(year FROM l.loan_date)::int AS vintage_year,
       (l.loan_date + make_interval(months => l.duration_months))::date AS maturity_date,
       l.amount_czk, l.duration_months, l.monthly_payment_czk, l.status, l.is_bad, l.is_finished,
       CASE WHEN l.is_bad THEN COALESCE(f.first_neg_after, l.loan_date) END AS default_date,
       (l.is_bad AND f.first_neg_after IS NULL) AS default_date_imputed,
       -- exposition au défaut (EAD) : encours estimé (amortissement linéaire) à la date de défaut
       CASE WHEN l.is_bad THEN l.amount_czk * greatest(0, 1 - (COALESCE(f.first_neg_after, l.loan_date) - l.loan_date) / 30.4375 / l.duration_months) END AS ead_at_default_czk,
       a.district_id, di.district_name, di.region,
       o.gender, o.birth_date
FROM stg.loan l
JOIN stg.account a USING (account_id)
JOIN stg.district di ON di.district_id = a.district_id
JOIN owner o ON o.account_id = l.account_id
LEFT JOIN first_neg f ON f.loan_id = l.loan_id;
ALTER TABLE mart.loan_base ADD PRIMARY KEY (loan_id);

-- ----------------------------------------------------------------------------
-- 2) Variables connues À L'OCTROI uniquement (fenêtre strictement antérieure à loan_date).
--    Le genre n'est volontairement pas dans la table des variables : exclu de la modélisation.
--    La table des ordres permanents (non datée) et le solde post-octroi sont exclus : risque de fuite.
--    Agrégats à la journée (l'ordre intra-journalier de la source n'est pas fiable).
-- ----------------------------------------------------------------------------
CREATE TABLE mart.loan_features AS
SELECT b.loan_id, b.loan_date, b.vintage_year, b.is_bad,
  b.amount_czk, b.duration_months, b.monthly_payment_czk,
  (b.loan_date - a.opened_date) / 30.4375                                        AS account_age_months,
  a.statement_frequency,
  extract(year FROM age(b.loan_date, b.birth_date))::int                          AS age_at_loan,
  di.urban_ratio_pct, di.avg_salary_czk, di.unemployment_96_pct, di.entrepreneurs_per_1000,
  (SELECT count(*) FROM stg.disp d WHERE d.account_id = b.account_id AND d.disp_type = 'disponent') > 0 AS has_disponent,
  EXISTS (SELECT 1 FROM stg.card ca JOIN stg.disp d USING (disp_id)
          WHERE d.account_id = b.account_id AND ca.issued_date < b.loan_date)    AS has_card_before,
  h.n_tx_90d, h.inflow_month_90d, h.outflow_month_90d, h.avg_balance_90d, h.min_balance_90d,
  h.cash_withdrawal_share_90d,
  h.n_days_negative_before AS n_neg_balance_days_before, h.last_tx_used
FROM mart.loan_base b
JOIN stg.account  a  USING (account_id)
JOIN stg.district di ON di.district_id = b.district_id
LEFT JOIN LATERAL (
  SELECT count(*) FILTER (WHERE t.tx_date >= b.loan_date - 90)                                                    AS n_tx_90d,
         coalesce(sum(t.amount_czk) FILTER (WHERE t.tx_type='credit' AND t.tx_date >= b.loan_date - 90), 0) / 3.0 AS inflow_month_90d,
         coalesce(sum(t.amount_czk) FILTER (WHERE t.tx_type='debit'  AND t.tx_date >= b.loan_date - 90), 0) / 3.0 AS outflow_month_90d,
         avg(t.balance_czk)  FILTER (WHERE t.tx_date >= b.loan_date - 90)                                         AS avg_balance_90d,
         min(t.balance_czk)  FILTER (WHERE t.tx_date >= b.loan_date - 90)                                         AS min_balance_90d,
         coalesce(sum(t.amount_czk) FILTER (WHERE t.operation='cash_withdrawal' AND t.tx_date >= b.loan_date - 90), 0)
           / NULLIF(sum(t.amount_czk) FILTER (WHERE t.tx_type='debit' AND t.tx_date >= b.loan_date - 90), 0)      AS cash_withdrawal_share_90d,
         count(DISTINCT t.tx_date) FILTER (WHERE t.balance_czk < 0)                                               AS n_days_negative_before,
         max(t.tx_date)                                                                                           AS last_tx_used
  FROM stg.trans t WHERE t.account_id = b.account_id AND t.tx_date < b.loan_date) h ON true;
ALTER TABLE mart.loan_features ADD PRIMARY KEY (loan_id);

-- ----------------------------------------------------------------------------
-- 3) Photographie mensuelle du portefeuille (fonctions de fenêtre + generate_series)
--    Encours estimé par amortissement linéaire (aucun échéancier dans la base : HYPOTHÈSE).
-- ----------------------------------------------------------------------------
CREATE TABLE mart.portfolio_monthly AS
WITH months AS (
  SELECT (date_trunc('month', d) + interval '1 month - 1 day')::date AS month_end
  FROM generate_series('1993-01-01'::date, '1998-12-01'::date, interval '1 month') d),
exp AS (
  SELECT m.month_end, b.loan_id, b.is_bad, b.default_date, b.amount_czk,
         greatest(0, 1 - (m.month_end - b.loan_date) / 30.4375 / b.duration_months) * b.amount_czk AS outstanding
  FROM months m JOIN mart.loan_base b ON b.loan_date <= m.month_end AND b.maturity_date > m.month_end),
agg AS (
  SELECT m.month_end,
         count(e.loan_id)                                                   AS n_live_loans,
         coalesce(sum(e.outstanding), 0)                                    AS outstanding_czk,
         coalesce(sum(e.outstanding) FILTER (WHERE e.default_date <= m.month_end), 0) AS defaulted_outstanding_czk,
         count(e.loan_id) FILTER (WHERE e.default_date <= m.month_end)      AS n_defaulted_live,
         (SELECT count(*) FROM mart.loan_base b WHERE b.loan_date > m.month_end - interval '1 month' AND b.loan_date <= m.month_end) AS n_originated,
         (SELECT coalesce(sum(b.amount_czk),0) FROM mart.loan_base b WHERE b.loan_date > m.month_end - interval '1 month' AND b.loan_date <= m.month_end) AS originated_czk,
         (SELECT count(*) FROM mart.loan_base b WHERE b.default_date > m.month_end - interval '1 month' AND b.default_date <= m.month_end) AS n_new_defaults,
         (SELECT coalesce(sum(b.ead_at_default_czk),0) FROM mart.loan_base b WHERE b.default_date > m.month_end - interval '1 month' AND b.default_date <= m.month_end) AS new_default_ead_czk
  FROM months m LEFT JOIN exp e USING (month_end) GROUP BY m.month_end)
SELECT month_end, n_live_loans, outstanding_czk, defaulted_outstanding_czk, n_defaulted_live,
       defaulted_outstanding_czk / NULLIF(outstanding_czk, 0) AS npl_ratio,
       n_originated, originated_czk, n_new_defaults, new_default_ead_czk,
       -- coût du risque proxy, glissant 12 mois : EAD des nouveaux défauts * LGD / encours moyen
       -- (aucun défaut ni encours avant fin 1993 : valeurs partielles les 11 premiers mois)
       sum(new_default_ead_czk) OVER r12 * (SELECT value FROM mart.assumption WHERE key = 'lgd')
         / NULLIF(avg(outstanding_czk) OVER r12, 0) AS cost_of_risk_12m_proxy
FROM agg
WINDOW r12 AS (ORDER BY month_end ROWS BETWEEN 11 PRECEDING AND CURRENT ROW);

-- ----------------------------------------------------------------------------
-- 4) Cohortes (vintages) : défaut cumulé par ancienneté, estimateur actuariel (table de survie, pas de 3 mois)
--    Un prêt sort du risque à son échéance (remboursé) ou à la fin des données (censure) ; les prêts censurés
--    en cours d'intervalle comptent pour la moitié. Évite le biais des cohortes récentes non mûries.
-- ----------------------------------------------------------------------------
CREATE TABLE mart.vintage AS
WITH b AS (
  SELECT vintage_year, is_bad,
         CASE WHEN is_bad THEN (default_date - loan_date) / 30.4375 END AS months_to_default,
         LEAST((date '1998-12-31' - loan_date) / 30.4375, duration_months) AS months_exit   -- fin d'observation ou échéance
  FROM mart.loan_base),
iv AS (
  SELECT b.vintage_year, g.m AS months_on_book, CASE WHEN g.m = 0 THEN -1 ELSE g.m - 3 END AS lb,
         b.is_bad, b.months_to_default, b.months_exit, g.m
  FROM b CROSS JOIN (SELECT generate_series(0, 60, 3) AS m) g),
cnt AS (
  SELECT vintage_year, months_on_book,
         count(*) FILTER (WHERE (is_bad AND months_to_default > lb) OR (NOT is_bad AND months_exit > lb))                    AS n_at_risk,
         count(*) FILTER (WHERE is_bad AND months_to_default > lb AND months_to_default <= m)                                 AS n_defaulted_interval,
         count(*) FILTER (WHERE NOT is_bad AND months_exit > lb AND months_exit <= m)                                         AS n_censored_interval
  FROM iv GROUP BY vintage_year, months_on_book),
haz AS (
  SELECT *, n_defaulted_interval / NULLIF(n_at_risk - n_censored_interval / 2.0, 0) AS hazard FROM cnt)
SELECT vintage_year, months_on_book, n_at_risk, n_censored_interval, n_defaulted_interval,
       sum(n_defaulted_interval) OVER (PARTITION BY vintage_year ORDER BY months_on_book) AS n_defaulted_cum,
       coalesce(hazard, 0) AS hazard,
       1 - exp(sum(ln(1 - least(coalesce(hazard, 0), 0.999999))) OVER (PARTITION BY vintage_year ORDER BY months_on_book)) AS cum_default_rate
FROM haz
WHERE n_at_risk > 0;

-- ----------------------------------------------------------------------------
-- 5) Indicateurs par segment (GROUPING SETS) : taux de défaut, montants, exposition défaillante
-- ----------------------------------------------------------------------------
CREATE TABLE mart.segment_kpi AS
SELECT coalesce(dim, 'Total') AS dimension, coalesce(segment, 'Total') AS segment,
       count(*) AS n_loans, sum(is_bad::int) AS n_bad,
       sum(is_bad::int)::numeric / count(*) AS bad_rate,
       sum(amount_czk) AS amount_czk, sum(amount_czk) FILTER (WHERE is_bad) AS bad_amount_czk,
       sum(amount_czk) FILTER (WHERE is_bad) / sum(amount_czk) AS bad_amount_share
FROM (SELECT b.*,
        CASE WHEN duration_months <= 12 THEN '12 mois' ELSE (duration_months || ' mois') END AS dur_seg,
        CASE WHEN amount_czk < 50000 THEN '1. < 50 k' WHEN amount_czk < 150000 THEN '2. 50-150 k'
             WHEN amount_czk < 250000 THEN '3. 150-250 k' ELSE '4. >= 250 k' END AS amount_seg,
        CASE WHEN vintage_year = 1998 THEN '1998 (immature)' ELSE vintage_year::text END AS vint_seg
      FROM mart.loan_base b) s,
LATERAL (VALUES ('Durée', dur_seg), ('Montant (CZK)', amount_seg), ('Région', region), ('Cohorte', vint_seg)) v(dim, segment)
GROUP BY ROLLUP ((dim, segment));
