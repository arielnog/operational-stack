#!/bin/bash
# =============================================================
#  setup_firewall.sh
#  Configura UFW para a VPS com Docker
#
#  IMPORTANTE: Execute ANTES de subir o Docker Compose
#  Rode como root: sudo bash setup_firewall.sh
# =============================================================

set -euo pipefail

echo "🛡️  Configurando firewall UFW..."

# Reset para estado limpo
ufw --force reset

# Política padrão: bloquear tudo
ufw default deny incoming
ufw default allow outgoing

# --- Portas públicas ---
ufw allow 22/tcp    comment 'SSH'
ufw allow 80/tcp    comment 'HTTP (Traefik → redireciona para HTTPS)'
ufw allow 443/tcp   comment 'HTTPS (Traefik)'

# --- BLOQUEAR acesso externo às portas internas Docker ---
# O Docker manipula o iptables diretamente e pode bypassar o UFW!
# A solução é configurar o Docker para NÃO expor portas no host público.
# No docker-compose, os serviços internos NÃO têm "ports:" declarado.
# Mas como camada extra de segurança:

# Bloquear acesso externo às portas que Docker poderia expor
ufw deny 5432/tcp   comment 'PostgreSQL — apenas interno'
ufw deny 6379/tcp   comment 'Redis — apenas interno'
ufw deny 3100/tcp   comment 'Loki — apenas interno'
ufw deny 9080/tcp   comment 'Promtail — apenas interno'
ufw deny 8080/tcp   comment 'Traefik dashboard — apenas interno'

# --- Proteção extra: limitar tentativas de SSH (brute force) ---
ufw limit 22/tcp    comment 'SSH rate limit'

# Habilitar UFW
ufw --force enable

echo ""
echo "✅ Firewall configurado! Status:"
ufw status verbose

# =============================================================
# IMPORTANTE: Corrigir bug do Docker + UFW
# O Docker modifica o iptables diretamente, ignorando o UFW.
# A configuração abaixo impede isso.
# =============================================================
echo ""
echo "🔧 Aplicando correção Docker + UFW (DOCKER-USER chain)..."

# Criar regra para bloquear acesso externo às redes internas Docker
# Permite apenas loopback e redes Docker internas
if ! iptables -L DOCKER-USER > /dev/null 2>&1; then
  echo "⚠️  Chain DOCKER-USER não existe ainda. Suba o Docker primeiro e rode novamente."
else
  # Permitir tráfego estabelecido/relacionado
  iptables -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  # Permitir acesso da rede Docker interna
  iptables -I DOCKER-USER -s 172.16.0.0/12 -j ACCEPT
  # Bloquear o resto (acesso externo direto aos containers)
  iptables -A DOCKER-USER -j DROP
  echo "✅ Regras DOCKER-USER aplicadas."
fi

# Persistir regras iptables
apt-get install -y iptables-persistent > /dev/null 2>&1 || true
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

echo ""
echo "🎉 Firewall pronto!"
echo ""
echo "📋 Resumo do que está bloqueado/permitido:"
echo "   ✅ 22   — SSH (com rate limit)"
echo "   ✅ 80   — HTTP (Traefik)"
echo "   ✅ 443  — HTTPS (Traefik)"
echo "   ❌ 5432 — PostgreSQL (apenas rede Docker interna)"
echo "   ❌ 6379 — Redis (apenas rede Docker interna)"
echo "   ❌ 3100 — Loki (apenas rede Docker interna)"
echo "   ❌ 8080 — Traefik dashboard (acesse via HTTPS autenticado)"
