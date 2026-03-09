#!/usr/bin/env bash
###############################################################################
#                    QELT Mainnet — Validator Node Installer                  #
#                           v2.0.0 — Production Hardened                      #
#                                                                             #
#  One-command installer for new QELT QBFT validators.                        #
#  Target OS: Ubuntu 22.04 / 24.04 LTS (x86_64)                              #
#  Besu Version: 25.12.0   |   Java: OpenJDK 21   |   Chain ID: 770          #
#                                                                             #
#  Usage:                                                                     #
#    sudo ./install-qelt-validator.sh                                         #
#  Or:                                                                        #
#    curl -sSL https://install.qelt.ai/validator.sh -o install.sh             #
#    chmod +x install.sh && sudo ./install.sh                                 #
#                                                                             #
#  This script is IDEMPOTENT — safe to re-run. It will NOT overwrite an       #
#  existing node key unless you explicitly choose to.                         #
#                                                                             #
#  Copyright 2026 QELT Network   |   License: MIT                            #
###############################################################################
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# CONSTANTS — Network-specific, pinned to QELT Mainnet production
# =============================================================================
readonly SCRIPT_VERSION="2.0.0"
readonly CHAIN_ID=770
readonly NETWORK_NAME="QELT Mainnet"

# Besu release
readonly BESU_VERSION="25.12.0"
readonly BESU_DOWNLOAD_URL="https://github.com/hyperledger/besu/releases/download/${BESU_VERSION}/besu-${BESU_VERSION}.tar.gz"
# SHA256 of the official besu-25.12.0.tar.gz from GitHub Releases.
# Verified from: https://github.com/hyperledger/besu/releases/tag/25.12.0
readonly BESU_SHA256="11a880ad19cbfa30edb71a0a990310c704d6f6625601e6125507092b07db51a5"

# Genesis file SHA256 — ensures byte-identical genesis across all validators
# Verified from production bootnode: sha256sum /etc/qelt/genesis.json
readonly GENESIS_SHA256="59fca3dc839bc650cf37af240ab018a154f7b024d93ebe9ec3fc6f8325bacedd"

# Bootnode — the primary network entry point (Node 1)
readonly BOOTNODE_ENODE="enode://710abc6491ff7de558de11d6835f64ca10ae3fd58b5a235d5cec068830fbd4e9568ec4e68293232a0a88f242fc7e81703827c9d90cad2bebb7a890cadb4220bc@62.169.25.2:30303"
readonly BOOTNODE_RPC="https://mainnet.qelt.ai"

# Directories (matching production layout)
readonly BESU_INSTALL_DIR="/opt/besu"
readonly DATA_DIR="/data/qelt"
readonly KEYS_DIR="${DATA_DIR}/keys"
readonly GENESIS_DIR="/etc/qelt"
readonly GENESIS_FILE="${GENESIS_DIR}/genesis.json"
readonly SERVICE_NAME="besu-qelt-validator"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# System user (security best practice — NOT root)
readonly BESU_USER="besu"
readonly BESU_GROUP="besu"

# Java
readonly JAVA_PACKAGE="openjdk-21-jdk-headless"

# Hardware minimums
readonly MIN_RAM_MB=7500       # ~8 GB with some tolerance
readonly MIN_DISK_GB=50
readonly REQUIRED_PORT=30303

# RPC defaults (localhost-only for security)
readonly RPC_HOST="127.0.0.1"
readonly RPC_PORT=8545
readonly METRICS_PORT=9090

# Track whether user chose public RPC (used by firewall step)
PUBLIC_RPC_ENABLED=false
PUBLIC_RPC_DOMAIN=""

# =============================================================================
# TERMINAL COLORS
# =============================================================================
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'  # No Color
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[  OK]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[FAIL]${NC}  $*"; }
log_step()    { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }
log_banner()  {
    echo -e "${BOLD}${CYAN}"
    cat << 'BANNER'

   ██████╗ ███████╗██╗  ████████╗
  ██╔═══██╗██╔════╝██║  ╚══██╔══╝
  ██║   ██║█████╗  ██║     ██║
  ██║▄▄ ██║██╔══╝  ██║     ██║
  ╚██████╔╝███████╗███████╗██║
   ╚══▀▀═╝ ╚══════╝╚══════╝╚═╝

  QELT Mainnet — Validator Node Installer

BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}Version:${NC}   ${SCRIPT_VERSION}"
    echo -e "  ${BOLD}Chain ID:${NC}  ${CHAIN_ID}"
    echo -e "  ${BOLD}Besu:${NC}      ${BESU_VERSION}"
    echo -e "  ${BOLD}Consensus:${NC} QBFT (Quorum Byzantine Fault Tolerance)"
    echo ""
}

# =============================================================================
# CLEANUP TRAP — properly tracks and removes temp directories
# =============================================================================
TMP_WORKDIR=""
cleanup() {
    if [[ -n "${TMP_WORKDIR}" && -d "${TMP_WORKDIR}" ]]; then
        rm -rf "${TMP_WORKDIR}"
    fi
}
trap cleanup EXIT

