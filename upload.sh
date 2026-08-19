#!/bin/bash

# ============================================================
# ROM BUILD / UPLOAD TELEGRAM NOTIFIER
# ============================================================

BOT_TOKEN="8617652855:AAFfFBA0kXwOGepBzcgfWuSAvq07iMLrtW4"
CHAT_ID="-1003884099920"

# ============================================================
# Colors
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ============================================================
# Timing
# ============================================================

SCRIPT_START_EPOCH=$(date +%s)

START_DATE=$(date '+%d %B %Y')
START_TIME=$(date '+%H:%M:%S')
START_DATETIME=$(date '+%d %B %Y, %H:%M:%S %Z')

# ============================================================
# Telegram
# ============================================================

send_telegram() {
    curl -s -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode text="$1" \
        -d parse_mode="HTML" \
        > /dev/null
}

# ============================================================
# Logging
# ============================================================

log() {
    echo -e "[$(date '+%H:%M:%S')] $1"
}

sep() {
    echo "============================================================"
}

success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $1${RESET}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $1${RESET}"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $1${RESET}"
}

# ============================================================
# Cleanup
# ============================================================

TMP_DIR=""

cleanup() {
    [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

trap cleanup EXIT

# ============================================================
# Duration formatter
# ============================================================

format_duration() {
    local seconds="$1"

    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [[ "$days" -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m ${secs}s"
    elif [[ "$hours" -gt 0 ]]; then
        echo "${hours}h ${minutes}m ${secs}s"
    elif [[ "$minutes" -gt 0 ]]; then
        echo "${minutes}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

# ============================================================
# File size
# ============================================================

file_size() {
    if [[ -f "$1" ]]; then
        du -h "$1" | awk '{print $1}'
    else
        echo "N/A"
    fi
}

# ============================================================
# Hash
# ============================================================

md5_hash() {
    if [[ -f "$1" ]]; then
        md5sum "$1" | awk '{print $1}'
    else
        echo "N/A"
    fi
}

sha256_hash() {
    if [[ -f "$1" ]]; then
        sha256sum "$1" | awk '{print $1}'
    else
        echo "N/A"
    fi
}

# ============================================================
# Link formatter
# ============================================================

fmt_link() {
    local link="$1"

    if [[ -n "$link" && "$link" != "N/A" && "$link" != "null" ]]; then
        echo "<a href=\"$link\">Download</a>"
    else
        echo "N/A"
    fi
}

# ============================================================
# Git information
# ============================================================

git_info() {
    local dir="$1"

    if [[ -d "$dir/.git" ]]; then
        local branch
        local commit

        branch=$(git -C "$dir" branch --show-current 2>/dev/null)
        commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)

        [[ -z "$branch" ]] && branch="detached"

        echo "${branch}@${commit}"
    else
        echo "N/A"
    fi
}

# ============================================================
# Start
# ============================================================

clear

sep
echo -e "${CYAN}          ROM BUILD / UPLOAD SCRIPT${RESET}"
sep

log "Script started"
log "Start date : $START_DATE"
log "Start time : $START_TIME"
log "Timezone   : $(date '+%Z (%z)')"
log "Timestamp  : $(date +%s)"
sep

# ============================================================
# Basic system information
# ============================================================

HOSTNAME_INFO=$(hostname 2>/dev/null || echo "Unknown")
BUILD_USER=$(whoami 2>/dev/null || echo "Unknown")
HOST_KERNEL=$(uname -r 2>/dev/null || echo "Unknown")
HOST_ARCH=$(uname -m 2>/dev/null || echo "Unknown")

if command -v lsb_release >/dev/null 2>&1; then
    HOST_OS=$(lsb_release -ds 2>/dev/null)
else
    HOST_OS=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null \
        | cut -d= -f2- \
        | tr -d '"' || echo "Unknown")
fi

log "Build host : $HOSTNAME_INFO"
log "Build user : $BUILD_USER"
log "Host OS    : $HOST_OS"
log "Host kernel: $HOST_KERNEL"
log "Host arch  : $HOST_ARCH"

# ============================================================
# Detect device
# ============================================================

PRODUCT_BASE="out/target/product"

log "Detecting device..."

DEVICE=$(find "$PRODUCT_BASE" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    ! -name generic \
    ! -name obj \
    ! -name symbols \
    -printf "%f\n" 2>/dev/null \
    | head -n 1)

PRODUCT_DIR="$PRODUCT_BASE/$DEVICE"

if [[ -z "$DEVICE" || ! -d "$PRODUCT_DIR" ]]; then

    error "Device directory not detected"

    send_telegram \
"<b>❌ BUILD FAILED</b>

<b>Reason:</b> Device directory not detected
<b>Time:</b> ${START_DATETIME}
<b>Host:</b> ${HOSTNAME_INFO}"

    exit 1
fi

success "Device detected: $DEVICE"

# ============================================================
# ROM ZIP
# ============================================================

sep
log "Searching for ROM ZIP..."

ROM_ZIP=$(find "$PRODUCT_DIR" \
    -type f \
    -name "*${DEVICE}*.zip" \
    | grep -Ev "ota|symbol|target_files" \
    | sort -r \
    | head -n 1)

if [[ ! -f "$ROM_ZIP" ]]; then

    error "ROM ZIP not found"

    send_telegram \
"<b>❌ BUILD FAILED</b>

<b>Reason:</b> ROM ZIP not found
<b>Device:</b> ${DEVICE}
<b>Time:</b> ${START_DATETIME}
<b>Host:</b> ${HOSTNAME_INFO}"

    exit 1
fi

ZIP_NAME=$(basename "$ROM_ZIP")

success "ROM ZIP found: $ZIP_NAME"

# ============================================================
# ROM metadata
# ============================================================

ROM_NAME=$(echo "$ZIP_NAME" \
    | sed -E "s/-${DEVICE}.*//")

if echo "$ZIP_NAME" | grep -qi "UNOFFICIAL"; then
    BUILD_TYPE="Unofficial"
elif echo "$ZIP_NAME" | grep -qi "OFFICIAL"; then
    BUILD_TYPE="Official"
else
    BUILD_TYPE="Unknown"
fi

# ============================================================
# Android information
# ============================================================

ANDROID_VERSION="Unknown"
ANDROID_SDK="Unknown"
BUILD_ID="Unknown"
BUILD_FINGERPRINT="Unknown"

if [[ -f "$PRODUCT_DIR/system/build.prop" ]]; then

    ANDROID_VERSION=$(grep '^ro.build.version.release=' \
        "$PRODUCT_DIR/system/build.prop" \
        | head -n1 \
        | cut -d= -f2-)

    ANDROID_SDK=$(grep '^ro.build.version.sdk=' \
        "$PRODUCT_DIR/system/build.prop" \
        | head -n1 \
        | cut -d= -f2-)

    BUILD_ID=$(grep '^ro.build.id=' \
        "$PRODUCT_DIR/system/build.prop" \
        | head -n1 \
        | cut -d= -f2-)

    BUILD_FINGERPRINT=$(grep '^ro.build.fingerprint=' \
        "$PRODUCT_DIR/system/build.prop" \
        | head -n1 \
        | cut -d= -f2-)

fi

# Fallback for newer build layouts

if [[ "$ANDROID_VERSION" == "Unknown" ]]; then
    ANDROID_VERSION=$(get_build_var PLATFORM_VERSION 2>/dev/null || echo "Unknown")
fi

if [[ "$ANDROID_SDK" == "Unknown" ]]; then
    ANDROID_SDK=$(get_build_var PLATFORM_SDK_VERSION 2>/dev/null || echo "Unknown")
fi

if [[ "$BUILD_ID" == "Unknown" ]]; then
    BUILD_ID=$(get_build_var BUILD_ID 2>/dev/null || echo "Unknown")
fi

# ============================================================
# Build number / date
# ============================================================

BUILD_DATE="Unknown"
BUILD_DATE_UTC="Unknown"

if [[ -n "$(get_build_var BUILD_DATETIME 2>/dev/null)" ]]; then
    BUILD_EPOCH=$(get_build_var BUILD_DATETIME 2>/dev/null)

    if [[ "$BUILD_EPOCH" =~ ^[0-9]+$ ]]; then
        BUILD_DATE=$(date -d "@${BUILD_EPOCH}" '+%d %B %Y, %H:%M:%S %Z' 2>/dev/null)
        BUILD_DATE_UTC=$(date -u -d "@${BUILD_EPOCH}" '+%d %B %Y, %H:%M:%S UTC' 2>/dev/null)
    fi
fi

# ============================================================
# Images
# ============================================================

BOOT_IMG="$PRODUCT_DIR/boot.img"
VENDOR_BOOT_IMG="$PRODUCT_DIR/vendor_boot.img"
DTBO_IMG="$PRODUCT_DIR/dtbo.img"
RECOVERY_IMG="$PRODUCT_DIR/recovery.img"
VBMETA_IMG="$PRODUCT_DIR/vbmeta.img"

# ============================================================
# File information
# ============================================================

ROM_SIZE=$(file_size "$ROM_ZIP")
BOOT_SIZE=$(file_size "$BOOT_IMG")
VENDOR_BOOT_SIZE=$(file_size "$VENDOR_BOOT_IMG")
DTBO_SIZE=$(file_size "$DTBO_IMG")
RECOVERY_SIZE=$(file_size "$RECOVERY_IMG")
VBMETA_SIZE=$(file_size "$VBMETA_IMG")

MD5SUM=$(md5_hash "$ROM_ZIP")
SHA256SUM=$(sha256_hash "$ROM_ZIP")

# ============================================================
# Git information
# ============================================================

DEVICE_TREE="device/*/${DEVICE}"
VENDOR_TREE="vendor/*/${DEVICE}"
KERNEL_TREE="kernel/*/*"

DEVICE_GIT="N/A"
VENDOR_GIT="N/A"
KERNEL_GIT="N/A"

DEVICE_PATH=$(find device -maxdepth 2 -type d -name "$DEVICE" 2>/dev/null | head -n1)

if [[ -n "$DEVICE_PATH" ]]; then
    DEVICE_GIT=$(git_info "$DEVICE_PATH")
fi

VENDOR_PATH=$(find vendor -maxdepth 2 -type d -name "$DEVICE" 2>/dev/null | head -n1)

if [[ -n "$VENDOR_PATH" ]]; then
    VENDOR_GIT=$(git_info "$VENDOR_PATH")
fi

KERNEL_PATH=$(find kernel -mindepth 2 -maxdepth 2 -type d 2>/dev/null | head -n1)

if [[ -n "$KERNEL_PATH" ]]; then
    KERNEL_GIT=$(git_info "$KERNEL_PATH")
fi

# ============================================================
# Disk information
# ============================================================

DISK_AVAILABLE=$(df -h "$PRODUCT_DIR" 2>/dev/null \
    | awk 'NR==2 {print $4}')

DISK_USED=$(df -h "$PRODUCT_DIR" 2>/dev/null \
    | awk 'NR==2 {print $5}')

# ============================================================
# GoFile
# ============================================================

sep
log "Fetching GoFile server..."

SERVER=$(curl -s --max-time 20 \
    https://api.gofile.io/servers \
    | jq -r '.data.servers[0].name' 2>/dev/null)

if [[ -z "$SERVER" || "$SERVER" == "null" ]]; then

    error "Unable to fetch GoFile server"

    send_telegram \
"<b>❌ UPLOAD FAILED</b>

<b>Reason:</b> Unable to fetch GoFile server
<b>ROM:</b> ${ROM_NAME}
<b>Device:</b> ${DEVICE}
<b>Time:</b> $(date '+%d %B %Y, %H:%M:%S %Z')"

    exit 1
fi

success "GoFile server: $SERVER"

# ============================================================
# Upload function
# ============================================================

upload() {

    local FILE="$1"
    local OUTPUT="$2"

    if [[ ! -f "$FILE" ]]; then
        echo "N/A" > "$OUTPUT"
        return
    fi

    local RESULT

    RESULT=$(curl -s \
        --max-time 3600 \
        -F "file=@${FILE}" \
        "https://${SERVER}.gofile.io/uploadFile")

    echo "$RESULT" \
        | jq -r '.data.downloadPage // "N/A"' \
        > "$OUTPUT"
}

# ============================================================
# Parallel uploads
# ============================================================

sep
log "Uploading files to GoFile..."
log "Uploads are running in parallel."

TMP_DIR=$(mktemp -d)

UPLOAD_START=$(date +%s)

upload "$ROM_ZIP" "$TMP_DIR/rom" &
PID_ROM=$!

upload "$BOOT_IMG" "$TMP_DIR/boot" &
PID_BOOT=$!

upload "$VENDOR_BOOT_IMG" "$TMP_DIR/vendor_boot" &
PID_VENDOR_BOOT=$!

upload "$DTBO_IMG" "$TMP_DIR/dtbo" &
PID_DTBO=$!

upload "$RECOVERY_IMG" "$TMP_DIR/recovery" &
PID_RECOVERY=$!

upload "$VBMETA_IMG" "$TMP_DIR/vbmeta" &
PID_VBMETA=$!

wait "$PID_ROM"
ROM_STATUS=$?

wait "$PID_BOOT"
BOOT_STATUS=$?

wait "$PID_VENDOR_BOOT"
VENDOR_BOOT_STATUS=$?

wait "$PID_DTBO"
DTBO_STATUS=$?

wait "$PID_RECOVERY"
RECOVERY_STATUS=$?

wait "$PID_VBMETA"
VBMETA_STATUS=$?

UPLOAD_END=$(date +%s)

UPLOAD_DURATION=$((UPLOAD_END - UPLOAD_START))

ROM_LINK=$(cat "$TMP_DIR/rom" 2>/dev/null)
BOOT_LINK=$(cat "$TMP_DIR/boot" 2>/dev/null)
VENDOR_BOOT_LINK=$(cat "$TMP_DIR/vendor_boot" 2>/dev/null)
DTBO_LINK=$(cat "$TMP_DIR/dtbo" 2>/dev/null)
RECOVERY_LINK=$(cat "$TMP_DIR/recovery" 2>/dev/null)
VBMETA_LINK=$(cat "$TMP_DIR/vbmeta" 2>/dev/null)

[[ -z "$ROM_LINK" ]] && ROM_LINK="N/A"
[[ -z "$BOOT_LINK" ]] && BOOT_LINK="N/A"
[[ -z "$VENDOR_BOOT_LINK" ]] && VENDOR_BOOT_LINK="N/A"
[[ -z "$DTBO_LINK" ]] && DTBO_LINK="N/A"
[[ -z "$RECOVERY_LINK" ]] && RECOVERY_LINK="N/A"
[[ -z "$VBMETA_LINK" ]] && VBMETA_LINK="N/A"

success "Uploads finished in $(format_duration "$UPLOAD_DURATION")"

# ============================================================
# Final timing
# ============================================================

SCRIPT_END_EPOCH=$(date +%s)
TOTAL_DURATION=$((SCRIPT_END_EPOCH - SCRIPT_START_EPOCH))

END_DATETIME=$(date '+%d %B %Y, %H:%M:%S %Z')
END_DATE=$(date '+%d %B %Y')
END_TIME=$(date '+%H:%M:%S')

# ============================================================
# Upload status
# ============================================================

UPLOADS_OK=0
UPLOADS_FAILED=0

for STATUS in \
    "$ROM_STATUS" \
    "$BOOT_STATUS" \
    "$VENDOR_BOOT_STATUS" \
    "$DTBO_STATUS" \
    "$RECOVERY_STATUS" \
    "$VBMETA_STATUS"
do
    if [[ "$STATUS" -eq 0 ]]; then
        ((UPLOADS_OK++))
    else
        ((UPLOADS_FAILED++))
    fi
done

# ============================================================
# Telegram
# ============================================================

sep
log "Sending Telegram notification..."

TELEGRAM_MESSAGE="📦 <b>ROM COMPILED SUCCESSFULLY!</b>

━━━━━━━━━━━━━━━━━━━━
📱 <b>ROM INFORMATION</b>
━━━━━━━━━━━━━━━━━━━━

• <b>ROM:</b> ${ROM_NAME}
• <b>Device:</b> ${DEVICE}
• <b>Build Type:</b> ${BUILD_TYPE}
• <b>Android:</b> ${ANDROID_VERSION}
• <b>SDK:</b> ${ANDROID_SDK}
• <b>Build ID:</b> ${BUILD_ID}

━━━━━━━━━━━━━━━━━━━━
🕐 <b>BUILD TIME</b>
━━━━━━━━━━━━━━━━━━━━

• <b>Started:</b> ${START_DATETIME}
• <b>Finished:</b> ${END_DATETIME}
• <b>Duration:</b> $(format_duration "$TOTAL_DURATION")
• <b>Unix Time:</b> ${SCRIPT_END_EPOCH}

━━━━━━━━━━━━━━━━━━━━
💾 <b>FILES</b>
━━━━━━━━━━━━━━━━━━━━

• <b>ROM:</b> ${ROM_SIZE}
• <b>Boot:</b> ${BOOT_SIZE}
• <b>Vendor Boot:</b> ${VENDOR_BOOT_SIZE}
• <b>DTBO:</b> ${DTBO_SIZE}
• <b>Recovery:</b> ${RECOVERY_SIZE}
• <b>VBMeta:</b> ${VBMETA_SIZE}

━━━━━━━━━━━━━━━━━━━━
🔐 <b>CHECKSUMS</b>
━━━━━━━━━━━━━━━━━━━━

• <b>MD5:</b>
<code>${MD5SUM}</code>

• <b>SHA256:</b>
<code>${SHA256SUM}</code>

━━━━━━━━━━━━━━━━━━━━
🌿 <b>SOURCE</b>
━━━━━━━━━━━━━━━━━━━━

• <b>Device:</b> ${DEVICE_GIT}
• <b>Vendor:</b> ${VENDOR_GIT}
• <b>Kernel:</b> ${KERNEL_GIT}

━━━━━━━━━━━━━━━━━━━━
🖥️ <b>BUILD HOST</b>
━━━━━━━━━━━━━━━━━━━━

• <b>Host:</b> ${HOSTNAME_INFO}
• <b>User:</b> ${BUILD_USER}
• <b>OS:</b> ${HOST_OS}
• <b>Kernel:</b> ${HOST_KERNEL}
• <b>Arch:</b> ${HOST_ARCH}

━━━━━━━━━━━━━━━━━━━━
💿 <b>DISK</b>
━━━━━━━━━━━━━━━━━━━━

• <b>Used:</b> ${DISK_USED}
• <b>Available:</b> ${DISK_AVAILABLE}

━━━━━━━━━━━━━━━━━━━━
📤 <b>UPLOADS</b>
━━━━━━━━━━━━━━━━━━━━

• <b>Server:</b> ${SERVER}
• <b>Upload Time:</b> $(format_duration "$UPLOAD_DURATION")
• <b>Successful:</b> ${UPLOADS_OK}
• <b>Failed:</b> ${UPLOADS_FAILED}

━━━━━━━━━━━━━━━━━━━━
⬇️ <b>DOWNLOADS</b>
━━━━━━━━━━━━━━━━━━━━

• <b>ROM:</b> $(fmt_link "$ROM_LINK")
• <b>BOOT:</b> $(fmt_link "$BOOT_LINK")
• <b>VENDOR_BOOT:</b> $(fmt_link "$VENDOR_BOOT_LINK")
• <b>DTBO:</b> $(fmt_link "$DTBO_LINK")
• <b>RECOVERY:</b> $(fmt_link "$RECOVERY_LINK")
• <b>VBMETA:</b> $(fmt_link "$VBMETA_LINK")

━━━━━━━━━━━━━━━━━━━━
📦 <b>ZIP</b>
━━━━━━━━━━━━━━━━━━━━

<code>${ZIP_NAME}</code>

━━━━━━━━━━━━━━━━━━━━
✅ <b>BUILD FINISHED</b>
━━━━━━━━━━━━━━━━━━━━

Build completed successfully 🚀"

send_telegram "$TELEGRAM_MESSAGE"

success "Telegram notification sent"
