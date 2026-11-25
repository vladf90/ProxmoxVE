#!/usr/bin/env bash
# Scryer lives only in this fork, so fetch ct/ and install/ from it unless the caller overrides it.
export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/vladf90/ProxmoxVE/main}"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vladf90
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.scryer.media/scryer/ | Github: https://github.com/scryer-media/scryer

APP="Scryer"
var_tags="${var_tags:-arr;media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var/lib/scryer/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "scryer" "scryer-media/scryer" "" "" "scryer-v"; then
    msg_info "Stopping Service"
    systemctl stop scryer
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "scryer" "scryer-media/scryer" "prebuild" "latest" "/opt/scryer" "scryer-linux-$(arch_resolve "x86_64" "arm64")-portable.tar.gz" "scryer-v"
    chmod 755 /opt/scryer/scryer

    msg_info "Starting Service"
    systemctl start scryer
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
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW}Get the one-time setup code inside the container with:${CL}"
echo -e "${TAB}${BGN}journalctl -u scryer | grep 'setup code'${CL}"