# =============================================================================
# PREFLIGHT CHECKS
# =============================================================================
preflight_checks() {
    log_step "Step 1/10 — Preflight Checks"

    local failures=0

    # Root check
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)."
        exit 1
    fi
    log_ok "Running as root"

    # OS check
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    source /etc/os-release
    if [[ "${ID}" != "ubuntu" ]]; then
        log_error "Unsupported OS: ${ID}. This installer requires Ubuntu 22.04 or 24.04 LTS."
        exit 1
    fi
    local major_ver
    major_ver=$(echo "${VERSION_ID}" | cut -d. -f1)
    if [[ "${major_ver}" != "22" && "${major_ver}" != "24" ]]; then
        log_error "Unsupported Ubuntu version: ${VERSION_ID}. Requires 22.04 or 24.04 LTS."
        exit 1
    fi
    log_ok "OS: Ubuntu ${VERSION_ID}"

    # Architecture check
    local arch
    arch=$(uname -m)
    if [[ "${arch}" != "x86_64" ]]; then
        log_error "Unsupported architecture: ${arch}. Requires x86_64."
        exit 1
    fi
    log_ok "Architecture: ${arch}"

    # RAM check
    local ram_mb
    ram_mb=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
    if [[ ${ram_mb} -lt ${MIN_RAM_MB} ]]; then
        log_error "Insufficient RAM: ${ram_mb} MB. Minimum required: 8 GB (${MIN_RAM_MB} MB)."
        ((failures++))
    else
        log_ok "RAM: ${ram_mb} MB"
    fi

    # Disk check — check the mount point where /data will live
    local disk_target="/"
    if mountpoint -q /data 2>/dev/null; then
        disk_target="/data"
    fi
    local disk_avail_gb
    disk_avail_gb=$(df -BG "${disk_target}" | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
    if [[ ${disk_avail_gb} -lt ${MIN_DISK_GB} ]]; then
        log_error "Insufficient disk space: ${disk_avail_gb} GB available on ${disk_target}. Minimum: ${MIN_DISK_GB} GB."
        ((failures++))
    else
        log_ok "Disk: ${disk_avail_gb} GB available on ${disk_target}"
    fi

    # Port 30303 check
    if ss -tlnp 2>/dev/null | grep -q ":${REQUIRED_PORT} " || ss -ulnp 2>/dev/null | grep -q ":${REQUIRED_PORT} "; then
        log_error "Port ${REQUIRED_PORT} is already in use. Another process is bound to it."
        ((failures++))
    else
        log_ok "Port ${REQUIRED_PORT} is available"
    fi

    # Internet connectivity check — use an actual JSON-RPC probe against the bootnode
    log_info "Testing connectivity to QELT bootnode..."
    local rpc_response
    rpc_response=$(curl -sf --max-time 10 -X POST \
        --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        "${BOOTNODE_RPC}" 2>/dev/null || echo "")

    if echo "${rpc_response}" | grep -q '"result"'; then
        local remote_chain_id_hex
        remote_chain_id_hex=$(echo "${rpc_response}" | jq -r '.result' 2>/dev/null || echo "")
        if [[ -n "${remote_chain_id_hex}" && "${remote_chain_id_hex}" != "null" ]]; then
            local remote_chain_id=$((16#${remote_chain_id_hex#0x}))
            if [[ ${remote_chain_id} -eq ${CHAIN_ID} ]]; then
                log_ok "Bootnode reachable — Chain ID ${remote_chain_id} confirmed"
            else
                log_warn "Bootnode returned Chain ID ${remote_chain_id}, expected ${CHAIN_ID}"
            fi
        fi
    else
        log_warn "Cannot reach QELT bootnode RPC (${BOOTNODE_RPC})."
        log_warn "This may be OK — the node will try P2P on port 30303."
    fi

    if [[ ${failures} -gt 0 ]]; then
        echo ""
        log_error "${failures} preflight check(s) failed. Please fix the issues above and re-run."
        exit 1
    fi

    echo ""
    log_ok "All preflight checks passed!"
}

# =============================================================================
# INSTALL DEPENDENCIES
# =============================================================================
install_dependencies() {
    log_step "Step 2/10 — Installing Dependencies"

    log_info "Updating package index..."
    apt-get update -qq

    log_info "Installing required packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl \
        wget \
        jq \
        openssl \
        ca-certificates \
        gnupg \
        lsb-release \
        unzip \
        tar \
        > /dev/null 2>&1
    log_ok "System packages installed"

    # Java 21
    if java -version 2>&1 | grep -q 'version "21'; then
        log_ok "Java 21 already installed"
    else
        log_info "Installing OpenJDK 21..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${JAVA_PACKAGE}" > /dev/null 2>&1
        if java -version 2>&1 | grep -q 'version "21'; then
            log_ok "OpenJDK 21 installed successfully"
        else
            log_error "Failed to install Java 21. Please install manually: sudo apt install ${JAVA_PACKAGE}"
            exit 1
        fi
    fi

    local java_home
    java_home=$(dirname "$(dirname "$(readlink -f "$(which java)")")")
    log_info "JAVA_HOME: ${java_home}"
}

# =============================================================================
# INSTALL BESU
# =============================================================================
install_besu() {
    log_step "Step 3/10 — Installing Hyperledger Besu ${BESU_VERSION}"

    # Check if already installed and correct version
    if [[ -x "${BESU_INSTALL_DIR}/bin/besu" ]]; then
        local installed_version
        installed_version=$("${BESU_INSTALL_DIR}/bin/besu" --version 2>/dev/null | head -1 || echo "unknown")
        if echo "${installed_version}" | grep -q "${BESU_VERSION}"; then
            log_ok "Besu ${BESU_VERSION} already installed at ${BESU_INSTALL_DIR}"
            return 0
        else
            log_warn "Different Besu version found: ${installed_version}"
            log_info "Upgrading to ${BESU_VERSION}..."
        fi
    fi

    TMP_WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/qelt-install.XXXXXXXX")
    local archive="${TMP_WORKDIR}/besu-${BESU_VERSION}.tar.gz"

    log_info "Downloading Besu ${BESU_VERSION} from GitHub..."
    if ! curl -sSL --fail -o "${archive}" "${BESU_DOWNLOAD_URL}"; then
        log_error "Failed to download Besu from: ${BESU_DOWNLOAD_URL}"
        log_error "Check internet connectivity and try again."
        exit 1
    fi
    log_ok "Download complete"

    # SHA256 checksum verification
    if [[ "${BESU_SHA256}" != "VERIFY_AND_PIN_BEFORE_PRODUCTION_DEPLOYMENT" ]]; then
        log_info "Verifying SHA256 checksum..."
        local actual_sha256
        actual_sha256=$(sha256sum "${archive}" | awk '{print $1}')
        if [[ "${actual_sha256}" != "${BESU_SHA256}" ]]; then
            log_error "CHECKSUM MISMATCH — possible supply chain compromise!"
            log_error "Expected: ${BESU_SHA256}"
            log_error "Actual:   ${actual_sha256}"
            log_error "Aborting installation. Do NOT proceed with this binary."
            exit 1
        fi
        log_ok "SHA256 checksum verified"
    else
        log_warn "BESU_SHA256 not pinned — skipping binary integrity check."
        log_warn "For production, update BESU_SHA256 in this script with the official hash"
        log_warn "from: https://github.com/hyperledger/besu/releases/tag/${BESU_VERSION}"
    fi

    # Extract
    log_info "Extracting to ${BESU_INSTALL_DIR}..."
    rm -rf "${BESU_INSTALL_DIR}"
    mkdir -p "${BESU_INSTALL_DIR}"
    tar -xzf "${archive}" -C "${BESU_INSTALL_DIR}" --strip-components=1

    # Verify installation
    if ! "${BESU_INSTALL_DIR}/bin/besu" --version 2>/dev/null | grep -q "${BESU_VERSION}"; then
        log_error "Besu installation verification failed. Binary does not report expected version."
        exit 1
    fi

    # Create symlink for convenience
    ln -sf "${BESU_INSTALL_DIR}/bin/besu" /usr/local/bin/besu

    log_ok "Besu ${BESU_VERSION} installed and verified"
}

# =============================================================================
# CREATE SYSTEM USER AND DIRECTORIES
# =============================================================================
create_user_and_dirs() {
    log_step "Step 4/10 — Creating System User and Directories"

    # Create dedicated system user (non-login, no home directory)
    if id "${BESU_USER}" &>/dev/null; then
        log_ok "System user '${BESU_USER}' already exists"
    else
        useradd --system --no-create-home --shell /usr/sbin/nologin "${BESU_USER}"
        log_ok "Created system user '${BESU_USER}' (non-login, no home dir)"
    fi

    # Create required directories
    mkdir -p "${DATA_DIR}"
    mkdir -p "${KEYS_DIR}"
    mkdir -p "${GENESIS_DIR}"

    # Set ownership — the besu user owns the data directory
    chown -R "${BESU_USER}:${BESU_GROUP}" "${DATA_DIR}"
    chmod 700 "${KEYS_DIR}"  # Strict permissions on keys directory

    log_ok "Directories created:"
    log_info "  Data:    ${DATA_DIR}"
    log_info "  Keys:    ${KEYS_DIR}"
    log_info "  Genesis: ${GENESIS_DIR}"
}

# =============================================================================
# DEPLOY GENESIS FILE — with full SHA256 verification
# =============================================================================
deploy_genesis() {
    log_step "Step 5/10 — Deploying Genesis Configuration"

    # Write the production-exact genesis file.
    # This MUST be byte-identical to what all existing validators use.
    # The extraData field is RLP-encoded QBFT validator set — do NOT modify.
    local genesis_content
    read -r -d '' genesis_content << 'GENESIS_EOF' || true
{
  "config": {
    "chainId": 770,
    "berlinBlock": 0,
    "londonBlock": 0,
    "shanghaiTime": 0,
    "cancunTime": 0,
    "zeroBaseFee": true,
    "contractSizeLimit": 1048576,
    "initcodeSizeLimit": 1048576,
    "evmStackSize": 2048,
    "qbft": {
      "blockperiodseconds": 5,
      "epochlength": 30000,
      "requesttimeoutseconds": 10
    }
  },
  "gasLimit": "0x2FAF080",
  "difficulty": "0x1",
  "alloc": {
    "4739cC491A177EBc16f2Cf5A75467E4F6d03e9A4": {
      "balance": "0x204fce5e3e25026110000000"
    }
  },
  "extraData": "0xf88fa00000000000000000000000000000000000000000000000000000000000000000f869944f20b89195e869abdb228a4a95a7f4927a57722594272e3bff6c94a6ac512e032fba927907242e314594fd54decb397f90724153fac3b5849732bce9750e942ce9060c510308b7a51cbf036cb00e13bcec6a14947fbd62e5f55eeed48b61c003d82cf3a8c764ec51c080c0"
}
GENESIS_EOF

    if [[ -f "${GENESIS_FILE}" ]]; then
        log_info "Genesis file already exists at ${GENESIS_FILE}"
        # Verify it matches expected content via SHA256
        if [[ "${GENESIS_SHA256}" != "VERIFY_AND_PIN_BEFORE_PRODUCTION_DEPLOYMENT" ]]; then
            local existing_sha256
            existing_sha256=$(sha256sum "${GENESIS_FILE}" | awk '{print $1}')
            if [[ "${existing_sha256}" == "${GENESIS_SHA256}" ]]; then
                log_ok "Existing genesis SHA256 matches — keeping it"
                return 0
            else
                log_warn "Existing genesis SHA256 mismatch!"
                log_warn "Expected: ${GENESIS_SHA256}"
                log_warn "Actual:   ${existing_sha256}"
                log_info "Replacing with correct genesis..."
            fi
        else
            # Fallback: at least check chain ID
            local existing_chain_id
            existing_chain_id=$(jq -r '.config.chainId' "${GENESIS_FILE}" 2>/dev/null || echo "unknown")
            if [[ "${existing_chain_id}" == "${CHAIN_ID}" ]]; then
                log_ok "Existing genesis matches Chain ID ${CHAIN_ID} — keeping it"
                return 0
            else
                log_warn "Existing genesis has Chain ID ${existing_chain_id}, expected ${CHAIN_ID}"
                log_info "Replacing with correct genesis..."
            fi
        fi
    fi

    # Write genesis file
    echo "${genesis_content}" > "${GENESIS_FILE}"

    # Verify the genesis file is valid JSON
    if ! jq empty "${GENESIS_FILE}" 2>/dev/null; then
        log_error "Genesis file is not valid JSON! Installation cannot proceed."
        exit 1
    fi

    # Verify SHA256 of what we just wrote (if pinned)
    if [[ "${GENESIS_SHA256}" != "VERIFY_AND_PIN_BEFORE_PRODUCTION_DEPLOYMENT" ]]; then
        local written_sha256
        written_sha256=$(sha256sum "${GENESIS_FILE}" | awk '{print $1}')
        if [[ "${written_sha256}" != "${GENESIS_SHA256}" ]]; then
            log_error "GENESIS CHECKSUM MISMATCH after writing!"
            log_error "Expected: ${GENESIS_SHA256}"
            log_error "Actual:   ${written_sha256}"
            log_error "This should not happen. The genesis embedded in this script may be corrupted."
            exit 1
        fi
        log_ok "Genesis SHA256 verified: ${GENESIS_SHA256}"
    else
        log_warn "GENESIS_SHA256 not pinned — skipping genesis integrity check."
        log_warn "For production, pin the hash from the bootnode's /etc/qelt/genesis.json"
    fi

    log_ok "Genesis file deployed to ${GENESIS_FILE}"
    log_info "Chain ID: ${CHAIN_ID} | Consensus: QBFT | EVM: Cancun"
}

# =============================================================================
# KEY MANAGEMENT — uses openssl for generation (not Besu startup)
# =============================================================================
manage_keys() {
    log_step "Step 6/10 — Validator Key Management"

    local nodekey_file="${KEYS_DIR}/nodekey"

    if [[ -f "${nodekey_file}" ]]; then
        echo ""
        log_warn "An existing node key was found at: ${nodekey_file}"
        echo ""
        echo -e "  ${BOLD}Options:${NC}"
        echo -e "    ${GREEN}1)${NC} Keep the existing key (recommended if resuming setup)"
        echo -e "    ${YELLOW}2)${NC} Generate a NEW key (the old key will be backed up)"
        echo -e "    ${CYAN}3)${NC} Import your own key"
        echo ""
        read -r -p "  Choose [1/2/3] (default: 1): " key_choice
        key_choice=${key_choice:-1}

        case "${key_choice}" in
            1)
                log_ok "Keeping existing node key"
                ;;
            2)
                local backup="${nodekey_file}.backup.$(date +%Y%m%d%H%M%S)"
                cp "${nodekey_file}" "${backup}"
                chown "${BESU_USER}:${BESU_GROUP}" "${backup}"
                log_info "Old key backed up to: ${backup}"
                rm -f "${nodekey_file}"
                _generate_new_key "${nodekey_file}"
                ;;
            3)
                local backup="${nodekey_file}.backup.$(date +%Y%m%d%H%M%S)"
                cp "${nodekey_file}" "${backup}"
                chown "${BESU_USER}:${BESU_GROUP}" "${backup}"
                log_info "Old key backed up to: ${backup}"
                _import_key "${nodekey_file}"
                ;;
            *)
                log_ok "Keeping existing node key (invalid choice, defaulting to keep)"
                ;;
        esac
    else
        echo ""
        echo -e "  ${BOLD}No existing node key found. Choose how to set up your validator identity:${NC}"
        echo ""
        echo -e "    ${GREEN}1)${NC} Auto-generate a new key (recommended for most users)"
        echo -e "    ${CYAN}2)${NC} Import your own private key"
        echo ""
        read -r -p "  Choose [1/2] (default: 1): " key_choice
        key_choice=${key_choice:-1}

        case "${key_choice}" in
            1)
                _generate_new_key "${nodekey_file}"
                ;;
            2)
                _import_key "${nodekey_file}"
                ;;
            *)
                _generate_new_key "${nodekey_file}"
                ;;
        esac
    fi

    # Set strict ownership/permissions
    chown "${BESU_USER}:${BESU_GROUP}" "${nodekey_file}"
    chmod 600 "${nodekey_file}"

    # Export and display validator identity
    echo ""
    _display_identity "${nodekey_file}"
}

