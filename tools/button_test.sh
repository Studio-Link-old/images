#!/bin/bash

# LED Test (GPIO_1[29] = 1x32+29 = 61)
echo 61 > /sys/class/gpio/export
gpio61="/sys/class/gpio/gpio61"
echo out > $gpio61/direction
for i in `seq 1 5`; do 
    echo 0 > $gpio61/value
    sleep 0.5 
    echo 1 > $gpio61/value
    sleep 0.5 
done
echo 61 > /sys/class/gpio/unexport

# Button Test (GPIO_2[2] = 2x32+2 = 66)
echo 66 > /sys/class/gpio/export
gpio66="/sys/class/gpio/gpio66"
echo in > $gpio66/direction
gstatus=`cat $gpio66/value`
echo "Press button"
while [ $gstatus == 1 ]; do 
    gstatus=`cat $gpio66/value`
    sleep 0.1
done
echo 66 > /sys/class/gpio/unexport
