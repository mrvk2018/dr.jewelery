#!/usr/bin/env python3
"""Live terminal monitor for migration/full_migration_stdout.log."""

from __future__ import annotations

import re
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
LOG_PATH = SCRIPT_DIR / "full_migration_stdout.log"
TOTAL_ESTIMATE = 12_200
PILOT_ALREADY_IMPORTED = 200
POLL_INTERVAL_SEC = 2
BAR_WIDTH = 24

PROGRESS_RE = re.compile(
    r"\[PROGRESS\].*?\bcumulative=(\d+)",
    re.IGNORECASE,
)


def read_log_text() -> str:
    if not LOG_PATH.is_file():
        return ""
    try:
        return LOG_PATH.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def last_cumulative(log_text: str) -> int:
    matches = PROGRESS_RE.findall(log_text)
    if not matches:
        return 0
    return int(matches[-1])


def render_bar(ratio: float) -> str:
    ratio = max(0.0, min(1.0, ratio))
    filled = int(round(BAR_WIDTH * ratio))
    return "[" + ("#" * filled) + ("░" * (BAR_WIDTH - filled)) + "]"


def main() -> None:
    print(f"Монитор: {LOG_PATH}", flush=True)
    print("Ожидание строк [PROGRESS]… (Ctrl+C для выхода)\n", flush=True)

    while True:
        log_text = read_log_text()

        if "Migration finished" in log_text:
            transferred = PILOT_ALREADY_IMPORTED + last_cumulative(log_text)
            bar = render_bar(1.0)
            sys.stdout.write(
                f"\r[МИГРАЦИЯ] Перенесено: {transferred} / ~{TOTAL_ESTIMATE} строк | "
                f"Прогресс: 100% | {bar}   \n"
            )
            sys.stdout.flush()
            print("УСПЕШНО ЗАВЕРШЕНО!", flush=True)
            break

        session_rows = last_cumulative(log_text)
        transferred = PILOT_ALREADY_IMPORTED + session_rows
        ratio = transferred / TOTAL_ESTIMATE if TOTAL_ESTIMATE else 0.0
        percent = int(min(100, ratio * 100))
        bar = render_bar(ratio)

        line = (
            f"[МИГРАЦИЯ] Перенесено: {transferred} / ~{TOTAL_ESTIMATE} строк | "
            f"Прогресс: {percent}% | {bar}"
        )
        sys.stdout.write(f"\r{line}   ")
        sys.stdout.flush()
        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nМонитор остановлен.", flush=True)