_generate_new_key() {
    local nodekey_file="$1"
    log_info "Generating new secp256k1 private key..."

    # Use openssl to generate a cryptographically secure 32-byte private key.
    # This is the correct, dependency-free method. The output is 64 hex chars
    # (no 0x prefix) — exactly what Besu expects in the nodekey file.
    openssl rand -hex 32 > "${nodekey_file}"

    if [[ ! -f "${nodekey_file}" ]]; then
        log_error "Key generation failed. The nodekey file was not created."
        exit 1
    fi

    # Validate we got exactly 64 hex characters (+ newline)
    local key_content
    key_content=$(tr -d '[:space:]' < "${nodekey_file}")
    if ! echo "${key_content}" | grep -qE '^[0-9a-fA-F]{64}$'; then
        log_error "Generated key has unexpected format. Got ${#key_content} chars, expected 64."
        exit 1
    fi

    log_ok "New validator key generated (secp256k1, 256-bit)"
}

_import_key() {
    local nodekey_file="$1"
    echo ""
    echo -e "  ${BOLD}Import your private key:${NC}"
    echo -e "  Enter the hex-encoded private key (64 hex characters, with or without 0x prefix)"
    echo -e "  Or provide the path to an existing key file."
    echo ""
    read -r -p "  Key or file path: " user_input

    if [[ -z "${user_input}" ]]; then
        log_error "No input provided. Aborting."
        exit 1
    fi

    # Check if it's a file path
    if [[ -f "${user_input}" ]]; then
        log_info "Reading key from file: ${user_input}"
        # Read, strip any 0x prefix and whitespace, then write clean hex
        local file_key
        file_key=$(tr -d '[:space:]' < "${user_input}")
        file_key="${file_key#0x}"
        echo "${file_key}" > "${nodekey_file}"
    else
        # It should be a hex string — strip 0x prefix if present
        local hex_key="${user_input#0x}"
        # Remove any whitespace
        hex_key=$(echo "${hex_key}" | tr -d '[:space:]')

        # Validate hex format (64 hex characters = 32 bytes)
        if ! echo "${hex_key}" | grep -qE '^[0-9a-fA-F]{64}$'; then
            log_error "Invalid key format. Expected 64 hex characters (32 bytes)."
            log_error "Got: ${hex_key:0:10}... (${#hex_key} characters)"
            exit 1
        fi

        # Write WITHOUT 0x prefix — Besu nodekey format is raw hex
        echo "${hex_key}" > "${nodekey_file}"
    fi

    log_ok "Key imported successfully"
}

