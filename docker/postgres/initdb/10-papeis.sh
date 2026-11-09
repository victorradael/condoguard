#!/bin/sh
# Roda uma única vez, quando o volume do Postgres está vazio.
#
# Papéis:
# - postgres          superusuário, só para administração e backup
# - condoguard_owner  dono do banco e do esquema; roda as migrações
# - condoguard_app    usado pela API em execução; sem SUPERUSER e sem BYPASSRLS,
#                     então as políticas de RLS (1b) valem para ele
set -eu

psql -v ON_ERROR_STOP=1 \
	--username "$POSTGRES_USER" \
	--dbname "$POSTGRES_DB" \
	-v owner_pw="$POSTGRES_OWNER_PASSWORD" \
	-v app_pw="$POSTGRES_APP_PASSWORD" <<'SQL'
CREATE ROLE condoguard_owner LOGIN PASSWORD :'owner_pw'
	NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE condoguard_app LOGIN PASSWORD :'app_pw'
	NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

ALTER DATABASE condoguard OWNER TO condoguard_owner;
REVOKE ALL ON DATABASE condoguard FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE condoguard TO condoguard_app;

ALTER SCHEMA public OWNER TO condoguard_owner;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO condoguard_app;

-- Tudo o que as migrações criarem já nasce acessível à API, sem DDL.
ALTER DEFAULT PRIVILEGES FOR ROLE condoguard_owner IN SCHEMA public
	GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO condoguard_app;
ALTER DEFAULT PRIVILEGES FOR ROLE condoguard_owner IN SCHEMA public
	GRANT USAGE, SELECT ON SEQUENCES TO condoguard_app;
ALTER DEFAULT PRIVILEGES FOR ROLE condoguard_owner IN SCHEMA public
	GRANT EXECUTE ON FUNCTIONS TO condoguard_app;
SQL
