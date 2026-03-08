#!/bin/bash
# ============================================================
# Hnina's Seafood - Digital Signage Installer for Raspberry Pi
# Debian / Raspberry Pi OS
# ============================================================

set -e

INSTALL_DIR="/opt/hninas-signage"
CONFIG_FILE="$INSTALL_DIR/config.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_USER="pi"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}Hnina's Seafood - Digital Signage Installer${NC}        ${RED}║${NC}"
    echo -e "${RED}║${NC}  Raspberry Pi Kiosk Setup                            ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "\n${CYAN}[STEP]${NC} ${BOLD}$1${NC}"
}

print_ok() {
    echo -e "${GREEN}  [OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}  [WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}  [ERROR]${NC} $1"
}

# ── Check root ──
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This installer must be run as root.${NC}"
    echo "Usage: sudo bash install.sh"
    exit 1
fi

print_banner

# ── Ensure pi user exists ──
print_step "Checking user account"
if id "$PI_USER" &>/dev/null; then
    print_ok "User '$PI_USER' exists"
else
    print_warn "User '$PI_USER' not found, creating..."
    useradd -m -s /bin/bash "$PI_USER"
    print_ok "User '$PI_USER' created"
fi

echo "$PI_USER:pi" | chpasswd
print_ok "Password for '$PI_USER' set"

# ── Select display type ──
print_step "Select display layout"
echo ""
echo "  1) Main Menu Screen"
echo "     Left sidebar with daily specials + QR codes"
echo "     4x2 menu grid + scrolling ticker"
echo ""
echo "  2) Two-Column Rotating Menu"
echo "     Header bar + two rotating menu columns"
echo "     Page indicators with countdown + scrolling ticker"
echo ""

while true; do
    read -rp "  Select display type [1 or 2]: " display_choice
    case "$display_choice" in
        1) DISPLAY_TYPE="main-menu-screen"; break ;;
        2) DISPLAY_TYPE="2-column-menu-screen"; break ;;
        *) echo -e "${RED}  Please enter 1 or 2${NC}" ;;
    esac
done
print_ok "Selected: $DISPLAY_TYPE"

# ── Configure schedule ──
print_step "Configure display schedule"
echo ""
echo "  Set daily on/off hours for the display."
echo "  Leave blank for 24/7 (always on)."
echo ""

read -rp "  Display ON time (HH:MM, 24h format, e.g. 11:00) [24/7]: " schedule_on
read -rp "  Display OFF time (HH:MM, 24h format, e.g. 20:00) [24/7]: " schedule_off

if [ -z "$schedule_on" ] || [ -z "$schedule_off" ]; then
    SCHEDULE_ON=""
    SCHEDULE_OFF=""
    SCHEDULE_ENABLED="false"
    print_ok "Schedule: Always on (24/7)"
else
    SCHEDULE_ON="$schedule_on"
    SCHEDULE_OFF="$schedule_off"
    SCHEDULE_ENABLED="true"
    print_ok "Schedule: ON at $SCHEDULE_ON, OFF at $SCHEDULE_OFF"
fi

# ── Configure WiFi ──
print_step "Configure WiFi connection"
echo ""

# Check if nmcli is available
if command -v nmcli &>/dev/null; then
    echo "  Scanning for available networks..."
    nmcli dev wifi rescan 2>/dev/null || true
    sleep 3

    echo ""
    echo "  Available WiFi networks:"
    echo "  ─────────────────────────"
    nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null | sort -t: -k2 -rn | head -15 | while IFS=: read -r ssid signal security; do
        [ -z "$ssid" ] && continue
        printf "    %-30s Signal: %s%%  Security: %s\n" "$ssid" "$signal" "$security"
    done
    echo ""

    read -rp "  Enter WiFi SSID (or press Enter to skip): " wifi_ssid
    if [ -n "$wifi_ssid" ]; then
        read -rsp "  Enter WiFi password: " wifi_pass
        echo ""
        nmcli dev wifi connect "$wifi_ssid" password "$wifi_pass" 2>/dev/null && \
            print_ok "Connected to '$wifi_ssid'" || \
            print_warn "Could not connect now, will retry after reboot"
        WIFI_SSID="$wifi_ssid"
    else
        WIFI_SSID=""
        print_ok "WiFi configuration skipped"
    fi
