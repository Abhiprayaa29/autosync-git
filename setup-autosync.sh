#!/usr/bin/env bash
# Setup sekali jalan:
#   1. cek prasyarat (git, bash, systemd user)
#   2. pastikan auto-sync.sh executable
#   3. install + enable systemd user service
#   4. jalankan auto-sync sekarang juga
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="autosync-git"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME.service"

echo "== Setup AutoSync Git =="
echo "Repo: $REPO_DIR"
echo

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git belum terpasang. Install dulu (Debian/Ubuntu: sudo apt install git)." >&2
  exit 1
fi

if [[ -z "$(git config user.name)" || -z "$(git config user.email)" ]]; then
  echo "ERROR: identitas git belum di-set. Jalankan dulu:" >&2
  echo "  git config --global user.name  \"Nama Kamu\"" >&2
  echo "  git config --global user.email \"email@contoh.com\"" >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "WARNING: systemctl tidak ditemukan (Windows/macOS?)."
  echo "Jalankan manual di terminal terpisah:"
  echo "  bash \"$REPO_DIR/auto-sync.sh\""
  echo "Atau commit/push manual lewat panel Source Control di VS Code."
  exit 0
fi

chmod +x "$REPO_DIR/auto-sync.sh"
mkdir -p "$SERVICE_DIR"

cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=AutoSync Git repo to GitHub
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/bash $REPO_DIR/auto-sync.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME.service"

echo
echo "OK. Status service:"
systemctl --user --no-pager status "$SERVICE_NAME.service" | head -8 || true
echo
echo "Selesai! Buka folder ini di VS Code:"
echo "  code \"$REPO_DIR\""
echo "Setiap simpan file (Ctrl+S) akan otomatis ke-push ke GitHub."
echo "Log: $REPO_DIR/.autosync.log"
