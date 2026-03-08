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

# Verificar se UFW já está ativo e configurado
if ufw status | grep -q "Status: active"; then
  echo "ℹ️  UFW já está ativo. Verificando regras existentes..."
  EXISTING_RULES=$(ufw status | grep -c "ALLOW\|DENY\|LIMIT" || true)
  if [[ "$EXISTING_RULES" -ge 3 ]]; then
    echo "✅ Firewall UFW já configurado com $EXISTING_RULES regras."
    ufw status verbose
    echo ""
    echo "ℹ️  Pulando reconfiguração do UFW (já OK)."
    echo "    Para forçar recriação: ufw --force reset && bash $0"
  else
    echo "⚠️  UFW ativo mas com poucas regras. Reconfigurando..."
    ufw --force reset
    UFW_NEEDS_SETUP=true
  fi
else
  UFW_NEEDS_SETUP=true
fi

if [[ "${UFW_NEEDS_SETUP:-false}" == "true" ]]; then
  # Política padrão: bloquear tudo
  ufw default deny incoming
  ufw default allow outgoing

  # --- Portas públicas ---
  ufw allow 22/tcp    comment 'SSH'
  ufw allow 80/tcp    comment 'HTTP (Traefik → redireciona para HTTPS)'
  ufw allow 443/tcp   comment 'HTTPS (Traefik)'

  # --- BLOQUEAR acesso externo às portas internas Docker ---
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
fi

# =============================================================
# IMPORTANTE: Corrigir bug do Docker + UFW
# O Docker modifica o iptables diretamente, ignorando o UFW.
# A configuração abaixo impede isso.
# =============================================================
echo ""
echo "🔧 Aplicando correção Docker + UFW (DOCKER-USER chain)..."

if ! iptables -L DOCKER-USER > /dev/null 2>&1; then
  echo "⚠️  Chain DOCKER-USER não existe ainda. Suba o Docker primeiro e rode novamente."
else
  # Limpar regras anteriores da chain DOCKER-USER para evitar duplicatas
  echo "ℹ️  Limpando regras antigas de DOCKER-USER..."
  iptables -F DOCKER-USER 2>/dev/null || true

  # Reaplicar regras limpas
  # 1. Permitir tráfego estabelecido/relacionado
  iptables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  # 2. Permitir acesso da rede Docker interna (172.16.0.0/12)
  iptables -A DOCKER-USER -s 172.16.0.0/12 -j ACCEPT
  # 3. Permitir tráfego nas portas públicas (Traefik)
  iptables -A DOCKER-USER -p tcp --dport 80 -j ACCEPT
  iptables -A DOCKER-USER -p tcp --dport 443 -j ACCEPT
  # 4. Permitir loopback
  iptables -A DOCKER-USER -i lo -j ACCEPT
  # 5. Bloquear o resto (acesso externo direto aos containers)
  iptables -A DOCKER-USER -j DROP

  echo "✅ Regras DOCKER-USER aplicadas."
fi

# Persistir regras iptables (sem prompts interativos)
echo "ℹ️  Persistindo regras iptables..."
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true

if command -v netfilter-persistent &> /dev/null; then
  netfilter-persistent save 2>/dev/null || true
fi

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
