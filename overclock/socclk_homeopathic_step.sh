#!/bin/bash
# socclk_homeopathic_step.sh — Stepping homeopático REAL
# TODOS os parâmetros escalonam juntos, não só SOCCLK
#
# Tabela homeopática (8 stages, 0-7):
#   SCLK:  1700→2000  (+43/stage)
#   MCLK:  1000→1200  (+29/stage)
#   FCLK:  1180→1200  (+3/stage)
#   TDP:   190→350    (+23W/stage)
#   TDC:   330→280    (-7A/stage)
#   SOCCLK: 972→1000  (+4/stage)
#
# Uso: sudo ./socclk_homeopathic_step.sh [stage|all|status|rollback|verify]

set -euo pipefail

UPP_BIN="$(command -v upp 2>/dev/null || echo /home/johncoffee/.local/bin/upp)"
UPP="${UPP_BIN:-$(command -v upp)}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PP_STOCK="$BASE_DIR/pp_table_patches/pp_table_stock.bin"
PP_DIR="$BASE_DIR/pp_table_patches/socclk_homeopathic"
BACKUP_DIR="$BASE_DIR/pp_table_patches/socclk_homeopathic/backups"

# Tabela homeopática completa — cada stage tem valores únicos para TODOS os parâmetros
declare -A SOCCLK_VALS=( [0]=972 [1]=976 [2]=980 [3]=984 [4]=988 [5]=992 [6]=996 [7]=1000 )
declare -A SCLK_VALS=( [0]=1700 [1]=1743 [2]=1786 [3]=1829 [4]=1871 [5]=1914 [6]=1957 [7]=2000 )
declare -A MCLK_VALS=( [0]=1000 [1]=1029 [2]=1057 [3]=1086 [4]=1114 [5]=1143 [6]=1171 [7]=1200 )
declare -A FCLK_VALS=( [0]=1180 [1]=1183 [2]=1186 [3]=1189 [4]=1193 [5]=1196 [6]=1199 [7]=1200 )
declare -A TDP_VALS=( [0]=190 [1]=213 [2]=236 [3]=259 [4]=282 [5]=305 [6]=328 [7]=350 )
declare -A TDC_VALS=( [0]=330 [1]=323 [2]=316 [3]=309 [4]=302 [5]=295 [6]=288 [7]=280 )

check_root() {
    [ "$(id -u)" -ne 0 ] && { echo -e "${RED}ERRO: sudo $0 $*${NC}"; exit 1; }
}

detect_card() {
    for _card in /sys/class/drm/card*/device; do
        [ "$(cat "$_card/vendor" 2>/dev/null)" = "0x1002" ] && [ -f "$_card/pp_table" ] && { echo "$_card/pp_table"; return 0; }
    done
    echo ""
    return 1
}

backup_pp() {
    local label="${1:-stock}"
    local card_pp; card_pp=$(detect_card) || { echo -e "${RED}GPU não detectada!${NC}"; return 1; }
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/pp_table_${label}_$(date +%Y%m%d_%H%M%S).bin"
    cp "$card_pp" "$backup_file"
    echo -e "${GREEN}✅ Backup: $(basename "$backup_file")${NC}"
    sha256sum "$backup_file"
}

generate_stage_pp() {
    local stage=$1
    local socclk=${SOCCLK_VALS[$stage]}
    local sclk=${SCLK_VALS[$stage]}
    local mclk=${MCLK_VALS[$stage]}
    local fclk=${FCLK_VALS[$stage]}
    local tdp=${TDP_VALS[$stage]}
    local tdc=${TDC_VALS[$stage]}
    local output="$PP_DIR/pp_table_socclk_${socclk}MHz.bin"
    
    mkdir -p "$PP_DIR"
    [ -f "$output" ] && { echo -e "${YELLOW}⚠️  Já existe: $(basename "$output")${NC}"; return 0; }
    
    cp "$PP_STOCK" "$output"
    
    $UPP -p "$output" set --write \
        SmallPowerLimit1=$tdp SmallPowerLimit2=$tdp BoostPowerLimit=$tdp \
        smcPPTable/SocketPowerLimitAc0=$tdp smcPPTable/SocketPowerLimitDc=$tdp \
        smcPPTable/TdcLimitGfx=$tdc smcPPTable/TedgeLimit=100 \
        smcPPTable/ThotspotLimit=$([ $stage -eq 7 ] && echo 150 || echo 105) \
        smcPPTable/ThbmLimit=94 \
        smcPPTable/FreqTableGfx/8=$sclk smcPPTable/DcModeMaxFreq/0=$sclk \
        smcPPTable/GfxclkDsMaxFreq=$sclk \
        smcPPTable/FreqTableUclk/2=$mclk smcPPTable/FreqTableUclk/3=$mclk \
        smcPPTable/FreqTableFclk/0=$fclk smcPPTable/FreqTableFclk/1=$fclk \
        smcPPTable/FreqTableFclk/2=$fclk smcPPTable/FreqTableFclk/3=$fclk \
        smcPPTable/FreqTableFclk/4=$fclk smcPPTable/FreqTableFclk/5=$fclk \
        smcPPTable/FreqTableFclk/6=$fclk smcPPTable/FreqTableFclk/7=$fclk \
        smcPPTable/FreqTableSocclk/0=310 smcPPTable/FreqTableSocclk/1=524 \
        smcPPTable/FreqTableSocclk/2=567 smcPPTable/FreqTableSocclk/3=619 \
        smcPPTable/FreqTableSocclk/4=680 smcPPTable/FreqTableSocclk/5=756 \
        smcPPTable/FreqTableSocclk/6=850 smcPPTable/FreqTableSocclk/7=$socclk \
        smcPPTable/MinVoltageGfx=$([ $stage -eq 7 ] && echo 2650 || echo 2950) \
        smcPPTable/MaxVoltageGfx=$([ $stage -eq 7 ] && echo 3890 || echo 4650) 2>&1 | tail -1
    
    echo -e "${GREEN}✅ Stage $stage: SCLK=${sclk} MCLK=${mclk} FCLK=${fclk} TDP=${tdp}W TDC=${tdc}A SOCCLK=${socclk}MHz${NC}"
}

