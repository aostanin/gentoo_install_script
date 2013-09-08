#! /usr/bin/env bash

SCRIPT_PARAMS=$@

#GENTOO_MIRROR=http://ftp.jaist.ac.jp/pub/Linux/Gentoo/
GENTOO_MIRROR=http://ftp.iij.ad.jp/pub/linux/gentoo/
GENTOO_STAGE3=releases/amd64/current-stage3/stage3-amd64-20130620.tar.bz2
MOUNT_LOCATION=/mnt/gentoo
TIMEZONE=Asia/Tokyo

CFLAGS="-march=core2 -O2 -pipe"

# Options
INSTALL_PREP=false
INSTALL_CHROOT=false

# Gentoo Options
ROOT_DISK_PARTITION=/dev/sda
SWAP_DISK_PARTITION=/dev/sdb
GRUB_DISK=/dev/sda
ROOT_PARTITION_FS_TYPE=ext4
HOSTNAME=gentoo
DOMAINNAME=localdomain
ROOT_PASSWORD=gentoo
INSTALL_KERNEL=false
INSTALL_GRUB=false

SOURCE="${PWD}/${BASH_SOURCE[0]}"

usage ()
{
    cat << EOF
usage: $0 options

This script can boostrap a Gentoo machine for running puppet.

OPTIONS:
    -h      Show this message
    -i      Install Gentoo Linux

FULL INSTALL OPTIONS:
    -c      Continue install of Gentoo from chroot (used internally)
    -d      Root disk partition to use (default $ROOT_DISK_PARTITION)
    -s      Swap disk partition to use (default $SWAP_DISK_PARTITION)
    -j      Disk to install grub on (default $GRUB_DISK)
    -n      Hostname (default $HOSTNAME)
    -m      Domainname (default $DOMAINNAME)
    -k      Install kernel (default $INSTALL_KERNEL)
    -g      Install grub (default $INSTALL_GRUB)
EOF
}

message ()
{
    echo
    echo -e " \x1b[01;34m>>> \x1b[01;31m" $@ "\x1b[00m"
}

command ()
{
    echo -e "\x1b[01;36m$@\x1b[00m"
    $@
    if [ $? -ne 0 ]; then
        echo -e "\x1b[01:31mFailed\x1b[00m"
        exit 1
    fi
}

install_gentoo_prep ()
{
    message Installing gentoo

    #
    # Setup disk
    #

    ROOT_DISK_SIZE=$(($(blockdev --getsize64 $ROOT_DISK_PARTITION) / 1048576))
    SWAP_DISK_SIZE=$(($(blockdev --getsize64 $SWAP_DISK_PARTITION) / 1048576))

    message Root: $ROOT_DISK_SIZE MB
    message Swap: $SWAP_DISK_SIZE MB

    command mkfs.${ROOT_PARTITION_FS_TYPE} ${ROOT_DISK_PARTITION}
    command mkswap ${SWAP_DISK_PARTITION}
    command swapon ${SWAP_DISK_PARTITION}

    #
    # Mount Disk
    #

    command mkdir -p $MOUNT_LOCATION
    command mount ${ROOT_DISK_PARTITION} $MOUNT_LOCATION

    #
    # Stage Tarball
    #

    command cd $MOUNT_LOCATION

    # latest-stage3-amd64.txt is currently BROKEN! Use hardcoded value instead.
    #LATEST_STAGE3=$(curl --silent ${GENTOO_MIRROR}releases/amd64/autobuilds/latest-stage3-amd64.txt | awk 'END{print}')
    #LATEST_STAGE3=${GENTOO_MIRROR}releases/amd64/autobuilds/${LATEST_STAGE3}
    LATEST_STAGE3=${GENTOO_MIRROR}${GENTOO_STAGE3}

    message Downloading stage 3 tarball from $LATEST_STAGE3
    command curl -O $LATEST_STAGE3

    message Extracting stage 3 tarball
    command tar xjpf stage3-*.tar.bz2

    #
    # Portage Snapshot
    #

    LATEST_PORTAGE=${GENTOO_MIRROR}snapshots/portage-latest.tar.bz2

    message Downloading portage snapshot from $LATEST_PORTAGE
    command curl -O $LATEST_PORTAGE

    message Extracting portage snapshot
    command tar xjf portage-latest.tar.bz2 -C ${MOUNT_LOCATION}/usr

    #
    # Basic Configuration
    #

    message Doing basic configuration

    cat << EOF > ${MOUNT_LOCATION}/etc/portage/make.conf
CFLAGS="${CFLAGS}"
CXXFLAGS="${CFLAGS}"
CHOST="x86_64-pc-linux-gnu"
USE="bindist mmx sse sse2"
EOF

    #
    # Chroot
    #

    message Preparing to chroot

    command cp -L /etc/resolv.conf ${MOUNT_LOCATION}/etc/

    command mount -t proc none ${MOUNT_LOCATION}/proc
    command mount --rbind /sys ${MOUNT_LOCATION}/sys
    command mount --rbind /dev ${MOUNT_LOCATION}/dev

    message Copying chroot script

    command cp $SOURCE ${MOUNT_LOCATION}/bootstrap.sh
    command chmod +x ${MOUNT_LOCATION}/bootstrap.sh

    message Chrooting

    command chroot $MOUNT_LOCATION /bootstrap.sh "${SCRIPT_PARAMS/-i/-c}"

    message Returned from chroot

    command umount -l /mnt/gentoo{/dev,/proc,/sys,}
    command swapoff ${SWAP_DISK_PARTITION}
}

