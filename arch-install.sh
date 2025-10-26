#!/usr/bin/env bash
# Arch Linux UEFI + LUKS installer (no arrow keys, step-by-step prompts)
# Usage:
#   curl -fsSL https://your-url/arch-encrypt.sh | bash
# or save then: bash arch-encrypt.sh

set -euo pipefail
IFS=$'\n\t'

LOG=/tmp/arch-install.log
exec > >(tee -a "$LOG") 2>&1

die() { echo "ERROR: $*" >&2; exit 1; }
run() { echo "==> $*"; eval "$*"; }
pause() { read -rp "Press Enter to continue..."; }

require_uefi() {
  [ -d /sys/firmware/efi/efivars ] || die "Not booted in UEFI mode."
}

require_net() {
  ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "No internet. Use iwctl, then rerun."
}

choose_disk() {
  echo
  echo "Disks:"
  mapfile -t L < <(lsblk -d -n -p -o NAME,SIZE,MODEL | sed 's/  */ /g')
  [ "${#L[@]}" -gt 0 ] || die "No disks found."
  for i in "${!L[@]}"; do printf "  %d) %s\n" "$((i+1))" "${L[$i]}"; done
  echo
  read -rp "Install to which number? " n
  [[ "$n" =~ ^[0-9]+$ ]] || die "Invalid selection."
  idx=$((n-1))
  [ "$idx" -ge 0 ] && [ "$idx" -lt "${#L[@]}" || die "Out of range." ]
  DISK=$(echo "${L[$idx]}" | awk '{print $1}')
  echo "Selected disk: $DISK"
}

confirm_wipe() {
  echo
  echo "WARNING: This will erase $DISK completely."
  read -rp "Type YES to continue: " yn
  [ "$yn" = "YES" ] || die "Cancelled."
}

defaults() {
  KEYMAP="us"
  LOCALE="${LOCALE:-en_US.UTF-8}"
  read -rp "Hostname [archlinux]: " HOSTNAME; HOSTNAME=${HOSTNAME:-archlinux}
  read -rp "Username: " USERNAME; [ -n "${USERNAME:-}" ] || die "Username required."
  read -rsp "User password: " USERPASS; echo
  read -rsp "Confirm user password: " USERPASS2; echo
  [ "$USERPASS" = "$USERPASS2" ] || die "User passwords do not match."
  read -rsp "Root password: " ROOTPASS; echo
  read -rsp "Confirm root password: " ROOTPASS2; echo
  [ "$ROOTPASS" = "$ROOTPASS2" ] || die "Root passwords do not match."
  read -rsp "Disk encryption password: " CRYPTPASS; echo
  read -rsp "Confirm encryption password: " CRYPTPASS2; echo
  [ "$CRYPTPASS" = "$CRYPTPASS2" ] || die "Encryption passwords do not match."
  read -rp "Timezone (Region/City) [UTC]: " TIMEZONE; TIMEZONE=${TIMEZONE:-UTC}
  echo "Locale will be ${LOCALE}. Keyboard will be ${KEYMAP}."
}

prep_iso_env() {
  timedatectl set-ntp true
  loadkeys "$KEYMAP" || true
  sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
  sed -i 's/^ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
}

partition_disk() {
  echo "Partitioning $DISK to GPT: 512M EFI + rest LUKS."
  if [[ "$DISK" =~ nvme|mmcblk ]]; then
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
  else
    BOOT_PART="${DISK}1"
    ROOT_PART="${DISK}2"
  fi
  run "wipefs -af $DISK"
  run "sgdisk -Z $DISK"
  run "sgdisk -n 1:0:+512M -t 1:ef00 -c 1:'EFI' $DISK"
  run "sgdisk -n 2:0:0    -t 2:8309 -c 2:'LUKS' $DISK"
  run "partprobe $DISK"
  sleep 2
  lsblk "$DISK"
}

format_encrypt_mount() {
  run "mkfs.fat -F32 $BOOT_PART"
  echo -n "$CRYPTPASS" | cryptsetup luksFormat --type luks2 "$ROOT_PART" - </dev/tty
  echo -n "$CRYPTPASS" | cryptsetup open "$ROOT_PART" cryptroot - </dev/tty
  run "mkfs.ext4 -F /dev/mapper/cryptroot"
  run "mount /dev/mapper/cryptroot /mnt"
  run "mkdir -p /mnt/boot"
  run "mount $BOOT_PART /mnt/boot"
}

