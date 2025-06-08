#!/bin/bash
set -e

echo "🏗️  Building NFC Payment Terminal for Production Deployment..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf ../../dist/
rm -rf build/app-bundle/

# Create production bundle directory
mkdir -p build/app-bundle

# Install dependencies and build TypeScript (from root)
echo "📦 Installing dependencies..."
cd ../../
npm ci --production=false --silent >/dev/null 2>&1

echo "🔨 Building TypeScript..."
npm run build --silent >/dev/null 2>&1

# Return to deployment directory
cd scripts/rpi-deploy

# Create production bundle structure
echo "📁 Creating production bundle..."
mkdir -p build/app-bundle/{app,config}

# Copy built application (from root dist)
cp -r ../../dist/* build/app-bundle/app/

# Copy package files for production install (from root)
cp ../../package.json build/app-bundle/
cp ../../package-lock.json build/app-bundle/

# Copy source files that might be needed (from root)
cp -r ../../src/web build/app-bundle/app/

# Create production package.json (remove dev dependencies)
echo "📦 Creating production package.json..."
node -e "
const pkg = require('../../package.json');
delete pkg.devDependencies;
pkg.scripts = {
  'start': 'node app/server.js'
};
require('fs').writeFileSync('build/app-bundle/package.json', JSON.stringify(pkg, null, 2));
"

# Create systemd service file
echo "⚙️  Creating systemd service file..."
cat > build/app-bundle/config/nfc-terminal.service << 'EOF'
[Unit]
Description=NFC Payment Terminal
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=freepay
WorkingDirectory=/opt/nfc-terminal
Environment=NODE_ENV=production
EnvironmentFile=/opt/nfc-terminal/.env
ExecStart=/usr/bin/node app/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/nfc-terminal

[Install]
WantedBy=multi-user.target
EOF

# Create WiFi connection service
echo "📶 Creating WiFi connection service..."
cat > build/app-bundle/config/wifi-connect.service << 'EOF'
[Unit]
Description=WiFi Connection Service
Before=network-online.target
After=systemd-networkd.service wifi-unblock.service
Wants=wifi-unblock.service systemd-networkd.service

[Service]
Type=oneshot
ExecStartPre=/bin/bash -c 'for i in {1..10}; do if ip link show wlan0 2>/dev/null; then echo "wlan0 interface found"; break; else echo "Waiting for wlan0 interface ($i/10)"; sleep 2; fi; done'
ExecStartPre=/usr/sbin/rfkill unblock wifi
ExecStartPre=/usr/sbin/rfkill unblock wlan
ExecStartPre=/sbin/ip link set wlan0 up
ExecStartPre=/bin/bash -c 'echo "Checking wpa_supplicant config files..."; ls -la /etc/wpa_supplicant/wpa_supplicant*.conf'
ExecStart=/bin/bash -c 'echo "Manual WiFi connection approach..."; if ! pgrep wpa_supplicant.*wlan0; then echo "Starting wpa_supplicant for wlan0..."; wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -D nl80211; sleep 8; echo "Checking wpa_supplicant status..."; iwconfig wlan0 | grep ESSID || echo "Not associated yet"; fi; echo "Requesting DHCP..."; if systemctl is-active --quiet systemd-networkd; then echo "Using systemd-networkd for DHCP"; networkctl reload; networkctl reconfigure wlan0; else echo "Using dhclient for DHCP"; dhclient -v wlan0 || true; fi; sleep 5; echo "Final status:"; ip addr show wlan0'
RemainAfterExit=yes
TimeoutStartSec=90
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

# Create display setup service
echo "🖥️  Creating display setup service..."
cat > build/app-bundle/config/display-setup.service << 'EOF'
[Unit]
Description=Setup 7inch Display
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo "Display setup complete"'
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF

# Create Chromium kiosk service
echo "🌐 Creating Chromium kiosk service..."
cat > build/app-bundle/config/chromium-kiosk.service << 'EOF'
[Unit]
Description=Chromium Kiosk Mode
After=graphical-session.target nfc-terminal.service
Requires=nfc-terminal.service

[Service]
Type=simple
User=freepay
Environment=DISPLAY=:0
ExecStartPre=/bin/bash -c 'until curl -f http://localhost:3000; do sleep 2; done'
ExecStart=/usr/bin/chromium-browser --kiosk --disable-infobars --disable-session-crashed-bubble --disable-restore-session-state --disable-features=TranslateUI --no-first-run --fast --fast-start --disable-default-apps --disable-popup-blocking --disable-translate --disable-background-timer-throttling --disable-renderer-backgrounding --disable-device-discovery-notifications --autoplay-policy=no-user-gesture-required --no-sandbox --disable-dev-shm-usage http://localhost:3000
Restart=always
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

# Create first-boot configuration script
echo "🚀 Creating first-boot setup script..."
cat > build/app-bundle/config/first-boot-setup.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 NFC Payment Terminal - First Boot Setup"

# Enable auto-login for freepay user
echo "⚙️  Configuring auto-login..."
sudo systemctl set-default graphical.target
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /tmp/autologin.conf << AUTOLOGIN
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin freepay --noclear %I \$TERM
AUTOLOGIN
sudo mv /tmp/autologin.conf /etc/systemd/system/getty@tty1.service.d/

# Configure X11 to start automatically
echo "🖥️  Configuring X11 auto-start..."
sudo -u freepay mkdir -p /home/freepay/.config/autostart
cat > /tmp/autostart-x.desktop << AUTOSTART
[Desktop Entry]
Type=Application
Name=Start X and Chromium
Exec=startx
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
AUTOSTART
sudo mv /tmp/autostart-x.desktop /home/freepay/.config/autostart/
sudo chown freepay:freepay /home/freepay/.config/autostart/autostart-x.desktop

# Create .xinitrc for freepay user
echo "🌐 Configuring X11 startup..."
cat > /tmp/xinitrc << XINITRC
#!/bin/bash
# Disable screen blanking
xset -dpms
xset s off
xset s noblank

# Hide cursor
unclutter -idle 1 &

# Start window manager (lightweight)
openbox-session &

# Wait for window manager
sleep 2

# Start Chromium kiosk
chromium-browser --kiosk --no-sandbox --disable-infobars --disable-session-crashed-bubble --disable-restore-session-state --disable-features=TranslateUI --no-first-run --fast --fast-start --disable-default-apps --disable-popup-blocking --disable-translate --disable-background-timer-throttling --disable-renderer-backgrounding --disable-device-discovery-notifications --autoplay-policy=no-user-gesture-required --disable-dev-shm-usage http://localhost:3000
XINITRC
sudo mv /tmp/xinitrc /home/freepay/.xinitrc
sudo chown freepay:freepay /home/freepay/.xinitrc
sudo chmod +x /home/freepay/.xinitrc

echo "✅ First boot setup complete"
echo "System will reboot to apply changes..."
sudo reboot
EOF
chmod +x build/app-bundle/config/first-boot-setup.sh

# Create install script for the Pi
echo "📥 Creating Pi installation script..."
cat > build/app-bundle/install-on-pi.sh << 'EOF'
#!/bin/bash
set -e

echo "📦 Installing NFC Payment Terminal on Raspberry Pi..."

# Update system
echo "🔄 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install required packages
echo "📦 Installing required packages..."
sudo apt install -y nodejs npm chromium-browser openbox unclutter libnfc-bin libpcsclite-dev pcscd pcsc-tools

# Install ACR1252U-M1 specific drivers
echo "📡 Installing ACR1252U-M1 NFC reader drivers..."
wget -O /tmp/acsccid.deb http://downloads.acs.com.hk/drivers/en/API-ACR1252U-M1-P1.5.01/API-ACR1252U-M1-P1.5.01.tar.gz
cd /tmp && tar -xzf API-ACR1252U-M1-P1.5.01.tar.gz
sudo dpkg -i acsccid_*.deb || sudo apt-get install -f -y

# Install application
echo "📁 Installing application..."
sudo mkdir -p /opt/nfc-terminal
sudo cp -r app/* /opt/nfc-terminal/
sudo cp .env /opt/nfc-terminal/ 2>/dev/null || echo "⚠️  No .env file found - will be created by build script"
sudo chown -R freepay:freepay /opt/nfc-terminal

# Install application dependencies
echo "📦 Installing Node.js dependencies..."
cd /opt/nfc-terminal
sudo -u freepay npm ci --production --silent >/dev/null 2>&1

# Install systemd services
echo "⚙️  Installing systemd services..."
sudo cp config/*.service /etc/systemd/system/
sudo systemctl daemon-reload

# Enable services
echo "🚀 Enabling services..."
sudo systemctl enable wifi-connect.service
sudo systemctl enable nfc-terminal.service
sudo systemctl enable display-setup.service

# Configure PCSC for NFC
echo "📡 Configuring NFC services..."
sudo systemctl enable pcscd
sudo usermod -a -G plugdev freepay

echo "✅ Installation complete!"
echo "Run first-boot setup with: sudo ./config/first-boot-setup.sh"
EOF
chmod +x build/app-bundle/install-on-pi.sh

# Create environment template
echo "📝 Creating environment template..."
cat > build/app-bundle/.env.template << 'EOF'
# This file will be populated by the build script
# with values from build-config.env

NODE_ENV=production
PORT=3000
LOG_LEVEL=info

# These will be injected during build:
# ALCHEMY_API_KEY=
# MERCHANT_ETH_ADDRESS=
# BLOCKCHAIN_NETWORKS=
EOF

# Create updated systemd services and helpers for freepay user
echo "⚙️  Creating freepay user services and helpers..."

# Update NFC terminal service for freepay user
cat > build/app-bundle/config/nfc-terminal.service << 'EOF'
[Unit]
Description=NFC Payment Terminal
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=freepay
WorkingDirectory=/opt/nfc-terminal
Environment=NODE_ENV=production
EnvironmentFile=-/opt/nfc-terminal/.env
ExecStartPre=/bin/bash -c 'echo "Checking NFC terminal directory..."; ls -la /opt/nfc-terminal/ || (echo "ERROR: /opt/nfc-terminal not found"; exit 1)'
ExecStartPre=/bin/bash -c 'echo "Checking Node.js and server.js..."; which node || echo "Node.js not found"; ls -la /opt/nfc-terminal/server.js || echo "server.js not found"'
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/nfc-terminal

[Install]
WantedBy=multi-user.target
EOF

# Create start-gui service
cat > build/app-bundle/config/start-gui.service << 'EOF'
[Unit]
Description=Start GUI for NFC Terminal
After=multi-user.target nfc-terminal.service
Wants=nfc-terminal.service
Before=getty@tty1.service
Conflicts=getty@tty1.service

[Service]
Type=simple
User=root
Group=root
Environment=HOME=/home/freepay
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=/run/user/1000
WorkingDirectory=/home/freepay
ExecStartPre=/bin/bash -c 'echo "Waiting for freepay user..."; for i in {1..60}; do if id freepay &>/dev/null; then echo "freepay user found: $(id freepay)"; break; else echo "Waiting for freepay user ($i/60)"; sleep 1; fi; done; if ! id freepay &>/dev/null; then echo "ERROR: freepay user not found after 60 seconds"; exit 1; fi'
ExecStartPre=/bin/bash -c 'echo "Setting up runtime directory..."; mkdir -p /run/user/1000; chown freepay:freepay /run/user/1000; chmod 700 /run/user/1000'
ExecStartPre=/bin/bash -c 'echo "Verifying home directory..."; ls -la /home/freepay || (echo "ERROR: /home/freepay not found"; exit 1)'
ExecStartPre=/bin/bash -c 'echo "Verifying GUI files..."; test -f /home/freepay/start-kiosk.sh || (echo "ERROR: start-kiosk.sh not found"; exit 1); test -x /home/freepay/start-kiosk.sh || (echo "ERROR: start-kiosk.sh not executable"; exit 1)'
ExecStartPre=/bin/bash -c 'echo "Checking GUI packages..."; which chromium-browser || (echo "ERROR: chromium-browser not installed"; exit 1); which openbox || (echo "ERROR: openbox not installed"; exit 1)'
ExecStartPre=/bin/bash -c 'echo "Verifying NFC terminal accessibility..."; timeout 30 bash -c "until curl -f http://localhost:3000 >/dev/null 2>&1; do sleep 2; done" || echo "WARNING: NFC terminal not responding, proceeding anyway"'
ExecStartPre=/bin/bash -c 'echo "Starting X11 server for freepay user..."'
ExecStart=/bin/bash -c 'cd /home/freepay && export HOME=/home/freepay && export USER=freepay && sudo -u freepay env HOME=/home/freepay USER=freepay DISPLAY=:0 /usr/bin/startx /home/freepay/start-kiosk.sh -- :0 vt1 -keeptty -nolisten tcp'
Restart=always
RestartSec=20
StandardOutput=journal
StandardError=journal
KillMode=mixed
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target graphical.target
EOF

# Create WiFi unblock service
cat > build/app-bundle/config/wifi-unblock.service << 'EOF'
[Unit]
Description=Unblock WiFi on boot
Before=wifi-connect.service wpa_supplicant@wlan0.service systemd-networkd.service
After=rfkill-unblock-wifi.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStartPre=/bin/bash -c 'echo "Checking rfkill status..."; rfkill list || true'
ExecStart=/bin/bash -c 'echo "Unblocking WiFi interfaces..."; rfkill unblock wifi; rfkill unblock wlan; rfkill unblock all'
ExecStartPost=/bin/bash -c 'echo "WiFi unblock completed"; rfkill list wifi || true'
RemainAfterExit=yes
TimeoutStartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create a simple diagnostic service to help debug boot issues
cat > build/app-bundle/config/boot-debug.service << 'EOF'
[Unit]
Description=Boot Debug Service
After=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 15; echo "=== Boot Debug $(date) ===" > /tmp/boot-debug.log; echo "Freepay User Check:" >> /tmp/boot-debug.log; id freepay >> /tmp/boot-debug.log 2>&1 || echo "freepay user not found" >> /tmp/boot-debug.log; echo "Home Directory:" >> /tmp/boot-debug.log; ls -la /home/ >> /tmp/boot-debug.log; echo "Runtime Directory:" >> /tmp/boot-debug.log; ls -la /run/user/ >> /tmp/boot-debug.log 2>&1 || echo "no /run/user/" >> /tmp/boot-debug.log; echo "Failed Services:" >> /tmp/boot-debug.log; systemctl list-units --failed >> /tmp/boot-debug.log; echo "GUI Service Status:" >> /tmp/boot-debug.log; systemctl status start-gui.service >> /tmp/boot-debug.log 2>&1; echo "GUI Service Logs:" >> /tmp/boot-debug.log; journalctl -u start-gui.service --no-pager -n 20 >> /tmp/boot-debug.log 2>&1; echo "=== End Debug ===" >> /tmp/boot-debug.log'
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF

# Create kiosk startup script (enhanced with complete portrait mode support)
echo "🖥️  Creating kiosk startup script..."
cat > build/app-bundle/config/start-kiosk.sh << 'EOF'
#!/bin/bash
echo "🖥️ Starting NFC Terminal Kiosk Mode..."

# Set display for portrait mode (90 degrees clockwise)
export DISPLAY=:0

# Wait for X server to be ready
echo "⏳ Waiting for X server..."
for i in {1..30}; do
    if xdpyinfo >/dev/null 2>&1; then
        echo "✅ X server is ready"
        break
    fi
    echo "Waiting for X server ($i/30)..."
    sleep 1
done

# Wait for NFC terminal service to be ready
echo "⏳ Waiting for NFC terminal service..."
timeout=120
while [ $timeout -gt 0 ]; do
    if curl -f http://localhost:3000 > /dev/null 2>&1; then
        echo "✅ NFC terminal service ready"
        break
    fi
    echo "NFC terminal not ready, waiting... ($timeout seconds left)"
    sleep 2
    timeout=$((timeout - 2))
done

if [ $timeout -le 0 ]; then
    echo "❌ ERROR: NFC terminal service not available after 2 minutes"
    # Show an error page instead of exiting
    echo "<html><body><h1>NFC Terminal Starting...</h1><p>Please wait while the service initializes.</p></body></html>" > /tmp/loading.html
    chromium-browser --kiosk --no-sandbox file:///tmp/loading.html &
    sleep 30
    # Try to connect again
    if curl -f http://localhost:3000 > /dev/null 2>&1; then
        pkill chromium-browser
    else
        exit 1
    fi
fi

# Configure display rotation (90 degrees counterclockwise for portrait)
echo "🔄 Setting up portrait display rotation..."
xrandr --output HDMI-1 --rotate left 2>/dev/null || \
xrandr --output HDMI-2 --rotate left 2>/dev/null || \
xrandr --output HDMI-A-1 --rotate left 2>/dev/null || \
echo "Display rotation not applied (may be configured at boot level)"

# Configure touchscreen for portrait mode (swap axes approach)
echo "👆 Configuring touchscreen..."
xinput set-prop "ADS7846 Touchscreen" "Coordinate Transformation Matrix" 1 0 0 0 1 0 0 0 1 2>/dev/null || \
echo "Touchscreen transformation not applied (device may not be present)"

# Set up display power management
echo "⚡ Configuring display settings..."
xset -dpms
xset s off  
xset s noblank

# Hide cursor
echo "🖱️ Hiding mouse cursor..."
unclutter -idle 1 &

echo "🌐 Starting Chromium in kiosk mode..."
exec chromium-browser \
    --kiosk \
    --app=http://localhost:3000 \
    --no-sandbox \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --disable-features=TranslateUI,VizDisplayCompositor,TouchpadAndWheelScrollLatching,kBackgroundResourceFetch \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-default-apps \
    --disable-popup-blocking \
    --disable-translate \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --disable-device-discovery-notifications \
    --disable-suggestions-service \
    --disable-save-password-bubble \
    --autoplay-policy=no-user-gesture-required \
    --disable-dev-shm-usage \
    --disable-extensions \
    --disable-plugins \
    --disable-web-security \
    --allow-running-insecure-content \
    --touch-events=enabled \
    --start-fullscreen \
    --window-size=480,800 \
    --window-position=0,0 \
    --force-device-scale-factor=1 \
    --overscroll-history-navigation=0 \
    --disable-pinch \
    --disable-features=Translate \
    --hide-scrollbars \
    --no-default-browser-check \
    --no-first-run \
    --disable-background-color
EOF
chmod +x build/app-bundle/config/start-kiosk.sh

# Create touch screen calibration script
echo "📱 Creating touch screen calibration script..."
cat > build/app-bundle/config/calibrate-touch.sh << 'EOF'
#!/bin/bash
echo "Touch Screen Calibration Tool (Portrait Mode)"
echo "=============================================="
echo "This script helps calibrate your 5\" touchscreen in portrait mode."
echo ""
echo "Current configuration:"
echo "- Display: Portrait mode (90° counterclockwise rotation)"
echo "- Touch rotation: Configured with transformation matrix (no inversion)"
echo ""
echo "Touch configuration files:"
echo "- Hardware config: /boot/config.txt (ads7846 overlay)"
echo "- X11 config: /etc/X11/xorg.conf.d/99-calibration.conf"
echo ""
echo "To run interactive calibration:"
echo "1. Make sure X11 is running (startx)"
echo "2. Run: xinput_calibrator"
echo "3. Follow the on-screen instructions"
echo "4. Update values in X11 config if needed"
echo ""
echo "Portrait mode settings:"
echo "- TransformationMatrix: \"1 0 0 0 1 0 0 0 1\" (identity - no transformation)"
echo "- SwapAxes: enabled (hardware-level axis swapping for rotation)"
echo "- InvertX: disabled, InvertY: enabled (correct orientation for left rotation)"
echo ""
echo "Current hardware configuration:"
grep "ads7846" /boot/config.txt || echo "No ads7846 configuration found"
echo ""
echo "Current X11 touch configuration:"
cat /etc/X11/xorg.conf.d/99-calibration.conf 2>/dev/null || echo "X11 touch config not found"
EOF
chmod +x build/app-bundle/config/calibrate-touch.sh

# Create WiFi connection helper script
echo "📶 Creating WiFi helper script..."
cat > build/app-bundle/config/connect-wifi.sh << 'EOF'
#!/bin/bash
echo "WiFi Connection Helper"
echo "======================"
echo ""

# Check current WiFi status
echo "Current WiFi status:"
if rfkill list wifi | grep -q "Soft blocked: yes"; then
    echo "❌ WiFi is blocked by rfkill"
    echo "   Attempting to unblock..."
    sudo rfkill unblock wifi
    sleep 2
fi

iwconfig wlan0 2>/dev/null | grep ESSID

echo ""
echo "Attempting WiFi connection..."

# Check if wpa_supplicant is running
if pgrep -x "wpa_supplicant" > /dev/null; then
    echo "✅ wpa_supplicant is running"
else
    echo "🔄 Starting wpa_supplicant..."
    if sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf; then
        echo "✅ wpa_supplicant started"
        sleep 5
        
        # Check if associated
        if iwconfig wlan0 2>/dev/null | grep -q "Access Point"; then
            echo "✅ WiFi associated"
            echo "   Getting IP address..."
            if sudo dhclient wlan0; then
                echo "✅ DHCP successful"
                ip addr show wlan0 | grep "inet "
            else
                echo "⚠️  WiFi associated but DHCP failed"
                echo "   Check router DHCP settings"
            fi
        else
            echo "❌ Failed to start wpa_supplicant"
            echo "   Check WiFi credentials in /etc/wpa_supplicant/wpa_supplicant.conf"
        fi
    else
        echo "❌ Failed to start wpa_supplicant"
        echo "   Check WiFi credentials in /etc/wpa_supplicant/wpa_supplicant.conf"
    fi
else
    echo "✅ WiFi already connected"
    iwconfig wlan0 2>/dev/null | grep ESSID
    ip addr show wlan0 | grep "inet "
fi

echo ""
echo "💡 Note: NFC terminal works with ethernet if WiFi fails"
echo "   Check service status: sudo systemctl status nfc-terminal"
EOF
chmod +x build/app-bundle/config/connect-wifi.sh

# Create GUI debug script
echo "🔍 Creating GUI debug script..."
cat > build/app-bundle/config/debug-gui.sh << 'EOF'
#!/bin/bash
echo "🔍 NFC Terminal GUI Debug Script"
echo "================================="
echo ""

echo "📊 System Status:"
echo "- Uptime: $(uptime)"
echo "- Default target: $(systemctl get-default)"
echo "- Current user: $(whoami)"
echo "- Groups: $(groups)"
echo ""

echo "🔧 Service Status:"
echo "- NFC Terminal: $(systemctl is-active nfc-terminal.service)"
echo "- Start GUI: $(systemctl is-active start-gui.service)"
echo "- Display Setup: $(systemctl is-active display-setup.service)"
echo ""

echo "🌐 Network Status:"
echo "- NFC Terminal responding: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 || echo "No response")"
echo ""

echo "🖥️ Display Status:"
echo "- X11 processes: $(ps aux | grep -E '[Xx]org|xinit|startx' | wc -l) running"
echo "- Chromium processes: $(ps aux | grep -v grep | grep chromium | wc -l) running"
echo ""

echo "📁 Critical Files Check:"
echo "- start-kiosk.sh: $(test -f /home/freepay/start-kiosk.sh && echo "✅ exists" || echo "❌ missing")"
echo "- start-kiosk.sh executable: $(test -x /home/freepay/start-kiosk.sh && echo "✅ yes" || echo "❌ no")"
echo "- .xinitrc: $(test -f /home/freepay/.xinitrc && echo "✅ exists" || echo "❌ missing")"
echo "- X11 wrapper config: $(test -f /etc/X11/Xwrapper.config && echo "✅ exists" || echo "❌ missing")"
echo ""

echo "📦 Required Packages:"
for pkg in chromium-browser openbox unclutter xinit curl; do
    if command -v $pkg >/dev/null 2>&1; then
        echo "- $pkg: ✅ installed"
    else
        echo "- $pkg: ❌ missing"
    fi
done
echo ""

echo "👤 User & Permissions:"
echo "- freepay user: $(id freepay 2>/dev/null || echo "❌ not found")"
echo "- freepay groups: $(groups freepay 2>/dev/null || echo "❌ cannot check")"
echo "- Runtime dir: $(test -d /run/user/1000 && echo "✅ exists" || echo "❌ missing")"
echo "- Runtime ownership: $(ls -ld /run/user/1000 2>/dev/null | awk '{print $3":"$4}' || echo "❌ cannot check")"
echo ""

echo "🖥️ X11 Configuration:"
echo "- X11 wrapper config:"
cat /etc/X11/Xwrapper.config 2>/dev/null || echo "❌ File not found"
echo ""

echo "📋 Detailed Service Logs (last 20 lines):"
echo ""
echo "=== NFC Terminal Service ==="
sudo journalctl -u nfc-terminal.service --no-pager -l -n 20
echo ""
echo "=== Start GUI Service ==="
sudo journalctl -u start-gui.service --no-pager -l -n 20
echo ""

echo "🔧 Manual Test Commands:"
echo ""
echo "To test GUI manually:"
echo "1. Stop the service: sudo systemctl stop start-gui.service"
echo "2. Kill any stuck X processes: sudo pkill -f 'Xorg|xinit'"
echo "3. Test kiosk script directly: sudo -u freepay /home/freepay/start-kiosk.sh"
echo "4. Test X11 manually: sudo -u freepay DISPLAY=:0 startx /home/freepay/start-kiosk.sh -- :0 vt1"
echo ""
echo "To see live logs:"
echo "sudo journalctl -u start-gui.service -f"
echo ""
echo "To restart everything cleanly:"
echo "sudo systemctl stop start-gui.service"
echo "sudo pkill -f 'Xorg|xinit|chromium'"
echo "sudo systemctl start start-gui.service"
echo ""
EOF
chmod +x build/app-bundle/config/debug-gui.sh

# Create .xinitrc for X11 startup (enhanced with complete portrait mode support)
echo "🪟 Creating .xinitrc..."
cat > build/app-bundle/config/xinitrc << 'EOF'
#!/bin/bash
echo "🪟 Starting X11 session with portrait mode..."

# Set display
export DISPLAY=:0

# Disable screen saver and power management
echo "⚡ Configuring display power management..."
xset -dpms
xset s off
xset s noblank

# Configure display rotation (90 degrees counterclockwise for portrait)
echo "🔄 Setting up portrait display rotation..."
xrandr --output HDMI-1 --rotate left 2>/dev/null || \
xrandr --output HDMI-2 --rotate left 2>/dev/null || \
xrandr --output HDMI-A-1 --rotate left 2>/dev/null || \
echo "Display rotation not applied (may be configured at boot level)"

# Configure touchscreen for portrait mode (swap axes approach)
echo "👆 Configuring touchscreen transformation..."
xinput set-prop "ADS7846 Touchscreen" "Coordinate Transformation Matrix" 1 0 0 0 1 0 0 0 1 2>/dev/null || \
echo "Touchscreen transformation not applied (device may not be present)"

# Hide cursor after 1 second of inactivity
echo "🖱️ Hiding mouse cursor..."
unclutter -idle 1 &

# Start window manager
echo "🪟 Starting window manager..."
openbox-session &

# Wait for window manager to initialize
echo "⏳ Waiting for window manager..."
sleep 3

# Start the kiosk application
echo "🚀 Launching kiosk application..."
exec /home/freepay/start-kiosk.sh
EOF
chmod +x build/app-bundle/config/xinitrc

# Create .bashrc append for freepay user (minimal - using systemd service for GUI)
echo "📝 Creating bashrc configuration..."
cat > build/app-bundle/config/bashrc-append << 'EOF'

# freepay user configuration
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games"
EOF

# Create X11 input configuration for 5" touchscreen (portrait mode)
echo "👆 Creating X11 touch configuration..."
mkdir -p build/app-bundle/config/xorg.conf.d
cat > build/app-bundle/config/xorg.conf.d/99-calibration.conf << 'EOF'
Section "InputClass"
    Identifier "calibration"
    MatchProduct "ADS7846 Touchscreen"
    Option "Calibration" "200 3900 200 3900"
    Option "SwapAxes" "0"
    Option "InvertX" "true"
    Option "InvertY" "false"
    Option "TransformationMatrix" "1 0 0 0 1 0 0 0 1"
EndSection

Section "InputClass"
    Identifier "evdev touchscreen catchall"
    MatchIsTouchscreen "on"
    MatchDevicePath "/dev/input/event*"
    Driver "evdev"
    Option "TransformationMatrix" "1 0 0 0 1 0 0 0 1"
EndSection
EOF

# Create udev rule for WiFi unblocking
echo "📡 Creating udev rules..."
mkdir -p build/app-bundle/config/udev/rules.d
cat > build/app-bundle/config/udev/rules.d/10-wifi-unblock.rules << 'EOF'
# Automatically unblock WiFi on boot
ACTION=="add", SUBSYSTEM=="rfkill", ATTR{type}=="wlan", ATTR{state}="0"
EOF

# Create user setup scripts
echo "👤 Creating user setup scripts..."

# SSH user setup script
cat > build/app-bundle/config/setup-ssh-user.sh << 'EOF'
#!/bin/bash
echo "Setting up SSH user..."

# Set default values if not provided
SSH_USERNAME=${SSH_USERNAME:-freepay}
SSH_PASSWORD=${SSH_PASSWORD:-freepay}

echo "Setting up SSH user: $SSH_USERNAME"

if [ -z "$SSH_USERNAME" ] || [ "$SSH_USERNAME" = "SSH_USERNAME_VALUE" ]; then
    echo "❌ No valid SSH username provided, skipping SSH user setup"
    exit 0
fi

# Create the user if it doesn't exist
if ! id "$SSH_USERNAME" &>/dev/null; then
    if useradd -m -s /bin/bash "$SSH_USERNAME"; then
        echo "✅ User $SSH_USERNAME created"
    else
        echo "❌ Failed to create user $SSH_USERNAME"
        exit 1
    fi
else
    echo "✅ User $SSH_USERNAME already exists"
fi

# Set password
if echo "$SSH_USERNAME:$SSH_PASSWORD" | chpasswd; then
    echo "✅ Password set for $SSH_USERNAME"
else
    echo "❌ Failed to set password for $SSH_USERNAME"
    exit 1
fi

# Add user to essential groups
echo "Adding $SSH_USERNAME to groups..."
for group in sudo plugdev dialout; do
    if getent group "$group" &>/dev/null; then
        if usermod -aG "$group" "$SSH_USERNAME"; then
            echo "✅ Added $SSH_USERNAME to $group group"
        else
            echo "❌ Failed to add $SSH_USERNAME to $group group"
        fi
    else
        echo "⚠️  Group $group does not exist"
    fi
done

# Ensure SSH directory exists for the user
echo "Setting up SSH directory..."
if mkdir -p "/home/$SSH_USERNAME/.ssh" && chmod 700 "/home/$SSH_USERNAME/.ssh" && chown "$SSH_USERNAME:$SSH_USERNAME" "/home/$SSH_USERNAME/.ssh"; then
    echo "✅ SSH directory setup completed"
else
    echo "❌ Failed to setup SSH directory"
fi

echo "✅ SSH user $SSH_USERNAME setup completed successfully"
EOF
chmod +x build/app-bundle/config/setup-ssh-user.sh

# Freepay user setup script
cat > build/app-bundle/config/setup-freepay-user.sh << 'EOF'
#!/bin/bash
echo "Setting up main freepay user..."

# Function to safely create user
create_freepay_user() {
    # Kill any processes by existing freepay user
    pkill -u freepay 2>/dev/null || true
    sleep 1
    
    # Remove existing freepay user if it exists
    if id freepay &>/dev/null; then
        echo "Removing existing freepay user..."
        userdel -r freepay 2>/dev/null || userdel -f freepay 2>/dev/null || true
        # Clean up home directory if it still exists
        rm -rf /home/freepay 2>/dev/null || true
    fi
    
    # Check if UID 1000 is taken by another user
    if getent passwd 1000 &>/dev/null; then
        existing_user=$(getent passwd 1000 | cut -d: -f1)
        if [ "$existing_user" != "freepay" ]; then
            echo "UID 1000 taken by $existing_user, removing..."
            pkill -u "$existing_user" 2>/dev/null || true
            sleep 1
            userdel -r "$existing_user" 2>/dev/null || userdel -f "$existing_user" 2>/dev/null || true
            # Clean up any remaining home directory
            rm -rf "/home/$existing_user" 2>/dev/null || true
        fi
    fi
    
    # Ensure no conflicting home directory exists
    if [ -d "/home/freepay" ]; then
        echo "Cleaning up existing home directory..."
        rm -rf /home/freepay
    fi
    
    # Create freepay user with UID 1000
    echo "Creating freepay user with UID 1000..."
    if useradd -m -s /bin/bash -u 1000 -U freepay; then
        echo "✅ freepay user created successfully"
    else
        echo "❌ Failed to create with UID 1000, trying alternative..."
        # Try without specific UID as fallback
        if useradd -m -s /bin/bash -U freepay; then
            echo "✅ freepay user created with auto-assigned UID"
        else
            echo "❌ Failed to create freepay user"
            return 1
        fi
    fi
}

# Attempt user creation
if ! create_freepay_user; then
    echo "❌ Failed to create freepay user, exiting"
    exit 1
fi

# Set password - try multiple methods for reliability
echo "Setting password for freepay..."
if echo "freepay:freepay" | chpasswd; then
    echo "✅ Password set via chpasswd"
elif printf "freepay\nfreepay\n" | passwd freepay; then
    echo "✅ Password set via passwd"
else
    echo "❌ Failed to set password"
fi

# Add to groups
echo "Adding freepay to essential groups..."
for group in sudo plugdev dialout video audio input tty users; do
    if getent group "$group" &>/dev/null; then
        usermod -aG "$group" freepay && echo "✅ Added to $group" || echo "❌ Failed to add to $group"
    else
        echo "⚠️  Group $group does not exist"
    fi
done

# Setup directories
echo "Setting up directories..."
mkdir -p /home/freepay
chown -R freepay:freepay /home/freepay 2>/dev/null || echo "❌ Failed to set home ownership"
chmod 755 /home/freepay

# Setup runtime directory for X11
user_id=$(id -u freepay 2>/dev/null || echo "1000")
mkdir -p "/run/user/$user_id"
chown freepay:freepay "/run/user/$user_id" 2>/dev/null || echo "❌ Failed to set runtime dir ownership"
chmod 700 "/run/user/$user_id"

# Add to sudoers for passwordless sudo
echo "Setting up sudo access..."
mkdir -p /etc/sudoers.d
echo "freepay ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/freepay
chmod 440 /etc/sudoers.d/freepay

# Verify setup
echo "Verifying freepay user setup..."
if id freepay &>/dev/null; then
    echo "✅ User info: $(id freepay)"
    echo "✅ Groups: $(groups freepay)"
    echo "✅ Home: $(ls -ld /home/freepay 2>/dev/null || echo 'not found')"
    echo "✅ Runtime: $(ls -ld /run/user/$user_id 2>/dev/null || echo 'not found')"
    echo "✅ Freepay user setup completed successfully"
else
    echo "❌ ERROR: freepay user verification failed"
    exit 1
fi
EOF
chmod +x build/app-bundle/config/setup-freepay-user.sh

echo ""
echo "✅ Production build complete!"
echo ""
echo "Created files:"
echo "  - build/app-bundle/ (complete application bundle)"
echo "  - build/app-bundle/app/ (built application)"
echo "  - build/app-bundle/config/ (systemd services & helper scripts)"
echo "  - build/app-bundle/install-on-pi.sh (Pi installation script)"
echo "  - build/app-bundle/.env.template (environment template)"
echo ""
echo "Configuration files created:"
echo "  - *.service files (systemd services)"
echo "  - Helper scripts (start-kiosk.sh, debug-gui.sh, etc.)"
echo "  - X11 configuration (xinitrc, touch calibration)"
echo "  - User setup scripts (freepay & SSH users)"
echo ""
echo "Next: Run image creation script to embed this into Raspberry Pi image" 