#!/usr/bin/env python3
"""
mi50_slave_pnp.py

Tool portátil para:
- detectar a MI50 pelo Device ID
- fazer backup do pp_table
- salvar patch no slave
- aplicar patch em runtime quando executado como root
- restaurar backup

Uso simples:
  sudo python3 mi50_slave_pnp.py apply --power 350 --tdc 300
  sudo python3 mi50_slave_pnp.py status
  sudo python3 mi50_slave_pnp.py rollback --backup /caminho/do/backup.bin

Observação:
- Tudo fica salvo no diretório BASE.
- Se o master for formatado, o que estiver só no master some.
- O que estiver no slave continua.
"""

from __future__ import annotations

import json
import argparse
import datetime as dt
import os
from pathlib import Path
import struct
import sys
from typing import Optional, Tuple

BASE = Path(os.environ.get("AI_LAB_BASE", "/mnt/dados"))
GPU_DIR = BASE / "gpu-fw" / "mi50"
BACKUP_DIR = GPU_DIR / "backups"
PATCH_DIR = GPU_DIR / "patched"
LOG_DIR = BASE / "logs"
STATE_FILE = GPU_DIR / "last_state.json"

MI50_DEVICE_ID = "0x66a1"

# Heurística conservadora: limita alterações cegas e exige backup antes.
DEFAULT_TDC_A = 300
DEFAULT_POWER_W = 350


def ensure_tree() -> None:
    for p in (GPU_DIR, BACKUP_DIR, PATCH_DIR, LOG_DIR):
        p.mkdir(parents=True, exist_ok=True)


