#!/bin/bash
# +--------------------------------------------------------------------------+
# |   _____ __            ___          ______                            __  |
# |  / ___// /___  ______/ (_)___     / ____/___  ____  ____  ___  _____/ /_ |
# |  \__ \/ __/ / / / __  / / __ \   / /   / __ \/ __ \/ __ \/ _ \/ ___/ __/ |
# | ___/ / /_/ /_/ / /_/ / / /_/ /  / /___/ /_/ / / / / / / /  __/ /__/ /_   |
# |/____/\__/\__,_/\__,_/_/\____/   \____/\____/_/ /_/_/ /_/\___/\___/\__/   |
# |Copyright Sebastian Reimers 2013 - 2014 studio-connect.de                 |
# |License: BSD-2-Clause (see LICENSE File)                                  |
# +--------------------------------------------------------------------------+

# Exit on non-zero return codes
set -e

# VARS
pacman="pacman --noconfirm --force --needed"
home="/opt/studio"
repo="https://github.com/studio-connect/webapp.git"
pkg_url="https://github.com/studio-connect/PKGBUILDs/raw/master"
version="14.4.2-alpha"
checkout="devel"
update_docroot="/tmp/update"

update_status() {
    mkdir -p $update_docroot
    curl -L https://raw.github.com/studio-connect/images/$checkout/update.html | sed "s/STATUS/$1/g" > $update_docroot/index.html
}

update_status 0 # 0%
systemctl stop nginx
cd $update_docroot
python2 -m SimpleHTTPServer 80 > /dev/null 2>&1 &
http_pid=$!

# Root permissions are required to run this script
if [ "$(whoami)" != "root" ]; then
    echo "Error: Studio Connect Bootstrap requires root privileges to install. Please re-run this script as root."
    exit 1
fi

# Cleanup pacman cache
yes | pacman -Scc

update_status 10 # 10%

# Check disk usage
disk_free=`df -m / | awk '{ print $4 }' | tail -1`
if [ $disk_free -lt 300 ]; then
    echo "Not enough free disk space [only ${disk_free} MByte free]"
    exit 1
fi

if [ "$(uname -m)" == "armv7l" ]; then
    # Update Mirrorlist
    cat > /etc/pacman.d/mirrorlist << EOF
# Studio Connect Mirror
Server = http://mirror.studio-connect.de/$version/armv7h/\$repo
EOF
fi

if ([ "$(grep -E "^(13\.|14\.1\.|14\.2\.)" /etc/studio-release)" ]); then
    pacman --noconfirm -R gstreamer gst-plugins-ugly gst-plugins-good gst-plugins-base \
        gst-plugins-base-libs gst-plugins-bad gst-libav python2-gobject gobject-introspection
fi

# Upgrade packages
$pacman -Syu

update_status 50 # 50%

# Install packages
$pacman -S git vim ntp nginx aiccu python2 python2-distribute avahi wget
$pacman -S python2-virtualenv alsa-plugins alsa-utils gcc make redis sudo

# Baresip requirements (codecs)
$pacman -S spandsp gsm

# Create User and generate Virtualenv
if [ ! -d $home ]; then
    useradd --create-home --password paCam17s4xpyc --home-dir $home studio
    virtualenv2 --system-site-packages $home
    git clone $repo $home/webapp
    $home/bin/pip install pytz==2014.2
    $home/bin/pip install --upgrade -r $home/webapp/requirements.txt
    cd $home/webapp
    $home/bin/python -c "from app import db; db.create_all();"
else
    if [ -f /etc/systemd/system/studio-webapp.service ]; then
        systemctl stop studio-webapp
        systemctl stop studio-celery
    fi
    
    # Upgrade Virtualenv
    python2_org_md5=$(md5sum /usr/bin/python2.7 | awk '{ print $1 }')
    python2_env_md5=$(md5sum $home/bin/python2 | awk '{ print $1 }')
    if [ "$python2_org_md5" != "$python2_env_md5" ]; then
        virtualenv2 --system-site-packages $home
    fi

    cd $home/webapp
    git checkout master
    git pull
    git checkout -f $checkout
    if [ "$checkout" == "devel" ]; then
        git pull
    fi
    $home/bin/pip install -r $home/webapp/requirements.txt
