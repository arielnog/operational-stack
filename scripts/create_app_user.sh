#!/bin/bash
# =============================================================
#  create_app_user.sh
#  Cria um novo schema + usuário dedicado no PostgreSQL
#
#  Uso:
#    ./scripts/create_app_user.sh <app_name> <password>
#
#  Exemplo:
#    ./scripts/create_app_user.sh minha_api SenhaForte123!
#
#  Isso cria:
#    - Schema: minha_api
#    - Usuário: minha_api_user
#    - Permissões restritas apenas ao schema minha_api
# =============================================================

set -euo pipefail

APP_NAME="${1:-}"
APP_PASSWORD="${2:-}"

if [[ -z "$APP_NAME" || -z "$APP_PASSWORD" ]]; then
  echo "❌ Uso: $0 <app_name> <password>"
  exit 1
fi

DB_USER="${POSTGRES_USER:-admin}"
DB_NAME="${POSTGRES_DB:-main}"
APP_USER="${APP_NAME}_user"
SCHEMA="${APP_NAME}"

echo "🔧 Criando schema '$SCHEMA' e usuário '$APP_USER' no banco '$DB_NAME'..."

docker exec -i postgres psql -U "$DB_USER" -d "$DB_NAME" <<EOF

-- Criar usuário
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_USER}') THEN
    CREATE USER ${APP_USER} WITH ENCRYPTED PASSWORD '${APP_PASSWORD}';
    RAISE NOTICE 'Usuário ${APP_USER} criado.';
  ELSE
    ALTER USER ${APP_USER} WITH ENCRYPTED PASSWORD '${APP_PASSWORD}';
    RAISE NOTICE 'Usuário ${APP_USER} já existia — senha atualizada.';
  END IF;
END
\$\$;

-- Criar schema
CREATE SCHEMA IF NOT EXISTS ${SCHEMA} AUTHORIZATION ${APP_USER};

-- Revogar acesso ao schema public (segurança)
REVOKE ALL ON SCHEMA public FROM ${APP_USER};

-- Garantir acesso total ao próprio schema
GRANT ALL PRIVILEGES ON SCHEMA ${SCHEMA} TO ${APP_USER};

-- Permissões para objetos futuros no schema
ALTER DEFAULT PRIVILEGES IN SCHEMA ${SCHEMA}
  GRANT ALL PRIVILEGES ON TABLES TO ${APP_USER};

ALTER DEFAULT PRIVILEGES IN SCHEMA ${SCHEMA}
  GRANT ALL PRIVILEGES ON SEQUENCES TO ${APP_USER};

ALTER DEFAULT PRIVILEGES IN SCHEMA ${SCHEMA}
  GRANT EXECUTE ON FUNCTIONS TO ${APP_USER};

-- Definir search_path padrão do usuário
ALTER USER ${APP_USER} SET search_path TO ${SCHEMA};

-- Conectar ao banco
GRANT CONNECT ON DATABASE ${DB_NAME} TO ${APP_USER};

\echo '✅ Schema e usuário criados com sucesso!'
\echo 'Host:     postgres (interno Docker) ou localhost:5432 (via túnel)'
\echo 'Banco:    ${DB_NAME}'
\echo 'Schema:   ${SCHEMA}'
\echo 'Usuário:  ${APP_USER}'
\echo 'Senha:    ${APP_PASSWORD}'

EOF

echo ""
echo "✅ Pronto! String de conexão para a aplicação:"
echo "   postgresql://${APP_USER}:${APP_PASSWORD}@postgres:5432/${DB_NAME}?search_path=${SCHEMA}"
