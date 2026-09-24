# AutoSync Git

Toolkit auto-sync Git. Setiap kali file di folder yang dipantau disimpan, perubahan di-commit, di-pull (rebase), dan di-push ke GitHub secara otomatis. Tanpa klik tombol apa pun.

Cocok untuk satu folder yang dikerjakan bareng tim, atau buat kamu yang ingin semua perubahan lokal selalu aman di remote.

## Fitur

- **Auto commit**: perubahan file di-commit tiap 2 detik dengan pesan `auto-sync: <waktu> [nama]`.
- **Auto pull + push**: `git pull --rebase --autostash` lalu `git push`. Jaringan mati tidak menggantung (ada timeout bawaan).
- **Penanganan konflik**: kalau rebase bentrok, rebase otomatis diabort, push ditahan, sinkronisasi jeda 120 detik, dan di Windows muncul notifikasi balloon. Watcher lanjut sendiri setelah kamu menyelesaikan konflik.
- **Mode sekali-jalan**: sync sekali tanpa loop lewat `bash auto-sync.sh once` (Linux) atau `-Once` (PowerShell).
- **Log lengkap**: `.autosync.log` mencatat tiap PUSHED / PULLED / CONFLICT / gagal. Galat di-rate-limit biar tidak spam.
- **`.gitignore` bawaan**: abaikan log runtime auto-sync plus file temp OS dan editor (swap vim, file `~`, lock file emacs).
- **Lintas platform**: satu engine untuk Linux/macOS (`auto-sync.sh`) dan Windows (`auto-sync.ps1`), dengan nama service/task `autosync-git`.

## Struktur file

| File | Fungsi |
|------|--------|
| `auto-sync.sh` | Engine utama Linux/macOS (loop watcher + mode `once`) |
| `auto-sync.ps1` | Engine utama Windows (loop watcher + `-Once`) |
| `setup-autosync.sh` | Setup Linux: pasang systemd user service `autosync-git` |
| `setup-autosync.ps1` / `setup-autosync.bat` | Setup Windows: pasang Scheduled Task `autosync-git` |
| `start-auto-sync.bat` | Jalankan watcher Windows tanpa Scheduled Task |
| `join.sh` | Setup plug & play Linux/macOS (clone repo + setup otomatis) |
| `join.ps1` | Setup plug & play Windows sekali jalan (clone repo + setup otomatis) |
| `join-local.ps1` / `join.bat` | Launcher lokal untuk `join.ps1` (klik dua kali) |
| `check-sync.ps1` | Cek status Scheduled Task + log (Windows) |
| `fix-sync.ps1` | Perbaikan otomatis umum (identitas git, remote, task) |
| `.gitignore` | Ignore log runtime, file temp OS/editor |

## Persyaratan

- Git terpasang, dengan identitas sudah di-set:

  ```
  git config --global user.name  "Nama Kamu"
  git config --global user.email "email@contoh.com"
  ```

- Kredensial push ke GitHub yang bisa dipakai tanpa prompt (SSH key, Personal Access Token, atau Git Credential Manager).
- Linux: systemd user (biasanya sudah ada). Windows: PowerShell (bawaan).

## Instalasi

### Linux

Plug & play dari internet (clone + setup otomatis ke `~/autosync-git`, identitas git diisi otomatis):

```bash
curl -fsSL https://raw.githubusercontent.com/Abhiprayaa29/autosync-git/main/join.sh | bash
```

atau jalankan `bash join.sh` dari folder clone yang sudah ada.

Manual:

```bash
git clone https://github.com/Abhiprayaa29/autosync-git.git
cd autosync-git
bash setup-autosync.sh
```

Service user `autosync-git` langsung aktif. Cek dengan `systemctl --user status autosync-git`.

Tanpa systemd, jalankan manual di terminal terpisah:

```bash
bash auto-sync.sh          # watcher
bash auto-sync.sh once     # sekali jalan
```

### Windows

Otomatis sebagai Scheduled Task (jalan tiap login), pilih salah satu:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-autosync.ps1
```

atau klik dua kali `setup-autosync.bat`.

Sekali jalan tanpa task:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\auto-sync.ps1 -Once
```

