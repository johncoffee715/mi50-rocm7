# Regra de Ouro do Modd MI50 (Vega 20 / Pro VII 66A1)

> Diretriz oficial consolidada em 2026-07-31, após diagnóstico de campo
> (perda de vídeo + corte de Vcore + beep no início de inferência).

## O problema

Com DPM automático, o clock salta **idle → 2000MHz instantaneamente** quando a
carga (inferência/LLM) inicia. O PMFW exige uma puxada de corrente abrupta e a
**proteção de energia (VRM/PSU) dispara**: corta Vcore, beep, perde vídeo.

**Não é** TDP, nem thermal throttling, nem arrefecimento, nem MCLK/SCLK em si,
nem undervolting — funciona com clocks **mais altos** quando a transição é suave.

## As 3 regras

1. **O daemon de performance é OBRIGATÓRIO em todo modd desta GPU.**
   `gpu-performance-daemon-v4.sh` deve estar ativo (systemd, enabled) junto
   com qualquer pp_table modificada.

2. **TDP sempre 350W fixo.**
   A placa pode receber 75W do PCIe + 150W × 2 (8-pin) = **375W disponível**;
   350W é o teto operacional correto. Nunca reduzir.

3. **O salto idle→full load deve PERCORRER GRADATIVAMENTE os estágios DPM**
   — tanto em clock quanto em alimentação. É para isso que existem os
   8 estágios (0-7 + topo): transição gradual = mecanismo anti-bug.

## Implementação: daemon v4 (rampa gradual)

- **Subida:** 1 nível/seg pelos estágios SCLK (0→1→2→…→8) ao detectar carga
  (`gpu_busy_percent ≥ 5`), MCLK acompanha (0→1→2)
- **Descida:** gradual (8→…→0) quando a carga cai
- **Idle profundo:** após ~15 ciclos, retorna a `auto`
- **TDP:** 350W fixo na pp_table (nunca reduzir)

## Instalação

```bash
sudo ./install_daemon_v4.sh
```

Verificação: `journalctl -u gpu-performance-daemon -f` → linhas `rampa ↑ SCLK=...`

## Configuração de referência (validada)

| Parâmetro | Valor |
|---|---|
| TDP | 350W fixo |
| SCLK | 2000MHz (estágio 8) |
| MCLK | 1120MHz (estágio 2) — 16GB 4-Hi é conservador |
| Voltagem | stock (undervolt é opcional e por sua conta) |
| FCLK / SOCCLK / LLC | stock |
| Daemon | v4 rampa gradual (obrigatório) |
