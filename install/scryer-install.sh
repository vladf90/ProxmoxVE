#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vladf90
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.scryer.media/scryer/ | Github: https://github.com/scryer-media/scryer

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "scryer" "scryer-media/scryer" "prebuild" "latest" "/opt/scryer" "scryer-linux-$(arch_resolve "x86_64" "arm64")-portable.tar.gz" "scryer-v"

msg_info "Configuring Scryer"
chmod 755 /opt/scryer/scryer
mkdir -p /var/lib/scryer
# Scryer reads <data-dir>/.env on startup; the process environment wins over it.
cat <<EOF >/var/lib/scryer/.env
# Listen on all interfaces (Scryer defaults to 127.0.0.1:8080)
SCRYER_BIND=0.0.0.0:8080
# Updates come from the 'update' command in this container, not the in-app upgrader
SCRYER_DISABLE_SELF_UPGRADE=1
SCRYER_LOG_FORMAT=text
EOF
chmod 600 /var/lib/scryer/.env
msg_ok "Configured Scryer"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/scryer.service
[Unit]
Description=Scryer media manager
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
UMask=0002
WorkingDirectory=/var/lib/scryer
ExecStart=/opt/scryer/scryer --data-dir /var/lib/scryer
KillSignal=SIGTERM
TimeoutStopSec=30
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now scryer
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
