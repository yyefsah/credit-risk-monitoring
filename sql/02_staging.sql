-- Typage, traduction des codes tchèques, décodage des dates et du numéro de naissance.
-- Dates source au format AAMMJJ (années 1993-1998 => préfixe 19).
CREATE FUNCTION stg.yymmdd(t text) RETURNS date LANGUAGE sql IMMUTABLE AS
$$ SELECT to_date('19' || lpad(split_part(trim(t), ' ', 1), 6, '0'), 'YYYYMMDD') $$;

CREATE TABLE stg.district AS
SELECT a1::int AS district_id, a2 AS district_name, a3 AS region, a4::int AS inhabitants,
       a10::numeric AS urban_ratio_pct, a11::int AS avg_salary_czk,
       NULLIF(a12, '?')::numeric AS unemployment_95_pct, a13::numeric AS unemployment_96_pct,
       a14::int AS entrepreneurs_per_1000,
       NULLIF(a15, '?')::int AS crimes_95, a16::int AS crimes_96
FROM raw.district;

CREATE TABLE stg.account AS
SELECT account_id::int, district_id::int,
       CASE frequency WHEN 'POPLATEK MESICNE' THEN 'monthly' WHEN 'POPLATEK TYDNE' THEN 'weekly'
                      WHEN 'POPLATEK PO OBRATU' THEN 'after_transaction' ELSE 'unknown' END AS statement_frequency,
       stg.yymmdd(date) AS opened_date
FROM raw.account;

CREATE TABLE stg.client AS
SELECT client_id::int, district_id::int,
       CASE WHEN substr(birth_number, 3, 2)::int > 50 THEN 'F' ELSE 'M' END AS gender,
       make_date(1900 + substr(birth_number, 1, 2)::int,
                 CASE WHEN substr(birth_number, 3, 2)::int > 50 THEN substr(birth_number, 3, 2)::int - 50
                      ELSE substr(birth_number, 3, 2)::int END,
                 substr(birth_number, 5, 2)::int) AS birth_date
FROM raw.client;

CREATE TABLE stg.disp AS
SELECT disp_id::int, client_id::int, account_id::int, lower(type) AS disp_type FROM raw.disp;

CREATE TABLE stg.loan AS
SELECT loan_id::int, account_id::int, stg.yymmdd(date) AS loan_date, amount::numeric AS amount_czk,
       duration::int AS duration_months, payments::numeric AS monthly_payment_czk, status,
       status IN ('B', 'D') AS is_bad,          -- B = terminé non remboursé, D = en cours, impayés
       status IN ('A', 'B') AS is_finished      -- A/B = contrat terminé ; C/D = en cours
FROM raw.loan;

CREATE TABLE stg.card AS
SELECT card_id::int, disp_id::int, type AS card_type, stg.yymmdd(issued) AS issued_date FROM raw.card;

CREATE TABLE stg."order" AS
SELECT order_id::int, account_id::int, amount::numeric AS amount_czk,
       CASE k_symbol WHEN 'POJISTNE' THEN 'insurance' WHEN 'SIPO' THEN 'household' WHEN 'LEASING' THEN 'leasing'
                     WHEN 'UVER' THEN 'loan_payment' ELSE 'other' END AS purpose
FROM raw."order";

CREATE TABLE stg.trans AS
SELECT trans_id::bigint, account_id::int, stg.yymmdd(date) AS tx_date,
       CASE type WHEN 'PRIJEM' THEN 'credit' ELSE 'debit' END AS tx_type,           -- VYDAJ et VYBER = débits
       CASE operation WHEN 'VKLAD' THEN 'cash_deposit' WHEN 'PREVOD Z UCTU' THEN 'incoming_transfer'
                      WHEN 'VYBER' THEN 'cash_withdrawal' WHEN 'VYBER KARTOU' THEN 'card_withdrawal'
                      WHEN 'PREVOD NA UCET' THEN 'outgoing_transfer' ELSE 'other' END AS operation,
       amount::numeric AS amount_czk, balance::numeric AS balance_czk,
       CASE NULLIF(trim(k_symbol), '') WHEN 'POJISTNE' THEN 'insurance' WHEN 'SLUZBY' THEN 'statement_fee'
            WHEN 'UROK' THEN 'interest_credited' WHEN 'SANKC. UROK' THEN 'penalty_interest'
            WHEN 'SIPO' THEN 'household' WHEN 'DUCHOD' THEN 'pension' WHEN 'UVER' THEN 'loan_payment'
            ELSE NULL END AS purpose,
       CASE WHEN type = 'PRIJEM' THEN amount::numeric ELSE -amount::numeric END AS signed_amount_czk
FROM raw.trans;

CREATE INDEX ON stg.trans (account_id, tx_date, trans_id);
ANALYZE stg.trans;
