# PLAN: SOCCLK 1000MHz via PP Table — Dev Loop MIX

## FASE 3: PLANO

### Task Breakdown

**Task 1: Analisar SOCCLK values anteriores**
- Prometheus: explorar histórico de SOCCLK
- Output: tabela de SOCCLK tested vs resultado

**Task 2: Reduzir SOCCLK para 1000MHz**
- Atlas: aplicar mudança na upp_targets_350w.conf
- All 8 slots FreqTableSocclk/0..7 = 1000 (was 1165)
- Backup de config anterior

**Task 3: Gerar nova PP table binária**
- Atlas: executar `upp set --write --from-conf`
- Output: pp_table_350w_2000sclk_1200mclk.bin

**Task 4: Commit e push**
- Commit: aea8f17 "Add MIX profile: SOCCLK 1000MHz"
- Push: origin/main

**Task 5: Documentar**
- Atualizar README.md com perfil MIX
- Atualizar vault cerebral

### Dependencies
- Task 1 → Task 2 → Task 3 → Task 4 → Task 5

### Acceptance Criteria (UAT)
1. ✅ SOCCLK todos slots = 1000MHz na config
2. ✅ Config upp_targets_350w.conf atualizado
3. ✅ Config upp_targets_350w_mix_socclk1000.conf criado
4. ✅ Commit e push realizados
5. ⏳ GPU offline: aplicar na próxima reinicialização

### Risk Assessment
- Riesgo: SOCCLK < 1000MHz poderia ser mais seguro, mas reduz performance
- Mitigação: 1000MHz é o valor máximo estável testado
- Backout: reverter para SOCCLK 1165 (valor stock)

### Dev Loop Tracking
| Iteração | SOCCLK | Resultado |
|----------|--------|-----------|
| 1 | 1165 (stock) | OK |
| 2 | 1080MHz | CRASH kernel loading |
| 3 | 1000MHz | ESTÁVEL ✅ |
