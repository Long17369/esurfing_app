"""Exercise the isolated APK on the explicitly authorized 16 KB emulator.

Install the sessionCheck APK first. This script only controls/uninstalls that
test package; it never launches, clears, or reads the production application.
"""
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ADB = "/home/long/Android/Sdk/platform-tools/adb"
SERIAL = "emulator-5554"
PACKAGE = "com.esurfing.esurfing_app.sessioncheck"
ACTIVITY = PACKAGE + "/com.esurfing.esurfing_app.MainActivity"
RECEIVER = PACKAGE + "/com.esurfing.esurfing_app.SessionCheckReceiver"
UI_FILE = "/sdcard/esurfing-session-check-ui.xml"
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "../.session-android")
OUT.mkdir(parents=True, exist_ok=True)
results = {}


def adb(*args):
    return subprocess.check_output([ADB, "-s", SERIAL, *args], text=True, timeout=30)


def command(name):
    return adb("shell", "am", "broadcast", "-n", RECEIVER, "--es", "command", name)


def evidence(label):
    value = json.loads(adb("shell", "run-as", PACKAGE, "cat", "files/session-check.json"))
    results[label] = value
    (OUT / "device-scenarios.json").write_text(json.dumps(results, indent=2))
    return value


def controls():
    adb("shell", "uiautomator", "dump", UI_FILE)
    return list(ET.fromstring(adb("exec-out", "cat", UI_FILE)).iter("node"))


def tap(node):
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def permission(name, allow, dialogs):
    command(name)
    for _ in range(dialogs):
        nodes = controls()
        suffixes = (("permission_allow_foreground_only_button", "permission_allow_button")
                    if allow else ("permission_deny_button",))
        choice = next((n for n in nodes if any(
            n.get("resource-id", "").endswith("/" + suffix) for suffix in suffixes)), None)
        assert choice is not None, f"No expected permission control: {name} {allow}"
        tap(choice)
    time.sleep(1)
    flags = adb("shell", "dumpsys", "package", PACKAGE)
    expected = ("POST_NOTIFICATIONS",) if name == "permission" else (
        "ACCESS_FINE_LOCATION", "NEARBY_WIFI_DEVICES")
    selected = {}
    for permission_name in expected:
        match = re.search(r"android\.permission\." + permission_name + r": granted=(true|false)", flags)
        assert match and (match[1] == "true") == allow, permission_name
        selected[permission_name] = match[1]
    results[f"{name}-{'granted' if allow else 'denied'}"] = selected
    assert evidence(name + str(allow))["nativeKeepRunning"]


def same_session(before, after):
    assert all(before[k] == after[k] for k in ("host", "engine", "pid"))
    assert after["nativeKeepRunning"] and not after["error"]
    assert after["requests"]["/keep.cgi"] > before["requests"]["/keep.cgi"]
    assert after["requests"]["/auth.cgi"] == before["requests"]["/auth.cgi"] == 1


pid = None
try:
    assert adb("shell", "getprop", "ro.product.cpu.abi").strip() == "x86_64"
    assert adb("shell", "getconf", "PAGE_SIZE").strip() == "16384"
    results["device"] = {"serial": SERIAL, "abi": "x86_64", "pageSize": 16384}
    assert PACKAGE in adb("shell", "pm", "list", "packages", PACKAGE).splitlines()[0]
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    for _ in range(60):
        try:
            started = evidence("started")
            if started["phase"] in ("keeping", "error"):
                break
        except (ValueError, subprocess.CalledProcessError):
            pass
        time.sleep(1)
    else:
        raise AssertionError("Native startup timed out")
    assert started["phase"] == "keeping" and started["nativeKeepRunning"], started
    pid = str(started["pid"])
    (OUT / "device-apk-maps.txt").write_text("\n".join(
        line for line in adb("shell", "run-as", PACKAGE, "cat", f"/proc/{pid}/maps").splitlines()
        if PACKAGE in line and "base.apk" in line))

    permission("permission", False, 1)
    permission("permission", True, 1)
    permission("wifiPermission", False, 2)
    permission("wifiPermission", True, 2)
    before = evidence("before-early-resume")
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(2)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(5)
    resumed = evidence("early-resumed")
    same_session(before, resumed)
    assert resumed["destroyCalls"] == resumed["activitiesDestroyed"] == 0
    assert resumed["activitiesCreated"] == 1

    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(8)
    removed = evidence("activity-destroyed")
    time.sleep(3)
    background = evidence("keeping-without-activity")
    same_session(removed, background)
    assert background["destroyCalls"] == background["activitiesDestroyed"] == 1
    assert background["activitiesCreated"] == 1
    assert "isForeground=true" in adb("shell", "dumpsys", "activity", "services", PACKAGE)

    adb("shell", "cmd", "statusbar", "expand-notifications")
    notification = next((n for n in controls() if
                         n.get("text") == "Isolated native keep check"), None)
    assert notification is not None, "No visible session notification"
    tap(notification)
    time.sleep(3)
    reopened = evidence("notification-reopened")
    same_session(background, reopened)
    assert reopened["activitiesCreated"] == 2 and reopened["activitiesDestroyed"] == 1
    assert reopened["lifecycle"][-1] == "resumed"

    command("stop")
    time.sleep(2)
    stopped = evidence("stopped")
    assert stopped["phase"] == "disposed" and not stopped["nativeKeepRunning"], stopped
    time.sleep(3)
    assert evidence("stopped-stable")["requests"] == stopped["requests"]
    assert "SessionService" not in adb("shell", "dumpsys", "activity", "services", PACKAGE)
    logs = adb("logcat", "-d", "--pid=" + pid)
    (OUT / "device-logcat.txt").write_text(logs)
    assert not re.search(r"FATAL EXCEPTION|Fatal signal|Unhandled Exception", logs), "App crash in logcat"
    results["passed"] = True
    print("PASS: permission deny/grant, early resume, Activity expiry, real notification reopen, native cleanup")
finally:
    if pid:
        (OUT / "device-logcat.txt").write_text(adb("logcat", "-d", "--pid=" + pid))
    adb("shell", "cmd", "statusbar", "collapse")
    adb("shell", "rm", "-f", UI_FILE)
    # This applicationId is reserved for this test build; production is untouched.
    command("stop")
    results["uninstall"] = adb("uninstall", PACKAGE).strip()
    results["remainingTestPackages"] = adb("shell", "pm", "list", "packages", PACKAGE).strip()
    (OUT / "device-scenarios.json").write_text(json.dumps(results, indent=2))
