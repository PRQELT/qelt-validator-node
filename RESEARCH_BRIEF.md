# QELT Validator Node Installer — Research Brief
**Purpose:** Input document for deep research (ChatGPT / Gemini) to validate best practices before writing the installer script.  
**Date:** 2026-03-09  
**Author:** Roo (AI) + QELT Network team  

---

## 1. What We Are Building

A **one-command bash installer script** (`install-qelt-validator.sh`) that lets community members join the **QELT Mainnet** as a new **validator node** in the QBFT permissioned network. The goal is maximum ease-of-use with minimal clicks, while following production security best practices.

**Invocation target (ideal):**
```bash
curl -sSL https://install.qelt.ai/validator.sh | sudo bash
```

Or downloadable and run locally:
```bash
wget https://install.qelt.ai/validator.sh
chmod +x validator.sh
sudo ./validator.sh
```

---

## 2. Live Network Facts (Confirmed from Production)

### 2.1 Network Parameters

| Parameter | Value |
|-----------|-------|
| **Network Name** | QELT Mainnet |
| **Chain ID** | `770` |
| **Consensus** | QBFT (Quorum Byzantine Fault Tolerance) — Hyperledger Besu implementation |
| **Block time** | 5 seconds |
| **Epoch length** | 30,000 blocks (~41.7 hours) |
| **Request timeout** | 10 seconds |
| **EVM version** | Cancun |
| **Zero base fee** | `true` (no EIP-1559 burning, gas price is configurable) |
| **Gas limit** | `0x2FAF080` = 50,000,000 |
| **Contract size limit** | 1,048,576 bytes |
| **EVM stack size** | 2,048 |
| **Block finality** | Immediate (QBFT — no reorgs) |

### 2.2 Genesis File (Production-Exact)

```json
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
```

> **Critical note:** The `extraData` field is RLP-encoded QBFT validator set data. It was regenerated using `besu rlp encode --type=QBFT_EXTRA_DATA` from the 5 validator addresses. This exact value must be embedded in any new node's genesis — it cannot differ by even one byte or the node will not sync.

### 2.3 Software Versions (Production-Confirmed)

| Software | Version | Notes |
|----------|---------|-------|
| Hyperledger Besu | **25.12.0** | Confirmed from `/data/qelt/VERSION_METADATA.json` |
| Java | **OpenJDK 21** | Required by Besu 25.x |
| Operating System | Ubuntu LTS | All production nodes run Ubuntu |
| Nginx | Latest stable | Used as reverse proxy for HTTPS RPC |
| Certbot | Latest | Let's Encrypt SSL automation |
| Storage format | **BONSAI** (pruned) | Efficient pruned storage |
| Sync mode | **FULL** | Full sync, not FAST/SNAP |

### 2.4 Network Topology

| Node | Role | IP | Domain | Validator Address |
|------|------|----|--------|-------------------|
| Node 1 | **Bootnode + Validator** | 62.169.25.2 | mainnet.qelt.ai | 0x4f20b89195e869abdb228a4a95a7f4927a577225 |
| Node 2 | Validator | 62.169.25.49 | mainnet2.qelt.ai | 0x272e3bff6c94a6ac512e032fba927907242e3145 |
| Node 3 | Validator | 62.169.25.73 | mainnet3.qelt.ai | 0xfd54decb397f90724153fac3b5849732bce9750e |
| Node 4 | Validator | 62.169.26.160 | mainnet4.qelt.ai | 0x2ce9060c510308b7a51cbf036cb00e13bcec6a14 |
| Node 5 | Validator | 62.169.30.179 | mainnet5.qelt.ai | 0x7fbd62e5f55eeed48b61c003d82cf3a8c764ec51 |
| Node 6 | Archive Node | 62.169.31.187 | archivem.qelt.ai | N/A |

### 2.5 Confirmed Bootnode Enode URL

```
enode://710abc6491ff7de558de11d6835f64ca10ae3fd58b5a235d5cec068830fbd4e9568ec4e68293232a0a88f242fc7e81703827c9d90cad2bebb7a890cadb4220bc@62.169.25.2:30303
```

> **Note:** Only Node 1's enode is documented. The other 4 validator enodes are not available in any stored documentation. Besu's DevP2P discovery will find peers after connecting to the bootnode, so one bootnode is sufficient.

### 2.6 Production Service Configuration (from `/etc/systemd/system/besu-qelt-validator.service`)

