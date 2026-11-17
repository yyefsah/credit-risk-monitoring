-- ============================================================================
-- CONTRÔLES QUALITÉ : chaque test écrit une ligne dans dq.result (n_failed = 0 => OK).
-- severity 'error' = bloque le pipeline (run.sh échoue) ; 'warning' = documenté, non bloquant ; 'info' = constat.
-- ============================================================================
CREATE TABLE dq.result (
  check_id serial PRIMARY KEY, layer text, check_name text, description text, severity text,
  n_checked bigint, n_failed bigint, passed boolean GENERATED ALWAYS AS (n_failed = 0) STORED);

CREATE FUNCTION dq.log(layer text, name text, descr text, sev text, n_checked bigint, n_failed bigint)
RETURNS void LANGUAGE sql AS $$ INSERT INTO dq.result(layer, check_name, description, severity, n_checked, n_failed)
VALUES (layer, name, descr, sev, n_checked, n_failed) $$;

\o /dev/null
-- Complétude : aucune ligne perdue entre la source brute et la couche typée
SELECT dq.log('staging','rowcount_loan','Lignes brut = typé (loan)','error',(SELECT count(*) FROM raw.loan),abs((SELECT count(*) FROM raw.loan)-(SELECT count(*) FROM stg.loan)));
SELECT dq.log('staging','rowcount_trans','Lignes brut = typé (trans)','error',(SELECT count(*) FROM raw.trans),abs((SELECT count(*) FROM raw.trans)-(SELECT count(*) FROM stg.trans)));
SELECT dq.log('staging','rowcount_account','Lignes brut = typé (account)','error',(SELECT count(*) FROM raw.account),abs((SELECT count(*) FROM raw.account)-(SELECT count(*) FROM stg.account)));
SELECT dq.log('staging','rowcount_client','Lignes brut = typé (client)','error',(SELECT count(*) FROM raw.client),abs((SELECT count(*) FROM raw.client)-(SELECT count(*) FROM stg.client)));

-- Cohérence des contrats
SELECT dq.log('staging','loan_one_per_account','Un seul prêt par compte','error',count(*),count(*)-count(DISTINCT account_id)) FROM stg.loan;
SELECT dq.log('staging','loan_payment_x_duration','mensualité x durée = montant (tolérance d''arrondi)','error',count(*),
              count(*) FILTER (WHERE abs(monthly_payment_czk*duration_months - amount_czk) > duration_months)) FROM stg.loan;
SELECT dq.log('staging','loan_after_account_open','Prêt octroyé après l''ouverture du compte','error',count(*),
              count(*) FILTER (WHERE l.loan_date < a.opened_date)) FROM stg.loan l JOIN stg.account a USING (account_id);
SELECT dq.log('staging','account_one_owner','Chaque compte a exactement un titulaire (OWNER)','error',count(*),count(*) FILTER (WHERE n<>1))
  FROM (SELECT account_id, count(*) FILTER (WHERE disp_type='owner') n FROM stg.disp GROUP BY 1) z;
-- Anomalie réelle de la source (anonymisation) : 30 prêts rattachés à un titulaire mineur. Conservés, signalés, non bloquants.
SELECT dq.log('staging','client_age_plausible','Âge du titulaire à l''octroi entre 18 et 100 ans (30 titulaires de 13-17 ans dans la source : conservés, signalés)','warning',count(*),
              count(*) FILTER (WHERE age_at_loan NOT BETWEEN 18 AND 100)) FROM mart.loan_features;
SELECT dq.log('staging','trans_dates_in_range','Transactions entre 1993-01-01 et 1998-12-31','error',count(*),
              count(*) FILTER (WHERE tx_date NOT BETWEEN '1993-01-01' AND '1998-12-31')) FROM stg.trans;

-- Réconciliation comptable : solde de fin de journée = cumul des mouvements (l'ordre intra-journalier de la source n'est pas fiable)
SELECT dq.log('staging','balance_reconciliation_daily','Un solde enregistré chaque jour égale le cumul des mouvements (écart <= 5 CZK, arrondis d''intérêts)','error',count(*),count(*) FILTER (WHERE mind > 5))
FROM (WITH day AS (SELECT account_id, tx_date, sum(signed_amount_czk) net FROM stg.trans GROUP BY 1,2),
           c AS (SELECT account_id, tx_date, sum(net) OVER (PARTITION BY account_id ORDER BY tx_date) cum FROM day)
      SELECT c.account_id, c.tx_date, min(abs(t.balance_czk - c.cum)) mind
      FROM c JOIN stg.trans t ON t.account_id=c.account_id AND t.tx_date=c.tx_date GROUP BY 1,2) q;

