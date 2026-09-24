#!/usr/bin/env bash
# Auto-commit + auto-push + auto-pull setiap ada perubahan di folder ini.
# Dijalankan oleh systemd user service: autosync-git.service
#
# Pemakaian:
#   bash auto-sync.sh        # mode watcher (loop tiap 2 detik)
#   bash auto-sync.sh once   # mode sekali-jalan (commit/pull/push sekali, lalu keluar)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="$REPO_DIR/.autosync.lock"
LOG_FILE="$REPO_DIR/.autosync.log"
INTERVAL_SEC=2
SETTLE_SEC=1
# Batas waktu git network ops supaya watcher tidak menggantung (pull/push macet menit-menit).
GIT_TIMEOUT_SEC=30
# Setelah konflik rebase: jeda dulu biar tidak spam abort + notifikasi tiap 2 detik.
CONFLICT_COOLDOWN_SEC=120

# Rate-limit log galat: hanya saat pesan berubah atau tiap ~30 kegagalan.
LAST_PULL_ERR=""
LAST_PUSH_ERR=""
PULL_FAIL_N=0
PUSH_FAIL_N=0
# Penanda rentetan konflik: 0 = tidak sedang konflik.
CONFLICT_STREAK=0
CONFLICT_HAS_STASH=0

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE"
}

log_fail() {
  # $1=kind $2=err $3=last_msg_var $4=counter_var - update variabel global via eval.
  local kind="$1" err="$2" last_name="$3" count_name="$4"
  local n short prev cur
  cur="${!count_name}"
  n=$((cur + 1))
  short="$(printf '%s' "$err" | head -n 3 | tr '\n' '|' | cut -c1-400)"
  [[ -z "$short" ]] && short="galat tidak diketahui"
  prev="${!last_name}"
  if [[ "$n" -eq 1 || "$short" != "$prev" || $((n % 30)) -eq 0 ]]; then
    log "$kind FAIL (x$n): $short"
    eval "$last_name=\$short"
  fi
  eval "$count_name=\$n"
}

notify_conflict() {
  # Notifikasi desktop best-effort (Linux). Abaikan kalau tidak ada display/daemon.
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "AutoSync Git" \
      "Konflik git di $REPO_DIR - rebase diabort, sinkronisasi dijeda ${CONFLICT_COOLDOWN_SEC}s. Selesaikan konflik manual (git pull / buka di VS Code), lalu watcher lanjut sendiri." \
      >/dev/null 2>&1 || true
  fi
}

handle_rebase_conflict() {
  # $1 = output git pull yang gagal.
  # return 0 = ini konflik rebase (sudah diabort); return 1 = galat lain (offline/auth/dst).
  local err="$1"
  local git_dir in_rebase=0
  git_dir="$(git rev-parse --git-dir 2>/dev/null || echo .git)"
  [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]] && in_rebase=1
  if [[ "$in_rebase" -eq 0 && "$err" != *"CONFLICT"* && "$err" != *"could not be applied"* ]]; then
    return 1
  fi
  if [[ "$in_rebase" -eq 1 ]]; then
    git rebase --abort >/dev/null 2>&1 || true
  fi
  # Autostash dari --autostash: JANGAN pop otomatis (bisa membuat conflict marker
  # di working tree). Tandai saja, user pop manual via 'git stash pop'.
  CONFLICT_HAS_STASH=0
  if git stash list 2>/dev/null | grep -q 'autostash'; then
    CONFLICT_HAS_STASH=1
  fi
  return 0
}

sync_once() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    return 0
  fi

  cd "$REPO_DIR" || return 1

  local dirty=0
  local changed=""
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    sleep "$SETTLE_SEC"
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
      dirty=1
      changed="$(git status --porcelain | head -20 | tr '\n' '; ')"
      git add -A || true
      git commit -m "auto-sync: $(date '+%Y-%m-%d %H:%M:%S') [$(git config user.name || echo unknown)]" >/dev/null 2>&1 || true
    fi
  fi

  local before after push_ok=1 pull_err="" push_err=""
  before="$(git rev-parse HEAD 2>/dev/null || true)"

  # Retry sekali untuk race transient "Cannot rebase onto multiple branches"
  # (bisa terjadi bila ada git pull paralel dari luar flock, mis. manual/VS Code).
  pull_ok=0
  if pull_err="$(timeout "$GIT_TIMEOUT_SEC" git pull --rebase --autostash 2>&1)"; then
    pull_ok=1
  elif [[ "$pull_err" == *"Cannot rebase onto multiple branches"* ]]; then
    sleep 1
    if pull_err="$(timeout "$GIT_TIMEOUT_SEC" git pull --rebase --autostash 2>&1)"; then
      pull_ok=1
    fi
  fi
  if [[ "$pull_ok" -eq 1 ]]; then
    PULL_FAIL_N=0
    LAST_PULL_ERR=""
    CONFLICT_STREAK=0
  elif handle_rebase_conflict "$pull_err"; then
    # Konflik rebase: rebase sudah diabort. Tahan push dulu (biar konflik
    # tidak ikut ter-upload ke remote), jeda panjang, notifikasi rate-limited.
    CONFLICT_STREAK=$((CONFLICT_STREAK + 1))
    if [[ "$CONFLICT_STREAK" -eq 1 || $((CONFLICT_STREAK % 30)) -eq 0 ]]; then
      log "CONFLICT (x$CONFLICT_STREAK): rebase diabort - sinkronisasi dijeda ${CONFLICT_COOLDOWN_SEC}s"
      if [[ "$CONFLICT_HAS_STASH" -eq 1 ]]; then
        log "CONFLICT: ada perubahan autostash - jalankan 'git stash pop' manual"
      fi
    fi
    if [[ "$CONFLICT_STREAK" -eq 1 ]]; then
      notify_conflict
    fi
    if [[ "$dirty" -eq 1 ]]; then
      log "COMMIT_OK_KONFLIK: $changed"
    fi
    flock -u 9
    return 0
  else
    CONFLICT_STREAK=0
    log_fail PULL "$pull_err" LAST_PULL_ERR PULL_FAIL_N
  fi

  if ! push_err="$(timeout "$GIT_TIMEOUT_SEC" git push 2>&1)"; then
    push_ok=0
    log_fail PUSH "$push_err" LAST_PUSH_ERR PUSH_FAIL_N
  else
    PUSH_FAIL_N=0
    LAST_PUSH_ERR=""
  fi

  after="$(git rev-parse HEAD 2>/dev/null || true)"

  if [[ "$dirty" -eq 1 ]]; then
    if [[ "$push_ok" -eq 1 ]]; then
      log "PUSHED: $changed"
    else
      log "COMMIT_OK_PUSH_FAIL: $changed"
    fi
  elif [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
    log "PULLED: update dari GitHub"
  fi

  flock -u 9
}

if [[ "${1:-}" == "once" ]]; then
  sync_once
  exit 0
fi

log "watcher started (pid $$)"

while true; do
  sync_once
  if [[ "$CONFLICT_STREAK" -gt 0 ]]; then
    sleep "$CONFLICT_COOLDOWN_SEC"
  else
    sleep "$INTERVAL_SEC"
  fi
done
