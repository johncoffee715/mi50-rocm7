#!/bin/bash
# apply_350w_noundervolt.sh — Aplica TDP 350W + remove undervolt (MaxVoltageGfx=4650 stock)
# Uso: sudo bash /tmp/apply_350w_noundervolt.sh
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
UPP="/home/johncoffee/.local/bin/upp"
PP_GPU="/sys/class/drm/card1/device/pp_table"
PP_ACTIVE="/etc/mi50-oc/pp_table_active.bin"
PP_NEW="/tmp/pp_table_350w_noundervolt.bin"

[ "$(id -u)" -ne 0 ] && { echo -e "${RED}ERRO: Execute com sudo${NC}"; exit 1; }
[ ! -f "$PP_NEW" ] && { echo -e "${RED}ERRO: pp_table não encontrada: $PP_NEW${NC}"; exit 1; }

echo -e "${YELLOW}══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  MI50 OC — TDP 350W + REMOVE UNDERVOLT${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════════════════${NC}"
echo ""

# [1] Backup
echo -e "${YELLOW}[1/4] Backup do pp_table_active...${NC}"
cp "$PP_ACTIVE" "/etc/mi50-oc/backup/pp_table_pre_350w_noundervolt_$(date +%Y%m%d_%H%M%S).bin"
echo -e "${GREEN}  ✅ Backup salvo${NC}"

# [2] Atualizar pp_table_active.bin
echo -e "${YELLOW}[2/4] Atualizando pp_table_active.bin...${NC}"
cp "$PP_NEW" "$PP_ACTIVE"
echo -e "${GREEN}  ✅ pp_table_active.bin atualizado${NC}"

# [3] Aplicar no GPU (runtime)
echo -e "${YELLOW}[3/4] Aplicando no GPU (runtime)...${NC}"
cp "$PP_NEW" "$PP_GPU"
echo -e "${GREEN}  ✅ PP table aplicada no GPU${NC}"

# [4] Verificar
echo -e "${YELLOW}[4/4] Verificando...${NC}"
sleep 2
echo "  SmallPowerLimit1: $($UPP -p "$PP_GPU" get SmallPowerLimit1 2>/dev/null | tail -1)"
echo "  MaxVoltageGfx:   $($UPP -p "$PP_GPU" get smcPPTable/MaxVoltageGfx 2>/dev/null | tail -1)"
echo "  FreqTableGfx/8:  $($UPP -p "$PP_GPU" get smcPPTable/FreqTableGfx/8 2>/dev/null | tail -1)"
echo "  FreqTableUclk/2: $($UPP -p "$PP_GPU" get smcPPTable/FreqTableUclk/2 2>/dev/null | tail -1)"
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ TDP 350W + UNDERVOLT REMOVIDO APLICADO!${NC}"
echo -e "${GREEN}  SCLK max: 2040 MHz | MCLK max: 1180 MHz${NC}"
echo -e "${GREEN}  MaxVoltageGfx: 4650 (stock) — sem undervolt${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
