#!/bin/bash
set -euo pipefail

PP_TABLE="/home/johncoffee/mi50-oc/pp_table_350w.bin"
PP_SYSFS="/sys/class/drm/card1/device/pp_table"
UPP_BIN="/home/johncoffee/.local/bin/upp"
SERVICE_SRC="/home/johncoffee/mi50-oc/mi50-apply-pp.sh"
SERVICE_DST="/usr/local/bin/mi50-apply-pp.sh"
SERVICE_FILE="/etc/systemd/system/mi50-apply-pp.service"
ACTIVE_DIR="/etc/mi50-oc"
ACTIVE_PP="$ACTIVE_DIR/pp_table_active.bin"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail() { echo -e "${RED}❌ $*${NC}"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    fail "Execute como root: sudo $0"
fi

echo "============================================="
echo " MI50 OC — Deploy PP Table 350W"
echo "============================================="
echo ""

if [ ! -f "$PP_TABLE" ]; then
    fail "PP table não encontrada: $PP_TABLE"
fi

PP_SIZE=$(stat -c%s "$PP_TABLE")
if [ "$PP_SIZE" -ne 1730 ]; then
    fail "Tamanho inválido: ${PP_SIZE}B (esperado 1730B)"
fi

echo "[1/6] Backup da PP table atual..."
BACKUP="$ACTIVE_DIR/backup/stock_$(date +%Y%m%d_%H%M%S).bin"
mkdir -p "$ACTIVE_DIR/backup"
cat "$PP_SYSFS" > "$BACKUP"
ok "Backup: $BACKUP"

echo "[2/6] Aplicando PP table na GPU..."
cat "$PP_TABLE" > "$PP_SYSFS"
ok "PP table escrita em $PP_SYSFS"

echo "[3/6] Verificando valores aplicados..."
if command -v "$UPP_BIN" &>/dev/null; then
    "$UPP_BIN" -p "$PP_SYSFS" dump 2>/dev/null | grep -E \
        "SmallPowerLimit1|BoostPowerLimit|FreqTableGfx 8|FreqTableUclk 2|FreqTableFclk 7|FreqTableSocclk 7|ThotspotLimit|TedgeLimit|MaxVoltageGfx"
else
    warn "UPP não encontrado — verificação manual: upp -p $PP_SYSFS dump"
fi

echo ""
echo "[4/6] Instalando binário do script..."
cp "$SERVICE_SRC" "$SERVICE_DST"
chmod +x "$SERVICE_DST"
ok "Script: $SERVICE_DST"

echo "[5/6] Configurando PP table ativa em $ACTIVE_PP..."
cp "$PP_TABLE" "$ACTIVE_PP"
ok "PP table ativa: $ACTIVE_PP"

echo "[6/6] Instalando serviço systemd..."
cat > "$SERVICE_FILE" << 'UNIT'
[Unit]
Description=MI50 OC — Apply PowerPlay table on boot
After=multi-user.target
Before=lightdm.service gdm.service sddm.service

[Service]
Type=oneshot
ExecStartPre=/bin/bash -c 'while [ ! -f /sys/class/drm/card1/device/pp_table ]; do sleep 1; done'
ExecStart=/usr/local/bin/mi50-apply-pp.sh /etc/mi50-oc/pp_table_active.bin
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable mi50-apply-pp.service
ok "Serviço habilitado: mi50-apply-pp.service"

echo ""
echo "============================================="
echo " ✅ DEPLOY COMPLETO"
echo "============================================="
echo ""
echo "Alvos ativos:"
echo "  Power:  350W"
echo "  SCLK:   2000 MHz"
echo "  MCLK:   1200 MHz"
echo "  FCLK:   1200 MHz"
echo "  SOCCLK: 1165 MHz (97.1%)"
echo "  Hotspot: 150°C"
echo "  Edge:   100°C"
echo ""
echo "Para verificar:"
echo "  rocm-smi -a"
echo "  upp -p /sys/class/drm/card1/device/pp_table dump"
echo "  sudo /usr/local/bin/mi50-apply-pp.sh --status"
