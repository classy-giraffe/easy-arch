#!/usr/bin/env bash

set -o nounset -o errexit
readonly MIRROR="https://mirror.pkgbuild.com"

function init() {
  readonly ORIG_PWD="${PWD}"
  readonly OUTPUT="${PWD}/output"
  readonly TMPDIR="$(mktemp --dry-run --directory --tmpdir="${PWD}/tmp")"
  mkdir -p "${OUTPUT}" "${TMPDIR}"

  cd "${TMPDIR}"
}

# Do some cleanup when the script exits
function cleanup() {
  rm -rf -- "${TMPDIR}"
  jobs -p | xargs --no-run-if-empty kill
}
trap cleanup EXIT

# Use local Arch iso or download the latest iso and extract the relevant files
function prepare_boot() {
  local iso
  local isos=()

  # retrieve any local images and sort them
  for iso in "${ORIG_PWD}/"archlinux-*-x86_64.iso; do
    if [[ -f "$iso" ]]; then
      isos+=("${iso}")
    fi
  done
  if (( ${#isos[@]} >= 1 )); then
    ISO="$(printf '%s\n' "${isos[@]}" | sort -r | head -n1)"
    printf "Using local iso: %s\n" "$ISO"
  fi

  if (( ${#isos[@]} < 1 )); then
    LATEST_ISO="$(curl -fs "${MIRROR}/iso/latest/" | grep -Eo 'archlinux-[0-9]{4}\.[0-9]{2}\.[0-9]{2}-x86_64.iso' | head -n 1)"
    if [[ -z "${LATEST_ISO}" ]]; then
      echo "Error: Couldn't find latest iso'"
      exit 1
    fi
    curl -fO "${MIRROR}/iso/latest/${LATEST_ISO}"
    ISO="${PWD}/${LATEST_ISO}"
  fi

  # We need to extract the kernel and initrd so we can set a custom cmdline:
  # console=ttyS0, so the kernel and systemd sends output to the serial.
  xorriso -osirrox on -indev "${ISO}" -extract arch/boot/x86_64 .
  ISO_VOLUME_ID="$(xorriso -indev "${ISO}" |& awk -F : '$1 ~ "Volume id" {print $2}' | tr -d "' ")"
}

function start_qemu() {
  # Used to communicate with qemu
  mkfifo guest.out guest.in
  # We could use a sparse file but we want to fail early
  fallocate -l 8G scratch-disk.img

  { qemu-system-x86_64 \
    -machine accel=kvm:tcg \
    -smp "$(nproc)" \
    -m 4096 \
    -device virtio-net-pci,romfile=,netdev=net0 -netdev user,id=net0 \
    -kernel vmlinuz-linux \
    -initrd initramfs-linux.img \
    -append "archisobasedir=arch archisolabel=${ISO_VOLUME_ID} cow_spacesize=4G ip=dhcp net.ifnames=0 console=ttyS0 mirror=${MIRROR}" \
    -drive file=scratch-disk.img,format=raw,if=virtio \
    -drive file="${ISO}",format=raw,if=virtio,media=cdrom,read-only \
    -virtfs "local,path=${ORIG_PWD},mount_tag=host,security_model=none" \
    -monitor none \
    -serial pipe:guest \
    -nographic || kill "${$}"; } &

  # We want to send the output to both stdout (fd1) and fd10 (used by the expect function)
  exec 3>&1 10< <(tee /dev/fd/3 <guest.out)
}

# Wait for a specific string from qemu
function expect() {
  local length="${#1}"
  local i=0
  local timeout="${2:-30}"
  # We can't use ex: grep as we could end blocking forever, if the string isn't followed by a newline
  while true; do
    # read should never exit with a non-zero exit code,
    # but it can happen if the fd is EOF or it times out
    IFS= read -r -u 10 -n 1 -t "${timeout}" c
    if [[ "${1:${i}:1}" = "${c}" ]]; then
      i="$((i + 1))"
      if [[ "${length}" -eq "${i}" ]]; then
        break
      fi
    else
      i=0
    fi
  done
}

# Send string to qemu
function send() {
  echo -en "${1}" >guest.in
}

function main() {
  init
  prepare_boot
  start_qemu

  # Login
  expect "archiso login:"
  send "root\n"
  expect "# "

  # Switch to bash and shutdown on error
  send "bash\n"
  expect "# "
  send "trap \"shutdown now\" ERR\n"
  expect "# "

  # Prepare environment
  send "mkdir /mnt/project && mount -t 9p -o trans=virtio host /mnt/project -oversion=9p2000.L\n"
  expect "# "
  send "mkfs.ext4 /dev/vda && mkdir /mnt/scratch-disk/ && mount /dev/vda /mnt/scratch-disk && cd /mnt/scratch-disk\n"
  expect "# "
  send "cp -a -- /mnt/project/{.gitlab,archiso,configs,scripts} .\n"
  expect "# "
  send "mkdir pkg && mount --bind pkg /var/cache/pacman/pkg\n"
  expect "# "

  # Wait for pacman-init
  send "until systemctl is-active pacman-init; do sleep 1; done\n"
  expect "# "

  # Explicitly lookup mirror address as we'd get random failures otherwise during pacman
  send "curl -sSo /dev/null ${MIRROR}\n"
  expect "# "

  # Install required packages
  send "pacman -Syu --ignore linux --noconfirm --needed qemu-headless jq dosfstools e2fsprogs libisoburn mtools squashfs-tools\n"
  expect "# " 120

  ## Start build and copy output to local disk
  send "bash -x ./.gitlab/ci/build-inside-vm.sh ${PROFILE}\n "
  expect "# " 1000 # mksquashfs can take a long time
  send "cp -r --preserve=mode,timestamps -- output /mnt/project/tmp/$(basename "${TMPDIR}")/\n"
  expect "# " 60
  mv output/* "${OUTPUT}/"

  # Shutdown the VM
  send "systemctl poweroff -i\n"
  wait
}
main