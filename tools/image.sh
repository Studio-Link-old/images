#!/bin/bash

image="2013-07-27-podlove-0.2.0-dev.img"

dd if=/dev/mmcblk0 of=tmp/$image count=3788800

mkdir -p tmp/mnt
sudo mount -o loop,offset=$((512*122880)) tmp/$image tmp/mnt
sudo sfill -z -l -l -f tmp/mnt 
sudo umount tmp/mnt