```ini
[Service]
User=root
Environment="JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64"
Environment="JAVA_OPTS=-Xms6g -Xmx6g -XX:+UseG1GC -XX:+UseStringDeduplication -XX:MaxGCPauseMillis=200 -Djava.awt.headless=true -Dfile.encoding=UTF-8"
ExecStart=/opt/besu/bin/besu \
  --data-path=/data/qelt \
  --genesis-file=/etc/qelt/genesis.json \
  --node-private-key-file=/data/qelt/keys/nodekey \
  --p2p-host=<PUBLIC_IP> \
  --p2p-port=30303 \
  --rpc-http-enabled \
  --rpc-http-host=0.0.0.0 \
  --rpc-http-port=8545 \
  --rpc-http-api=ETH,NET,QBFT,WEB3,TXPOOL \
  --rpc-http-cors-origins="*" \
  --metrics-enabled \
  --metrics-host=0.0.0.0 \
  --metrics-port=9090 \
  --host-allowlist="*" \
  --min-gas-price=1000 \
  --min-priority-fee=1000 \
  --data-storage-format=BONSAI \
  --sync-mode=FULL \
  --sync-min-peers=2 \
  --logging=INFO
Restart=on-failure
RestartSec=10
LimitNOFILE=1048576
MemoryMax=8G
CPUWeight=90
```

> **Question for research:** Should new validators also run with `--rpc-http-host=0.0.0.0` (open to all interfaces) or restrict to `--rpc-http-host=127.0.0.1` (localhost only) when not exposing a public endpoint? The production nodes expose RPC on all interfaces and rely on firewall/nginx.

### 2.7 Ports Used

| Port | Protocol | Purpose | Accessibility |
|------|----------|---------|---------------|
| 30303 | TCP + UDP | P2P consensus + discovery | **Public — must be open inbound** |
| 8545 | TCP | HTTP RPC | Localhost only (nginx proxies HTTPS on 443) |
| 9090 | TCP | Prometheus metrics | Internal only |
| 443 | TCP | HTTPS RPC (via nginx) | Public — only if domain configured |

### 2.8 QBFT Consensus — How Validator Admission Works

QBFT uses **on-chain voting** (no smart contract — it is built into the consensus protocol itself):

1. New validator runs node and syncs to chain tip
2. New validator operator shares their **Ethereum address** (derived from their node key)
3. Each **existing** validator operator runs:
   ```bash
   curl -X POST --data '{"jsonrpc":"2.0","method":"qbft_proposeValidatorVote","params":["0xNEW_VALIDATOR_ADDRESS", true],"id":1}' http://localhost:8545
   ```
4. Once **≥ (N/2 + 1)** validators vote (currently 3 of 5), the new address is added
5. Admission takes effect at the **next epoch boundary** (every 30,000 blocks)
6. Verify with:
   ```bash
   curl -X POST --data '{"jsonrpc":"2.0","method":"qbft_getValidatorsByBlockNumber","params":["latest"],"id":1}' https://mainnet.qelt.ai
   ```

> **Question for research:** Is there a better/safer way to handle QBFT validator voting in Besu 25.x? Are there known issues with epoch boundaries or vote ordering? What happens if a new node's key is wrong and it gets voted in — can it be voted out?

### 2.9 Hardware Requirements (Derived from Production)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 8 GB | 16 GB |
| CPU | 4 cores | 8 cores |
| Storage | 100 GB SSD | 500 GB NVMe SSD |
| Network | 100 Mbps | 1 Gbps |
| Static IP | Required | Required |
| OS | Ubuntu 22.04 / 24.04 LTS | Ubuntu 24.04 LTS |

> **Question for research:** Are these hardware specs appropriate for a Besu 25.x QBFT validator? What are Hyperledger's current official minimum recommendations?

---

## 3. Installer Script — Proposed Design

### 3.1 Overview

A **single interactive bash script** that:
- Is idempotent (safe to re-run)
- Has colored terminal output with clear status indicators
- Validates all prerequisites before making any changes
- Offers key management flexibility
- Configures everything needed for production-grade operation

### 3.2 Script Flow (Step by Step)