def log(msg: str) -> None:
    ts = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        with open(LOG_DIR / "mi50_pnp.log", "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def is_root() -> bool:
    return hasattr(os, "geteuid") and os.geteuid() == 0


def detect_pp_table() -> Optional[Path]:
    # Busca direta e depois por índice PCI -> drm/card*/device/pp_table
    for dev in Path("/sys/bus/pci/devices").glob("*"):
        device_file = dev / "device"
        if device_file.exists():
            try:
                content = device_file.read_text(errors="ignore").lower()
            except Exception:
                continue
            if MI50_DEVICE_ID in content:
                matches = list((dev / "drm").glob("card*/device/pp_table"))
                if matches:
                    return matches[0]
    return None


def read_pp_table(pp_path: Path) -> bytearray:
    return bytearray(pp_path.read_bytes())


def write_pp_table(pp_path: Path, data: bytes) -> None:
    pp_path.write_bytes(data)


def backup_current(pp_path: Path) -> Path:
    ensure_tree()
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = BACKUP_DIR / f"pp_table_{stamp}.bin"
    out.write_bytes(pp_path.read_bytes())
    log(f"backup salvo em: {out}")
    return out


def save_patched(data: bytes, power_w: int, tdc_a: int) -> Path:
    ensure_tree()
    out = PATCH_DIR / f"mi50_{power_w}w_tdc{tdc_a}a.bin"
    out.write_bytes(data)
    log(f"patch salvo em: {out}")
    return out


def patch_power(data: bytearray, power_w: int, tdc_a: int, mode: str) -> Tuple[bytearray, dict]:
    """
    mode:
      - heuristic: troca ocorrências de 190W -> power_w em áreas compatíveis
      - offsets: tenta escrever offsets fixos, mas só se o binário tiver tamanho mínimo
    """
    info = {"replacements": 0, "tdc_written": False, "mode": mode}

    old_pwr = struct.pack("<H", 190)
    new_pwr = struct.pack("<H", power_w)

    if mode == "heuristic":
        idx = 0
        while True:
            idx = data.find(old_pwr, idx)
            if idx == -1:
                break

            # filtro simples para evitar sair trocando lixo aleatório:
            # exige contexto mínimo e evita borda do arquivo.
            start = max(0, idx - 8)
            end = min(len(data), idx + 10)
            ctx = data[start:end]

            if len(ctx) >= 8:
                zero_count = ctx.count(0)
                # aceita somente se não parece padding puro
                if zero_count < len(ctx) - 2:
                    data[idx:idx + 2] = new_pwr
                    info["replacements"] += 1

            idx += 2

    elif mode == "offsets":
        # Mantém como fallback explícito. Não usa sem saber o layout do teu binário.
        if len(data) < 0x4C:
            raise ValueError("pp_table pequeno demais para patch por offsets.")
        data[0x46:0x48] = new_pwr
        info["replacements"] = 1

    else:
        raise ValueError("modo inválido")

    # TDC em offset fixo somente como fallback opcional.
    # Se o layout não bater, o ideal é gerar um parser específico do teu dump.
    if len(data) >= 0x4C:
        try:
            data[0x4A:0x4C] = struct.pack("<H", tdc_a)
            info["tdc_written"] = True
        except Exception:
            info["tdc_written"] = False

    return data, info


def apply_patch(power_w: int, tdc_a: int, mode: str, live: bool, force: bool) -> int:
    ensure_tree()

    pp_path = detect_pp_table()

    if not pp_path:
        log("MI50 não encontrada em /sys/bus/pci/devices.")
        return 2

    log(f"pp_table detectada em: {pp_path}")

    if live and not is_root():
        log("aplicação live exige root.")
        return 3

    backup = backup_current(pp_path)
    current = read_pp_table(pp_path)

    patched_file = PATCH_DIR / f"mi50_{power_w}w_tdc{tdc_a}a.bin"

    # reutiliza firmware persistente
    if patched_file.exists():

        log(f"usando firmware persistente: {patched_file}")

        try:
            patched = bytearray(patched_file.read_bytes())

            if len(patched) != len(current):
                log("firmware persistente inválido")
                return 6

            info = {
                "replacements": -1,
                "tdc_written": True,
                "mode": "persistent"
            }

            patched_path = patched_file

        except Exception as e:
            log(f"erro carregando firmware persistente: {e}")
            return 7

    else:

        patched, info = patch_power(current, power_w, tdc_a, mode)

        if info["replacements"] == 0 and mode == "heuristic" and not force:
            log("nenhuma ocorrência útil foi encontrada; patch cancelado.")
            return 4

        patched_path = save_patched(patched, power_w, tdc_a)

    STATE_FILE.write_text(
        json.dumps(
            {
                "pp_table": str(pp_path),
                "backup": str(backup),
                "patched": str(patched_path),
                "power_w": power_w,
                "tdc_a": tdc_a,
                "mode": info["mode"],
                "live": live,
                "replacements": info["replacements"],
                "tdc_written": info["tdc_written"],
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    if live:
        write_pp_table(pp_path, patched)
        log("patch aplicado em runtime.")

    log(
        f"concluído: "
        f"power={power_w}W "
        f"tdc={tdc_a}A "
        f"mode={info['mode']} "
        f"replacements={info['replacements']}"
    )

    return 0


def rollback(backup: Path, live: bool) -> int:
    pp_path = detect_pp_table()
    if not pp_path:
        log("MI50 não encontrada.")
        return 2

    if live and not is_root():
        log("rollback live exige root.")
        return 3

    data = backup.read_bytes()
    patched_path = PATCH_DIR / f"rollback_{backup.stem}.bin"
    patched_path.write_bytes(data)

    if live:
        write_pp_table(pp_path, data)
        log("rollback aplicado em runtime.")

    log(f"rollback pronto. cópia salva em: {patched_path}")
    return 0


def status() -> int:
    pp_path = detect_pp_table()
    if not pp_path:
        log("MI50 não encontrada.")
        return 2

    size = pp_path.stat().st_size
    log(f"pp_table: {pp_path}")
    log(f"tamanho: {size} bytes")
    if STATE_FILE.exists():
        log(f"estado salvo: {STATE_FILE}")
    else:
        log("sem estado salvo ainda.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="mi50_slave_pnp.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    ap = sub.add_parser("apply", help="gera backup, salva patch e opcionalmente aplica ao vivo")
    ap.add_argument("--power", type=int, default=DEFAULT_POWER_W, help="limite de potência em W")
    ap.add_argument("--tdc", type=int, default=DEFAULT_TDC_A, help="limite de corrente em A")
    ap.add_argument("--mode", choices=("heuristic", "offsets"), default="heuristic")
    ap.add_argument("--live", action="store_true", help="escreve no pp_table em runtime")
    ap.add_argument("--force", action="store_true", help="força aplicação mesmo sem matches heurísticos")

    rb = sub.add_parser("rollback", help="restaura um backup")
    rb.add_argument("--backup", type=Path, required=True)
    rb.add_argument("--live", action="store_true")

    sub.add_parser("status", help="mostra a pp_table detectada")

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.cmd == "apply":
        return apply_patch(args.power, args.tdc, args.mode, args.live, args.force)

    if args.cmd == "rollback":
        if not args.backup.exists():
            log("backup não encontrado.")
            return 2
        return rollback(args.backup, args.live)

    if args.cmd == "status":
        return status()

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
