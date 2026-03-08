-- =============================================================
--  init.sql — Executado automaticamente na 1ª inicialização
--  Cria bancos, schemas e usuários para cada serviço
-- =============================================================

-- Extensões úteis no banco principal
\connect main;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- =============================================================
-- METABASE
-- =============================================================
CREATE DATABASE metabase;
CREATE USER metabase_user WITH ENCRYPTED PASSWORD :'METABASE_DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE metabase TO metabase_user;
\connect metabase;
GRANT ALL ON SCHEMA public TO metabase_user;

-- =============================================================
-- GRAFANA
-- =============================================================
CREATE DATABASE grafana;
CREATE USER grafana_user WITH ENCRYPTED PASSWORD :'GRAFANA_DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana_user;
\connect grafana;
GRANT ALL ON SCHEMA public TO grafana_user;

-- =============================================================
-- Voltar ao banco principal para criar schemas de aplicações
-- =============================================================
\connect main;

-- Schema para cada futura aplicação (exemplos)
-- As aplicações usam o mesmo banco 'main' mas schemas isolados
CREATE SCHEMA IF NOT EXISTS app_example;

-- Usuário de exemplo para uma aplicação
-- (use o script create_app_user.sh para criar novos)