```
START
  │
  ├─► [1] BANNER & INTRO
  │       Show QELT logo, version, what will be installed
  │
  ├─► [2] PREFLIGHT CHECKS (non-destructive)
  │       ✓ OS: Ubuntu 22.04 or 24.04 (cat /etc/os-release)
  │       ✓ Architecture: x86_64
  │       ✓ RAM: ≥ 8 GB (free -m)
  │       ✓ Disk free: ≥ 50 GB on /data or /
  │       ✓ Port 30303 not already in use (ss -tlnp)
  │       ✓ Running as root or sudo
  │       ✓ Internet connectivity (curl https://mainnet.qelt.ai)
  │       ✗ Any failure → exit with clear error message
  │
  ├─► [3] INSTALL DEPENDENCIES
  │       apt-get update
  │       Install: curl wget jq openssl
  │       Install: openjdk-21-jdk (if not present)
  │       Verify Java version ≥ 21
  │
  ├─► [4] INSTALL HYPERLEDGER BESU 25.12.0
  │       Download from official GitHub releases
  │       Verify SHA256 checksum
  │       Extract to /opt/besu/
  │       Symlink /usr/local/bin/besu → /opt/besu/bin/besu
  │       Verify: besu --version
  │
  ├─► [5] CREATE SYSTEM USER + DIRECTORIES
  │       useradd --system --no-create-home besu (if not already root)
  │       mkdir -p /data/qelt/keys
  │       mkdir -p /etc/qelt
  │       Set appropriate permissions
  │
  ├─► [6] DEPLOY GENESIS FILE
  │       Write /etc/qelt/genesis.json (embedded in script as heredoc)
  │       Verify: checksum matches known-good genesis hash
  │
  ├─► [7] KEY MANAGEMENT (interactive choice)
  │       ┌─ Option 1: AUTO-GENERATE (default, recommended)
  │       │     Use: besu --data-path=/tmp/besu-keygen --genesis-file=... \
  │       │           to generate a key, then copy to /data/qelt/keys/nodekey
  │       │     OR: use openssl/python to generate secp256k1 key
  │       │     Display: public key, derived Ethereum address
  │       │
  │       └─ Option 2: IMPORT OWN KEY
  │             Sub-option A: Paste hex private key (32 bytes / 64 hex chars)
  │             Sub-option B: Provide path to existing keyfile
  │             Validate: key format, derive and display address
  │
  ├─► [8] CONFIGURE SYSTEMD SERVICE
  │       Detect public IP (curl ifconfig.me or ip route get 8.8.8.8)
  │       Ask: optional description/name for this node
  │       Write /etc/systemd/system/besu-qelt-validator.service
  │       systemctl daemon-reload
  │       systemctl enable besu-qelt-validator
  │
  ├─► [9] PUBLIC RPC ENDPOINT (optional)
  │       Ask: "Do you want to expose a public HTTPS RPC endpoint?"
  │       ┌─ YES:
  │       │     Ask: domain name (e.g. mynode.example.com)
  │       │     Install: nginx, certbot
  │       │     Write nginx config (reverse proxy, rate limiting, security headers)
  │       │     Obtain Let's Encrypt cert (certbot --nginx -d DOMAIN)
  │       │     Enable + start nginx
  │       └─ NO:
  │             Configure RPC on localhost only (--rpc-http-host=127.0.0.1)
  │
  ├─► [10] START SERVICES
  │        systemctl start besu-qelt-validator
  │        Wait for node to initialize (poll /data/qelt/database for creation)
  │
  ├─► [11] SYNC VERIFICATION
  │        Poll eth_syncing every 5 seconds
  │        Show progress: block number increasing
  │        Wait until syncing OR at least first block received
  │        Check peer count (should see ≥ 1 peer)
  │
  └─► [12] POST-INSTALL SUMMARY
            ═══════════════════════════════════
            ✅ QELT Validator Node Installed!
            
            Validator Address: 0x...
            Enode URL: enode://...@YOUR_IP:30303
            
            ⚠ NEXT STEP — Request Validator Admission:
              Send your validator address to the QELT team
              OR contact existing validators to propose your vote.
            
            📋 Commands:
              Status:  sudo systemctl status besu-qelt-validator
              Logs:    sudo journalctl -u besu-qelt-validator -f
              Peers:   curl localhost:8545 (eth_peerCount)
            ═══════════════════════════════════
```

### 3.3 Key Generation — Design Decision

**Option A (Preferred):** Use Besu's own key generation:
```bash
# Besu can generate a key on first run if no keyfile exists:
besu --data-path=/data/qelt --genesis-file=/etc/qelt/genesis.json &
# Then kill it and read the generated key
```

