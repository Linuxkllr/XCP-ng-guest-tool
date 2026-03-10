#!/usr/bin/env bash
set -euo pipefail

# Citrix/XenServer Linux Guest Tools installer
# Tested for Rocky Linux / RHEL-like systems
# Usage:
#   sudo bash install-citrix-guest-tools.sh
#
# Optional:
#   TOOL_URL="https://downloads.xenserver.com/vm-tools-linux/10.0.0-1-149/LinuxGuestTools-10.0.0-1.tar.gz" sudo bash install-citrix-guest-tools.sh

TOOL_URL="${TOOL_URL:-https://downloads.xenserver.com/vm-tools-linux/10.0.0-1-149/LinuxGuestTools-10.0.0-1.tar.gz}"
WORKDIR="/usr/local/src/citrix-guest-tools"
ARCHIVE_NAME="$(basename "$TOOL_URL")"
EXTRACT_DIR=""
SUDO=""

if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

detect_pkg_mgr() {
  if command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  else
    fail "Neither dnf nor yum was found."
  fi
}

install_packages() {
  local pkg_mgr="$1"

  log "Installing required packages..."
  $SUDO "$pkg_mgr" install -y \
    wget \
    tar \
    gcc \
    make \
    perl \
    kernel-devel \
    kernel-headers || warn "Some packages could not be installed automatically."

  log "Attempting to install matching kernel-devel for running kernel: $(uname -r)"
  $SUDO "$pkg_mgr" install -y "kernel-devel-$(uname -r)" || warn "Matching kernel-devel package was not available."
  $SUDO "$pkg_mgr" install -y "kernel-headers-$(uname -r)" || warn "Matching kernel-headers package was not available."
}

download_archive() {
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"

  log "Downloading guest tools from:"
  echo "       $TOOL_URL"

  if command -v curl >/dev/null 2>&1; then
    curl -fL "$TOOL_URL" -o "$ARCHIVE_NAME"
  else
    require_cmd wget
    wget -O "$ARCHIVE_NAME" "$TOOL_URL"
  fi
}

extract_archive() {
  cd "$WORKDIR"

  log "Extracting $ARCHIVE_NAME ..."
  tar xzf "$ARCHIVE_NAME"

  EXTRACT_DIR="$(tar tzf "$ARCHIVE_NAME" | head -1 | cut -d/ -f1)"
  [[ -n "$EXTRACT_DIR" ]] || fail "Could not determine extracted directory."

  [[ -d "$EXTRACT_DIR" ]] || fail "Expected extracted directory not found: $WORKDIR/$EXTRACT_DIR"
}

run_installer() {
  cd "$WORKDIR/$EXTRACT_DIR"

  [[ -f install.sh ]] || fail "install.sh not found in $WORKDIR/$EXTRACT_DIR"

  chmod +x install.sh

  log "Running installer..."
  $SUDO ./install.sh
}

post_install_check() {
  log "Checking for xe-linux-distribution service..."

  if systemctl list-unit-files | grep -q '^xe-linux-distribution'; then
    $SUDO systemctl enable xe-linux-distribution || warn "Could not enable xe-linux-distribution"
    $SUDO systemctl restart xe-linux-distribution || warn "Could not restart xe-linux-distribution"
    $SUDO systemctl --no-pager --full status xe-linux-distribution || true
  else
    warn "xe-linux-distribution service was not found after install."
  fi

  if pgrep -fa xe >/dev/null 2>&1; then
    log "Guest tools processes detected:"
    pgrep -fa xe || true
  else
    warn "No xe-related processes found yet."
  fi
}

main() {
  require_cmd uname
  require_cmd tar

  local pkg_mgr
  pkg_mgr="$(detect_pkg_mgr)"

  log "Starting Citrix/XenServer guest tools installation"
  log "Detected package manager: $pkg_mgr"
  log "Running kernel: $(uname -r)"

  install_packages "$pkg_mgr"
  download_archive
  extract_archive
  run_installer
  post_install_check

  log "Installation finished."
  log "A reboot is recommended:"
  echo "       sudo reboot"
}

main "$@"
