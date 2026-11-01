-- Apply manually as PostgreSQL administrator before deploying this recipe.
-- Creates only the lobehub role/database and the required extension.
-- Existing role passwords and application data are never reset.
\set ON_ERROR_STOP on

SELECT 'CREATE ROLE lobehub LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lobehub')
\gexec

DO $bootstrap$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = 'lobehub' AND rolcanlogin
      AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
      AND NOT rolreplication AND NOT rolbypassrls
  ) THEN
    RAISE EXCEPTION 'Refusing to use an existing lobehub role with unexpected privileges';
  END IF;
END;
$bootstrap$;

SELECT 'CREATE DATABASE lobehub OWNER lobehub'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'lobehub')
\gexec

DO $bootstrap$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_database
    WHERE datname = 'lobehub' AND pg_get_userbyid(datdba) <> 'lobehub'
  ) THEN
    RAISE EXCEPTION 'Refusing to use an existing lobehub database owned by another role';
  END IF;
END;
$bootstrap$;

\connect lobehub
CREATE EXTENSION IF NOT EXISTS vector;
