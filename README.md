# VPS Stack — Infraestrutura Base

Stack completa de infraestrutura para VPS com Docker, pronta para hospedar aplicações Node/PHP com banco de dados compartilhado, observabilidade e proxy reverso seguro.

---

## 📁 Estrutura de arquivos

```
vps-stack/
├── docker-compose.yml              # Stack principal
├── docker-compose.app-example.yml # Exemplo de app conectada
├── .env.example                    # Modelo de variáveis (copie para .env)
│
├── traefik/
│   ├── traefik.yml                 # Config estática (entrypoints, certificados)
│   └── dynamic.yml                 # Middlewares, TLS, headers de segurança
│
├── postgres/
│   └── init/
│       └── 01_init.sql             # Criação de bancos e usuários iniciais
│
├── loki/
│   └── loki.yml                    # Agregador de logs
│
├── promtail/
│   └── promtail.yml                # Coleta de logs (host + containers)
│
├── grafana/
│   └── provisioning/
│       └── datasources/
│           └── datasources.yml     # Loki + PostgreSQL pré-configurados
│
└── scripts/
    ├── setup_vps.sh                # ① Setup inicial da VPS (rodar 1x)
    ├── setup_git.sh                # ② Instalação e configuração do Git (opcional)
    └── setup_firewall.sh           # ③ Chamado automaticamente pelo setup_vps.sh
```

---

## 🗺️ Visão geral da arquitetura

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────────────────┐
│  FIREWALL (UFW + iptables)                                   │
│  Só portas 22, 80, 443 abertas externamente                  │
└──────────────────────────────────────────────────────────────┘
   │ 80 / 443
   ▼
┌──────────────────────────────────────────────────────────────┐
│  TRAEFIK (proxy reverso)                    rede: proxy      │
│  • SSL automático via Let's Encrypt + Cloudflare             │
│  • Roteia por subdomínio → container certo                   │
│  • Rate limiting, headers de segurança, TLS 1.2+             │
└───────────┬──────────────────────────────────────────────────┘
            │ rede interna Docker
   ┌─────────┼──────────┬──────────────┐
   ▼         ▼          ▼              ▼
Metabase  Grafana   Suas Apps    (futuras apps)
            │
            ▼
┌──────────────────────────────────────────────────────────────┐
│  REDE INTERNA (não acessível externamente)                   │
│  PostgreSQL · Redis · Loki · Promtail                        │
└──────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Scripts disponíveis

| Script | Quando usar | O que faz |
|--------|-------------|-----------|
| `setup_vps.sh` | **Primeira execução** | Setup base da VPS: Docker, dependências, firewall, fail2ban |
| `setup_git.sh` | **Opcional** | Instala e configura Git com identidade global |
| `setup_firewall.sh` | Chamado pelo setup_vps | Configura UFW e iptables |

**Ordem recomendada:**
1. `setup_vps.sh` ← sempre primeiro
2. `setup_git.sh` ← se precisar do Git
3. Configurar .env e subir a stack

---

## 🚀 Guia de execução — passo a passo

### Pré-requisitos (na sua máquina local)

Você precisa de:
- Acesso SSH à VPS (Ubuntu 22.04 ou 24.04 LTS)
- Um domínio apontando para o IP da VPS (ou via Cloudflare)
- Conta na Cloudflare com o domínio configurado (para SSL automático)

---

### FASE 1 — Acessar a VPS pela primeira vez

```bash
# Na sua máquina local, conecte via SSH
ssh root@IP_DA_SUA_VPS

# Se ainda não tiver chave SSH configurada, gere uma:
ssh-keygen -t ed25519 -C "seu@email.com"

# Copie a chave para a VPS (na sua máquina local):
ssh-copy-id root@IP_DA_SUA_VPS
```

---

### FASE 2 — Clonar o repositório na VPS

> ⚠️ O Git não é mais instalado automaticamente pelo setup_vps.sh.
> Para instalar e configurar o Git, use o script dedicado:

```bash
# Instalar Git separadamente (opcional)
sudo bash scripts/setup_git.sh
```

**Ou instale manualmente se preferir:**

```bash
# Na VPS, caso o git não esteja instalado ainda:
apt-get update && apt-get install -y git

# Clonar o repositório
git clone https://github.com/seu-usuario/vps-stack.git /opt/vps-stack
cd /opt/vps-stack

# Ou, se quiser subir via scp da sua máquina local (sem git):
# scp -r ./vps-stack root@IP_DA_VPS:/opt/vps-stack
```

---

### FASE 3 — Rodar o setup inicial

```bash
# Na VPS, dentro do diretório do projeto:
cd /opt/vps-stack

# Tornar scripts executáveis
chmod +x scripts/*.sh

# Rodar o setup (como root)
sudo bash scripts/setup_vps.sh
```

O script vai te guiar interativamente por 9 etapas:

