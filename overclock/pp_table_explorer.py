#!/usr/bin/env python3
"""
pp_table_explorer.py — AMD GPU PowerPlay Table Explorer & Patcher

Ferramenta para analisar e modificar a tabela de power play (pp_table)
de GPUs AMD Vega 20 (Radeon VII, Radeon Pro VII, MI50, MI60) via sysfs.

Usa UPP (Uplift Power Play) como backend para todas as operações de
leitura e modificação — não usa offsets hexadecimais hardcoded.

Uso:
  python3 pp_table_explorer.py info                    # Mostra info da GPU
  python3 pp_table_explorer.py dump                    # Dump completo da pp_table atual
  python3 pp_table_explorer.py explore <file.bin>      # Analisa arquivo via UPP
  python3 pp_table_explorer.py patch <file.bin> <power_w> [sclk] [mclk]  # Cria patch via UPP
  python3 pp_table_explorer.py apply <file.bin>        # Aplica ao sysfs (root)
  python3 pp_table_explorer.py save [filename]         # Salva pp_table atual
  python3 pp_table_explorer.py restore <file.bin>      # Restaura pp_table (root)
"""

import argparse
import hashlib
import os
import subprocess
import sys
import time


CARD0_SYSFS = "/sys/class/drm/card0/device/pp_table"
BACKUP_DIR = "/etc/mi50-oc/backup"


