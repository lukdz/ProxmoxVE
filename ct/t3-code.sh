#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: lukdz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://t3.codes/ | Github: https://github.com/pingdotgg/t3code

APP="T3-Code"
var_tags="${var_tags:-ai;coding;development}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

t3_user="t3"
t3_home="/home/${t3_user}"

header_info "$APP"
variables
color
catch_errors

t3_exec() {
  $STD runuser --user "$t3_user" -- env \
    HOME="$t3_home" \
    USER="$t3_user" \
    LOGNAME="$t3_user" \
    SHELL=/bin/bash \
    PATH="$t3_home/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    XDG_RUNTIME_DIR="/run/user/${t3_uid}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${t3_uid}/bus" \
    NPM_CONFIG_CACHE="$t3_home/.cache/npm" \
    "$@"
}

fix_resource_monitor_permissions() {
  local monitor
  t3_resource_monitor_repaired=0
  for monitor in "$t3_home"/.t3/runtime/versions/*/node_modules/t3/dist/resource-monitor/linux-*/t3-resource-monitor; do
    [[ -f "$monitor" ]] || continue
    if [[ ! -x "$monitor" ]]; then
      chmod 755 "$monitor"
      t3_resource_monitor_repaired=1
    fi
  done
}

sync_t3_version() {
  local version
  version=$(jq -r '.activeVersion // empty' "$t3_home/.t3/runtime/service-state.json" 2>/dev/null || true)
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    msg_error "Unable to determine the installed T3 Code version."
    exit 1
  fi
  cat <<EOF >/root/.t3-code
${version}
EOF
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! id "$t3_user" >/dev/null 2>&1 || [[ ! -f "$t3_home/.config/systemd/user/t3code.service" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  t3_uid="$(id -u "$t3_user")"
  fix_resource_monitor_permissions

  if check_for_gh_release "t3-code" "pingdotgg/t3code"; then
    NODE_VERSION="24" setup_nodejs

    msg_info "Updating ${APP}"
    t3_exec /usr/bin/npx --yes "t3@${CHECK_UPDATE_RELEASE#v}" service update
    fix_resource_monitor_permissions
    t3_exec /usr/bin/systemctl --user restart t3code.service
    sync_t3_version
    msg_ok "Updated ${APP}"

    if ! t3_exec /usr/bin/systemctl --user is-active --quiet t3code.service; then
      msg_error "${APP} service failed to start"
      exit 1
    fi
    msg_ok "Updated successfully!"
  elif [[ "$t3_resource_monitor_repaired" -eq 1 ]]; then
    msg_info "Restarting ${APP} after resource monitor repair"
    t3_exec /usr/bin/systemctl --user restart t3code.service
    msg_ok "Restarted ${APP}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3773${CL}"
echo -e "${INFO}${YW}Run the pairing command as the T3 user:${CL}"
echo -e "${TAB}${BGN}su - t3${CL}"
echo -e "${TAB}${BGN}npx --yes t3@latest pair${CL}"
echo -e "${INFO}${YW}Install and authenticate any provider CLI as the t3 user; credentials are not copied by this script.${CL}"
