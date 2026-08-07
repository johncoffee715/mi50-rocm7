#!/bin/bash
# gpu-performance-daemon-v4.sh — Gestão de clocks MI50/Pro VII com RAMPA GRADUAL
# REGRA DE OURO (usuário 2026-07-31):
#   - O salto idle→full load deve PERCORRER GRADATIVAMENTE os estágios DPM (0→7→8)
#     tanto em clock quanto em alimentação — por isso existem os 8 estágios
#   - Evita o bug de transiente: subida abrupta idle→2000MHz dispara proteção
#     de energia (corta Vcore + beep + perde vídeo)
#   - TDP 350W fixo (75W PCIe + 150W×2 8-pin = 375W disponível; 350W = teto seguro)
#
# Comportamento:
#   - Detectar carga via gpu_busy_percent
#   - Subida GRADUAL: SCLK nível a nível (0→1→2→...→8) e MCLK (0→1→2)
#   - Descida GRADUAL no idle: 8→...→0 (um nível por ciclo)
#   - Rampa em modo manual (níveis explícitos), retorna a 'auto' no idle profundo

PERF="/sys/class/drm/card1/device/power_dpm_force_performance_level"
SCLK="/sys/class/drm/card1/device/pp_dpm_sclk"
MCLK="/sys/class/drm/card1/device/pp_dpm_mclk"
BUSY="/sys/class/drm/card1/device/gpu_busy_percent"

SCLK_TARGET=8        # nível máximo (2000MHz)
MCLK_TARGET=2        # nível máximo MCLK (1120MHz)
LOAD_THRESHOLD=5     # % busy acima do qual sobe
IDLE_THRESHOLD=3     # % busy abaixo do qual desce
RAMP_STEP_SEC=1      # tempo entre cada degrau da rampa (1s por nível)
IDLE_CYCLES=15       # ciclos de idle antes de voltar a 'auto' (15 × poll)
POLL_INTERVAL=1

log() { logger -t gpu-perf-v4 "$*"; }

current_level() {
    # retorna o nível SCLK atualmente selecionado (o que tem *)
    awk '/\*/ {print $1}' "$SCLK" 2>/dev/null | tr -d ':'
}

ramp_up() {
    local cur
    cur=$(current_level)
    [ -z "$cur" ] && cur=0
    while [ "$cur" -lt "$SCLK_TARGET" ]; do
        cur=$((cur + 1))
        echo "manual" > "$PERF" 2>/dev/null
        echo "$cur" > "$SCLK" 2>/dev/null
        # MCLK acompanha até o alvo (2 níveis)
        mclk=$(( cur > MCLK_TARGET ? MCLK_TARGET : cur ))
        echo "$mclk" > "$MCLK" 2>/dev/null
        log "rampa ↑ SCLK=$cur MCLK=$mclk"
        sleep "$RAMP_STEP_SEC"
    done
}

ramp_down() {
    local cur
    cur=$(current_level)
    [ -z "$cur" ] && cur=0
    while [ "$cur" -gt 0 ]; do
        cur=$((cur - 1))
        echo "manual" > "$PERF" 2>/dev/null
        echo "$cur" > "$SCLK" 2>/dev/null
        mclk=$(( cur > MCLK_TARGET ? MCLK_TARGET : cur ))
        echo "$mclk" > "$MCLK" 2>/dev/null
        log "rampa ↓ SCLK=$cur MCLK=$mclk"
        sleep "$RAMP_STEP_SEC"
    done
}

# ─── Início ───
log "Daemon v4 iniciado — rampa gradual SCLK 0→${SCLK_TARGET}, TDP 350W fixo"
idle_count=0
state="down"  # down | up | idle

while true; do
    load=$(cat "$BUSY" 2>/dev/null || echo 0)

    if [ "$load" -ge "$LOAD_THRESHOLD" ]; then
        # carga presente — sobe gradualmente (se não estiver no topo)
        if [ "$state" != "up" ]; then
            ramp_up
            state="up"
            echo "auto" > "$PERF" 2>/dev/null
            log "topo alcançado (load=${load}%) — comutado p/ AUTO (jogo estável)"
        fi
        idle_count=0
    else
        # idle — desce gradualmente e depois volta a auto
        idle_count=$((idle_count + 1))
        if [ "$idle_count" -eq 1 ] && [ "$state" = "up" ]; then
            ramp_down
            state="down"
            log "descida completa (load=${load}%)"
        fi
        if [ "$idle_count" -ge "$IDLE_CYCLES" ]; then
            echo "auto" > "$PERF" 2>/dev/null
            state="auto"
        fi
    fi

    sleep "$POLL_INTERVAL"
done
