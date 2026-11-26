#!/usr/bin/env python3
"""PySide6 + Kirigami settings GUI for the org.darc.lockscreen Plasma lock screen."""
import getpass
import os
import shlex
import shutil
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PySide6.QtCore import Property, QObject, QProcess, QTimer, QUrl, Signal, Slot  # noqa: E402
from PySide6.QtGui import QFontDatabase, QGuiApplication, QIcon  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuickControls2 import QQuickStyle  # noqa: E402

from settings_store import DEFAULTS, SETTINGS_JSON, load_settings, save_settings  # noqa: E402

APP_DIR = os.path.dirname(os.path.abspath(__file__))
SHELL_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")),
    "plasma",
    "shells",
    "org.darc.lockscreen",
)
CUSTOM_FONTS_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")),
    "fonts",
    "kveil",
)
FONT_EXTENSIONS = {".ttf", ".otf", ".ttc"}
STAGED_COMPARE = os.path.join(APP_DIR, "compare.py")
HOWDY_ENABLE_KEYS = {"faceStatusEnabled", "irPreviewEnabled"}
FPRINT_ENABLE_KEYS = {"fingerprintStatusEnabled"}

SECURITY_LIB_DIRS = (
    "/usr/lib/security",
    "/lib/security",
    "/usr/lib64/security",
    "/lib64/security",
    "/usr/lib/x86_64-linux-gnu/security",
    "/lib/x86_64-linux-gnu/security",
    "/usr/lib/aarch64-linux-gnu/security",
    "/lib/aarch64-linux-gnu/security",
)


def _first_existing_file(paths):
    for p in paths:
        if p and os.path.isfile(p):
            return p
    return None


