#!/usr/bin/env bash
# install.sh — install apm onto the local system
#
# Usage:
#   bash install.sh              # install to ~/.local/bin (default)
#   bash install.sh ~/bin        # install to a custom directory
#   bash install.sh --uninstall  # remove the installed symlink
#   bash install.sh --check      # check deps only, don't install

set -uo pipefail

APM_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APM_BIN="${APM_REPO_DIR}/apm"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_info()  { printf "  \033[32m✓\033[0m  %s\n" "$*"; }
_warn()  { printf "  \033[33m!\033[0m  %s\n" "$*"; }
_err()   { printf "  \033[31m✗\033[0m  %s\n" "$*" >&2; }
_die()   { _err "$*"; exit 1; }
_step()  { printf "\n  %s\n" "$*"; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

UNINSTALL=0
CHECK_ONLY=0
INSTALL_DIR=""

for arg in "$@"; do
    case "$arg" in
        --uninstall) UNINSTALL=1 ;;
        --check)     CHECK_ONLY=1 ;;
        --*)         _die "Unknown flag: $arg" ;;
        *)           INSTALL_DIR="$arg" ;;
    esac
done

# Resolve install directory
if [ -z "$INSTALL_DIR" ]; then
    if [ -d "${HOME}/.local/bin" ]; then
        INSTALL_DIR="${HOME}/.local/bin"
    elif [ -d "${HOME}/bin" ]; then
        INSTALL_DIR="${HOME}/bin"
    else
        INSTALL_DIR="${HOME}/.local/bin"
    fi
fi
INSTALL_LINK="${INSTALL_DIR}/apm"

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------

_check_deps() {
    local ok=1

    _step "Checking dependencies..."

    if command -v python3 >/dev/null 2>&1; then
        local py_version
        py_version=$(python3 --version 2>&1)
        _info "python3 found: $py_version"
    else
        _err "python3 not found — required for YAML parsing"
        ok=0
    fi

    if python3 -c "import yaml" 2>/dev/null; then
        _info "PyYAML found"
    else
        _err "PyYAML not found — install with: pip3 install pyyaml"
        ok=0
    fi

    if command -v git >/dev/null 2>&1; then
        _info "git found (required for GitHub sync)"
    else
        _warn "git not found — GitHub sync commands will not work"
    fi

    [ $ok -eq 1 ]
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

if [ "$UNINSTALL" = "1" ]; then
    echo ""
    echo "  Uninstalling apm..."
    if [ -L "$INSTALL_LINK" ]; then
        rm "$INSTALL_LINK"
        _info "Removed: $INSTALL_LINK"
    elif [ -f "$INSTALL_LINK" ]; then
        _err "$INSTALL_LINK exists but is not a symlink — not removing"
        _err "Remove it manually: rm $INSTALL_LINK"
        exit 1
    else
        _warn "Not installed at $INSTALL_LINK — nothing to remove"
    fi
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Check only
# ---------------------------------------------------------------------------

if [ "$CHECK_ONLY" = "1" ]; then
    echo ""
    if _check_deps; then
        echo ""
        _info "All dependencies satisfied"
    else
        echo ""
        _err "Some dependencies are missing"
        exit 1
    fi
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

echo ""
echo "  apm installer"
echo "  ─────────────"
printf "  Repo  : %s\n" "$APM_REPO_DIR"
printf "  Target: %s\n" "$INSTALL_LINK"

if ! _check_deps; then
    echo ""
    _die "Dependency check failed — fix the above issues and re-run"
fi

_step "Installing..."

# Ensure install dir exists
if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR" || _die "Cannot create directory: $INSTALL_DIR"
    _info "Created: $INSTALL_DIR"
fi

# Create or update symlink
if [ -L "$INSTALL_LINK" ]; then
    rm "$INSTALL_LINK"
fi
if [ -e "$INSTALL_LINK" ]; then
    _die "$INSTALL_LINK already exists and is not a symlink — remove it manually"
fi

ln -s "$APM_BIN" "$INSTALL_LINK" || _die "Failed to create symlink at $INSTALL_LINK"
_info "Linked: $INSTALL_LINK → $APM_BIN"

# ---------------------------------------------------------------------------
# PATH check
# ---------------------------------------------------------------------------

_step "Checking PATH..."

if echo ":${PATH}:" | grep -q ":${INSTALL_DIR}:"; then
    _info "$INSTALL_DIR is in your PATH"
else
    _warn "$INSTALL_DIR is not in your PATH"
    echo ""
    echo "  Add it to your shell profile:"
    echo ""
    echo "    # bash / zsh"
    echo "    export PATH=\"\$PATH:${INSTALL_DIR}\""
    echo ""
    echo "  Then restart your shell or run:"
    echo "    source ~/.zshrc   # or ~/.bashrc"
fi

# ---------------------------------------------------------------------------
# First-run hint
# ---------------------------------------------------------------------------

echo ""
echo "  ─────────────"
echo "  Done. Run:  apm setup"
echo ""