atau klik dua kali `start-auto-sync.bat` untuk watcher di terminal.

Plug & play dari internet (clone + setup otomatis ke `Documents`):

```powershell
irm https://raw.githubusercontent.com/Abhiprayaa29/autosync-git/main/join.ps1 | iex
```

atau klik dua kali `join.bat` kalau file itu sudah ada di folder yang sama.

## Mode sekali-jalan

Mode `once` melakukan satu siklus penuh (deteksi perubahan, commit, pull rebase, push) lalu keluar dengan kode 0. Berguna untuk cron/job runner, atau untuk memaksa sync sebelum komputer dimatikan:

```bash
bash auto-sync.sh once
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\auto-sync.ps1 -Once
```

## Perilaku saat konflik git

Saat `git pull --rebase` bentrok:

1. Rebase otomatis diabort, jadi working tree kembali bersih (tidak ada conflict marker yang tersisa).
2. Push ditahan untuk siklus itu, supaya konflik tidak ter-upload ke remote.
3. Log mencatat `CONFLICT` (di-rate-limit) dan watcher jeda 120 detik sebelum mencoba lagi.
4. Di Windows muncul notifikasi balloon; di Linux `notify-send` dipakai kalau tersedia.
5. Kamu menyelesaikan konflik secara manual (`git status`, lalu `git merge`/`git rebase` sendiri atau lewat VS Code), watcher lanjut sendiri.

Kalau ada perubahan `autostash` yang tertahan, log menyarankan menjalankan `git stash pop` manual. Toolkit ini sengaja tidak mem-pop otomatis karena bisa membuat conflict marker di working tree yang lalu ikut ter-commit.

## Pakai di repo lain

Semua file di repo ini generik. Untuk memakainya di repository sendiri:

1. Salin file yang dibutuhkan (`auto-sync.*`, `setup-autosync.*`, `.gitignore`) ke repo kamu, atau clone repo ini ke dalam folder kerja.
2. Arahkan remote ke repo kamu: `git remote set-url origin https://github.com/<OWNER>/<REPO>.git`.
3. Untuk alur plug & play, ganti nilai `$RepoUrl` (di `join.ps1`) atau `REPO_URL` (di `join.sh`) menjadi `https://github.com/<OWNER>/<REPO>.git`.

## Batasan & peringatan

- File tersembunyi (dotfiles) **tidak** di-ignore otomatis. Mengabaikan semua file tersembunyi secara buta berisiko menggigit `.gitignore`, `.github/`, dan file penting lain, jadi polanya dibatasi ke log runtime dan file temp editor/OS saja. Tambahkan pola sendiri di `.gitignore` kalau perlu.
- Satu instance per folder. Watcher Linux memakai lock file, Windows memakai mutex `Local\autosync-git`, jadi dua instance tidak saling tabrakan.
- Kredensial harus non-interaktif. Kalau push butuh input user/prompt, otomatisasi akan gagal cepat dan tercatat di log.
- Selalu baca `.autosync.log` sebelum menganggap sesuatu gagal diam-diam.

## Troubleshooting

- **Linux**: `systemctl --user status autosync-git`, log ada di `.autosync.log` di folder repo.
- **Windows**: `powershell -NoProfile -ExecutionPolicy Bypass -File .\check-sync.ps1` untuk status task dan log.
- **Task/service tidak jalan atau status aneh**: jalankan `fix-sync.ps1` (Windows) atau jalankan ulang `setup-autosync.sh`.
- **Konflik menumpuk**: selesaikan manual dengan `git status`, `git log --oneline -5`, lalu `git add` + `git commit` atau `git rebase --abort`. Watcher otomatis melanjutkan.
- **Log penuh galat PULL/PUSH**: cek dulu jaringan dan kredensial (`git push` manual sekali di folder yang sama).

## Proyek sejenis

Konsep watcher yang commit/pull/push otomatis ini juga dipakai oleh [GitJournal/git-auto-sync](https://github.com/GitJournal/git-auto-sync), CLI berbasis Go dengan mode `sync` sekali jalan dan `daemon` untuk banyak repo. Toolkit ini berdiri sendiri: ditulis untuk Windows dan Linux tanpa dependensi selain Git, dan bisa di-clone ke repo mana pun.