elif command -v wpa_cli &>/dev/null; then
    echo "  NetworkManager not found, using wpa_supplicant"
    read -rp "  Enter WiFi SSID (or press Enter to skip): " wifi_ssid
    if [ -n "$wifi_ssid" ]; then
        read -rsp "  Enter WiFi password: " wifi_pass
        echo ""

        # Add network to wpa_supplicant
        WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
        if [ -f "$WPA_CONF" ]; then
            # Remove existing entry for this SSID
            sed -i "/ssid=\"$wifi_ssid\"/,/}/d" "$WPA_CONF"
        else
            cat > "$WPA_CONF" << WPAEOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US
WPAEOF
        fi

        cat >> "$WPA_CONF" << WPAEOF

network={
    ssid="$wifi_ssid"
    psk="$wifi_pass"
    key_mgmt=WPA-PSK
}
WPAEOF
        print_ok "WiFi credentials saved for '$wifi_ssid'"
        WIFI_SSID="$wifi_ssid"
        wpa_cli -i wlan0 reconfigure 2>/dev/null || true
    else
        WIFI_SSID=""
        print_ok "WiFi configuration skipped"
    fi
else
    print_warn "No WiFi manager found. Configure WiFi manually after install."
    WIFI_SSID=""
fi

# ── Install packages ──
print_step "Installing required packages"
apt-get update -qq
apt-get install -y -qq \
    chromium-browser \
    xserver-xorg \
    x11-xserver-utils \
    xinit \
    openbox \
    unclutter \
    python3 \
    python3-pip \
    python3-venv \
    openssh-server \
    lightdm \
    > /dev/null 2>&1

print_ok "All packages installed"

# ── Enable SSH ──
print_step "Enabling SSH"
systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null || true
print_ok "SSH enabled and started"

# ── Configure HDMI output ──
print_step "Configuring HDMI for 1920x1080"

# Handle both config.txt locations (Pi 4 vs Pi 5 / bookworm)
for cfg in /boot/config.txt /boot/firmware/config.txt; do
    if [ -f "$cfg" ]; then
        cp "$cfg" "${cfg}.bak.$(date +%Y%m%d%H%M%S)"

        # Remove existing display settings
        sed -i '/^hdmi_force_hotplug/d' "$cfg"
        sed -i '/^hdmi_group/d' "$cfg"
        sed -i '/^hdmi_mode/d' "$cfg"
        sed -i '/^hdmi_drive/d' "$cfg"
        sed -i '/^disable_overscan/d' "$cfg"
        sed -i '/^overscan_/d' "$cfg"
        sed -i '/^framebuffer_width/d' "$cfg"
        sed -i '/^framebuffer_height/d' "$cfg"

        cat >> "$cfg" << HDMIEOF

# Hnina's Signage - HDMI Configuration
hdmi_force_hotplug=1
hdmi_group=1
hdmi_mode=16
hdmi_drive=2
disable_overscan=1
overscan_left=0
overscan_right=0
overscan_top=0
overscan_bottom=0
framebuffer_width=1920
framebuffer_height=1080
HDMIEOF
        print_ok "HDMI configured in $cfg"
    fi
done

# ── Deploy display content ──
print_step "Deploying signage files"
mkdir -p "$INSTALL_DIR"

# Copy both display types
cp -r "$SCRIPT_DIR/display-content/main-menu-screen" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/display-content/2-column-menu-screen" "$INSTALL_DIR/"

# Copy scripts
cp -r "$SCRIPT_DIR/scripts/"* "$INSTALL_DIR/" 2>/dev/null || true

print_ok "Display content deployed to $INSTALL_DIR"

# ── Write config file ──
print_step "Writing configuration"
cat > "$CONFIG_FILE" << CFGEOF
{
    "display_type": "$DISPLAY_TYPE",
    "schedule_enabled": $SCHEDULE_ENABLED,
    "schedule_on": "$SCHEDULE_ON",
    "schedule_off": "$SCHEDULE_OFF",
    "wifi_ssid": "$WIFI_SSID",
    "install_dir": "$INSTALL_DIR",
    "web_panel_port": 8080
}
CFGEOF
chown "$PI_USER:$PI_USER" "$CONFIG_FILE"
print_ok "Config written to $CONFIG_FILE"