fi

if [ ! -f $home/webapp/htpasswd ]; then
    echo 'studio:$apr1$Qq44Nzw6$pRmaAHIi001i4UChgU1jF1' > $home/webapp/htpasswd
fi

# Cleanup old versions (13.x.x, 14.[1-2].x and before)
if ([ "$(grep -E "^(13\.|14\.1\.|14\.2\.)" /etc/studio-release)" ] || [ ! -f /etc/studio-release ]); then
    cd $home/webapp
    rm app.db
    $home/bin/python -c "from app import db; db.create_all();"
    $pacman -S linux-am33x
    $home/bin/pip install --upgrade pytz==2014.2
    $home/bin/pip install --upgrade -r $home/webapp/requirements.txt
fi

chown -R studio:studio $home
chmod 755 $home
gpasswd -a studio audio
gpasswd -a studio video
mkdir -p $home/logs

update_status 90 # 90%

# Deploy configs
cat > /etc/systemd/system/studio-webapp.service << EOF
[Unit]
Description=studio-webapp fastcgi
After=syslog.target
After=network.target
After=redis.service

[Service]
Type=simple
User=studio
Group=studio
ExecStart=/opt/studio/bin/gunicorn -w 3 -b 127.0.0.1:5000 --chdir /opt/studio/webapp app:app
ExecStartPost=/usr/bin/redis-cli flushall
CPUShares=200

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
ExecStart=/opt/studio/bin/celery worker --app=app.tasks -l info --concurrency=1 --purge
WorkingDirectory=/opt/studio/webapp
CPUShares=100

[Install]
WantedBy=multi-user.target
EOF

# REMOVE LEGACY celery2 SERVICE - 14.2.0-alpha
if [ -f /etc/systemd/system/studio-celery2.service ]; then
    systemctl stop studio-celery2
    systemctl disable studio-celery2
    rm /etc/systemd/system/studio-celery2.service
fi

# REMOVE LEGACY beat SERVICE - 14.2.0-alpha
if [ -f /etc/systemd/system/studio-beat.service ]; then
    systemctl stop studio-beat
    systemctl disable studio-beat
    rm /etc/systemd/system/studio-beat.service
fi

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
                root /opt/studio/webapp/app/templates;

                access_log off;

                location / { 
                    auth_basic "Please Login";
                    auth_basic_user_file  /opt/studio/webapp/htpasswd;
                    try_files \$uri @studioapp;
                }

                location @studioapp {
                    proxy_pass         http://127.0.0.1:5000;
                    proxy_redirect     off;

                    proxy_set_header   Host             \$host;
                    proxy_set_header   X-Real-IP        \$remote_addr;
                    proxy_set_header   X-Forwarded-For  \$proxy_add_x_forwarded_for;
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
    <title>Rebooting/Upgrading</title>
    <style>
        body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
        }
    </style>
</head>
<body>
    <h1>Rebooting/Upgrading...</h1>

    <p>Please wait and retry a few seconds later.</p>
    <p>Bitte warten, die Anwendung wird gerade neu gestartet.</p>
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

cat > /etc/systemd/system/baresip.service << EOF
[Unit]
Description=baresip
After=syslog.target
After=network.target

[Service]
Type=simple
User=studio
Group=studio
ExecStart=/usr/bin/baresip
WorkingDirectory=/opt/studio/webapp
CPUShares=2048
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

mkdir -p $home/.baresip