def _find_kscreenlocker_greet():
    candidates = []
    for qtpaths_bin in ("qtpaths6", "qtpaths-qt6", "qtpaths"):
        exe = shutil.which(qtpaths_bin)
        if exe:
            try:
                out = subprocess.check_output(
                    [exe, "--query", "QT_INSTALL_LIBEXECS"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                ).strip()
                if out:
                    candidates.append(os.path.join(out, "kscreenlocker_greet"))
                    candidates.append(os.path.join(out, "kf6", "kscreenlocker_greet"))
            except Exception:
                pass
    which_greet = shutil.which("kscreenlocker_greet")
    if which_greet:
        candidates.append(which_greet)
    candidates.extend([
        "/usr/lib/kscreenlocker_greet",
        "/usr/libexec/kscreenlocker_greet",
        "/usr/libexec/kf6/kscreenlocker_greet",
        "/usr/lib64/libexec/kscreenlocker_greet",
        "/usr/lib64/kscreenlocker_greet",
        "/usr/lib/x86_64-linux-gnu/libexec/kscreenlocker_greet",
        "/usr/lib/aarch64-linux-gnu/libexec/kscreenlocker_greet",
    ])
    return _first_existing_file(candidates)


def _find_howdy_compare():
    candidates = [os.path.join(d, "howdy", "compare.py") for d in SECURITY_LIB_DIRS]
    candidates.append("/etc/howdy/compare.py")
    return _first_existing_file(candidates) or "/usr/lib/security/howdy/compare.py"


def _find_weather_bin():
    return (
        shutil.which("lockscreen-weather")
        or os.path.expanduser("~/.local/bin/lockscreen-weather")
    )


class LockscreenSettingsBackend(QObject):
    settingsChanged = Signal()
    statusChanged = Signal()
    toastRequested = Signal(str)

    def __init__(self):
        super().__init__()
        self._custom_font_ids = {}
        self._scan_custom_fonts()
        first_run = not os.path.exists(SETTINGS_JSON)
        self._settings = load_settings()
        if first_run:
            families = set(QFontDatabase.families())
            if "SF Pro Display" in families:
                self._settings["fontFamily"] = "SF Pro Display"
            elif "SF Pro Text" in families:
                self._settings["fontFamily"] = "SF Pro Text"
            else:
                self._settings["fontFamily"] = ""
        # Ensure Settings.qml exists on first launch so the lock screen picks up defaults
        save_settings(self._settings)
        self._status = self._collect_status()

    def _run_fc_cache(self):
        fc_cache = shutil.which("fc-cache")
        if fc_cache and os.path.isdir(CUSTOM_FONTS_DIR):
            try:
                subprocess.run(
                    [fc_cache, "-f", CUSTOM_FONTS_DIR],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=5,
                )
            except Exception:
                pass

    def _scan_custom_fonts(self):
        if not os.path.isdir(CUSTOM_FONTS_DIR):
            for path, (fid, _fams) in list(self._custom_font_ids.items()):
                if fid != -1:
                    QFontDatabase.removeApplicationFont(fid)
            self._custom_font_ids.clear()
            return []

        existing_paths = set()
        custom_fonts = []
        for fname in sorted(os.listdir(CUSTOM_FONTS_DIR), key=str.casefold):
            ext = os.path.splitext(fname)[1].lower()
            if ext not in FONT_EXTENSIONS:
                continue
            path = os.path.join(CUSTOM_FONTS_DIR, fname)
            if not os.path.isfile(path):
                continue
            existing_paths.add(path)
            if path not in self._custom_font_ids:
                fid = QFontDatabase.addApplicationFont(path)
                fams = list(dict.fromkeys(QFontDatabase.applicationFontFamilies(fid))) if fid != -1 else []
                self._custom_font_ids[path] = (fid, fams)
            _, fams = self._custom_font_ids[path]
            custom_fonts.append({"fileName": fname, "families": fams})

        for path in list(self._custom_font_ids):
            if path not in existing_paths:
                fid, _fams = self._custom_font_ids.pop(path)
                if fid != -1:
                    QFontDatabase.removeApplicationFont(fid)
        return custom_fonts

    def _collect_status(self):
        shell_installed = os.path.isdir(os.path.join(SHELL_DIR, "contents", "lockscreen"))
        env_shell = os.environ.get("PLASMA_DEFAULT_SHELL", "")
        cfg_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
        systemd_dropin = (
            os.path.exists(os.path.join(cfg_home, "systemd/user/plasma-kwin_wayland.service.d/apple-lockscreen.conf"))
            or os.path.exists(os.path.join(cfg_home, "systemd/user/plasma-kwin_x11.service.d/apple-lockscreen.conf"))
        )
        howdy_bin = (
            shutil.which("howdy") is not None
            or os.path.isfile("/usr/local/bin/howdy")
            or os.path.isfile("/usr/bin/howdy-rs")
        )
        howdy_dir = any(
            os.path.isdir(os.path.join(d, "howdy")) for d in SECURITY_LIB_DIRS
        ) or os.path.isdir("/etc/howdy")
        pam_howdy_so = _first_existing_file(
            [os.path.join(d, "pam_howdy.so") for d in SECURITY_LIB_DIRS]
        )
        howdy_rs_present = (
            (
                shutil.which("howdy") is not None
                or os.path.isfile("/usr/local/bin/howdy")
                or os.path.isfile("/usr/bin/howdy-rs")
            )
            and pam_howdy_so is not None
        )
        howdy_present = (howdy_bin and howdy_dir) or howdy_rs_present

        pam_fp_path = _first_existing_file([
            "/etc/pam.d/kde-fingerprint",
            "/usr/lib/pam.d/kde-fingerprint",
            "/lib/pam.d/kde-fingerprint",
        ])
        pam_txt = ""
        if pam_fp_path:
            try:
                with open(pam_fp_path, "r") as f:
                    pam_txt = f.read()
            except OSError:
                pass

        howdy_rs_pam = "pam_howdy.so" in pam_txt
        howdy_pam_configured = "howdy" in pam_txt
        howdy_backend = "rust" if (howdy_rs_pam and howdy_rs_present) else ("python" if howdy_present else "none")

        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        howdyd_running = os.path.exists(os.path.join(runtime_dir, "howdyd.sock"))
        howdyd_service_installed = os.path.isfile(
            os.path.join(cfg_home, "systemd", "user", "howdyd.service")
        )

        howdy_compare = _find_howdy_compare()
        howdy_hook_installed = False
        howdy_hook_outdated = False
        if howdy_backend == "rust":
            # Native howdy-rs compiles preview + multi-stage face tracking in directly
            howdy_hook_installed = True
        else:
            try:
                with open(howdy_compare, "r") as f:
                    installed_src = f.read()
                if "_emit_preview_frame" in installed_src:
                    try:
                        with open(STAGED_COMPARE, "r") as sf:
                            howdy_hook_outdated = installed_src != sf.read()
                    except OSError:
                        pass
                    howdy_hook_installed = not howdy_hook_outdated
            except OSError:
                pass

        pam_fprintd_so = _first_existing_file(
            [os.path.join(d, "pam_fprintd.so") for d in SECURITY_LIB_DIRS]
        )
        fprintd_present = (
            shutil.which("fprintd-verify") is not None
            or shutil.which("fprintd-enroll") is not None
            or os.path.exists("/usr/lib/fprintd/fprintd")
            or os.path.exists("/usr/libexec/fprintd")
            or pam_fprintd_so is not None
        )
        fprintd_pam_configured = ("pam_fprintd.so" in pam_txt) and ("howdy" not in pam_txt)
        weather_bin = _find_weather_bin()
        weather_bin_ok = os.path.isfile(weather_bin) and os.access(weather_bin, os.X_OK)
        custom_fonts = self._scan_custom_fonts()
        installed_fonts = sorted(set(QFontDatabase.families()), key=str.casefold)
        families = set(installed_fonts)
        has_sf_pro = "SF Pro Display" in families or "SF Pro Text" in families
        cache_home = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
        return {
            "shellInstalled": shell_installed,
            "shellActive": env_shell == "org.darc.lockscreen" or systemd_dropin,
            "howdyPresent": howdy_present,
            "howdyBackend": howdy_backend,
            "howdyRsPresent": howdy_rs_present,
            "howdydRunning": howdyd_running,
            "howdydServiceInstalled": howdyd_service_installed,
            "howdyPamConfigured": howdy_pam_configured,
            "howdyHookInstalled": howdy_hook_installed,
            "howdyHookOutdated": howdy_hook_outdated,
            "fprintdPresent": fprintd_present,
            "fprintdPamConfigured": fprintd_pam_configured,
            "stagedComparePath": STAGED_COMPARE,
            "howdyComparePath": howdy_compare,
            "weatherBinOk": weather_bin_ok,
            "weatherCached": os.path.exists(os.path.join(cache_home, "darc-lockscreen", "Weather.qml")),
            "hasSfPro": has_sf_pro,
            "installedFonts": installed_fonts,
            "customFonts": custom_fonts,
            "customFontsDir": CUSTOM_FONTS_DIR,
            "configPath": SETTINGS_JSON,
        }

    @Property("QVariantMap", notify=settingsChanged)
    def settings(self):
        return self._settings

    @Property("QVariantMap", notify=statusChanged)
    def status(self):
        return self._status

    @Slot(str, "QVariant")
    def setOption(self, key, value):
        if key not in DEFAULTS:
            return
        if key in HOWDY_ENABLE_KEYS and bool(value) and not self._status.get("howdyPresent"):
            self.toastRequested.emit("Install Howdy before enabling face unlock or IR preview")
            self.settingsChanged.emit()
            return
        if key in FPRINT_ENABLE_KEYS and bool(value) and not self._status.get("fprintdPresent"):
            self.toastRequested.emit("Install fprintd before enabling fingerprint unlock indicator")
            self.settingsChanged.emit()
            return
        if self._settings.get(key) == value:
            return
        self._settings[key] = value
        self._settings = save_settings(self._settings)
        self.settingsChanged.emit()

    @Slot()
    def resetDefaults(self):
        defaults = dict(DEFAULTS)
        self._settings = save_settings(defaults)
        self.settingsChanged.emit()
        self.toastRequested.emit("Reset all settings to defaults")

    @Slot("QVariantList")
    def addFontFiles(self, file_urls):
        os.makedirs(CUSTOM_FONTS_DIR, exist_ok=True)
        added_families = []
        failed_files = []

        for item in file_urls:
            local_path = item.toLocalFile() if isinstance(item, QUrl) else (QUrl(str(item)).toLocalFile() or str(item))
            if not local_path or not os.path.isfile(local_path):
                continue
            fname = os.path.basename(local_path)
            if os.path.splitext(fname)[1].lower() not in FONT_EXTENSIONS:
                failed_files.append(fname)
                continue

            dest = os.path.join(CUSTOM_FONTS_DIR, fname)
            copied = False
            if os.path.abspath(local_path) != os.path.abspath(dest):
                if dest in self._custom_font_ids:
                    old_fid, _ = self._custom_font_ids.pop(dest)
                    if old_fid != -1:
                        QFontDatabase.removeApplicationFont(old_fid)
                shutil.copy2(local_path, dest)
                copied = True

            fid = QFontDatabase.addApplicationFont(dest)
            fams = list(dict.fromkeys(QFontDatabase.applicationFontFamilies(fid))) if fid != -1 else []
            if fid == -1 or not fams:
                if copied:
                    try:
                        os.remove(dest)
                    except OSError:
                        pass
                failed_files.append(fname)
                continue

            self._custom_font_ids[dest] = (fid, fams)
            added_families.extend(fams)

        if not added_families:
            msg = f"Unsupported or invalid font file: {', '.join(failed_files)}" if failed_files else "No font files selected"
            self.toastRequested.emit(msg)
            return

        self._run_fc_cache()
        unique_fams = list(dict.fromkeys(added_families))
        chosen = "SF Pro Display" if "SF Pro Display" in unique_fams else unique_fams[0]
        self._settings["fontFamily"] = chosen
        self._settings = save_settings(self._settings)
        self.refreshStatus()
        self.settingsChanged.emit()
        if failed_files:
            self.toastRequested.emit(f"Added '{chosen}' (skipped invalid: {', '.join(failed_files)})")
        else:
            self.toastRequested.emit(f"Added '{chosen}' and selected it")

    @Slot(str)
    def removeCustomFont(self, file_name):
        if not file_name or os.path.basename(file_name) != file_name or file_name in (".", ".."):
            return
        dest = os.path.join(CUSTOM_FONTS_DIR, file_name)
        if dest in self._custom_font_ids:
            fid, _ = self._custom_font_ids.pop(dest)
            if fid != -1:
                QFontDatabase.removeApplicationFont(fid)
        if os.path.isfile(dest):
            try:
                os.remove(dest)
            except OSError as exc:
                self.toastRequested.emit(f"Failed to remove {file_name}: {exc}")
                return
        self._run_fc_cache()
        self.refreshStatus()
        current_font = self._settings.get("fontFamily", "")
        if current_font and current_font not in set(self._status.get("installedFonts", [])):
            self._settings["fontFamily"] = ""
            self._settings = save_settings(self._settings)
            self.settingsChanged.emit()
        self.toastRequested.emit(f"Removed custom font '{file_name}'")

    @Slot()
    def refreshStatus(self):
        self._status = self._collect_status()
        self.statusChanged.emit()

    @Slot()
    def refreshWeather(self):
        weather_bin = _find_weather_bin()
        if not os.path.isfile(weather_bin):
            self.toastRequested.emit("Weather helper not found at ~/.local/bin/lockscreen-weather")
            return
        proc = QProcess(self)
        proc.finished.connect(lambda code, _st: (
            self.refreshStatus(),
            self.toastRequested.emit("Weather updated" if code == 0 else "Weather refresh failed")
        ))
        proc.start(sys.executable, [weather_bin])

    @Slot()
    def testLockScreen(self):
        greeter = _find_kscreenlocker_greet()
        if not greeter:
            self.toastRequested.emit("kscreenlocker_greet not found")
            return
        env = dict(os.environ)
        env["PLASMA_DEFAULT_SHELL"] = "org.darc.lockscreen"
        subprocess.Popen([greeter, "--testing"], env=env, start_new_session=True)
        self.toastRequested.emit("Launched lock screen preview (--testing)")

    @Slot()
    def openWallpaperSettings(self):
        kcmshell = shutil.which("kcmshell6")
        sysset = shutil.which("systemsettings")
        if kcmshell:
            subprocess.Popen([kcmshell, "kcm_screenlocker"], start_new_session=True)
            self.toastRequested.emit("Opened Screen Locking settings (click Configure Appearance for wallpaper)")
        elif sysset:
            subprocess.Popen([sysset, "kcm_screenlocker"], start_new_session=True)
            self.toastRequested.emit("Opened Screen Locking settings")
        else:
            self.toastRequested.emit("KDE Screen Locking settings tool not found")

    @Slot()
    def copyHookCommand(self):
        howdy_compare = _find_howdy_compare()
        user = getpass.getuser()
        cmd = (
            f"sudo install -m 640 {shlex.quote(STAGED_COMPARE)} {shlex.quote(howdy_compare)} && "
            f"sudo setfacl -m u:{shlex.quote(user)}:r {shlex.quote(howdy_compare)}"
        )
        cb = QGuiApplication.clipboard()
        if cb:
            cb.setText(cmd)
        self.toastRequested.emit("Copied sudo install command to clipboard")

    @Slot()
    def startHowdyd(self):
        if shutil.which("systemctl") is None:
            self.toastRequested.emit("systemctl not found")
            return
        proc = QProcess(self)
        action = "restart" if self._status.get("howdydRunning") else "start"

        def on_done(code, _st):
            proc.deleteLater()
            QTimer.singleShot(150, self.refreshStatus)
            if code == 0:
                self.toastRequested.emit("Howdy-rs daemon active (models preloaded)")
            else:
                self.toastRequested.emit("Failed to start howdyd.service")

        proc.finished.connect(on_done)
        proc.start("systemctl", ["--user", action, "howdyd.service"])


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    if os.environ.get("QT_QPA_PLATFORM") != "offscreen":
        QQuickStyle.setStyle("org.kde.desktop")

    app = QGuiApplication(sys.argv)
    app.setApplicationName("KVeil")
    app.setOrganizationName("kveil")
    app.setDesktopFileName("kveil")
    app.setWindowIcon(QIcon(os.path.join(APP_DIR, "kveil-logo.svg")))

    backend = LockscreenSettingsBackend()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(os.path.join(APP_DIR, "settings_ui.qml")))

    if not engine.rootObjects():
        sys.exit(1)

    if "--smoke-test" in sys.argv:
        QTimer.singleShot(250, app.quit)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
