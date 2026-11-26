#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="${HOME}/.local/bin"
DATA_BASE="${XDG_DATA_HOME:-${HOME}/.local/share}"
CFG_BASE="${XDG_CONFIG_HOME:-${HOME}/.config}"

APP_DIR="${DATA_BASE}/kveil"
SHELL_DIR="${DATA_BASE}/plasma/shells/org.kveil.lockscreen"
APPS_DIR="${DATA_BASE}/applications"
ICON_DIR="${DATA_BASE}/icons/hicolor/scalable/apps"
SYSTEMD_DIR="${CFG_BASE}/systemd/user"

# Migrate legacy darc-lockscreen config and remove old app/shell dirs if upgrading
if [[ -f "${CFG_BASE}/darc-lockscreen/settings.json" && ! -f "${CFG_BASE}/kveil/settings.json" ]]; then
    mkdir -p "${CFG_BASE}/kveil"
    cp -a "${CFG_BASE}/darc-lockscreen/settings.json" "${CFG_BASE}/kveil/settings.json"
fi
rm -rf "${DATA_BASE}/darc-lockscreen" "${DATA_BASE}/plasma/shells/org.darc.lockscreen"

echo "[1/5] Installing KVeil settings app -> ${APP_DIR}"
mkdir -p "${APP_DIR}" "${BIN_DIR}" "${APPS_DIR}" "${ICON_DIR}"
install -Dm755 "${ROOT}/app/settings_app.py" "${APP_DIR}/settings_app.py"
install -Dm644 "${ROOT}/app/settings_store.py" "${APP_DIR}/settings_store.py"
install -Dm644 "${ROOT}/app/settings_ui.qml" "${APP_DIR}/settings_ui.qml"
install -Dm644 "${ROOT}/app/kveil-logo.svg" "${APP_DIR}/kveil-logo.svg"
install -Dm644 "${ROOT}/hooks/compare.py" "${APP_DIR}/compare.py"
install -Dm755 "${ROOT}/app/kveil" "${BIN_DIR}/kveil"
install -Dm644 "${ROOT}/app/kveil-logo.svg" "${ICON_DIR}/kveil.svg"
install -Dm644 "${ROOT}/app/kveil.desktop" "${APPS_DIR}/kveil.desktop"

echo "[2/5] Installing lock screen helpers -> ${BIN_DIR}"
install -Dm755 "${ROOT}/bin/lockscreen-weather" "${BIN_DIR}/lockscreen-weather"
install -Dm755 "${ROOT}/bin/lockscreen-mpris-art" "${BIN_DIR}/lockscreen-mpris-art"

echo "[3/5] Installing Plasma 6 lock screen shell -> ${SHELL_DIR}"
rm -rf "${SHELL_DIR}"
mkdir -p "${SHELL_DIR}"
cp -a "${ROOT}/shell/org.kveil.lockscreen/." "${SHELL_DIR}/"

echo "[4/5] Installing systemd user units & KWin lock screen overrides -> ${SYSTEMD_DIR}"
mkdir -p \
    "${SYSTEMD_DIR}" \
    "${SYSTEMD_DIR}/plasma-kwin_wayland.service.d" \
    "${SYSTEMD_DIR}/plasma-kwin_x11.service.d"
install -Dm644 "${ROOT}/systemd/apple-lockscreen.conf" "${SYSTEMD_DIR}/plasma-kwin_wayland.service.d/apple-lockscreen.conf"
install -Dm644 "${ROOT}/systemd/apple-lockscreen.conf" "${SYSTEMD_DIR}/plasma-kwin_x11.service.d/apple-lockscreen.conf"
install -Dm644 "${ROOT}/systemd/lockscreen-weather.service" "${SYSTEMD_DIR}/lockscreen-weather.service"
install -Dm644 "${ROOT}/systemd/lockscreen-weather.timer" "${SYSTEMD_DIR}/lockscreen-weather.timer"
install -Dm644 "${ROOT}/systemd/lockscreen-mpris-art.service" "${SYSTEMD_DIR}/lockscreen-mpris-art.service"

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
    systemctl --user enable --now lockscreen-weather.timer || true
    systemctl --user start lockscreen-weather.service || true
    systemctl --user enable --now lockscreen-mpris-art.service || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APPS_DIR}" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "${DATA_BASE}/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "[5/5] Checking dependencies"
missing=0
if ! python3 -c "import PySide6" >/dev/null 2>&1; then
    echo "  ! Missing Python module: PySide6 (install your distro's python-pyside6 / python3-pyside6 package)"
    missing=1
fi
if ! python3 -c "import gi; gi.require_version('Gio', '2.0')" >/dev/null 2>&1; then
    echo "  ! Missing Python module: PyGObject / gi (needed by lockscreen-mpris-art for album art)"
fi

echo ""
echo "KVeil installed!"
echo "  - Launch GUI: ${BIN_DIR}/kveil (or 'KVeil' from your app launcher)"
echo "  - Test immediately without re-login using KVeil's 'Test Lock Screen' button"
echo "  - Log out and log back in once so KWin picks up PLASMA_DEFAULT_SHELL=org.kveil.lockscreen"
if [[ "${missing}" -ne 0 ]]; then
    echo "  - Install missing dependencies listed above before launching KVeil"
fi
