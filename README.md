# Podlove Studio Connect

## Current Base Images

### Cubieboard 2 (Allwinner A20)

http://archlinuxarm.org/os/ArchLinuxARM-sun7i-latest.tar.gz

### BeagleBone Black

http://archlinuxarm.org/platforms/armv7/ti/beaglebone-black

## Bootstrap

If you're looking for the *one-liner* to install podlove studio connect...


Using ``wget`` to install:

```pacman -Sy wget```

```wget -O - https://raw.github.com/podlove-studio-connect/images/master/install.sh | bash```


If you have certificate issues using ``wget`` try the following:

```wget --no-check-certificate -O - https://raw.github.com/podlove-studio-connect/images/master/install.sh | bash```
