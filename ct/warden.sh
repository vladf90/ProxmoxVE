#!/usr/bin/env bash
# Warden lives only in this fork, so fetch ct/ and install/ from it unless the caller overrides it.
export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/vladf90/ProxmoxVE/main}"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vladf90
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/vladf90/warden

APP="Warden"
var_tags="${var_tags:-ssh;security}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
# Warden holds the SSH key every target trusts: keep it in its own unprivileged LXC.
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/warden || ! -d /opt/warden ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Warden publishes no releases yet, so updates follow its main branch.
  if check_for_gh_branch "warden" "vladf90/warden" "main"; then
    msg_info "Stopping Service"
    systemctl stop warden
    msg_ok "Stopped Service"

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
    cp packages/warden/warden.service /etc/systemd/system/warden.service
    systemctl daemon-reload
    msg_ok "Installed Warden"

    msg_info "Starting Service"
    systemctl start warden
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}The dashboard is plain HTTP on port 8080, meant to sit behind Traefik (HTTPS):${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW}SSH endpoint: ${IP}:2222. Target setup endpoint: ${IP}:8443${CL}"
echo -e "${INFO}${YW}Dashboard login and authenticator key are in ~/warden.creds inside the container${CL}"