| Etapa | O que acontece |
|-------|---------------|
| 1 | `apt-get update && upgrade` — sistema atualizado |
| 2 | Instala: curl, wget, vim, htop, jq, dnsutils, unzip... |
| 3 | Instala Docker + Docker Compose plugin + pergunta usuário do grupo docker |
| 4 | Configura `/etc/docker/daemon.json` (logs, live-restore) |
| 5 | Cria a rede Docker `proxy` (usada pelo Traefik) |
| 6 | Instala Fail2Ban — bloqueia IPs após 3 tentativas SSH falhas |
| 7 | Pergunta se quer desabilitar login SSH por senha |
| 8 | Cria `/var/log/traefik` e `/etc/iptables` |
| 9 | Configura UFW (portas 22, 80, 443) + correção Docker/iptables |

Ao final, o script exibe um resumo do que foi instalado e os próximos passos.

---

### FASE 4 — Configurar variáveis de ambiente

```bash
# Copiar o modelo
cp .env.example .env

# Editar com suas informações reais
vim .env
```

Preencha cada variável:

```bash
# Seu domínio principal (sem https://)
DOMAIN=seudominio.com

# Token da Cloudflare (veja como obter abaixo)
CF_DNS_API_TOKEN=seu_token_cloudflare_aqui

# PostgreSQL — superusuário
POSTGRES_USER=admin
POSTGRES_PASSWORD=TROQUE_POR_SENHA_FORTE
POSTGRES_DB=main

# Redis
REDIS_PASSWORD=TROQUE_POR_SENHA_FORTE

# Let's Encrypt (e-mail para alertas de expiração)
LETSENCRYPT_EMAIL=seu@email.com

# Metabase (usuário dedicado no Postgres)
METABASE_DB=metabase
METABASE_DB_USER=metabase_user
METABASE_DB_PASSWORD=TROQUE_POR_SENHA_FORTE

# Grafana
GRAFANA_USER=admin
GRAFANA_PASSWORD=TROQUE_POR_SENHA_FORTE
GRAFANA_DB=grafana
GRAFANA_DB_USER=grafana_user
GRAFANA_DB_PASSWORD=TROQUE_POR_SENHA_FORTE

# Dashboard Traefik (basic auth)
# Gere com: echo "usuario:$(openssl passwd -apr1 senha)" | sed -e 's/\$/\$\$/g'
TRAEFIK_DASHBOARD_AUTH=usuario:$$apr1$$hash$$aqui
```

---

### FASE 5 — Configurar o Traefik

**5a. Configurar e-mail do Let's Encrypt:**

No arquivo `.env`, defina a variável `LETSENCRYPT_EMAIL` com seu e-mail real. O Let's Encrypt envia alertas de expiração de certificados para esse endereço:

```bash
LETSENCRYPT_EMAIL=seu@email.com
```

**5b. Obter o token da Cloudflare:**

