-- =============================================================
--  init.sql — Executado automaticamente na 1ª inicialização
--  Cria extensões no banco principal
-- =============================================================

-- Extensões úteis no banco principal
\connect main;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";
