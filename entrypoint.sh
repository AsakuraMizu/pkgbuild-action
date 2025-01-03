#!/bin/bash

set -eo pipefail

path="$1"
archive="$2"

if [[ ! -d "$path" ]]; then
    echo "::error ::Invalid path: [$path]"
    exit 1
fi

outputwarning() {
    local warnings="$1"
    if [[ -n "$warnings" ]]; then
        warnings="${warnings//'%'/'%25'}"
        warnings="${warnings//$'\n'/'%0A'}"
        warnings="${warnings//$'\r'/'%0D'}"
        echo "::warning::$warnings"
    fi
}

if [[ -n "$archive" ]]; then
    echo "::group::Use archive on $archive"
    echo "Server = https://archive.archlinux.org/repos/$archive/\$repo/os/\$arch" | sudo tee /etc/pacman.d/mirrorlist
    sudo pacman -Syyuu --noconfirm
    echo "::endgroup::"
fi

abspath="$(realpath "$path")"

export HOME=/home/build
echo "::group::Move files to $HOME"
cd "$HOME"
cp -r "$abspath" .
cd "$(basename "$abspath")"
echo "::endgroup::"

if [[ $INPUT_UPDPKGSUMS == true ]]; then
    echo "::group::Update checksums"
    updpkgsums
    sudo cp PKGBUILD "$abspath"
    echo "::endgroup::"
fi

echo "::group::Source PKGBUILD"
source PKGBUILD
echo "::endgroup::"

echo "::group::Install depends"
paru -Syu --removemake --needed --noconfirm "${depends[@]}" "${makedepends[@]}"
echo "::endgroup::"

echo "::group::Make package"
logfile=$(mktemp)
makepkg -cfs --noconfirm 2>&1 | tee "$logfile"
warn="$(grep WARNING "$logfile" || true)"
outputwarning "$warn"
echo "::endgroup::"

echo "::group::Show package info"
source /etc/makepkg.conf # get PKGEXT
files=("${pkgname}-"*"${PKGEXT}")
pkgfile="${files[0]}"
echo "pkgfile=${pkgfile}" | sudo tee -a "$GITHUB_OUTPUT"
pacman -Qip "${pkgfile}"
pacman -Qlp "${pkgfile}"
echo "::endgroup::"

echo "::group::Run namcap checks"
outputwarning "$(namcap PKGBUILD)"
outputwarning "$(namcap "${pkgfile}")"
echo "::endgroup::"

sudo mv "$pkgfile" /github/workspace

echo "::group::Generate .SRCINFO"
makepkg --printsrcinfo > .SRCINFO
sudo mv .SRCINFO "$abspath"
echo "::endgroup::"
