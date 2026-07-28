# 🚀 Overclock AMD Radeon Pro VII / MI50 (gfx906) via pp_table

> **+23.5% core clock, +20% memory, +58% power limit — sem modificar VBIOS**
>
> Toda modificação é **runtime** (via sysfs). Um reboot restaura tudo ao normal.

---

## 🇧🇷 Português (primário)

### Sobre Este Guia

Este guia documenta overclock da **Radeon Pro VII / MI50 16GB** (Vega 20, gfx906, 60 CUs)
instalada em hardware consumer (CachyOS, kernel Linux 6.x, ROCm 7.x).

**GPU alvo:** `1002:66a1` (Lenovo 17aa:103e), VBIOS `113-D1640700-100`
**Cooler:** Watercooler custom 1200×20mm (superdimensionado)

> ⚠️ Os valores e offsets aqui foram **validados com UPP** (Uplift Power Play)
> na PP table real da GPU em questão. Não são genéricos.
>
> 🔍 **Auto-detect:** O script `apply-gpu-patch.sh` detecta automaticamente o
> número do card (card0, card1, etc.) — não precisa mais configurar manualmente.

---

### O Problema

A Radeon Pro VII (mesma die da MI50) **não aceita overclock pelas interfaces padrão** do driver amdgpu:

| Interface | Resultado |
|-----------|-----------|
| `pp_od_clk_voltage` | Retorna vazio (`OD_RANGE:` sem valores) |
| `pp_sclk_od` | Escritas não persistem |
| `rocm-smi --setpoweroverdrive` | Ignorado |
| `power1_cap` (hwmon) | Só permite reduzir, não aumentar |

O driver amdgpu bloqueia overclock fino em GPUs profissionais. A única via é
**patching direto da tabela de firmware PowerPlay (pp_table)** via sysfs.

---

### A Solução

O kernel expõe a tabela PowerPlay em:

```
/sys/class/drm/cardN/device/pp_table   # card0, card1, etc.
```

> A numeração do card depende da ordem de detecção do driver. O script
> `apply-gpu-patch.sh` agora **auto-detecta** qualquer card AMD com pp_table.

É um blob binário de **1730 bytes** contendo frequências, limites de energia,
voltagens, temperaturas e configurações do SMU. **Ler, modificar com UPP e
escrever de volta aplica o overclock instantaneamente — sem reboot.**

---

### Resultados (Validados na GPU Real)

| Métrica | Stock | Overclock V1 | Overclock V2 (atual) | Ganho |
|---------|-------|-------------|---------------------|-------|
| **SCLK (core)** | 1700 MHz | 2100 MHz | **2000 MHz** | **+17.6%** |
| **MCLK (HBM)** | 1000 MHz | 1200 MHz | **1200 MHz** | **+20%** |
| **FCLK** | 933 MHz | 1180 MHz | **1200 MHz** | **+28.6%** |
| **SOCCLK** | 900 MHz | 971 MHz | **1165 MHz** | **+29.4%** |
| **Power limit** | 190W | 300W | **350W** | **+84%** |
| **TDC GFX** | 330A | 330A | **280A** | (proteção térmica) |
| **Hotspot limit** | 105°C | 105°C | **150°C** | (falso positivo 7nm) |
| **Edge limit** | 100°C | 100°C | **100°C** | (referência primária) |
| **MaxVoltageGfx** | ~1025mV | ~1025mV | **~972.5mV** (3890) | Undervolt -13% |