1. Acesse: [https://dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Clique em **"Create Token"**
3. Procure o template **"Edit zone DNS"** e clique em **"Use template"**
4. Configure as permissões:
   - **Permissions**: `Zone` → `DNS` → `Edit` (já vem preenchido pelo template)
   - **Zone Resources**: `Include` → `Specific zone` → **selecione seu domínio**
5. *(Opcional)* Em **Client IP Address Filtering**, adicione o IP da sua VPS para restringir o uso do token apenas a ela — isso impede que o token funcione de qualquer outro lugar
6. Clique em **"Continue to summary"** → **"Create Token"**
7. **Copie o token gerado** — ele só aparece uma vez! Se perder, terá que criar outro
8. Cole no seu `.env`:
   ```bash
   CF_DNS_API_TOKEN=o_token_que_voce_copiou
   ```

> **Por que esse token é necessário?** O Traefik usa o método DNS-01 challenge do Let's Encrypt. Ele cria automaticamente um registro DNS `_acme-challenge.seudominio.com` via API da Cloudflare para provar que você controla o domínio. Isso permite gerar certificados SSL wildcard (`*.seudominio.com`) sem precisar abrir portas extras.

---

### FASE 6 — Verificar o DNS do domínio

Antes de subir a stack, confirme que seu domínio aponta para o IP da VPS:

```bash
# Na VPS ou na sua máquina local:
dig +short seudominio.com
# Deve retornar o IP da sua VPS

# Verificar propagação:
nslookup seudominio.com 1.1.1.1
```

Se ainda não apontou, vá no painel da Cloudflare e adicione:

| Tipo | Nome | Conteúdo | Proxy |
|------|------|----------|-------|
| A | `@` | `IP_DA_VPS` | ✅ Proxied |
| A | `*` | `IP_DA_VPS` | ✅ Proxied |

O `*` é o wildcard — permite que `qualquer.seudominio.com` funcione automaticamente.

---

### FASE 7 — Subir a stack

```bash
# Dentro do diretório vps-stack
docker compose up -d
```

O Docker vai baixar todas as imagens e iniciar os containers. Na primeira vez pode levar alguns minutos.

**Acompanhar o boot em tempo real:**

```bash
docker compose logs -f
```

**Verificar se todos subiram corretamente:**

```bash
docker compose ps
```

A saída deve mostrar todos os serviços como `healthy` ou `running`:

```
NAME         IMAGE                    STATUS
traefik      traefik:v3.1             running (healthy)
postgres     postgres:16-alpine       running (healthy)
redis        redis:7-alpine           running (healthy)
metabase     metabase/metabase        running (healthy)
grafana      grafana/grafana          running (healthy)
loki         grafana/loki             running (healthy)
promtail     grafana/promtail         running
```

---

### FASE 8 — Acessar os serviços

Após tudo subir (aguarde ~2 minutos para o SSL ser emitido):

| Serviço | URL | Usuário padrão |
|---------|-----|----------------|
| Traefik dashboard | `https://traefik.seudominio.com` | basic auth do `.env` |
| Metabase | `https://metabase.seudominio.com` | criado no primeiro acesso |
| Grafana | `https://grafana.seudominio.com` | admin / senha do `.env` |

---

## 📦 Adicionar uma nova aplicação

Crie o `docker-compose.yml` da sua app (veja `docker-compose.app-example.yml` como modelo):

```bash
mkdir /opt/minha-api
vim /opt/minha-api/docker-compose.yml
```

Pontos importantes no compose da app:
- Conecte às redes `proxy` e `internal` (ambas `external: true`)
- Adicione as labels do Traefik para o subdomínio
- **Não declare `ports:`** — o Traefik faz o roteamento

```bash
# Subir a app
docker compose -f /opt/minha-api/docker-compose.yml up -d
```

---

## 🔒 Segurança — resumo

### Portas abertas no servidor

| Porta | Status | Motivo |
|-------|--------|--------|
| 22 | ✅ Aberta (rate limit) | SSH |
| 80 | ✅ Aberta | HTTP → redireciona para HTTPS |
| 443 | ✅ Aberta | HTTPS via Traefik |
| 5432 | ❌ Fechada | PostgreSQL — só via rede Docker |
| 6379 | ❌ Fechada | Redis — só via rede Docker |
| 3100 | ❌ Fechada | Loki — só via rede Docker |
| 8080 | ❌ Fechada | Traefik dashboard — só via HTTPS |

### Redes Docker

- **`proxy`** — Traefik + containers que precisam ser acessados externamente
- **`internal`** — Postgres, Redis, Loki — inacessível de fora
- **`observability`** — Rede dedicada para observabilidade. Permite que Grafana, Loki e Promtail troquem dados de métricas e logs de forma isolada, sem expor portas externas. Use esta rede para conectar serviços de monitoramento e logging.

---

## 🔧 Comandos do dia a dia

```bash
# Ver status de todos os containers
docker compose ps

# Acompanhar logs em tempo real
docker compose logs -f

# Logs de um serviço específico
docker compose logs -f postgres
docker compose logs -f traefik

# Reiniciar um serviço
docker compose restart grafana

# Parar tudo
docker compose down

# Atualizar imagens e reiniciar
docker compose pull && docker compose up -d

# Acessar o PostgreSQL diretamente
docker exec -it postgres psql -U admin -d main

# Verificar regras do firewall
ufw status verbose

# Ver IPs bloqueados pelo Fail2Ban
fail2ban-client status sshd

# Backup do banco inteiro
docker exec postgres pg_dumpall -U admin > backup_$(date +%Y%m%d).sql
```

---

## 📊 Observabilidade

- **Logs de containers** — Promtail coleta automaticamente via Docker socket
- **Logs do host** — `/var/log/syslog` e `/var/log/auth.log` também coletados
- **Visualização** — Grafana → Explore → selecione datasource Loki
- **Retenção** — 30 dias (altere em `loki/loki.yml` → `retention_period`)

---

## ❗ Troubleshooting

### SSL não está sendo emitido
```bash
docker compose logs traefik | grep -i "acme\|certificate\|error"
# Verifique:
# - Token Cloudflare correto no .env
# - Domínio realmente aponta para o IP da VPS
# - Porta 443 aberta no firewall
```

### Container não sobe (unhealthy)
```bash
docker compose logs nome_do_servico
docker inspect nome_do_servico | jq '.[0].State'
# Verifique variáveis de ambiente, dependências e healthchecks
```

### Postgres não conecta
```bash
docker exec -it postgres pg_isready -U admin
# Verifique:
# - POSTGRES_USER e POSTGRES_PASSWORD no .env
# - Rede interna configurada corretamente
# - Container da aplicação está na rede 'internal'
```

### Traefik não roteia para a app
```bash
# Verifique se a app está na rede 'proxy'
docker network inspect proxy
# Verifique as labels no docker-compose da app
docker inspect nome_da_app | jq '.[0].Config.Labels'
# Certifique-se de que não há conflito de portas ou subdomínios
```

### Firewall bloqueando acesso
```bash
ufw status verbose
# Confirme se portas 22, 80, 443 estão abertas
# Use 'ufw allow' para liberar portas se necessário
```

### Falha no backup do banco
```bash
docker exec postgres pg_dumpall -U admin > backup_$(date +%Y%m%d).sql
# Verifique espaço em disco e permissões
```
