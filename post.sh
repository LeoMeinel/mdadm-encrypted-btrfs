#!/bin/bash
###
# File: post.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2023 Leopold Meinel & contributors
# SPDX ID: GPL-3.0-or-later
# URL: https://www.gnu.org/licenses/gpl-3.0-standalone.html
# -----
###

KEYMAP="de-latin1"
KEYLAYOUT="de"

# Fail on error
set -e

# Define functions
sed_exit() {
    echo "ERROR: 'sed' didn't replace, report this @"
    echo "       https://github.com/LeoMeinel/arch-install/issues"
    exit 1
}

# Configure dot-files (setup)
SYSUSER="<INSERT_SYSUSER>"
VIRTUSER="<INSERT_VIRTUSER>"
HOMEUSER="<INSERT_HOMEUSER>"
GUESTUSER="<INSERT_GUESTUSER>"
/dot-files.sh setup
doas su -lc '/dot-files.sh setup' "$VIRTUSER"
doas su -lc '/dot-files.sh setup' "$HOMEUSER"
doas su -lc '/dot-files.sh setup' "$GUESTUSER"
doas su -lc '/dot-files.sh setup-root' root

# Configure clock
doas timedatectl set-ntp true

# Configure $KEYMAP
doas localectl --no-convert set-keymap "$KEYMAP"
doas localectl --no-convert set-x11-keymap "$KEYLAYOUT"

# Configure iptables
# FIXME: Replace with nftables
# References
#
# https://networklessons.com/uncategorized/iptables-example-configuration
# https://linoxide.com/block-common-attacks-iptables/
# https://serverfault.com/questions/199421/how-to-prevent-ip-spoofing-within-iptables
# https://www.cyberciti.biz/tips/linux-iptables-10-how-to-block-common-attack.html
# https://javapipe.com/blog/iptables-ddos-protection/
# https://danielmiessler.com/study/iptables/
# https://inai.de/documents/Perfect_Ruleset.pdf
# https://unix.stackexchange.com/questions/108169/what-is-the-difference-between-m-conntrack-ctstate-and-m-state-state
# https://gist.github.com/jirutka/3742890
# https://www.ripe.net/publications/docs/ripe-431
# https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/security_guide/sect-security_guide-firewalls-malicious_software_and_spoofed_ip_addresses
#
## ipv4
### Flush & delete all chains
doas iptables -F
doas iptables -X
### Set up new chains
doas iptables -L | grep -q "Chain INPUT" ||
    doas iptables -N INPUT
doas iptables -L | grep -q "Chain FORWARD" ||
    doas iptables -N FORWARD
doas iptables -L | grep -q "Chain OUTPUT" ||
    doas iptables -N OUTPUT
