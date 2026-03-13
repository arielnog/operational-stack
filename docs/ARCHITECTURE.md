# VPS Infrastructure — Arquitetura de Referência

Prompt compilado com todas as decisões aprovadas para geração ou regeneração da stack de infraestrutura.

---

## Contexto

- Infraestrutura pessoal em VPS Ubuntu 24.04, baseada em Docker
- Stack gerenciada via Git (repositório privado)
- Desenvolvedor full-stack solo (Node e PHP)

---

## Decisões de arquitetura aprovadas

### Aplicações

| Decisão | Detalhe |
|---------|---------|
| Apps pessoais (Node/PHP) | Cada uma com seu próprio `docker-compose.yml` e banco dedicado |
| Apps third party (n8n, Outline, etc.) | Mesmo padrão — banco próprio no compose |
| Banco compartilhado | Nenhum banco global compartilhado entre apps |
| Isolamento | Cada app pode ser derrubada com `docker compose down` sem afetar o restante |

### Banco de dados

| Decisão | Detalhe |
|---------|---------|
| Por app | Cada app sobe seu próprio PostgreSQL no compose dela |
| Postgres global | Não existe Postgres global na infra |
| Metabase | Banco dedicado (sobe no compose da infra) |
| Metabase → apps | Cada banco expõe usuário `*_reader` (somente SELECT) na rede `infra_data` |

### Redis

| Decisão | Detalhe |
|---------|---------|
| Compartilhado | Um único Redis por toda a VPS, na infra |
| Isolamento | Por database number (DB 0 reservado, cada app usa um número dedicado) |
| Documentação | `redis/databases.md` no repositório |
| Redis dedicado | Apenas se a app exigir `noeviction` ou configuração incompatível |

### Metabase

| Decisão | Detalhe |
|---------|---------|
| Acesso | Exclusivamente leitura (visualização de dados das apps) |
| Escrita | Sem escrita, sem acesso externo direto ao banco |
| Conexão | Conecta nos bancos das apps via rede `infra_data` com usuário read-only |
| Cadastro | Cada banco como fonte de dados separada |

---

## Redes Docker

| Rede | Quem entra | Para quê |
|------|------------|----------|
| **traefik_public** | traefik, metabase, grafana, apps com rota pública | Roteamento externo via Traefik |
| **infra_internal** | loki, promtail, grafana, redis, apps pessoais | Comunicação interna da infra, acesso ao Redis |
| **infra_data** | metabase, bancos das apps (somente read-only) | Metabase lê os bancos sem porta exposta |
| ***_net** (por app) | app + banco dela | Comunicação interna exclusiva da app |

### Regras de rede

1. **A app nunca entra na infra_data** — só o banco dela entra
2. **Banco de cada app** fica em duas redes: `*_net` (acesso total da app) e `infra_data` (read-only para Metabase)
3. **Redis** fica em `infra_internal` — apps acessam por lá
4. **Nenhum banco** tem porta exposta para o host

---

## Diagrama de redes

```
                    ┌─────────────────────────────────────────────────┐
                    │                  Internet                        │
                    └────────────────────────┬────────────────────────┘
                                             │ 80/443
                    ┌────────────────────────▼────────────────────────┐
                    │              traefik_public                      │
                    │   traefik · metabase · grafana · apps (roteadas) │
                    └──────┬──────────────────────────────────┬───────┘
                           │                                  │
         ┌─────────────────▼──────────────┐    ┌──────────────▼──────────────┐
         │        infra_internal           │    │        infra_data            │
         │  redis · loki · promtail ·      │    │  metabase · postgres_app1   │
         │  grafana · apps (acesso Redis)  │    │  postgres_app2 · ...         │
         └────────────────────────────────┘    │  (somente leitura)           │
                                               └─────────────────────────────┘

    Por app:
    ┌─────────────────────────┐
    │   minha_api_net         │
    │   app · postgres_app    │  ← postgres também em infra_data
    └─────────────────────────┘
```
