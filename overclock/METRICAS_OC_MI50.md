# 📊 MÉTRICAS CONSOLIDADAS — Overclock MI50 (2026-08-07)

> Evidência de cada patamar validado. Atualizar a cada novo perfil.

## Escalada de SCLK (homeopática, 50MHz/degrau — todos sem freeze)

| Perfil | SCLK | MD5 | Validação |
|---|---|---|---|
| v29 BASE | 1700 | `754da772` | ✅ base estável |
| v30 | 1850 | `2cae563f` | ✅ |
| v31 | 1900 | `6a6b01b4` | ✅ |
| v32 | 1950 | `30a4271f` | ✅ |
| v33 | 2000 | `3a66640f` | ✅ inferência ok |
| v34 | 2050 | `0624f954` | ✅ |
| v35 | 2100 | `d891907d` | ✅ teste ok |
| **v36** | **2150 (teto SCLK)** | `7e9cc1e4` | ✅ teste ok |

## Escalada de MCLK (homeopatia, após SCLK teto)

| Perfil | SCLK | MCLK | MD5 | Validação |
|---|---|---|---|---|
| base | 1700 | 1000 | `754da772` | ✅ |
| **v37** | 2100 | **1100** | `e8d7d5fa` | ✅ aplicado, topo MCLK=1100 aceito |
| v39 | 2100 | 1150 | `e31e082a` | ✅ topo MCLK=1150 |
| **v40** | 2100 | **1200 (teto HBM2)** | `22430f05` | ✅ topo MCLK=1200 |

## Snapshot de métricas — v36 (SCLK 2150), 2026-08-07 00:44

```
Uptime: 28 min
CLOCKS:
  sclk  : nível 3 (1316 MHz) idle · nível 8 (2150) sob carga
  mclk  : nível 2 (1000 MHz)
  fclk  : 1080 · socclk: 850
TEMPS:
  edge    : 34°C
  junction: 40°C  (sensor HW danificado — não usar como ref)
  memory  : 33°C
POWER:
  socket gfx package: 28 W (idle)
BUSY: 0 (pós-inferência)
PERF: manual
pp_table: 7e9cc1e4f68a9c654114595339cdaac0 (v36)
ERROS amdgpu: nenhum (dmesg limpo)
```

## Configuração de referência (receita que sustenta o teto)

| Parâmetro | Valor | Papel |
|---|---|---|
| amdgpu.ppfeaturemask | 0xffffffff | OverDrive full |
| SmallPowerLimit / Boost / AC / DC | 350 W | TDP fixo |
| ThotspotLimit | 150 | workaround sensor HW |
| TedgeLimit / ThbmLimit | 100 / 94 | refs de throttle reais (edge+VRAM) |
| MaxVoltageGfx | 4650 (stock) | sem undervolt |
| SoftwareShutdownTemp | 113 (stock) | — |
| Tabela DPM nível 8 | = SCLK alvo | o "segredo" — rampa 0→8 |
| daemon v4 | enabled | rampa gradual (anti-bug) |
| aplicação | pós-boot | nunca no boot |