install_base() {
  CPU_VENDOR=$(grep -m1 -i '^vendor_id' /proc/cpuinfo | awk '{print $3}' || true)
  MC=""
  [[ "$CPU_VENDOR" == "GenuineIntel" ]] && MC="intel-ucode"
  [[ "$CPU_VENDOR" == "AuthenticAMD" ]] && MC="amd-ucode"
  echo "Detected CPU: $CPU_VENDOR ${MC:+(adding $MC)}"
  run "pacstrap -K /mnt base base-devel linux linux-firmware $MC networkmanager grub efibootmgr cryptsetup lvm2 sudo nano vim"
  run "genfstab -U /mnt > /mnt/etc/fstab"
}

write_chroot_script() {
  cat > /mnt/root/configure.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[chroot] $*"; }

TIMEZONE="__TIMEZONE__"
LOCALE="__LOCALE__"
KEYMAP="__KEYMAP__"
HOSTNAME="__HOSTNAME__"
USERNAME="__USERNAME__"
USERPASS="__USERPASS__"
ROOTPASS="__ROOTPASS__"
ROOT_PART="__ROOT_PART__"

log "Timezone"
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

log "Locale"
sed -i "s/^#\(${LOCALE//\//\\/}\s\+UTF-8\)/\1/" /etc/locale.gen || echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

log "Console keymap"
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

log "Hostname"
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

log "Passwords"
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USERPASS}" | chpasswd

log "Sudo"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

log "mkinitcpio hooks for LUKS"
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

log "GRUB kernel cmdline with cryptdevice"
CRYPT_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=${CRYPT_UUID}:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub

log "Install GRUB to NVRAM"
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ArchLinux --recheck

log "Also install fallback EFI (removable path)"
grub-install --target=x86_64-efi --efi-directory=/boot --removable

log "Generate GRUB config"
grub-mkconfig -o /boot/grub/grub.cfg

log "Enable services"
systemctl enable NetworkManager

log "Show EFI entries (if available)"
efibootmgr -v || true

log "Done"
EOS

  sed -i "s|__TIMEZONE__|$TIMEZONE|g" /mnt/root/configure.sh
  sed -i "s|__LOCALE__|$LOCALE|g" /mnt/root/configure.sh
  sed -i "s|__KEYMAP__|$KEYMAP|g" /mnt/root/configure.sh
  sed -i "s|__HOSTNAME__|$HOSTNAME|g" /mnt/root/configure.sh
  sed -i "s|__USERNAME__|$USERNAME|g" /mnt/root/configure.sh
  sed -i "s|__USERPASS__|$USERPASS|g" /mnt/root/configure.sh
  sed -i "s|__ROOTPASS__|$ROOTPASS|g" /mnt/root/configure.sh
  sed -i "s|__ROOT_PART__|$ROOT_PART|g" /mnt/root/configure.sh
  chmod +x /mnt/root/configure.sh
}

run_chroot() {
  run "arch-chroot /mnt /root/configure.sh"
  run "rm -f /mnt/root/configure.sh"
}

verify_boot() {
  echo "Boot files:"
  ls -l /mnt/boot || true
  ls -l /mnt/boot/EFI || true
  [ -f /mnt/boot/grub/grub.cfg ] || die "Missing /boot/grub/grub.cfg"
  # Fallback path should exist after --removable
  [ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ] || echo "Note: fallback BOOTX64.EFI not found; check firmware NVRAM entry."
}

finish() {
  echo
  echo "Install finished. Log: $LOG"
  echo "Unmount and reboot now."
  echo "Commands:"
  echo "  umount -R /mnt"
  echo "  cryptsetup close cryptroot"
  echo "  reboot"
}

main() {
  require_uefi
  require_net
  choose_disk
  confirm_wipe
  defaults
  prep_iso_env
  partition_disk
  format_encrypt_mount
  install_base
  write_chroot_script
  run_chroot
  verify_boot
  finish
}

main
