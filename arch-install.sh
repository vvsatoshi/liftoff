#!/bin/bash

# Arch Linux Encrypted Installation - Interactive TUI (Fixed)
# Usage: curl -sL <url> | bash

set -e

# Logging
LOGFILE="/tmp/arch-install.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

error_exit() {
    echo "ERROR: $1" | tee -a "$LOGFILE"
    dialog --title "Installation Failed" --msgbox "\nInstallation failed!\n\nError: $1\n\nCheck the log at: $LOGFILE" 10 60
    exit 1
}

# Check if dialog is available, if not install it
if ! command -v dialog &> /dev/null; then
    pacman -Sy --noconfirm dialog
fi

# Dialog dimensions
HEIGHT=20
WIDTH=70
CHOICE_HEIGHT=10

# Temp file for dialog output
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Color scheme for dialog
export DIALOGRC=$(mktemp)
cat > $DIALOGRC << 'EOF'
use_colors = ON
screen_color = (CYAN,BLACK,ON)
shadow_color = (BLACK,BLACK,ON)
dialog_color = (BLACK,WHITE,OFF)
title_color = (BLUE,WHITE,ON)
border_color = (WHITE,WHITE,ON)
button_active_color = (WHITE,BLUE,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_key_active_color = (WHITE,BLUE,ON)
button_key_inactive_color = (RED,WHITE,OFF)
button_label_active_color = (WHITE,BLUE,ON)
button_label_inactive_color = (BLACK,WHITE,ON)
inputbox_color = (BLACK,WHITE,OFF)
inputbox_border_color = (BLACK,WHITE,OFF)
searchbox_color = (BLACK,WHITE,OFF)
searchbox_title_color = (BLUE,WHITE,ON)
searchbox_border_color = (WHITE,WHITE,ON)
position_indicator_color = (BLUE,WHITE,ON)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (WHITE,WHITE,ON)
item_color = (BLACK,WHITE,OFF)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (BLUE,WHITE,ON)
tag_selected_color = (WHITE,BLUE,ON)
tag_key_color = (RED,WHITE,OFF)
tag_key_selected_color = (RED,BLUE,ON)
check_color = (BLACK,WHITE,OFF)
check_selected_color = (WHITE,BLUE,ON)
uarrow_color = (GREEN,WHITE,ON)
darrow_color = (GREEN,WHITE,ON)
itemhelp_color = (BLACK,WHITE,OFF)
form_active_text_color = (WHITE,BLUE,ON)
form_text_color = (BLACK,WHITE,OFF)
EOF

# Variables
declare -A CONFIG

log "=== Arch Linux Encrypted Installation Started ==="

# Welcome screen
dialog --title "Arch Linux Encrypted Installation" \
    --colors --msgbox "\n\Zb\Z4Welcome to the Arch Linux Encrypted Installer!\Zn\n\n\
This installer will guide you through setting up:\n\n\
  • UEFI boot with GRUB\n\
  • LUKS2 full disk encryption\n\
  • Base system with NetworkManager\n\
  • Ready for Hyprland installation\n\n\
Press \Zb\Z1OK\Zn to continue..." 16 $WIDTH

# Check UEFI mode
if [ ! -d /sys/firmware/efi/efivars ]; then
    error_exit "System not booted in UEFI mode"
fi
log "UEFI mode confirmed"

# Internet check
dialog --infobox "Checking internet connection..." 4 40
if ! ping -c 1 archlinux.org &> /dev/null; then
    dialog --title "No Internet" --msgbox "\n\
No internet connection detected!\n\n\
For WiFi, exit and use:\n\n\
  iwctl\n\
  station list\n\
  station <device> connect <SSID>\n\n\
Then run this script again." 14 $WIDTH
    exit 1
fi
log "Internet connection verified"

# Keyboard layout - default to US
CONFIG[KEYMAP]="us"
loadkeys ${CONFIG[KEYMAP]}
log "Keyboard layout set to: ${CONFIG[KEYMAP]}"

# Disk selection
DISKS=$(lsblk -d -n -p -o NAME,SIZE,TYPE | grep disk)
DISK_OPTIONS=()
while IFS= read -r line; do
    disk=$(echo $line | awk '{print $1}')
    size=$(echo $line | awk '{print $2}')
    DISK_OPTIONS+=("$disk" "$size")
done <<< "$DISKS"

dialog --title "Disk Selection" \
    --menu "Select installation disk:\n\n⚠️  ALL DATA WILL BE ERASED!" \
    $HEIGHT $WIDTH $CHOICE_HEIGHT \
    "${DISK_OPTIONS[@]}" 2> $TEMP_FILE

CONFIG[DISK]=$(cat $TEMP_FILE)
log "Selected disk: ${CONFIG[DISK]}"

# Confirm disk
dialog --title "⚠️  CONFIRMATION REQUIRED" \
    --colors --yesno "\n\
\Zb\Z1WARNING: ALL DATA ON ${CONFIG[DISK]} WILL BE DESTROYED!\Zn\n\n\
This action cannot be undone.\n\n\
Do you want to continue?" 11 $WIDTH

if [ $? -ne 0 ]; then
    log "Installation cancelled by user"
    dialog --msgbox "Installation cancelled." 6 40
    exit 0
fi

# Timezone - Region
REGIONS=$(ls /usr/share/zoneinfo/ | grep -v "posix\|right\|Etc" | sort)
REGION_OPTIONS=()
for region in $REGIONS; do
    [ -d "/usr/share/zoneinfo/$region" ] && REGION_OPTIONS+=("$region" "")
done

dialog --title "Timezone - Region" \
    --menu "Select your region:" \
    $HEIGHT $WIDTH $CHOICE_HEIGHT \
    "${REGION_OPTIONS[@]}" 2> $TEMP_FILE

CONFIG[REGION]=$(cat $TEMP_FILE)
log "Selected region: ${CONFIG[REGION]}"

# Timezone - City
CITIES=$(ls /usr/share/zoneinfo/${CONFIG[REGION]}/ | sort)
CITY_OPTIONS=()
for city in $CITIES; do
    [ -f "/usr/share/zoneinfo/${CONFIG[REGION]}/$city" ] && CITY_OPTIONS+=("$city" "")
done

dialog --title "Timezone - City" \
    --menu "Select your city:" \
    $HEIGHT $WIDTH $CHOICE_HEIGHT \
    "${CITY_OPTIONS[@]}" 2> $TEMP_FILE

CONFIG[CITY]=$(cat $TEMP_FILE)
CONFIG[TIMEZONE]="${CONFIG[REGION]}/${CONFIG[CITY]}"
log "Timezone set to: ${CONFIG[TIMEZONE]}"

# Locale selection
LOCALES=("en_US.UTF-8" "English (US)"
         "en_GB.UTF-8" "English (UK)"
         "de_DE.UTF-8" "German"
         "fr_FR.UTF-8" "French"
         "es_ES.UTF-8" "Spanish"
         "it_IT.UTF-8" "Italian"
         "pt_BR.UTF-8" "Portuguese (Brazil)"
         "ru_RU.UTF-8" "Russian"
         "ja_JP.UTF-8" "Japanese"
         "zh_CN.UTF-8" "Chinese (Simplified)")

dialog --title "Locale" \
    --menu "Select your locale:" \
    $HEIGHT $WIDTH $CHOICE_HEIGHT \
    "${LOCALES[@]}" 2> $TEMP_FILE

CONFIG[LOCALE]=$(cat $TEMP_FILE)
log "Locale set to: ${CONFIG[LOCALE]}"

# Hostname
dialog --title "Hostname" \
    --inputbox "Enter hostname for this machine:" \
    10 $WIDTH "archlinux" 2> $TEMP_FILE

CONFIG[HOSTNAME]=$(cat $TEMP_FILE)
log "Hostname: ${CONFIG[HOSTNAME]}"

# Username
dialog --title "User Account" \
    --inputbox "Enter username:" \
    10 $WIDTH "" 2> $TEMP_FILE

CONFIG[USERNAME]=$(cat $TEMP_FILE)
log "Username: ${CONFIG[USERNAME]}"

# User password
while true; do
    dialog --title "User Password" \
        --insecure --passwordbox "Enter password for ${CONFIG[USERNAME]}:" \
        10 $WIDTH 2> $TEMP_FILE
    PASS1=$(cat $TEMP_FILE)
    
    dialog --title "User Password" \
        --insecure --passwordbox "Confirm password:" \
        10 $WIDTH 2> $TEMP_FILE
    PASS2=$(cat $TEMP_FILE)
    
    if [ "$PASS1" = "$PASS2" ]; then
        CONFIG[USER_PASSWORD]="$PASS1"
        break
    else
        dialog --msgbox "Passwords don't match. Try again." 6 40
    fi
done
log "User password set"

# Root password
while true; do
    dialog --title "Root Password" \
        --insecure --passwordbox "Enter root password:" \
        10 $WIDTH 2> $TEMP_FILE
    PASS1=$(cat $TEMP_FILE)
    
    dialog --title "Root Password" \
        --insecure --passwordbox "Confirm root password:" \
        10 $WIDTH 2> $TEMP_FILE
    PASS2=$(cat $TEMP_FILE)
    
    if [ "$PASS1" = "$PASS2" ]; then
        CONFIG[ROOT_PASSWORD]="$PASS1"
        break
    else
        dialog --msgbox "Passwords don't match. Try again." 6 40
    fi
done
log "Root password set"

# Encryption password
while true; do
    dialog --title "Disk Encryption Password" \
        --colors --insecure --passwordbox "\n\
\Zb\Z4This password will decrypt your disk at boot.\Zn\n\
Choose a strong password!\n\n\
Enter encryption password:" \
        12 $WIDTH 2> $TEMP_FILE
    PASS1=$(cat $TEMP_FILE)
    
    dialog --title "Disk Encryption Password" \
        --insecure --passwordbox "Confirm encryption password:" \
        10 $WIDTH 2> $TEMP_FILE
    PASS2=$(cat $TEMP_FILE)
    
    if [ "$PASS1" = "$PASS2" ]; then
        CONFIG[CRYPT_PASSWORD]="$PASS1"
        break
    else
        dialog --msgbox "Passwords don't match. Try again." 6 40
    fi
done
log "Encryption password set"

# Summary and final confirmation
dialog --title "Installation Summary" \
    --colors --yesno "\n\
Please review your configuration:\n\n\
\Zb\Z6Disk:\Zn          ${CONFIG[DISK]}\n\
\Zb\Z6Hostname:\Zn      ${CONFIG[HOSTNAME]}\n\
\Zb\Z6Username:\Zn      ${CONFIG[USERNAME]}\n\
\Zb\Z6Timezone:\Zn      ${CONFIG[TIMEZONE]}\n\
\Zb\Z6Locale:\Zn        ${CONFIG[LOCALE]}\n\
\Zb\Z6Keyboard:\Zn      ${CONFIG[KEYMAP]}\n\n\
\Zb\Z1Start installation?\Zn" 17 $WIDTH

if [ $? -ne 0 ]; then
    log "Installation cancelled by user at summary"
    dialog --msgbox "Installation cancelled." 6 40
    exit 0
fi

log "User confirmed installation, starting..."

# Create a named pipe for progress
PROGRESS_PIPE=$(mktemp -u)
mkfifo $PROGRESS_PIPE
trap "rm -f $PROGRESS_PIPE" EXIT

# Start dialog gauge in background
dialog --title "Installing Arch Linux" --gauge "Preparing..." 10 $WIDTH 0 < $PROGRESS_PIPE &
DIALOG_PID=$!

# Function to update progress
update_progress() {
    local percent=$1
    local message=$2
    echo "$percent"
    echo "# $message"
    log "$message"
} > $PROGRESS_PIPE

# Installation begins
{
    update_progress 0 "Updating system clock..."
    timedatectl set-ntp true || error_exit "Failed to set NTP"
    
    update_progress 5 "Partitioning disk..."
    
    # Determine partition naming
    if [[ ${CONFIG[DISK]} == *"nvme"* ]] || [[ ${CONFIG[DISK]} == *"mmcblk"* ]]; then
        BOOT_PART="${CONFIG[DISK]}p1"
        ROOT_PART="${CONFIG[DISK]}p2"
    else
        BOOT_PART="${CONFIG[DISK]}1"
        ROOT_PART="${CONFIG[DISK]}2"
    fi
    
    log "Boot partition: $BOOT_PART"
    log "Root partition: $ROOT_PART"
    
    wipefs -af ${CONFIG[DISK]} || error_exit "Failed to wipe disk"
    sgdisk -Z ${CONFIG[DISK]} || error_exit "Failed to zap disk"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" ${CONFIG[DISK]} || error_exit "Failed to create boot partition"
    sgdisk -n 2:0:0 -t 2:8309 -c 2:"LUKS" ${CONFIG[DISK]} || error_exit "Failed to create root partition"
    partprobe ${CONFIG[DISK]} || error_exit "Failed to probe partitions"
    sleep 3
    
    update_progress 15 "Formatting boot partition..."
    mkfs.fat -F32 $BOOT_PART || error_exit "Failed to format boot partition"
    
    update_progress 20 "Setting up encryption (this may take a moment)..."
    echo -n "${CONFIG[CRYPT_PASSWORD]}" | cryptsetup luksFormat --type luks2 $ROOT_PART - || error_exit "Failed to encrypt partition"
    echo -n "${CONFIG[CRYPT_PASSWORD]}" | cryptsetup open $ROOT_PART cryptroot - || error_exit "Failed to open encrypted partition"
    
    update_progress 30 "Formatting root partition..."
    mkfs.ext4 -F /dev/mapper/cryptroot || error_exit "Failed to format root partition"
    
    update_progress 35 "Mounting partitions..."
    mount /dev/mapper/cryptroot /mnt || error_exit "Failed to mount root"
    mkdir -p /mnt/boot
    mount $BOOT_PART /mnt/boot || error_exit "Failed to mount boot"
    
    update_progress 40 "Configuring pacman..."
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i 's/^ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
    
    update_progress 45 "Installing base system (5-15 minutes depending on connection)..."
    pacstrap /mnt base base-devel linux linux-firmware networkmanager nano vim grub efibootmgr cryptsetup lvm2 git curl wget || error_exit "Failed to install base system"
    
    update_progress 70 "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab || error_exit "Failed to generate fstab"
    
    update_progress 75 "Configuring system..."
    
    cat << 'CHROOT_EOF' > /mnt/root/configure.sh
#!/bin/bash
set -e

log() {
    echo "[CONFIG] $*"
}

error_exit() {
    echo "[ERROR] $*"
    exit 1
}

log "Setting timezone..."
ln -sf /usr/share/zoneinfo/TIMEZONE_PLACEHOLDER /etc/localtime || error_exit "Failed to set timezone"
hwclock --systohc || error_exit "Failed to sync hardware clock"

log "Generating locale..."
echo "LOCALE_PLACEHOLDER UTF-8" >> /etc/locale.gen
locale-gen || error_exit "Failed to generate locale"
echo "LANG=LOCALE_PLACEHOLDER" > /etc/locale.conf

log "Setting keyboard layout..."
echo "KEYMAP=KEYMAP_PLACEHOLDER" > /etc/vconsole.conf

log "Setting hostname..."
echo "HOSTNAME_PLACEHOLDER" > /etc/hostname
cat > /etc/hosts << 'HOSTS_EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   HOSTNAME_PLACEHOLDER.localdomain HOSTNAME_PLACEHOLDER
HOSTS_EOF

log "Setting root password..."
echo "root:ROOT_PASSWORD_PLACEHOLDER" | chpasswd || error_exit "Failed to set root password"

log "Creating user..."
useradd -m -G wheel -s /bin/bash USERNAME_PLACEHOLDER || error_exit "Failed to create user"
echo "USERNAME_PLACEHOLDER:USER_PASSWORD_PLACEHOLDER" | chpasswd || error_exit "Failed to set user password"

log "Configuring sudo..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

log "Configuring mkinitcpio for encryption..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P || error_exit "Failed to generate initramfs"

log "Getting UUID for encrypted partition..."
CRYPT_UUID=$(blkid -s UUID -o value ROOT_PART_PLACEHOLDER)
log "Encrypted partition UUID: $CRYPT_UUID"

log "Configuring GRUB..."
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=${CRYPT_UUID}:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub

log "Installing GRUB to EFI..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ArchLinux --recheck || error_exit "Failed to install GRUB"

log "Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg || error_exit "Failed to generate GRUB config"

log "Enabling NetworkManager..."
systemctl enable NetworkManager || error_exit "Failed to enable NetworkManager"

log "Configuration complete!"
CHROOT_EOF
    
    # Replace placeholders
    sed -i "s|TIMEZONE_PLACEHOLDER|${CONFIG[TIMEZONE]}|g" /mnt/root/configure.sh
    sed -i "s|LOCALE_PLACEHOLDER|${CONFIG[LOCALE]}|g" /mnt/root/configure.sh
    sed -i "s|KEYMAP_PLACEHOLDER|${CONFIG[KEYMAP]}|g" /mnt/root/configure.sh
    sed -i "s|HOSTNAME_PLACEHOLDER|${CONFIG[HOSTNAME]}|g" /mnt/root/configure.sh
    sed -i "s|ROOT_PASSWORD_PLACEHOLDER|${CONFIG[ROOT_PASSWORD]}|g" /mnt/root/configure.sh
    sed -i "s|USERNAME_PLACEHOLDER|${CONFIG[USERNAME]}|g" /mnt/root/configure.sh
    sed -i "s|USER_PASSWORD_PLACEHOLDER|${CONFIG[USER_PASSWORD]}|g" /mnt/root/configure.sh
    sed -i "s|ROOT_PART_PLACEHOLDER|$ROOT_PART|g" /mnt/root/configure.sh
    
    chmod +x /mnt/root/configure.sh
    
    update_progress 80 "Running system configuration in chroot..."
    arch-chroot /mnt /root/configure.sh || error_exit "Failed to configure system"
    rm /mnt/root/configure.sh
    
    update_progress 95 "Verifying installation..."
    
    # Verify critical files exist
    [ -f /mnt/boot/grub/grub.cfg ] || error_exit "GRUB config not found"
    [ -d /mnt/boot/EFI ] || error_exit "EFI directory not found"
    [ -f /mnt/etc/fstab ] || error_exit "fstab not found"
    
    log "Boot files verification:"
    ls -la /mnt/boot/
    ls -la /mnt/boot/EFI/ || true
    
    update_progress 100 "Installation complete!"
    sleep 2
    
} 2>&1 | tee -a "$LOGFILE"

# Wait for dialog to finish
wait $DIALOG_PID

# Success screen
dialog --title "🎉 Installation Complete!" \
    --colors --msgbox "\n\
\Zb\Z2Installation finished successfully!\Zn\n\n\
Your system is now ready.\n\n\
\Zb\Z6Next steps:\Zn\n\
  1. Reboot your system\n\
  2. Remove installation media\n\
  3. Boot into your new system\n\
  4. Install Hyprland and your dotfiles\n\n\
\Zb\Z4System Info:\Zn\n\
  Hostname: ${CONFIG[HOSTNAME]}\n\
  Username: ${CONFIG[USERNAME]}\n\
  Encryption: LUKS2\n\
  Log: $LOGFILE\n\n\
Press OK to reboot now." 22 $WIDTH

log "=== Installation completed successfully ==="

# Cleanup and reboot
umount -R /mnt
cryptsetup close cryptroot
reboot
