# gentoo install script

## Description

This is a simple install script for Gentoo Linux. I mainly used it for quickly installing virtual machines, but it also worked well for a laptop as well. It uses the server profile and assumes an amd64 system by default. It is probably best to adapt this script to your needs rather than using it as-is.

## Usage

First set up your disks by partitioning them. The script will make a filesystem and mount the partitions for you.

Make sure to edit the top of the script to suite your needs.

```
usage: ./install.sh options

This script can boostrap a Gentoo machine for running puppet.

OPTIONS:
    -h      Show this message
    -i      Install Gentoo Linux

FULL INSTALL OPTIONS:
    -c      Continue install of Gentoo from chroot (used internally)
    -d      Root disk partition to use (default /dev/sda)
    -s      Swap disk partition to use (default /dev/sdb)
    -j      Disk to install grub on (default /dev/sda)
    -n      Hostname (default gentoo)
    -m      Domainname (default localdomain)
    -k      Install kernel (default false)
    -g      Install grub (default false)
```

### Examples

```
./install.sh -i -d /dev/sda1 -s /dev/sda2 -j /dev/sda -n gentoo -m box.ostanin.org -k -g
```

This will install gentoo with `/dev/sda1` as the root partition and `/dev/sda2` as the swap partition. It will also install the Grub bootloader to the `/dev/sda` disk and build a kernel with genkernel.