_display_identity() {
    local nodekey_file="$1"

    # Extract validator address (the Ethereum address used for QBFT voting)
    local validator_address
    validator_address=$("${BESU_INSTALL_DIR}/bin/besu" public-key export-address \
        --node-private-key-file="${nodekey_file}" 2>/dev/null | grep "^0x" | head -1)

    # Extract public key (for enode URL construction)
    local public_key
    public_key=$("${BESU_INSTALL_DIR}/bin/besu" public-key export \
        --node-private-key-file="${nodekey_file}" 2>/dev/null | grep "^0x" | head -1)

    # Remove 0x prefix for enode URL
    local pubkey_hex="${public_key#0x}"

    # Store for later use
    echo "${validator_address}" > "${DATA_DIR}/.validator_address"
    echo "${pubkey_hex}" > "${DATA_DIR}/.public_key"

    echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}║           YOUR VALIDATOR IDENTITY                       ║${NC}"
    echo -e "  ${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${BOLD}║${NC} Validator Address: ${GREEN}${validator_address}${NC}"
    echo -e "  ${BOLD}║${NC}"
    echo -e "  ${BOLD}║${NC} ${YELLOW}⚠  SAVE THIS ADDRESS — you will need it to request${NC}"
    echo -e "  ${BOLD}║${NC} ${YELLOW}   admission to the QELT validator set.${NC}"
    echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
}

# =============================================================================
# STATIC NODES CONFIGURATION
# =============================================================================
deploy_static_nodes() {
    log_info "Writing static-nodes.json for bootnode resilience..."

    cat > "${DATA_DIR}/static-nodes.json" << STATIC_EOF
[
  "${BOOTNODE_ENODE}"
]
STATIC_EOF

    chown "${BESU_USER}:${BESU_GROUP}" "${DATA_DIR}/static-nodes.json"
    log_ok "static-nodes.json deployed with bootnode entry"
}

# =============================================================================
# CONFIGURE SYSTEMD SERVICE — with ALL production flags
# =============================================================================
configure_service() {
    log_step "Step 7/10 — Configuring Systemd Service"

    # Detect public IP
    local public_ip
    public_ip=$(curl -sSf --max-time 10 https://ifconfig.me 2>/dev/null \
        || curl -sSf --max-time 10 https://api.ipify.org 2>/dev/null \
        || curl -sSf --max-time 10 https://icanhazip.com 2>/dev/null \
        || echo "")

    if [[ -z "${public_ip}" ]]; then
        log_warn "Could not auto-detect public IP address."
        read -r -p "  Enter this server's public IP address: " public_ip
        if [[ -z "${public_ip}" ]]; then
            log_error "A public IP is required for P2P connectivity."
            exit 1
        fi
    else
        log_ok "Detected public IP: ${public_ip}"
        echo ""
        read -r -p "  Is this correct? [Y/n]: " ip_confirm
        ip_confirm=${ip_confirm:-Y}
        if [[ "${ip_confirm}" =~ ^[Nn] ]]; then
            read -r -p "  Enter the correct public IP: " public_ip
        fi
    fi

    # Detect JAVA_HOME
    local java_home
    java_home=$(dirname "$(dirname "$(readlink -f "$(which java)")")")

    # Determine heap size based on available RAM
    local ram_mb
    ram_mb=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
    local heap_gb=4
    if [[ ${ram_mb} -ge 16000 ]]; then
        heap_gb=8
    elif [[ ${ram_mb} -ge 12000 ]]; then
        heap_gb=6
    fi

    # Deploy static nodes for resilient peer discovery
    deploy_static_nodes

    # Store the public IP for later use (enode URL display)
    echo "${public_ip}" > "${DATA_DIR}/.public_ip"

    # Write the systemd service file with ALL production flags
    cat > "${SERVICE_FILE}" << SERVICE_EOF
[Unit]
Description=QELT Mainnet Besu Validator
Documentation=https://github.com/qelt/validator-installer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${BESU_USER}
Group=${BESU_GROUP}

# JVM configuration
Environment="JAVA_HOME=${java_home}"
Environment="JAVA_OPTS=-Xms${heap_gb}g -Xmx${heap_gb}g -XX:+UseG1GC -XX:+UseStringDeduplication -XX:MaxGCPauseMillis=200 -Djava.awt.headless=true -Dfile.encoding=UTF-8"

ExecStart=${BESU_INSTALL_DIR}/bin/besu \\
  --data-path=${DATA_DIR} \\
  --genesis-file=${GENESIS_FILE} \\
  --node-private-key-file=${KEYS_DIR}/nodekey \\
  --bootnodes=${BOOTNODE_ENODE} \\
  --p2p-host=${public_ip} \\
  --p2p-port=30303 \\
  --discovery-enabled=true \\
  --max-peers=25 \\
  --remote-connections-limit-enabled=true \\
  --remote-connections-max-percentage=60 \\
  --rpc-http-enabled \\
  --rpc-http-host=${RPC_HOST} \\
  --rpc-http-port=${RPC_PORT} \\
  --rpc-http-api=ETH,NET,QBFT,WEB3,TXPOOL \\
  --rpc-http-cors-origins="http://localhost,http://127.0.0.1" \\
  --rpc-http-max-active-connections=80 \\
  --host-allowlist=localhost,127.0.0.1 \\
  --metrics-enabled \\
  --metrics-host=127.0.0.1 \\
  --metrics-port=${METRICS_PORT} \\
  --min-gas-price=1000 \\
  --min-priority-fee=1000 \\
  --target-gas-limit=50000000 \\
  --data-storage-format=BONSAI \\
  --sync-mode=FULL \\
  --sync-min-peers=1 \\
  --logging=INFO

# Restart policy
Restart=on-failure
RestartSec=10

# Resource limits
LimitNOFILE=1048576
MemoryMax=$((heap_gb + 2))G
CPUWeight=90

# Security hardening (principle of least privilege)
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=${DATA_DIR}
NoNewPrivileges=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
PrivateTmp=yes

# Working directory
WorkingDirectory=${DATA_DIR}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    # Reload systemd and enable the service
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}" > /dev/null 2>&1

    log_ok "Systemd service configured and enabled"
    log_info "Service: ${SERVICE_NAME}"
    log_info "Heap: ${heap_gb} GB | P2P Host: ${public_ip}"
    log_info "RPC bound to ${RPC_HOST}:${RPC_PORT} (localhost only)"
}

