#!/usr/bin/env bash
#
# dingdong-ditch installer
#
#   curl -fsSL https://raw.githubusercontent.com/wiggels/dingdong-ditch/main/install.sh | sudo bash
#
# What it does:
#   1. Downloads the latest release binary for your CPU (Intel or Apple Silicon)
#      and installs it to /usr/local/bin (checksum-verified).
#   2. Adds a sudoers rule so `sudo dingdong-ditch` never asks for a password
#      (scoped to this one binary only).
#   3. Adds an alias to your shell profile so plain `dingdong-ditch` just works.
#
# Uninstall:
#   sudo rm /usr/local/bin/dingdong-ditch /etc/sudoers.d/dingdong-ditch
#   then remove the "dingdong-ditch" block from your shell profile.

set -euo pipefail

REPO="${DINGDONG_REPO:-wiggels/dingdong-ditch}"
INSTALL_DIR="/usr/local/bin"
BIN="dingdong-ditch"
SUDOERS_FILE="/etc/sudoers.d/dingdong-ditch"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "this tool only supports macOS (it edits Zoom.app's sound files)"
[ "$(id -u)" -eq 0 ] || die "run me with sudo: curl -fsSL .../install.sh | sudo bash"

case "$(uname -m)" in
  arm64)  target="aarch64-apple-darwin" ;;
  x86_64) target="x86_64-apple-darwin" ;;
  *)      die "unsupported architecture: $(uname -m)" ;;
esac

# Resolve the invoking (pre-sudo) user for their shell profile and their
# per-user ~/Applications, since $HOME points at root's home under sudo.
user_home=""
user_shell=""
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  user_home="$(dscl . -read "/Users/${SUDO_USER}" NFSHomeDirectory | awk '{print $2}')"
  user_shell="$(dscl . -read "/Users/${SUDO_USER}" UserShell | awk '{print $2}')"
fi

log "Finding latest release of ${REPO}..."
tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep -m1 '"tag_name"' | cut -d'"' -f4)"
[ -n "$tag" ] || die "could not determine the latest release tag"
version="${tag#v}"
log "Latest release: ${tag}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

asset="dingdong-ditch-${version}-${target}.tar.gz"
base="https://github.com/${REPO}/releases/download/${tag}"

log "Downloading ${asset}..."
curl -fsSL -o "${tmp}/${asset}" "${base}/${asset}"
curl -fsSL -o "${tmp}/SHA256SUMS" "${base}/SHA256SUMS"

log "Verifying checksum..."
(cd "$tmp" && grep " ${asset}\$" SHA256SUMS | shasum -a 256 -c -) \
  || die "checksum verification failed"

log "Installing to ${INSTALL_DIR}/${BIN}..."
tar -xzf "${tmp}/${asset}" -C "$tmp"
mkdir -p "$INSTALL_DIR"
install -m 755 -o root -g wheel "${tmp}/${BIN}" "${INSTALL_DIR}/${BIN}"

log "Allowing passwordless sudo for ${BIN} (admins only)..."
echo "%admin ALL=(root) NOPASSWD: ${INSTALL_DIR}/${BIN}" > "${tmp}/sudoers"
visudo -cf "${tmp}/sudoers" >/dev/null || die "generated sudoers rule failed validation"
install -m 440 -o root -g wheel "${tmp}/sudoers" "$SUDOERS_FILE"

# Add an alias to the invoking user's shell profile so a bare `dingdong-ditch`
# runs through sudo (which the rule above makes passwordless).
alias_line="alias ${BIN}='sudo ${INSTALL_DIR}/${BIN}'"
if [ -n "$user_home" ]; then
  case "$user_shell" in
    */zsh)  profile="${user_home}/.zshrc" ;;
    */bash) profile="${user_home}/.bash_profile" ;;
    *)      profile="${user_home}/.profile" ;;
  esac
  if [ -f "$profile" ] && grep -qF "$alias_line" "$profile"; then
    log "Alias already present in ${profile}"
  else
    log "Adding alias to ${profile}..."
    printf '\n# dingdong-ditch (https://github.com/%s)\n%s\n' "$REPO" "$alias_line" >> "$profile"
    chown "$SUDO_USER" "$profile"
  fi
else
  log "Could not determine the invoking user; add this to your shell profile yourself:"
  log "  ${alias_line}"
fi

# macOS gates writes inside other apps' bundles behind App Management (TCC),
# even for root. Probe by creating a scratch file inside each Zoom install
# (system-wide and per-user): on a fresh machine this makes macOS show the
# permission dialog right now; if it's already been denied, open the settings
# pane so the user can flip it on.
found_zoom=0
blocked=0
for zoom_res in "/Applications/zoom.us.app/Contents/Resources" \
                "${user_home:+${user_home}/Applications/zoom.us.app/Contents/Resources}"; do
  [ -n "$zoom_res" ] && [ -d "$zoom_res" ] || continue
  found_zoom=1
  log "Checking macOS App Management permission for ${zoom_res}..."
  probe="${zoom_res}/.dingdong-ditch-probe"
  if touch "$probe" 2>/dev/null; then
    rm -f "$probe"
    log "App Management permission is good to go."
  else
    blocked=1
  fi
done
if [ "$found_zoom" -eq 0 ]; then
  log "Zoom doesn't appear to be installed; skipping permission check."
elif [ "$blocked" -eq 1 ]; then
  log "macOS is blocking changes to Zoom.app (App Management protection)."
  log "If a permission dialog just popped up, approve it. Otherwise enable"
  log "your terminal app in the settings pane that's opening now, then quit"
  log "and reopen your terminal."
  pane="x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    sudo -u "$SUDO_USER" open "$pane" || true
  else
    open "$pane" || true
  fi
fi

echo
log "Done! Open a new terminal (or 'source' your profile), then:"
echo "      dingdong-ditch           # silence Zoom's doorbell"
echo "      dingdong-ditch --fart    # make it fart"
echo "      dingdong-ditch --aim     # party like it's 1999"
echo "      dingdong-ditch --restore # bring the dingdong back"
