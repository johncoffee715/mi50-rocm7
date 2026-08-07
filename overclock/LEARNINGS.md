# Learnings — Overclocking MI50 / Vega 20 (PP Tables)

## ✅ FECHAMENTO DEFINITIVO (2026-08-07): WALL = SCLK 2100. 2135/2150 causam page fault + gfx timeout
- **Teste 2135/1200 (perf=AUTO):** 40s de burst ok (TDP 75W), mas **`gfxhub0 no-retry page fault` + `ring gfx timeout` → wedged** em sessão real (1901s). NÃO estável.
- **Teste 2150/1200:** `ring gfx timeout` + wedged (1066s/1389s). NÃO estável.
- **ESTÁVEL = SCLK 2100 / MCLK 1200** (MD5 `22430f05`) — sem page fault, sem wedge.
- **PERFIL DEFINITIVO: `pp_table_final_estavel_2100_1200.bin`**, persistido (/etc + postboot + watchdog gate `22430f05`), aplica pós-boot + `perf=AUTO` em jogo.
- **LIÇÃO FINAL:** o Vega 20 desta placa sustenta **até 2100** com segurança; acima (2135–2150) gera page faults GFX = barreira física do silicone. Aceitar o wall; MCLK 1200 (máx estável) já conquistado.

## 🔬 FINE-TUNING: a 2150 o "wedged" (gfx timeout transitório sem recovery) — teto estável = 2100
- **Dados:** `ring gfx timeout` aos 1066s e 1389s, mas **"device wedged, but no recovery needed"** → estagna brevemente e volta (por isso "sai do freeze sozinho").
- **2150 sustenta ~20s em full load mas causa wedges recorrentes** (instabilidade fina do ring gfx a +645MHz). Em 2100 (v35/v40) não houve wedges.
- **CONCLUSAO:** teto **estável de produção = SCLK 2100** (não 2150). 2150 = burst, mas wedges em sessão longa.
- **Perfil estável:** SCLK 2100 + MCLK 1200 (v40-combo); 2150 como pico. Daemon não deve ficar em manual em jogo (perf=AUTO).

## 🔬 NOVO ACHADO em jogo (2026-08-07): `ring gfx timeout` + perf_level MANUAL trava os clocks altos
- **Teste de jogo no v42 (2150/1200):** freeze + **clocks NÃO subiram** — sclk ficou **capped em 1700** e vram **800** (não atingiram o topo da DPM). dmesg: **`amdgpu: ring gfx timeout`**.
- **CAUSA provável:** `power_dpm_force_performance_level = manual` trava o escalonamento; em jogo (carga real de GFX), o `manual` impede o boost e ainda faz o `ring gfx` parar → freeze.
- **CORREÇÃO (a testar):** em carga de jogo real, pode-se precisar de `perf_level=auto` (deixa DPM automático escalar até o topo da DPM), em vez de forçar `manual`. O `manual` é bom para rampa (daemon), mas em jogo sust ptf o ring.
- **HIPÓTESES validadas antes:** rampa gradual (estável) + VRAM livre (co-factor) + base v29 (Thp150/refs) — mas o **jogo full load** abre um novo modo (ring gfx) que o `manual` não sustenta.
- **PRÓXIMO:** testar v42 com `perf_level=auto` durante jogo (deixa DPM escalar ao topo 2150/1200) p/ ver se sustenta ambos em over.

## 🔬 MECANISMO-CHAVE (usuário, 2026-08-07): rampa GRADUAL e suave é o que estabiliza
- **Insight do usuário:** "parece que quando tem rampa gradativa e suave" funciona. O **daemon v4** faz `ramp_up 0→1→2→...→8` (1 nível/seg, `RAMP_STEP_SEC=1`) + `ramp_down` no idle → transição suave = estável.
- **POR QUE:** o Vega 20 (com sensor hotspot danificado e VRAM variável) accepta o clock ALTO desde que a **subida seja gradual** (a "regra de ouro" positiva). Salto abrupto idle→2150 = transiente → hang; rampa = ok.
- **CONSEQUÊNCIA:** a estabilidade não depende só do valor final (2150 é ok com rampa) nem só da VRAM; a **RAMPA gradual do daemon é o mantenedor**. Manter daemon v4 enabled + `RAMP_STEP_SEC=1`.
- **CONJUNTO: base v29 + tabela DPM (topo nível 8) + daemon rampa + aplicar pós-boot + VRAM gerenciada (regra ciclo-vida) = OC alto estável.**

