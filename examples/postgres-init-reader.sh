#!/bin/bash
# =============================================================
#  Cria usuário read-only para o Metabase
#  Copie para: sua-app/postgres-init/01_create_reader.sh
#  Substitua {app}_reader e SENHA_READER pelos valores reais
# =============================================================
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER minha_api_reader WITH PASSWORD 'SENHA_READER_AQUI';
  GRANT CONNECT ON DATABASE minha_api TO minha_api_reader;
  GRANT USAGE ON SCHEMA public TO minha_api_reader;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO minha_api_reader;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO minha_api_reader;
EOSQL
