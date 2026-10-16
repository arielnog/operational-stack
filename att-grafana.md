# Stack arnsolutions.tech — Alloy + Dashboards

Este arquivo orienta o Claude Code rodando **dentro da VPS** (Hostinger), acessada pelo iPhone via Tailscale + Termius, numa sessão `tmux`.

**Escopo:** migrar Promtail → Grafana Alloy e montar os dashboards no Grafana (health, logs, recursos, tráfego).
**Fora do escopo:** Tailscale, firewall, DNS e exposição do Grafana. Isso está sendo feito à parte; não mexa.

---

## 1. Contexto da stack

- Docker + Docker Compose. **Traefik v3** como reverse proxy, TLS via Let's Encrypt, DNS na Cloudflare.
- **PostgreSQL** com um banco por app. **Redis** compartilhado, isolado por DB number.
- **Observabilidade atual:** Grafana, Loki, Promtail (EOL desde mar/2026), Metabase.
- **Redes Docker:** `traefik_public`, `infra_internal`, `infra_data`, `observability`.
- **Apps:** bot de promoções (Hyperf + Evolution API), IPTV API (Hyperf), serviços NestJS + BullMQ, site do casamento, entre outros. **Descubra nomes e portas reais na Fase 0. Não presuma.**

## 2. Arquivos de apoio (já prontos, nesta pasta)

| Arquivo | Destino |
|---|---|
| `grafana/provisioning/datasources/datasources.yml` | Datasources Prometheus (uid `prometheus`) e Loki (uid `loki`) |
| `grafana/provisioning/dashboards/dashboards.yml` | Provider que carrega os JSONs de `/var/lib/grafana/dashboards` |
| `grafana/dashboards/visao-geral.json` | Dashboard "Visão Geral" (health, tráfego, recursos, logs) |
| `alloy/config.alloy.referencia` | Config de referência do Alloy, para usar só se o `convert` falhar |

Ajuste os caminhos ao layout real da stack. Monte as pastas de provisioning e dashboards no container do Grafana se ainda não estiverem montadas.

## 3. Regras para o Claude Code

1. **Antes de cada fase:** `git add -A && git commit -m "antes da fase N"` na pasta da stack. Se não for repositório git, rode `git init` antes, com um `.gitignore` que exclua `.env*`, `acme.json` e pastas de dados.
2. **Nunca** exiba, copie ou faça `cat` de `.env`, tokens ou `acme.json`. Para checar se uma variável existe, use `grep -c NOME .env`.
3. **Nunca** remova volumes nem rode `docker compose down -v`, `docker volume rm` ou `docker system prune`.
4. **Peça confirmação explícita** antes de:
   - reiniciar o Traefik;
   - remover o Promtail;
   - recriar o container do Grafana ou do Loki.
5. **Não publique** portas de métricas ou de debug (8082, 9090, 9100, 9115, 12345 etc.) no host, nem crie routers no Traefik para elas.
6. **Separação de redes:**
   - exporters de banco entram em `infra_data` + `observability`;
   - o blackbox entra em `observability` + as redes onde estão as apps que ele vai testar.
7. Valide o **checkpoint** de cada fase antes de seguir. Se falhar, pare e reporte.
8. **Respostas curtas:** o usuário está no celular. Mostre só diffs pequenos e o resultado dos checkpoints.

---

## Fase 0 — Inventário (somente leitura)

- `docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Networks}}'`
- Localize:
  - os composes;
  - a config estática do Traefik;
  - o `promtail.yml`;
  - o provisioning atual do Grafana (se existir) e os datasources já criados (`curl` na API do Grafana de dentro da rede, ou confira na UI).
- Para cada app, descubra o endpoint de health (`/health`, `/healthz`, `/status`) e a porta interna.
- Liste os labels que o Promtail gera hoje. No Loki, rode `curl -s http://loki:3100/loki/api/v1/labels` de um container na rede `observability`.

**Entregável:** uma tabela curta com app, container, rede, porta interna e endpoint de health, mais a lista de labels atuais do Loki.

## Fase 1 — Promtail → Grafana Alloy

1. **Converter** a config do Promtail:
   ```bash
   docker run --rm -v "$PWD/<pasta-promtail>":/cfg grafana/alloy:latest \
     convert --source-format=promtail --report=/cfg/report.txt \
     --output=/cfg/config.alloy /cfg/promtail.yml
   ```
   Revise o `report.txt`. Se a conversão falhar ou ficar confusa, parta de `alloy/config.alloy.referencia`, ajustando os labels para bater com os atuais.
2. **Subir o Alloy em paralelo** ao Promtail, na rede `observability`:
   ```yaml
   alloy:
     image: grafana/alloy:latest
     command: run /etc/alloy/config.alloy --server.http.listen-addr=0.0.0.0:12345 --storage.path=/var/lib/alloy/data
     volumes:
       - ./alloy/config.alloy:/etc/alloy/config.alloy:ro
       - /var/run/docker.sock:/var/run/docker.sock:ro
       - alloy_data:/var/lib/alloy/data
     networks: [observability]
     restart: unless-stopped
   ```
   Enquanto os dois rodam juntos, haverá logs duplicados. Isso é esperado e temporário.
