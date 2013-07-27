# Podlove Studio Connect

## Current Base Images

### Raspberry Pi

http://archlinuxarm.org/os/rpi/archlinux-hf-2013-06-15.img.zip


## Bootstrap

If you're looking for the *one-liner* to install podlove studio connect...


Using ``wget`` to install:

.. code:: console
  wget -O - https://raw.github.com/podlove-studio-connect/images/master/install.sh | bash


If you have certificate issues using ``wget`` try the following:

.. code:: console
  wget --no-check-certificate -O - https://raw.github.com/podlove-studio-connect/images/master/install.sh | bash