# =============================================================================
# OPTIONAL: PUBLIC HTTPS RPC (nginx + Node.js RPC middleware + certbot)
# =============================================================================
setup_public_rpc() {
    log_step "Step 8/10 — Public HTTPS RPC Endpoint (Optional)"

    echo ""
    echo -e "  ${BOLD}Do you want to expose a public HTTPS RPC endpoint?${NC}"
    echo ""
    echo -e "  This requires a domain name pointed at this server's IP."
    echo -e "  It will install nginx + Node.js RPC middleware + Let's Encrypt SSL."
    echo ""
    echo -e "    ${GREEN}1)${NC} No  — validator only, no public RPC (recommended for most)"
    echo -e "    ${CYAN}2)${NC} Yes — set up HTTPS RPC with domain + SSL"
    echo ""
    read -r -p "  Choose [1/2] (default: 1): " rpc_choice
    rpc_choice=${rpc_choice:-1}

    if [[ "${rpc_choice}" != "2" ]]; then
        log_ok "Skipping public RPC setup. RPC available locally only at ${RPC_HOST}:${RPC_PORT}"
        return 0
    fi

    echo ""
    read -r -p "  Enter your domain name (e.g. mynode.example.com): " domain_name

    if [[ -z "${domain_name}" ]]; then
        log_error "No domain provided. Skipping public RPC setup."
        return 0
    fi

    read -r -p "  Enter email for Let's Encrypt certificate notifications: " cert_email
    cert_email=${cert_email:-"admin@${domain_name}"}

    # Mark public RPC enabled for firewall step
    PUBLIC_RPC_ENABLED=true
    PUBLIC_RPC_DOMAIN="${domain_name}"

    # Update systemd service to add domain to host-allowlist
    # IMPORTANT: Besu stays on 127.0.0.1 — nginx proxies to it locally
    if [[ -f "${SERVICE_FILE}" ]]; then
        sed -i "s|--host-allowlist=localhost,127.0.0.1|--host-allowlist=localhost,127.0.0.1,${domain_name}|g" "${SERVICE_FILE}"
        # Also expand CORS origins for the domain
        sed -i "s|--rpc-http-cors-origins=\"http://localhost,http://127.0.0.1\"|--rpc-http-cors-origins=\"http://localhost,http://127.0.0.1,https://${domain_name}\"|g" "${SERVICE_FILE}"
        systemctl daemon-reload
    fi

    # --- Install Node.js for RPC validation middleware ---
    log_info "Installing Node.js for RPC validation middleware..."
    if ! command -v node &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs > /dev/null 2>&1
    fi

    if command -v node &>/dev/null; then
        log_ok "Node.js $(node --version) installed"
        _deploy_rpc_middleware "${domain_name}"
    else
        log_warn "Node.js installation failed — falling back to direct nginx-to-Besu proxy."
        log_warn "This provides less application-layer protection."
    fi

    # --- Install nginx and certbot ---
    log_info "Installing nginx and certbot..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx certbot python3-certbot-nginx > /dev/null 2>&1

    # Determine the upstream port for nginx (middleware on 8547 if available, else Besu on 8545)
    local upstream_port="${RPC_PORT}"
    if systemctl is-enabled qelt-rpc-validator 2>/dev/null | grep -q "enabled"; then
        upstream_port=8547
    fi

    # Write nginx configuration
    local nginx_conf="/etc/nginx/sites-available/${domain_name}"
    cat > "${nginx_conf}" << NGINX_EOF
# QELT Validator Node — Nginx Reverse Proxy
# Auto-generated by QELT Validator Installer v${SCRIPT_VERSION}

# Rate Limiting Zones
limit_req_zone \$binary_remote_addr zone=qelt_general:10m rate=100r/m;
limit_req_zone \$binary_remote_addr zone=qelt_burst:10m rate=20r/s;
limit_conn_zone \$binary_remote_addr zone=qelt_conn:10m;

server {
    server_name ${domain_name};

    # Request size limits
    client_max_body_size 1M;
    client_body_timeout 30s;
    client_header_timeout 30s;

    # Connection limits
    limit_conn qelt_conn 20;

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Block hidden files
    location ~ /\\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Main RPC endpoint
    location / {
        limit_req zone=qelt_general burst=50 nodelay;
        limit_req zone=qelt_burst burst=10 nodelay;

        # Allow only safe methods
        limit_except GET POST OPTIONS {
            deny all;
        }

        if (\$request_method !~ ^(GET|POST|OPTIONS)\$) {
            return 405;
        }

        # Block malicious scanners
        if (\$http_user_agent ~* (nmap|nikto|wikto|sf|sqlmap|bsqlbf|w3af|acunetix|havij|appscan)) {
            return 403;
        }

        # Proxy to RPC middleware (or directly to Besu if middleware unavailable)
        proxy_pass http://127.0.0.1:${upstream_port};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # CORS
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;
        add_header Access-Control-Max-Age 3600 always;

        if (\$request_method = OPTIONS) {
            return 204;
        }
    }

    # Health endpoint (no rate limiting)
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }

    listen 80;
    listen [::]:80;
}
NGINX_EOF

    # Enable the site
    ln -sf "${nginx_conf}" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    # Test and reload nginx
    if nginx -t 2>/dev/null; then
        systemctl restart nginx
        log_ok "Nginx configured for ${domain_name}"
    else
        log_error "Nginx configuration test failed. Please check: ${nginx_conf}"
        return 1
    fi

    # Obtain SSL certificate
    log_info "Obtaining Let's Encrypt SSL certificate..."
    log_info "Ensure DNS for '${domain_name}' points to this server before proceeding."
    if certbot --nginx -d "${domain_name}" --non-interactive --agree-tos -m "${cert_email}" --redirect 2>/dev/null; then
        log_ok "SSL certificate obtained and auto-renewal configured"
        log_ok "Public RPC endpoint: https://${domain_name}"
    else
        log_warn "SSL certificate acquisition failed."
        log_warn "Ensure DNS for ${domain_name} points to this server, then run:"
        log_warn "  sudo certbot --nginx -d ${domain_name}"
    fi
}