## 🔬 DISSECÇÃO CONFIRMADA (2026-08-07): VRAM cheia é co-factor no teto (2150 sustenta com VRAM livre)
- **Teste controlado:** v42 (SCLK2150/MCLK1200) com VRAM **~88% cheia** (15.2GB pesos LLM) = ❌ hang a 2145+ (sem OCP, sem beep). Após **liberar VRAM** (→1.6GB) = ✅ **SCLK 2150 sustenta 30s+ sob estresse**, TDP 26→68W, sem freeze.
- **PROVA:** o freeze em ~2150 não é o clock isolado — é a **contenda de VRAM cheia + OC alto**. Com VRAM livre, o teto é estável.
- **REGRAS OPERACIONAIS derivadas (para a comunidade):**
  1. Liberar VRAM (desligar LLM/stack) **quando não há inferência** → permite OC alto (2150) com segurança.
  2. Com VRAM saturada (~88%) → reduzir o teto p/ ~2100 (evita hang).
  3. Monitorar `VRAM Used` como "métrica/interruptor": usado>~85% + OC alto = risck.
- **DOC p/ comunidade:** este padrão (VRAM full + OC = hang; VRAM livre = OC ok) vale para Vega 20 / LLM-GPU.

## 🔬 DISSECÇÃO do freeze no teto (2026-08-07): SCLK ~2145/2150 = hang SEM OCP (não beep/corte)
- **DADO do teste sob carga (v42 2150/1200):** SCLK picos até 2145 (29,41% over), nunca fixo em 2150; **freeze SEM corte de vcore/SEM beep da morte** (≠ OCP!).
- **Causa:** NÃO é energia/PSU (não cortou vcore). É **hang de GPU/silício** na faixa 2145–2150 sob carga — o ASIC não sustenta o over de ~29% na prática (especialmente com VRAM ocupada pelos pesos LLM).
- **HIPÓTESE DO USUÁRIO (a testar):** VRAM com pesos LLM + OC alto → contenda/sobrecarga → hang. Teste controlado: teto com VRAM livre vs carregada.
- **FATO:** 2150 = teto de silício "frágil" (respira/picos); 2100 = estável (v35/v40). O freeze em 2145+ = hang limpo sem proteção, recupera via reboot.
- **LIÇÃO:** teto útil prático pode ser ~2100, não 2150; e o teste sob VRAM ocupada (uso real) é o que vale.

## 🔍 WALL do chip confirmado por teste (2026-08-07): SCLK 2200 = freeze (hang duro), 2150 = estável
- **Teste:** v36 SCLK 2150 = ✅ estável; v41 SCLK 2200 = ❌ **freeze (hang duro, sem log do kernel)**.
- **Causa:** não é térmico (34/40/33°C) nem TDP (350W fixo); é **limite do silício Vega 20 a 2200** com MaxVolt 4650 stock. Chip sustenta até ~2150; 2200 = instabilidade (igorslab "wall").
- **TETO CONFIRMADO:** **SCLK 2150 / MCLK 1200** (v36 + v40 combinados). Perfil máximo real = **v42-final (SCLK2150/MCLK1200)**.
- **LIÇÃO:** homeopatia ~50MHz definiu o wall exato; parar em 2150; o 2200 é perda de estabilidade sem ganho.

> 📘 **DOC-MESTRE:** `ESTRATEGIA_OC_MI50.md` — receita completa consolidada (base v29, doses homeopáticas v30–v33, mecanismo, boot/systemd, erros). Usar como referência única para futuras tasks de OC.