3. **Checkpoint:**
   - `docker logs alloy` sem erros de componente;
   - `curl http://alloy:12345/-/ready` (de dentro da rede) retorna pronto;
   - no Loki, os mesmos labels de antes existem e uma query como `{container="<app>"}` traz linhas novas;
   - as queries e dashboards de logs que já existiam continuam funcionando.
4. **Com confirmação:** remova o Promtail do compose. Mantenha o arquivo `promtail.yml` no git por um tempo.

## Fase 2 — Métricas e health (pré-requisito dos dashboards)

- Adicione ao compose de observabilidade:
  - **Prometheus:** `--storage.tsdb.retention.time=15d`, `scrape_interval: 30s`, volume persistente;
  - **node-exporter:** `pid: host`, `/` montado em `/host:ro,rslave`, `--path.rootfs=/host`;
  - **cAdvisor:** `--docker_only=true --housekeeping_interval=30s`;
  - **blackbox-exporter** com o módulo padrão `http_2xx`;
  - **postgres-exporter:** usuário `monitor` com role `pg_monitor`, senha no `.env`;
  - **redis-exporter.**
- **Métricas do Traefik:** entrypoint `metrics` em `:8082`, `metrics.prometheus` com `entryPoint: metrics`, `addRoutersLabels: true` e `addServicesLabels: true`. Reinício **com confirmação**.
- **`prometheus.yml`:** jobs `node`, `cadvisor`, `traefik`, `postgres`, `redis` e `health`.
  - O job `health` usa o blackbox (`metrics_path: /probe`, `module: http_2xx`) com o relabel padrão `__address__ → __param_target → instance`, e `__address__` apontando para `blackbox:9115`.
  - Os targets de health são as **URLs internas** levantadas na Fase 0.
  - Probes externos de sites públicos são opcionais. Subdomínios atrás do Cloudflare Access retornam 302, então use a URL interna.
- **Checkpoint:**
  - `curl -s http://prometheus:9090/api/v1/targets` (de dentro da rede) mostra todos os jobs `up`;
  - `probe_success` retorna 1 para as apps saudáveis.

## Fase 3 — Dashboards

1. **Provisioning:** copie `grafana/provisioning/*` e `grafana/dashboards/*` para os caminhos montados no Grafana. Confira se não há conflito de nome ou uid com datasources que já existiam. Se o Loki já existir com outro uid, prefira **ajustar o arquivo** a apagar o datasource antigo.
2. **Dashboards da comunidade.** Baixe com:
   `curl -sL https://grafana.com/api/dashboards/<ID>/revisions/latest/download -o grafana/dashboards/<nome>.json`
   Depois substitua as variáveis de input (`${DS_PROMETHEUS}`, `${DS_LOKI}` e similares) pelos uids `prometheus` e `loki`, e remova o bloco `__inputs` se existir.

   | ID | Dashboard | Arquivo |
   |---|---|---|
   | 1860 | Node Exporter Full | `node-exporter.json` |
   | 14282 | cAdvisor | `cadvisor.json` |
   | 17346 | Traefik v3 | `traefik.json` |
   | 9628 | PostgreSQL | `postgres.json` |
   | 11835 | Redis (redis_exporter) | `redis.json` |
   | 7587 | Blackbox | `blackbox.json` |
   | 13639 | Logs / Loki | `logs.json` |

   Se algum ID não existir mais ou estiver quebrado, avise e sugira um equivalente. Não invente.
3. **"Visão Geral"** (`visao-geral.json`, pronto):
   - **Health:** stat UP/DOWN por app, menor validade de TLS, targets down, containers reiniciados e latência dos probes;
   - **Tráfego:** requests/s, taxa de 5xx e latência p95 por serviço do Traefik;
   - **Recursos:** CPU, RAM e disco da VPS, mais RAM e CPU por container;
   - **Logs:** erros por app e painel de logs com as variáveis `$app` e `$busca`.

   O dashboard usa o label `container` no Loki. Se o label real for outro (ex.: `container_name`), ajuste as 3 ocorrências no JSON: a variável `app` e os dois painéis de logs.
4. **Recarregar:** o provider relê os arquivos a cada 30s. Se os datasources novos não aparecerem, é preciso reiniciar o Grafana **com confirmação**.
5. **Checkpoint:**
   - os dashboards aparecem na pasta **Infra**;
   - na "Visão Geral", nenhum painel mostra "No data", exceto métricas que de fato ainda não existem (diga quais).

## Fase 4 — Alertas (depois dos dashboards)

- Regras no Grafana Alerting, provisionadas em `grafana/provisioning/alerting/`:
  - `probe_success == 0` por 2 min;
  - 5xx acima de 5% por 5 min;
  - disco abaixo de 15%;
  - TLS vencendo em menos de 14 dias;
  - container reiniciando;
  - `up == 0`.
- **Contact point:** pergunte ao Ariel se prefere Telegram ou webhook para a Evolution API (WhatsApp). Credenciais ficam no `.env`.
- **Checkpoint:** um alerta de teste chega no celular.

## Fase 5 — Opcional (só se o Ariel pedir)

- Métricas de negócio nas apps: `hyperf/metric` (driver Prometheus) e `@willsoto/nestjs-prometheus`, com um dashboard "Negócio" (mensagens enviadas, matches de promoção, jobs BullMQ por estado).
- Consolidar node-exporter e cAdvisor dentro do Alloy (`prometheus.exporter.unix` / `prometheus.exporter.cadvisor`).
