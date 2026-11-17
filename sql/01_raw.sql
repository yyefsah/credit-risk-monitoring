-- Chargement brut : tout en texte, aucune transformation. Exécuter depuis la racine du projet.
CREATE TABLE raw.account  (account_id text, district_id text, frequency text, date text);
CREATE TABLE raw.client   (client_id text, birth_number text, district_id text);
CREATE TABLE raw.disp     (disp_id text, client_id text, account_id text, type text);
CREATE TABLE raw.district (a1 text, a2 text, a3 text, a4 text, a5 text, a6 text, a7 text, a8 text, a9 text,
                           a10 text, a11 text, a12 text, a13 text, a14 text, a15 text, a16 text);
CREATE TABLE raw.loan     (loan_id text, account_id text, date text, amount text, duration text, payments text, status text);
CREATE TABLE raw.card     (card_id text, disp_id text, type text, issued text);
CREATE TABLE raw."order"  (order_id text, account_id text, bank_to text, account_to text, amount text, k_symbol text);
CREATE TABLE raw.trans    (trans_id text, account_id text, date text, type text, operation text, amount text,
                           balance text, k_symbol text, bank text, account text);

\copy raw.account  FROM 'data/account.asc'  WITH (FORMAT csv, DELIMITER ';', HEADER true)
\copy raw.client   FROM 'data/client.asc'   WITH (FORMAT csv, DELIMITER ';', HEADER true)
\copy raw.disp     FROM 'data/disp.asc'     WITH (FORMAT csv, DELIMITER ';', HEADER true)
\copy raw.district FROM 'data/district.asc' WITH (FORMAT csv, DELIMITER ';', HEADER true)
\copy raw.loan     FROM 'data/loan.asc'     WITH (FORMAT csv, DELIMITER ';', HEADER true)
\copy raw.card     FROM 'data/card.asc'     WITH (FORMAT csv, DELIMITER ';', HEADER true)
\copy raw."order"  FROM 'data/order.asc'    WITH (FORMAT csv, DELIMITER ';', HEADER true)
\copy raw.trans    FROM 'data/trans.asc'    WITH (FORMAT csv, DELIMITER ';', HEADER true)
