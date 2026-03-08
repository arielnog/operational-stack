#!/bin/bash
# =============================================================
#  setup_git.sh — Instalação e configuração do Git
#
#  O que esse script faz:
#    1. Instala o Git (se não estiver instalado)
#    2. Configura identidade global (opcional)
#    3. Define configurações recomendadas
#
#  Pré-requisitos:
#    - Ubuntu 22.04 ou 24.04 LTS
#    - Acesso root (sudo)
#
#  Como usar:
#    sudo bash scripts/setup_git.sh
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
  err "Execute como root: sudo bash scripts/setup_git.sh"
  exit 1
fi

divider
echo -e "${BOLD}  🔧 Git Setup — Instalação e Configuração${NC}"
echo -e "  Ubuntu $(lsb_release -rs 2>/dev/null || echo '?') | $(date '+%d/%m/%Y %H:%M')"
divider

# =============================================================
# ETAPA 1 — Instalar Git
# =============================================================
step "ETAPA 1/2 — Instalando Git"

if command -v git &> /dev/null; then
  ok "Git já instalado: $(git --version)"
else
  info "Instalando Git..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
  ok "Git instalado: $(git --version)"
fi

# =============================================================
# ETAPA 2 — Configurar Git
# =============================================================
step "ETAPA 2/2 — Configurando Git"

echo ""
read -p "  Configurar identidade global do Git agora? [s/N]: " CONFIG_GIT
if [[ "$CONFIG_GIT" =~ ^[sS]$ ]]; then
  read -p "  Seu nome (ex: João Silva): " GIT_NAME
  read -p "  Seu e-mail (ex: joao@email.com): " GIT_EMAIL

  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  git config --global core.autocrlf input

  ok "Git configurado:"
  info "  Nome:          $GIT_NAME"
  info "  E-mail:        $GIT_EMAIL"
  info "  Branch padrão: main"
else
  warn "Pulando configuração do Git. Para configurar depois:"
  info "  git config --global user.name 'Seu Nome'"
  info "  git config --global user.email 'seu@email.com'"
fi

# =============================================================
# RESUMO FINAL
# =============================================================
divider
echo -e "${BOLD}  🎉 Git configurado com sucesso!${NC}"
divider
echo ""
echo -e "${BOLD}  Configurações aplicadas:${NC}"
echo -e "  • $(git --version)"
if git config --global user.name &>/dev/null; then
  echo -e "  • Usuário: $(git config --global user.name)"
  echo -e "  • E-mail: $(git config --global user.email)"
else
  warn "Identidade global não configurada"
fi
echo -e "  • Branch padrão: $(git config --global init.defaultBranch 2>/dev/null || echo 'master (padrão)')"
echo ""
divider