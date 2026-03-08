# Hnina's Seafood - Digital Signage System

A complete digital menu board signage system for **Hnina's Seafood** (Ocoee, FL), designed for 1920x1080 displays with automatic viewport scaling. Runs on Raspberry Pi in kiosk mode with a web-based management panel.

## Live Demos

- **[Main Menu Screen](https://getdatasurge.github.io/hninas-seafood-signage/main-menu-screen/all-in-one.html)** - Left sidebar with daily specials & QR codes, 4x2 menu grid, scrolling ticker
- **[Two-Column Rotating](https://getdatasurge.github.io/hninas-seafood-signage/2-column-menu-screen/all-in-one.html)** - Header bar, two rotating menu columns with countdown timers, scrolling ticker

## Screen Layouts

### Screen 1: Main Menu
- Left sidebar: logo, daily specials (auto-highlights today), rotating QR codes, contact info
- Main area: 4x2 grid of menu categories with rotating pages and page-dot indicators
- Bottom: scrolling ticker with restaurant info

### Screen 2: Two-Column Rotating
- Top: header bar with logo and restaurant name
- Content: two independently rotating menu columns with numbered page indicators and countdown timer bars
- Bottom: scrolling ticker

## Features

- **Single-file HTML** - Each display is a self-contained HTML file (inline CSS + JS), only external dependencies are Google Fonts and QR code API
- **Auto-scaling viewport** - Designed at 1920x1080 but automatically scales to fit any screen size
- **GPU-optimized animations** - Uses `requestAnimationFrame`, `will-change`, `transform: translateZ(0)`, and `contain` for smooth 60fps rendering
- **Kiosk-ready** - Built for Chromium `--kiosk` mode on Raspberry Pi

## Project Structure

```
hninas-seafood-signage/
+-- index.html                    # Main Menu Screen (root)
+-- menu-rotate.html              # Two-Column Rotating Screen (root)
+-- main-menu-screen/
|   +-- all-in-one.html           # Standalone main menu (GitHub Pages)
|   +-- all-in-one.zip            # Downloadable package
|   +-- sidebar.html              # Sidebar component
|   +-- menu.html                 # Menu grid component
|   +-- ticker.html               # Ticker component
|   +-- media/                    # Images (logo, food photos)
+-- 2-column-menu-screen/
|   +-- all-in-one.html           # Standalone two-column (GitHub Pages)
|   +-- all-in-one.zip            # Downloadable package
|   +-- header.html               # Header component
|   +-- left-column.html          # Left column component
|   +-- right-column.html         # Right column component
|   +-- ticker.html               # Ticker component
|   +-- media/                    # Images (logo, food photos)
+-- pi-installer/
    +-- install.sh                # Raspberry Pi installer script
    +-- display-content/          # Display HTML files for Pi deployment
    +-- web-panel/
        +-- app.py                # Flask management panel
        +-- templates/            # Web panel HTML templates
```

## Raspberry Pi Installation

### Prerequisites
- Raspberry Pi 3B+ or newer
- Fresh Raspberry Pi OS (Debian-based) install
- HDMI display (1920x1080 recommended)
- Network connection

### Quick Install

```bash
# Clone the repo
git clone https://github.com/getdatasurge/hninas-seafood-signage.git
cd hninas-seafood-signage/pi-installer

# Run the installer as root
sudo bash install.sh
```

The installer will:
1. Prompt for display type selection (main menu or two-column)
2. Configure display schedule (on/off hours, or 24/7)
3. Scan and configure WiFi connection
4. Install all dependencies (Chromium, X server, Openbox, Flask, etc.)
5. Configure HDMI output at 1920x1080
6. Set up Chromium kiosk mode with LightDM autologin
7. Deploy the Flask web management panel on port 8080
8. Reboot into signage mode

### Web Management Panel

After installation, access the management panel at `http://<pi-ip>:8080`

- **Dashboard** - Display status, system info, quick actions
- **Display Settings** - Switch display type, configure daily on/off schedule
- **File Manager** - Upload new HTML, food images, and logos

### Default Credentials
- SSH user: `pi` / password: `pi`
- Web panel: No authentication (local network only)

## Design System

| Token | Value | Usage |
|-------|-------|-------|
| `--bg-dark` | `#1a1a2e` | Page background |
| `--bg-panel` | `#16213e` | Panel/sidebar background |
| `--bg-card` | `#0f3460` | Card background |
| `--accent` | `#e94560` | Primary accent (red) |
| `--accent-gold` | `#f5a623` | Secondary accent (gold) |
| `--text` | `#ffffff` | Primary text |
| `--text-muted` | `#b0b8c8` | Secondary text |

**Fonts:** Oswald (headings) + Open Sans (body)

## License

Proprietary - Hnina's Seafood. All rights reserved.
