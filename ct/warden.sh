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

# vladf90/warden is a private repository, so git reads it with a GitHub token
# that can only read that repository (fine-grained, Contents: read-only). It is
# asked for here and kept only in the environment: the install inside the
# container gets it through lxc-attach, and git sends it as a header from the
# environment, so it is never written to disk or put on a command line.
function warden_token() {
  { local xtrace=$-; set +x; } 2>/dev/null # keep the token out of a debug trace
  # Without a terminal (an unattended update), pass WARDEN_GITHUB_TOKEN in the environment.
  if [[ -z "${WARDEN_GITHUB_TOKEN:-}" ]] && (: </dev/tty) 2>/dev/null; then
    read -rsp "GitHub token that can read vladf90/warden: " WARDEN_GITHUB_TOKEN </dev/tty || true
    echo
  fi
  if [[ -z "${WARDEN_GITHUB_TOKEN:-}" ]]; then
    msg_error "Warden needs a GitHub token that can read vladf90/warden (WARDEN_GITHUB_TOKEN)"
    exit 1
  fi
  export WARDEN_GITHUB_TOKEN
  if [[ $xtrace == *x* ]]; then set -x; fi
}

function warden_git_auth() {
  warden_token
  { local xtrace=$-; set +x; } 2>/dev/null
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="http.https://github.com/vladf90/warden.extraheader"
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$WARDEN_GITHUB_TOKEN" | base64 -w0)"
  export GIT_CONFIG_VALUE_0
  if [[ $xtrace == *x* ]]; then set -x; fi
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/warden || ! -d /opt/warden ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Warden publishes no releases yet, so updates follow its main branch.
  warden_git_auth
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
warden_token
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}The dashboard is plain HTTP on port 8080, meant to sit behind Traefik (HTTPS):${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW}SSH endpoint: ${IP}:2222. Target setup endpoint: ${IP}:8443${CL}"
echo -e "${INFO}${YW}Dashboard login and authenticator key are in ~/warden.creds inside the container${CL}"