cat > $home/.baresip/config << EOF
poll_method             epoll
input_device            /dev/event0
input_port              5555
sip_trans_bsize         128
sip_listen              0.0.0.0:5060
audio_player            alsa,plughw:0,0
audio_source            alsa,plughw:0,0
audio_alert             alsa,plughw:0,0
audio_srate             8000-48000
ausrc_srate             48000
auplay_srate            48000
audio_channels          1-2
rtp_tos                 184
rtcp_enable             yes
rtcp_mux                no
jitter_buffer_delay     5-10
rtp_stats               no
module_path             /usr/lib/baresip/modules
module                  httpdsc.so
module                  opus.so
module                  alsa.so
module                  stun.so
module                  turn.so
module                  ice.so
module_tmp              account.so
module_app              auloop.so
module_app              contact.so
module_app              menu.so
EOF

chown -R studio:studio $home/.baresip

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

cat > /etc/systemd/system/studio-update.service << EOF
[Unit]
Description=studio-update
After=syslog.target
After=network.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/opt/studio/bin/studio-update.sh

[Install]
WantedBy=multi-user.target
EOF

cat > /opt/studio/bin/studio-update.sh << EOF
#!/bin/bash
version=\$(/usr/bin/redis-cli get next_release)
if [ \$version ]; then
    curl -L https://raw.github.com/studio-connect/images/\$version/bootstrap.sh | bash
fi
EOF

chmod +x /opt/studio/bin/studio-update.sh

# DISABLED (baresip audio problems)
#cat > /etc/modules-load.d/studio.conf << EOF
#g_audio
#EOF
#cat > /etc/modprobe.d/studio.conf << EOF
#options g_audio iProduct=StudioConnect
#EOF

systemctl daemon-reload

# Enable systemd start scripts
systemctl enable nginx
systemctl enable avahi-daemon
systemctl enable redis
systemctl enable ntpdate
systemctl enable studio-webapp
systemctl enable studio-celery
systemctl enable baresip

# Temporary disabling ip6tables until final version
systemctl disable ip6tables.service

# sudo privileges
cat > /etc/sudoers << EOF
root ALL=(ALL) ALL
studio ALL=(ALL) NOPASSWD: ALL
EOF

if [ "$(uname -m)" == "armv7l" ]; then
    # Only write fstab if no sdcard
    if [ ! "$(blkid /dev/mmcblk1p2)" ]; then
        uuid=$(blkid -o value -s UUID /dev/mmcblk0p2)
        # Mount Options (noatime)
        cat > /etc/fstab << EOF
UUID=$uuid / ext4 defaults,noatime,nodiratime 0 1
EOF
    fi
fi

# Limit systemd journal
cat > /etc/systemd/journald.conf << EOF
[Journal]
SystemMaxUse=20M
EOF

# Hostname
if [ "$(uname -m)" == "armv7l" ]; then
    post=$(ip link show eth0 | grep ether | awk '{ print $2 }' | sed s/://g | cut -c 7-)
else
    post="dev"
fi
echo "studio-connect-$post" > /etc/hostname

# Disable root account
passwd -l root

# Set timezone
if [ ! -f /etc/studio-release ]; then
    timedatectl set-timezone Europe/Berlin
fi

# Cleanup
yes | pacman -Scc

# Logrotate (mostly nginx logs)
logrotate -f /etc/logrotate.conf

if [ "$(uname -m)" == "armv7l" ]; then
    cd /tmp
    wget $pkg_url/opus/opus-1.1-101-armv7h.pkg.tar.xz
    wget $pkg_url/libre/libre-0.4.7-1-armv7h.pkg.tar.xz
    wget $pkg_url/librem/librem-0.4.5-1-armv7h.pkg.tar.xz
    wget $pkg_url/baresip/baresip-0.4.10-3-armv7h.pkg.tar.xz
    $pacman -U *-armv7h.pkg.tar.xz
    rm -f /tmp/*-armv7h.pkg.tar.xz
fi

# Starting Services
systemctl start redis
systemctl start studio-webapp
systemctl start studio-celery
systemctl start baresip

update_status 95 # 95%

# Flush filesystem buffers
echo "Syncing filesystem..."
sync; sleep 5; sync

kill $http_pid
sleep 2 
systemctl start nginx

# Update Version
echo $version > /etc/studio-release

echo "*** Bootstrap finished! Please reboot now! ***"