**Option B:** Use Python/openssl to generate a secp256k1 key without starting Besu:
```python
# pip install eth-keys
from eth_keys import keys
import os
private_key = keys.PrivateKey(os.urandom(32))
print(private_key.to_hex())  # Store as nodekey
print(private_key.public_key.to_hex())  # The enode public key
print(private_key.public_key.to_checksum_address())  # The validator address
```

**Option C:** Shell-only using openssl:
```bash
# Generate secp256k1 private key
openssl ecparam -name secp256k1 -genkey -noout -out /tmp/key.pem
openssl ec -in /tmp/key.pem -text -noout 2>/dev/null | grep priv -A 3 | \
  tail -3 | tr -d ' \n:' > /data/qelt/keys/nodekey
```

> **Question for research:** What is the safest, most reliable way to generate a secp256k1 keypair and derive the Ethereum address in a bash script WITHOUT requiring Python pip packages? Is there a way to use Besu's built-in key generation CLI tool without starting the full node? (e.g., `besu public-key export-address` exists — is there a `besu public-key generate`?)

### 3.4 Deriving Ethereum Address from Private Key

The Ethereum address is: `keccak256(publicKey)[12:]` (last 20 bytes)

In Besu, once the nodekey file exists, the address can be obtained via:
```bash
besu public-key export-address --node-private-key-file=/data/qelt/keys/nodekey
```

> **Question for research:** Does `besu public-key export-address` work correctly in Besu 25.12.0? Is there a way to do this without running Besu (e.g., using `cast` from Foundry or another lightweight tool that would be available in a fresh Ubuntu install)?

### 3.5 Enode URL Generation

The enode URL is:
```
enode://<PUBLIC_KEY_128_HEX_CHARS>@<PUBLIC_IP>:30303
```

Where `PUBLIC_KEY` is the 64-byte uncompressed secp256k1 public key (without the 04 prefix), expressed as 128 hex characters.

This can be obtained post-install via:
```bash
besu public-key export --node-private-key-file=/data/qelt/keys/nodekey
```

### 3.6 Static Nodes / Bootnodes Configuration

New validator will connect to the network via the bootnode:
```
enode://710abc6491ff7de558de11d6835f64ca10ae3fd58b5a235d5cec068830fbd4e9568ec4e68293232a0a88f242fc7e81703827c9d90cad2bebb7a890cadb4220bc@62.169.25.2:30303
```

This is added via the Besu flag:
```
--bootnodes=enode://710abc6...bc@62.169.25.2:30303
```

And/or as a static-nodes.json file at `/data/qelt/static-nodes.json`:
```json
[
  "enode://710abc6491ff7de558de11d6835f64ca10ae3fd58b5a235d5cec068830fbd4e9568ec4e68293232a0a88f242fc7e81703827c9d90cad2bebb7a890cadb4220bc@62.169.25.2:30303"
]
```

> **Question for research:** In Besu 25.x, what is the difference between `--bootnodes` and `static-nodes.json`? Which is preferred for a QBFT permissioned network? Should both be used? Is there a `--static-nodes-file` flag?

### 3.7 Systemd Service — New Validator Version

