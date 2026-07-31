#!/bin/bash
# install_daemon_v4.sh — Instala e ativa o daemon v4 (rampa gradual) em substituição ao v3
# Uso: sudo ./install_daemon_v4.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERRO: rode com sudo"; exit 1; }

SRC="/home/johncoffee/mi50-oc/gpu-performance-daemon-v4.sh"
SVC_SRC="/home/johncoffee/mi50-oc/gpu-performance-daemon-v4.service"
DST="/usr/local/bin/gpu-performance-daemon-v4.sh"
SVC_DST="/etc/systemd/system/gpu-performance-daemon.service"

echo "══════════════════════════════════════════════"
echo "  INSTALAÇÃO — Daemon v4 (rampa gradual)"
echo "══════════════════════════════════════════════"

# 1. Instalar script
cp "$SRC" "$DST"
chmod +x "$DST"
echo "✅ Script: $DST"

# 2. Instalar service (mesmo nome do antigo, substitui)
cp "$SVC_SRC" "$SVC_DST"
systemctl daemon-reload
echo "✅ Service: $SVC_DST"

# 3. Parar o daemon v3 (se rodando) e iniciar v4
systemctl stop gpu-performance-daemon.service 2>/dev/null || true
systemctl enable --now gpu-performance-daemon.service
echo "✅ Daemon v4 ativo: $(systemctl is-active gpu-performance-daemon.service)"

# 4. Verificar
echo
echo "=== VERIFICAÇÃO ==="
systemctl status gpu-performance-daemon.service --no-pager 2>&1 | head -8
echo
echo "PRÓXIMO PASSO: testar inferência — a rampa agora sobe 1 nível/seg (0→8)"
echo "Acompanhar: journalctl -u gpu-performance-daemon -f  (linhas 'rampa ↑')"