# ── Setup kiosk display scripts ──
print_step "Setting up kiosk display"

# Create the kiosk launcher script
cat > "$INSTALL_DIR/kiosk.sh" << 'KIOSKEOF'
#!/bin/bash
# Hnina's Signage Kiosk Launcher
CONFIG="/opt/hninas-signage/config.json"
INSTALL_DIR="/opt/hninas-signage"

# Read display type from config
DISPLAY_TYPE=$(python3 -c "import json; print(json.load(open('$CONFIG'))['display_type'])" 2>/dev/null || echo "main-menu-screen")
HTML_FILE="$INSTALL_DIR/$DISPLAY_TYPE/index.html"

if [ ! -f "$HTML_FILE" ]; then
    echo "ERROR: Display file not found: $HTML_FILE"
    exit 1
fi

# Disable screen blanking / power management
xset s off
xset s noblank
xset -dpms

# Hide cursor after 0.5s of inactivity
unclutter -idle 0.5 -root &

# Wait for X to be ready
sleep 2

# Launch Chromium in kiosk mode
chromium-browser \
    --kiosk \
    --no-first-run \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --disable-component-update \
    --disable-features=TranslateUI \
    --noerrdialogs \
    --incognito \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    --window-size=1920,1080 \
    --window-position=0,0 \
    --start-fullscreen \
    "file://$HTML_FILE"
KIOSKEOF
chmod +x "$INSTALL_DIR/kiosk.sh"
chown "$PI_USER:$PI_USER" "$INSTALL_DIR/kiosk.sh"
print_ok "Kiosk launcher created"

# ── Create display on/off scripts ──
cat > "$INSTALL_DIR/display-on.sh" << 'ONEOF'
#!/bin/bash
# Start the kiosk display
export DISPLAY=:0
CONFIG="/opt/hninas-signage/config.json"
INSTALL_DIR="/opt/hninas-signage"
DISPLAY_TYPE=$(python3 -c "import json; print(json.load(open('$CONFIG'))['display_type'])" 2>/dev/null || echo "main-menu-screen")
HTML_FILE="$INSTALL_DIR/$DISPLAY_TYPE/index.html"

# Kill any existing chromium
pkill -f "chromium-browser.*kiosk" 2>/dev/null || true
sleep 1

# Disable screen blanking
xset s off 2>/dev/null
xset s noblank 2>/dev/null
xset -dpms 2>/dev/null

# Launch chromium
chromium-browser \
    --kiosk \
    --no-first-run \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --disable-component-update \
    --disable-features=TranslateUI \
    --noerrdialogs \
    --incognito \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    --window-size=1920,1080 \
    --window-position=0,0 \
    --start-fullscreen \
    "file://$HTML_FILE" &
ONEOF
chmod +x "$INSTALL_DIR/display-on.sh"

cat > "$INSTALL_DIR/display-off.sh" << 'OFFEOF'
#!/bin/bash
# Stop the kiosk display (let TV handle power saving)
export DISPLAY=:0
pkill -f "chromium-browser.*kiosk" 2>/dev/null || true
OFFEOF
chmod +x "$INSTALL_DIR/display-off.sh"
print_ok "Display on/off scripts created"

# ── Configure schedule cron jobs ──
if [ "$SCHEDULE_ENABLED" = "true" ]; then
    print_step "Configuring display schedule"

    ON_HOUR=$(echo "$SCHEDULE_ON" | cut -d: -f1)
    ON_MIN=$(echo "$SCHEDULE_ON" | cut -d: -f2)
    OFF_HOUR=$(echo "$SCHEDULE_OFF" | cut -d: -f1)
    OFF_MIN=$(echo "$SCHEDULE_OFF" | cut -d: -f2)

    # Remove existing signage cron entries
    crontab -u "$PI_USER" -l 2>/dev/null | grep -v "hninas-signage" | crontab -u "$PI_USER" - 2>/dev/null || true

    # Add new cron entries
    (crontab -u "$PI_USER" -l 2>/dev/null || true; echo "$ON_MIN $ON_HOUR * * * $INSTALL_DIR/display-on.sh # hninas-signage") | crontab -u "$PI_USER" -
    (crontab -u "$PI_USER" -l 2>/dev/null || true; echo "$OFF_MIN $OFF_HOUR * * * $INSTALL_DIR/display-off.sh # hninas-signage") | crontab -u "$PI_USER" -

    print_ok "Cron schedule: ON at $SCHEDULE_ON, OFF at $SCHEDULE_OFF"
