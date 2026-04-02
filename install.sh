#!/bin/sh
set -eu

REPO="akama/silt"
INSTALL_DIR="${SILT_INSTALL_DIR:-/usr/local/bin}"
BINARY="silt"

main() {
    check_deps
    detect_platform
    version=$(resolve_version)
    current=$(current_version)

    if [ "$current" = "$version" ]; then
        echo "silt ${version} is already installed."
        exit 0
    fi

    if [ -n "$current" ]; then
        echo "Updating silt: ${current} -> ${version}"
    else
        echo "Installing silt ${version}"
    fi

    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    download "$version" "$tmpdir"
    verify "$version" "$tmpdir"
    install_bin "$tmpdir"

    echo "Installed silt ${version} to ${INSTALL_DIR}/${BINARY}"
}

check_deps() {
    for cmd in curl tar sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            # macOS uses shasum instead of sha256sum
            if [ "$cmd" = "sha256sum" ] && command -v shasum >/dev/null 2>&1; then
                continue
            fi
            echo "Error: required command '$cmd' not found" >&2
            exit 1
        fi
    done
}

detect_platform() {
    os=$(uname -s)
    arch=$(uname -m)

    case "$os" in
        Linux)  os_name="linux" ;;
        Darwin) os_name="macos" ;;
        *)      echo "Error: unsupported OS: $os" >&2; exit 1 ;;
    esac

    case "$arch" in
        x86_64|amd64)   arch_name="x86_64" ;;
        aarch64|arm64)   arch_name="aarch64" ;;
        *)               echo "Error: unsupported architecture: $arch" >&2; exit 1 ;;
    esac

    ARTIFACT="silt-${os_name}-${arch_name}"
    echo "Detected platform: ${os_name}-${arch_name}"
}

resolve_version() {
    tag=$(curl -sI "https://github.com/${REPO}/releases/latest" \
        | grep -i '^location:' \
        | sed 's/.*\/tag\///' \
        | tr -d '\r\n ')
    if [ -z "$tag" ]; then
        echo "Error: could not determine latest version" >&2
        exit 1
    fi
    echo "$tag"
}

current_version() {
    if command -v "$BINARY" >/dev/null 2>&1; then
        "$BINARY" --version 2>/dev/null || true
    fi
}

download() {
    version=$1
    dest=$2
    base_url="https://github.com/${REPO}/releases/download/${version}"

    echo "Downloading ${ARTIFACT}.tar.gz..."
    curl -sfL -o "${dest}/${ARTIFACT}.tar.gz" "${base_url}/${ARTIFACT}.tar.gz" || {
        echo "Error: download failed. Check that ${version} has a ${ARTIFACT} artifact." >&2
        exit 1
    }

    echo "Downloading checksums..."
    curl -sfL -o "${dest}/SHA256SUMS" "${base_url}/SHA256SUMS" || {
        echo "Warning: could not download checksums, skipping verification" >&2
        return 0
    }
}

verify() {
    version=$1
    dest=$2

    if [ ! -f "${dest}/SHA256SUMS" ]; then
        return 0
    fi

    echo "Verifying checksum..."
    expected=$(grep "${ARTIFACT}.tar.gz" "${dest}/SHA256SUMS" | awk '{print $1}')
    if [ -z "$expected" ]; then
        echo "Warning: no checksum found for ${ARTIFACT}.tar.gz" >&2
        return 0
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "${dest}/${ARTIFACT}.tar.gz" | awk '{print $1}')
    else
        actual=$(shasum -a 256 "${dest}/${ARTIFACT}.tar.gz" | awk '{print $1}')
    fi

    if [ "$expected" != "$actual" ]; then
        echo "Error: checksum mismatch" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        exit 1
    fi
    echo "Checksum OK"
}

install_bin() {
    dest=$1

    tar xzf "${dest}/${ARTIFACT}.tar.gz" -C "${dest}"

    if [ ! -f "${dest}/silt" ]; then
        echo "Error: archive did not contain 'silt' binary" >&2
        exit 1
    fi

    chmod +x "${dest}/silt"

    # Ensure install dir exists, try direct copy, fall back to sudo
    if [ -w "$INSTALL_DIR" ] || mkdir -p "$INSTALL_DIR" 2>/dev/null; then
        mv "${dest}/silt" "${INSTALL_DIR}/${BINARY}"
    else
        echo "Need elevated permissions to write to ${INSTALL_DIR}"
        sudo mkdir -p "$INSTALL_DIR"
        sudo mv "${dest}/silt" "${INSTALL_DIR}/${BINARY}"
    fi
}

main "$@"
