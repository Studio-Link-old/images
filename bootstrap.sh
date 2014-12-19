#!/bin/bash
# +--------------------------------------------------------------------------+
# |   _____ __            ___          __    _       __                      |
# |  / ___// /___  ______/ (_)___     / /   (_)___  / /__                    |
# |  \__ \/ __/ / / / __  / / __ \   / /   / / __ \/ //_/                    |
# | ___/ / /_/ /_/ / /_/ / / /_/ /  / /___/ / / / / ,<                       |
# |/____/\__/\__,_/\__,_/_/\____/  /_____/_/_/ /_/_/|_|                      |
# |Copyright Sebastian Reimers 2013 - 2014 studio-link.de                    |
# |License: BSD-2-Clause (see LICENSE File)                                  |
# +--------------------------------------------------------------------------+

# Exit on non-zero return codes
set -e

# VARS
pacman="pacman --noconfirm --force --needed"
home="/opt/studio"
repo="https://github.com/studio-link/webapp.git"
pkg_url="https://github.com/studio-link/PKGBUILDs/raw/master"
version="14.11.0-beta"
checkout="master"
update_docroot="/tmp/update"

update_status() {
    mkdir -p $update_docroot
    curl -L https://raw.githubusercontent.com/studio-link/images/$checkout/update.html | sed "s/STATUS/$1/g" > $update_docroot/index.html_tmp
    mv $update_docroot/index.html_tmp $update_docroot/index.html
}

# Root permissions are required to run this script
if [ "$(whoami)" != "root" ]; then
    echo "Error: Studio Link Bootstrap requires root privileges to install. Please re-run this script as root."
    exit 1
fi

update_status 0 # 0%
systemctl stop nginx || true
cd $update_docroot
python2 -m SimpleHTTPServer 80 > /dev/null 2>&1 &
http_pid=$!

