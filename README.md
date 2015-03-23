# Studio Link

[![Build Status](https://ci-studio.visr.de/job/studio-link-images/badge/icon)](https://ci-studio.visr.de/job/studio-link-images/)

## Current Base Images (armv7)

### BeagleBone Black

http://archlinuxarm.org/platforms/armv7/ti/beaglebone-black

### ODROID-U3 (without OTG audio support, need >=3.18 kernel)

http://archlinuxarm.org/platforms/armv7/samsung/odroid-u3

### ODROID-C1 (without OTG audio support, need >=3.18 kernel)

http://archlinuxarm.org/platforms/armv7/amlogic/odroid-c1

## Bootstrap

If you have a clean archlinux image you can run the following commands:

### Install/Update

```
touch /etc/studio-link-community
curl -L https://raw.githubusercontent.com/studio-link/images/master/bootstrap.sh | bash
```
