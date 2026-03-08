#!/bin/bash
# =============================================================
#  02_create_services.sh — Cria bancos e usuários para serviços
#  Executado automaticamente na 1ª inicialização do Postgres
#  Usa variáveis de ambiente passadas pelo docker-compose
# =============================================================

set -e

# Variáveis vindas do docker-compose environment
DB_USER="${POSTGRES_USER:-admin}"

echo "🔧 Criando bancos e usuários dos serviços..."

# =============================================================
# METABASE
# =============================================================
echo "  → Criando banco e usuário do Metabase..."
psql -v ON_ERROR_STOP=1 --username "$DB_USER" --dbname "${POSTGRES_DB:-main}" <<-EOSQL
  -- Criar banco se não existir
  SELECT 'CREATE DATABASE ${METABASE_DB:-metabase}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${METABASE_DB:-metabase}')
  \gexec

  -- Criar usuário se não existir
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${METABASE_DB_USER:-metabase_user}') THEN
      CREATE USER ${METABASE_DB_USER:-metabase_user} WITH ENCRYPTED PASSWORD '${METABASE_DB_PASSWORD}';
    END IF;
  END
  \$\$;

  GRANT ALL PRIVILEGES ON DATABASE ${METABASE_DB:-metabase} TO ${METABASE_DB_USER:-metabase_user};
EOSQL

psql -v ON_ERROR_STOP=1 --username "$DB_USER" --dbname "${METABASE_DB:-metabase}" <<-EOSQL
  GRANT ALL ON SCHEMA public TO ${METABASE_DB_USER:-metabase_user};
EOSQL

echo "  ✅ Metabase OK"

# =============================================================
# GRAFANA
# =============================================================
echo "  → Criando banco e usuário do Grafana..."
psql -v ON_ERROR_STOP=1 --username "$DB_USER" --dbname "${POSTGRES_DB:-main}" <<-EOSQL
  SELECT 'CREATE DATABASE ${GRAFANA_DB:-grafana}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${GRAFANA_DB:-grafana}')
  \gexec

  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${GRAFANA_DB_USER:-grafana_user}') THEN
      CREATE USER ${GRAFANA_DB_USER:-grafana_user} WITH ENCRYPTED PASSWORD '${GRAFANA_DB_PASSWORD}';
    END IF;
  END
  \$\$;

  GRANT ALL PRIVILEGES ON DATABASE ${GRAFANA_DB:-grafana} TO ${GRAFANA_DB_USER:-grafana_user};
EOSQL

psql -v ON_ERROR_STOP=1 --username "$DB_USER" --dbname "${GRAFANA_DB:-grafana}" <<-EOSQL
  GRANT ALL ON SCHEMA public TO ${GRAFANA_DB_USER:-grafana_user};
EOSQL

echo "  ✅ Grafana OK"

# =============================================================
# Schema de exemplo no banco principal
# =============================================================
psql -v ON_ERROR_STOP=1 --username "$DB_USER" --dbname "${POSTGRES_DB:-main}" <<-EOSQL
  CREATE SCHEMA IF NOT EXISTS app_example;
EOSQL

echo "🎉 Todos os bancos e usuários criados com sucesso!"
