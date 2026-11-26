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
ADMIN_PASS="$(random_password 20)"
# Scryer reads <data-dir>/.env on startup; the process environment wins over it.
cat <<EOF >/var/lib/scryer/.env
# Listen on all interfaces (Scryer defaults to 127.0.0.1:8080)
SCRYER_BIND=0.0.0.0:8080
# Updates come from the 'update' command in this container, not the in-app upgrader
SCRYER_DISABLE_SELF_UPGRADE=1
SCRYER_LOG_FORMAT=text
# First-boot admin. Creating it skips the one-time setup code, and Scryer asks
# for a new password at first login. Removed once Scryer has started.
SCRYER_ADMIN_USERNAME=admin
SCRYER_ADMIN_PASSWORD=${ADMIN_PASS}
EOF
chmod 600 /var/lib/scryer/.env
cat <<EOF >~/scryer.creds
Scryer Admin User: admin
Scryer Admin Password: ${ADMIN_PASS}
(temporary: Scryer asks for a new password at first login)
EOF
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

msg_info "Waiting for Scryer to create the admin"
# The admin is created before the web server starts listening, so once it
# answers the bootstrap lines can go: they would block startup if that account
# were later disabled, and the password should not sit in the config.
SCRYER_UP=0
for _ in $(seq 1 60); do
  if curl -s -o /dev/null http://127.0.0.1:8080/; then
    SCRYER_UP=1
    break
  fi
  sleep 2
done
if [[ "$SCRYER_UP" == "1" ]]; then
  sed -i '/^# First-boot admin/,/^SCRYER_ADMIN_PASSWORD=/d' /var/lib/scryer/.env
  msg_ok "Admin created (login in ~/scryer.creds)"
else
  msg_warn "Scryer did not answer within 2 minutes; check 'journalctl -u scryer'"
fi

motd_ssh
customize

# `update` must pull from this fork's main branch. An install from a test branch
# records that branch, and the branch is deleted once its PR merges.
if [[ -f /usr/bin/update ]]; then
  sed -i -E \
    -e 's#^export COMMUNITY_SCRIPTS_URL=.*#export COMMUNITY_SCRIPTS_URL="https://raw.githubusercontent.com/vladf90/ProxmoxVE/main"#' \
    -e 's#https://raw\.githubusercontent\.com/[^/]+/ProxmoxVE/[^"]*(/ct/)#https://raw.githubusercontent.com/vladf90/ProxmoxVE/main\1#g' \
    /usr/bin/update
fi

cleanup_lxc
