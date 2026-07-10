#!/usr/bin/env python3
"""
pp_table_explorer.py — AMD GPU PowerPlay Table Explorer & Patcher

Ferramenta para analisar e modificar a tabela de power play (pp_table)
de GPUs AMD via sysfs ou arquivo binário.

Suporta: Vega 20 (Radeon VII, Radeon Pro VII, MI50, MI60)
         MI50/MI60 (gfx906)

Uso:
  python3 pp_table_explorer.py info                    # Mostra info da GPU atual
  python3 pp_table_explorer.py dump                    # Dump completo da pp_table
  python3 pp_table_explorer.py explore <file.bin>     # Analisa arquivo pp_table
  python3 pp_table_explorer.py patch <file.bin> <sclk_mhz> [mclk_mhz]  # Cria patch
  python3 pp_table_explorer.py apply <file.bin>        # Aplica ao sysfs (root)
  python3 pp_table_explorer.py save                    # Salva pp_table atual
  python3 pp_table_explorer.py restore <file.bin>      # Restaura pp_table (root)
"""

import struct
import sys
import os
import subprocess

# Vega 20 offset map
PP_TABLE_OFFSETS = {
    'sclk_table': 826,      # 9 entries × 2 bytes
    'sclk_max': 842,        # SCLK max frequency
    'sclk_copy1': 1010,     # SCLK max copy
    'sclk_copy2': 1066,     # SCLK max copy
    'mclk_table': 922,      # 3 entries × 2 bytes
    'mclk_max': 926,        # MCLK max frequency
    'mclk_copy': 928,       # MCLK max copy
    'tdp_offsets': [112, 116, 376, 380],  # TDP in Watts (4-byte)
}

GPU_INFO_CMD = "rocm-smi --showproductname 2>/dev/null | grep -A5 'Product Info'"
SCLK_CMD = "cat /sys/class/drm/card*/device/pp_dpm_sclk 2>/dev/null | tail -1"
MCLK_CMD = "cat /sys/class/drm/card*/device/pp_dpm_mclk 2>/dev/null | tail -1"
TEMP_CMD = "rocm-smi --showtemp 2>/dev/null | grep junction"


def find_pp_table_sysfs():
    """Encontra o path do pp_table no sysfs."""
    for path in [
        "/sys/class/drm/card1/device/pp_table",
        "/sys/class/drm/card0/device/pp_table",
        "/sys/bus/pci/devices/0000:05:00.0/drm/card1/device/pp_table",
    ]:
        if os.path.exists(path):
            return path
    return None


def read_pp_table(path):
    """Lê pp_table de arquivo ou sysfs."""
    if path == "sysfs" or not path:
        path = find_pp_table_sysfs()
        if not path:
            print("❌ pp_table sysfs não encontrado!")
            sys.exit(1)
    
    try:
        with open(path, 'rb') as f:
            data = f.read()
        return data, path
    except PermissionError:
        print(f"❌ Permissão negada: {path}. Execute como root.")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Erro lendo {path}: {e}")
        sys.exit(1)


