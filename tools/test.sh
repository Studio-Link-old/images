#!/bin/bash
qemu-system-arm -daemonize -nographic -M vexpress-a9 -kernel zImage -drive file=root.img,if=sd,cache=none -append "root=/dev/mmcblk0p2 rw" -m 512 -net nic -net user,hostfwd=tcp::2222-:22
sleep 30
ssh  -o StrictHostKeyChecking=no root@127.0.0.1 -p2222 "echo 'MY SSH'; exit 0"