# Cleanup pacman cache
yes | pacman -Scc
rm /var/lib/pacman/sync/*

# Remove corrupt systemd journal files
find /var/log/journal -name "*.journal~" -exec rm {} \;
systemctl restart systemd-journald

update_status 10 # 10%

# Check disk usage
disk_free=`df -m / | awk '{ print $4 }' | tail -1`
if [ $disk_free -lt 300 ]; then
    echo "Not enough free disk space [only ${disk_free} MByte free]"
    exit 1
fi

if [[ "$(uname -m)" =~ armv7.? ]]; then
    # Update Mirrorlist
    cat > /etc/pacman.d/mirrorlist << EOF
# Studio Connect Mirror
Server = http://mirror.studio-connect.de/$version/armv7h/\$repo
EOF
fi

# Upgrade packages
$pacman -Syu

update_status 50 # 50%

# Install packages
$pacman -S git vim ntp nginx aiccu python2 python2-distribute avahi wget
$pacman -S python2-virtualenv alsa-plugins alsa-utils gcc make redis sudo fake-hwclock
$pacman -S python2-numpy ngrep tcpdump

# Baresip/Jackd requirements (codecs)
$pacman -S spandsp gsm celt

# Long polling and baresip redis requirements
$pacman -S hiredis libmicrohttpd

if [[ "$(uname -m)" =~ armv7.? ]]; then
	cd /tmp
	wget $pkg_url/jack2/jack2-14.8.0-1-armv7h.pkg.tar.xz
	$pacman -U jack2-14.8.0-1-armv7h.pkg.tar.xz
fi

# Create User and generate Virtualenv
if [ ! -d $home ]; then
    useradd --create-home --password paCam17s4xpyc --home-dir $home studio
    virtualenv2 --system-site-packages $home
    git clone $repo $home/webapp
    $home/bin/pip install pytz==2014.10
    $home/bin/pip install --upgrade -r $home/webapp/requirements.txt
    cd $home/webapp
    $home/bin/python -c "from app import db; db.create_all();"
else
    if [ -f /etc/systemd/system/studio-webapp.service ]; then
        systemctl stop studio-webapp
        systemctl stop studio-celery
        systemctl stop baresip
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

# Compile long_polling server
cd $home/webapp/long_polling
make

# One-time
if [ "$(grep -E "^14\.5" /etc/studio-release)" ]; then
	cd $home/webapp
	$home/bin/pip install --upgrade pytz==2014.10
	$home/bin/pip install --upgrade -r $home/webapp/requirements.txt
	sync
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
After=syslog.target network.target redis.service

[Service]
Type=simple
User=studio
Group=studio
ExecStart=/opt/studio/bin/gunicorn -w 2 -b 127.0.0.1:5000 --chdir /opt/studio/webapp app:app
ExecStartPost=/usr/bin/redis-cli flushall
CPUShares=200

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/studio-events.service << EOF
[Unit]
Description=studio-webapp events
After=syslog.target network.target redis.service

[Service]
Type=simple
User=studio
Group=studio
ExecStart=/opt/studio/webapp/long_polling/server
CPUShares=100

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/studio-celery.service << EOF
[Unit]
Description=studio-celery worker
After=syslog.target network.target

[Service]
Type=simple
User=studio
Group=studio
ExecStart=/opt/studio/bin/celery worker --app=app.tasks -l info --concurrency=1
WorkingDirectory=/opt/studio/webapp
CPUShares=100

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/aiccu.service << EOF
[Unit]
Description=SixXS Automatic IPv6 Connectivity Configuration Utility
After=network.target ntpdate.service

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

		location /events {
		    proxy_pass         http://127.0.0.1:8888;
		    proxy_redirect     off;
		}

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

cat > /etc/nsswitch.conf << EOF
# Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

publickey: files

hosts: files mdns_minimal [NOTFOUND=return] dns myhostname
networks: files

protocols: files
services: files
ethers: files
rpc: files

netgroup: files

# End /etc/nsswitch.conf
EOF

cat > /etc/systemd/system/baresip.service << EOF
[Unit]
Description=baresip
After=syslog.target network.target ntpdate.service

[Service]
Type=simple
User=studio
Group=studio
LimitRTPRIO=infinity
LimitMEMLOCK=infinity
ExecStart=/usr/bin/baresip
WorkingDirectory=/opt/studio/webapp
CPUShares=2048
TimeoutStopSec=10
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
jitter_buffer_delay     1-5
rtp_stats               no
module_path             /usr/lib/baresip/modules
module                  httpdsc.so
# Audio codec Modules (in order) {
module                  opus.so
module                  g722.so
module                  g726.so
module                  g711.so
module                  gsm.so
module                  l16.so
# }
module                  alsa.so
module                  stun.so
module                  turn.so
module                  ice.so
module_tmp              uuid.so
module_tmp              account.so
module_app              auloop.so
module_app              contact.so
module_app              menu.so
module_app		redis.so
ice_turn                yes
ice_debug               yes
ice_nomination          regular # {regular,aggressive}
ice_mode                full    # {full,lite}
opus_bitrate            64000
EOF

chown -R studio:studio $home/.baresip

# Fix IPv6 avahi
sed -i 's/use-ipv6=no/use-ipv6=yes/' /etc/avahi/avahi-daemon.conf

cat > /etc/iptables/ip6tables.rules << EOF
# Generated by studio-link
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
After=syslog.target network.target

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
    curl -L https://raw.githubusercontent.com/studio-link/images/\$version/bootstrap.sh | bash
fi
EOF

chmod +x /opt/studio/bin/studio-update.sh

cat > /etc/systemd/system/studio-jackd.service << EOF
[Unit]
Description=Studio Link JACK DAEMON
After=baresip studio-webapp

[Service]
LimitRTPRIO=infinity
LimitMEMLOCK=infinity
User=studio
ExecStart=/opt/studio/bin/studio-jackd.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /opt/studio/bin/studio-jackd.sh << EOF
#!/bin/bash
device=\$(grep audio_player /opt/studio/.baresip/config | awk '{ print \$2 }' | awk -F: '{ print \$2 }')

/usr/bin/jackd -R -P89 -dalsa -d hw:\$device -r48000 -p480 -n3
EOF

chmod +x /opt/studio/bin/studio-jackd.sh

cat > /etc/sysctl.d/99-sysctl.conf << EOF
# realtime fix jackd
kernel.sched_rt_runtime_us = -1
EOF

cat > /etc/systemd/system/studio-gaudio_in.service << EOF
[Unit]
Description=Studio Link g_audio_IN
After=studio-jackd

[Service]
LimitRTPRIO=infinity
LimitMEMLOCK=infinity
User=studio
ExecStart=/usr/bin/alsa_in -d hw:UAC2Gadget -c 2 -r 48000 -q 0 > /dev/null

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/studio-gaudio_out.service << EOF
[Unit]
Description=Studio Link g_audio_OUT
After=studio-jackd

[Service]
LimitRTPRIO=infinity
LimitMEMLOCK=infinity
User=studio
ExecStart=/usr/bin/alsa_out -d hw:UAC2Gadget -c 2 -r 48000 -q 0 > /dev/null

[Install]
WantedBy=multi-user.target
EOF

cat > /opt/studio/.asoundrc << EOF
# convert alsa API over jack API

# use this as default
pcm.!default {
    type plug
    slave { pcm "jack" }
}

ctl.mixer0 {
    type hw
    card 1
}

# pcm type jack
pcm.jack {
    type jack
    playback_ports {
        0 system:playback_1
        1 system:playback_2
    }
    capture_ports {
        0 system:capture_1
        1 system:capture_2
    }
}
EOF

chown studio:studio /opt/studio/.asoundrc

# g_audio Kernel Modul
cat > /etc/modules-load.d/studio.conf << EOF
g_audio
EOF
cat > /etc/modprobe.d/studio.conf << EOF
options g_audio c_srate=48000 p_srate=48000
EOF

cat > /opt/studio/routing.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<jack>
  <client name="system">
    <port name="capture_1">
      <connection port="sip-src:in0" />
      <connection port="sip-src:in1" />
    </port>
    <port name="capture_2">
      <connection port="sip-src:in0" />
      <connection port="sip-src:in1" />
    </port>
  </client>
  <client name="sip-play">
    <port name="out0">
      <connection port="system:playback_2" />
    </port>
    <port name="out1">
      <connection port="system:playback_1" />
    </port>
  </client>
</jack>
EOF

chown studio:studio /opt/studio/routing.xml

cat > /etc/systemd/system/aj-snapshot.service << EOF
[Unit]
Description=aj-snapshot
After=syslog.target network.target studio-jackd

[Service]
Type=simple
User=studio
Group=studio
LimitMEMLOCK=infinity
ExecStart=/usr/bin/aj-snapshot -j -d /opt/studio/routing.xml

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# Enable systemd start scripts
systemctl enable nginx
systemctl enable avahi-daemon
systemctl enable redis
systemctl enable ntpdate
systemctl enable studio-webapp
systemctl enable studio-events
systemctl enable studio-celery
systemctl enable baresip
systemctl enable fake-hwclock
systemctl enable studio-jackd
systemctl enable aj-snapshot

# Temporary disabling ip6tables until final version
systemctl disable ip6tables.service

# Disable mandb cache daily cron
systemctl stop man-db.timer
systemctl disable man-db.timer
systemctl mask man-db.timer

# sudo privileges
cat > /etc/sudoers << EOF
root ALL=(ALL) ALL
studio ALL=(ALL) NOPASSWD: ALL
EOF

pacman -Q | grep linux-am33x
if [ $? -eq 0 ]; then
    mkdir -p /media
    # Only write fstab if no sdcard
    if [ ! "$(blkid /dev/mmcblk1p2)" ]; then
        uuid=$(blkid -o value -s UUID /dev/mmcblk0p2)
        # Mount Options (noatime)
        cat > /etc/fstab << EOF
UUID=$uuid / ext4 defaults,noatime,nodiratime 0 1
/dev/disk/by-path/platform-48060000.mmc-part1 /media auto defaults,x-systemd.automount 0 0
EOF
    fi
fi

# Limit systemd journal
cat > /etc/systemd/journald.conf << EOF
[Journal]
SystemMaxUse=20M
EOF

# Hostname
if [[ "$(uname -m)" =~ armv7.? ]]; then
    post=$(ip link show eth0 | grep ether | awk '{ print $2 }' | sed s/://g | cut -c 7-)
else
    post="dev"
fi
echo "studio-link-$post" > /etc/hostname

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

if [[ "$(uname -m)" =~ armv7.? ]]; then
    cd /tmp
    wget $pkg_url/opus/opus-1.1-101-armv7h.pkg.tar.xz
    wget $pkg_url/libre/libre-0.4.10-1-armv7h.pkg.tar.xz
    wget $pkg_url/librem/librem-0.4.6-1-armv7h.pkg.tar.xz
    wget $pkg_url/baresip/baresip-14.11.0-3-armv7h.pkg.tar.xz
    wget $pkg_url/aj-snapshot/aj-snapshot-0.9.6-1-armv7h.pkg.tar.xz

    pacman -Q | grep linux-am33x
    if [ $? -eq 0 ]; then
	    yes | pacman -S linux-am33x
    fi

    $pacman -U *-armv7h.pkg.tar.xz
    rm -f /tmp/*-armv7h.pkg.tar.xz
fi

# Add Audio files
#if [ ! -f /usr/local/share/baresip/ring.wav ]; then
#    mkdir -p /usr/local/share/baresip
#    cd /usr/local/share/baresip/
#    wget http://mirror.studio-connect.de/music/busy.wav
#    wget http://mirror.studio-connect.de/music/error.wav
#    wget http://mirror.studio-connect.de/music/message.wav
#    wget http://mirror.studio-connect.de/music/ring.wav
#    wget http://mirror.studio-connect.de/music/ringback.wav
#fi

if [ -f /usr/local/share/baresip/ring.wav ]; then
    rm -Rf /usr/local/share/baresip
fi

# Starting Services
systemctl start redis
systemctl start studio-celery
systemctl start studio-webapp
systemctl start studio-events
systemctl start studio-jackd
systemctl start baresip
systemctl start aj-snapshot

if [ ! -f /etc/studio-link-community ]; then
	# Provisioning
	hash=$(ip link show eth0 | grep ether | awk '{ print $2 }' | md5sum | awk '{ print $1 }')
	wget https://server.visr.de/provisioning/$hash.txt -O /tmp/provisioning.txt || true
	if [ -s /tmp/provisioning.txt ]; then
		cd /opt/studio/webapp
		/opt/studio/bin/celery call --app=app.tasks app.tasks.provisioning
	fi
fi

update_status 95 # 95%

# Flush filesystem buffers
echo "Syncing filesystem..."
sync; sleep 5; sync

kill $http_pid
sleep 5
systemctl start nginx

# Update Version
echo $version > /etc/studio-release

echo "*** Bootstrap finished! Please reboot now! ***"
/usr/bin/redis-cli set reboot_required true