def analyze_pp_table(data, label=""):
    """Analisa e exibe o conteúdo da pp_table."""
    print(f"\n{'='*60}")
    print(f"📊 pp_table Analysis {label}")
    print(f"{'='*60}")
    print(f"  Size: {len(data)} bytes")
    
    # SCLK DPM table
    print(f"\n  🔵 SCLK DPM Table (9 levels):")
    for i in range(9):
        off = PP_TABLE_OFFSETS['sclk_table'] + i * 2
        val = struct.unpack('<H', data[off:off+2])[0]
        marker = " ⭐ MAX" if val == max(
            struct.unpack('<H', data[PP_TABLE_OFFSETS['sclk_table']+j*2:
                                    PP_TABLE_OFFSETS['sclk_table']+j*2+2])[0]
            for j in range(9)
        ) else ""
        print(f"    Level {i}: {val} MHz (offset {off}){marker}")
    
    # Check SCLK max consistency
    sclk_max_off = PP_TABLE_OFFSETS['sclk_max']
    sclk_max = struct.unpack('<H', data[sclk_max_off:sclk_max_off+2])[0]
    print(f"\n  SCLK max references:")
    for name, off in [('main', 842), ('copy1', 1010), ('copy2', 1066)]:
        val = struct.unpack('<H', data[off:off+2])[0]
        match = "✅" if val == sclk_max else "❌ MISMATCH"
        print(f"    {name}: {val} MHz @ offset {off} {match}")
    
    # MCLK DPM table
    mclk_off = PP_TABLE_OFFSETS['mclk_table']
    print(f"\n  🟢 MCLK DPM Table (3 levels):")
    for i in range(3):
        off = mclk_off + i * 2
        val = struct.unpack('<H', data[off:off+2])[0]
        print(f"    Level {i}: {val} MHz (offset {off})")
    
    # MCLK max consistency
    mclk_max_off = PP_TABLE_OFFSETS['mclk_max']
    mclk_max = struct.unpack('<H', data[mclk_max_off:mclk_max_off+2])[0]
    for name, off in [('max', 926), ('copy', 928)]:
        val = struct.unpack('<H', data[off:off+2])[0]
        match = "✅" if val == mclk_max else "❌ MISMATCH"
        print(f"    {name}: {val} MHz @ offset {off} {match}")
    
    # Power/TDP
    print(f"\n  🔴 TDP/Power values:")
    for off in PP_TABLE_OFFSETS['tdp_offsets']:
        if off < len(data):
            val = struct.unpack('<I', data[off:off+4])[0]
            print(f"    offset {off}: {val} W (32-bit: 0x{val:08x})")
    
    # Search for all frequency values
    print(f"\n  📈 All frequency values found:")
    found = []
    for off in range(0, len(data) - 1, 2):
        val = struct.unpack('<H', data[off:off+2])[0]
        if 800 <= val <= 2500:
            found.append((off, val))
    
    # Group consecutive frequencies
    groups = []
    current_group = []
    for off, val in found:
        if not current_group or off == current_group[-1][0] + 2:
            current_group.append((off, val))
        else:
            if len(current_group) >= 4:
                groups.append(current_group)
            current_group = [(off, val)]
    if len(current_group) >= 4:
        groups.append(current_group)
    
    for g in groups:
        vals = [v for _, v in g]
        print(f"    offset {g[0][0]}: {' '.join(str(v) for v in vals)} MHz")
    
    return {'sclk_max': sclk_max, 'mclk_max': mclk_max}


def get_gpu_info():
    """Mostra informações da GPU via rocm-smi e sysfs."""
    print("\n" + "="*60)
    print("🖥️  GPU Information")
    print("="*60)
    
    try:
        subprocess.run("rocm-smi --showproductname 2>/dev/null", shell=True)
    except:
        print("  rocm-smi não disponível")
    
    for cmd, label in [(SCLK_CMD, "SCLK"), (MCLK_CMD, "MCLK"), (TEMP_CMD, "Temp")]:
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            if result.stdout.strip():
                print(f"  {label}: {result.stdout.strip()}")
        except:
            pass
    
    # Kernel param
    try:
        with open('/sys/module/amdgpu/parameters/ppfeaturemask') as f:
            mask = f.read().strip()
            print(f"  ppfeaturemask: {mask} {'✅' if mask == '0xffffffff' else '⚠️'}")
    except:
        pass


