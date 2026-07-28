#!/usr/bin/env python3
"""
pmbus_monitor.py — Monitor PMBus para VRM IR35217 (AMD Radeon Pro VII / MI50)

Escaneia barramentos i2c em busca do regulador de tensão Infineon IR35217
e monitora tensão, corrente e status via protocolo PMBus.

IR35217 é o VRM de memória (VDD_MEM) na Radeon Pro VII / MI50,
tipicamente no endereço 0x40 no barramento SMU (i2c-0).

PMBus Commands:
  0x20 VOUT_MODE    — Formato da leitura de tensão
  0x8B READ_VOUT    — Tensão de saída (16 bits linear)
  0x8C READ_IOUT    — Corrente de saída (16 bits linear)
  0x79 STATUS_WORD  — Status geral (16 bits)
  0x7A STATUS_VOUT  — Status de tensão
  0x7B STATUS_IOUT  — Status de corrente
  0x88 READ_TEMPERATURE_1 — Temperatura do VRM (se disponível)

Uso:
  python3 pmbus_monitor.py --scan              # Escanear todos os barramentos
  python3 pmbus_monitor.py --bus 0 --addr 0x40 # Monitorar dispositivo específico
  python3 pmbus_monitor.py --bus 0 --monitor   # Monitor contínuo (Ctrl+C para sair)
  python3 pmbus_monitor.py --list              # Listar barramentos i2c disponíveis
"""

import argparse
import os
import subprocess
import sys
import time

# Endereços PMBus comuns para VRMs
VRM_ADDRESSES = [0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47]

# PMBus commands
PMBUS_VOUT_MODE = 0x20
PMBUS_READ_VOUT = 0x8B
PMBUS_READ_IOUT = 0x8C
PMBUS_STATUS_WORD = 0x79
PMBUS_STATUS_VOUT = 0x7A
PMBUS_STATUS_IOUT = 0x7B
PMBUS_READ_TEMP1 = 0x88
PMBUS_READ_VIN = 0x88  # pode conflitar, depende do dispositivo
PMBUS_MFR_ID = 0x99
PMBUS_MFR_MODEL = 0x9A
PMBUS_IC_DEVICE_ID = 0xAD
PMBUS_IC_MFR_ID = 0xAE


def check_i2c_tools():
    """Verifica se i2c-tools estão instalados."""
    for cmd in ["i2cdetect", "i2cget", "i2cset"]:
        result = subprocess.run(
            ["command", "-v", cmd], capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"❌ {cmd} não encontrado. Instale i2c-tools:")
            print("   sudo pacman -S i2c-tools  (Arch/CachyOS)")
            print("   sudo apt install i2c-tools (Debian/Ubuntu)")
            return False
    return True


def list_i2c_buses():
    """Lista barramentos i2c disponíveis."""
    i2c_devs = []
    for entry in os.listdir("/dev/"):
        if entry.startswith("i2c-"):
            try:
                num = int(entry.split("-")[1])
                i2c_devs.append(num)
            except ValueError:
                pass
    return sorted(i2c_devs)


