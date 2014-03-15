#!/bin/bash

cd /root
wget http://archlinuxarm.org/os/omap/BeagleBone-bootloader.tar.gz
wget http://archlinuxarm.org/os/ArchLinuxARM-am33x-latest.tar.gz
mkdir boot
mkdir root
mkfs.vfat -F 16 /dev/mmcblk1p1
mkfs.ext4 /dev/mmcblk1p2
mount /dev/mmcblk1p1 boot
mount /dev/mmcblk1p2 root
tar -xvf BeagleBone-bootloader.tar.gz -C boot
tar -xf ArchLinuxARM-am33x-latest.tar.gz -C root

# patch u-boot env
cat > boot/uEnv.txt << EOF
uenvcmd=if load mmc 0:2 \${loadaddr} /boot/zImage; then setenv mmcdev 0; run uenvboot; else setenv mmcdev 1; setenv mmcroot /dev/mmcblk1p2 rw; if load mmc 1:2 \${loadaddr} /boot/zImage; then run uenvboot; else echo No zImage found; fi; fi
uenvboot=run loadfdt; run setmmcroot; run mmcboot
setmmcroot=setenv mmcroot /dev/mmcblk0p2 rw
loadfdt=load mmc \${mmcdev}:2 \${fdtaddr} /boot/dtbs/\${fdtfile}
mmcboot=echo Booting from mmc ...; run mmcargs; bootz \${loadaddr} - \${fdtaddr}
EOF

umount boot
umount root
sync
poweroff
