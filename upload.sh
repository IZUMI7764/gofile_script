```bash
#!/usr/bin/env bash

# ============================================================
#              DSU IMAGE PACKER AUTOMATION
#             ROM BUILD • GOFILE • TELEGRAM
# ============================================================

# ---------------- CONFIGURATION ----------------

BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="-1002534976589"

PRODUCT_BASE="out/target/product"

# ---------------- TERMINAL COLORS ----------------

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    WHITE='\033[1;37m'
    GRAY='\033[0;90m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE=''
    CYAN='' MAGENTA='' WHITE=''
    GRAY='' BOLD='' RESET=''
fi

set -o pipefail

# ============================================================
#                    TERMINAL INTERFACE
# ============================================================

log() {
    printf "%b\n" "${GRAY}[$(date '+%H:%M:%S')]${RESET} $1"
}

info() {
    printf "%b\n" "${GRAY}[$(date '+%H:%M:%S')]${RESET} ${BLUE}ℹ${RESET}  $1"
}

success() {
    printf "%b\n" "${GRAY}[$(date '+%H:%M:%S')]${RESET} ${GREEN}✔${RESET}  $1"
}

warning() {
    printf "%b\n" "${GRAY}[$(date '+%H:%M:%S')]${RESET} ${YELLOW}⚠${RESET}  $1"
}

error() {
    printf "%b\n" "${GRAY}[$(date '+%H:%M:%S')]${RESET} ${RED}✖${RESET}  $1"
}

sep() {
    echo -e "${GRAY}  ─────────────────────────────────────────────────${RESET}"
}

step() {
    echo
    echo -e "${CYAN}${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}${BOLD}  ◆ $1${RESET}"
    echo -e "${CYAN}${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

banner() {
    [[ -t 1 ]] && clear 2>/dev/null || true

    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
      ██████╗ ███████╗██╗   ██╗
      ██╔══██╗██╔════╝██║   ██║
      ██║  ██║███████╗██║   ██║
      ██║  ██║╚════██║██║   ██║
      ██████╔╝███████║╚██████╔╝
      ╚═════╝ ╚══════╝ ╚═════╝
EOF
    echo -e "${RESET}"

    echo -e "  ${WHITE}${BOLD}DSU IMAGE PACKER${RESET} ${GRAY}│${RESET} ${MAGENTA}GOFILE UPLOADER${RESET}"
    echo -e "  ${GRAY}Android ROM Build Automation${RESET}"
    echo

    sep

    echo -e "  ${GREEN}●${RESET} ${WHITE}Build system initialized${RESET}"
    echo -e "  ${GRAY}Started: $(date '+%d %b %Y | %H:%M:%S')${RESET}"

    sep
    echo
}

# ============================================================
#                    TELEGRAM FUNCTIONS
# ============================================================

send_telegram() {
    local message="$1"
    local response

    [[ -z "$BOT_TOKEN" ]] && return 1
    command -v curl >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1

    response=$(curl -fsS \
        --connect-timeout 15 \
        --max-time 30 \
        -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${message}" \
        -d "parse_mode=HTML" 2>/dev/null) || return 1

    echo "$response" | jq -e '.ok == true' >/dev/null 2>&1
}

# ============================================================
#                    HTML FORMATTER
# ============================================================

html_escape() {
    local value="$1"

    value="${value//&/\&amp;}"
    value="${value//</\&lt;}"
    value="${value//>/\&gt;}"
    value="${value//\"/\&quot;}"

    printf '%s' "$value"
}

fmt_link() {
    local link="$1"

    if [[ "$link" =~ ^https:// ]]; then
        printf '<a href="%s">Download DSU Package</a>' \
            "$(html_escape "$link")"
    else
        printf 'N/A'
    fi
}

# ============================================================
#                    FAILURE HANDLER
# ============================================================

fail() {
    local title="$1"
    local details="$2"

    echo
    error "$title"
    sep

    if [[ -n "$BOT_TOKEN" ]]; then
        send_telegram \
"<b>❌ DSU BUILD FAILED</b>

━━━━━━━━━━━━━━━━━━━━

${details}

━━━━━━━━━━━━━━━━━━━━

<code>Android DSU Build Automation</code>" || true
    fi

    exit 1
}

# ============================================================
#                    START
# ============================================================

banner

success "DSU packaging pipeline started."

# ============================================================
#                    DEPENDENCY CHECK
# ============================================================

step "DEPENDENCY CHECK"

REQUIRED_COMMANDS=(
    curl
    jq
    zip
    unzip
    md5sum
    du
    find
    awk
    grep
    sort
    sed
    basename
    date
)

MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        success "$cmd"
    else
        error "$cmd is missing"
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [[ ${#MISSING_COMMANDS[@]} -gt 0 ]]; then

    MISSING_TEXT=""

    for cmd in "${MISSING_COMMANDS[@]}"; do
        MISSING_TEXT+="• <code>${cmd}</code>"$'\n'
    done

    fail "Dependency check failed." \
"<b>Missing dependencies:</b>

${MISSING_TEXT}"
fi

success "All dependencies are installed."

# ============================================================
#                    TELEGRAM CONFIGURATION
# ============================================================

step "TELEGRAM CONFIGURATION"

if [[ -z "$BOT_TOKEN" ]]; then
    warning "Telegram token not configured."
    warning "Notifications will be unavailable."
else
    success "Telegram configuration loaded."
fi

# ============================================================
#                    DEVICE DETECTION
# ============================================================

step "DEVICE DETECTION"

info "Scanning product directories..."

if [[ ! -d "$PRODUCT_BASE" ]]; then
    fail "Product directory not found." \
"Expected directory:

<code>${PRODUCT_BASE}</code>"
fi

DEVICE=$(find "$PRODUCT_BASE" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    ! -name generic \
    ! -name obj \
    ! -name symbols \
    -printf '%f\n' \
    | sort \
    | sed -n '1p')

PRODUCT_DIR="$PRODUCT_BASE/$DEVICE"

if [[ -z "$DEVICE" || ! -d "$PRODUCT_DIR" ]]; then
    fail "Device detection failed." \
"Device directory was not detected inside:

<code>${PRODUCT_BASE}</code>"
fi

success "Device detected: ${WHITE}${BOLD}${DEVICE}${RESET}"
info "Product directory: ${CYAN}${PRODUCT_DIR}${RESET}"

# ============================================================
#                    ROM ZIP DETECTION
# ============================================================

step "ROM BUILD DISCOVERY"

info "Searching for ROM build ZIP..."

ROM_ZIP=$(find "$PRODUCT_DIR" \
    -maxdepth 1 \
    -type f \
    -name "*${DEVICE}*.zip" \
    | grep -Eiv 'ota|symbol|target_files|DSU-' \
    | sort -r \
    | sed -n '1p')

if [[ -z "$ROM_ZIP" || ! -f "$ROM_ZIP" ]]; then
    fail "ROM build ZIP not found." \
"Device:

<code>${DEVICE}</code>

No matching ROM ZIP was found."
fi

ROM_FILENAME=$(basename "$ROM_ZIP")
ROM_NAME="${ROM_FILENAME%.zip}"

success "ROM build found."
info "${WHITE}${ROM_FILENAME}${RESET}"

# ============================================================
#                    REQUIRED DSU IMAGES
# ============================================================

SYSTEM_IMG="$PRODUCT_DIR/system.img"
SYSTEM_EXT_IMG="$PRODUCT_DIR/system_ext.img"
VENDOR_IMG="$PRODUCT_DIR/vendor.img"
PRODUCT_IMG="$PRODUCT_DIR/product.img"
ODM_IMG="$PRODUCT_DIR/odm.img"

# ============================================================
#                    IMAGE VALIDATION
# ============================================================

step "DSU IMAGE VALIDATION"

MISSING_IMAGES=()

check_image() {
    local image="$1"
    local path="$2"
    local size

    if [[ -f "$path" ]]; then
        size=$(du -h "$path" | awk '{print $1}')
        success "${WHITE}${image}${RESET} ${GRAY}(${size})${RESET}"
    else
        error "${image} NOT FOUND"
        MISSING_IMAGES+=("$image")
    fi
}

check_image "system.img" "$SYSTEM_IMG"
check_image "system_ext.img" "$SYSTEM_EXT_IMG"
check_image "vendor.img" "$VENDOR_IMG"
check_image "product.img" "$PRODUCT_IMG"
check_image "odm.img" "$ODM_IMG"

if [[ ${#MISSING_IMAGES[@]} -gt 0 ]]; then

    MISSING_TEXT=""

    for image in "${MISSING_IMAGES[@]}"; do
        MISSING_TEXT+="❌ ${image}"$'\n'
    done

    fail "Required DSU images are missing." \
"<b>DEVICE:</b> <code>${DEVICE}</code>

<b>ROM:</b> <code>$(html_escape "$ROM_FILENAME")</code>

<b>Missing images:</b>

<code>${MISSING_TEXT}</code>

DSU package was NOT created."
fi

success "All required DSU images found."

# ============================================================
#                    CREATE DSU ZIP
# ============================================================

step "PACKAGE GENERATION"

PRODUCT_DIR_ABS="$(cd "$PRODUCT_DIR" && pwd -P)"

DSU_ZIP="${PRODUCT_DIR_ABS}/DSU-${ROM_FILENAME}"

info "Output package:"
info "${CYAN}${DSU_ZIP}${RESET}"

# Remove previous package

if [[ -f "$DSU_ZIP" ]]; then
    warning "Removing existing DSU package..."
    rm -f "$DSU_ZIP"
fi

START_TIME=$(date +%s)

info "Compressing DSU images..."
info "Compression level: 9"

cd "$PRODUCT_DIR_ABS" || {
    fail "Directory access failed." \
"Could not enter:

<code>$(html_escape "$PRODUCT_DIR_ABS")</code>"
}

zip -q -9 \
    "$DSU_ZIP" \
    system.img \
    system_ext.img \
    vendor.img \
    product.img \
    odm.img

ZIP_STATUS=$?

END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

if [[ "$ZIP_STATUS" -ne 0 || ! -f "$DSU_ZIP" ]]; then
    rm -f "$DSU_ZIP"

    fail "DSU ZIP creation failed." \
"Device: <code>${DEVICE}</code>

ROM: <code>$(html_escape "$ROM_FILENAME")</code>

Failed while compressing DSU images."
fi

success "DSU package created successfully."

# ============================================================
#                    PACKAGE INFORMATION
# ============================================================

step "PACKAGE INFORMATION"

DSU_NAME=$(basename "$DSU_ZIP")
DSU_SIZE=$(du -h "$DSU_ZIP" | awk '{print $1}')
DSU_MD5=$(md5sum "$DSU_ZIP" | awk '{print $1}')

success "Package: ${DSU_NAME}"
info "Size: ${WHITE}${DSU_SIZE}${RESET}"
info "MD5: ${WHITE}${DSU_MD5}${RESET}"
info "Compression time: ${BUILD_TIME}s"

# ============================================================
#                    ZIP INTEGRITY CHECK
# ============================================================

step "PACKAGE INTEGRITY"

info "Verifying ZIP archive..."

if ! unzip -t "$DSU_ZIP" >/dev/null 2>&1; then

    rm -f "$DSU_ZIP"

    fail "ZIP integrity verification failed." \
"Device: <code>${DEVICE}</code>

Package: <code>${DSU_NAME}</code>

The generated archive failed integrity verification.

Invalid package has been removed."
fi

success "ZIP integrity verified."

# ============================================================
#                    GOFILE SERVER
# ============================================================

step "GOFILE SERVER"

info "Fetching GoFile upload server..."

SERVER_RESPONSE=$(curl -fsS \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 30 \
    "https://api.gofile.io/servers" 2>/dev/null)

if [[ -z "$SERVER_RESPONSE" ]]; then
    fail "GoFile server request failed." \
"Could not connect to the GoFile servers API."
fi

SERVER=$(echo "$SERVER_RESPONSE" \
    | jq -er '.data.servers[0].name // empty' 2>/dev/null)

if [[ -z "$SERVER" || "$SERVER" == "null" ]]; then
    fail "GoFile server unavailable." \
"Could not obtain a valid upload server."
fi

if [[ ! "$SERVER" =~ ^[a-zA-Z0-9-]+$ ]]; then
    fail "Invalid GoFile server response." \
"The server returned an unexpected server name."
fi

success "Upload server: ${WHITE}${SERVER}${RESET}"

# ============================================================
#                    GOFILE UPLOAD
# ============================================================

step "CLOUD UPLOAD"

info "Uploading DSU package..."
info "File: ${WHITE}${DSU_NAME}${RESET}"
info "Size: ${WHITE}${DSU_SIZE}${RESET}"
warning "Please wait while the upload completes..."

UPLOAD_RESPONSE=$(curl -fsS \
    --retry 3 \
    --retry-delay 3 \
    --connect-timeout 30 \
    --max-time 0 \
    -F "file=@${DSU_ZIP}" \
    "https://${SERVER}.gofile.io/uploadFile" 2>/dev/null)

if [[ -z "$UPLOAD_RESPONSE" ]]; then
    fail "GoFile upload failed." \
"Device: <code>${DEVICE}</code>

Package: <code>${DSU_NAME}</code>

No valid response was received from GoFile."
fi

UPLOAD_STATUS=$(echo "$UPLOAD_RESPONSE" \
    | jq -r '.status // empty' 2>/dev/null)

DSU_LINK=$(echo "$UPLOAD_RESPONSE" \
    | jq -r '.data.downloadPage // empty' 2>/dev/null)

if [[ "$UPLOAD_STATUS" != "ok" || ! "$DSU_LINK" =~ ^https:// ]]; then

    API_ERROR=$(echo "$UPLOAD_RESPONSE" \
        | jq -r '.message // .status // "Unknown upload error"' 2>/dev/null)

    fail "GoFile upload failed." \
"Device: <code>${DEVICE}</code>

Package: <code>${DSU_NAME}</code>

GoFile response:

<code>$(html_escape "$API_ERROR")</code>"
fi

success "GoFile upload successful."
info "Download link: ${CYAN}${DSU_LINK}${RESET}"

# ============================================================
#                    TELEGRAM NOTIFICATION
# ============================================================

step "TELEGRAM NOTIFICATION"

info "Preparing build notification..."

ROM_HTML=$(html_escape "$ROM_NAME")
DEVICE_HTML=$(html_escape "$DEVICE")
PACKAGE_HTML=$(html_escape "$DSU_NAME")

TELEGRAM_MESSAGE="
🚀 <b>DSU PACKAGE GENERATED SUCCESSFULLY</b>

━━━━━━━━━━━━━━━━━━━━

📱 <b>BUILD INFORMATION</b>

├ <b>ROM:</b> ${ROM_HTML}
├ <b>DEVICE:</b> <code>${DEVICE_HTML}</code>
└ <b>PACKAGE:</b> <code>${PACKAGE_HTML}</code>

━━━━━━━━━━━━━━━━━━━━

📦 <b>PACKAGE DETAILS</b>

├ <b>SIZE:</b> ${DSU_SIZE}
├ <b>MD5:</b>
│ <code>${DSU_MD5}</code>
└ <b>BUILD TIME:</b> ${BUILD_TIME}s

━━━━━━━━━━━━━━━━━━━━

🗂 <b>INCLUDED IMAGES</b>

<code>
├ system.img
├ system_ext.img
├ vendor.img
├ product.img
└ odm.img
</code>

━━━━━━━━━━━━━━━━━━━━

🌐 <b>DOWNLOAD PACKAGE</b>

⬇️ $(fmt_link "$DSU_LINK")

━━━━━━━━━━━━━━━━━━━━

<blockquote>✅ ZIP integrity verified
☁️ Uploaded to GoFile
📦 DSU package ready</blockquote>

<code>Android DSU Build Automation</code>
"

if send_telegram "$TELEGRAM_MESSAGE"; then
    success "Telegram notification delivered."
    TELEGRAM_STATUS="Sent"
else
    warning "Telegram notification could not be delivered."
    TELEGRAM_STATUS="Failed"
fi

# ============================================================
#                    BUILD COMPLETED
# ============================================================

step "BUILD COMPLETED"

echo

success "DSU package created successfully."
success "Package uploaded to GoFile."

if [[ "$TELEGRAM_STATUS" == "Sent" ]]; then
    success "Telegram notification sent."
else
    warning "Telegram notification failed."
fi

echo
sep

echo -e "  ${GREEN}${BOLD}✔ ALL TASKS COMPLETED${RESET}"
echo
echo -e "  ${GRAY}DEVICE:${RESET}      ${WHITE}${DEVICE}${RESET}"
echo -e "  ${GRAY}ROM:${RESET}         ${WHITE}${ROM_NAME}${RESET}"
echo -e "  ${GRAY}PACKAGE:${RESET}     ${WHITE}${DSU_NAME}${RESET}"
echo -e "  ${GRAY}SIZE:${RESET}        ${WHITE}${DSU_SIZE}${RESET}"
echo -e "  ${GRAY}MD5:${RESET}         ${WHITE}${DSU_MD5}${RESET}"
echo -e "  ${GRAY}DURATION:${RESET}    ${WHITE}${BUILD_TIME}s${RESET}"
echo -e "  ${GRAY}TELEGRAM:${RESET}    ${WHITE}${TELEGRAM_STATUS}${RESET}"

sep

echo
echo -e "  ${MAGENTA}${BOLD}Thank you for using DSU Image Packer!${RESET}"
echo -e "  ${GRAY}Android ROM Build Automation${RESET}"
echo

# ============================================================
#                    END OF SCRIPT
# ============================================================
```