### Allow all connections on all chains to start
doas iptables -P INPUT ACCEPT
doas iptables -P FORWARD ACCEPT
doas iptables -P OUTPUT ACCEPT
### Accept loopback
doas iptables -A INPUT -i lo -j ACCEPT
### First packet has to be TCP SYN
doas iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
### Drop all invalid packets
doas iptables -A INPUT -m state --state INVALID -j DROP
doas iptables -A FORWARD -m state --state INVALID -j DROP
doas iptables -A OUTPUT -m state --state INVALID -j DROP
### Block packets with bogus TCP flags
doas iptables -A INPUT -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
doas iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
doas iptables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
doas iptables -A INPUT -p tcp --tcp-flags FIN,ACK FIN -j DROP
doas iptables -A INPUT -p tcp --tcp-flags ACK,URG URG -j DROP
doas iptables -A INPUT -p tcp --tcp-flags ACK,PSH PSH -j DROP
### Drop NULL packets
doas iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
### Drop XMAS packets
doas iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
### Drop excessive TCP RST packets
doas iptables -A INPUT -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT
doas iptables -A INPUT -p tcp --tcp-flags RST RST -j DROP
### Drop SYN-FLOOD packets
doas iptables -A INPUT -p tcp -m state --state NEW -m limit --limit 2/second --limit-burst 2 -j ACCEPT
doas iptables -A INPUT -p tcp -m state --state NEW -j DROP
### Drop fragments
doas iptables -A INPUT -f -j DROP
doas iptables -A FORWARD -f -j DROP
doas iptables -A OUTPUT -f -j DROP
### Drop SYN packets with suspicious MSS value
doas iptables -A INPUT -p tcp -m state --state NEW -m tcpmss ! --mss 536:65535 -j DROP
### Block spoofed packets
doas iptables -A INPUT -s 127.0.0.0/8 ! -i lo -j DROP
### Drop ICMP
doas iptables -A INPUT -p icmp -j DROP
### Allow SMTP
doas iptables -A INPUT -p tcp --dport 25 -j ACCEPT
doas iptables -A INPUT -p tcp --dport 587 -j ACCEPT
### Allow POP & POPS
doas iptables -A INPUT -p tcp --dport 110 -j ACCEPT
doas iptables -A INPUT -p tcp --dport 995 -j ACCEPT
### Allow IMAP & IMAPS
doas iptables -A INPUT -p tcp --dport 143 -j ACCEPT
doas iptables -A INPUT -p tcp --dport 993 -j ACCEPT
### Allow default ktorrent ports (Forward them if not using UPnP)
doas iptables -A INPUT -p tcp --dport 6881 -j ACCEPT
doas iptables -A INPUT -p udp --dport 7881 -j ACCEPT
doas iptables -A INPUT -p udp --dport 8881 -j ACCEPT
### Allow mDNS
doas iptables -A INPUT -p udp --dport 5353 -j ACCEPT
### Allow http & https (for wget)
doas iptables -A INPUT -p tcp --dport 80 -j ACCEPT
doas iptables -A INPUT -p tcp --dport 443 -j ACCEPT
### Allow established connections
doas iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
### Set default policies for chains
doas iptables -P INPUT DROP
doas iptables -P FORWARD ACCEPT
doas iptables -P OUTPUT ACCEPT
## ipv6
### Flush & delete all chains
doas ip6tables -F
doas ip6tables -X
### Set up new chains
doas ip6tables -L | grep -q "Chain INPUT" ||
    doas ip6tables -N INPUT
doas ip6tables -L | grep -q "Chain INPUT" ||
    doas ip6tables -N FORWARD
doas ip6tables -L | grep -q "Chain INPUT" ||
    doas ip6tables -N OUTPUT
