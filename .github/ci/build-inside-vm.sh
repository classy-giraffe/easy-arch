#!/usr/bin/env bash
#
# This script is run within a virtual environment to build the available archiso profiles and create checksum files for
# the resulting images.
# The script needs to be run as root and assumes $PWD to be the root of the repository.

readonly orig_pwd="${PWD}"
readonly output="${orig_pwd}/output"
readonly tmpdir="$(mktemp --dry-run --directory --tmpdir="${orig_pwd}/tmp")"

cleanup() {
  # clean up temporary directories
  if [ -n "${tmpdir:-}" ]; then
    rm -rf "${tmpdir}"
  fi
}

create_checksums() {
  # create checksums for a file
  # $1: a file
  sha256sum "${1}" >"${1}.sha256"
  sha512sum "${1}" >"${1}.sha512"
  b2sum "${1}" >"${1}.b2"
  if [ -n "${SUDO_UID:-}" ]; then
    chown "${SUDO_UID}:${SUDO_GID}" "${1}"{,.b2,.sha{256,512}}
  fi
}

run_mkarchiso() {
  # run mkarchiso
  # $1: template name
  mkdir -p "${output}/${1}" "${tmpdir}/${1}"
  ./archiso/mkarchiso -o "${output}/${1}" -w "${tmpdir}/${1}" -v "configs/${1}"
  create_checksums "${output}/${1}/"*.iso
}

trap cleanup EXIT

run_mkarchiso "${1}"