def detect_device_on_bus(bus_num, addr):
    """Tenta detectar dispositivo no endereço via i2cdetect."""
    result = subprocess.run(
        ["i2cdetect", "-y", str(bus_num)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) > 0 and parts[0].rstrip(":") in [f"{a:02x}" for a in range(0x00, 0x80, 0x10)]:
            pass
        addr_str = f"{addr:02x}"
        if addr_str in line:
            # Verificar se o endereço aparece (não "XX" que significa sem dispositivo)
            # i2cdetect mostra "--" para vazio, o endereço para presente, "UU" para usado pelo driver
            if addr_str in result.stdout:
                # Verificação mais precisa
                for l in result.stdout.splitlines():
                    cols = l.split()
                    for c in cols:
                        if c == addr_str or c == "UU":
                            return True
    return False


def i2c_get(bus_num, addr, cmd, width="w"):
    """Lê um valor via i2cget."""
    try:
        result = subprocess.run(
            ["i2cget", "-y", str(bus_num), f"{addr:#04x}", f"{cmd:#04x}", width],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None


def parse_pmbus_vout(vout_mode, raw_vout):
    """
    Converte leitura PMBus VOUT para volts.
    VOUT_MODE: byte com bit 7 = 0 indica formato linear,
               bits 6:0 = expoente N em complemento de 2.
    READ_VOUT: 16 bits, valor inteiro * 2^N volts.
    """
    if raw_vout is None or not raw_vout.startswith("0x"):
        return None
    try:
        raw = int(raw_vout, 16)
    except ValueError:
        return None

    if vout_mode is not None:
        try:
            mode_byte = int(vout_mode, 16)
            exp = mode_byte & 0x1F  # lower 5 bits
            if mode_byte & 0x10:  # bit 4 set = expoente negativo
                exp = exp - 32 if exp < 16 else exp - 32
            # Aplicar expoente
            if exp >= 0:
                voltage = raw * (2 ** exp) / 1000.0
            else:
                voltage = raw / (2 ** abs(exp)) / 1000.0
            return voltage
        except (ValueError, TypeError):
            pass

    # Fallback: linear 16 bits com expoente -12 (comum em VRMs)
    voltage = raw * 0.000244  # Aproximação para formato Linear11
    return voltage


def parse_pmbus_iout(raw_iout):
    """Converte leitura PMBus IOUT para amperes."""
    if raw_iout is None or not raw_iout.startswith("0x"):
        return None
    try:
        raw = int(raw_iout, 16)
    except ValueError:
        return None

    # PMBus Linear11: bits 15:11 = expoente (signed 5-bit), bits 10:0 = mantissa (signed 11-bit)
    exp = (raw >> 11) & 0x1F
    if exp & 0x10:  # expoente negativo
        exp = exp - 32
    mant = raw & 0x7FF
    if mant & 0x400:  # mantissa negativa
        mant = mant - 2048

    current = mant * (2 ** exp)
    return current


def parse_status_word(raw_status):
    """Interpreta STATUS_WORD PMBus."""
    if raw_status is None or not raw_status.startswith("0x"):
        return {}
    try:
        val = int(raw_status, 16)
    except ValueError:
        return {}

    flags = {
        "VOUT_OV": bool(val & 0x8000),     # Tensão acima do limite
        "VOUT_UV": bool(val & 0x4000),     # Tensão abaixo do limite
        "IOUT_OC": bool(val & 0x2000),     # Corrente acima do limite
        "VIN_OV": bool(val & 0x1000),       # Tensão de entrada alta
        "TEMPERATURE": bool(val & 0x0400),  # Alarme de temperatura
        "CML": bool(val & 0x0200),          # Erro de comunicação
        "MFR": bool(val & 0x0100),          # Erro do fabricante
        "VOUT": bool(val & 0x0080),         # Alarme VOUT
        "IOUT": bool(val & 0x0040),         # Alarme IOUT
        "POWER_GOOD": not bool(val & 0x0008), # Power good (invertido)
        "BUSY": bool(val & 0x0004),         # Ocupado
        "OFF": bool(val & 0x0002),          # Desligado
    }
    return flags


def read_device_info(bus_num, addr):
    """Tenta ler informações do fabricante do dispositivo PMBus."""
    info = {}
    mfr_id = i2c_get(bus_num, addr, PMBUS_MFR_ID, "b")
    mfr_model = i2c_get(bus_num, addr, PMBUS_MFR_MODEL, "b")
    dev_id = i2c_get(bus_num, addr, PMBUS_IC_DEVICE_ID, "b")
    mfr = i2c_get(bus_num, addr, PMBUS_IC_MFR_ID, "b")

    if mfr_id:
        try:
            info["MFR_ID"] = bytes.fromhex(mfr_id[2:]).decode("ascii", errors="replace")
        except Exception:
            info["MFR_ID"] = mfr_id

    if mfr_model:
        try:
            info["MFR_MODEL"] = bytes.fromhex(mfr_model[2:]).decode("ascii", errors="replace")
        except Exception:
            info["MFR_MODEL"] = mfr_model

    if dev_id:
        info["DEVICE_ID"] = dev_id
    if mfr:
        info["MFR"] = mfr

    return info


def scan_all_buses():
    """Escaneia todos os barramentos i2c por dispositivos PMBus."""
    print("=" * 60)
    print("PMBus Device Scan")
    print("=" * 60)

    buses = list_i2c_buses()
    if not buses:
        print("❌ Nenhum barramento i2c encontrado.")
        print("   Carregue módulos: sudo modprobe i2c-dev")
        return

    print(f"  Barramentos encontrados: {buses}")

    for bus in buses:
        # Identificar o barramento
        bus_name = f"i2c-{bus}"
        try:
            with open(f"/sys/class/i2c-adapter/{bus_name}/name") as f:
                name = f.read().strip()
        except Exception:
            name = "?"

        print(f"\n  Bus {bus}: {name}")

        for addr in VRM_ADDRESSES:
            # i2cdetect para verificar presença
            result = subprocess.run(
                ["i2cdetect", "-y", str(bus), f"{addr:#04x}", f"{addr:#04x}"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            detected = False
            for line in result.stdout.splitlines():
                if f"{addr:02x}" in line or "UU" in line:
                    detected = True

            if detected:
                print(f"    {addr:#04x}: Dispositivo detectado!")
                info = read_device_info(bus, addr)
                for k, v in info.items():
                    print(f"      {k}: {v}")

                # Tentar ler VOUT
                vout_mode = i2c_get(bus, addr, PMBUS_VOUT_MODE, "b")
                raw_vout = i2c_get(bus, addr, PMBUS_READ_VOUT, "w")
                vout = parse_pmbus_vout(vout_mode, raw_vout)
                if vout is not None:
                    print(f"      VOUT: {vout:.4f} V")

                iout = i2c_get(bus, addr, PMBUS_READ_IOUT, "w")
                current = parse_pmbus_iout(iout)
                if current is not None:
                    print(f"      IOUT: {current:.2f} A")

                status = i2c_get(bus, addr, PMBUS_STATUS_WORD, "w")
                flags = parse_status_word(status)
                if flags:
                    alarms = [k for k, v in flags.items() if v]
                    if alarms:
                        print(f"      ALARMS: {', '.join(alarms)}")
            else:
                print(f"    {addr:#04x}: vazio")


def monitor_device(bus_num, addr, interval=2):
    """Monitora um dispositivo PMBus continuamente."""
    print(f"📊 Monitorando PMBus i2c-{bus_num} @ {addr:#04x}")
    print(f"   Ctrl+C para parar\n")
    print(f"{'Tempo':>8} {'VOUT (V)':>10} {'IOUT (A)':>10} {'Status':>20}")
    print("-" * 50)

    start = time.time()
    try:
        while True:
            elapsed = int(time.time() - start)
            vout_mode = i2c_get(bus_num, addr, PMBUS_VOUT_MODE, "b")
            raw_vout = i2c_get(bus_num, addr, PMBUS_READ_VOUT, "w")
            vout = parse_pmbus_vout(vout_mode, raw_vout)
            raw_iout = i2c_get(bus_num, addr, PMBUS_READ_IOUT, "w")
            iout = parse_pmbus_iout(raw_iout)
            status = i2c_get(bus_num, addr, PMBUS_STATUS_WORD, "w")
            flags = parse_status_word(status)
            alarms = [k for k, v in flags.items() if v] if flags else []

            vout_str = f"{vout:.4f}" if vout is not None else "N/A"
            iout_str = f"{iout:.2f}" if iout is not None else "N/A"
            alarm_str = "OK" if not alarms else "⚠️ " + ",".join(alarms[:3])

            print(f"{elapsed:>6}s {vout_str:>10} {iout_str:>10} {alarm_str:>20}")
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\n✅ Monitoramento encerrado.")


def main():
    parser = argparse.ArgumentParser(
        description="PMBus Monitor para VRM IR35217 (Radeon Pro VII / MI50)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument("--list", action="store_true", help="Listar barramentos i2c")
    parser.add_argument("--scan", action="store_true", help="Escanear todos os barramentos por VRMs")
    parser.add_argument("--bus", type=int, default=0, help="Número do barramento i2c (default: 0)")
    parser.add_argument("--addr", type=lambda x: int(x, 16), default=0x40,
                        help="Endereço i2c do VRM em hex (default: 0x40)")
    parser.add_argument("--monitor", action="store_true",
                        help="Monitor contínuo (requer --bus e --addr)")
    parser.add_argument("--interval", type=float, default=2.0,
                        help="Intervalo de monitoramento em segundos (default: 2)")

    args = parser.parse_args()

    if not check_i2c_tools():
        sys.exit(1)

    # Verificar acesso aos barramentos
    buses = list_i2c_buses()
    if not buses:
        print("⚠️  Nenhum barramento i2c encontrado.")
        print("   Execute: sudo modprobe i2c-dev")

    if args.list:
        print("Barramentos i2c disponíveis:")
        for bus in buses:
            try:
                with open(f"/sys/class/i2c-adapter/{bus}/name") as f:
                    name = f.read().strip()
            except Exception:
                name = "?"
            print(f"  i2c-{bus}: {name}")
        sys.exit(0)

    if args.scan:
        scan_all_buses()
        sys.exit(0)

    if args.monitor:
        monitor_device(args.bus, args.addr, args.interval)
        sys.exit(0)

    # Modo single-shot
    print(f"Lendo PMBus i2c-{args.bus} @ {args.addr:#04x}")
    vout_mode = i2c_get(args.bus, args.addr, PMBUS_VOUT_MODE, "b")
    raw_vout = i2c_get(args.bus, args.addr, PMBUS_READ_VOUT, "w")
    vout = parse_pmbus_vout(vout_mode, raw_vout)
    raw_iout = i2c_get(args.bus, args.addr, PMBUS_READ_IOUT, "w")
    iout = parse_pmbus_iout(raw_iout)
    status = i2c_get(args.bus, args.addr, PMBUS_STATUS_WORD, "w")
    flags = parse_status_word(status)

    print(f"  VOUT_MODE: {vout_mode or 'N/A'}")
    print(f"  READ_VOUT: {raw_vout or 'N/A'}")
    if vout is not None:
        print(f"  Tensão: {vout:.4f} V")
    if iout is not None:
        print(f"  Corrente: {iout:.2f} A")
    if flags:
        alarms = [k for k, v in flags.items() if v]
        if alarms:
            print(f"  Alarmes: {', '.join(alarms)}")
        else:
            print("  Status: OK (sem alarmes)")
    else:
        print(f"  STATUS_WORD: {status or 'N/A'} - Dispositivo não respondeu")


if __name__ == "__main__":
    main()
