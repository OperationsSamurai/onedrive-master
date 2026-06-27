#!/usr/bin/env bash
# OneDrive Recovery Foundation
# Version: 2026.06.26-origin-rebuild
# Co-authored by Microsoft 365 Copilot - Derek's Subscription

set -Eeuo pipefail

BASE="$HOME/onedrive_snapshot"
CONFIG="$HOME/.config/onedrive/config"

echo "[1] Creating snapshot directory..."
mkdir -p "$BASE"

echo "[2] Backing up OneDrive config..."
if [[ -d "$HOME/.config/onedrive" ]]; then
  rm -rf "$BASE/config"
  cp -a "$HOME/.config/onedrive" "$BASE/config"
else
  echo "WARN: ~/.config/onedrive not found"
fi

echo "[3] Backing up OneDrive local data state if present..."
if [[ -d "$HOME/.local/share/onedrive" ]]; then
  rm -rf "$BASE/data"
  cp -a "$HOME/.local/share/onedrive" "$BASE/data"
else
  echo "WARN: ~/.local/share/onedrive not found"
fi

echo "[4] Capturing OneDrive display config..."
if command -v onedrive >/dev/null 2>&1; then
  onedrive --display-config > "$BASE/display_config.txt" 2>&1 || true
else
  echo "onedrive command not found" > "$BASE/display_config.txt"
fi

echo "[5] Capturing service status..."
systemctl --user status onedrive > "$BASE/service_status.txt" 2>&1 || true

echo "[6] Ensuring config exists..."
mkdir -p "$HOME/.config/onedrive"
touch "$CONFIG"

echo "[7] Normalizing config baseline..."
python3 - "$CONFIG" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
txt = p.read_text(errors="ignore") if p.exists() else ""

updates = {
    "sync_dir": "~/OneDrive",
    "enable_logging": "true",
    "log_dir": "~/.local/share/onedrive/logs",
    "disable_notifications": "true",
    "force_http_11": "true",
    "monitor_interval": "300",
    "monitor_log_frequency": "12",
    "monitor_fullscan_frequency": "12",
    "skip_dir": "Pictures|Videos|Temp",
    "skip_file": "~*|.~*|*.tmp|*.bak|*.swp|*.partial",
    "sync_dir_permissions": "700",
    "sync_file_permissions": "600",
    "space_reservation": "52428800"
}

out = []
seen = set()

for line in txt.splitlines():
    s = line.strip()
    if "=" in s and not s.startswith("#"):
        key = s.split("=", 1)[0].strip()
        if key in updates:
            out.append(f'{key} = "{updates[key]}"')
            seen.add(key)
            continue
    out.append(line)

for key, value in updates.items():
    if key not in seen:
        out.append(f'{key} = "{value}"')

p.write_text("\n".join(out) + "\n")
p.chmod(0o600)
PY

echo "[8] Creating log directory..."
mkdir -p "$HOME/.local/share/onedrive/logs"

echo "[9] Running required resync with supported v2.5 syntax..."
if command -v onedrive >/dev/null 2>&1; then
  onedrive --sync --resync || true
else
  echo "WARN: onedrive command not found; resync skipped"
fi

echo "[10] Ensuring systemd user service is enabled and active..."
systemctl --user daemon-reload || true
systemctl --user reset-failed onedrive || true
systemctl --user enable onedrive || true
systemctl --user restart onedrive || true

echo
echo "COMPLETE"
echo "Snapshot: $BASE"
echo "Co-authored by Microsoft 365 Copilot - Derek's Subscription"