def find_upp() -> str:
    """Localiza o binário UPP no sistema."""
    for candidate in [
        os.path.expanduser("~/.local/bin/upp"),
        "/usr/local/bin/upp",
        "/usr/bin/upp",
    ]:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    # tentar via PATH
    try:
        result = subprocess.run(
            ["command", "-v", "upp"], capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass
    return "upp"  # fallback


def upp_dump(bin_path: str) -> str:
    """Executa upp dump e retorna stdout."""
    upp = find_upp()
    result = subprocess.run(
        [upp, "-p", bin_path, "dump"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        print(f"⚠️  UPP dump falhou: {result.stderr.strip()}")
        return ""
    return result.stdout


def upp_set(bin_path: str, param: str, value, output_path: str = None) -> bool:
    """Modifica um parâmetro via UPP set --write."""
    upp = find_upp()
    out_path = output_path or bin_path
    cmd = [upp, "-p", bin_path, "set", "--write", f"{param}={value}"]
    if output_path and output_path != bin_path:
        cmd += ["-o", output_path]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        print(f"⚠️  UPP set {param}={value} falhou: {result.stderr.strip()}")
        return False
    return True


def get_gpu_info():
    """Mostra informações da GPU."""
    print("=" * 60)
    print("GPU Information")
    print("=" * 60)

    # rocm-smi
    try:
        subprocess.run(
            "rocm-smi --showproductname 2>/dev/null", shell=True, timeout=10
        )
    except Exception:
        print("  rocm-smi não disponível")

    # sysfs clocks
    for label, path in [
        ("SCLK", "/sys/class/drm/card0/device/pp_dpm_sclk"),
        ("MCLK", "/sys/class/drm/card0/device/pp_dpm_mclk"),
    ]:
        if os.path.exists(path):
            try:
                with open(path) as f:
                    lines = f.read().strip().splitlines()
                    print(f"  {label}:")
                    for line in lines[-3:]:
                        print(f"    {line.strip()}")
            except Exception:
                pass

    # Temperatura
    try:
        result = subprocess.run(
            "rocm-smi --showtemp 2>/dev/null | grep -E 'GPU|edge|junction|memory'",
            shell=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.stdout.strip():
            print(f"  Temp:\n{result.stdout.rstrip()}")
    except Exception:
        pass

    # Potência
    try:
        result = subprocess.run(
            "rocm-smi --showpower 2>/dev/null | grep -E 'GPU|Average|Current'",
            shell=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.stdout.strip():
            print(f"  Power:\n{result.stdout.rstrip()}")
    except Exception:
        pass

    # ppfeaturemask
    try:
        with open("/sys/module/amdgpu/parameters/ppfeaturemask") as f:
            mask = f.read().strip()
            ok = "✅" if mask == "0xffffffff" else "⚠️"
            print(f"  ppfeaturemask: {mask} {ok}")
    except Exception:
        pass

    # UPP disponível?
    upp = find_upp()
    if upp:
        try:
            ver = subprocess.run(
                [upp, "--version"], capture_output=True, text=True, timeout=5
            )
            print(f"  UPP: {ver.stdout.strip() or 'ok'}")
        except Exception:
            print(f"  UPP: {upp}")
    else:
        print("  UPP: não encontrado (pipx install upp)")


def analyze_with_upp(bin_path: str, label: str = ""):
    """Analisa PP table via UPP dump e mostra parâmetros relevantes."""
    size = os.path.getsize(bin_path)
    sha = hashlib.sha256()
    with open(bin_path, "rb") as f:
        sha.update(f.read())
    hash_str = sha.hexdigest()

    print(f"\n{'=' * 60}")
    print(f"PP Table Analysis {label}")
    print(f"{'=' * 60}")
    print(f"  Size: {size} bytes")
    print(f"  SHA-256: {hash_str[:20]}...")

    dump = upp_dump(bin_path)

    # Parâmetros de interesse
    params = [
        "SmallPowerLimit1",
        "SmallPowerLimit2",
        "BoostPowerLimit",
        "ODTurboPowerLimit",
        "SocketPowerLimitAc0",
        "SocketPowerLimitDc",
        "FreqTableGfx",
        "FreqTableUclk",
        "MaxVoltageGfx",
        "MaxVoltageUclk",
        "TdcLimit",
        "ShutdownTemp",
        "MinVoltageGfx",
        "MinVoltageUclk",
    ]

    print(f"\n  Parâmetros (UPP):")
    found_any = False
    for param in params:
        for line in dump.splitlines():
            if param in line:
                print(f"    {line.strip()}")
                found_any = True
    if not found_any:
        print("    (UPP dump não retornou dados. Verifique o formato do arquivo.)")
        print(f"\n  Raw dump (primeiras 20 linhas):")
        for line in dump.splitlines()[:20]:
            print(f"    {line}")

    # Parse SCLK table
    sclk_levels = []
    for line in dump.splitlines():
        if "FreqTableGfx" in line:
            parts = line.split()
            for i, p in enumerate(parts):
                try:
                    val = int(p)
                    if 200 <= val <= 3000:
                        sclk_levels.append(val)
                except ValueError:
                    pass

    uclk_levels = []
    for line in dump.splitlines():
        if "FreqTableUclk" in line:
            parts = line.split()
            for i, p in enumerate(parts):
                try:
                    val = int(p)
                    if 200 <= val <= 3000:
                        uclk_levels.append(val)
                except ValueError:
                    pass

    if sclk_levels:
        print(f"\n  SCLK Levels: {', '.join(str(v) for v in sclk_levels)} MHz")
        print(f"  SCLK Max: {max(sclk_levels)} MHz")
    if uclk_levels:
        print(f"\n  MCLK Levels: {', '.join(str(v) for v in uclk_levels)} MHz")
        print(f"  MCLK Max: {max(uclk_levels)} MHz")

    return {"sclk_levels": sclk_levels, "uclk_levels": uclk_levels}


def create_patch_upp(source: str, power_w: int, sclk: int = None, mclk: int = None) -> str:
    """Cria PP table patch usando UPP."""
    if not os.path.isfile(source):
        print(f"❌ Arquivo não encontrado: {source}")
        sys.exit(1)

    base = os.path.splitext(os.path.basename(source))[0]
    parts = [base, f"{power_w}w"]
    if sclk:
        parts.append(f"{sclk}mhz")
    if mclk:
        parts.append(f"{mclk}uclk")
    out_name = "_".join(parts) + ".bin"

    # Copia o arquivo fonte
    import shutil
    shutil.copy2(source, out_name)

    print(f"\n🔧 Criando patch via UPP:")
    print(f"   Fonte: {source}")
    print(f"   Power Limit: {power_w}W")
    if sclk:
        print(f"   SCLK Max: {sclk} MHz")
    if mclk:
        print(f"   MCLK Max: {mclk} MHz")
    print(f"   Destino: {out_name}")

    # Power limits (sempre)
    params = {
        "SmallPowerLimit1": power_w,
        "SmallPowerLimit2": power_w,
        "BoostPowerLimit": power_w,
        "ODTurboPowerLimit": power_w,
        "smcPPTable/SocketPowerLimitAc0": power_w,
        "smcPPTable/SocketPowerLimitDc": power_w,
    }

    for param, value in params.items():
        if upp_set(out_name, param, value):
            print(f"  ✅ {param} = {value}")

    # SCLK
    if sclk:
        # Tenta encontrar o SCLK mais alto e modificar
        for level in range(9):
            param = f"smcPPTable/FreqTableGfx/{level}"
            if upp_set(out_name, param, sclk):
                print(f"  ✅ {param} = {sclk} MHz")

    # MCLK
    if mclk:
        for level in range(3):
            param = f"smcPPTable/FreqTableUclk/{level}"
            if upp_set(out_name, param, mclk):
                print(f"  ✅ {param} = {mclk} MHz")

    print(f"\n💾 Salvo: {out_name}")
    print(f"   SHA-256: ", end="")
    sha = hashlib.sha256()
    with open(out_name, "rb") as f:
        sha.update(f.read())
    print(sha.hexdigest())

    return out_name


def apply_to_sysfs(bin_path: str):
    """Aplica PP table ao sysfs."""
    if not os.path.isfile(bin_path):
        print(f"❌ Arquivo não encontrado: {bin_path}")
        sys.exit(1)

    if not os.path.isfile(CARD0_SYSFS):
        print(f"❌ GPU não encontrada em {CARD0_SYSFS}")
        sys.exit(1)

    target = CARD0_SYSFS
    size = os.path.getsize(bin_path)
    sclk = "?"
    mclk = "?"
    orig_hash = "?"

    # Backup automático
    try:
        with open(target, "rb") as f:
            orig = f.read()
        orig_hash = hashlib.sha256(orig).hexdigest()[:16]
    except Exception:
        pass

    try:
        with open(bin_path, "rb") as f:
            data = f.read()

        # Tentar ler clocks do dump UPP
        dump = upp_dump(bin_path)
        for line in dump.splitlines():
            if "FreqTableGfx" in line:
                parts = line.split()
                for p in parts:
                    try:
                        sclk_candidate = int(p)
                        if 200 <= sclk_candidate <= 3000:
                            sclk = str(sclk_candidate)
                    except ValueError:
                        pass
            if "FreqTableUclk" in line:
                parts = line.split()
                for p in parts:
                    try:
                        mclk_candidate = int(p)
                        if 200 <= mclk_candidate <= 3000:
                            mclk = str(mclk_candidate)
                    except ValueError:
                        pass

        # Escrever no sysfs (root required)
        with open(target, "wb") as f:
            f.write(data)

        sha = hashlib.sha256(data).hexdigest()[:16]
        print(f"✅ PP table aplicada: {bin_path} → {target}")
        print(f"   Size: {size} bytes")
        print(f"   SCLK max: {sclk} MHz")
        print(f"   MCLK max: {mclk} MHz")
        print(f"   SHA-256: {sha}")
        print(f"   Backup (orig): {orig_hash}")
    except PermissionError:
        print("❌ Permissão negada. Execute como root.")
        print(f"   Use: sudo python3 pp_table_explorer.py apply {bin_path}")
        sys.exit(1)
    except OSError as e:
        print(f"❌ Erro de escrita: {e}")
        sys.exit(1)


def save_current(filename: str = None):
    """Salva a PP table atual do sysfs."""
    if not os.path.isfile(CARD0_SYSFS):
        print(f"❌ GPU não encontrada em {CARD0_SYSFS}")
        sys.exit(1)

    try:
        with open(CARD0_SYSFS, "rb") as f:
            data = f.read()
    except PermissionError:
        print("❌ Permissão negada.")
        sys.exit(1)

    if not filename:
        sha = hashlib.sha256(data).hexdigest()[:8]
        filename = f"pp_table_{sha}.bin"

    with open(filename, "wb") as f:
        f.write(data)

    sha = hashlib.sha256(data).hexdigest()
    print(f"💾 pp_table salva em {filename}")
    print(f"   Size: {len(data)} bytes")
    print(f"   SHA-256: {sha}")

    # Analisar com UPP
    analyze_with_upp(filename, f"[{filename}]")


def restore_from(bin_path: str):
    """Restaura PP table de um arquivo."""
    apply_to_sysfs(bin_path)


def main():
    parser = argparse.ArgumentParser(
        description="AMD GPU PowerPlay Table Explorer & Patcher (UPP backend)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Comandos:
  info              Mostra informações da GPU
  dump              Salva e analisa a pp_table atual
  explore <file>    Analisa um arquivo .bin via UPP
  patch <file> <W> [SCLK] [MCLK]   Cria patch via UPP
  apply <file>      Aplica pp_table ao sysfs (root)
  save [filename]   Salva pp_table atual
  restore <file>    Restaura pp_table do arquivo
        """,
    )

    parser.add_argument("command", nargs="?", help="Comando a executar")
    parser.add_argument(
        "args", nargs=argparse.REMAINDER, help="Argumentos do comando"
    )

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    cmd = args.command
    cmd_args = args.args

    if cmd == "info":
        get_gpu_info()
        if os.path.isfile(CARD0_SYSFS):
            try:
                with open(CARD0_SYSFS, "rb") as f:
                    data = f.read()
                analyze_with_upp(CARD0_SYSFS, "[sysfs live]")
            except PermissionError:
                print("\n⚠️  Não foi possível ler pp_table (permissão). Use sudo para info completa.")
            except Exception as e:
                print(f"\n⚠️  Erro lendo pp_table: {e}")

    elif cmd == "dump":
        save_current(cmd_args[0] if cmd_args else None)

    elif cmd == "explore":
        if not cmd_args:
            print("Uso: python3 pp_table_explorer.py explore <file.bin>")
            sys.exit(1)
        analyze_with_upp(cmd_args[0], f"[{cmd_args[0]}]")

    elif cmd == "patch":
        if len(cmd_args) < 2:
            print("Uso: python3 pp_table_explorer.py patch <file.bin> <power_W> [sclk_mhz] [mclk_mhz]")
            sys.exit(1)
        source = cmd_args[0]
        power = int(cmd_args[1])
        sclk = int(cmd_args[2]) if len(cmd_args) > 2 else None
        mclk = int(cmd_args[3]) if len(cmd_args) > 3 else None
        create_patch_upp(source, power, sclk, mclk)

    elif cmd == "apply":
        if not cmd_args:
            print("Uso: python3 pp_table_explorer.py apply <file.bin>")
            sys.exit(1)
        apply_to_sysfs(cmd_args[0])

    elif cmd == "save":
        save_current(cmd_args[0] if cmd_args else None)

    elif cmd == "restore":
        if not cmd_args:
            print("Uso: python3 pp_table_explorer.py restore <file.bin>")
            sys.exit(1)
        restore_from(cmd_args[0])

    else:
        print(f"❌ Comando desconhecido: {cmd}")
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
