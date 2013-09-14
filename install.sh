#!/bin/bash

# VARS
pacman="pacman --noconfirm --force"
home="/opt/studio"
repo="https://github.com/studio-connect/webapp.git"

# Install packages
$pacman -Syu
$pacman -S git vim
$pacman -S nginx aiccu python2 python2-distribute avahi python2-gobject
$pacman -S gstreamer gst-plugins-ugly gst-plugins-good gst-plugins-base gst-plugins-base-libs gst-plugins-bad gst-libav
$pacman -S python2-virtualenv alsa-plugins alsa-utils supervisor gcc make redis sudo

# Enable systemd start scripts
systemctl enable nginx
systemctl enable avahi-daemon
systemctl enable supervisord
systemctl enable redis

# Create User and generate Virtualenv
useradd --create-home --password paCam17s4xpyc --home-dir $home studio
virtualenv2 --system-site-packages $home
git clone $repo $home/webapp
$home/bin/pip install pytz==2013b
$home/bin/pip install --upgrade -r $home/webapp/requirements.txt
cd $home/webapp
$home/bin/python -c "from app import db; db.create_all();"
chown -R studio:studio $home
gpasswd -a studio audio
gpasswd -a studio video
mkdir $home/logs

# Deploy configs
cat > /etc/supervisor.d/studio-webapp.ini << EOF
[program:studio-webapp]
command=/opt/studio/bin/python /opt/studio/webapp/app.fcgi
autorestart=true
user=studio
numprocs=1
process_name=%(program_name)s_%(process_num)02d
EOF

cat > /etc/nginx/nginx.conf << EOF
worker_processes  1;

events {
        worker_connections  20;
}

http {
        include       mime.types;
        default_type  application/octet-stream;

        sendfile        on;
        keepalive_timeout  65;

        gzip  off;

        server {
                listen       80;
                server_name  localhost;


                location / { try_files \$uri @yourapplication; }
                location @yourapplication {
                        include fastcgi_params;
                        fastcgi_param PATH_INFO \$fastcgi_script_name;
                        fastcgi_param SCRIPT_NAME "";
                        fastcgi_pass unix:/tmp/fcgi.sock;
                }

                error_page   500 502 503 504  /50x.html;
                location = /50x.html {
                        root   /usr/share/nginx/html;
                }

        }
}
EOF

cat > /etc/avahi/services/http.service << EOF
<?xml version="1.0" standalone='no'?><!--*-nxml-*-->
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
<name replace-wildcards="yes">%h HTTP</name>
<service>
<type>_http._tcp</type>
<port>80</port>
</service>
</service-group>
EOF

# Sudo
echo "studio ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Hostname
echo "studio-connect" > /etc/hostname

# Disable root account
passwd -l root

# Cleanup
$pacman -Scc
reboot