### Allow all connections on all chains to start
doas ip6tables -P INPUT ACCEPT
doas ip6tables -P FORWARD ACCEPT
doas ip6tables -P OUTPUT ACCEPT
### Accept loopback
doas ip6tables -A INPUT -i lo -j ACCEPT
### First packet has to be TCP SYN
doas ip6tables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
### Drop all invalid packets
doas ip6tables -A INPUT -m state --state INVALID -j DROP
doas ip6tables -A FORWARD -m state --state INVALID -j DROP
doas ip6tables -A OUTPUT -m state --state INVALID -j DROP
### Block packets with bogus TCP flags
doas ip6tables -A INPUT -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags FIN,ACK FIN -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags ACK,URG URG -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags ACK,PSH PSH -j DROP
### Drop NULL packets
doas ip6tables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
### Drop XMAS packets
doas ip6tables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
### Drop excessive TCP RST packets
doas ip6tables -A INPUT -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT
doas ip6tables -A INPUT -p tcp --tcp-flags RST RST -j DROP
### Drop SYN-FLOOD packets
doas ip6tables -A INPUT -p tcp -m state --state NEW -m limit --limit 2/second --limit-burst 2 -j ACCEPT
doas ip6tables -A INPUT -p tcp -m state --state NEW -j DROP
### Drop fragments
doas ip6tables -A INPUT -m frag -j DROP
doas ip6tables -A FORWARD -m frag -j DROP
doas ip6tables -A OUTPUT -m frag -j DROP
### Drop SYN packets with suspicious MSS value
doas ip6tables -A INPUT -p tcp -m state --state NEW -m tcpmss ! --mss 536:65535 -j DROP
### Block spoofed packets
doas ip6tables -A INPUT -s ::1/128 ! -i lo -j DROP
### Drop ICMP
doas ip6tables -A INPUT -p icmp -j DROP
### Allow SMTP
doas ip6tables -A INPUT -p tcp --dport 25 -j ACCEPT
doas ip6tables -A INPUT -p tcp --dport 587 -j ACCEPT
### Allow POP & POPS
doas ip6tables -A INPUT -p tcp --dport 110 -j ACCEPT
doas ip6tables -A INPUT -p tcp --dport 995 -j ACCEPT
### Allow IMAP & IMAPS
doas ip6tables -A INPUT -p tcp --dport 143 -j ACCEPT
doas ip6tables -A INPUT -p tcp --dport 993 -j ACCEPT
### Allow default ktorrent ports (Forward them if not using UPnP)
doas ip6tables -A INPUT -p tcp --dport 6881 -j ACCEPT
doas ip6tables -A INPUT -p udp --dport 7881 -j ACCEPT
doas ip6tables -A INPUT -p udp --dport 8881 -j ACCEPT
### Allow mDNS
doas ip6tables -A INPUT -p udp --dport 5353 -j ACCEPT
### Allow http & https (for wget)
doas ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT
doas ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
### Allow established connections
doas ip6tables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
### Set default policies for chains
doas ip6tables -P INPUT DROP
doas ip6tables -P FORWARD ACCEPT
doas ip6tables -P OUTPUT ACCEPT
### Save rules to /etc/iptables
doas sh -c 'iptables-save > /etc/iptables/iptables.rules'
doas sh -c 'ip6tables-save > /etc/iptables/ip6tables.rules'
doas chmod 644 /etc/iptables/*.rules

# Configure secureboot
# Prompt user
# This prompt prevents unwanted overrides of already enrolled keys
echo "INFO: To deploy your own keys, don't confirm the next prompt"
read -rp "Overwrite secureboot keys? (Type 'yes' in capital letters): " choice
case "$choice" in
YES)
    if mountpoint -q /boot; then
        doas umount -AR /boot
    fi
    if mountpoint -q /efi; then
        doas umount -AR /efi
    fi
    doas cryptboot mount
    doas cryptboot-efikeys create
    doas cryptboot-efikeys enroll
    doas cryptboot update-grub
    ;;
*)
    {
        echo '#!/bin/bash'
        echo ''
        echo 'EFI_KEYS_DIR="/etc/secureboot/keys"'
        echo 'source "/etc/cryptboot.conf"'
        echo 'read -rp "Have you transferred your keys to $EFI_KEYS_DIR? (Type '"'"'yes'"'"' in capital letters): " choice'
        echo 'case "$choice" in'
        echo 'YES)'
        echo '    if mountpoint -q /boot; then'
        echo '        doas umount -AR /boot'
        echo '    fi'
        echo '    if mountpoint -q /efi; then'
        echo '        doas umount -AR /efi'
        echo '    fi'
        echo '    mkdir -p "$EFI_KEYS_DIR"'
        echo '    doas cryptboot mount'
        echo '    doas cryptboot update-grub'
        echo '    ;;'
        echo '*)'
        echo '    echo "ERROR: User has not transferred keys to $EFI_KEYS_DIR"'
        echo '    exit 1'
        echo '    ;;'
        echo 'esac'
    } >~/secureboot.sh
    chmod 700 ~/secureboot.sh
    echo "WARNING: User aborted enrolling secureboot keys"
    EFI_KEYS_DIR="/etc/secureboot/keys"
    source "/etc/cryptboot.conf"
    echo "         Deploy your own keys in $EFI_KEYS_DIR and run ~/secureboot.sh to sign your bootloader"
    ;;
esac

# Install paru-bin
source ~/.bash_profile
git clone https://aur.archlinux.org/paru-bin.git ~/git/paru-bin
cd ~/git/paru-bin
makepkg -sri --noprogressbar --noconfirm --needed

# Configure paru.conf
## START sed
FILE=/etc/paru.conf
STRING="^#RemoveMake"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/RemoveMake/" "$FILE" || sed_exit
STRING="^#CleanAfter"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/CleanAfter/" "$FILE" || sed_exit
STRING="^#SudoLoop.*"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/SudoLoop = true/" "$FILE" || sed_exit
STRING="^#\[bin\]"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/\[bin\]/" "$FILE" || sed_exit
STRING="^#FileManager =.*"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/FileManager = nvim/" "$FILE" || sed_exit
STRING="^FileManager = nvim"
grep -q "$STRING" "$FILE" &&
    doas sed -i "/$STRING/a FileManagerFlags = '"\'"'-c,\"NvimTreeFocus\"'"\'"" "$FILE" || sed_exit
STRING="^#Sudo =.*"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/Sudo = doas/" "$FILE" || sed_exit
STRING="^#CombinedUpgrade"
grep -q "$STRING" "$FILE" &&
    doas sed -i "/$STRING/a BatchInstall" "$FILE" || sed_exit
## END sed

# Install packages
# FIXME: This can't be tested in a VM
[ -d /sys/class/bluetooth ] &&
    echo "mkinitcpio-bluetooth" >>~/pkgs-post.txt
paru -S --noprogressbar --noconfirm --needed - <~/pkgs-post.txt
paru --noprogressbar --noconfirm -Syu
paru -Scc

# Clean firecfg
doas firecfg --clean

# Configure dot-files (vscodium)
/dot-files.sh vscodium
doas su -lc '/dot-files.sh vscodium' "$VIRTUSER"
doas su -lc '/dot-files.sh vscodium' "$HOMEUSER"
doas su -lc '/dot-files.sh vscodium' "$GUESTUSER"

# Configure firejail
## START sed
FILE=/etc/firejail/firecfg.config
STRING="^code-oss$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#code-oss #arch-install/" "$FILE" || sed_exit
STRING="^code$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#code #arch-install/" "$FILE" || sed_exit
STRING="^codium$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#codium #arch-install/" "$FILE" || sed_exit
STRING="^dnsmasq$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#dnsmasq #arch-install/" "$FILE" || sed_exit
STRING="^ktorrent$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#ktorrent #arch-install/" "$FILE" || sed_exit
STRING="^nextcloud-desktop$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#nextcloud-desktop #arch-install/" "$FILE" || sed_exit
STRING="^nextcloud$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#nextcloud #arch-install/" "$FILE" || sed_exit
STRING="^signal-desktop$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#signal-desktop #arch-install/" "$FILE" || sed_exit
STRING="^spectacle$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#spectacle #arch-install/" "$FILE" || sed_exit
STRING="^vscodium$"
grep -q "$STRING" "$FILE" &&
    doas sed -i "s/$STRING/#vscodium #arch-install/" "$FILE" || sed_exit
## END sed
doas firecfg --add-users root "$SYSUSER" "$VIRTUSER" "$HOMEUSER" "$GUESTUSER"
doas apparmor_parser -r /etc/apparmor.d/firejail-default
doas firecfg
rm -rf ~/.local/share/applications/*
doas su -c 'rm -rf ~/.local/share/applications/*' "$VIRTUSER"
doas su -c 'rm -rf ~/.local/share/applications/*' "$HOMEUSER"
doas su -c 'rm -rf ~/.local/share/applications/*' "$GUESTUSER"

# Configure /etc/mkinitcpio.conf
pacman -Qq mkinitcpio-bluetooth &&
    {
        ## START sed
        FILE=/etc/mkinitcpio.conf
        STRING0="^HOOKS=.*"
        grep -q "$STRING0" "$FILE" &&
            {
                STRING1="encrypt"
                grep -q "$STRING1" "$FILE" &&
                    doas sed -i "/$STRING0/s/$STRING1/bluetooth $STRING1/" "$FILE" || sed_exit
            }
        ## END sed
    }

# Enable systemd services
pacman -Qq "iptables" &&
    {
        doas systemctl enable ip6tables
        doas systemctl enable iptables
    }
pacman -Qq "sddm" &&
    doas systemctl enable sddm

# Enable systemd user services
pacman -Qq "usbguard-notifier" &&
    systemctl enable --user usbguard-notifier.service

# Setup /boot & /efi
doas mkinitcpio -P
doas grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
doas grub-mkconfig -o /boot/grub/grub.cfg

# Remove repo
rm -rf ~/git

# Remove scripts
doas rm -f /dot-files.sh
doas rm -f /root/.bash_history
rm -f ~/.bash_history
rm -f ~/pkgs-post.txt
rm -f ~/post.sh
