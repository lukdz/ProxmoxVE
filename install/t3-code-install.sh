#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: lukdz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://t3.codes/ | Github: https://github.com/pingdotgg/t3code

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

t3_user="t3"
t3_home="/home/${t3_user}"

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  python3 \
  dbus \
  dbus-user-session \
  libpam-systemd
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

msg_info "Creating T3 User"
if ! id "$t3_user" >/dev/null 2>&1; then
  $STD useradd --create-home --user-group --home-dir "$t3_home" --shell /bin/bash "$t3_user"
fi
# T3 can execute provider agent commands, so keep its server and project work non-root.
$STD passwd --lock "$t3_user"
$STD chmod 750 "$t3_home"
if ! grep -q '^export XDG_RUNTIME_DIR=' "$t3_home/.profile" 2>/dev/null; then
  cat <<'EOF' >>"$t3_home/.profile"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
EOF
fi
chown "$t3_user:$t3_user" "$t3_home/.profile"
chmod 640 "$t3_home/.profile"
msg_ok "Created T3 User"

t3_uid="$(id -u "$t3_user")"

msg_info "Preparing T3 User Service"
$STD systemctl start systemd-logind.service
$STD loginctl enable-linger "$t3_user"
$STD systemctl start "user-runtime-dir@${t3_uid}.service" "user@${t3_uid}.service"
for _ in {1..30}; do
  [[ -S "/run/user/${t3_uid}/bus" ]] && break
  sleep 1
done
if [[ ! -S "/run/user/${t3_uid}/bus" ]]; then
  msg_error "The T3 user service bus is unavailable. Ensure systemd user services are supported by this LXC."
  exit 1
fi
msg_ok "Prepared T3 User Service"

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

msg_info "Installing T3 Code"
t3_exec /usr/bin/npx --yes t3@latest service install
msg_ok "Installed T3 Code"
fix_resource_monitor_permissions
if [[ "$t3_resource_monitor_repaired" -eq 1 ]]; then
  msg_ok "Repaired T3 resource monitor permissions"
fi

msg_info "Configuring Network Access"
mkdir -p "$t3_home/.config/systemd/user/t3code.service.d"
cat <<EOF >"$t3_home/.config/systemd/user/t3code.service.d/10-network.conf"
[Service]
Environment=HOME=${t3_home}
Environment=PATH=${t3_home}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=T3CODE_HOST=0.0.0.0
Environment=T3CODE_PORT=3773
EOF
chown "$t3_user:$t3_user" \
  "$t3_home/.config/systemd/user/t3code.service.d" \
  "$t3_home/.config/systemd/user/t3code.service.d/10-network.conf"
t3_exec /usr/bin/systemctl --user daemon-reload
t3_exec /usr/bin/systemctl --user restart t3code.service
if ! t3_exec /usr/bin/systemctl --user is-active --quiet t3code.service; then
  msg_error "T3 Code service failed to start"
  exit 1
fi
msg_ok "Configured Network Access"

t3_version=$(jq -r '.activeVersion // empty' "$t3_home/.t3/runtime/service-state.json" 2>/dev/null || true)
if [[ ! "$t3_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  msg_error "Unable to determine the installed T3 Code version."
  exit 1
fi
cat <<EOF >/root/.t3-code
${t3_version}
EOF

motd_ssh
customize
cleanup_lxc