def create_patch(source_path, new_sclk, new_mclk=None):
    """Cria pp_table patch com novos clocks."""
    data, path = read_pp_table(source_path)
    data = bytearray(data)
    
    orig_sclk = struct.unpack('<H', data[842:844])[0]
    orig_mclk = struct.unpack('<H', data[926:928])[0]
    
    if new_mclk is None:
        new_mclk = orig_mclk + (new_sclk - orig_sclk) * 2 // 3  # Proportional
    
    # Patches
    patches = [
        (842, orig_sclk, new_sclk, "SCLK max"),
        (1010, orig_sclk, new_sclk, "SCLK copy 1"),
        (1066, orig_sclk, new_sclk, "SCLK copy 2"),
        (926, orig_mclk, new_mclk, "MCLK max"),
        (928, orig_mclk, new_mclk, "MCLK copy"),
    ]
    
    print(f"\n🔧 Creating patch: {orig_sclk}→{new_sclk} MHz SCLK, {orig_mclk}→{new_mclk} MHz MCLK")
    
    for off, ov, nv, desc in patches:
        curr = struct.unpack('<H', data[off:off+2])[0]
        if curr != ov:
            print(f"  ⚠️  {desc}: expected {ov}, got {curr} — SKIP")
            continue
        struct.pack_into('<H', data, off, nv)
        print(f"  ✅ {desc}: {ov} → {nv} MHz")
    
    out_name = f"pp_table_{new_sclk}_{new_mclk}.bin"
    with open(out_name, 'wb') as f:
        f.write(data)
    
    print(f"\n💾 Saved: {out_name} ({len(data)} bytes)")
    return out_name


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    cmd = sys.argv[1]
    
    if cmd == 'info':
        get_gpu_info()
        data, path = read_pp_table("sysfs")
        analyze_pp_table(data, f"[from {path}]")
    
    elif cmd == 'dump':
        data, path = read_pp_table("sysfs")
        out = "pp_table_dump.bin"
        with open(out, 'wb') as f:
            f.write(data)
        print(f"💾 pp_table salva em {out} ({len(data)} bytes)")
    
    elif cmd == 'explore':
        if len(sys.argv) < 3:
            print("Uso: python3 pp_table_explorer.py explore <file.bin>")
            sys.exit(1)
        data, _ = read_pp_table(sys.argv[2])
        analyze_pp_table(data, f"[{sys.argv[2]}]")
    
    elif cmd == 'patch':
        if len(sys.argv) < 4:
            print("Uso: python3 pp_table_explorer.py patch <file.bin> <sclk_mhz> [mclk_mhz]")
            sys.exit(1)
        source = sys.argv[2]
        sclk = int(sys.argv[3])
        mclk = int(sys.argv[4]) if len(sys.argv) > 4 else None
        create_patch(source, sclk, mclk)
    
    elif cmd == 'apply':
        if len(sys.argv) < 3:
            print("Uso: python3 pp_table_explorer.py apply <file.bin>")
            sys.exit(1)
        filepath = sys.argv[2]
        target = find_pp_table_sysfs()
        if not target:
            print("❌ pp_table sysfs não encontrado")
            sys.exit(1)
        with open(filepath, 'rb') as f:
            data = f.read()
        try:
            with open(target, 'wb') as f:
                f.write(data)
            print(f"✅ pp_table aplicada: {filepath} → {target}")
            print(f"   SCLK: {struct.unpack('<H', data[842:844])[0]} MHz")
            print(f"   MCLK: {struct.unpack('<H', data[926:928])[0]} MHz")
        except PermissionError:
            print("❌ Permissão negada. Execute como root: sudo !!")
    
    elif cmd == 'save':
        data, path = read_pp_table("sysfs")
        out = f"pp_table_backup_{struct.unpack('<H', data[842:844])[0]}mhz.bin"
        with open(out, 'wb') as f:
            f.write(data)
        print(f"💾 pp_table salva em {out}")
    
    elif cmd == 'restore':
        if len(sys.argv) < 3:
            print("Uso: python3 pp_table_explorer.py restore <file.bin>")
            sys.exit(1)
        os.system(f'sudo cat {sys.argv[2]} > {find_pp_table_sysfs()}')
        print("✅ pp_table restaurada")
    
    else:
        print(f"❌ Comando desconhecido: {cmd}")
        print(__doc__)


if __name__ == '__main__':
    main()
