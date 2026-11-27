#!/usr/bin/env bash
set -euo pipefail

PURGE=0
if [[ "${1:-}" == "--purge" ]]; then
    PURGE=1
fi

BIN_DIR="${HOME}/.local/bin"
DATA_BASE="${XDG_DATA_HOME:-${HOME}/.local/share}"
CFG_BASE="${XDG_CONFIG_HOME:-${HOME}/.config}"
CACHE_BASE="${XDG_CACHE_HOME:-${HOME}/.cache}"

APP_DIR="${DATA_BASE}/kveil"
SHELL_DIR="${DATA_BASE}/plasma/shells/org.kveil.lockscreen"
APPS_DIR="${DATA_BASE}/applications"
ICON_FILE="${DATA_BASE}/icons/hicolor/scalable/apps/kveil.svg"
SYSTEMD_DIR="${CFG_BASE}/systemd/user"
PLASMA_ENV_DIR="${CFG_BASE}/plasma-workspace/env"
AUTOSTART_DIR="${CFG_BASE}/autostart"

if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now lockscreen-weather.timer >/dev/null 2>&1 || true
    systemctl --user disable --now lockscreen-mpris-art.service >/dev/null 2>&1 || true
fi
if command -v pkill >/dev/null 2>&1; then
    pkill -u "$(id -u)" -f "${BIN_DIR}/lockscreen-weather --daemon" >/dev/null 2>&1 || true
    pkill -u "$(id -u)" -f "${BIN_DIR}/lockscreen-mpris-art" >/dev/null 2>&1 || true
fi

rm -f \
    "${BIN_DIR}/kveil" \
    "${BIN_DIR}/lockscreen-weather" \
    "${BIN_DIR}/lockscreen-mpris-art" \
    "${APPS_DIR}/kveil.desktop" \
    "${ICON_FILE}" \
    "${SYSTEMD_DIR}/plasma-kwin_wayland.service.d/apple-lockscreen.conf" \
    "${SYSTEMD_DIR}/plasma-kwin_x11.service.d/apple-lockscreen.conf" \
    "${SYSTEMD_DIR}/lockscreen-weather.service" \
    "${SYSTEMD_DIR}/lockscreen-weather.timer" \
    "${SYSTEMD_DIR}/lockscreen-mpris-art.service" \
    "${PLASMA_ENV_DIR}/kveil.sh" \
    "${AUTOSTART_DIR}/org.kde.plasmashell.desktop" \
    "${AUTOSTART_DIR}/kveil-weather.desktop" \
    "${AUTOSTART_DIR}/kveil-mpris-art.desktop"

rmdir "${SYSTEMD_DIR}/plasma-kwin_wayland.service.d" >/dev/null 2>&1 || true
rmdir "${SYSTEMD_DIR}/plasma-kwin_x11.service.d" >/dev/null 2>&1 || true

rm -rf "${APP_DIR}" "${SHELL_DIR}" "${DATA_BASE}/darc-lockscreen" "${DATA_BASE}/plasma/shells/org.darc.lockscreen"

if [[ "${PURGE}" -eq 1 ]]; then
    rm -rf "${CFG_BASE}/kveil" "${CACHE_BASE}/kveil" "${CFG_BASE}/darc-lockscreen" "${CACHE_BASE}/darc-lockscreen"
fi

if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APPS_DIR}" >/dev/null 2>&1 || true
fi

echo "KVeil removed. Log out and log back in so KWin reverts to the default Plasma lock screen."
