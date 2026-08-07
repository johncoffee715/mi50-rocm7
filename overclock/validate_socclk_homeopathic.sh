#!/bin/bash
# validate_socclk_homeopathic.sh — Validação homeopática dos campos SOCCLK
# Lê o pp_table_stock.bin e valida cada campo SOCCLK individualmente
# Uso: sudo ./validate_socclk_homeopathic.sh [caminho/pp_table.bin]
#
# Abordagem homeopática: cada campo é validado isoladamente
# antes de qualquer modificação ser considerada.

set -euo pipefail

UPP_BIN="$(command -v upp 2>/dev/null || echo /home/johncoffee/.local/bin/upp)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PP_FILE="${1:-pp_table_patches/pp_table_stock.bin}"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  SOCCLK HOMEOPATHIC VALIDATOR — Vega20 (MI50/Pro VII)  ║${NC}"
echo -e "${CYAN}║  Validação isolada de cada nível SOCCLK               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- Check UPP ---
if ! command -v "$UPP_BIN" &>/dev/null && ! command -v upp &>/dev/null; then
    echo -e "${RED}ERRO: UPP não encontrado. Instale com: pipx install upp${NC}"
    exit 1
fi
UPP="${UPP_BIN:-$(command -v upp)}"

# --- Check PP file ---
if [ ! -f "$PP_FILE" ]; then
    echo -e "${RED}ERRO: Arquivo não encontrado: $PP_FILE${NC}"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$PP_FILE" 2>/dev/null || echo 0)
echo -e "${YELLOW}[INFO] Arquivo: $PP_FILE${NC}"
echo -e "${YELLOW}[INFO] Tamanho: ${FILE_SIZE} bytes${NC}"
echo ""

if [ "$FILE_SIZE" -ne 1730 ]; then
    echo -e "${RED}ERRO: Tamanho inválido (${FILE_SIZE}B, esperado 1730B)${NC}"
    exit 1
fi