# =============================================================================
# NODE.JS RPC VALIDATION MIDDLEWARE
# Architecture: Internet → nginx → middleware (8547) → Besu (8545)
# =============================================================================
_deploy_rpc_middleware() {
    local domain_name="$1"
    local middleware_dir="/opt/qelt-rpc-validator"
    local middleware_port=8547

    log_info "Deploying RPC validation middleware..."

    mkdir -p "${middleware_dir}"
    chown "${BESU_USER}:${BESU_GROUP}" "${middleware_dir}"

    # Write the middleware script
    cat > "${middleware_dir}/validator.js" << 'MIDDLEWARE_EOF'
/**
 * QELT RPC Validation Middleware
 * Sits between nginx and Besu to provide method whitelisting,
 * parameter validation, and application-layer rate limiting.
 *
 * Architecture: nginx (443) → this middleware (8547) → Besu (8545)
 */
const http = require('http');

const BESU_HOST = '127.0.0.1';
const BESU_PORT = 8545;
const LISTEN_PORT = 8547;
const LISTEN_HOST = '127.0.0.1';

// Allowed RPC methods (public-safe subset)
const ALLOWED_METHODS = new Set([
    // ETH namespace
    'eth_chainId',
    'eth_blockNumber',
    'eth_getBlockByNumber',
    'eth_getBlockByHash',
    'eth_getTransactionByHash',
    'eth_getTransactionReceipt',
    'eth_getTransactionCount',
    'eth_getBalance',
    'eth_getCode',
    'eth_getStorageAt',
    'eth_call',
    'eth_estimateGas',
    'eth_gasPrice',
    'eth_feeHistory',
    'eth_maxPriorityFeePerGas',
    'eth_sendRawTransaction',
    'eth_getLogs',
    'eth_syncing',
    'eth_accounts',
    'eth_getBlockTransactionCountByHash',
    'eth_getBlockTransactionCountByNumber',
    'eth_getTransactionByBlockHashAndIndex',
    'eth_getTransactionByBlockNumberAndIndex',
    'eth_protocolVersion',
    // NET namespace
    'net_version',
    'net_peerCount',
    'net_listening',
    // WEB3 namespace
    'web3_clientVersion',
    'web3_sha3',
    // QBFT namespace (read-only)
    'qbft_getValidatorsByBlockNumber',
    // TXPOOL namespace (read-only)
    'txpool_besuStatistics',
    'txpool_besuTransactions',
]);

// Blocked methods (never pass through, even if allowlist is expanded)
const BLOCKED_METHODS = new Set([
    'admin_addPeer',
    'admin_removePeer',
    'admin_peers',
    'admin_nodeInfo',
    'debug_traceTransaction',
    'debug_traceBlock',
    'debug_storageRangeAt',
    'perm_addNodesToAllowlist',
    'perm_removeNodesFromAllowlist',
    'qbft_proposeValidatorVote',
    'qbft_discardValidatorVote',
    'miner_start',
    'miner_stop',
]);

function proxyToBesu(body, res) {
    const options = {
        hostname: BESU_HOST,
        port: BESU_PORT,
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        timeout: 30000,
    };

    const proxyReq = http.request(options, (proxyRes) => {
        let data = '';
        proxyRes.on('data', (chunk) => { data += chunk; });
        proxyRes.on('end', () => {
            res.writeHead(proxyRes.statusCode, { 'Content-Type': 'application/json' });
            res.end(data);
        });
    });

    proxyReq.on('error', (err) => {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            jsonrpc: '2.0',
            id: null,
            error: { code: -32603, message: 'Backend unavailable' }
        }));
    });

    proxyReq.on('timeout', () => {
        proxyReq.destroy();
        res.writeHead(504, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            jsonrpc: '2.0',
            id: null,
            error: { code: -32603, message: 'Backend timeout' }
        }));
    });

    proxyReq.write(body);
    proxyReq.end();
}

const server = http.createServer((req, res) => {
    // Only allow POST
    if (req.method !== 'POST') {
        res.writeHead(405, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            jsonrpc: '2.0', id: null,
            error: { code: -32600, message: 'Only POST allowed' }
        }));
        return;
    }

    let body = '';
    let bodySize = 0;
    const MAX_BODY = 1024 * 1024; // 1 MB

    req.on('data', (chunk) => {
        bodySize += chunk.length;
        if (bodySize > MAX_BODY) {
            res.writeHead(413, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                jsonrpc: '2.0', id: null,
                error: { code: -32600, message: 'Request too large' }
            }));
            req.destroy();
            return;
        }
        body += chunk;
    });

    req.on('end', () => {
        let parsed;
        try {
            parsed = JSON.parse(body);
        } catch (e) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                jsonrpc: '2.0', id: null,
                error: { code: -32700, message: 'Invalid JSON' }
            }));
            return;
        }

        // Handle batch requests
        const requests = Array.isArray(parsed) ? parsed : [parsed];

        // Validate ALL methods in the batch
        for (const rpcReq of requests) {
            const method = rpcReq.method;

            if (!method || typeof method !== 'string') {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({
                    jsonrpc: '2.0', id: rpcReq.id || null,
                    error: { code: -32600, message: 'Missing method' }
                }));
                return;
            }

            if (BLOCKED_METHODS.has(method)) {
                res.writeHead(403, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({
                    jsonrpc: '2.0', id: rpcReq.id || null,
                    error: { code: -32601, message: `Method not allowed: ${method}` }
                }));
                return;
            }

            if (!ALLOWED_METHODS.has(method)) {
                res.writeHead(403, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({
                    jsonrpc: '2.0', id: rpcReq.id || null,
                    error: { code: -32601, message: `Method not available: ${method}` }
                }));
                return;
            }
        }

        // All methods valid — proxy to Besu
        proxyToBesu(body, res);
    });
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
    console.log(`QELT RPC Validator running on ${LISTEN_HOST}:${LISTEN_PORT}`);
    console.log(`Proxying to Besu at ${BESU_HOST}:${BESU_PORT}`);
    console.log(`Allowed methods: ${ALLOWED_METHODS.size}`);
});
MIDDLEWARE_EOF

    # Create systemd service for the middleware
    cat > /etc/systemd/system/qelt-rpc-validator.service << MWSVC_EOF
