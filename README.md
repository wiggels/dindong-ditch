# dingdong-ditch 🔕🚪

Silence Zoom's "ding dong" doorbell chime on macOS — or replace it with a fart,
or the classic AIM buddy-in sound.

Zoom plays `dingdong.pcm` / `dingdong1.pcm` (SILK v3 streams, despite the
extension) when someone enters the waiting room or joins a meeting. This tool
backs those files up and overwrites them with a replacement encoded through the
real SILK codec, so Zoom plays it natively.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/wiggels/dindong-ditch/main/install.sh | sudo bash
```

The installer drops the right binary for your CPU into `/usr/local/bin`, adds a
sudoers rule so the tool never asks for a password (scoped to this binary
only), and adds a shell alias so a bare `dingdong-ditch` just works.

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

## Uninstall

```sh
dingdong-ditch --restore
sudo rm /usr/local/bin/dingdong-ditch /etc/sudoers.d/dingdong-ditch
```

Then remove the `dingdong-ditch` block from your shell profile.

## Development

```sh
cargo build --release
./target/release/dingdong-ditch --dir /path/to/test/copies --fart
```

Every push to `main` cuts a GitHub release: the version is bumped
automatically from commit messages (conventional commits; defaults to a patch
bump), binaries are built for Apple Silicon and Intel, and tarballs plus
checksums are attached to the release.