-- Valeurs manquantes connues (information, non bloquant)
SELECT dq.log('staging','district_missing_unemployment_95','Districts sans taux de chômage 1995 (valeur "?" dans la source)','info',count(*),count(*) FILTER (WHERE unemployment_95_pct IS NULL)) FROM stg.district;

-- Définition de la cible : statut B/D <=> compte à découvert au moins une fois
SELECT dq.log('marts','label_equals_ever_overdrawn','is_bad <=> solde négatif au moins une fois sur le compte','error',count(*),
              count(*) FILTER (WHERE b.is_bad IS DISTINCT FROM EXISTS (SELECT 1 FROM stg.trans t WHERE t.account_id=b.account_id AND t.balance_czk<0))) FROM mart.loan_base b;
SELECT dq.log('marts','default_date_imputed','Prêts défaillants dont la date de défaut est imputée (découvert uniquement avant octroi)','warning',count(*) FILTER (WHERE is_bad),count(*) FILTER (WHERE default_date_imputed)) FROM mart.loan_base;

-- Grain et cohérence des marts
SELECT dq.log('marts','loan_base_grain','mart.loan_base : une ligne par prêt','error',(SELECT count(*) FROM stg.loan),abs((SELECT count(*) FROM stg.loan)-(SELECT count(*) FROM mart.loan_base)));
SELECT dq.log('marts','vintage_consistency','Cohortes : taux dans [0,1], croissants avec l''ancienneté, n_at_risk au mois 0 = prêts de la cohorte','error',count(*),
   count(*) FILTER (WHERE cum_default_rate NOT BETWEEN 0 AND 1 OR cum_default_rate < coalesce(prev, 0) - 1e-12
                    OR (months_on_book = 0 AND n_at_risk <> (SELECT count(*) FROM mart.loan_base b WHERE b.vintage_year = v.vintage_year))))
FROM (SELECT *, lag(cum_default_rate) OVER (PARTITION BY vintage_year ORDER BY months_on_book) AS prev FROM mart.vintage) v;
SELECT dq.log('marts','vintage_defaults_match','Défauts cumulés de la cohorte (dernier pas) = défauts observés du portefeuille','error',(SELECT count(*) FROM mart.loan_base WHERE is_bad),
   abs((SELECT count(*) FROM mart.loan_base WHERE is_bad) - (SELECT sum(n_defaulted_cum) FROM (SELECT DISTINCT ON (vintage_year) vintage_year, n_defaulted_cum FROM mart.vintage ORDER BY vintage_year, months_on_book DESC) z)::bigint));
SELECT dq.log('marts','npl_ratio_bounds','Taux d''encours défaillant dans [0,1]','error',count(*),count(*) FILTER (WHERE npl_ratio < 0 OR npl_ratio > 1)) FROM mart.portfolio_monthly;
SELECT dq.log('marts','segment_totals','Somme des segments d''une dimension = total prêts','error',(SELECT count(*) FROM stg.loan),
   (SELECT count(*) FROM (SELECT dimension, sum(n_loans) s FROM mart.segment_kpi WHERE dimension <> 'Total' GROUP BY 1 HAVING sum(n_loans) <> (SELECT count(*) FROM stg.loan)) x));

-- Anti-fuite : aucune variable du modèle n'utilise d'information à partir de la date d'octroi
SELECT dq.log('marts','no_leakage_features_window','Dernière transaction utilisée par les variables < date d''octroi','error',count(*),
              count(*) FILTER (WHERE last_tx_used >= loan_date)) FROM mart.loan_features;
SELECT dq.log('marts','features_no_null','Variables du modèle sans valeur manquante (hors part des retraits et soldes 90j si aucune opération)','warning',count(*),
              count(*) FILTER (WHERE n_tx_90d = 0 OR cash_withdrawal_share_90d IS NULL)) FROM mart.loan_features;

\o
-- Sortie : la table des résultats ; échec bloquant si une erreur
\echo ''
SELECT check_id, layer, check_name, severity, n_checked, n_failed, CASE WHEN passed THEN 'OK' WHEN severity='error' THEN 'ÉCHEC' ELSE 'à noter' END AS status FROM dq.result ORDER BY check_id;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM dq.result WHERE severity = 'error' AND NOT passed) THEN
    RAISE EXCEPTION 'Contrôles qualité en échec : %', (SELECT string_agg(check_name, ', ') FROM dq.result WHERE severity='error' AND NOT passed);
  END IF; END $$;
