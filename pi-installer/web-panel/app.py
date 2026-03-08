#!/usr/bin/env python3
"""
Hnina's Seafood - Digital Signage Web Management Panel
Runs on port 8080, provides full control over the signage display.
"""

import json
import os
import subprocess
import shutil
from pathlib import Path
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify

app = Flask(__name__)
app.secret_key = "hninas-signage-panel-key"

INSTALL_DIR = "/opt/hninas-signage"
CONFIG_FILE = os.path.join(INSTALL_DIR, "config.json")
PI_USER = "pi"


def load_config():
    """Load the signage configuration."""
    try:
        with open(CONFIG_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {
            "display_type": "main-menu-screen",
            "schedule_enabled": False,
            "schedule_on": "",
            "schedule_off": "",
            "wifi_ssid": "",
            "install_dir": INSTALL_DIR,
            "web_panel_port": 8080,
        }


def save_config(config):
    """Save the signage configuration."""
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=4)


def run_cmd(cmd, timeout=10):
    """Run a shell command and return output."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "Command timed out", 1
    except Exception as e:
        return str(e), 1


def get_display_status():
    """Check if Chromium kiosk is currently running."""
    out, _ = run_cmd("pgrep -f 'chromium-browser.*kiosk'")
    return "running" if out else "stopped"


def get_system_info():
    """Gather system information."""
    info = {}

    out, _ = run_cmd("hostname -I")
    info["ip"] = out.split()[0] if out else "Unknown"

    out, _ = run_cmd("hostname")
    info["hostname"] = out or "Unknown"

    out, _ = run_cmd("uptime -p")
    info["uptime"] = out or "Unknown"

    out, _ = run_cmd("vcgencmd measure_temp 2>/dev/null || echo 'N/A'")
    info["temp"] = out.replace("temp=", "") if "temp=" in out else out

    out, _ = run_cmd("free -m | awk 'NR==2{printf \"%s/%sMB (%.0f%%)\", $3,$2,$3*100/$2}'")
    info["memory"] = out or "Unknown"

    out, _ = run_cmd("df -h / | awk 'NR==2{printf \"%s/%s (%s)\", $3,$2,$5}'")
    info["disk"] = out or "Unknown"

    out, _ = run_cmd("iwgetid -r 2>/dev/null || echo 'Not connected'")
    info["wifi"] = out or "Not connected"

    return info


def update_cron_schedule(config):
    """Update cron jobs based on config schedule."""
    # Remove existing signage cron entries
    run_cmd(
        f"crontab -u {PI_USER} -l 2>/dev/null | grep -v 'hninas-signage' | crontab -u {PI_USER} - 2>/dev/null"
    )

    if config.get("schedule_enabled") and config.get("schedule_on") and config.get("schedule_off"):
        on_parts = config["schedule_on"].split(":")
        off_parts = config["schedule_off"].split(":")

        if len(on_parts) == 2 and len(off_parts) == 2:
            on_min, on_hour = on_parts[1], on_parts[0]
            off_min, off_hour = off_parts[1], off_parts[0]

            on_cron = f"{on_min} {on_hour} * * * {INSTALL_DIR}/display-on.sh # hninas-signage"
            off_cron = f"{off_min} {off_hour} * * * {INSTALL_DIR}/display-off.sh # hninas-signage"

            run_cmd(
                f'(crontab -u {PI_USER} -l 2>/dev/null || true; echo "{on_cron}") | crontab -u {PI_USER} -'
            )
            run_cmd(
                f'(crontab -u {PI_USER} -l 2>/dev/null || true; echo "{off_cron}") | crontab -u {PI_USER} -'
            )


@app.route("/")
def index():
    """Dashboard page."""
    config = load_config()
    status = get_display_status()
    sys_info = get_system_info()
    return render_template(
        "index.html", config=config, status=status, sys_info=sys_info
    )


@app.route("/display", methods=["GET", "POST"])
def display_settings():
    """Display type and schedule settings."""
    config = load_config()

    if request.method == "POST":
        action = request.form.get("action")

        if action == "change_display":
            new_type = request.form.get("display_type")
            if new_type in ("main-menu-screen", "2-column-menu-screen"):
                config["display_type"] = new_type
                save_config(config)
                flash(f"Display type changed to: {new_type}", "success")

        elif action == "update_schedule":
            schedule_on = request.form.get("schedule_on", "").strip()
            schedule_off = request.form.get("schedule_off", "").strip()
            schedule_enabled = request.form.get("schedule_enabled") == "on"

            config["schedule_enabled"] = schedule_enabled
            config["schedule_on"] = schedule_on
            config["schedule_off"] = schedule_off
            save_config(config)
            update_cron_schedule(config)

            if schedule_enabled and schedule_on and schedule_off:
                flash(f"Schedule updated: ON at {schedule_on}, OFF at {schedule_off}", "success")
            else:
                flash("Schedule disabled (24/7 mode)", "success")

        return redirect(url_for("display_settings"))

    return render_template("display.html", config=config)


@app.route("/files", methods=["GET", "POST"])
def file_manager():
    """Upload and manage display files."""
    config = load_config()

    if request.method == "POST":
        display_type = request.form.get("target_display", config["display_type"])
        target_dir = os.path.join(INSTALL_DIR, display_type)

        if "html_file" in request.files:
            f = request.files["html_file"]
            if f.filename and f.filename.endswith(".html"):
                dest = os.path.join(target_dir, "index.html")
                f.save(dest)
                flash(f"HTML file uploaded to {display_type}/index.html", "success")
            else:
                flash("Please upload an .html file", "error")

        if "image_files" in request.files:
            images = request.files.getlist("image_files")
            media_dir = os.path.join(target_dir, "media", "food")
            os.makedirs(media_dir, exist_ok=True)
            count = 0
            for img in images:
                if img.filename and img.filename.lower().endswith((".jpg", ".jpeg", ".png", ".webp")):
                    dest = os.path.join(media_dir, img.filename)
                    img.save(dest)
                    count += 1
            if count:
                flash(f"{count} image(s) uploaded to {display_type}/media/food/", "success")

        if "logo_file" in request.files:
            f = request.files["logo_file"]
            if f.filename and f.filename.lower().endswith((".jpg", ".jpeg", ".png")):
                logo_dir = os.path.join(target_dir, "media", "logo")
                os.makedirs(logo_dir, exist_ok=True)
                dest = os.path.join(logo_dir, f.filename)
                f.save(dest)
                flash(f"Logo uploaded: {f.filename}", "success")

        return redirect(url_for("file_manager"))

    # List current files
    files = {}
    for dt in ("main-menu-screen", "2-column-menu-screen"):
        dt_dir = os.path.join(INSTALL_DIR, dt)
        dt_files = []
        if os.path.exists(dt_dir):
            for root, dirs, filenames in os.walk(dt_dir):
                for fn in filenames:
                    full_path = os.path.join(root, fn)
                    rel_path = os.path.relpath(full_path, dt_dir)
                    size = os.path.getsize(full_path)
                    dt_files.append({"path": rel_path, "size": size})
        files[dt] = sorted(dt_files, key=lambda x: x["path"])

    return render_template("files.html", config=config, files=files)


@app.route("/control/<action>")
def control(action):
    """Control the display."""
    if action == "restart":
        run_cmd(f"sudo -u {PI_USER} bash {INSTALL_DIR}/display-off.sh")
        run_cmd(f"sudo -u {PI_USER} bash {INSTALL_DIR}/display-on.sh")
        flash("Display restarted", "success")

    elif action == "stop":
        run_cmd(f"sudo -u {PI_USER} bash {INSTALL_DIR}/display-off.sh")
        flash("Display stopped", "success")

    elif action == "start":
        run_cmd(f"sudo -u {PI_USER} bash {INSTALL_DIR}/display-on.sh")
        flash("Display started", "success")

    elif action == "reboot":
        flash("System rebooting...", "success")
        run_cmd("sudo reboot")

    return redirect(url_for("index"))


@app.route("/api/status")
def api_status():
    """API endpoint for display status."""
    config = load_config()
    return jsonify(
        {
            "display_type": config.get("display_type"),
            "status": get_display_status(),
            "schedule_enabled": config.get("schedule_enabled"),
            "schedule_on": config.get("schedule_on"),
            "schedule_off": config.get("schedule_off"),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
