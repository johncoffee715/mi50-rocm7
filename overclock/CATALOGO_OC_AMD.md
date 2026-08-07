# CATÁLOGO — Overclock de GPUs AMD no Linux (Vega 20 / MI50 / Radeon VII)

> Criado: 2026-08-06 (Gran-Mestre). Regra global: catalogar conhecimento após pesquisa.
> Fontes: kernel.org (docs amdgpu/thermal), ROCm GitHub #463, amdgpu-clocks (sibradzic), Phoronix, Reddit r/linux_gaming, Igor'sLAB, ArchWiki, CachyOS forum.

---

## 1. MÉTODO CANÔNICO (docs do kernel + comunidade)

**NÃO substituir o binário `pp_table` inteiro** (`cp table.bin > /sys/.../pp_table`) — driver revalida a tabela inteira de uma vez, sob display ativo → hang (page fault TCP / ring timeout). É provavelmente a causa dos freezes.

**Interface fina recomendada: `pp_od_clk_voltage`** (OverDrive) + `power_dpm_force_performance_level=manual`:

```bash
CARD=/sys/class/drm/card1/device
# 1. modo manual (habilita override)
echo "manual" > $CARD/power_dpm_force_performance_level
# 2. clocks: "s <0=min|1=max> <MHz>", "m <idx> <MHz>"
echo "s 0 500"  > $CARD/pp_od_clk_voltage   # sclk mínimo
echo "s 1 2000" > $CARD/pp_od_clk_voltage   # sclk máximo
echo "m 1 1000" > $CARD/pp_od_clk_voltage   # mclk máximo
# 3. curva de voltagem Vega20: "vc <point 0..2> <clock> <mV>"
echo "vc 0 300 600"    > $CARD/pp_od_clk_voltage   # p1
echo "vc 2 1000 1000"  > $CARD/pp_od_clk_voltage   # p3 (clock, volt)
# 4. voltage offset (Sienna+): "vo -50"  (NÃO suportado em Vega20; Vega20 usa vc)
echo "c" > $CARD/pp_od_clk_voltage   # commit
# 5. revert p/ default
echo "r" > $CARD/pp_od_clk_voltage
```

- Fonte: https://docs.kernel.org/gpu/amdgpu/thermal.html — **"For sclk voltage curve supported by Vega20 and NV1X, enter new values by writing a string that contains "vc point clock voltage". The points are indexed by 0, 1 and 2."**
- Phoronix: `pp_sclk_od`/`pp_mclk_od` são **deprecadas** (só %); `pp_od_clk_voltage` é a fina (clocks+voltagem, under+over).

## 2. HABILITAR OVERDRIVE (obrigatório)

```bash
# kernel cmdline (entry systemd-boot / grub)
amdgpu.ppfeaturemask=0xffffffff        # ou 0xfffd7fff (bit 14 = 0x4000 = OverDrive)
```
⚠️ O parâmetro é **`amdgpu.ppfeaturemask=`** (com prefixo `amdgpu.`). Sem prefixo → kernel ignora (`Unknown kernel command line parameters`), módulo fica no default `0xfff7bfff` → OverDrive OFF → aplicar OC alto = SMU em proteção (mclk preso 350) → freeze.

## 3. REGRAS PRÁTICAS (comunidade)

- **Temperatura de referência Vega 20 = Junction/Hotspot** (TechPowerUp): throttle a 115°C; fan control por junction. Sensor junction sobe rápido.
- **Undervolt**: ~100mV ganho típico; teste com carga real; **aumentar power limit permite UV mais profundo** (Reddit/TekTick).
- **Radeon VII**: HBM 1200 rock-stable em muitos; 1165 média TPU; SCLK 1950–2000 no ar; 2050–2064 água (Igor'sLAB "The Wall").
- **HBM em alguns ASIC 16GB 4-high**: MCLK >1000 pode ser instável (extrapolação) — testar degrau a degrau.
- **Subida brusca** (idle→2000 instantâneo) = transiente de energia → proteção. Usar **rampa gradual** (daemon com degraus 1s/nível).

## 4. ERROS COMUNS / SINTOMAS (mapeados nos testes reais 2026-08-06)

| Sintoma | Causa provável | Correção |
|---|---|---|
| mclk preso 350 + freeze | SMU protection (PP rejeitada / OverDrive OFF) | amdgpu.ppfeaturemask=0xffffffff (com prefixo) |
| `page fault` client TCP + reset loop | aplicar pp_table inteira sob Vulkan/display | usar pp_od_clk_voltage, não cp pp_table |
| `comp_* ring timeout` | workload compute + troca brusca de clock | rampa gradual / perf level manual |
| freeze antes da senha (boot) | mi50-apply-pp faz `cp` da tabela no boot | aplicar via service que usa pp_od_clk_voltage OU aplicar após boot/display |
| `flip_done timed out` / pageflip | bug display DC (CachyOS/amdgpu) | amdgpu.dcdebugmask=0x12, KWIN_DRM_NO_DIRECT_SCANOUT=1, amdgpu.runpm=0 |

## 5. PARÂMETROS DE BOOT DE ESTABILIDADE (CachyOS forum — amdgpu freeze)

```bash
amdgpu.runpm=0            # desliga runtime PM dGPU
amdgpu.dcdebugmask=0x12   # desliga PSR+stutter (0x10 PSR, 0x2 stutter)
amdgpu.gpu_recovery=1     # recupera em vez de congelar
amdgpu.dpm=0              # ÚLTIMO recurso: desliga PowerPlay (perde OC, estabiliza)
```
KDE Wayland: `KWIN_DRM_NO_DIRECT_SCANOUT=1` em /etc/environment (resolveu vários).

## 6. TOOLS

- **upp** (sibradzic/upp) — parse/dump/patch de pp_table binário
- **amdgpu-clocks** (sibradzic) — script + systemd p/ custom state via pp_od_clk_voltage (config em /etc/default/amdgpu-custom-state.cardX)
- **LACT** / **CoreCtrl** / **TuxClocker** / **WattmanGTK** — GUIs
- **rocm-smi** — monitor/ajuste ROCm

## 7. FONTES

- https://docs.kernel.org/gpu/amdgpu/thermal.html
- https://github.com/ROCm/ROCm/issues/463 (método Vega/GFX9 + grub params)
- https://github.com/sibradzic/amdgpu-clocks (OverDrive bit 14 = 0x4000)
- https://www.phoronix.com/forums/forum/linux-graphics-x-org-drivers/open-source-amd-linux/1063854-overclock-vega-amdgpu
- https://www.techpowerup.com/review/amd-radeon-vii/33.html (junction throttle 115°C)
- https://www.igorslab.de/en/the-wall-stable-overclocking-of-amd-radeon-vii-with-waterblock-and-chiller-igorslab
- https://discuss.cachyos.org/t/tutorial-mitigate-gfx-crash-lockup-apparent-freeze-with-amdgpu/10842
- https://www.reddit.com/r/linux_gaming/comments/au7m3x/radeon_vii_on_linux_overclocking_undervolting/
- https://www.tektick.com/graphics-cards/radeon-vii-undervolt-guide