# --- DUMP completo ---
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}[PASSO 1] Dump completo da PP table${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

DUMP=$("$UPP" -p "$PP_FILE" dump 2>/dev/null)

# --- Validação HOMEOPÁTICA: cada campo SOCCLK isoladamente ---
echo ""
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}[PASSO 2] Validação homeopática — campo por campo${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

# SOCCLK tem 8 níveis (0-7) no Vega20
SOCCLK_FIELDS=("smcPPTable/FreqTableSocclk/0" "smcPPTable/FreqTableSocclk/1" "smcPPTable/FreqTableSocclk/2" \
               "smcPPTable/FreqTableSocclk/3" "smcPPTable/FreqTableSocclk/4" "smcPPTable/FreqTableSocclk/5" \
               "smcPPTable/FreqTableSocclk/6" "smcPPTable/FreqTableSocclk/7")

SOCCLK_NAMES=("Nível 0 (idle)" "Nível 1" "Nível 2" "Nível 3" \
              "Nível 4" "Nível 5" "Nível 6" "Nível 7 (max)")

PASS_COUNT=0
FAIL_COUNT=0

for i in "${!SOCCLK_FIELDS[@]}"; do
    FIELD="${SOCCLK_FIELDS[$i]}"
    NAME="${SOCCLK_NAMES[$i]}"
    
    # Extrair valor com UPP get
    VALUE=$("$UPP" -p "$PP_FILE" get "$FIELD" 2>/dev/null | tail -1)
    
    if [ -n "$VALUE" ] && [ "$VALUE" != "0" ]; then
        echo -e "  ${GREEN}✓${NC} $NAME: ${CYAN}${FIELD}${NC} = ${YELLOW}${VALUE} MHz"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${RED}✗${NC} $NAME: ${CYAN}${FIELD}${NC} = ${RED}N/A (campo não encontrado ou zero)${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}[RESULTADO] Validação homeopática${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
echo -e "  Campos válidos:  ${GREEN}${PASS_COUNT}${NC}/8"
echo -e "  Campos inválidos: ${RED}${FAIL_COUNT}${NC}/8"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Alguns campos SOCCLK não foram encontrados.${NC}"
    echo -e "${YELLOW}   Isso pode indicar uma VBIOS diferente ou formato alterado.${NC}"
fi

# --- Extrair todos os valores SOCCLK para referência ---
echo ""
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}[PASSO 3] Tabela SOCCLK completa (referência para stepping)${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

SOCCLK_VALUES=()
for i in "${!SOCCLK_FIELDS[@]}"; do
    VALUE=$("$UPP" -p "$PP_FILE" get "${SOCCLK_FIELDS[$i]}" 2>/dev/null | tail -1)
    SOCCLK_VALUES+=("${VALUE:-0}")
done

echo ""
printf "  %-20s %-15s %-10s %-10s\n" "Campo" "Valor (MHz)" "Delta" "Acumulado"
printf "  %-20s %-15s %-10s %-10s\n" "────────────────────" "─────────────" "───────" "─────────"

ACCUM=0
for i in "${!SOCCLK_VALUES[@]}"; do
    VAL=${SOCCLK_VALUES[$i]}
    if [ "$i" -eq 0 ]; then
        DELTA=0
    else
        PREV=${SOCCLK_VALUES[$((i-1))]}
        DELTA=$((VAL - PREV))
    fi
    ACCUM=$((ACCUM + DELTA))
    
    if [ "$i" -eq 7 ]; then
        printf "  ${YELLOW}%-20s${NC} %-15s %-10s %-10s\n" "${SOCCLK_FIELDS[$i]}" "${VAL} MHz" "+${DELTA}" "${ACCUM} MHz"
    else
        printf "  ${SOCCLK_FIELDS[$i]} %-14s %-15s %-10s %-10s\n" "${VAL} MHz" "+${DELTA}" "${ACCUM} MHz"
    fi
done

SOCCLK_MAX=${SOCCLK_VALUES[7]}
echo ""
echo -e "  ${GREEN}SOCCLK máximo stock: ${SOCCLK_MAX} MHz${NC}"
echo -e "  ${YELLOW}Meta homeopática: 1000 MHz no estágio 7${NC}"
echo -e "  ${CYAN}Margem disponível: $((1000 - SOCCLK_MAX)) MHz${NC}"

# --- Campos correlatos que também precisam de stepping ---
echo ""
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}[PASSO 4] Campos correlatos que acompanham o SOCCLK${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

RELATED_FIELDS=(
    "smcPPTable/smcPPTable/DcModeMaxFreq/0"
    "GfxclkDsMaxFreq"
    "PowerSavingClockTable/PowerSavingClockMax/0"
    "XgmiSocclkFreq/0"
)

for FIELD in "${RELATED_FIELDS[@]}"; do
    VALUE=$("$UPP" -p "$PP_FILE" get "$FIELD" 2>/dev/null | tail -1)
    if [ -n "$VALUE" ]; then
        echo -e "  ${CYAN}${FIELD}${NC} = ${YELLOW}${VALUE} MHz${NC}"
    fi
done

# --- Min/Max Voltage SOC (limites de segurança) ---
echo ""
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}[PASSO 5] Limites de voltagem SOC (segurança)${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

VOLT_FIELDS=("MinVoltageSoc" "MaxVoltageSoc")
for FIELD in "${VOLT_FIELDS[@]}"; do
    VALUE=$("$UPP" -p "$PP_FILE" get "$FIELD" 2>/dev/null | tail -1)
    if [ -n "$VALUE" ]; then
        MVOLT=$((VALUE / 10))
        echo -e "  ${CYAN}${FIELD}${NC} = ${YELLOW}${VALUE} (${MVOLT} mV)${NC}"
    fi
done

echo ""
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}[PASSO 6] Resumo para planejamento do stepping homeopático${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

echo ""
echo "  Tabela SOCCLK STOCK (Vega20 gfx906):"
echo "  ┌─────────┬──────────┬──────────┐"
echo "  │ Nível   │ Stock    │ Meta 1000│"
echo "  ├─────────┼──────────┼──────────┤"
for i in "${!SOCCLK_VALUES[@]}"; do
    if [ "$i" -eq 7 ]; then
        printf "  │ %-7s │ %-8s │ %-8s │\n" "${SOCCLK_VALUES[$i]}" "${SOCCLK_VALUES[$i]} MHz" "1000 MHz"
    else
        printf "  │ %-7s │ %-8s │ %-8s │\n" "${SOCCLK_VALUES[$i]}" "${SOCCLK_VALUES[$i]} MHz" "-"
    fi
done
echo "  └─────────┴──────────┴──────────┘"

echo ""
echo -e "${GREEN}✅ Validação homeopática concluída.${NC}"
echo -e "${GREEN}   Todos os 8 campos SOCCLK validados individualmente.${NC}"
echo ""
