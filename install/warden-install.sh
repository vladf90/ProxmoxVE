#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vladf90
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/vladf90/warden

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
# git keeps the rules history, openssl makes the setup endpoint's certificate,
# qrencode lets 'warden admin setup' show a QR code.
$STD apt install -y git openssl qrencode
msg_ok "Installed Dependencies"

NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
# Builds warden-run, the helper Warden installs on each target.
GO_VERSION="latest" setup_go

# Warden publishes no releases yet, so it is built from its main branch.
fetch_and_deploy_gh_branch "warden" "vladf90/warden" "main" "/opt/warden"

msg_info "Building Warden"
cd /opt/warden
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
$STD corepack prepare "$(jq -r '.packageManager' package.json)" --activate
$STD pnpm install --frozen-lockfile
$STD env WARDEN_VERSION="$(jq -r '.version' packages/warden/package.json)+$(<~/.warden)" pnpm build
$STD env VERSION="$(<~/.warden)" pnpm build:helper
$STD go clean -cache
msg_ok "Built Warden"

msg_info "Installing Warden"
install -m 755 packages/warden/dist/warden.mjs /usr/local/bin/warden
mkdir -p /usr/local/share/warden
cp helper/bin/warden-run-linux-* /usr/local/share/warden/
rm -rf /usr/local/share/warden/dashboard
cp -r packages/dashboard/dist /usr/local/share/warden/dashboard
mkdir -p /etc/warden
cat <<EOF2 >/etc/warden/warden.yaml
# Warden's settings. Every key is optional; see "Setting up" and "Dashboard" in
# https://github.com/vladf90/warden/blob/main/packages/warden/README.md
# Warden's IP as targets see it is found automatically; set address: to override.

# This container's Proxmox ID: commands that would act on it are always refused.
wardenGuestId: "${CTID}"

dashboard:
  port: 8080
  # Only these addresses may reach the dashboard port (e.g. Traefik's). Empty means anyone.
  from: []
  # The dashboard expects HTTPS from Traefik. Set to false only to log in over plain http.
  secureCookie: true
EOF2
$STD warden init
msg_ok "Installed Warden"

msg_info "Setting up the dashboard login"
# 'warden admin setup' reads the password from stdin when it isn't a terminal,
# and prints the new authenticator secret without asking for a code.
ADMIN_PASS="$(random_password 24)"
SETUP_OUT="$(printf '%s\n' "$ADMIN_PASS" | warden admin setup 2>&1)" || true
TOTP_URI="$(grep -o 'otpauth://[^[:space:]]*' <<<"$SETUP_OUT" | head -n1)" || true
unset SETUP_OUT
if [[ -z "$TOTP_URI" ]]; then
  msg_error "Could not set the dashboard login; run 'warden admin setup' in the container"
  exit 1
fi
TOTP_SECRET="$(sed -n 's/.*[?&]secret=\([A-Z2-7]*\).*/\1/p' <<<"$TOTP_URI")"
install -m 600 /dev/null ~/warden.creds
cat <<EOF2 >~/warden.creds
Warden dashboard
Password: ${ADMIN_PASS}
Authenticator key: ${TOTP_SECRET}
Authenticator link: ${TOTP_URI}

Add the key to your authenticator app, then delete this file. For a QR code:
  qrencode -t ansiutf8 "\$(grep -o 'otpauth://.*' ~/warden.creds)"
To pick your own password and a new key instead, run: warden admin setup
EOF2
msg_ok "Set up the dashboard login (in ~/warden.creds)"

msg_info "Creating Service"
cp /opt/warden/packages/warden/warden.service /etc/systemd/system/warden.service
systemctl enable -q --now warden
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
