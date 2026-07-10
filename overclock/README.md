# 🚀 Overclock da AMD Radeon Pro VII / MI50 (gfx906) via pp_table

> **+24.7% core clock, +34% memory, +22% FP32 performance — sem aumentar voltagem!**

## 🇧🇷 Português

### O Problema

A **Radeon Pro VII** (Vega 20, gfx906, 60 CUs, 32 GB HBM2) é uma GPU profissional/compute que **não aceita overclock pelas interfaces normais** do driver amdgpu:

- `pp_od_clk_voltage` → retorna `OD_RANGE:` vazio
- `pp_sclk_od` → escritas não persistem
- `rocm-smi --setoverdrive` → ignorado

O driver amdgpu bloqueia o overclock fino em GPUs profissionais. A única via viável é **patching direto da tabela binária de firmware (pp_table)**.

### A Solução

O kernel expõe a tabela de power play (PowerPlay table) em:

```
/sys/class/drm/card1/device/pp_table
```

Este é um blob binário de **1730 bytes** contendo todas as frequências, voltagens e limites de energia da GPU. **Lendo, modificando offsets específicos e escrevendo de volta, o overclock é aplicado instantaneamente — sem reboot.**

### Resultados Obtidos

| Métrica | Stock | Overclock | Ganho |
|---------|-------|-----------|-------|
| **SCLK (core)** | 1700 MHz | **2120 MHz** | **+24.7%** |
| **MCLK (memória)** | 1000 MHz | **1340 MHz** | **+34%** |
| **FP32** | 13.0 TFLOPS | **15.86 TFLOPS** | **+22%** |
| **FP64** | 6.5 TFLOPS | **7.84 TFLOPS** | **+20.6%** |
| **TDP** | 190W | **350W** | **+84%** |
| **Voltagem** | 1162 mV | 1162 mV | **Stock (sem aumento!)** |
| **Temp. máxima (junction)** | ~70°C | **46°C** | Cooler superdimensionado |

> **2150 MHz**: instável (context lost / GPU crash durante compute)

### Como Funciona

#### Estrutura da pp_table (Vega 20)

```
Offset  Size  Descrição
------  ----  --------
 0-1     2    Header size (1730 = tamanho total)
 2-3     2    Tabela size
...
 826-843 18   SCLK DPM table (9 níveis × 2 bytes LE em MHz)
                842: SCLK max (stock 1700 = 0x06A4)
 922-927  6   MCLK DPM table (3 níveis × 2 bytes LE em MHz)
                926: MCLK max (stock 1000 = 0x03E8)
1010-1011 2   Cópia SCLK max (tabela secundária)
1066-1067 2   Cópia SCLK max (tabela terciária)
 928-929  2   Cópia MCLK max
```

#### Comando Mágico

```bash
# 1. Ler tabela atual
cat /sys/class/drm/card1/device/pp_table > pp_table_stock.bin

# 2. Modificar (exemplo: SCLK 1700→2120 MHz)
python3 -c "
import struct
data = bytearray(open('pp_table_stock.bin', 'rb').read())
struct.pack_into('<H', data, 842, 2120)   # SCLK max
struct.pack_into('<H', data, 1010, 2120)  # SCLK copy 1
struct.pack_into('<H', data, 1066, 2120)  # SCLK copy 2
struct.pack_into('<H', data, 926, 1340)   # MCLK max
struct.pack_into('<H', data, 928, 1340)   # MCLK copy
open('pp_table_oc.bin', 'wb').write(data)
"

# 3. Aplicar (root)
sudo cat pp_table_oc.bin > /sys/class/drm/card1/device/pp_table
```

### Instalação Passo a Passo

#### 1. Kernel Parameter

Adicione ao bootloader (systemd-boot):

```
amdgpu.ppfeaturemask=0xffffffff
```

No CachyOS, edite `/boot/loader/entries/linux-cachyos.conf`:
```
options amdgpu.ppfeaturemask=0xffffffff root=... rw ...
```

#### 2. Aplicar Overclock

```bash
# Usar o patch final (2120 MHz)
sudo cat overclock/pp_table_patches/pp_table_overclocked_final.bin > /sys/class/drm/card1/device/pp_table
```

#### 3. Persistência no Boot

Copie o script de serviço:

```bash
sudo cp overclock/apply-gpu-patch.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/apply-gpu-patch.sh
sudo cp overclock/apply-gpu-patch.service /etc/systemd/system/
sudo systemctl enable apply-gpu-patch.service
```

### Arquivos neste Diretório

