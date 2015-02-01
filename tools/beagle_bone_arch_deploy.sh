#!/bin/bash

yes | mkfs.vfat -F 16 /dev/mmcblk1p1
yes | mkfs.ext4 /dev/mmcblk1p2
mkdir -p boot
mkdir -p root
mount /dev/mmcblk1p1 boot
mount /dev/mmcblk1p2 root
tar -xvf BeagleBone-bootloader.tar.gz -C boot
tar -xf 15_1_0-beta.tar.gz -C root
sync
rm root/etc/ssh/ssh_host*
umount boot
umount root
sync
sleep 5
poweroff
