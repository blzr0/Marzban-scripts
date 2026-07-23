#!/usr/bin/env bash

# Download Xray latest

RELEASE_TAG="latest"

if [[ "$1" ]]; then
    RELEASE_TAG="$1"
fi

USE_RU_GEO="${USE_RU_GEO:-true}"
RUNETFREEDOM_BASE_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"

check_if_running_as_root() {
    # If you want to run as another user, please modify $EUID to be owned by this user
    if [[ "$EUID" -ne '0' ]]; then
        echo "error: You must run this script as root!"
        exit 1
    fi
}

identify_the_operating_system_and_architecture() {
    if [[ "$(uname)" == 'Linux' ]]; then
        case "$(uname -m)" in
            'i386' | 'i686')
                ARCH='32'
            ;;
            'amd64' | 'x86_64')
                ARCH='64'
            ;;
            'armv5tel')
                ARCH='arm32-v5'
            ;;
            'armv6l')
                ARCH='arm32-v6'
                grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5'
            ;;
            'armv7' | 'armv7l')
                ARCH='arm32-v7a'
                grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5'
            ;;
            'armv8' | 'aarch64')
                ARCH='arm64-v8a'
            ;;
            'mips')
                ARCH='mips32'
            ;;
            'mipsle')
                ARCH='mips32le'
            ;;
            'mips64')
                ARCH='mips64'
                lscpu | grep -q "Little Endian" && ARCH='mips64le'
            ;;
            'mips64le')
                ARCH='mips64le'
            ;;
            'ppc64')
                ARCH='ppc64'
            ;;
            'ppc64le')
                ARCH='ppc64le'
            ;;
            'riscv64')
                ARCH='riscv64'
            ;;
            's390x')
                ARCH='s390x'
            ;;
            *)
                echo "error: The architecture is not supported."
                exit 1
            ;;
        esac
    else
        echo "error: This operating system is not supported."
        exit 1
    fi
}

download_xray() {
    if [[ "$RELEASE_TAG" == "latest" ]]; then
        DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$ARCH.zip"
    else
        DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/download/$RELEASE_TAG/Xray-linux-$ARCH.zip"
    fi
    
    echo "Downloading Xray archive: $DOWNLOAD_LINK"
    if ! curl -RL -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK"; then
        echo 'error: Download failed! Please check your network or try again.'
        return 1
    fi
}

extract_xray() {
    if ! unzip -q "$ZIP_FILE" -d "$TMP_DIRECTORY"; then
        echo 'error: Xray decompression failed.'
        "rm" -rf "$TMP_DIRECTORY"
        echo "removed: $TMP_DIRECTORY"
        exit 1
    fi
    echo "Extracted Xray archive to $TMP_DIRECTORY"
}

is_ru_geo_enabled() {
    case "$USE_RU_GEO" in
        false|0|no|off|FALSE|False|No|NO|Off|OFF)
            return 1
        ;;
        *)
            return 0
        ;;
    esac
}

fetch() {
    curl -fRL --retry 3 --retry-delay 2 --connect-timeout 10 -H 'Cache-Control: no-cache' -o "$2" "$1"
}

verify_checksum() {
    local file="$1"
    local sha_file="$2"
    local expected_hash actual_hash

    expected_hash="$(awk '{print tolower($1); exit}' "$sha_file" 2>/dev/null)"
    if [[ -z "$expected_hash" ]]; then
        return 1
    fi

    actual_hash="$(sha256sum "$file" | awk '{print tolower($1)}')"

    [[ "$expected_hash" == "$actual_hash" ]]
}

download_russian_geo() {
    local geoip_url="${RUNETFREEDOM_BASE_URL}/geoip.dat"
    local geosite_url="${RUNETFREEDOM_BASE_URL}/geosite.dat"

    if ! fetch "$geoip_url" "${TMP_DIRECTORY}/ru-geoip.dat"; then
        echo "warning: failed to download runetfreedom geoip.dat"
        return 1
    fi
    if ! fetch "${geoip_url}.sha256sum" "${TMP_DIRECTORY}/ru-geoip.dat.sha256sum"; then
        echo "warning: failed to download runetfreedom geoip.dat checksum"
        return 1
    fi
    if ! fetch "$geosite_url" "${TMP_DIRECTORY}/ru-geosite.dat"; then
        echo "warning: failed to download runetfreedom geosite.dat"
        return 1
    fi
    if ! fetch "${geosite_url}.sha256sum" "${TMP_DIRECTORY}/ru-geosite.dat.sha256sum"; then
        echo "warning: failed to download runetfreedom geosite.dat checksum"
        return 1
    fi

    if ! verify_checksum "${TMP_DIRECTORY}/ru-geoip.dat" "${TMP_DIRECTORY}/ru-geoip.dat.sha256sum"; then
        echo "warning: checksum mismatch for runetfreedom geoip.dat"
        return 1
    fi
    if ! verify_checksum "${TMP_DIRECTORY}/ru-geosite.dat" "${TMP_DIRECTORY}/ru-geosite.dat.sha256sum"; then
        echo "warning: checksum mismatch for runetfreedom geosite.dat"
        return 1
    fi

    return 0
}

place_xray() {
    install -m 755 "${TMP_DIRECTORY}/xray" "/usr/local/bin/xray"
    install -d "/usr/local/share/xray/"

    local geo_source="xtls"
    if is_ru_geo_enabled; then
        if download_russian_geo; then
            geo_source="runetfreedom"
        else
            echo "warning: failed to fetch runetfreedom geo files, falling back to XTLS defaults"
        fi
    fi

    if [[ "$geo_source" == "runetfreedom" ]]; then
        install -m 644 "${TMP_DIRECTORY}/ru-geoip.dat" "/usr/local/share/xray/geoip.dat"
        install -m 644 "${TMP_DIRECTORY}/ru-geosite.dat" "/usr/local/share/xray/geosite.dat"
        echo "Geo files installed from runetfreedom (russia-v2ray-rules-dat)"
    else
        install -m 644 "${TMP_DIRECTORY}/geoip.dat" "/usr/local/share/xray/geoip.dat"
        install -m 644 "${TMP_DIRECTORY}/geosite.dat" "/usr/local/share/xray/geosite.dat"
    fi

    echo "Xray files installed"
}

check_if_running_as_root
identify_the_operating_system_and_architecture

TMP_DIRECTORY="$(mktemp -d)"
ZIP_FILE="${TMP_DIRECTORY}/Xray-linux-$ARCH.zip"

download_xray
extract_xray
place_xray

"rm" -rf "$TMP_DIRECTORY"