| Arquivo | Descrição |
|---------|-----------|
| `pp_table_patches/pp_table_step1.bin` | +50MHz (1750 SCLK / 1040 MCLK) |
| `pp_table_patches/pp_table_step2.bin` | +100MHz (1800 / 1080) |
| `pp_table_patches/pp_table_step3.bin` | +150MHz (1850 / 1120) |
| `pp_table_patches/pp_table_step4.bin` | +200MHz (1900 / 1160) |
| `pp_table_patches/pp_table_step5.bin` | +250MHz (1950 / 1200) |
| `pp_table_patches/pp_table_step6.bin` | +300MHz (2000 / 1240) |
| `pp_table_patches/pp_table_overclocked.bin` | 2050 MHz (intermediário) |
| `pp_table_patches/pp_table_overclocked_final.bin` | **Final: 2120 MHz SCLK / 1340 MCLK** |
| `mi50_pnp.py` | Ferramenta Python para gerenciar patches |
| `apply-gpu-patch.sh` | Script de boot para aplicar no startup |
| `pp_table_explorer.py` | Ferramenta para analisar e modificar pp_table |

### Estabilidade

Testado com **clpeak** (benchmark completo Vulkan + OpenCL):
- FP32: 15.86 TFLOPS (97.6% de eficiência teórica)
- FP64: 7.84 TFLOPS
- Memória: 650+ GB/s
- Temperatura máxima durante teste: 46°C junction
- **2150 MHz**: instável — GPU crash (context lost)

---

## 🇬🇧 English

### The Problem

The **Radeon Pro VII** (Vega 20, gfx906, 60 CUs, 32 GB HBM2) is a professional/compute GPU that **does not accept overclocking through the standard amdgpu sysfs interfaces**:

- `pp_od_clk_voltage` → returns empty `OD_RANGE:`
- `pp_sclk_od` → writes don't persist
- `rocm-smi --setoverdrive` → ignored

The amdgpu driver blocks fine-grained overclocking on professional GPUs. The only viable path is **direct binary patching of the firmware PowerPlay table (pp_table)**.

### The Solution

The kernel exposes the PowerPlay table at:

```
/sys/class/drm/card1/device/pp_table
```

This is a **1730-byte binary blob** containing all GPU frequencies, voltages, and power limits. **Reading, modifying specific offsets, and writing it back applies the overclock instantly — no reboot required.**

### Results

| Metric | Stock | Overclocked | Gain |
|--------|-------|-------------|------|
| **SCLK (core)** | 1700 MHz | **2120 MHz** | **+24.7%** |
| **MCLK (memory)** | 1000 MHz | **1340 MHz** | **+34%** |
| **FP32** | 13.0 TFLOPS | **15.86 TFLOPS** | **+22%** |
| **FP64** | 6.5 TFLOPS | **7.84 TFLOPS** | **+20.6%** |
| **TDP** | 190W | **350W** | **+84%** |
| **Voltage** | 1162 mV | 1162 mV | **Stock (no increase!)** |
| **Max temp (junction)** | ~70°C | **46°C** | Overkill cooler |

> **2150 MHz**: unstable — GPU crashed (context lost during compute)

### pp_table Structure (Vega 20)

```
Offset  Size  Description
------  ----  -----------
 826-843 18   SCLK DPM table (9 levels × 2 bytes LE in MHz)
                842: SCLK max (stock 1700 = 0x06A4)
 922-927  6   MCLK DPM table (3 levels × 2 bytes LE in MHz)
                926: MCLK max (stock 1000 = 0x03E8)
1010-1011 2   SCLK max copy (secondary table)
1066-1067 2   SCLK max copy (tertiary table)
 928-929  2   MCLK max copy
```

### Quick Start

```bash
# Apply final overclock (2120 MHz)
sudo cat pp_table_patches/pp_table_overclocked_final.bin > /sys/class/drm/card1/device/pp_table

# Verify
cat /sys/class/drm/card1/device/pp_dpm_sclk  # Should show 2120MHz
```

### Stability Notes

Tested with **clpeak** (full Vulkan + OpenCL benchmark suite):
- FP32: 15.86 TFLOPS (97.6% theoretical efficiency)
- FP64: 7.84 TFLOPS
- Memory bandwidth: 650+ GB/s
- Max temperature under load: 46°C junction
- **2150 MHz**: NOT stable — GPU context lost during compute

---

## 📜 License

MIT — feel free to use, modify, and share. If this helps you, give the repo a ⭐!

## 🙏 Credits

- Based on the amazing work by [nullkalahar](https://github.com/nullkalahar) for MI50 ROCm bringup
- Original overclock research and testing by [johncoffee715](https://github.com/johncoffee715)
