#!/bin/bash
###
# File: setup.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2023 Leopold Meinel & contributors
# SPDX ID: GPL-3.0-or-later
# URL: https://www.gnu.org/licenses/gpl-3.0-standalone.html
# -----
###

# Source config
SCRIPT_DIR="$(dirname -- "$(readlink -f -- "$0")")"
source "$SCRIPT_DIR/install.conf"

# Fail on error
set -eu

# Define functions
sed_exit() {
    echo "ERROR: 'sed' didn't replace, report this @"
    echo "       https://github.com/leomeinel/arch-install/issues"
    exit 1
}

# Add groups & users
## START sed
FILE=/etc/default/useradd
STRING="^SHELL=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/SHELL=\/bin\/bash/" "$FILE"
## END sed
groupadd -r audit
groupadd -r usbguard
useradd -ms /bin/bash -G adm,audit,log,rfkill,sys,systemd-journal,usbguard,wheel,video "$SYSUSER"
useradd -ms /bin/bash -G video "$HOMEUSER"
useradd -ms /bin/bash -G video "$GUESTUSER"
echo "Enter password for root"
passwd root
echo "Enter password for $SYSUSER"
passwd "$SYSUSER"
echo "Enter password for $HOMEUSER"
passwd "$HOMEUSER"
echo "Enter password for $GUESTUSER"
passwd "$GUESTUSER"

