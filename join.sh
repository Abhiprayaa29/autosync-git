#!/usr/bin/env bash
# AutoSync Git - setup plug & play (Linux/macOS).
# Pemakaian:
#   curl -fsSL https://raw.githubusercontent.com/Abhiprayaa29/autosync-git/main/join.sh | bash
#   atau dari clone yang sudah ada: bash join.sh
# CATATAN: saat di-curl|bash skrip dibaca dari stdin (bukan file biasa),
# jadi skrip ini wajib self-contained sampai repo berhasil di-clone ke disk.
set -euo pipefail

# GANTI dengan URL repo kamu kalau toolkit ini dipakai di repo lain.
REPO_URL='https://github.com/Abhiprayaa29/autosync-git.git'
REPO_NAME="${REPO_URL##*/}"
REPO_NAME="${REPO_NAME%.git}"
PARENT_DIR="$HOME"
TARGET_DIR="$PARENT_DIR/$REPO_NAME"

echo "========================================"
echo " AutoSync Git - Setup (Linux/macOS)"
echo "========================================"
echo

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git belum terpasang. Install dulu:" >&2
  echo "  Debian/Ubuntu : sudo apt install git" >&2
  echo "  Fedora        : sudo dnf install git" >&2
  echo "  Arch          : sudo pacman -S git" >&2
  exit 1
fi

# Identitas commit diisi otomatis tanpa prompt (mirror join.ps1).
if [[ -z "$(git config user.name || true)" || -z "$(git config user.email || true)" ]]; then
  NAME=""
  EMAIL=""
  if command -v gh >/dev/null 2>&1; then
    LOGIN="$(gh api user --jq .login 2>/dev/null || true)"
    if [[ -n "$LOGIN" ]]; then
      NAME="$LOGIN"
      EMAIL="$LOGIN@users.noreply.github.com"
    fi
  fi
  if [[ -z "$NAME" ]]; then
    NAME="$(id -un)"
    EMAIL="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')@users.noreply.github.com"
  fi
  git config --global user.name "$NAME"
  git config --global user.email "$EMAIL"
  echo "Identitas commit otomatis: $NAME <$EMAIL>"
  echo
fi

# Saat dipipe, BASH_SOURCE menunjuk ke /dev/fd atau stdin: jalur clone yang dipakai.
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
fi

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/auto-sync.sh" && -e "$SCRIPT_DIR/.git" ]]; then
  TARGET_DIR="$SCRIPT_DIR"
  echo "Clone lokal terdeteksi: $TARGET_DIR"
  echo "Git pull update terbaru..."
  git -C "$TARGET_DIR" pull --rebase --autostash || echo "Pull gagal (offline / conflict?). Lanjut setup dulu."
  echo
elif [[ -e "$TARGET_DIR/.git" ]]; then
  echo "Repo sudah ada di: $TARGET_DIR"
  echo "Git pull update terbaru..."
  git -C "$TARGET_DIR" pull --rebase --autostash || echo "Pull gagal (offline / conflict?). Lanjut setup dulu."
  echo
else
  if [[ -e "$TARGET_DIR" ]]; then
    echo "ERROR: $TARGET_DIR sudah ada tetapi bukan repo git." >&2
    echo "Hapus atau pindahkan folder itu, lalu jalankan ulang." >&2
    exit 1
  fi
  echo "Clone repo ke: $TARGET_DIR"
  if ! git clone "$REPO_URL" "$TARGET_DIR"; then
    echo "ERROR: git gagal clone. Cek koneksi / akses repo." >&2
    exit 1
  fi
  echo
fi

if [[ ! -f "$TARGET_DIR/setup-autosync.sh" ]]; then
  echo "ERROR: setup-autosync.sh tidak ditemukan di $TARGET_DIR" >&2
  exit 1
fi

bash "$TARGET_DIR/setup-autosync.sh"

echo
echo "SELESAI - plug & play."
echo "Folder : $TARGET_DIR"
echo "Log    : $TARGET_DIR/.autosync.log"
if command -v code >/dev/null 2>&1; then
  echo
  echo "Buka folder di VS Code:"
  echo "  code \"$TARGET_DIR\""
fi