install_gentoo_chroot ()
{
    command env-update
    command source /etc/profile

    #
    # Install
    #

    message Syncing portage
    command emerge --quiet --sync

    message Setting profile
    command eselect profile set 1

    message Setting timezone
    command ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
    echo "${TIMEZONE}" >> /etc/timezone

    if $INSTALL_KERNEL; then
        message Installing the kernel sources
        command emerge --quiet-build gentoo-sources genkernel

        message Compiling kernel sources
        command genkernel --no-mountboot all
    fi

    #
    # Configuring
    #

    message Configuring

    cat << EOF > /etc/fstab
${ROOT_DISK_PARTITION}   /       ext4    noatime     0 2
${SWAP_DISK_PARTITION}   none    swap    sw          0 0
EOF

    cat << EOF > /etc/hosts
127.0.0.1       ${HOSTNAME}.${DOMAINNAME} ${HOSTNAME} localhost
::1             ${HOSTNAME}.${DOMAINNAME} ${HOSTNAME} localhost
EOF

    sed s/localhost/${HOSTNAME}/g -i /etc/conf.d/hostname
    echo dns_domain=\"${DOMAINNAME}\" >> /etc/conf.d/net
    cd /etc/init.d && ln -s net.lo net.eth0 && cd -
    command rc-update add net.eth0 default

    ( echo $ROOT_PASSWORD ; echo $ROOT_PASSWORD ) | passwd

    command rc-update add sshd default
    command emerge --quiet-build dhcpcd

    if $INSTALL_GRUB; then
        command emerge --quiet-build grub

        KERNEL=$(ls /boot/kernel-*)
        INITRD=$(ls /boot/initramfs-*)
        cat << EOF > /boot/grub/grub.conf
default 0
timeout 10

title Gentoo Linux
root (hd0,0)
kernel ${KERNEL} root=/dev/ram0 real_root=${ROOT_DISK_PARTITION}
initrd ${INITRD}
EOF

        grep -v rootfs /proc/mounts > /etc/mtab
        command grub-install --no-floppy ${GRUB_DISK}
    fi

    message Done installing

    command rm /stage3-*.tar.bz2
    command rm /portage-latest.tar.bz2
    command rm /bootstrap.sh
}

while getopts "hicd:s:n:m:gj:k" OPTION; do
    case $OPTION in
        i)  INSTALL_PREP=true
            ;;

        c)  INSTALL_CHROOT=true
            ;;
        d)  ROOT_DISK_PARTITION=$OPTARG
            ;;
        s)  SWAP_DISK_PARTITION=$OPTARG
            ;;
        n)  HOSTNAME=$OPTARG
            ;;
        m)  DOMAINNAME=$OPTARG
            ;;
        g)  INSTALL_GRUB=true
            ;;
        k)  INSTALL_KERNEL=true
            ;;
        j)  GRUB_DISK=$OPTARG
            ;;

        h)  usage
            exit
            ;;
        *)  usage
            exit 1
            ;;
    esac
done

if $INSTALL_PREP; then
    install_gentoo_prep
elif $INSTALL_CHROOT; then
    install_gentoo_chroot
else
    usage
fi

