#!/bin/bash
# mi50-apply-pp.sh — Aplica PP table modificada na AMD Radeon Pro VII / MI50
# Uso: ./mi50-apply-pp.sh [caminho/para/pp_table_mod.bin]
#      ./mi50-apply-pp.sh --install    (instala systemd service)
#      ./mi50-apply-pp.sh --status     (verifica estado atual)
#
# Alvos atuais (2026-07-28): 350W / SCLK 2000 / MCLK 1200 / FCLK 1200 / SOCCLK 1165
# Baseado em análise UPP da VBIOS 113-D1640700-100 (Vega20, gfx906, Lenovo)

set -euo pipefail

PP_SRC="${1:-/etc/mi50-oc/pp_table_active.bin}"
# Auto-detecta card: procura vendor 0x1002 com pp_table >= 1730 bytes
for _card in /sys/class/drm/card*/device; do
    _vendor=$(cat "$_card/vendor" 2>/dev/null)
    _pp="$_card/pp_table"
    if [ "$_vendor" = "0x1002" ] && [ -f "$_pp" ]; then
        PP_SYSFS="$_pp"
        break
    fi
done
PP_SYSFS="${PP_SYSFS:-/sys/class/drm/card1/device/pp_table}"
BACKUP_DIR="/etc/mi50-oc/backup"
SERVICE_NAME="mi50-apply-pp"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
UPP_BIN="$(command -v upp 2>/dev/null || echo /home/johncoffee/.local/bin/upp)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}ERRO: Este script precisa ser executado como root.${NC}"
        echo "Use: sudo $0 $*"
        exit 1
    fi
}

check_gpu() {
    if [ ! -f "$PP_SYSFS" ]; then
        echo -e "${RED}ERRO: GPU não encontrada em $PP_SYSFS${NC}"
        echo "Verifique se o driver amdgpu está carregado."
        exit 1
    fi
}

backup_original() {
    mkdir -p "$BACKUP_DIR"
    local backup="$BACKUP_DIR/pp_table_stock.$(date +%Y%m%d_%H%M%S).bin"
    cat "$PP_SYSFS" > "$backup"
    echo -e "${GREEN}✅ Backup salvo: $backup${NC}"
    sha256sum "$backup"
}

apply_pp_table() {
    local src="$1"
    if [ ! -f "$src" ]; then
        echo -e "${RED}ERRO: Arquivo não encontrado: $src${NC}"
        exit 1
    fi

    # Validação rápida: tamanho deve ser 1730 bytes
    local size
    size=$(stat -c%s "$src" 2>/dev/null || stat -f%z "$src" 2>/dev/null)
    if [ "$size" -ne 1730 ]; then
        echo -e "${RED}ERRO: Tamanho inválido da PP table: ${size}B (esperado 1730B)${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Aplicando PP table: ${src}${NC}"
    cp "$src" "$PP_SYSFS"
    echo -e "${GREEN}✅ PP table aplicada com sucesso!${NC}"
}

status() {
    echo "=== PP Table Atual ==="
    if [ -f "$PP_SYSFS" ]; then
        local hash
        hash=$(sha256sum "$PP_SYSFS" | cut -d' ' -f1)
        echo "Hash: $hash"
        if command -v upp &>/dev/null; then
            upp -p "$PP_SYSFS" dump 2>/dev/null | grep -E "PowerLimit|FreqTableGfx|FreqTableUclk|ShutdownTemp" | head -10
        else
            echo "UPP não encontrado. Instale via: pipx install upp"
        fi
    else
        echo "GPU não detectada."
    fi

    echo
    echo "=== Backups Disponíveis ==="
    ls -la "$BACKUP_DIR" 2>/dev/null | grep "pp_table_stock" | tail -5 || echo "(nenhum backup encontrado)"

    echo
    echo "=== Serviço Systemd ==="
    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null 2>&1; then
        systemctl status "$SERVICE_NAME" --no-pager 2>&1 | head -10
    else
        echo "Serviço não instalado."
    fi
}

install_service() {
    echo -e "${YELLOW}Instalando serviço systemd...${NC}"

    # Copia script para /usr/local/bin
    cp "$0" /usr/local/bin/mi50-apply-pp.sh
    chmod +x /usr/local/bin/mi50-apply-pp.sh

    # Cria diretório de configuração
    mkdir -p /etc/mi50-oc /etc/mi50-oc/backup

    # Backup da PP table original (boot)
    if [ -f "$PP_SYSFS" ] && [ ! -f /etc/mi50-oc/pp_table_stock.bin ]; then
        cat "$PP_SYSFS" > /etc/mi50-oc/pp_table_stock.bin
        echo -e "${GREEN}✅ PP table stock salva em /etc/mi50-oc/pp_table_stock.bin${NC}"
    fi

    # Cria o service
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=mi50-oc — Apply PowerPlay table tweaks for AMD MI50 (Vega20)
After=multi-user.target
Before=lightdm.service gdm.service sddm.service

[Service]
Type=oneshot
ExecStartPre=/bin/bash -c 'while [ ! -f /sys/class/drm/card1/device/pp_table ]; do sleep 1; done'
ExecStart=/usr/local/bin/mi50-apply-pp.sh /etc/mi50-oc/pp_table_active.bin
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Cria link simbólico para a PP table ativa
    if [ ! -f /etc/mi50-oc/pp_table_active.bin ]; then
        cp /etc/mi50-oc/pp_table_stock.bin /etc/mi50-oc/pp_table_active.bin
        echo -e "${YELLOW}⚠️  Nenhuma PP table ativa configurada.${NC}"
        echo "Copie uma PP table modificada para /etc/mi50-oc/pp_table_active.bin"
    fi

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    echo -e "${GREEN}✅ Serviço instalado e habilitado.${NC}"
    echo "Para ativar agora: sudo systemctl start $SERVICE_NAME"
}

# --- Main ---
case "${1:-}" in
    --install)
        check_root
        install_service
        ;;
    --status|status)
        status
        ;;
    --backup)
        check_root
        check_gpu
        backup_original
        ;;
    --help|-h)
        echo "Uso: $0 [pp_table.bin | --install | --status | --backup | --help]"
        echo ""
        echo "  pp_table.bin    Aplica PP table modificada (runtime)"
        echo "  --install       Instala serviço systemd para persistência"
        echo "  --status        Mostra estado atual da PP table"
        echo "  --backup        Faz backup da PP table original"
        echo "  --help          Mostra esta ajuda"
        exit 0
        ;;
    *)
        check_root
        check_gpu
        backup_original
        apply_pp_table "$PP_SRC"
        ;;
esac
