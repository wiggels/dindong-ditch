# dingdong-ditch 🔕🚪

Silence Zoom's "ding dong" doorbell chime on macOS and Windows — or replace it
with a fart, or the classic AIM buddy-in sound.

Zoom plays `dingdong.pcm` / `dingdong1.pcm` (SILK v3 streams, despite the
extension) when someone enters the waiting room or joins a meeting. This tool
backs those files up and overwrites them with a replacement encoded through the
real SILK codec, so Zoom plays it natively. On macOS both system-wide
(`/Applications`) and per-user (`~/Applications`) installs are detected; on
Windows it patches `%APPDATA%\Zoom\bin`.

## Install

macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/wiggels/dingdong-ditch/main/install.sh | sudo bash
```

The installer drops the right binary for your CPU into `/usr/local/bin`, adds a
sudoers rule so the tool never asks for a password (scoped to this binary
only), and adds a shell alias so a bare `dingdong-ditch` just works.

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/wiggels/dingdong-ditch/main/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Programs\dingdong-ditch` and adds it to your user
PATH. No admin needed — Zoom's sounds live in your own `%APPDATA%`.

## Use

```sh
dingdong-ditch            # silence the doorbell
dingdong-ditch --fart     # make it fart
dingdong-ditch --aim      # party like it's 1999
dingdong-ditch --restore  # bring back the dingdong
dingdong-ditch --fart --preview fart.wav   # hear it before you commit
```

Zoom app updates reinstall the original sounds — just run the tool again.
See `dingdong-ditch --help` for everything else.

### "permission denied" even with sudo?

macOS 13+ blocks modifying other apps' bundles (App Management protection),
even as root. Grant your terminal app the permission and re-run:

**System Settings → Privacy & Security → App Management** → enable your
terminal (Terminal, iTerm2, etc.). Shortcut:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
```

## Uninstall

macOS:

```sh
dingdong-ditch --restore
sudo rm /usr/local/bin/dingdong-ditch /etc/sudoers.d/dingdong-ditch
```

Then remove the `dingdong-ditch` block from your shell profile.

Windows (PowerShell):

```powershell
dingdong-ditch --restore
Remove-Item -Recurse "$env:LOCALAPPDATA\Programs\dingdong-ditch"
```

Then remove that directory from your user PATH.

## Development

```sh
cargo build --release
./target/release/dingdong-ditch --dir /path/to/test/copies --fart
```

Every push to `main` cuts a GitHub release: the version is bumped
automatically from commit messages (conventional commits; defaults to a patch
bump), binaries are built for Apple Silicon, Intel mac, and Windows x64, and
archives plus checksums are attached to the release.