> 🔬 Overclock final validado por UPP — **30 parâmetros em uma única escrita atômica.**
> V2 usa `upp set --write --from-conf` com arquivo de configuração, mais seguro
> que múltiplas chamadas UPP individuais.
>
> ⚡ O hotspot foi elevado para 150°C porque o sensor junction (7nm TSMC)
> apresenta leitura falsa em watercooling: Edge 55°C, Junction 103°C com
> ΔT de ~50°C (anormal — esperado 10-20°C). Ver [hotspot fix](#).
>
> 🌡️ **Full load real (watercooling 1200×20mm):** Edge 44°C~57°C
> (variação com temp ambiente). Watercooling superdimensionado —
> a MI50 não esquenta o suficiente para justificar o hotspot lido.

---\n\n### Aplicação Segura (TTY Mode)\n\n**⚠️ Regra de ouro:** Sempre aplique a PP table em um **TTY puro**\n(`Ctrl+Alt+F2`) — **nunca** em uma sessão X11/Wayland.\n\n**Por quê?** A GPU MI50 é o mesmo hardware que controla o display.\nSe a PP table crashar o driver durante a aplicação em X11/Wayland,\nvocê **perde o vídeo completamente** e precisa de um **reset forçado**\n(power cycle). Em TTY, o crash apenas retorna ao prompt — sem reboot.\n\n#### Procedimento TTY\n\n```bash\n# 1. Troque para TTY2\n# Ctrl+Alt+F2 (ou Ctrl+Alt+F3..F6)\n\n# 2. Faça login\n\n# 3. Pare o display manager (opcional, mas recomendado para testes)\nsudo systemctl stop lightdm   # ou gdm / sddm / xdm\n\n# 4. Aplicar a PP table\nsudo ./apply-gpu-patch.sh pp_table_patches/pp_table_350w_2000sclk_1200mclk.bin\n\n# 5. Verificar\n./apply-gpu-patch.sh --status\n\n# 6. Voltar ao desktop\nsudo systemctl start lightdm   # ou gdm / sddm / xdm\n# Ctrl+Alt+F1 (ou F7) para voltar\n```\n\n#### Rollback (Recuperação)\n\n```bash\n# Se a GPU crashar durante o teste:\n# Role para TTY2 (Ctrl+Alt+F2) — se perdeu vídeo, reset forçado\n\n# Restaurar último backup automático\nBACKUP=$(ls -t /etc/mi50-oc/backup/pp_table_stock.*.bin | head -1)\nsudo cat \"$BACKUP\" > /sys/class/drm/card1/device/pp_table\n\n# Ou reboot (restaura PP table original da VBIOS)\nsudo reboot\n```\n\n---\n\n### Estrutura da PP Table (Vega 20 — Validada por UPP)

Os campos abaixo foram **confirmados por UPP** na PP table real (SHA-256
`3d341947...`), não inferidos por heurística:

```
Offset  Campo UPP                     Stock   Descrição
------  ----------------------------  ------  ------------------------------
 0x016  SmallPowerLimit1              190W    Power limit curto prazo
 0x018  SmallPowerLimit2              190W    Power limit curto prazo #2
 0x01a  BoostPowerLimit               190W    Power limit sustentado
 0x01c  ODTurboPowerLimit             0W      Turbo (desligado em GPUs pro)
 0x1e6  smcPPTable/SocketPowerLimitAc0 190W  Limite AC
 0x1f6  smcPPTable/SocketPowerLimitDc  190W  Limite DC
 0x33c  smcPPTable/FreqTableGfx/8     1700    SCLK máximo (P8)
 0x39c  smcPPTable/FreqTableUclk/2    1000    MCLK máximo (P2)
```

**Campos NÃO confirmados** (diferentes do que foi publicado anteriormente):

| Offset antigo (incorreto) | Realidade |
|---|---|
| `112, 116, 376, 380` (TDP 4-byte) | ❌ UPP mostra que estes offsets **não são** power limits. Power limits estão em `0x016`, `0x1e6`, etc. |
| `1010, 1066` (cópias SCLK) | ❓ UPP não expõe estes campos como endereçáveis. Podem ser parte de outras estruturas. **Teste necessário.** |
| `928` (cópia MCLK) | ❓ Mesmo caso. |

---

### Ferramenta Recomendada: UPP

Use o [UPP (Uplift Power Play)](https://github.com/sibradzic/upp) em vez de
hex edit manual:

```bash
# Instalação (via pipx)
pipx install upp

# Backup da PP table original
cp /sys/class/drm/card0/device/pp_table pp_table_stock.bin
sha256sum pp_table_stock.bin

# Ver parâmetros atuais
upp -p pp_table_stock.bin dump | grep -E "PowerLimit|FreqTableGfx|FreqTableUclk"

# Modificar: aumentar power limit para 250W
cp pp_table_stock.bin pp_table_250w.bin
upp -p pp_table_250w.bin set --write \
  /SmallPowerLimit1=250 \
  /SmallPowerLimit2=250 \
  /BoostPowerLimit=250 \
  /smcPPTable/SocketPowerLimitAc0=250 \
  /smcPPTable/SocketPowerLimitDc=250

# Verificar
upp -p pp_table_250w.bin dump | grep PowerLimit

# Aplicar (root)
sudo cp pp_table_250w.bin /sys/class/drm/card0/device/pp_table
```

---

### Plano de Validação em Estágios

Siga esta ordem. **Não pule estágios.**

#### Stage 1 — Baseline

- [ ] `rocm-smi` mostra a GPU (device ID 0x66a1)
- [ ] `cat /sys/class/drm/card0/device/pp_dpm_sclk` funcional
- [ ] `cat /sys/class/drm/card0/device/pp_table` sem erro
- [ ] Backup salvo: `sha256sum pp_table_stock.bin`
- [ ] Temperatura idle < 40°C edge, < 50°C junction

#### Stage 2 — Power Limit (250W)

**Arquivo:** `pp_table_patches/pp_table_250w.bin`

- [ ] Aplicar: `sudo cp pp_table_250w.bin /sys/class/drm/card0/device/pp_table`
- [ ] `rocm-smi --showpower` mostra o novo limite
- [ ] Rodar `clpeak` 15 min
- [ ] Temperatura junction < 85°C
- [ ] ECC corrected errors = 0 (antes e depois)
- [ **Rollback se:** perder vídeo, GPU reset, ECC errors ]

#### Stage 3 — SCLK (incremental 50MHz)

Use os patches step1..step6 ou crie com UPP:

| Estágio | Arquivo | SCLK | MCLK | Power |
|---------|---------|------|------|-------|
| Step 1 | `pp_table_step1.bin` | 1750 | 1000 | 250W |
| Step 2 | `pp_table_step2.bin` | 1800 | 1000 | 250W |
| Step 3 | `pp_table_step3.bin` | 1850 | 1000 | 250W |
| Step 4 | `pp_table_step4.bin` | 1900 | 1000 | 250W |
| Step 5 | `pp_table_step5.bin` | 1950 | 1000 | 250W |
| Step 6 | `pp_table_step6.bin` | 2000 | 1000 | 250W |
| Step 7 | `pp_table_2000mhz.bin` | 2000 | 1000 | 250W |
| **Final SCLK** | `pp_table_final.bin` | **2100** | **1200** | **300W** |
| **V2 — 350W** | `pp_table_350w_2000sclk_1200mclk.bin` | **2000** | **1200** | **350W** |

Cada step: 10 min de carga computacional (clpeak, llama.cpp, ou ROCm).
**Rollback se:** perder vídeo, ECC uncorrected, GPU reset, temperatura
junction > 95°C.

#### Stage 4 — MCLK (incremental)

Após SCLK estável em 2000MHz:

| Passo | MCLK | SCLK | Power |
|-------|------|------|-------|
| 1 | 1050 | 2000 | 250W |
| 2 | 1100 | 2000 | 250W |
| 3 | 1150 | 2000 | 250W |
| 4 | 1200 | 2000 | 300W |

Cada passo: verificar ECC counters antes e depois.
**Rollback se:** uncorrected ECC errors > 0, instabilidade.

#### Stage 5 — Combinado + Longo

- SCLK 2100 + MCLK 1200 + Power 300W
- 2h de carga contínua (clpeak + llama.cpp)
- Verificar: ECC, temperatura, throttling, PCIe AER

---

### Condições de Parada (Stop Conditions)

**Pare imediatamente e reverta ao stock SE:**

1. ❌ Perda de vídeo sob carga (watchdog SMU)
2. ❌ HBM ECC **uncorrected** > 0
3. ❌ GPU reset detectado (`dmesg | grep -i reset`)
4. ❌ Temperatura junction > 95°C
5. ❌ PCIe AER errors
6. ❌ Clock não retorna ao normal após rollback

---

### Persistência (Systemd Service)

\`\`\`bash
# Instalar o serviço
sudo ./apply-gpu-patch.sh --install

# Escolher qual PP table usar no boot
sudo cp pp_table_patches/pp_table_350w_2000sclk_1200mclk.bin /etc/mi50-oc/pp_table_active.bin

# Ativar agora
sudo systemctl start mi50-apply-pp

# Verificar
systemctl status mi50-apply-pp
\`\`\`

O serviço:
- Espera o driver amdgpu carregar
- Auto-detecta o número do card (card1, etc.)
- Aplica a PP table antes do display manager
- Backup automático da tabela original antes de cada aplicação

### Deploy Completo (Script Único)

Para deploy completo (backup + aplicar + instalar serviço + verificar):

```bash
# Tudo em um comando (precisa sudo)
sudo ./deploy.sh

# Ou manualmente:
sudo ./apply-gpu-patch.sh pp_table_patches/pp_table_350w_2000sclk_1200mclk.bin
sudo ./apply-gpu-patch.sh --install
```

O script `deploy.sh` faz 6 passos automaticamente:
1. Backup da PP table atual
2. Aplica PP table na GPU
3. Verifica com UPP (power, clocks, hotspot)
4. Instala script em `/usr/local/bin/mi50-apply-pp.sh`
5. Configura PP table ativa em `/etc/mi50-oc/pp_table_active.bin`
6. Instala e habilita serviço systemd `mi50-apply-pp.service`

---

### Monitoramento PMBus (IR35217)

O VRM de memória da MI50/Pro VII é o **Infineon IR35217**.

```bash
# Escanear barramento SMU (i2c-0) em busca do IR35217
sudo i2cdetect -y 0

# Se encontrado (tipicamente 0x40 ou 0x41):
sudo i2cget -y 0 0x40 0x88 w   # Ler VOUT (tensão da memória)
```

> ⚠️ No momento, o IR35217 **não está visível** no barramento i2c-0
> na GPU analisada. Pode exigir configuração do SMU ou estar atrás de
> um multiplexador. Investigação em andamento.

---

### Arquivos neste Diretório

| Arquivo | Descrição |
|---------|-----------|
| **Scripts** | |
| `mi50-apply-pp.sh` | Script de apply + instalador systemd |
| `pp_table_explorer.py` | Explorador de PP table (usa UPP como backend) |
| `mi50_pnp.py` | Ferramenta legada (manter para referência) |
| `pmbus_monitor.py` | Monitor PMBus para IR35217 |
| **PP Tables (UPP-validated)** | |
| `pp_table_patches/pp_table_stock.bin` | Backup da original (SHA-256: `3d341947...`) |
| `pp_table_patches/pp_table_250w.bin` | Power limit 250W (stock clocks) |
| `pp_table_patches/pp_table_1800mhz.bin` | 1800MHz SCLK + 250W |
| `pp_table_patches/pp_table_2000mhz.bin` | 2000MHz SCLK + 250W |
| `pp_table_patches/pp_table_2000mhz_mclk.bin` | 2000MHz SCLK + 1100MHz MCLK |
| `pp_table_patches/pp_table_final.bin` | **2100MHz / 1200MHz / 300W** |
| `pp_table_patches/pp_table_350w_2000sclk_1200mclk.bin` | **V2 — 350W / 2000 SCLK / 1200 MCLK / 1200 FCLK / 1165 SOCCLK / Hotspot 150°C** |
| `pp_table_patches/upp_targets_350w.conf` | Config UPP para recriar a PP table V2 |
| `pp_table_patches/pp_table_stock_backup.bin` | Backup da stock original (para rollback manual) |
| **PP Tables (legadas — repo original)** | |
| `pp_table_patches/legacy/pp_table_step1..6.bin` | Steps incrementais (offset-based) |
| `pp_table_patches/legacy/pp_table_overclocked.bin` | 2050MHz (legado) |
| `pp_table_patches/legacy/pp_table_overclocked_final.bin` | 2120MHz / 1340MHz (legado — crash em 2150) |
| **Documentação** | |
| `VALIDATION.md` | Plano completo de validação com checkboxes |

---

### Diff: O Que Mudou do Repositório Anterior

| Aspecto | Antigo | Novo |
|---------|--------|------|
| **Base de offsets** | Hex manual (842, 926, 1010...) | ✅ UPP (nomes simbólicos validados) |
| **Power limit** | Heurística busca 0xBE (190) | ✅ UPP set nos campos corretos |
| **Patch SCLK** | SCLK máximo + 2 cópias (842, 1010, 1066) | ✅ Só FreqTableGfx/8 (via UPP) |
| **Voltagem** | Ignorada | ✅ Ajustável via `MaxVoltageGfx` |
| **Validação** | "Testado com clpeak" | ✅ 5 estágios com stop conditions |
| **Persistência** | Service simples sem backup | ✅ Backup automático + Before DM |
| **card path** | card1 (incorreto) | ✅ auto-detect (qualquer card AMD com pp_table) |
| **VRAM** | 32GB | ✅ 16GB (especificação correta) |
| **PMBus** | Inexistente | ✅ Script de monitoramento |
| **Idioma primário** | Inglês | ✅ Português |

---

### HW Monitor Via GPU

```bash
# Verificar clocks atuais
watch -n 1 'cat /sys/class/drm/card0/device/pp_dpm_sclk; echo "---"; cat /sys/class/drm/card0/device/pp_dpm_mclk'

# Verificar temperatura e potência
watch -n 1 'rocm-smi --showtemp --showpower --showclocks'

# Verificar ECC
rocm-smi --showecc

# Verificar erros PCIe
sudo dmesg | grep -i "pcie.*aer"
```

---

### ⚠️ Avisos

1. **Runtime é reversível** — reboot restaura a PP table original. Não há risco de brick.
2. **Crossflash NÃO é necessário** — runtime cobre todos os ajustes necessários.
3. **RSA signature check** na VBIOS impede hex-patch direto da ROM — runtime é o único caminho.
4. **Seu cooler precisa ser adequado.** Teste incremental. Não pule estágios.
5. **HBM ECC**: MCLK elevado pode gerar erros de memória. Monitore com `rocm-smi --showecc`.

---

## 🇬🇧 English Summary

This guide documents overclocking the **Radeon Pro VII / MI50 16GB** (Vega 20, gfx906)
via runtime PowerPlay table patching using **UPP** (Uplift Power Play).

**Key improvements over previous version:**
- All offsets validated by UPP, not hex heuristics
- 5-stage validation plan with explicit stop conditions
- Correct power limit fields (UPP symbolic, not 0xBE search)
- Systemd service with backup and proper boot ordering
- PMBus monitoring script for IR35217 VRM
- Portuguese as primary language

**Results:** SCLK 1700→2100 MHz, MCLK 1000→1200 MHz, Power 190→300W

---

## 📜 License

MIT — feel free to use, modify, and share.

## 🙏 Credits

- UPP tool by [sibradzic](https://github.com/sibradzic/upp)
- Research and validation by [johncoffee715](https://github.com/johncoffee715)
