#!/usr/bin/env bash
# Remote Control installer for Linux (Arch gets a pacman package).
#   curl -fsSL https://brizzad.github.io/remote-control-site/install.sh | bash
# Run it as your normal desktop user, inside your graphical session.
# Running it again upgrades the agent and keeps this computer's ID and account.
set -euo pipefail

REPO="${RC_RELEASE_URL:-https://github.com/brizzad/remote-control-site/releases/latest/download}"
APP="https://brizzad.github.io/remote-control-site/app/"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Linux ] || die "this installer is for Linux; on Windows use install.ps1"
[ "$(uname -m)" = x86_64 ] || die "only x86_64 builds are available right now"
[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root (it uses sudo where needed)"
for c in curl sha256sum; do command -v "$c" >/dev/null || die "$c is required"; done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Downloads a release file and checks it against the release's SHA256SUMS.
fetch() {
  curl -fL --progress-bar -o "$tmp/$1" "$REPO/$1" || die "could not download $1 from $REPO (is there a release yet?)"
  (cd "$tmp" && grep -E "^[0-9a-f]{64}  $1\$" SHA256SUMS > "$1.sum") || die "$1 is not listed in the release checksums"
  (cd "$tmp" && sha256sum -c --quiet "$1.sum") || die "$1 failed its checksum; not installing it"
}
# Runs a downloaded rcagent once; explains the usual reasons it cannot start.
check_runs() {
  local out
  if out="$("$1" --version 2>&1)"; then echo "$out"; return 0; fi
  case "$out" in
    *libpipewire*) die "rcagent needs PipeWire's library (libpipewire-0.3): install pipewire (e.g. sudo apt install libpipewire-0.3-0t64, or sudo dnf install pipewire-libs) and run this again" ;;
    *GLIBC_*) die "this Linux is too old for the prebuilt rcagent (it needs glibc 2.39 or newer): $out" ;;
    *) die "rcagent does not run on this system: $out" ;;
  esac
}
curl -fsSL -o "$tmp/SHA256SUMS" "$REPO/SHA256SUMS" || die "could not download the release checksums from $REPO (is there a release yet?)"

if command -v pacman >/dev/null; then ASSET=remote-control-x86_64.pkg.tar.zst; else ASSET=rcagent-linux-x86_64; fi
fetch "$ASSET"
# Tests stop here (download and checksum only).
if [ -n "${RC_DOWNLOAD_ONLY:-}" ]; then
  if [ "$ASSET" = rcagent-linux-x86_64 ]; then chmod +x "$tmp/$ASSET" && check_runs "$tmp/$ASSET"; fi
  say "downloaded and verified $ASSET"
  exit 0
fi

if [ "$ASSET" = remote-control-x86_64.pkg.tar.zst ]; then
  say "Arch Linux detected: installing the remote-control package"
  sudo pacman -U --noconfirm "$tmp/remote-control-x86_64.pkg.tar.zst"
  # Remote desktop needs the backend for this desktop (installed with
  # Plasma/GNOME, but make sure).
  case "${XDG_CURRENT_DESKTOP:-}" in
    *KDE*) pacman -Qq xdg-desktop-portal-kde >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm xdg-desktop-portal-kde ;;
    *GNOME*) pacman -Qq xdg-desktop-portal-gnome >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm xdg-desktop-portal-gnome ;;
    *Hyprland*|*sway*|*Sway*) pacman -Qq wayvnc >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm wayvnc ;;
  esac
  RCAGENT=/usr/bin/rcagent
else
  say "Installing rcagent to ~/.local/bin"
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$tmp/rcagent-linux-x86_64" "$HOME/.local/bin/rcagent"
  RCAGENT="$HOME/.local/bin/rcagent"
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) say "Add ~/.local/bin to your PATH to run rcagent directly." ;; esac
fi

check_runs "$RCAGENT"

say "Setting up this computer"
# The script itself may be piped into bash, so read answers from the terminal.
# An existing setup is kept (rcagent setup --force replaces the account).
"$RCAGENT" setup < /dev/tty

say "Starting Remote Control now and at every boot"
"$RCAGENT" service install
if loginctl enable-linger "$USER" 2>/dev/null; then
  say "It will start at boot, even before you sign in (desktop needs your graphical session)."
else
  say "Could not enable start-before-login (loginctl enable-linger \$USER); it starts when you sign in."
fi

echo
"$RCAGENT" status | sed -n 's/^id: */Computer ID: /p'
say "Connect from $APP"