## 🔍 FECHAMENTO do case (2026-08-07): sensor hotspot IRREPARÁVEL (HW danificado) → workaround SW
- **Usuário verificou:** já removeu x-bracket, é a **2ª MI50 com a mesma falha**, provável **sensor danificado por uso 24/7 sem refrigeração** — não reparável sem trocar GPU. (junction real 105°C em full load gaming+OC).
- **workaround definitivo (SW):** **`ThotspotLimit=150`** (e refs de throttle = edge 100 + VRAM 94), Power Cap 350W, resto stock → confirmado ATIVO (glxinfo: Power Cap 350, Junction Crit 150/Emerg 155).
- **ESTE É O PADRÃO-DA-CASA:** nunca mais usar hotspot como referência; referência = edge+VRAM. v29/v30 implementa. OC possível; só não pode trepidar pelo hotspot.
- **v29 BASE (MD5 754da772) + v30 (SCLK 1850, MD5 2cae563f):** doses homeopáticas sobre a base.

## 🔒 **REGRA GLOBAL (2026-08-06):** ao encontrar a ROTA da solução (causa raiz + caminho de fix), **SALVAR O APRENDIZADO IMEDIATAMENTE** neste arquivo + CONTEXT.md. NUNCA prosseguir sem persistir — o scaffold só se fortalece se cada fio de solução for registrado.

> ⚠️ **REGRA GLOBAL #2 (2026-08-06):** **SEMPRE CONFERIR o binário/estado ANTES de executar qualquer mudança.** NUNCA confiar no NOME do arquivo (`v12_uv50` NÃO garante undervolt). Protocolo obrigatório: `upp -p <bin> dump` + `md5sum` + conferir os **3 invariantes** antes de aplicar: (1) `MaxVoltageGfx` (stock=4040/4060, UV=−50=3840), (2) `FreqTableGfx[8]` e `FreqTableUclk[2]` = clocks alvo, (3) `ThotspotLimit`/`TedgeLimit`/`ThbmLimit` dentro do domínio (150/100/94). **Exemplo real:** `v12` rotulado "uv50" tinha `MaxVoltageGfx=4600` (**overvolt!**) e `Uclk=1000` — nome errado. Se aplicado sem conferir, quebraria a GPU. Conferência = escudo contra teste mutilado.

