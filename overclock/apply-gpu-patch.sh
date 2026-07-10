#!/bin/bash
# apply-gpu-patch.sh
# Aplica TDP 350W + Overclock 2120MHz na Radeon Pro VII / MI50 via pp_table
# Deve ser executado como root no boot (systemd service)
# 
# Funciona tanto para Radeon Pro VII (card1) quanto MI50 (card0)

PP_TABLE_SYS="/sys/class/drm/card1/device/pp_table"
PP_TABLE_ALT="/sys/class/drm/card0/device/pp_table"
PP_TABLE_PCI="/sys/bus/pci/devices/0000:05:00.0/drm/card1/device/pp_table"

# Encontrar o path correto
TARGET=""
for p in "$PP_TABLE_SYS" "$PP_TABLE_PCI" "$PP_TABLE_ALT"; do
    [ -w "$p" ] && TARGET="$p" && break
done

# Caminho do diretório do script (para encontrar os patches relativos)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "$TARGET" ]; then
    # Tentar primeiro TDP patch, depois OC patch
    # O OC patch já inclui TDP 350W + clocks 2120MHz
    OC_FILE="${SCRIPT_DIR}/pp_table_patches/pp_table_overclocked_final.bin"
    
    if [ -f "$OC_FILE" ]; then
        cat "$OC_FILE" > "$TARGET"
        logger "[gpu-patch] Overclock 2120MHz + TDP 350W aplicado em $TARGET"
        echo "[gpu-patch] ✅ Overclock 2120MHz + TDP 350W aplicado"
    else
        # Fallback: tentar patches legacy
        for pf in \
            "/mnt/dados/gpu-fw/mi50/pp_table_patches/pp_table_overclocked_final.bin" \
            "/mnt/dados/gpu-fw/mi50/patched/mi50_350w_tdc300a.bin"; do
            [ -f "$pf" ] && cat "$pf" > "$TARGET" && logger "[gpu-patch] Aplicado: $pf"
        done
    fi

    # Forçar alta performance (evita idle)
    echo "high" > /sys/class/drm/card1/device/power_dpm_force_performance_level 2>/dev/null
    echo "high" > /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null
    logger "[gpu-patch] Performance level set to high"
else
    logger "[gpu-patch] ❌ ERRO: pp_table sysfs nao encontrado ou sem permissao"
    echo "[gpu-patch] ❌ ERRO: pp_table sysfs nao encontrado"
    exit 1
fi