Differences vs. production Node 1:
- Node 1 runs as **root** (not ideal, but production reality)
- New nodes: should run as a dedicated **besu** system user
- Heap size: Node 1 uses 6GB; new nodes should start with **4GB** for lower spec machines
- Add `--bootnodes` flag (Node 1 IS the bootnode so doesn't need it)
- `--p2p-host` should be the detected public IP (not hardcoded)
- `--host-allowlist` should NOT be `*` in production — should be restricted

```ini
[Unit]
Description=QELT Mainnet Besu Validator
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=besu
Group=besu
Environment="JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64"
Environment="JAVA_OPTS=-Xms4g -Xmx4g -XX:+UseG1GC -XX:+UseStringDeduplication -XX:MaxGCPauseMillis=200 -Djava.awt.headless=true -Dfile.encoding=UTF-8"
ExecStart=/opt/besu/bin/besu \
  --data-path=/data/qelt \
  --genesis-file=/etc/qelt/genesis.json \
  --node-private-key-file=/data/qelt/keys/nodekey \
  --p2p-host=DETECTED_PUBLIC_IP \
  --p2p-port=30303 \
  --bootnodes=enode://710abc6491ff7de558de11d6835f64ca10ae3fd58b5a235d5cec068830fbd4e9568ec4e68293232a0a88f242fc7e81703827c9d90cad2bebb7a890cadb4220bc@62.169.25.2:30303 \
  --rpc-http-enabled \
  --rpc-http-host=127.0.0.1 \
  --rpc-http-port=8545 \
  --rpc-http-api=ETH,NET,QBFT,WEB3,TXPOOL \
  --rpc-http-cors-origins="*" \
  --metrics-enabled \
  --metrics-host=127.0.0.1 \
  --metrics-port=9090 \
  --host-allowlist=localhost,127.0.0.1 \
  --min-gas-price=1000 \
  --min-priority-fee=1000 \
  --data-storage-format=BONSAI \
  --sync-mode=FULL \
  --sync-min-peers=1 \
  --logging=INFO
Restart=on-failure
RestartSec=10
LimitNOFILE=1048576
MemoryMax=6G
CPUWeight=90
WorkingDirectory=/data/qelt
StandardOutput=journal
StandardError=journal
SyslogIdentifier=besu-qelt-validator

[Install]
WantedBy=multi-user.target
```

> **Question for research:** Is running Besu as root (as production nodes do) acceptable for a permissioned network validator? What is the official Hyperledger Besu recommendation? Should the script create a dedicated `besu` system user?

### 3.8 Nginx Configuration for Public RPC (Optional)

If the user chooses to expose a public HTTPS RPC endpoint, the script will deploy an nginx config matching the production template, including:
- Rate limiting (1200 req/min general, 100 req/sec burst)
- Security headers (X-Frame-Options, X-Content-Type-Options, etc.)
- Request method restriction (GET, POST, OPTIONS only)
- Body size limit (1 MB)
- User-agent blocking for known attack tools
- Let's Encrypt SSL with auto-renewal
- HTTP → HTTPS redirect

> **Question for research:** Are there any improvements to the nginx configuration for a blockchain RPC endpoint in 2026? Should we use nginx rate limiting, or would something like fail2ban or Cloudflare be recommended instead for DDoS protection?

---

## 4. Open Research Questions

Please research the following with the latest Hyperledger Besu documentation, GitHub issues, and best practices:

### 4.1 Besu Key Generation
- What is the canonical way to generate a secp256k1 keypair for a Besu node in 2025/2026?
- Does `besu operator generate-blockchain-config` still work in 25.x? What does it produce?
- Is there a `besu public-key generate` subcommand?
- Can we use `besu --genesis-file=... --data-path=... --key-value-storage=memory` to generate and immediately export a key without writing a full database?

### 4.2 QBFT Validator Admission Best Practices
- In Besu 25.x QBFT, what is the exact sequence for adding a new validator?
- Does the new node need to be fully synced before it can be voted in?
- After the vote passes, does the node automatically start participating in consensus, or is a restart required?
- What happens to consensus if the new node is voted in but offline? Does it affect block production?
- Are there any known bugs with QBFT validator voting in Besu 25.x?
- Is there a minimum peer count required before a new validator starts signing blocks?

### 4.3 Static Nodes vs Bootnodes in QBFT
- In a QBFT permissioned network with Besu 25.x, should new validators use `--bootnodes`, `static-nodes.json`, or both?
- What is the difference in behavior between these two connection methods?
- After a new validator is added via QBFT vote, do existing validators automatically discover and connect to the new node? Or does the new node need to be added to existing nodes' static-nodes.json?
- Is `--discovery-enabled=false` recommended for QBFT permissioned networks?

### 4.4 Security Best Practices
- Should the RPC HTTP API be enabled at all on a pure validator node (not serving public RPC)?
- Is there a way to run a Besu validator without exposing any RPC endpoint?
- What are the minimum required APIs (`--rpc-http-api`) for a validator that only needs to participate in QBFT consensus?
- Should validator node keys use a hardware security module (HSM) or external signer (like EthSigner/Web3Signer)?
- What is the recommended firewall configuration for a Besu QBFT validator?

### 4.5 Monitoring
- What are best practices for monitoring a Besu QBFT validator in 2026?
- Should the installer set up Prometheus + Grafana, or point users to a hosted solution?
- What are the most important Besu metrics to alert on for a validator?

### 4.6 Sync Mode
- For a new validator joining an existing QBFT network, is `FULL` sync mode still required, or can `SNAP` or `FAST` sync be used?
- Does BONSAI storage format work correctly with QBFT in Besu 25.x?
- Is there a way to speed up initial sync (e.g., from a snapshot)?

### 4.7 Script Architecture
- What is the recommended approach for a production-quality bash installer script in 2026?
- Should we use a framework like `bash-oo-framework`, `bashly`, or plain bash?
- What are the security implications of `curl | bash` for blockchain node installers?
- Should we provide an alternative (download + verify + run) alongside the `curl | bash` option?
- What checksum/signature verification should be done for the Besu binary?

---

## 5. Installer Script — Files to Be Created

```
qelt-validator-installer/
├── install-qelt-validator.sh     ← Main installer (the one-command script)
├── README.md                     ← User-facing documentation
├── VALIDATOR_ADMISSION.md        ← Step-by-step admission process
└── RESEARCH_BRIEF.md             ← This document
```

---

## 6. Constraints & Decisions Already Made

| Decision | Chosen | Reasoning |
|----------|--------|-----------|
| OS support | Ubuntu 22.04 + 24.04 LTS only | Production nodes, user confirmed |
| Besu version | 25.12.0 | Matches production |
| Java version | OpenJDK 21 | Required by Besu 25.x |
| Storage format | BONSAI (pruned) | Matches production, saves disk |
| Sync mode | FULL | Matches production requirement |
| Chain ID | 770 | Fixed by genesis |
| Bootnode | enode://710abc6...@62.169.25.2:30303 | Only confirmed enode |
| Key format | Raw hex file at `/data/qelt/keys/nodekey` | Matches production |
| Data directory | `/data/qelt/` | Matches production |
| Genesis location | `/etc/qelt/genesis.json` | Matches production |
| Service name | `besu-qelt-validator` | Matches production |

---

## 7. What We Don't Know Yet (Need Research)

1. **Best way to derive Ethereum address from private key in bash** without Python dependencies
2. **Whether `besu public-key generate` exists** as a CLI subcommand in 25.x
3. **Whether ADMIN API needs to be enabled** for the voting process (currently not enabled in production)
4. **Whether new validators need any config change on existing validators** (e.g., adding to static-nodes.json) or if P2P discovery handles it automatically
5. **Whether `--discovery-enabled` should be set to `false` or `true`** for a new joining validator
6. **The exact QBFT vote threshold** — documentation says ">50%" but is it strictly "more than half" or "at least half+1"? With 5 validators, is 3 votes sufficient?
7. **The `--min-gas-price=1000` flag** — is this correct for a zero-base-fee network? Does this cause any issues?

---

## 8. Summary for Research Prompt

**Use this section as a direct prompt for ChatGPT Deep Research / Google Gemini:**

---

I am building a one-command bash installer (`curl | bash`) for a new community validator node on the **QELT blockchain**, which is:
- A **private/permissioned Ethereum-compatible blockchain**
- Running **Hyperledger Besu 25.12.0** with **QBFT consensus**
- Chain ID: **770**, Block time: **5 seconds**, EVM: Cancun
- Currently has **5 active validators** (quorum: 3 of 5)
- Validator admission via **QBFT on-chain voting** (`qbft_proposeValidatorVote`)
- Target OS: **Ubuntu 22.04 / 24.04 LTS**

**Please research and answer the following:**

1. What is the **canonical, production-safe way to generate a secp256k1 Besu node key** in a bash script in 2025/2026? (Without requiring Python pip packages that may not be installed.) Does `besu operator generate-blockchain-config` work for single node key generation in Besu 25.x?

2. What is the **correct and complete procedure to add a new validator to a QBFT Besu network** in 2025/2026? Specifically:
   - Does the new node need to be fully synced before requesting a vote?
   - After the vote threshold is met (3/5), when exactly does the new validator start signing blocks?
   - Does the existing network need any configuration changes (static-nodes, etc.)?
   - Are there any known issues or bugs with QBFT validator addition in Besu 25.x?

3. For **security**: Should a pure QBFT validator node (not serving public RPC) have `--rpc-http-enabled` at all? What are the minimum required flags? Should it run as root or a dedicated system user?

4. For **connectivity**: In a Besu QBFT permissioned network, should new validators use `--bootnodes`, `--static-nodes-file`, or both? Should `--discovery-enabled` be false?

5. For **sync**: Can a new QBFT validator use SNAP sync mode to speed up initial sync, or is FULL sync required? Does BONSAI storage work with QBFT in Besu 25.x?

6. What are **bash scripting best practices** for a production blockchain node installer that will be used by non-technical users? What security checks should be included for the Besu binary download?

Please cite specific Hyperledger Besu documentation, GitHub issues, or official sources where possible.

---

*Document prepared by: Roo (AI Engineering Assistant), QELT Network, 2026-03-09*
