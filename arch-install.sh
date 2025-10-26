#!/bin/bash

# Arch Linux Encrypted Installation - Interactive TUI
# Usage: curl -sL <url> | bash

set -e

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
    dialog --title "Error" --msgbox "This script requires UEFI mode.\n\nPlease boot in UEFI mode." 8 $WIDTH
    exit 1
fi

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

# Keyboard layout - default to US
CONFIG[KEYMAP]="us"
loadkeys ${CONFIG[KEYMAP]}

dialog --infobox "Keyboard layout set to: US" 4 40
sleep 1

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

# Confirm disk
dialog --title "⚠️  CONFIRMATION REQUIRED" \
    --colors --yesno "\n\
\Zb\Z1WARNING: ALL DATA ON ${CONFIG[DISK]} WILL BE DESTROYED!\Zn\n\n\
This action cannot be undone.\n\n\
Do you want to continue?" 11 $WIDTH

if [ $? -ne 0 ]; then
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

# Hostname
dialog --title "Hostname" \
    --inputbox "Enter hostname for this machine:" \
    10 $WIDTH "archlinux" 2> $TEMP_FILE

CONFIG[HOSTNAME]=$(cat $TEMP_FILE)

# Username
dialog --title "User Account" \
    --inputbox "Enter username:" \
    10 $WIDTH "" 2> $TEMP_FILE

CONFIG[USERNAME]=$(cat $TEMP_FILE)

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
    dialog --msgbox "Installation cancelled." 6 40
    exit 0
fi

# Installation begins
(
    echo "0" ; echo "# Updating system clock..." ; sleep 1
    timedatectl set-ntp true
    
    echo "5" ; echo "# Partitioning disk..." ; sleep 1
    # Determine partition naming
    if [[ ${CONFIG[DISK]} == *"nvme"* ]] || [[ ${CONFIG[DISK]} == *"mmcblk"* ]]; then
        BOOT_PART="${CONFIG[DISK]}p1"
        ROOT_PART="${CONFIG[DISK]}p2"
    else
        BOOT_PART="${CONFIG[DISK]}1"
        ROOT_PART="${CONFIG[DISK]}2"
    fi
    
    wipefs -af ${CONFIG[DISK]} 2>&1 | grep -v "^$"
    sgdisk -Z ${CONFIG[DISK]} 2>&1 | grep -v "^$"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" ${CONFIG[DISK]} 2>&1 | grep -v "^$"
    sgdisk -n 2:0:0 -t 2:8309 -c 2:"LUKS" ${CONFIG[DISK]} 2>&1 | grep -v "^$"
    partprobe ${CONFIG[DISK]}
    sleep 2
    
    echo "15" ; echo "# Formatting boot partition..." ; sleep 1
    mkfs.fat -F32 $BOOT_PART 2>&1 | grep -v "^$"
    
    echo "20" ; echo "# Setting up encryption (this may take a moment)..." ; sleep 1
    echo -n "${CONFIG[CRYPT_PASSWORD]}" | cryptsetup luksFormat --type luks2 $ROOT_PART - 2>&1 | grep -v "^$"
    echo -n "${CONFIG[CRYPT_PASSWORD]}" | cryptsetup open $ROOT_PART cryptroot - 2>&1 | grep -v "^$"
    
    echo "30" ; echo "# Formatting root partition..." ; sleep 1
    mkfs.ext4 /dev/mapper/cryptroot 2>&1 | grep -v "^$"
    
    echo "35" ; echo "# Mounting partitions..." ; sleep 1
    mount /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/boot
    mount $BOOT_PART /mnt/boot
    
    echo "40" ; echo "# Configuring pacman..." ; sleep 1
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i 's/^ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
    
    echo "45" ; echo "# Installing base system (this will take several minutes)..." ; sleep 1
    pacstrap /mnt base base-devel linux linux-firmware networkmanager nano vim grub efibootmgr cryptsetup lvm2 git curl wget 2>&1 | \
        stdbuf -oL tr '\r' '\n' | grep -E "installing|upgrading" | tail -1
    
    echo "70" ; echo "# Generating fstab..." ; sleep 1
    genfstab -U /mnt >> /mnt/etc/fstab
    
    echo "75" ; echo "# Configuring system..." ; sleep 1
    
    cat << CHROOT_EOF > /mnt/root/configure.sh
#!/bin/bash
set -e

ln -sf /usr/share/zoneinfo/${CONFIG[TIMEZONE]} /etc/localtime
hwclock --systohc

echo "${CONFIG[LOCALE]} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${CONFIG[LOCALE]}" > /etc/locale.conf

echo "KEYMAP=${CONFIG[KEYMAP]}" > /etc/vconsole.conf

echo "${CONFIG[HOSTNAME]}" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${CONFIG[HOSTNAME]}.localdomain ${CONFIG[HOSTNAME]}
HOSTS_EOF

echo "root:${CONFIG[ROOT_PASSWORD]}" | chpasswd

useradd -m -G wheel -s /bin/bash ${CONFIG[USERNAME]}
echo "${CONFIG[USERNAME]}:${CONFIG[USER_PASSWORD]}" | chpasswd

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P >/dev/null 2>&1

CRYPT_UUID=\$(blkid -s UUID -o value $ROOT_PART)
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=\${CRYPT_UUID}:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB >/dev/null 2>&1
grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1

systemctl enable NetworkManager >/dev/null 2>&1

echo "done"
CHROOT_EOF
    
    chmod +x /mnt/root/configure.sh
    arch-chroot /mnt /root/configure.sh
    rm /mnt/root/configure.sh
    
    echo "95" ; echo "# Cleaning up..." ; sleep 1
    
    echo "100" ; echo "# Installation complete!" ; sleep 1
    
) | dialog --title "Installing Arch Linux" --gauge "Preparing..." 10 $WIDTH 0

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
  Encryption: LUKS2\n\n\
Press OK to reboot now." 20 $WIDTH

# Cleanup and reboot
umount -R /mnt
reboot