fi

# ── Configure auto-login and kiosk autostart ──
print_step "Configuring auto-login and kiosk autostart"

# Configure LightDM for autologin
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf << LDMEOF
[Seat:*]
autologin-user=$PI_USER
autologin-user-timeout=0
user-session=openbox
LDMEOF
print_ok "Auto-login configured for '$PI_USER'"

# Create openbox autostart for kiosk
OPENBOX_DIR="/home/$PI_USER/.config/openbox"
mkdir -p "$OPENBOX_DIR"
cat > "$OPENBOX_DIR/autostart" << ASEOF
# Hnina's Signage Kiosk Autostart
$INSTALL_DIR/kiosk.sh &
ASEOF
chown -R "$PI_USER:$PI_USER" "/home/$PI_USER/.config"
print_ok "Openbox autostart configured"

# ── Setup web management panel ──
print_step "Setting up web management panel"

# Copy web panel files
cp -r "$SCRIPT_DIR/web-panel/"* "$INSTALL_DIR/web-panel/" 2>/dev/null || mkdir -p "$INSTALL_DIR/web-panel"

# Create Python virtual environment
python3 -m venv "$INSTALL_DIR/web-panel/venv"
"$INSTALL_DIR/web-panel/venv/bin/pip" install flask werkzeug > /dev/null 2>&1
print_ok "Web panel dependencies installed"

# Copy web panel app
cp "$SCRIPT_DIR/web-panel/app.py" "$INSTALL_DIR/web-panel/app.py"
cp -r "$SCRIPT_DIR/web-panel/templates" "$INSTALL_DIR/web-panel/"
cp -r "$SCRIPT_DIR/web-panel/static" "$INSTALL_DIR/web-panel/" 2>/dev/null || true

# Create systemd service for web panel
cat > /etc/systemd/system/hninas-webpanel.service << SVCEOF
[Unit]
Description=Hnina's Signage Web Management Panel
After=network.target

[Service]
Type=simple
User=$PI_USER
WorkingDirectory=$INSTALL_DIR/web-panel
ExecStart=$INSTALL_DIR/web-panel/venv/bin/python app.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable hninas-webpanel
systemctl start hninas-webpanel 2>/dev/null || true
print_ok "Web panel service enabled (port 8080)"

# ── Set ownership ──
chown -R "$PI_USER:$PI_USER" "$INSTALL_DIR"

# ── Enable graphical target ──
systemctl set-default graphical.target

# ── Summary ──
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}Installation Complete!${NC}                              ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Display type:${NC}    $DISPLAY_TYPE"
if [ "$SCHEDULE_ENABLED" = "true" ]; then
    echo -e "  ${BOLD}Schedule:${NC}        ON at $SCHEDULE_ON / OFF at $SCHEDULE_OFF"
else
    echo -e "  ${BOLD}Schedule:${NC}        Always on (24/7)"
fi
echo -e "  ${BOLD}Install dir:${NC}     $INSTALL_DIR"
echo -e "  ${BOLD}User:${NC}            $PI_USER (password: pi)"
echo -e "  ${BOLD}SSH:${NC}             Enabled"
echo -e "  ${BOLD}Web panel:${NC}       http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<pi-ip>'):8080"
echo -e "  ${BOLD}HDMI:${NC}            1920x1080, overscan disabled"
echo ""
echo -e "  ${YELLOW}Reboot to start the kiosk display:${NC}"
echo -e "  ${BOLD}  sudo reboot${NC}"
echo ""
