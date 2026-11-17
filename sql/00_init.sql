-- Schémas : raw (tel que reçu) -> stg (typé, nettoyé, libellés traduits) -> mart (tables d'analyse) ; dq (contrôles qualité)
DROP SCHEMA IF EXISTS raw CASCADE;
DROP SCHEMA IF EXISTS stg CASCADE;
DROP SCHEMA IF EXISTS mart CASCADE;
DROP SCHEMA IF EXISTS dq CASCADE;
CREATE SCHEMA raw;
CREATE SCHEMA stg;
CREATE SCHEMA mart;
CREATE SCHEMA dq;
