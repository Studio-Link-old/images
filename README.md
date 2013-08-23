# Podlove Studio Connect

## Current Base Images

### Raspberry Pi

http://archlinuxarm.org/os/ArchLinuxARM-rpi-latest.zip

### Cubieboard 2 (Allwinner A20)

http://archlinuxarm.org/os/ArchLinuxARM-sun7i-latest.tar.gz

## Bootstrap

If you're looking for the *one-liner* to install podlove studio connect...


Using ``wget`` to install:

```wget -O - https://raw.github.com/podlove-studio-connect/images/master/install.sh | bash```


If you have certificate issues using ``wget`` try the following:

```wget --no-check-certificate -O - https://raw.github.com/podlove-studio-connect/images/master/install.sh | bash```
