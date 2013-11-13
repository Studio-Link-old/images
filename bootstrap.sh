#!/bin/bash

# VARS
pacman="pacman --noconfirm --force --needed"
home="/opt/studio"
repo="https://github.com/studio-connect/webapp.git"
version="13.11.2-dev"
checkout="master"

# Root permissions are required to run this script
if [ "$(whoami)" != "root" ]; then
    echoerror "Studio Connect Bootstrap requires root privileges to install. Please re-run this script as root."
    exit 1
fi

if [ "$(uname -m)" == "armv7l" ]; then
# Update Mirrorlist
cat > /etc/pacman.d/mirrorlist << EOF
# Studio Connect Mirror
Server = http://mirror.studio-connect.de/$version/armv7h/\$repo
EOF
pacman --noconfirm -R linux-am33x-legacy
$pacman -S linux-am33x
fi

# Install packages
$pacman -Syu
$pacman -S git vim ntp 
$pacman -S nginx aiccu python2 python2-distribute avahi python2-gobject
$pacman -S gstreamer gst-plugins-ugly gst-plugins-good gst-plugins-base gst-plugins-base-libs gst-plugins-bad gst-libav
$pacman -S python2-virtualenv alsa-plugins alsa-utils gcc make redis sudo

# Create User and generate Virtualenv
id studio
if [ $? == 1 ]; then
    useradd --create-home --password paCam17s4xpyc --home-dir $home studio
    virtualenv2 --system-site-packages $home
    git clone $repo $home/webapp
    $home/bin/pip install pytz==2013.7
    $home/bin/pip install --upgrade -r $home/webapp/requirements.txt
    cd $home/webapp
    $home/bin/python -c "from app import db; db.create_all();"
else
    cd $home/webapp
    git pull
    git checkout -f $checkout
    git pull
    $home/bin/pip install -r $home/webapp/requirements.txt
    redis-cli FLUSHALL
    systemctl stop studio-webapp
    systemctl stop studio-celery
    systemctl stop studio-celery2
fi

if [ ! -f $home/webapp/htpasswd ]; then
    echo 'studio:$apr1$Qq44Nzw6$pRmaAHIi001i4UChgU1jF1' > $home/webapp/htpasswd
fi

chown -R studio:studio $home
chmod 755 $home
gpasswd -a studio audio
gpasswd -a studio video
mkdir -p $home/logs

# Deploy configs
cat > /etc/systemd/system/studio-webapp.service << EOF
[Unit]
Description=studio-webapp fastcgi
After=syslog.target
After=network.target

[Service]
Type=simple
User=studio
Group=studio
ExecStart=/opt/studio/bin/python /opt/studio/webapp/app.fcgi
CPUShares=100

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/studio-celery.service << EOF
[Unit]
Description=studio-celery worker
After=syslog.target
After=network.target

[Service]
Type=simple
User=studio
Group=studio
ExecStart=/opt/studio/bin/celery worker --app=app -l info --concurrency=1 --purge
WorkingDirectory=/opt/studio/webapp
CPUShares=2048

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/studio-celery2.service << EOF
[Unit]
Description=studio-celery2 worker
After=syslog.target
After=network.target

[Service]
Type=simple
User=studio
Group=studio
ExecStart=/opt/studio/bin/celery worker --app=app -l info --concurrency=1
WorkingDirectory=/opt/studio/webapp
CPUShares=2048

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/studio-beat.service << EOF
[Unit]
Description=studio-beat
After=syslog.target
After=network.target

[Service]
Type=simple
User=studio
Group=studio
ExecStart=/opt/studio/bin/celery beat --app=app -l info
WorkingDirectory=/opt/studio/webapp
CPUShares=100

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/aiccu.service << EOF
[Unit]
Description=SixXS Automatic IPv6 Connectivity Configuration Utility
After=network.target
After=ntpdate.service

