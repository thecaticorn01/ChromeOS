#!/usr/bin/env bash
set -euo pipefail

D_BRUNCH_COUNT=0

# Check sudo
if command -v sudo &>/dev/null; then
    with_sudo="sudo "
else
    with_sudo=""
fi

install_dependencies() {
    ${with_sudo}apt update
    ${with_sudo}apt -y install pv cgpt tar unzip aria2 curl
}

clean_previous_run() {
    [ -d brunch ] && rm -rf brunch
    [ -d chromeos ] && rm -rf chromeos
    echo "Cleaned previous run"
}

download_chromeos() {
    local code_name=$1
    local url="https://cros.tech/device/${code_name}"

    local response=$(curl -s "$url")

    local link=$(echo "$response" | sed -n 's/.*<a[^>]*href="\([^"]*dl\.google\.com[^"]*\.zip\)".*/\1/p' | head -n1)

    [ -z "$link" ] && { echo "No valid links found"; exit 1; }

    echo "Downloading Chrome OS for $code_name"
    aria2c -x 16 -o chromeos.zip "$link" || { echo "Download failed"; exit 1; }

    unzip -o chromeos.zip -d chromeos
    rm -f chromeos.zip
}

download_brunch() {
    local url="https://api.github.com/repos/sebanc/brunch/releases/latest"
    local response=$(curl -s "$url")

    local link=$(echo "$response" | grep -m1 '"browser_download_url":' | sed -E 's/.*"([^"]*\.tar\.gz)".*/\1/')

    if [ -z "$link" ]; then
        if [ "$D_BRUNCH_COUNT" -ge 2 ]; then
            echo "Failed to download Brunch"
            exit 1
        fi

        local random_sec=$((1 + RANDOM % 5))
        echo "Retrying in $random_sec seconds..."
        sleep $random_sec
        D_BRUNCH_COUNT=$((D_BRUNCH_COUNT + 1))
        download_brunch
        return
    fi

    echo "Downloading Brunch"
    aria2c -x 16 -o brunch.tar.gz "$link" || { echo "Download failed"; exit 1; }

    mkdir -p brunch
    tar -xzf brunch.tar.gz -C brunch
    rm -f brunch.tar.gz
}

post_download_setup() {
    [ ! -d brunch ] && { echo "brunch directory not found"; exit 1; }
    [ ! -d chromeos ] && { echo "chromeos directory not found"; exit 1; }

    echo "Copying Brunch files..."
    cp -r brunch/* chromeos/

    bin_file=$(ls chromeos/chromeos*.bin 2>/dev/null | head -n1)
    [ -z "$bin_file" ] && { echo "No chromeos*.bin found"; exit 1; }

    mv "$bin_file" chromeos/chromeos.bin
}

build_chromos_img() {
    cd chromeos || exit 1

    [ ! -f chromeos.bin ] && { echo "chromeos.bin not found"; exit 1; }
    [ ! -f chromeos-install.sh ] && { echo "chromeos-install.sh not found"; exit 1; }

    rm -f chromeos.img

    CHROMEOS_IMG_FILENAME=${CHROMEOS_IMG_FILENAME:-chromeos.img}

    [[ "$CHROMEOS_IMG_FILENAME" == *.img ]] || {
        echo "Filename must end in .img"
        exit 1
    }

    ${with_sudo}bash chromeos-install.sh -src chromeos.bin -dst "$CHROMEOS_IMG_FILENAME"

    [ -f "$CHROMEOS_IMG_FILENAME" ] && echo "Image created: $CHROMEOS_IMG_FILENAME"
}

# MAIN
install_dependencies

[ -z "${1:-}" ] && { echo "Provide Chrome OS codename"; exit 1; }

clean_previous_run
download_chromeos "$1"
download_brunch
post_download_setup
build_chromos_img