# Setup /etc
rsync -rq /git/arch-install/etc/ /etc
## Configure locale in /etc/locale.gen /etc/locale.conf
### START sed
FILE=/etc/locale.gen
STRING="^#de_DE.UTF-8 UTF-8"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/de_DE.UTF-8 UTF-8/" "$FILE"
STRING="^#en_US.UTF-8 UTF-8"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/en_US.UTF-8 UTF-8/" "$FILE"
STRING="^#en_DK.UTF-8 UTF-8"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/en_DK.UTF-8 UTF-8/" "$FILE"
STRING="^#fr_FR.UTF-8 UTF-8"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/fr_FR.UTF-8 UTF-8/" "$FILE"
STRING="^#nl_NL.UTF-8 UTF-8"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/nl_NL.UTF-8 UTF-8/" "$FILE"
### END sed
chmod 644 /etc/locale.conf
locale-gen
## Configure /etc/doas.conf
chown root:root /etc/doas.conf
chmod 0400 /etc/doas.conf
## Configure random MAC address for WiFi in /etc/NetworkManager/conf.d/50-mac-random.conf
chmod 644 /etc/NetworkManager/conf.d/50-mac-random.conf
## Configure pacman hooks in /etc/pacman.d/hooks
{
    echo '#!/bin/sh'
    echo ''
    echo '/usr/bin/firecfg >/dev/null 2>&1'
    echo "/usr/bin/su -c '/usr/bin/rm -rf ~/.local/share/applications/*' $SYSUSER"
    echo "/usr/bin/su -c '/usr/bin/rm -rf ~/.local/share/applications/*' $HOMEUSER"
    echo "/usr/bin/su -c '/usr/bin/rm -rf ~/.local/share/applications/*' $GUESTUSER"
    echo ''
} >/etc/pacman.d/hooks/scripts/70-firejail.sh
chmod 755 /etc/pacman.d/hooks
chmod 755 /etc/pacman.d/hooks/scripts
chmod 644 /etc/pacman.d/hooks/*.hook
chmod 744 /etc/pacman.d/hooks/scripts/*.sh
## Configure /etc/systemd/zram-generator.conf
chmod 644 /etc/systemd/zram-generator.conf
## Configure /etc/sysctl.d
chmod 755 /etc/sysctl.d
chmod 644 /etc/sysctl.d/*
## Configure /etc/systemd/system/snapper-cleanup.timer.d/override.conf
chmod 644 /etc/systemd/system/snapper-cleanup.timer.d/override.conf
## Configure /etc/pacman.conf /etc/makepkg.conf /etc/xdg/reflector/reflector.conf
{
    echo "--save /etc/pacman.d/mirrorlist"
    echo "--country $MIRRORCOUNTRIES"
    echo "--protocol https"
    echo "--latest 20"
    echo "--sort rate"
} >/etc/xdg/reflector/reflector.conf
chmod 644 /etc/xdg/reflector/reflector.conf
### START sed
FILE=/etc/makepkg.conf
STRING="^#PACMAN_AUTH=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/PACMAN_AUTH=(doas)/" "$FILE"
###
FILE=/etc/pacman.conf
STRING="^#Color"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/Color/" "$FILE"
STRING="^#ParallelDownloads =.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/ParallelDownloads = 10/" "$FILE"
STRING="^#CacheDir"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/CacheDir/" "$FILE"
### END sed
{
    echo ""
    echo "# Custom"
    echo "[multilib]"
    echo "Include = /etc/pacman.d/mirrorlist"
} >>/etc/pacman.conf
pacman-key --init
## Update mirrors
reflector --save /etc/pacman.d/mirrorlist --country "$MIRRORCOUNTRIES" --protocol https --latest 20 --sort rate

# Install packages
pacman -Syu --noprogressbar --noconfirm --needed - </git/arch-install/pkgs-setup.txt

# Configure $SYSUSER
## Run sysuser.sh
chmod +x /git/arch-install/sysuser.sh
su -c '/git/arch-install/sysuser.sh' "$SYSUSER"
cp /git/arch-install/dot-files.sh /
chmod 777 /dot-files.sh

# Configure /etc
## Configure /etc/crypttab
DISK1="$(lsblk -npo PKNAME $(findmnt -no SOURCE --target /efi) | tr -d "[:space:]")"
DISK1P2="$(lsblk -rnpo TYPE,NAME "$DISK1" | grep "part" | sed 's/part//' | sed -n '2p' | tr -d "[:space:]")"
MD0UUID="$(blkid -s UUID -o value $DISK1P2)"
{
    echo "md0_crypt UUID=$MD0UUID none initramfs,luks,key-slot=0"
} >/etc/crypttab
## Configure /etc/localtime /etc/vconsole.conf /etc/hostname /etc/hosts
ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
hwclock --systohc
echo "KEYMAP=$KEYMAP" >/etc/vconsole.conf
echo "$HOSTNAME" >/etc/hostname
{
    echo "127.0.0.1  localhost"
    echo "127.0.1.1  $HOSTNAME.$DOMAIN	$HOSTNAME"
    echo "::1  ip6-localhost ip6-loopback"
    echo "ff02::1  ip6-allnodes"
    echo "ff02::2  ip6-allrouters"
} >/etc/hosts
## Configure /etc/fwupd/uefi_capsule.conf
{
    echo ""
    echo "# Custom"
    echo "## Set /efi as mountpoint"
    echo "OverrideESPMountPoint=/efi"
} >>/etc/fwupd/uefi_capsule.conf
## Configure /etc/cryptboot.conf
git clone https://github.com/leomeinel/cryptboot.git /git/cryptboot
cp /git/cryptboot/cryptboot.conf /etc/
chmod 644 /etc/cryptboot.conf
## Configure /etc/ssh/sshd_config
{
    echo ""
    echo "# Override"
    echo "PasswordAuthentication no"
    echo "AuthenticationMethods publickey"
    echo "PermitRootLogin no"
    echo "AllowTcpForwarding no"
    echo "ClientAliveCountMax 2"
    echo "LogLevel VERBOSE"
    echo "MaxAuthTries 3"
    echo "MaxSessions 2"
    echo "Port 9122"
    echo "TCPKeepAlive no"
    echo "AllowAgentForwarding no"
} >>/etc/ssh/sshd_config
## Configure /etc/xdg/user-dirs.defaults
### START sed
FILE=/etc/xdg/user-dirs.defaults
STRING="^TEMPLATES=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s|$STRING|TEMPLATES=Documents/Templates|" "$FILE"
STRING="^PUBLICSHARE=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s|$STRING|PUBLICSHARE=Documents/Public|" "$FILE"
STRING="^DESKTOP=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s|$STRING|DESKTOP=Desktop|" "$FILE"
STRING="^MUSIC=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s|$STRING|MUSIC=Documents/Music|" "$FILE"
STRING="^PICTURES=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s|$STRING|PICTURES=Documents/Pictures|" "$FILE"
STRING="^VIDEOS=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s|$STRING|VIDEOS=Documents/Videos|" "$FILE"
### END sed
## Configure /etc/usbguard/usbguard-daemon.conf /etc/usbguard/rules.conf
usbguard generate-policy >/etc/usbguard/rules.conf
usbguard add-user -g usbguard --devices=modify,list,listen --policy=list --exceptions=listen
## Configure /etc/pam.d/system-login /etc/security/faillock.conf /etc/pam.d/su /etc/pam.d/su-l
echo "auth optional pam_faildelay.so delay=8000000" >>/etc/pam.d/system-login
### START sed
FILE=/etc/security/faillock.conf
STRING="^#.*dir.*=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s|$STRING|dir = /var/lib/faillock|" "$FILE"
### END sed
echo "auth required pam_wheel.so use_uid" >>/etc/pam.d/su
echo "auth required pam_wheel.so use_uid" >>/etc/pam.d/su-l
## Configure /etc/audit/auditd.conf
### START sed
FILE=/etc/audit/auditd.conf
STRING="^log_group.*=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/log_group = audit/" "$FILE"
### END sed
## mDNS
### Configure /etc/systemd/resolved.conf
### START sed
FILE=/etc/systemd/resolved.conf
STRING="^#MulticastDNS=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/MulticastDNS=no/" "$FILE"
### END sed
### Configure /etc/nsswitch.conf
### START sed
FILE=/etc/nsswitch.conf
STRING="^hosts: mymachines"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/hosts: mymachines mdns_minimal [NOTFOUND=return]/" "$FILE"
### END sed
## Configure /etc/bluetooth/main.conf
### START sed
FILE=/etc/bluetooth/main.conf
STRING="^#AutoEnable=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/AutoEnable=true/" "$FILE"
### END sed
## Configure /etc/dracut.conf.d/modules.conf
{
    echo "filesystems+=\" btrfs \""
} >/etc/dracut.conf.d/modules.conf
## Configure /etc/dracut.conf.d/cmdline.conf
DISK1P2UUID="$(blkid -s UUID -o value "$DISK1P2")"
PARAMETERS="rd.luks.uuid=luks-$MD0UUID rd.lvm.lv=vg0/lv0 rd.md.uuid=$DISK1P2UUID root=/dev/mapper/vg0-lv0 rootfstype=btrfs rootflags=rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=256,subvol=/@ rd.lvm.lv=vg0/lv1 rd.lvm.lv=vg0/lv2 rd.lvm.lv=vg0/lv3 rd.luks.allow-discards=$DISK1P2UUID rd.vconsole.unicode rd.vconsole.keymap=$KEYMAP loglevel=5 rd.info rd.shell bgrt_disable audit=1 lsm=landlock,lockdown,yama,integrity,apparmor,bpf iommu=pt zswap.enabled=0 lockdown=integrity module.sig_enforce=1"
#### If on intel set kernel parameter intel_iommu=on
pacman -Qq "intel-ucode" >/dev/null 2>&1 &&
    PARAMETERS="${PARAMETERS} intel_iommu=on"
echo "kernel_cmdline=\"$PARAMETERS\"" >/etc/dracut.conf.d/cmdline.conf
chmod 644 /etc/dracut.conf.d/*.conf

# Setup /usr
rsync -rq /git/arch-install/usr/ /usr
cp /git/cryptboot/systemd-boot-sign /usr/local/bin/
cp /git/cryptboot/cryptboot /usr/local/bin/
cp /git/cryptboot/cryptboot-efikeys /usr/local/bin/
## Configure /usr/share/gruvbox/gruvbox.yml
chmod 755 /usr/share/gruvbox
chmod 644 /usr/share/gruvbox/gruvbox.yml
## Configure /usr/local/bin
chmod 755 /usr/local/bin/cryptboot
chmod 755 /usr/local/bin/cryptboot-efikeys
chmod 755 /usr/local/bin/systemd-boot-sign
ln -s "$(which nvim)" /usr/local/bin/edit
ln -s "$(which nvim)" /usr/local/bin/vedit
ln -s "$(which nvim)" /usr/local/bin/vi
ln -s "$(which nvim)" /usr/local/bin/vim
chmod 755 /usr/local/bin/ex
chmod 755 /usr/local/bin/sway-logout
chmod 755 /usr/local/bin/view
chmod 755 /usr/local/bin/vimdiff
chmod 755 /usr/local/bin/edit
chmod 755 /usr/local/bin/vedit
chmod 755 /usr/local/bin/vi
chmod 755 /usr/local/bin/vim

# Configure /usr
## Configure /usr/share/snapper/config-templates/default & configure snapper configs
### Setup configs
#### /usr/share/snapper/config-templates/default
##### START sed
STRING0="^ALLOW_GROUPS=.*"
STRING1="^SPACE_LIMIT=.*"
STRING2="^FREE_LIMIT=.*"
STRING3="^NUMBER_LIMIT=.*"
STRING4="^NUMBER_LIMIT_IMPORTANT=.*"
STRING5="^TIMELINE_CREATE=.*"
STRING6="^TIMELINE_CLEANUP=.*"
STRING7="^TIMELINE_LIMIT_MONTHLY=.*"
STRING8="^TIMELINE_LIMIT_YEARLY=.*"
#####
FILE0=/usr/share/snapper/config-templates/default
grep -q "$STRING0" "$FILE0" || sed_exit
sed -i "s/$STRING0/ALLOW_GROUPS=\"wheel\"/" "$FILE0"
grep -q "$STRING1" "$FILE0" || sed_exit
sed -i "s/$STRING1/SPACE_LIMIT=\"0.2\"/" "$FILE0"
grep -q "$STRING2" "$FILE0" || sed_exit
sed -i "s/$STRING2/FREE_LIMIT=\"0.4\"/" "$FILE0"
grep -q "$STRING3" "$FILE0" || sed_exit
sed -i "s/$STRING3/NUMBER_LIMIT=\"5\"/" "$FILE0"
grep -q "$STRING4" "$FILE0" || sed_exit
sed -i "s/$STRING4/NUMBER_LIMIT_IMPORTANT=\"5\"/" "$FILE0"
grep -q "$STRING5" "$FILE0" || sed_exit
sed -i "s/$STRING5/TIMELINE_CREATE=\"yes\"/" "$FILE0"
grep -q "$STRING6" "$FILE0" || sed_exit
sed -i "s/$STRING6/TIMELINE_CLEANUP=\"yes\"/" "$FILE0"
grep -q "$STRING7" "$FILE0" || sed_exit
sed -i "s/$STRING7/TIMELINE_LIMIT_MONTHLY=\"0\"/" "$FILE0"
grep -q "$STRING8" "$FILE0" || sed_exit
sed -i "s/$STRING8/TIMELINE_LIMIT_YEARLY=\"0\"/" "$FILE0"
##### END sed
### Remove & unmount snapshots (Prepare snapshot dirs 1)
for subvolume in "${SUBVOLUMES[@]}"; do
    umount "$subvolume".snapshots
    rm -rf "$subvolume".snapshots
done
####### START sed
STRING0="^TIMELINE_LIMIT_HOURLY=.*"
STRING1="^TIMELINE_LIMIT_DAILY=.*"
#######
SUBVOLUMES_LENGTH="${#SUBVOLUMES[@]}"
[[ "$SUBVOLUMES_LENGTH" -ne ${#CONFIGS[@]} ]] &&
    {
        echo "ERROR: SUBVOLUMES and CONFIGS aren't the same length!"
        exit 1
    }
for ((i = 0; i < SUBVOLUMES_LENGTH; i++)); do
    #### Copy template
    FILE1="/usr/share/snapper/config-templates/${CONFIGS[$i]}"
    cp "$FILE0" "$FILE1"
    chmod 644 "$FILE1"
    #### Set variables for configs
    case "${CONFIGS[$i]}" in
    "var_cache" | "var_games" | "var_log")
        HOURLY=1
        DAILY=1
        ;;
    "var" | "var_lib" | "var_lib_docker")
        HOURLY=2
        DAILY=2
        ;;
    "home")
        HOURLY=3
        DAILY=2
        ;;
    *)
        HOURLY=2
        DAILY=1
        ;;
    esac
    #######
    grep -q "$STRING0" "$FILE1" || sed_exit
    sed -i "s/$STRING0/TIMELINE_LIMIT_HOURLY=\"$HOURLY\"/" "$FILE1"
    grep -q "$STRING1" "$FILE1" || sed_exit
    sed -i "s/$STRING1/TIMELINE_LIMIT_DAILY=\"$DAILY\"/" "$FILE1"
    ####### END sed
    #### Create config
    snapper --no-dbus -c "${CONFIGS[$i]}" create-config -t "${CONFIGS[$i]}" "${SUBVOLUMES[$i]}"
done
### Replace subvolumes for snapshots (Prepare snapshot dirs 2)
for subvolume in "${SUBVOLUMES[@]}"; do
    btrfs subvolume delete "$subvolume".snapshots
    mkdir -p "$subvolume".snapshots
done
#### Mount /etc/fstab
mount -a
### Set correct permissions on snapshots (Prepare snapshot dirs 3)
for subvolume in "${SUBVOLUMES[@]}"; do
    chmod 755 "$subvolume".snapshots
    chown :wheel "$subvolume".snapshots
done
## Configure /usr/share/wallpapers/Custom/content
mkdir -p /usr/share/wallpapers/Custom/content
git clone https://github.com/leomeinel/wallpapers.git /git/wallpapers
cp /git/wallpapers/*.jpg /git/wallpapers/*.png /usr/share/wallpapers/Custom/content/
chmod 755 /usr/share/wallpapers/Custom
chmod 755 /usr/share/wallpapers/Custom/content
chmod 644 /usr/share/wallpapers/Custom/content/*

# Configure /var
## Configure /var/games
chown :games /var/games

# Setup /efi
rsync -rq /git/arch-install/efi/ /efi
chmod 644 /efi/loader/loader.conf

# Enable systemd services
pacman -Qq "apparmor" >/dev/null 2>&1 &&
    {
        systemctl enable apparmor.service
        systemctl enable auditd.service
    }
pacman -Qq "avahi" >/dev/null 2>&1 &&
    systemctl enable avahi-daemon
pacman -Qq "bluez" >/dev/null 2>&1 &&
    systemctl enable bluetooth
pacman -Qq "cups" >/dev/null 2>&1 &&
    systemctl enable cups.service
pacman -Qq "util-linux" >/dev/null 2>&1 &&
    systemctl enable fstrim.timer
pacman -Qq "networkmanager" >/dev/null 2>&1 &&
    systemctl enable NetworkManager
pacman -Qq "reflector" >/dev/null 2>&1 &&
    {
        systemctl enable reflector
        systemctl enable reflector.timer
    }
pacman -Qq "snapper" >/dev/null 2>&1 &&
    {
        systemctl enable snapper-cleanup.timer
        systemctl enable snapper-timeline.timer
    }
pacman -Qq "systemd" >/dev/null 2>&1 &&
    systemctl enable systemd-boot-update.service
pacman -Qq "usbguard" >/dev/null 2>&1 &&
    systemctl enable usbguard.service

# Setup /boot & /efi
if udevadm info -q property --property=ID_BUS --value "$DISK1" | grep -q "usb"; then
    bootctl --esp-path=/efi --no-variables install
else
    bootctl --esp-path=/efi install
fi
dracut --regenerate-all

# Remove repo
rm -rf /git