## 🔍 DIAGNÓSTICO FÍSICO do freeze (2026-08-07): delta junction−edge = 55°C = MAU CONTATO TÉRMICO
- **DADO REAL do usuário (full load):** edge/VRAM = 50°C, **junction (hotspot) = 105°C** → delta **55°C**.
- **REGRAS (CONTEXT + Igor'sLAB/TechPowerUP):** delta edge/hotspot **>20°C = contato/TIM irregular** do waterblock/montagem. O junction lê o ponto mais quente do die; 55°C de delta = **térmico físico ruim** (não é sensor quebrado de software).
- **CONEXÃO COM TODOS OS FREEZES:** no stock `ThotspotLimit=105`, o junction real 105°C dispara proteção SMU → mclk 350 → freeze. **v29 (ThotspotLimit 150) "funcionou" porque desativou a proteção prematura** — mas causa raiz é HW.
- **AÇÃO:** (1) SW: manter ThotspotLimit 150 (v29/v30) p/ não throttlear em 105°C; (2) **HW: remontar o waterblock (re-aplicar TIM)** para reduzir o delta junction-edge — esse é o fix real do freezer.

## ✅ FASE 1 (v29 BASE) RESOLVIDA — 2026-08-07: pipeline pós-boot funciona (sem freeze)
- **CONFIG:** entry `amdgpu.ppfeaturemask=0xffffffff` + `mi50-apply-pp` (no-boot) DISABLED + `mi50-apply-postboot` ENABLED (aplica v29 45s pós-boot, After=gpu-perf-daemon) + `gpu-watchdog` com GATE (só sobe llama quando MD5==v29) + daemon v4 (rampa).
- **RESULTADO:** v29 BASE (TDP350/Thp150/refs edge+VRAM/resto stock, MD5 `754da772`) aplicado pós-boot → mclk 1000 (não 350), sclk 1654 idle, temps edge34/junction37/mem33, dmesg SEM resets, 2min estável.
- **REPRODUTÍVEL:** boot→PowerPlay/OD→postboot +45s aplica v29→daemon rampa→llama só depois. NÃO congelou.
- **PRÓXIMO:** Fase 2 — subir SCLK em doses homeopáticas (v30 = v29 base + SCLK 1850, mantendo térmica/volt/refs via base) → validar → depois MCLK.

## ✅ CAUSA DIAGNOSTICADA COM TESTE (2026-08-06): o problema é o TIMING no BOOT, não o clock/cp
- **TESTE (pós-boot, sistema estável, OD full):** `cp pp_table_v27 → sysfs` **FUNCIONA** — SCLK sobe gradual 1425→1583→**2000**, MCLK 1000, sem hang, MD5 confere.
- **COMPARAÇÃO:** o MESMO `cp` v27 no **BOOT** (mi50-apply-pp) CONGELAVA.
- **CONCLUSÃO:** o **overclock/cp NÃO é o problema — o TIMING é.** Aplicar a pp_table **durante o boot** (display subindo + Vulkan/llama alocando VRAM) → hang. Aplicar **pós-boot** (sistema estável) → funciona perfeitamente.
- **REGRA:** pp_table para OC deve ser aplicada **DEPOIS** do boot estabilizar, NUNCA no boot. `mi50-apply-pp` no-boot é o causador dos freezes. Preferir aplicar via serviço com atraso/After display, ou manual.
- **Nota:** `pp_od_clk_voltage` NÃO funciona nesta placa (overdrive não suportado) — não usar; o caminho é cp da tabela pós-boot.

## 🔍 CRÍTICO 2026-08-06: Overdrive nativo NÃO suportado nesta placa — pp_od_clk_voltage inútil
- **SINTOMA:** `pp_od_clk_voltage` existe mas **`OD_RANGE:` vazio**; `s 1 2000` → `Argumento inválido`. dmesg: **`amdgpu: [powerplay] Sclk min/max frequency overdrive not supported`**.
- **CONSEQUÊNCIA:** no Radeon Pro VII / MI50 com `amdgpu.ppfeaturemask=0xffffffff`, o **overdrive nativo de SCLK/MCLK NÃO existe**. SCLK max fica **1700** (lvl 8), MCLK max **1000** (lvl 2). O método canônico (`pp_od_clk_voltage`) documentado no kernel **NÃO se aplica** a esta placa.
- **IMPACTO:** a **única** forma de clock >stock (2000/2140) é **substituir o binário `pp_table`** (o `cp` que causava freeze) — ou usar ferramenta que injete tabela (UPP/SoftPPT). O freeze não vem do método em si; vem de outra causa (concorrência/compatibilidade/display), ainda a isolar.

## 🔍 NOVA HIPÓTESE-CHEFE (usuário, 2026-08-06): "nunca foi o clock — pode ser subida BRUSCA"
- **Insight:** o freeze não é o valor final do clock; é a **SUBIDA ABRUPTA idle→SCLK2000** quando o workload (Vulkan/llama) sobe. O tote `859→2000MHz` instantâneo = transiente de energia → SMU/proteção → hang. Bate com a REGRA DE OURO do usuário (daemon-v4 faz **rampa 0→8 gradual**).
- **Caminho:** preservar o clock alto (SCLK 2000) mas **subir graduamente** via `gpu-performance-daemon-v4` (rampa 1s por nível), com OD full (`0xffffffff`), perfil **v27 (SCLK2000/MCLK1000)**, e watchdog com gate.
- **Ações enfileiradas:** entry com `amdgpu.ppfeaturemask=0xffffffff` + S/D dpm, reativar mi50-apply-pp + daemon (rampa), v27 persistido, reboot teste.

## 🔍 REFUTADO: MCLK NÃO é o gatilho (teste v27, 2026-08-06)
- **TESTE v27 (MCLK STOCK 1000 / SCLK 2000 / TDP 350):** aplicado (MD5 `2d3317c6` no sysfs), ppfeaturemask `0xfff7ffff`. **MESMO ASSIM** mclk preso em 350 + `comp_1.2.0 timeout → GPU reset → VRAM lost` aos ~114s.
- **Conclusão:** mclk=350 é **sintoma de proteção**, não causa. O gatilho NÃO é a memória (HBM).
- **NOVA HIPÓTESE:** o gatilho é **SCLK 2000 + TDP 350W SOB CARGA VULKAN/COMPUTE** (o ring `comp_*` que estoura = workload de compute; acontece ~quando os llama Vulkan sobem). Stock (1700/190W) aguenta; 2000/350W não. 
- **PRÓXIMO ISOLAMENTO:** testar **v27 SEM os llama** (watchdog desligado) → se estável, prova que é a **concorrência SCLK2000/350W com Vulkan**; se ainda travar, é o perfil em si.

# Learnings — Overclocking MI50 / Vega 20 (PP Tables)

## 🔍 SENSOR HOTSPOT = CHAVE (2026-08-06, quarteto MI50/ProVII/RVII/V20)
- **O Vega 20/USUÁRIO:** throttle e fan são controlados pelo **hotspot/junction** (TechPowerUp). A **placa de contato stock é côncava → hotspot lê FALSAMENTE ALTO** (110°C à stock! OverclockersUK/Reddit). Com waterblock, contato/TIM irregular mantém o falso-alto sob carga.
- **IMPLICAÇÃO (explica TODOS os freezes):** sob qualquer carga, o SMU pode **ver hotspot falso-alto → proteção térmica → mclk 350 → freeze** — mesmo com clocks baixos (v24/v27 quase-stock travaram). NÃO é o MHz; é o sensor de referência do throttle.
- **USER CONFIRMOU:** "thp sensor ruim" (2026-08-06) — ele já suspeitava do sensor.
- **REMOÇÃO/MITIGAÇÃO:** para OC estável, precisa **desacoplar o throttle do hotspot falso** (ou mitigar o sensor). Opções: manter ThotspotLimit alto e refs edge/HBM, OU melhorar contato (TIM/jaula) no waterblock, OU reduzir clocks até o sensor real não disparar. O **v28 (gpufw-style, SCLK2000/MCLK1150, térmica+volt stock 113/105/4650)** é o candidato pós-boot.

## 🔍 ACHADO DECISIVO (2026-08-06): padrão CORRETO = manter térmica/voltagem STOCK, só SCLK/MCLK/TDP
- **FONTE:** `/mnt/dados/gpu-fw/mi50/pp_table_patches/*.bin` — os patches que validaram 2100/2140/2150 MHz / MCLK 1280–1340.
- **PADRÃO DOS QUE FUNCIONAM:** `SoftwareShutdownTemp=113` (stock), `ThotspotLimit=105` (stock), `TedgeLimit=100`, `ThbmLimit=94` (stock), **`MaxVoltageGfx=4650` (stock, SEM undervolt)**. Só alteram: `SmallPowerLimit 350`, `FreqTableGfx[8]`, `FreqTableUclk[2,3]`.
- **DIVERGÊNCIA DO MEU v26/v27:** eu defini `SoftwareShutdownTemp=150`, `ThotspotLimit=150`, `MaxVoltageGfx=3840` (UV) — **nesse tocavam o SOP térmico/voltagem**. Provaria que mudar esses limites derruba o SMU→freeze.
- **REGRA:** para OC estável desta placa: **MEXER SÓ em TDP/B locks + térmica/voltagem STOCK** (113/105/4650), aplicar pós-boot com daemon v4. Undervolt apenas se o thermal pedir, degrau a degrau.


## 🔍 GATILHO CONFIRMADO (2026-08-06, teste ao vivo): MCLK > stock dispara SMU protection
- **SINTOMA À LUZ DO BOOT:** com v24 (2000/1100) + OD habilitado, `sclk` sobe a **2000 (lvl 8)** mas **`mclk` PRESO em 350 (lvl 0)** = SMU em proteção → freeze → GPU hang (ring/gfx timeout) → reset loop. *TODOS* os perfis que tocam MCLK>1000 (v24=1100, v26=1200) reproduzem isso.
- **CAUSA:** o gatilho é o **MCLK acima de stock (1000)** nesta placa **MI50/Pro VII 16GB HBM 4-high** (CONTEXT.md F1 §39 já avisava "MCLK 1180 ⚠️ agressivo; 16GB 4-high é extrapolação"). O **SCLK 2000 sobe normal** — não é o core clock, é a **memória (HBM)**.
- **PERFIL DE PROVA:** `pp_table_v27_2000_1000_stock_uv50.bin` = MD5 `2d3317c6bac0e1bdf8fe8ac5e5262169` = **SCLK 2000 / MCLK stock 1000** / TDP 350 / UV-50 / hotspot 150. Única mudança vs v25 = MCLK em stock. **Se v27 não travar (mclk 1000, não 350) → prova que MCLK é o gatilho.**
- **TETO SUSTENTÁVEL REAL (a confirmar): SCLK 2000 + MCLK stock 1000** — elevar HBM não sustenta nesta placa.

## 🔍 NOVA PISTA GRANDE 2026-08-06 — isolar em vez de culpar o OC
- **SINTOMA REAL (dmesg): `no-retry page fault` ... `Faulty UTCL2 client ID: TCP (0x8)`** — é **GPU page fault por processo Vulkan/ROCm**, NÃO reset de SMU/energia.
- **CONTEXTO:** 4 `llama-server` (LFM/Nanbeige/Ornity/Bonsai) rodam Vulkan na VRAM no boot **+** `gpu-performance-daemon-v4` faz **rampa 0→8 de clocks** no sysfs **concorrentemente**.
- **HIPÓTESE (explica até o v24 quase-stock falhar):** o "freeze" vem da **concorrência** — aplicar/trocar PP+clocks (mesmo 2000/1100) **enquanto os workloads Vulkan ativos alocam VRAM** → driver troca clock sob carga Vulkan → **page fault TCP** → hang. O OC em si pode NÃO ser a causa; é a troca sob Vulkan.
- **EXPERIMENTO DE ISOLAMENTO (próximo):** boot com a pp_table (v24) mas com **`llama-server` E `gpu-performance-daemon` DESLIGADOS** durante aplicação (PP aplica no boot; checar se não hang; só depois ligar Vulkan). Se estável com Vulkan OFF → culpado é concorrência, não MHz.

## Descobertas Críticas

### 0b. **Wall do Vega 20: SCLK ≥2000 e MCLK ≥1200 é exatamente onde tanga (Igor'sLAB + Reddit)**
- **Igor'sLAB "The Wall"** (artigo oficial): OC estável real do Radeon VII é **2050–2064 MHz** — mas com água/chiller. Com cooler de referência NO AR, o teto estável real é ~2000 MHz; 2150 SCLK + vcore por padrão = instável (dips 1700↔2000). A "wall" = 2000-2064.
- **Reddit TekTick undervolt guide:** HBM **1200 MHz é rock-stable** ("didn't affect anything else"), mas VCORE ideal ~900–1002 mV @ 1740–1950 MHz. ⚠️ **MCLK 1200 é o pico absoluto do HBM2; em alguns ASIC freeza (Shijan/MacRumors: 1100+ pode freeze por instabilidade do HBM)**
- **Conclusão operacional:** o alvo **2100 SCLK / 1200 MCLK está NO LIMITE física** da placa. É o que "sempre funcionou" em benchmarks curtos, mas **estável sustentável precisa:**
  - **SCLK ≤ 2000** (Reddit e Igor's concordam)
  - **MCLK ≤ 1200** (1200 é teto; 1000–1100 é o doce e estável)
  - **IRC +5 que**: aplicar override do HBM (MCLK) é o que mais tende a falsear o sistema freeza (walnut alerta). Em muitas placas, **freeze em 1200 HBM → baixar p/ 1100 resolve**.

### 0. **Regressão de ppfeaturemask é a causa provável de "freeze que antes não existia"**
- **⚠️ CRÍTICO (2026-08-06, confirmado no dmesg): O parâmetro do kernel é `amdgpu.ppfeaturemask=`, NÃO `ppfeaturemask=`.** O dmesg mostrou `Unknown kernel command line parameters "splash ppfeaturemask=..."` — sem o prefixo `amdgpu.`, o kernel REJEITA o parâmetro e o módulo fica no default (`0xfff7bfff`). Resultado: **OverDrive nunca foi ativado** → aplicar pp_table (2000/1100) sem OD → SMU entra em proteção (mclk preso em 350) → GPU reset em loop → freeze. **TODA vez que `cat /sys/module/amdgpu/parameters/ppfeaturemask` mostrar `0xfff7bfff` apesar do cmdline ter o param, a causa é o prefixo faltando.**
- **Fix:** entrada correta = `amdgpu.ppfeaturemask=0xfff7ffff` (bit 14/OD ON). Correção idempotente: `sed -i 's/\bppfeaturemask=amdgpu.ppfeaturemask=/g'`.
- **Sintoma:** overclock que ANTES funcionava (ex: 2100/1200) passa a dar freeze + perda de vídeo + mclk preso em 350 (SMU em proteção).
- **Causa raiz:** `ppfeaturemask` carregado agora = `0xfff7bfff` — **bit 14 (PP_OVERDRIVE_MASK) OFF pela falta do prefixo amdgpu.** Sem OverDrive, driver não aplica OC → SMU proteção → freeze.
- **VALOR CORRETO P/ OC (pesquisa original F1 + prática): `0xfff7ffff`** (só bit 14 ON) — `0xffffffff` também é usado na comunidade mas `0xfff7ffff` é o mínimo; **ambos precisam do prefixo `amdgpu.`**.
- **Regra:** conferir `cat /sys/module/amdgpu/parameters/ppfeaturemask` → `0xfff7ffff`/`0xffffffff` para OC estável; se `0xfff7bfff`, falta prefixo no cmdline.
- **Ferramenta de recover p/ crash:** `amdgpu.dpm=0` no cmdline (também com prefixo) desativa PowerPlay → GPU low-power estável → acesso sem freeze (perde OC, ganha vídeo).

### 1. O driver REJEITA PP tables com muitas mudanças simultâneas

**Sintoma:** `cp table.bin /sys/.../pp_table` retorna sem erro. Verificar com `diff <(upp -p bin dump) <(upp -p sysfs dump)`.

**Regra prática:** Após aplicar, **sempre verificar com diff**. O sysfs é volátil — após reboot forçado (puxar da tomada), as configurações são perdidas.

**Importante:** O driver ACEITOU a v2 (2100/1340/4800/LLC55/300A/350W) — ela rodou por minutos antes do crash por OCP. Só perdeu as configs porque o usuário precisou puxar da tomada após o crash. O sysfs lido após reboot mostrava valores VBIOS stock, mas NÃO porque a table foi rejeitada — a table funcionou, o crash foi de energia e o reboot limpou a memória volátil.

**Confirmação:** A v3 (2050/1200) e a v4 (2100/1340/395W) foram construídas com mudanças múltiplas e foram ACEITAS com diff zero. O driver não rejeita mudanças múltiplas — ele aplica o que for válido.

### 2. MCLK preso em 350MHz = SMU em modo de proteção

**Sintoma:** MCLK não escala acima de 350MHz mesmo com `power_dpm_force_performance_level = high`.

**Causa:** O SMU detectou uma condição anormal (PP table rejeitada, configuração inconsistente entre parâmetros, ou overcorrente) e bloqueou o MCLK como proteção.

**Já aconteceu 2 vezes:**
1. Com FCLK/SOCCLK não-stock (curvas modificadas confundiram o SMU)
2. Após reboot forçado (puxar da tomada pós-crash) — o sysfs perdeu as configs e voltou para VBIOS stock, e o MCLK ficou em 350MHz porque a GPU estava sem a PP table aplicada

### 3. Parâmetros que precisam ser consistentes

Quando alterar SCLK máx, TODOS estes precisam ser atualizados:
```
smcPPTable/FreqTableGfx/8          # Frequência GFX máx
smcPPTable/DcModeMaxFreq/0         # DC mode freq máx (GFX domain)
smcPPTable/GfxclkDsMaxFreq         # Deep sleep max freq
PowerSavingClockTable/PowerSavingClockMax/0  # Power saving max
```

### 4. Limites práticos do Vega 20 (MI50)

| Parâmetro | Stock | Máximo testado | Igor'sLAB wall |
|---|---|---|---|
| SCLK | 1700 MHz | 2140 MHz | ~2050-2064 MHz |
| MCLK | 1000 MHz | 1340 MHz | — |
| MaxVoltageGfx | 4650 (1.16V) | 5000 (1.25V) | 1.3V sem scaling |
| TDP | 190W | 350W | 385W OCP rail |
| TDC | 330A | 330A | — |
| FCLK | 1180 MHz | 1180 MHz | Firmware limit |
| SOCCLK | 972 MHz | 972 MHz | Firmware limit (971) |

### 5. OverDrive8 table tem hard cap de voltagem

`ODSettingsMax 10/11 = 4950` — este é o limite máximo de voltagem que o OverDrive8 table permite. Valores acima podem ser rejeitados ou causar comportamento imprevisível.

### 6. MinVoltageGfx como indicador de "assinatura"

O parâmetro `MinVoltageGfx` NÃO é alterado por nossas modificações, mas é consistente entre as PP tables que criamos (2950) e diferente do que o driver carrega quando rejeita nossas tables (2390). Serve como indicador rápido para saber se a PP table foi aceita ou rejeitada.

### 7. Systemd service é EFETIVO

O serviço `mi50-apply-pp.service` aplica o binário em `/etc/mi50-oc/pp_table_active.bin` no boot. Testado e funcionando — após reboot forçado, a PP table v3 foi restaurada com sucesso.

### 8. Relação TDP / TDC / OCP

O crash de "vcore cut + beep" não é térmico — é **proteção de energia** (OCP do VRM ou PSU).

- TDP 350W → card conseguiu puxar 393W mesmo com limite de 350W (tau=0 desabilita o enforcement suave)
- TDC 300A → pode estar limitando corrente para 395W a 1.2V (I=395/1.2=329A)
- Solução: aumentar TDP para 395W E TDC para 330A
- O limite real é físico (conector 8-pin + 6-pin, PSU capacity, VRM phases)

**Seqüência do crash:**
1. PP table aceita → SCLK 2100, MCLK 1340, MaxVoltage 4800
2. Jogo roda → GPU sob carga → TDP sobe para 393W (acima do limite 350W)
3. Tensão bate 1200mV (MaxVoltageGfx) → corrente muito alta
4. OCP do PSU/VRM dispara → vcore cortado → beep da placa-mãe
5. Forced reboot (puxar da tomada) → sysfs perde as configs

### 9. Sysfs é VOLÁTIL — sempre persistir

O `/sys/class/drm/card1/device/pp_table` é volátil. Qualquer reboot (normal ou forçado) restaura os valores da VBIOS. Sempre:
1. Salvar o binário em `/etc/mi50-oc/pp_table_active.bin`
2. Configurar systemd service para aplicar no boot (`mi50-apply-pp.service`)
3. Após reboot, **verificar** com `diff` que a table foi restaurada

## Fluxo de Debug

1. Escrever PP table → `cp table.bin /sys/.../pp_table`
2. **SEMPRE verificar** → `upp -p /sys/... dump | diff - <(upp -p table.bin dump)`
3. Se diff acusar diferenças → a table foi rejeitada
4. Se diff vazio → table aceita

## Referências

- [Igor'sLAB - Radeon VII Overclocking Wall](https://www.igorslab.de/en/radeon-vii-overclocking/)
- [TechPowerUp - Radeon VII Review](https://www.techpowerup.com/review/amd-radeon-vii/33.html)
- [GamersNexus - Radeon VII Liquid Cooled OC](https://gamersnexus.net/guides/3450-amd-radeon-vii-powerplay-overclocking-results-liquid-cooling-mod)
- [UPP - unofficial power play tool](https://github.com/sibradzic/upp)