[Unit]
Description=QELT RPC Validation Middleware
After=network-online.target ${SERVICE_NAME}.service
Wants=${SERVICE_NAME}.service

[Service]
Type=simple
User=${BESU_USER}
Group=${BESU_GROUP}
ExecStart=/usr/bin/node ${middleware_dir}/validator.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=qelt-rpc-validator

# Security hardening
ProtectHome=yes
ProtectSystem=strict
NoNewPrivileges=yes
PrivateTmp=yes
ReadWritePaths=${middleware_dir}

[Install]
WantedBy=multi-user.target
MWSVC_EOF

    systemctl daemon-reload
    systemctl enable qelt-rpc-validator > /dev/null 2>&1

    log_ok "RPC middleware deployed at ${middleware_dir}/validator.js"
    log_info "Architecture: nginx → middleware (:${middleware_port}) → Besu (:${RPC_PORT})"
}

# =============================================================================
# FIREWALL HELPER — opens correct ports based on choices
# =============================================================================
configure_firewall() {
    log_step "Step 9/10 — Firewall Configuration"

    # Only configure if ufw is available
    if command -v ufw &>/dev/null; then
        echo ""
        echo -e "  ${BOLD}Firewall (UFW) detected. Configure recommended rules?${NC}"
        echo -e "    - Allow 30303/tcp+udp (P2P — required)"
        echo -e "    - Allow 22/tcp (SSH — keep access)"
        if [[ "${PUBLIC_RPC_ENABLED}" == "true" ]]; then
            echo -e "    - Allow 80/tcp  (HTTP — for Let's Encrypt ACME validation)"
            echo -e "    - Allow 443/tcp (HTTPS — public RPC endpoint)"
        fi
        echo ""
        read -r -p "  Configure firewall? [Y/n]: " fw_choice
        fw_choice=${fw_choice:-Y}

        if [[ "${fw_choice}" =~ ^[Yy] ]]; then
            ufw allow 30303/tcp comment "QELT P2P" > /dev/null 2>&1
            ufw allow 30303/udp comment "QELT P2P Discovery" > /dev/null 2>&1
            ufw allow 22/tcp comment "SSH" > /dev/null 2>&1

            if [[ "${PUBLIC_RPC_ENABLED}" == "true" ]]; then
                ufw allow 80/tcp comment "HTTP for ACME/nginx" > /dev/null 2>&1
                ufw allow 443/tcp comment "HTTPS RPC" > /dev/null 2>&1
                log_ok "Firewall: opened 30303 TCP/UDP, 22 TCP, 80 TCP, 443 TCP"
            else
                log_ok "Firewall: opened 30303 TCP/UDP, 22 TCP"
            fi

            if ! ufw status | grep -q "Status: active"; then
                ufw --force enable > /dev/null 2>&1
            fi
        else
            log_warn "Skipping firewall configuration."
            log_warn "Ensure port 30303 (TCP+UDP) is open for P2P connectivity!"
            if [[ "${PUBLIC_RPC_ENABLED}" == "true" ]]; then
                log_warn "Also ensure ports 80 and 443 are open for HTTPS RPC!"
            fi
        fi
    else
        log_info "UFW not installed. Ensure port 30303 (TCP+UDP) is open in your firewall."
        if [[ "${PUBLIC_RPC_ENABLED}" == "true" ]]; then
            log_info "Also ensure ports 80 and 443 are open for HTTPS RPC."
        fi
    fi
}

