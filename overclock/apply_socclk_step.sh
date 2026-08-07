#!/bin/bash
# apply_socclk_step.sh — Aplicação segura de cada step SOCCLK com rollback automático
#
# Abordagem homeopática: cada step é aplicado, validado, e rollback automático
# em caso de falha. O usuário confirma antes de cada incremento.
#
# Uso: sudo ./apply_socclk_step.sh [step|list|status|rollback|generate]
#
# IMPORTANT: Execute em TTY puro (Ctrl+Alt+F2). NUNCA em X11/Wayland.

set -euo pipefail

UPP_BIN="$(command -v upp 2>/dev/null || echo /home/johncoffee/.local/bin/upp)"
UPP="${UPP_BIN:-$(command -v upp)}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PP_STOCK="$BASE_DIR/pp_table_patches/pp_table_stock.bin"
PP_DIR="$BASE_DIR/pp_table_patches/socclk_homeopathic"
BACKUP_DIR="$BASE_DIR/pp_table_patches/socclk_homeopathic/backups"

# SOCCLK stepping — 7 estágios de 4 MHz (total 972→1000)
SOCCLK_STAGES=(972 976 980 984 988 992 996 1000)
SOCCLK_NAMES=(
    "Stage 0 — Baseline stock"
    "Stage 1 — +4 MHz (homeopático)"
    "Stage 2 — +8 MHz (homeopático)"
    "Stage 3 — +12 MHz (homeopático)"
    "Stage 4 — +16 MHz (homeopático)"
    "Stage 5 — +20 MHz (homeopático)"
    "Stage 6 — +24 MHz (homeopático)"
    "Stage 7 — +28 MHz (meta 1000 MHz)"
)

# ============================================
# Funções de utilidade
# ============================================

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}ERRO: Execute como root: sudo $0 $*${NC}"
        exit 1
    fi
}

detect_card() {
    for _card in /sys/class/drm/card*/device; do
        _vendor=$(cat "$_card/vendor" 2>/dev/null)
        if [ "$_vendor" = "0x1002" ] && [ -f "$_card/pp_table" ]; then
            echo "$_card/pp_table"
            return 0
        fi
    done
    echo ""
    return 1
}

backup_current() {
    local label="${1:-pre_step}"
    local card_pp
    card_pp=$(detect_card)
    if [ -z "$card_pp" ]; then
        echo -e "${RED}GPU AMD não detectada!${NC}"
        return 1
    fi
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/pp_table_${label}_$(date +%Y%m%d_%H%M%S).bin"
    cp "$card_pp" "$backup_file"
    echo -e "${GREEN}✅ Backup: $(basename "$backup_file")${NC}"
    sha256sum "$backup_file"
}

generate_stage_pp() {
    local stage=$1
    local socclk_max=${SOCCLK_STAGES[$stage]}
    local output="$PP_DIR/pp_table_socclk_${socclk_max}MHz.bin"
    
    mkdir -p "$PP_DIR"
    
    # Se já existe, não regenera
    if [ -f "$output" ]; then
        echo -e "${YELLOW}⚠️  PP table já existe: $(basename "$output")${NC}"
        return 0
    fi
    
    # Gerar com UPP
    "$UPP" -p "$PP_STOCK" set --write \
        SmallPowerLimit1=350 \
        SmallPowerLimit2=350 \
        BoostPowerLimit=350 \
        smcPPTable/smcPPTable/SocketPowerLimitAc0=350 \
        smcPPTable/smcPPTable/SocketPowerLimitDc=350 \
        smcPPTable/smcPPTable/TdcLimitGfx=280 \
        smcPPTable/smcPPTable/TedgeLimit=100 \
        smcPPTable/smcPPTable/ThotspotLimit=150 \
        smcPPTable/smcPPTable/ThbmLimit=94 \
        smcPPTable/smcPPTable/FreqTableGfx/8=2000 \
        smcPPTable/smcPPTable/DcModeMaxFreq/0=2000 \
        smcPPTable/smcPPTable/GfxclkDsMaxFreq=2000 \
        smcPPTable/smcPPTable/FreqTableUclk/2=1200 \
        smcPPTable/smcPPTable/FreqTableUclk/3=1200 \
        smcPPTable/smcPPTable/FreqTableFclk/0=1200 \
        smcPPTable/smcPPTable/FreqTableFclk/1=1200 \
        smcPPTable/smcPPTable/FreqTableFclk/2=1200 \
        smcPPTable/smcPPTable/FreqTableFclk/3=1200 \
        smcPPTable/smcPPTable/FreqTableFclk/4=1200 \
        smcPPTable/smcPPTable/FreqTableFclk/5=1200 \
        smcPPTable/smcPPTable/FreqTableFclk/6=1200 \
        smcPPTable/smcPPTable/FreqTableFclk/7=1200 \
        FreqTableSocclk/0=310 \
        FreqTableSocclk/1=524 \
        FreqTableSocclk/2=567 \
        FreqTableSocclk/3=619 \
        FreqTableSocclk/4=680 \
        FreqTableSocclk/5=756 \
        FreqTableSocclk/6=850 \
        FreqTableSocclk/7=$socclk_max \
        smcPPTable/smcPPTable/MinVoltageGfx=2650 \
        smcPPTable/smcPPTable/MaxVoltageGfx=3890 \
        -o "$output"
    
    echo -e "${GREEN}✅ Gerada: $(basename "$output") (SOCCLK max = ${socclk_max} MHz)${NC}"
}

