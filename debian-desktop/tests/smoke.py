#!/usr/bin/env python3
"""Run installed desktop components on an isolated headless compositor.

Run with: dbus-run-session -- python3 tests/smoke.py
Does not launch the session's power/idle/network helpers or import systemd env.
Logs and a screenshot remain in a printed temporary directory for inspection.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

PROFILE = Path(__file__).resolve().parents[1]


def main():
    artifacts = Path(tempfile.mkdtemp(prefix="sway-desktop-test-"))
    runtime = artifacts / "runtime"
    runtime.mkdir(mode=0o700)
    config = (PROFILE / "config/sway/config").read_text()
    # Explicitly omit only the real session manager and host-specific overrides.
    isolated = "\n".join(
        line for line in config.splitlines()
        if not line.startswith(("exec $bin/desktop-session", "include "))
    )
    test_config = artifacts / "sway.conf"
    test_config.write_text(isolated + "\noutput HEADLESS-1 mode 1920x1080\n")
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), WLR_BACKENDS="headless",
               WLR_RENDERER="pixman", WLR_LIBINPUT_NO_DEVICES="1",
               XDG_CURRENT_DESKTOP="sway", XDG_SESSION_TYPE="wayland",
               LIBGL_ALWAYS_SOFTWARE="1", NO_AT_BRIDGE="1")
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("SWAYSOCK", None)
    children = []
    log_handles = []

    def spawn(name, argv):
        log = (artifacts / (name + ".log")).open("w")
        log_handles.append(log)
        process = subprocess.Popen(argv, env=env, stdout=log, stderr=log, start_new_session=True)
        children.append(process)
        return process

    def until(predicate, label, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            if compositor.poll() is not None:
                raise RuntimeError("Sway exited: " + (artifacts / "sway.log").read_text())
            time.sleep(0.1)
        raise AssertionError("Timed out: " + label)

    def ipc(*args):
        result = subprocess.run(["swaymsg", "-r", *args], env=env,
                                capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def command(text):
        result = ipc(text)
        assert all(item.get("success") for item in result), (text, result)

    def nodes(node=None):
        node = ipc("-t", "get_tree") if node is None else node
        yield node
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            yield from nodes(child)

    def windows():
        return [node for node in nodes() if node.get("app_id") == "Alacritty"]

    def key(key_name):
        prefix = "bindsym " + key_name + " "
        commands = [line[len(prefix):] for line in config.splitlines() if line.startswith(prefix)]
        assert len(commands) == 1, (key_name, commands)
        command(commands[0].replace("$bin", str(Path.home() / ".local/bin")))

    try:
        subprocess.run(["sway", "--validate", "-c", str(test_config)], env=env, check=True)
        compositor = spawn("sway", ["sway", "-c", str(test_config)])
        socket = until(lambda: next(runtime.glob("sway-ipc.*.sock"), None), "IPC socket")
        env["SWAYSOCK"] = str(socket)
        display = until(lambda: next((p for p in runtime.glob("wayland-*") if not p.name.endswith(".lock")), None), "Wayland socket")
        env["WAYLAND_DISPLAY"] = display.name
        spawn("autotiling", ["autotiling"])
        for index in range(3):
            spawn(f"alacritty-{index}", ["alacritty", "--config-file", str(PROFILE / "config/alacritty/alacritty.toml"),
                  "--title", f"Desktop test {index + 1}", "-e", "sleep", "120"])
            until(lambda: len(windows()) == index + 1, f"terminal {index + 1}")
            time.sleep(0.25)
        assert len({(w["rect"]["x"], w["rect"]["y"]) for w in windows()}) == 3

        key("$mod+2")
        assert next(w for w in ipc("-t", "get_workspaces") if w["focused"])["num"] == 2
        key("$mod+1")
        key("$mod+Shift+2")
        key("$mod+2")
        focused = next(w for w in windows() if w["focused"])
        key("$mod+f")
        assert next(w for w in windows() if w["id"] == focused["id"])["fullscreen_mode"] == 1
        key("$mod+f")
        key("$mod+a")
        assert next(w for w in windows() if w["id"] == focused["id"])["type"] == "floating_con"
        key("$mod+a")
        key("$mod+r")
        assert ipc("-t", "get_binding_state")["name"] == "resize"
        command("mode default")
        key("$mod+Shift+w")
        assert next(w for w in windows() if w["id"] == focused["id"])["scratchpad_state"] != "none"
        key("$mod+w")
        key("$mod+1")
        subprocess.run([str(PROFILE / "bin/desktop-swap")], env=env, check=True, capture_output=True)

        mako = spawn("mako", ["mako", "--config", str(PROFILE / "config/mako/config")])
        time.sleep(0.3)
        assert mako.poll() is None, "Mako failed"
        subprocess.run(["notify-send", "Sway desktop test", "Alt key actions, terminals and notifications are working."], env=env, check=True)
        menu = spawn("bemenu", [str(PROFILE / "bin/desktop-menu"), "--prompt", "Test"])
        time.sleep(0.3)
        # No stdin entries is valid; check the backend did not report parse errors.
        if menu.poll() is not None:
            assert "unrecognized option" not in (artifacts / "bemenu.log").read_text()
        else:
            menu.terminate()

        subprocess.run(["grim", "-o", "HEADLESS-1", str(artifacts / "desktop.png")], env=env, check=True)
        assert (artifacts / "desktop.png").read_bytes().startswith(b"\x89PNG")
        # Test the real lock protocol only on the disposable compositor.
        lock = spawn("swaylock", ["swaylock", "--config", str(PROFILE / "config/swaylock/config")])
        time.sleep(0.5)
        assert lock.poll() is None, "Swaylock failed"
        print("PASS: configuration, 3 rendered terminals, tiling, workspaces, moving, fullscreen,")
        print("      floating, resize mode, scratchpad, swap, notifications, screenshot, lock startup")
    finally:
        for process in reversed(children):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
        for process in children:
            try:
                process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        for log in log_handles:
            log.close()
        print("Test artifacts:", artifacts)


if __name__ == "__main__":
    main()