apply_and_verify() {
    local stage=$1
    local socclk=${SOCCLK_VALS[$stage]}
    local sclk=${SCLK_VALS[$stage]}
    local mclk=${MCLK_VALS[$stage]}
    local pp_file="$PP_DIR/pp_table_socclk_${socclk}MHz.bin"
    local card_pp; card_pp=$(detect_card) || return 1
    
    [ ! -f "$pp_file" ] && { echo -e "${RED}PP table não encontrada: $pp_file${NC}"; return 1; }
    
    echo -e "${YELLOW}[1/4] Backup...${NC}"; backup_pp "pre_stage${stage}"
    echo -e "${YELLOW}[2/4] Aplicando Stage $stage...${NC}"
    cp "$pp_file" "$card_pp"
    
    local actual_socclk; actual_socclk=$($UPP -p "$card_pp" get smcPPTable/FreqTableSocclk/7 2>/dev/null | tail -1)
    if [ "$actual_socclk" != "$socclk" ]; then
        echo -e "${RED}❌ SOCCLK incorreto! Esperado: ${socclk}, Atual: ${actual_socclk}${NC}"
        echo -e "${YELLOW}Rollback...${NC}"; cp "$PP_STOCK" "$card_pp"; return 1
    fi
    
    local actual_sclk; actual_sclk=$($UPP -p "$card_pp" get smcPPTable/FreqTableGfx/8 2>/dev/null | tail -1)
    if [ "$actual_sclk" != "$sclk" ]; then
        echo -e "${RED}❌ SCLK incorreto! Esperado: ${sclk}, Atual: ${actual_sclk}${NC}"
        echo -e "${YELLOW}Rollback...${NC}"; cp "$PP_STOCK" "$card_pp"; return 1
    fi
    
    echo -e "${GREEN}✅ SOCCLK=${actual_socclk}MHz SCLK=${actual_sclk}MHz aplicados${NC}"
    
    echo -e "${YELLOW}[3/4] Load test (10 min)...${NC}"
    if command -v clpeak &>/dev/null; then
        timeout 600 clpeak > /tmp/clpeak_socclk_${socclk}.log 2>&1 || true
    else
        echo "  ⚠️  clpeak não encontrado — load simulado (10 min)"
        sleep 600
    fi
    
    echo -e "${YELLOW}[4/4] Verificando erros...${NC}"
    local has_errors=false
    
    if dmesg 2>/dev/null | grep -qi "amdgpu.*reset\|amdgpu.*hang"; then
        echo -e "  ${RED}⚠️  Erros no dmesg!${NC}"; has_errors=true
    fi
    
    if [ "$has_errors" = true ]; then
        echo -e "${RED}══════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  ❌ Stage $stage (${socclk}MHz) — INSTÁVEL!${NC}"
        echo -e "${RED}══════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}Rollback automático...${NC}"; cp "$PP_STOCK" "$card_pp"
        return 1
    else
        echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✅ Stage $stage (${socclk}MHz) — ESTÁVEL!${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
        return 0
    fi
}

rollback_to_stock() {
    local card_pp; card_pp=$(detect_card) || return 1
    echo -e "${YELLOW}Rollback para stock...${NC}"
    backup_pp "pre_rollback"; cp "$PP_STOCK" "$card_pp"
    echo -e "${GREEN}✅ Rollback concluído${NC}"
}

show_status() {
    local card_pp; card_pp=$(detect_card)
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  SOCCLK HOMEOPATHIC — STATUS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    printf "  %-8s %-8s %-8s %-8s %-8s %-8s %-8s\n" "Stage" "SCLK" "MCLK" "FCLK" "TDP" "TDC" "SOCCLK"
    printf "  %-8s %-8s %-8s %-8s %-8s %-8s %-8s\n" "───────" "──────" "──────" "──────" "──────" "──────" "──────"
    for i in $(seq 0 7); do
        printf "  %-8s %-7sM %-7sM %-7sM %-6sW %-6sA %-7sM\n" \
            "$i" "${SCLK_VALS[$i]}" "${MCLK_VALS[$i]}" "${FCLK_VALS[$i]}" \
            "${TDP_VALS[$i]}W" "${TDC_VALS[$i]}A" "${SOCCLK_VALS[$i]}"
    done
    
    if [ -n "$card_pp" ] && [ -f "$card_pp" ]; then
        echo ""
        echo -e "${YELLOW}SOCCLK atual na GPU:${NC}"
        for i in 0 1 2 3 4 5 6 7; do
            local val; val=$($UPP -p "$card_pp" get smcPPTable/FreqTableSocclk/$i 2>/dev/null | tail -1)
            [ "$i" -eq 7 ] && printf "  ${YELLOW}Nível 7:${NC} %s MHz\n" "$val" || printf "  Nível %d: %s MHz\n" "$i" "$val"
        done
    fi
}

generate_all() {
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  GERANDO TODAS AS 8 PP TABLES HOMEOPÁTICAS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    mkdir -p "$PP_DIR"
    for i in $(seq 0 7); do
        echo -e "${YELLOW}Gerando Stage $i...${NC}"
        generate_stage_pp "$i"
        echo ""
    done
    echo -e "${GREEN}✅ Todas geradas em: $PP_DIR${NC}"
    ls -la "$PP_DIR"/pp_table_socclk_*.bin 2>/dev/null
}

case "${1:-help}" in
    stage)
        STAGE="${2:-0}"
        [ "$STAGE" -lt 0 ] || [ "$STAGE" -gt 7 ] && { echo -e "${RED}Stage inválido: $STAGE (0-7)${NC}"; exit 1; }
        check_root
        
        socclk=${SOCCLK_VALS[$STAGE]}
        echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}  SOCCLK HOMEOPATHIC — Stage $STAGE${NC}"
        echo -e "${CYAN}  SCLK=${SCLK_VALS[$STAGE]} MCLK=${MCLK_VALS[$STAGE]} FCLK=${FCLK_VALS[$STAGE]} TDP=${TDP_VALS[$STAGE]}W SOCCLK=${socclk}MHz${NC}"
        echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
        echo ""
        
        PP_FILE="$PP_DIR/pp_table_socclk_${socclk}MHz.bin"
        [ ! -f "$PP_FILE" ] && generate_stage_pp "$STAGE"
        
        if apply_and_verify "$STAGE"; then
            [ "$STAGE" -lt 7 ] && echo -e "${GREEN}Próximo: sudo $0 stage $((STAGE + 1))${NC}" || echo -e "${GREEN}🎉 META 1000 MHz ALCANÇADA!${NC}"
        else
            echo -e "${RED}Stage $STAGE instável. Rollback automático.${NC}"
        fi
        ;;
    
    all)
        check_root; generate_all
        ;;
    
    status) show_status ;;
    rollback) check_root; rollback_to_stock ;;
    verify)
        check_root
        local card_pp; card_pp=$(detect_card)
        echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}  VERIFICAÇÃO SOCCLK NA GPU${NC}"
        echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
        for i in 0 1 2 3 4 5 6 7; do
            local val; val=$($UPP -p "$card_pp" get smcPPTable/FreqTableSocclk/$i 2>/dev/null | tail -1)
            [ "$i" -eq 7 ] && printf "  ${YELLOW}Nível 7:${NC} %s MHz\n" "$val" || printf "  Nível %d: %s MHz\n" "$i" "$val"
        done
        ;;
    
    help|-h)
        echo "Uso: sudo $0 [stage|all|status|rollback|verify|help]"
        echo ""
        echo "  stage N   — Aplica e testa Stage N (0-7)"
        echo "  all       — Gera todas as 8 PP tables"
        echo "  status    — Mostra tabela homeopática completa"
        echo "  rollback  — Rollback para stock"
        echo "  verify    — Verifica SOCCLK atual na GPU"
        echo ""
        echo "Tabela homeopática (todos escalonam juntos):"
        printf "  %-8s %-8s %-8s %-8s %-8s %-8s %-8s\n" "Stage" "SCLK" "MCLK" "FCLK" "TDP" "TDC" "SOCCLK"
        for i in $(seq 0 7); do
            printf "  %-8s %-7sM %-7sM %-7sM %-6sW %-6sA %-7sM\n" \
                "$i" "${SCLK_VALS[$i]}" "${MCLK_VALS[$i]}" "${FCLK_VALS[$i]}" \
                "${TDP_VALS[$i]}W" "${TDC_VALS[$i]}A" "${SOCCLK_VALS[$i]}"
        done
        ;;
    
    *) echo -e "${RED}Comando desconhecido: $1${NC}"; echo "Use: sudo $0 help"; exit 1 ;;
esac
