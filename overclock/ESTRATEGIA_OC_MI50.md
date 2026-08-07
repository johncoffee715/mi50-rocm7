# 🎯 ESTRATÉGIAS DE OVERCLOCK MI50 / PRO VII / VEGA 20 — Consolidado (2026-08-07)

> Documento canônico do scaffold. Síntese de TODA a pesquisa (EN/PT/CN/JA/RU/DE/TW), testes reais e as 3 pastas (`mi50-oc`, `mi50-rocm7`, `gpu-fw/mi50`).
> FONTE VIVA: este é o arquivo-mestre para futuras tarefas de OC desta GPU.

---

## 1. CONTEXTO do HARDWARE (Radeon Pro VII / MI50, 1002:66a1, VBIOS 113-D1640700-100)

- **GPU:** Vega 20 gfx906, 60 CU, 16GB HBM2 4096-bit (hynix), 16GB 4-high.
- **SISTEMA:** CachyOS (kernel cachyos 7.x), ROCm 7.2.4, Mesa 26, systemd-boot.
- **ARREFECIMENTO:** waterblock custom (ByKSKI) + rad ~120mm + dual pump; x-bracket instalado.
- **⚠️ LIMITAÇÃO HW CONFIRMADA:** sensor **hotspot/junction IRREPARÁVEL** (danificado por uso 24/7 sem refrigeração — 2ª MI50 com mesma falha). Junction lê **105°C** em full-load com edge/VRAM a **50°C** (delta 55°C).

---

## 2. MECANISMO DE OC (o que funciona e o que NÃO)

| Método | Funciona? | Nota |
|---|---|---|
| **`pp_od_clk_voltage`** (OverDrive fino) | ❌ NÃO | `OD_RANGE:` vazio; "overdrive not supported" numa GPU profissional |
| `pp_sclk_od` / `pp_mclk_od` | ❌ NÃO | não persiste em GPU pro |
| `power1_cap` (hwmon) | ❌ | só reduz |
| **patchear `pp_table` via sysfs (UPP/cp)** | ✅ **SIM** | única via real. Aplicar PÓS-boot (nunca no boot) |
| **OverDrive bifício (tido no boot)** | ❌ | causava freeze; aplicar PÓS-boot = correta |

**Aplicação PÓS-boot** é a regra de ouro do timing: aplicar no boot → freeze; pós-boot (sistema estável) → funciona.

---

## 3. A RECEITA VENCEDORA (confirmada por teste, 2026-08-07)

```
Boot (PowerPlay + amdgpu.ppfeaturemask=0xffffffff)
  → mi50-apply-pp (no-boot) DISABLED
  → (45s pós-boot) mi50-apply-postboot aplica a pp_table
  → gpu-performance-daemon v4 faz a RAMPA GRADUAL (0→8, 1 nível/seg)
  → gpu-watchdog só sobe os llama quando MD5 da tabela bate (gate)
```
- **TABELA DPM é o segredo:** o daemon percorre os níveis 0→8 da DPM progressivamente. Elevar o TOPO (nível 8) + rampa = transição suave = estável.
- **NUNCA usar hotspot (junction) como referência de throttle** → `ThotspotLimit=150` (workaround sensor). Referência real = **edge (TedgeLimit 100) + VRAM (ThbmLimit 94)**.

---

## 4. A BASE (v29) e doses homeopáticas — VALIDADO

### BASE v29 (MD5 `754da772c8321ef18c525908e33f3174`)
| Parâmetro | Valor | Status |
|---|---|---|
| SmallPowerLimit1/2, BoostPowerLimit | 350 W | ✅ (foi 190W stock) |
| SocketPowerLimitAc0/Dc | 350 W | ✅ |
| **ThotspotLimit** | **150** | ✅ workaround sensor |
| TedgeLimit / ThbmLimit (refs) | 100 / 94 | ✅ edge+VRAM |
| MaxVoltageGfx | **4650** (STOCK, SEM UV) | ✅ |
| SoftwareShutdownTemp | 113 (stock) | ✅ |
| TdcLimitGfx | 330 (stock) | ✅ |
| **Clocks** | SCLK 1700 / MCLK 1000 (stock) | base estável |

### Escalada homeopática (cada dose validada ao vivo, sem freeze)
| Perfil | SCLK | MD5 |
|---|---|---|
| v30 | 1850 | `2cae563f` |
| v31 | 1900 | `6a6b01b4` |
| v32 | 1950 | `30a4271f` |
| v33 | 2000 | `3a66640f` |
| v35 | 2100 | `d891907d` |
| **v36** | **2150 (ativo — teto máx)** | `7e9cc1e4` |
| v37+ (próximo) | MCLK 1100+ (homeopatia) | — |

**Doses:** sempre elevar SCLK em ~50MHz (1700→1850→1900→1950→2000→2050→2100→2150), validando alto (`pp_dpm_sclk` nível 8 = alvo, dmesg sem erros, mclk NÃO preso em 350), aplicando pós-boot.

---

## 5. BOOT / SYSTEMD (configuração canônica)
- **entry:** `amdgpu.ppfeaturemask=0xffffffff` (prefixo OBRIGATÓRIO; sem prefixo → módulo 0xfff7bfff → overdrive off → freeze)
- `mi50-apply-pp` (no-boot): **disabled**
- `mi50-apply-postboot`: **enabled** (aplica pós-boot, `After=gpu-performance-daemon`)
- `gpu-performance-daemon`: **enabled** (rampa gradual — regra de ouro)
- `gpu-watchdog` (user): gate espera MD5 da tabela antes de subir llama
- **Recuperação de crash:** colocar `amdgpu.dpm=0` na entry (PowerPlay off, low-power estável)

---

## 6. ERROS / SINTOMAS MAPEADOS
| Sintomas | Causa | Correção |
|---|---|---|
| mclk 350 + freeze | SMU protection (OD off OU hotspot dispara) | ppfeaturemask correcto + ThotspotLimit 150 |
| freezer no boot | aplicar pp_table no boot | aplicar pós-boot |
| delta junction−edge 55°C | sensor danificado (HW) | workaround SW (ThotspotLimit 150) |

---

## 7. Referências
- kernel.org docs amdgpu/thermal, ROCm#463, igorsLAB "The Wall", TechPowerUP R9 VII, 3dnews.ru, Guru3D, Reddit r/linux_gaming + r/overclocking, CachyOS forum.