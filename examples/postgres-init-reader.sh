#!/bin/bash
# =============================================================
#  Cria usuário read-only para o Metabase
#  Copie para: sua-app/postgres-init/01_create_reader.sh
#  Troque minha_api_reader pelo nome da sua app.
#
#  No compose da app, passe a senha para o container do banco:
#    environment:
#      DB_READER_PASSWORD: ${DB_READER_PASSWORD}
#
#  Roda só na 1ª inicialização do volume (docker-entrypoint-initdb.d).
#  ALTER DEFAULT PRIVILEGES cobre as tabelas criadas depois pelas
#  migrations (feitas pelo POSTGRES_USER).
# =============================================================
set -e

if [ -z "${DB_READER_PASSWORD}" ]; then
  echo "DB_READER_PASSWORD vazio, pulando criação do usuário reader"
  exit 0
fi

# A senha vai como variável do psql (:'reader_password') para não quebrar com aspas.
psql -v ON_ERROR_STOP=1 -v reader_password="${DB_READER_PASSWORD}" --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER minha_api_reader WITH PASSWORD :'reader_password';
  GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO minha_api_reader;
  GRANT USAGE ON SCHEMA public TO minha_api_reader;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO minha_api_reader;
  ALTER DEFAULT PRIVILEGES FOR ROLE ${POSTGRES_USER} IN SCHEMA public GRANT SELECT ON TABLES TO minha_api_reader;
EOSQL