[Service]
Type=forking
PIDFile=/var/run/aiccu.pid
ExecStart=/usr/bin/aiccu start
ExecStop=/usr/bin/aiccu stop
Restart=always
RestartSec=20

[Install]
WantedBy=multi-user.target
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
                listen  80;
                listen  [::]:80;
                server_name  localhost;

                location /api1/ {
                        try_files \$uri @yourapplication; 
                }

                location / { 
                        auth_basic "Please Login";
                        auth_basic_user_file  /opt/studio/webapp/htpasswd;
                        try_files \$uri @yourapplication; 
                }
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

cat > /usr/share/nginx/html/50x.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Rebooting</title>
    <style>
        body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
        }
    </style>
</head>
<body>
    <h1>Rebooting...</h1>

    <p>Please wait and retry a few seconds later.</p>
</body>
</html>
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

# Fix IPv6 avahi
sed -i 's/use-ipv6=no/use-ipv6=yes/' /etc/avahi/avahi-daemon.conf

cat > /etc/iptables/ip6tables.rules << EOF
# Generated by studio-connect
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p ipv6-icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -s fe80::/10 -j ACCEPT
COMMIT
EOF

# Allow ipv4 autoconfiguration (comment noipv4ll)
# https://wiki.archlinux.org/index.php/avahi#Obtaining_IPv4LL_IP_address
cat > /etc/dhcpcd.conf << EOF
hostname
clientid
#duid
option rapid_commit
option domain_name_servers, domain_name, domain_search, host_name
option classless_static_routes
option ntp_servers
require dhcp_server_identifier
nohook lookup-hostname
#noipv4ll
EOF

cat > /etc/netctl/hooks/dhcpcd-timeout << EOF
TimeoutDHCP=40
EOF

chmod +x /etc/netctl/hooks/dhcpcd-timeout

# Enable systemd start scripts
systemctl enable nginx
systemctl enable avahi-daemon
systemctl enable redis
systemctl enable ntpdate
systemctl enable studio-webapp
systemctl enable studio-celery
systemctl enable studio-celery2
systemctl enable studio-beat

# Temporary disabling ip6tables until final version
#systemctl enable ip6tables.service
systemctl disable ip6tables.service

# Sudo
cat > /etc/sudoers << EOF
root ALL=(ALL) ALL
studio ALL=(ALL) NOPASSWD: ALL
EOF

if [ "$(uname -m)" == "armv7l" ]; then
# Mount Options (noatime)
cat > /etc/fstab << EOF
/dev/mmcblk0p2 / ext4 defaults,noatime,nodiratime 0 1
EOF
fi

# Limit systemd journal
cat > /etc/systemd/journald.conf << EOF
[Journal]
SystemMaxUse=10M
EOF

# Hostname
post=$(ip link show eth0 | grep ether | awk '{ print $2 }' | md5sum | cut -c -4)
echo "studio-connect-$post" > /etc/hostname

# Disable root account
passwd -l root

# Set timezone
timedatectl set-timezone Europe/Berlin

# Cleanup
$pacman -Scc

# Update Version
echo $version > /etc/studio-release

# Logrotate (mostly nginx logs)
logrotate -f /etc/logrotate.conf

# Bugfixing
if [ "$(uname -m)" == "armv7l" ]; then
    cd /tmp
    wget http://mirror.studio-connect.de/opus-1.0.3-1-armv7h.pkg.tar.xz
    wget http://mirror.studio-connect.de/pygobject-devel-3.8.3-1-armv7h.pkg.tar.xz
    wget http://mirror.studio-connect.de/python2-gobject-3.8.3-1-armv7h.pkg.tar.xz
    $pacman -U opus-1.0.3-1-armv7h.pkg.tar.xz
    $pacman -U pygobject-devel-3.8.3-1-armv7h.pkg.tar.xz python2-gobject-3.8.3-1-armv7h.pkg.tar.xz
fi

# Starting Services
systemctl start studio-webapp
systemctl start studio-celery
systemctl start studio-celery2
