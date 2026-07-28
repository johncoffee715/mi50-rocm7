# Plano de Validação — Overclock MI50 / Radeon Pro VII

## Baseline (VBIOS 113-D1640700-100, GPU 0x66a1 Lenovo)

- GPU instalada em: `0000:05:00.0`
- Cooler: Watercooler custom 1200×20mm
- Kernel: linux-cachyos com `amdgpu.ppfeaturemask=0xffffffff`
- ROCm: instalado e funcional

## PP tables Disponíveis

| Arquivo | SHA-256 | SCLK | MCLK | Power | Descrição |
|---------|---------|------|------|-------|-----------|
| `pp_table_stock.bin` | `3d341947c3b5613e...` | 1700 | 1000 | 190W | Stock backup (dump real da GPU) |
| `pp_table_250w.bin` | `c5047a9bb35c680f...` | 1700 | 1000 | 250W | Apenas power limit |
| `pp_table_1800mhz.bin` | `134e9d7be1f9a61e...` | 1800 | 1000 | 250W | SCLK leve |
| `pp_table_2000mhz.bin` | `e52369bd2c4e3465...` | 2000 | 1000 | 250W | SCLK médio |
| `pp_table_2000mhz_mclk.bin` | `703f188b158cc407...` | 2000 | 1100 | 250W | SCLK + MCLK |
| `pp_table_final.bin` | `798731f001162d30...` | **2100** | **1200** | **300W** | Alvo final |

## Estágios de Validação

### Stage 1 — Baseline ✅ (completo)

- [x] GPU detectada via rocm-smi
- [x] VBIOS version: 113-D1640700-100
- [x] Device ID: 0x66a1, Subsystem: Lenovo 0x103e
- [x] SHA-256 pp_table stock: `3d341947c3b5613e296d768ad35b654a46b485f77576099c5a1c7d9920d9ffe6`
- [x] Temperatura idle: 28°C edge, 32°C junction
- [x] Power idle: 23W
- [x] I2C buses escaneados (IR35217 não visível no SMU bus)
- [ ] **Pendente:** Teste de baseline com carga (`clpeak`)

### Stage 2 — Power Limit 250W

- Arquivo: `pp_table_patches/pp_table_250w.bin`
- [ ] Aplicar: `sudo cp pp_table_250w.bin /sys/class/drm/card0/device/pp_table`
- [ ] `rocm-smi --showpower` confirma novo power limit
- [ ] `clpeak` 15 min sem crash
- [ ] Temperatura junction < 85°C
- [ ] ECC corrected == 0 (antes e depois)
- [ ] Vídeo permanece ativo

### Stage 3 — SCLK 1800MHz

- Arquivo: `pp_table_patches/pp_table_1800mhz.bin`
- [ ] Aplicar: `sudo cp pp_table_1800mhz.bin /sys/class/drm/card0/device/pp_table`
- [ ] `cat pp_dpm_sclk` mostra 1800MHz disponível
- [ ] `clpeak` 15 min estável
- [ ] Temperatura junction < 85°C

### Stage 4 — SCLK 2000MHz

- Arquivo: `pp_table_patches/pp_table_2000mhz.bin`
- [ ] Aplicar
- [ ] `clpeak` 30 min
- [ ] Temperatura junction < 95°C

### Stage 5 — MCLK 1100MHz + 2000MHz SCLK

- Arquivo: `pp_table_patches/pp_table_2000mhz_mclk.bin`
- [ ] Verificar ECC counters antes da aplicação
- [ ] Aplicar
- [ ] Verificar clocks via sysfs
- [ ] `clpeak` 30 min
- [ ] Verificar ECC uncorrected == 0

### Stage 6 — Final: 2100MHz / 1200MHz / 300W

- Arquivo: `pp_table_patches/pp_table_final.bin`
- [ ] Verificar todos os parâmetros via UPP dump
- [ ] Aplicar
- [ ] `clpeak` benchmark completo
- [ ] 2h de carga contínua (clpeak + llama.cpp)
- [ ] Monitorar ECC, temperatura, throttling, PCIe AER

## Condições de Rollback Imediato

| Condição | Ação |
|----------|------|
| ❌ Perda de vídeo sob carga (watchdog SMU) | Reboot obrigatório |
| ❌ ECC uncorrected errors > 0 | Reverter para step anterior |
| ❌ GPU reset detectado (`dmesg \| grep reset`) | Reboot + reavaliar |
| ❌ Temperatura junction > 95°C | Parar carga, reduzir clock |
| ❌ PCIe AER errors | Verificar slot/solda |

## Comandos Úteis

```bash
# Monitoramento em tempo real
watch -n 2 'cat /sys/class/drm/card0/device/pp_dpm_sclk | tail -1 && rocm-smi --showtemp --showpower 2>/dev/null | grep -E "GPU|Temperature|Power"'

# ECC
rocm-smi --showecc

# Rollback rápido
sudo cp pp_table_patches/pp_table_stock.bin /sys/class/drm/card0/device/pp_table

# dmesg errors
sudo dmesg | grep -iE "reset|error|fail|ecc|pcie.*aer"

# Análise UPP
upp -p pp_table_patches/pp_table_final.bin dump | grep -E "PowerLimit|FreqTable"
```

## Referências

- Overclock README: `README.md`
- PP tables: `pp_table_patches/`
- Script de apply: `apply-gpu-patch.sh` / `mi50-apply-pp.sh`
- Service systemd: `apply-gpu-patch.service`
- Script de análise: `pp_table_explorer.py` (usa UPP como backend)
- Monitor PMBus: `pmbus_monitor.py`
