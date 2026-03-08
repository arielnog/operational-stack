#!/bin/bash
# =============================================================
#  setup_vps.sh — Preparação completa da VPS Ubuntu
#
#  O que esse script faz (em ordem):
#    1. Atualiza o sistema
#    2. Instala dependências essenciais (curl, vim, htop...)
#    3. Instala o Docker + Docker Compose plugin
#    4. Configura o daemon do Docker (logs, segurança)
#    5. Cria a rede Docker pública 'proxy'
#    6. Instala e configura o Fail2Ban (proteção SSH)
#    7. Opcional: desabilita login SSH por senha
#    8. Cria diretório de logs do Traefik
#    9. Configura o Firewall (UFW + iptables)
#
#  Pré-requisitos:
#    - Ubuntu 22.04 ou 24.04 LTS
#    - Acesso root (sudo)
#
#  Como usar:
#    sudo bash scripts/setup_vps.sh
# =============================================================

set -euo pipefail

# ── Helpers de output ─────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

step()    { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }
ok()      { echo -e "  ${GREEN}✅ $1${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
info()    { echo -e "  ℹ️  $1"; }
err()     { echo -e "  ${RED}❌ $1${NC}"; }
divider() { echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Checar se está rodando como root ─────────────────────────
if [[ "$EUID" -ne 0 ]]; then
  err "Execute como root: sudo bash scripts/setup_vps.sh"
  exit 1
fi

divider
echo -e "${BOLD}  🚀 VPS Setup — Infraestrutura Base${NC}"
echo -e "  Ubuntu $(lsb_release -rs 2>/dev/null || echo '?') | $(date '+%d/%m/%Y %H:%M')"
divider

# =============================================================
# ETAPA 1 — Atualizar sistema
# =============================================================
step "ETAPA 1/10 — Atualizando sistema"
info "Executando apt-get update e upgrade..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
ok "Sistema atualizado."

# =============================================================
# ETAPA 2a — Corrigir dependências quebradas
# =============================================================
step "ETAPA 2a/11 — Corrigindo dependências quebradas"
info "Verificando e corrigindo pacotes quebrados..."
apt-get check 2>/dev/null || true
info "Limpando cache do apt..."
apt-get clean
apt-get autoclean
info "Corrigindo dependências quebradas..."
dpkg --configure -a
apt-get install -f -y
apt-get autoremove -y
apt-get update -qq
ok "Sistema limpo e dependências corrigidas."

# =============================================================
# ETAPA 2b — Instalar dependências essenciais
# =============================================================
step "ETAPA 2b/11 — Instalando dependências essenciais"

# Instalar em grupos menores para evitar conflitos
BASIC_PACKAGES=(
  curl wget vim htop nano
  ca-certificates gnupg lsb-release
  unzip zip jq
)

NETWORK_PACKAGES=(
  net-tools dnsutils
)

SECURITY_PACKAGES=(
  ufw fail2ban iptables-persistent
)

info "Instalando ferramentas básicas: ${BASIC_PACKAGES[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${BASIC_PACKAGES[@]}"
ok "Ferramentas básicas instaladas."

info "Instalando ferramentas de rede: ${NETWORK_PACKAGES[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${NETWORK_PACKAGES[@]}"
ok "Ferramentas de rede instaladas."

info "Instalando ferramentas de segurança: ${SECURITY_PACKAGES[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${SECURITY_PACKAGES[@]}"
ok "Ferramentas de segurança instaladas."

# =============================================================
# ETAPA 3 — Instalar Docker
# =============================================================
step "ETAPA 3/11 — Instalando Docker"

if command -v docker &> /dev/null; then
  ok "Docker já instalado: $(docker --version)"
else
  info "Baixando e instalando via script oficial (get.docker.com)..."
  curl -fsSL https://get.docker.com | bash
  ok "Docker instalado: $(docker --version)"
fi

if docker compose version &> /dev/null; then
  ok "Docker Compose plugin já disponível: $(docker compose version --short)"
else
  info "Instalando Docker Compose plugin..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-compose-plugin
  ok "Docker Compose instalado: $(docker compose version --short)"
fi

systemctl enable docker --quiet
systemctl start docker
ok "Docker habilitado no boot e rodando."

echo ""
read -p "  Adicionar usuário ao grupo docker (evita usar sudo)? [s/N]: " ADD_USER
if [[ "$ADD_USER" =~ ^[sS]$ ]]; then
  read -p "  Nome do usuário: " DOCKER_USER
  if id "$DOCKER_USER" &>/dev/null; then
    usermod -aG docker "$DOCKER_USER"
    ok "Usuário '$DOCKER_USER' adicionado ao grupo docker."
    warn "Faça logout/login para aplicar (ou: newgrp docker)"
  else
    err "Usuário '$DOCKER_USER' não encontrado. Pulando."
  fi
fi

# =============================================================
# ETAPA 4 — Configurar daemon do Docker
# =============================================================
step "ETAPA 4/11 — Configurando daemon do Docker"

info "Escrevendo /etc/docker/daemon.json..."
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "iptables": true,
  "userland-proxy": false,
  "live-restore": true
}
EOF

systemctl restart docker
ok "Daemon Docker reconfigurado:"
info "  log-driver:    json-file (10MB × 3 arquivos por container)"
info "  live-restore:  containers continuam se o daemon reiniciar"
info "  userland-proxy: desabilitado (melhor performance)"

# =============================================================
# ETAPA 5 — Rede Docker 'proxy'
# =============================================================
step "ETAPA 5/11 — Criando rede Docker 'proxy'"

if docker network ls --format '{{.Name}}' | grep -q "^proxy$"; then
  ok "Rede 'proxy' já existe."
else
  docker network create proxy
  ok "Rede Docker 'proxy' criada."
fi

info "Redes Docker disponíveis:"
docker network ls --format "  • {{.Name}} ({{.Driver}})"

# =============================================================
# ETAPA 6 — Fail2Ban
# =============================================================
step "ETAPA 6/11 — Configurando Fail2Ban (proteção contra brute force)"

info "Escrevendo /etc/fail2ban/jail.local..."
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = 3
EOF

systemctl enable fail2ban --quiet
systemctl restart fail2ban
ok "Fail2Ban configurado e rodando:"
info "  bantime:       1 hora"
info "  findtime:      10 minutos"
info "  maxretry SSH:  3 tentativas → IP bloqueado"

# =============================================================
# ETAPA 7 — Segurança SSH
# =============================================================
step "ETAPA 7/11 — Segurança SSH"

warn "ATENÇÃO: Antes de desabilitar login por senha, confirme que"
warn "sua chave SSH já está no servidor em ~/.ssh/authorized_keys"
warn "Se errar aqui pode perder acesso à VPS!"
echo ""
read -p "  Sua chave SSH pública já está configurada no servidor? [s/N]: " HAS_KEY

if [[ "$HAS_KEY" =~ ^[sS]$ ]]; then
  read -p "  Desabilitar login por senha? (altamente recomendado) [s/N]: " DISABLE_PASSWD
  if [[ "$DISABLE_PASSWD" =~ ^[sS]$ ]]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    info "Backup salvo em /etc/ssh/sshd_config.bak"

    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    systemctl restart sshd
    ok "Login SSH por senha desabilitado."
    ok "Apenas chave SSH permitida daqui em diante."
  else
    warn "Login por senha mantido. Configure uma chave e desabilite quando possível."
  fi
else
  warn "Pulando. Para configurar sua chave SSH depois:"
  info "  Na sua máquina local:"
  info "    ssh-keygen -t ed25519 -C 'seu@email.com'"
  info "    ssh-copy-id usuario@ip_da_vps"
  info "  Então rode este script novamente ou edite /etc/ssh/sshd_config"
fi

# =============================================================
# ETAPA 8 — Diretórios
# =============================================================
step "ETAPA 8/11 — Criando diretórios necessários"

mkdir -p /var/log/traefik
mkdir -p /etc/iptables
ok "Criado: /var/log/traefik"
ok "Criado: /etc/iptables"

# =============================================================
# ETAPA 9 — Firewall
# =============================================================
step "ETAPA 9/11 — Configurando Firewall (UFW + iptables)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/setup_firewall.sh"

# =============================================================
# RESUMO FINAL
# =============================================================
divider
echo -e "${BOLD}  🎉 Setup concluído com sucesso!${NC}"
divider
echo ""
echo -e "${BOLD}  O que foi instalado/configurado:${NC}"
echo -e "  • $(docker --version)"
echo -e "  • Docker Compose $(docker compose version --short)"
echo -e "  • Fail2Ban $(fail2ban-client version 2>/dev/null | head -1 || echo 'instalado')"
echo -e "  • UFW $(ufw version 2>/dev/null | head -1 || echo 'instalado')"
echo -e "  • jq $(jq --version 2>/dev/null || echo 'instalado')"
echo ""
divider
echo -e "${BOLD}  📋 Próximos passos — siga esta ordem:${NC}"
divider
echo ""
echo -e "  ${CYAN}${BOLD}[1] Configure as variáveis de ambiente${NC}"
echo -e "      cp .env.example .env"
echo -e "      vim .env"
echo -e "      # Preencha TODAS as variáveis (domínio, senhas, tokens)"
echo ""
echo -e "  ${CYAN}${BOLD}[2] Configure o e-mail no Traefik (Let's Encrypt)${NC}"
echo -e "      vim traefik/traefik.yml"
echo -e "      # Troque 'seu@email.com' pelo seu e-mail real"
echo ""
echo -e "  ${CYAN}${BOLD}[3] Obtenha o token da Cloudflare${NC}"
echo -e "      Acesse: https://dash.cloudflare.com/profile/api-tokens"
echo -e "      → Create Token → Edit zone DNS → Zone: seu domínio"
echo -e "      Cole em CF_DNS_API_TOKEN no .env"
echo ""
echo -e "  ${CYAN}${BOLD}[4] Torne os scripts executáveis${NC}"
echo -e "      chmod +x scripts/*.sh"
echo ""
echo -e "  ${CYAN}${BOLD}[5] Suba a stack${NC}"
echo -e "      docker compose up -d"
echo ""
echo -e "  ${CYAN}${BOLD}[6] Verifique se tudo subiu corretamente${NC}"
echo -e "      docker compose ps"
echo -e "      docker compose logs -f"
echo ""
echo -e "  ${CYAN}${BOLD}[7] Crie usuários para suas aplicações${NC}"
echo -e "      ./scripts/create_app_user.sh minha_api SenhaForte123!"
echo ""