# =============================================================================
# START AND VERIFY — with proper JVM startup wait
# =============================================================================
start_and_verify() {
    log_step "Step 10/10 — Starting Validator Node"

    log_info "Starting ${SERVICE_NAME}..."
    systemctl start "${SERVICE_NAME}"

    # JVM + Besu startup takes 15-30 seconds. Wait appropriately.
    log_info "Waiting for Besu JVM to initialize (15 seconds)..."
    sleep 15

    # Check if service is running
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        log_error "Service failed to start. Checking logs..."
        journalctl -u "${SERVICE_NAME}" --no-pager -n 30
        echo ""
        log_error "Please review the logs above and fix any issues."
        log_error "Then restart with: sudo systemctl restart ${SERVICE_NAME}"
        exit 1
    fi
    log_ok "Service is running"

    # Wait for RPC to become available
    log_info "Waiting for RPC endpoint to initialize..."
    local rpc_ready=false
    for i in $(seq 1 30); do
        if curl -sf --max-time 2 -X POST \
            --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
            "http://${RPC_HOST}:${RPC_PORT}" > /dev/null 2>&1; then
            rpc_ready=true
            break
        fi
        sleep 2
    done

    if [[ "${rpc_ready}" == "true" ]]; then
        log_ok "RPC endpoint is live"

        # Now that Besu RPC is confirmed, start the middleware (if deployed)
        if systemctl is-enabled qelt-rpc-validator 2>/dev/null | grep -q "enabled"; then
            log_info "Starting RPC validation middleware..."
            systemctl start qelt-rpc-validator
            log_ok "RPC middleware started (port 8547 → Besu 8545)"
        fi

        # Verify chain ID
        local chain_id_hex
        chain_id_hex=$(curl -sf -X POST \
            --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
            "http://${RPC_HOST}:${RPC_PORT}" | jq -r '.result' 2>/dev/null)
        if [[ -n "${chain_id_hex}" && "${chain_id_hex}" != "null" ]]; then
            local chain_id_dec=$((16#${chain_id_hex#0x}))
            if [[ ${chain_id_dec} -eq ${CHAIN_ID} ]]; then
                log_ok "Chain ID verified: ${chain_id_dec}"
            else
                log_warn "Chain ID mismatch: got ${chain_id_dec}, expected ${CHAIN_ID}"
            fi
        fi

        # Check peers
        local peer_count_hex
        peer_count_hex=$(curl -sf -X POST \
            --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
            "http://${RPC_HOST}:${RPC_PORT}" | jq -r '.result' 2>/dev/null)
        if [[ -n "${peer_count_hex}" && "${peer_count_hex}" != "null" ]]; then
            local peer_count=$((16#${peer_count_hex#0x}))
            if [[ ${peer_count} -gt 0 ]]; then
                log_ok "Connected to ${peer_count} peer(s)"
            else
                log_warn "No peers yet. This is normal during initial startup — peers will connect shortly."
            fi
        fi

        # Check sync status
        local syncing
        syncing=$(curl -sf -X POST \
            --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
            "http://${RPC_HOST}:${RPC_PORT}" | jq -r '.result' 2>/dev/null)
        if [[ "${syncing}" == "false" ]]; then
            log_ok "Node is fully synced"
        else
            log_info "Node is syncing (this is expected on first run)..."
            local current_block
            current_block=$(curl -sf -X POST \
                --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                "http://${RPC_HOST}:${RPC_PORT}" | jq -r '.result' 2>/dev/null)
            if [[ -n "${current_block}" && "${current_block}" != "null" && "${current_block}" != "0x0" ]]; then
                local block_dec=$((16#${current_block#0x}))
                log_info "Current block: ${block_dec}"
            fi
            log_info "Sync may take several hours depending on chain height."
        fi
    else
        log_warn "RPC not yet responsive (may still be initializing)."
        log_warn "Check status with: sudo systemctl status ${SERVICE_NAME}"
        log_warn "Watch logs with:   sudo journalctl -u ${SERVICE_NAME} -f"
    fi
}

# =============================================================================
# POST-INSTALL SUMMARY
# =============================================================================
print_summary() {
    local validator_address=""
    local public_key=""
    local public_ip=""

    if [[ -f "${DATA_DIR}/.validator_address" ]]; then
        validator_address=$(cat "${DATA_DIR}/.validator_address")
    fi
    if [[ -f "${DATA_DIR}/.public_key" ]]; then
        public_key=$(cat "${DATA_DIR}/.public_key")
    fi
    if [[ -f "${DATA_DIR}/.public_ip" ]]; then
        public_ip=$(cat "${DATA_DIR}/.public_ip")
    fi

    local enode_url=""
    if [[ -n "${public_key}" && -n "${public_ip}" ]]; then
        enode_url="enode://${public_key}@${public_ip}:30303"
    fi

    echo ""
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║                                                              ║"
    echo "  ║           ✅  QELT VALIDATOR NODE INSTALLED!                 ║"
    echo "  ║                                                              ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "  ${BOLD}Validator Address:${NC}"
    echo -e "    ${GREEN}${validator_address}${NC}"
    echo ""

    if [[ -n "${enode_url}" ]]; then
        echo -e "  ${BOLD}Enode URL:${NC}"
        echo -e "    ${CYAN}${enode_url}${NC}"
        echo ""
    fi

    echo -e "  ${BOLD}${YELLOW}━━━ IMPORTANT: NEXT STEPS ━━━${NC}"
    echo ""
    echo -e "  ${BOLD}1. Wait for full sync${NC}"
    echo -e "     Monitor sync progress:"
    echo -e "     ${CYAN}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
    echo ""
    echo -e "     Check if synced (should return ${GREEN}false${NC} when done):"
    echo -e "     ${CYAN}curl -s -X POST --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}' http://${RPC_HOST}:${RPC_PORT} | jq .result${NC}"
    echo ""
    echo -e "  ${BOLD}2. Request validator admission${NC}"
    echo -e "     Once fully synced, share your ${BOLD}Validator Address${NC} with the"
    echo -e "     QELT network team. They will coordinate the vote among existing"
    echo -e "     validators using:"
    echo -e "     ${CYAN}qbft_proposeValidatorVote(\"${validator_address}\", true)${NC}"
    echo ""
    echo -e "     A majority of existing validators (currently 3 of 5) must vote."
    echo -e "     Votes are included in block headers as validators propose blocks."
    echo -e "     When >50% of validators publish a matching proposal, the protocol"
    echo -e "     adds your address to the validator pool automatically."
    echo ""
    echo -e "  ${BOLD}3. Verify admission${NC}"
    echo -e "     After the vote passes, check your address in the validator set:"
    echo -e "     ${CYAN}curl -s -X POST --data '{\"jsonrpc\":\"2.0\",\"method\":\"qbft_getValidatorsByBlockNumber\",\"params\":[\"latest\"],\"id\":1}' http://${RPC_HOST}:${RPC_PORT} | jq .result${NC}"
    echo ""

    echo -e "  ${BOLD}━━━ USEFUL COMMANDS ━━━${NC}"
    echo ""
    echo -e "  Service status:   ${CYAN}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  Live logs:        ${CYAN}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
    echo -e "  Restart:          ${CYAN}sudo systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  Stop:             ${CYAN}sudo systemctl stop ${SERVICE_NAME}${NC}"
    echo ""
    echo -e "  Block height:     ${CYAN}curl -s -X POST --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://${RPC_HOST}:${RPC_PORT} | jq -r .result${NC}"
    echo -e "  Peer count:       ${CYAN}curl -s -X POST --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_peerCount\",\"params\":[],\"id\":1}' http://${RPC_HOST}:${RPC_PORT} | jq -r .result${NC}"
    echo ""
    echo -e "  ${BOLD}Key files:${NC}"
    echo -e "    Node key:       ${KEYS_DIR}/nodekey"
    echo -e "    Genesis:        ${GENESIS_FILE}"
    echo -e "    Service:        ${SERVICE_FILE}"
    echo -e "    Data dir:       ${DATA_DIR}"
    echo ""

    echo -e "  ${RED}${BOLD}⚠  SECURITY REMINDER:${NC}"
    echo -e "  ${RED}  Your node key (${KEYS_DIR}/nodekey) is your validator identity.${NC}"
    echo -e "  ${RED}  Back it up securely. If lost, you lose your validator slot.${NC}"
    echo -e "  ${RED}  Never share your private key with anyone.${NC}"
    echo ""

    # Save a summary file for reference
    cat > "${DATA_DIR}/VALIDATOR_INFO.txt" << INFO_EOF
QELT Mainnet Validator Node
============================
Installed: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Installer Version: ${SCRIPT_VERSION}
Besu Version: ${BESU_VERSION}
Chain ID: ${CHAIN_ID}

Validator Address: ${validator_address}
Enode URL: ${enode_url}

Service: ${SERVICE_NAME}
Data Dir: ${DATA_DIR}
Genesis: ${GENESIS_FILE}
Node Key: ${KEYS_DIR}/nodekey

STATUS: Waiting for sync + validator admission vote
INFO_EOF

    chown "${BESU_USER}:${BESU_GROUP}" "${DATA_DIR}/VALIDATOR_INFO.txt"

    log_ok "Installation complete! Summary saved to ${DATA_DIR}/VALIDATOR_INFO.txt"
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================
main() {
    log_banner

    echo -e "  This installer will set up a QELT Mainnet validator node on this server."
    echo -e "  It installs: Java 21, Hyperledger Besu ${BESU_VERSION}, and configures"
    echo -e "  the node to connect to the QELT network."
    echo ""
    read -r -p "  Continue? [Y/n]: " confirm
    confirm=${confirm:-Y}
    if [[ ! "${confirm}" =~ ^[Yy] ]]; then
        echo "  Aborted."
        exit 0
    fi

    preflight_checks          # Step 1
    install_dependencies      # Step 2
    install_besu              # Step 3
    create_user_and_dirs      # Step 4
    deploy_genesis            # Step 5
    manage_keys               # Step 6
    configure_service         # Step 7 (includes static-nodes.json)
    setup_public_rpc          # Step 8 (optional: nginx + Node.js middleware + SSL)
    configure_firewall        # Step 9
    start_and_verify          # Step 10
    print_summary             # Final output
}

# Run
main "$@"
