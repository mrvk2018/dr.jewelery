#!/usr/bin/env python3
"""Pair Android 11+ over Wi‑Fi: QR in terminal + mDNS + adb pair/connect."""

from __future__ import annotations

import re
import secrets
import socket
import string
import subprocess
import sys
import threading
import time

import qrcode
from zeroconf import ServiceBrowser, ServiceStateChange, Zeroconf

ADB = r"C:\Android\platform-tools\adb.exe"
PAIRING_TYPE = "_adb-tls-pairing._tcp.local."
CONNECT_TYPE = "_adb-tls-connect._tcp.local."
TIMEOUT_SEC = 120


def _rand_alnum(n: int) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(n))


def _print_qr(payload: str) -> None:
    qr = qrcode.QRCode(border=1)
    qr.add_data(payload)
    try:
        qr.print_ascii(invert=True)
    except UnicodeEncodeError:
        # Windows cp949 terminals: fallback UTF-8 re-encode
        import io

        buf = io.StringIO()
        qr.print_ascii(out=buf, invert=True)
        sys.stdout.buffer.write(buf.getvalue().encode("utf-8", errors="replace"))
        sys.stdout.buffer.write(b"\n")


def _run_adb(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [ADB, *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def _ipv4_from_info(info) -> str | None:
    for addr in info.addresses:
        if len(addr) == 4:
            return socket.inet_ntoa(addr)
    return None


def main() -> int:
    service_name = f"studio-{_rand_alnum(10)}"
    password = _rand_alnum(8)
    qr_payload = f"WIFI:T:ADB;S:{service_name};P:{password};;"

    print("=== ADB Wi‑Fi pairing (Galaxy S21) ===")
    print("1) Телефон: Настройки → Для разработчиков → Беспроводная отладка")
    print("2) «Сопряжение устройства с QR‑кодом» (не обычная камера!)")
    print("3) Наведите камеру на QR ниже\n")
    print(f"Service (S): {service_name}")
    print(f"Password (P): {password}\n")

    _print_qr(qr_payload)

    paired_event = threading.Event()
    paired_endpoint: list[str] = []
    connect_event = threading.Event()
    connect_endpoint: list[str] = []

    def on_pairing_change(
        zeroconf: Zeroconf,
        service_type: str,
        name: str,
        state_change: ServiceStateChange,
    ) -> None:
        if state_change is not ServiceStateChange.Added:
            return
        if service_name not in name:
            return
        info = zeroconf.get_service_info(service_type, name)
        if not info:
            return
        host = _ipv4_from_info(info)
        if not host:
            return
        endpoint = f"{host}:{info.port}"
        print(f"\n[mDNS] Pairing service: {name} → {endpoint}")
        result = _run_adb(["pair", endpoint, password])
        print(result.stdout.strip())
        if result.stderr.strip():
            print(result.stderr.strip())
        if result.returncode == 0:
            paired_endpoint.append(endpoint)
            paired_event.set()

    def on_connect_change(
        zeroconf: Zeroconf,
        service_type: str,
        name: str,
        state_change: ServiceStateChange,
    ) -> None:
        if state_change is not ServiceStateChange.Added:
            return
        info = zeroconf.get_service_info(service_type, name)
        if not info:
            return
        host = _ipv4_from_info(info)
        if not host:
            return
        endpoint = f"{host}:{info.port}"
        print(f"\n[mDNS] Connect service: {name} → {endpoint}")
        result = _run_adb(["connect", endpoint])
        print(result.stdout.strip())
        if result.stderr.strip():
            print(result.stderr.strip())
        if result.returncode == 0 and "connected" in (result.stdout + result.stderr).lower():
            connect_endpoint.append(endpoint)
            connect_event.set()

    zc = Zeroconf()
    ServiceBrowser(zc, PAIRING_TYPE, handlers=[on_pairing_change])
    ServiceBrowser(zc, CONNECT_TYPE, handlers=[on_connect_change])

    deadline = time.time() + TIMEOUT_SEC
    print(f"\nОжидание сканирования QR (до {TIMEOUT_SEC} с)…")
    while time.time() < deadline:
        if connect_event.is_set():
            break
        if paired_event.is_set():
            # After pair, wait briefly for connect service
            time.sleep(2)
        time.sleep(0.5)

    zc.close()

    print("\n--- adb devices -l ---")
    devices = _run_adb(["devices", "-l"])
    print(devices.stdout.strip())
    if devices.stderr.strip():
        print(devices.stderr.strip())

    if connect_endpoint:
        print(f"\nOK: подключено к {connect_endpoint[0]}")
        return 0
    if paired_endpoint:
        print(f"\nСопряжение OK ({paired_endpoint[0]}), connect не подтверждён — проверьте «Беспроводная отладка» на телефоне (IP:порт) и: adb connect IP:PORT")
        return 0
    print("\nТаймаут: QR не отсканирован или телефон не в той Wi‑Fi сети.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