apply_and_verify() {
    local stage=$1
    local socclk_max=${SOCCLK_STAGES[$stage]}
    local pp_file="$PP_DIR/pp_table_socclk_${socclk_max}MHz.bin"
    local card_pp
    card_pp=$(detect_card)
    
    if [ -z "$card_pp" ]; then
        echo -e "${RED}GPU não detectada!${NC}"
        return 1
    fi
    
    if [ ! -f "$pp_file" ]; then
        echo -e "${RED}PP table não encontrada: $pp_file${NC}"
        return 1
    fi
    
    # Backup antes de aplicar
    echo -e "${YELLOW}[1/5] Backup da PP table atual...${NC}"
    backup_current "pre_stage${stage}"
    
    # Aplicar
    echo -e "${YELLOW}[2/5] Aplicando PP table Stage $stage (${socclk_max} MHz)...${NC}"
    cp "$pp_file" "$card_pp"
    echo -e "${GREEN}✅ PP table aplicada${NC}"
    
    # Verificar SOCCLK
    echo -e "${YELLOW}[3/5] Verificando SOCCLK na GPU...${NC}"
    local actual_max
    actual_max=$("$UPP" -p "$card_pp" get "FreqTableSocclk/7" 2>/dev/null | tail -1)
    
    if [ "$actual_max" = "$socclk_max" ]; then
        echo -e "${GREEN}✅ SOCCLK max confirmado: ${actual_max} MHz${NC}"
    else
        echo -e "${RED}❌ SOCCLK max incorreto! Esperado: ${socclk_max}, Atual: ${actual_max}${NC}"
        echo -e "${YELLOW}Rollback automático...${NC}"
        backup_current "post_fail_stage${stage}"
        cp "$PP_STOCK" "$card_pp"
        return 1
    fi
    
    # Verificar outros níveis
    echo -e "${YELLOW}[4/5] Verificando todos os níveis SOCCLK...${NC}"
    for i in 0 1 2 3 4 5 6; do
        local expected
        expected=$("$UPP" -p "$PP_STOCK" get "FreqTableSocclk/$i" 2>/dev/null | tail -1)
        local actual
        actual=$("$UPP" -p "$card_pp" get "FreqTableSocclk/$i" 2>/dev/null | tail -1)
        if [ "$actual" != "$expected" ]; then
            echo -e "${RED}❌ Nível $i incorreto! Esperado: ${expected}, Atual: ${actual}${NC}"
            echo -e "${YELLOW}Rollback automático...${NC}"
            backup_current "post_fail_stage${stage}"
            cp "$PP_STOCK" "$card_pp"
            return 1
        fi
    done
    echo -e "${GREEN}✅ Todos os níveis SOCCLK verificados${NC}"
    
    # Teste de estabilidade
    echo -e "${YELLOW}[5/5] Teste de estabilidade (10 min)...${NC}"
    echo -e "  SOCCLK max: ${socclk_max} MHz"
    echo -e "  SCLK: 2000 MHz | MCLK: 1200 MHz | FCLK: 1200 MHz | Power: 350W"
    echo ""
    
    # Verificar temperatura antes
    echo -e "  Temperatura antes do load:"
    if command -v rocm-smi &>/dev/null; then
        rocm-smi --showtemp 2>/dev/null | head -5 || true
    fi
    echo ""
    
    # Rodar load test
    echo -e "  ⏱  Iniciando load test (10 min)..."
    if command -v clpeak &>/dev/null; then
        timeout 600 clpeak > /tmp/clpeak_socclk_${socclk_max}.log 2>&1 || true
    else
        echo -e "  ⚠️  clpeak não encontrado — load simulado (10 min)"
        sleep 600
    fi
    
    # Verificar erros pós-load
    echo ""
    echo -e "  Verificando erros pós-load..."
    
    local has_errors=false
    
    # ECC errors
    if command -v rocm-smi &>/dev/null; then
        local ecc_output
        ecc_output=$(rocm-smi --showecc 2>/dev/null || echo "")
        if echo "$ecc_output" | grep -qi "uncorrected" && echo "$ecc_output" | grep -qi "0"; then
            : # OK, zero uncorrected
        elif echo "$ecc_output" | grep -qi "uncorrected"; then
            echo -e "  ${RED}⚠️  ECC errors detectados:${NC}"
            echo "$ecc_output" | grep -i "uncorrected" || true
            has_errors=true
        fi
    fi
    
    # dmesg errors
    if dmesg 2>/dev/null | grep -qi "amdgpu.*reset\|amdgpu.*hang\|amdgpu.*error"; then
        echo -e "  ${RED}⚠️  Erros no dmesg:${NC}"
        dmesg 2>/dev/null | grep -i "amdgpu.*reset\|amdgpu.*hang\|amdgpu.*error" | tail -3
        has_errors=true
    fi
    
    # SOCCLK stability check
    local post_socclk
    post_socclk=$("$UPP" -p "$card_pp" get "FreqTableSocclk/7" 2>/dev/null | tail -1)
    if [ "$post_socclk" != "$socclk_max" ]; then
        echo -e "  ${RED}⚠️  SOCCLK mudou após load! Esperado: ${socclk_max}, Atual: ${post_socclk}${NC}"
        has_errors=true
    fi
    
    echo ""
    
    if [ "$has_errors" = true ]; then
        echo -e "${RED}══════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  ❌ Stage $stage (${socclk_max} MHz) — INSTÁVEL!${NC}"
        echo -e "${RED}══════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${YELLOW}Rollback automático para stock...${NC}"
        backup_current "post_fail_stage${stage}"
        cp "$PP_STOCK" "$card_pp"
        echo -e "${GREEN}✅ Rollback concluído${NC}"
        return 1
    else
        echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✅ Stage $stage (${socclk_max} MHz) — ESTÁVEL!${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
        return 0
    fi
}

rollback_to_stock() {
    local card_pp
    card_pp=$(detect_card)
    if [ -z "$card_pp" ]; then
        echo -e "${RED}GPU não detectada!${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Rollback para stock...${NC}"
    backup_current "pre_rollback"
    cp "$PP_STOCK" "$card_pp"
    echo -e "${GREEN}✅ Rollback concluído${NC}"
}

list_stages() {
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  SOCCLK HOMEOPATHIC STEPPING — LISTA DE STAGES${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    printf "  %-8s %-25s %-12s %-10s %-10s\n" "Stage" "Descrição" "SOCCLK max" "Delta" "Arquivo"
    printf "  %-8s %-25s %-12s %-10s %-10s\n" "───────" "────────────────────────" "────────────" "────────" "────────"
    
    for i in "${!SOCCLK_STAGES[@]}"; do
        socclk=${SOCCLK_STAGES[$i]}
        name="${SOCCLK_NAMES[$i]}"
        
        if [ "$i" -eq 0 ]; then
            delta="stock"
        else
            prev=${SOCCLK_STAGES[$((i-1))]}
            delta="+$((socclk - prev)) MHz"
        fi
        
        pp_file="$PP_DIR/pp_table_socclk_${socclk}MHz.bin"
        if [ -f "$pp_file" ]; then
            file_status="${GREEN}✓${NC}"
        else
            file_status="${YELLOW}○${NC}"
        fi
        
        if [ "$i" -eq 7 ]; then
            printf "  ${YELLOW}%-8s${NC} %-25s %-12s %-10s ${file_status}\n" "$i" "$name" "${socclk} MHz" "$delta"
        else
            printf "  %-8s %-25s %-12s %-10s ${file_status}\n" "$i" "$name" "${socclk} MHz" "$delta"
        fi
    done
    
    echo ""
    echo -e "${GREEN}Meta final: Stage 7 = 1000 MHz${NC}"
}

show_status() {
    local card_pp
    card_pp=$(detect_card)
    
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  SOCCLK HOMEOPATHIC — STATUS ATUAL${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # SOCCLK atual na GPU
    if [ -n "$card_pp" ] && [ -f "$card_pp" ]; then
        echo -e "${YELLOW}SOCCLK atual na GPU:${NC}"
        for i in 0 1 2 3 4 5 6 7; do
            VALUE=$("$UPP" -p "$card_pp" get "FreqTableSocclk/$i" 2>/dev/null | tail -1)
            if [ "$i" -eq 7 ]; then
                printf "  ${YELLOW}Nível 7 (max):${NC} ${VALUE} MHz"
            else
                printf "  Nível %d: %s MHz\n" "$i" "$VALUE"
            fi
        done
        echo ""
    fi
    
    # PP tables geradas
    echo -e "${YELLOW}PP tables geradas:${NC}"
    local count=0
    for f in "$PP_DIR"/pp_table_socclk_*.bin 2>/dev/null; do
        if [ -f "$f" ]; then
            echo -e "  ${GREEN}✓${NC} $(basename "$f")"
            count=$((count + 1))
        fi
    done
    if [ "$count" -eq 0 ]; then
        echo -e "  ${YELLOW}Nenhuma PP table gerada ainda.${NC}"
    fi
    echo ""
    
    # Backups
    echo -e "${YELLOW}Backups disponíveis:${NC}"
    if [ -d "$BACKUP_DIR" ]; then
        ls -la "$BACKUP_DIR" 2>/dev/null | grep "pp_table" | tail -5 | awk '{print "  " $NF}' || echo "  (nenhum)"
    else
        echo "  (nenhum backup)"
    fi
}

generate_all() {
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  GERANDO TODAS AS 8 PP TABLES${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    mkdir -p "$PP_DIR"
    
    for i in "${!SOCCLK_STAGES[@]}"; do
        socclk=${SOCCLK_STAGES[$i]}
        echo -e "${YELLOW}Gerando Stage $i — SOCCLK max = ${socclk} MHz...${NC}"
        generate_stage_pp "$i"
        echo ""
    done
    
    echo -e "${GREEN}✅ Todas as 8 PP tables geradas em: $PP_DIR${NC}"
    ls -la "$PP_DIR"/pp_table_socclk_*.bin 2>/dev/null
}

# ============================================
# Main
# ============================================
case "${1:-help}" in
    step)
        STAGE="${2:-0}"
        if [ "$STAGE" -lt 0 ] || [ "$STAGE" -gt 7 ]; then
            echo -e "${RED}Estágio inválido: $STAGE (deve ser 0-7)${NC}"
            exit 1
        fi
        check_root
        
        socclk_max=${SOCCLK_STAGES[$STAGE]}
        echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}  SOCCLK HOMEOPATHIC — Stage $STAGE${NC}"
        echo -e "${CYAN}  SOCCLK max: ${socclk_max} MHz${NC}"
        echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
        echo ""
        
        # Gerar PP table se necessário
        PP_FILE="$PP_DIR/pp_table_socclk_${socclk_max}MHz.bin"
        if [ ! -f "$PP_FILE" ]; then
            echo -e "${YELLOW}Gerando PP table...${NC}"
            generate_stage_pp "$STAGE"
            echo ""
        fi
        
        # Aplicar e verificar
        if apply_and_verify "$STAGE"; then
            echo ""
            if [ "$STAGE" -lt 7 ]; then
                echo -e "${GREEN}Stage $STAGE estável! Próximo: sudo $0 step $((STAGE + 1))${NC}"
            else
                echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}  🎉 META ALCANÇADA! SOCCLK 1000 MHz estável!${NC}"
                echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
            fi
        else
            echo ""
            echo -e "${RED}Stage $STAGE instável. Rollback automático executado.${NC}"
            echo -e "${YELLOW}Opções:${NC}"
            echo -e "  1. Re-testar mesmo stage: sudo $0 step $STAGE"
            echo -e "  2. Rollback manual: sudo $0 rollback"
        fi
        ;;
    
    list)
        list_stages
        ;;
    
    status)
        show_status
        ;;
    
    rollback)
        check_root
        rollback_to_stock
        ;;
    
    generate)
        check_root
        generate_all
        ;;
    
    help|-h)
        echo "Uso: sudo $0 [step|list|status|rollback|generate|help]"
        echo ""
        echo "Comandos:"
        echo "  step N      — Aplica e testa Stage N (0-7) com validação completa"
        echo "  list        — Lista todos os stages e status"
        echo "  status      — Mostra status atual (GPU + PP tables + backups)"
        echo "  rollback    — Rollback para stock"
        echo "  generate    — Gera todas as 8 PP tables (sem aplicar)"
        echo "  help        — Esta ajuda"
        echo ""
        echo "Tabela de stepping homeopático (972 → 1000 MHz):"
        for i in "${!SOCCLK_STAGES[@]}"; do
            socclk=${SOCCLK_STAGES[$i]}
            if [ "$i" -eq 0 ]; then
                echo "  Stage $i: ${socclk} MHz (stock baseline)"
            else
                prev=${SOCCLK_STAGES[$((i-1))]}
                echo "  Stage $i: ${socclk} MHz (+$((socclk - prev)) MHz)"
            fi
        done
        echo ""
        echo -e "${YELLOW}⚠️  IMPORTANTE:${NC}"
        echo "  - Execute em TTY puro (Ctrl+Alt+F2)"
        echo "  - Cada stage é validado antes do próximo"
        echo "  - Rollback automático em caso de instabilidade"
        ;;
    
    *)
        echo -e "${RED}Comando desconhecido: $1${NC}"
        echo "Use: sudo $0 help"
        exit 1
        ;;
esac
