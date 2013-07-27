#!/bin/bash

# VARS
pacman="pacman --noconfirm --force"
home="/opt/studio"
repo="git@github.com:podlove-studio-connect/webapp.git"

# Install packages
$pacman -Syu
$pacman -S git vim
$pacman -S nginx aiccu python2 python2-distribute avahi python2-gobject
$pacman -S gstreamer gst-plugins-ugly gst-plugins-good gst-plugins-base gst-plugins-base-libs gst-plugins-bad gst-libav
$pacman -S python2-virtualenv python2-dev alsa-plugins alsa-utils supervisor gcc make redis

# Enable systemd start scripts
systemctl enable nginx
systemctl enable avahi-daemon
systemctl enable supervisord
systemctl enable redis

# Create User and generate Virtualenv
useradd --create-home --home-dir $home studio
virtualenv --system-site-packages $home
git clone $repo $home/webapp
$home/bin/pip install -r $home/webapp/requirements.txt
chown -R studio:studio $home

# Cleanup
$pacman -Scc
