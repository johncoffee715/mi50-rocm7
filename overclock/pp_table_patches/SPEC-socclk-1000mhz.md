# SPEC: SOCCLK 1000MHz — Mixer Profile (MIX)

## Resumo
Reduzir SOCCCLK para 1000MHz na PP table da MI50 (Vega20, gfx906).
Anteriores (1080MHz e superiores) crasham durante loading do kernel.

## Motivation
- SOCCLK 1080MHz causa crash no kernel loading (anterior estaba em pp_table_patches/legacy/)
- 1000MHz é o valor máximo estável testado
- Perfil "MIX" = perfil misto de overclock para uso diário sem instabilidade

## Acceptance Criteria
1. Config upp_targets_350w.conf: todos 8 slots FreqTableSocclk/=1000
2. Config upp_targets_350w_mix_socclk1000.conf: criado e consistente
3. Commits: aea8f17 (MIX profile) + ecc90e2 (V2)
4. Push: origin/main atualizado
5. GPU offline: configurar na próxima reinicialização via deploy.sh

## Constraints
- SOCCLK não pode exceder 1000MHz (crash confirmado)
- Demais parâmetros permanecem inalterados (350W/2000/1200/1200/1165)
- TTY mode: toda modificação deve ser feita em TTY

## Dev Loop
- Iteração 1: Testar SOCCLK 1080MHz → CRASH
- Iteração 2: Reduzir para 1000MHz → ESTÁVEL
- Next: Validar em full load com clpeak/vkpeak
