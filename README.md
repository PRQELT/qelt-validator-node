# QELT Validator Node

**Deploy your own QELT Mainnet validator node in minutes.**

[![Chain ID](https://img.shields.io/badge/Chain_ID-770-blue)]()
[![Besu](https://img.shields.io/badge/Besu-25.12.0-green)]()
[![Consensus](https://img.shields.io/badge/Consensus-QBFT-orange)]()
[![License](https://img.shields.io/badge/License-MIT-yellow)]()

---

## 🚀 Step-by-Step: Deploy Your Validator Node

### Step 1 — Get a Server

You need a dedicated server (VPS or bare-metal) with:

| Requirement | Minimum | Recommended |
|-------------|:-------:|:-----------:|
| **OS** | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| **RAM** | 8 GB | 16 GB |
| **CPU** | 4 cores | 8 cores |
| **Storage** | 100 GB SSD | 500 GB NVMe |
| **Network** | 100 Mbps, static IP | 1 Gbps |
| **Ports** | **30303 TCP+UDP open inbound** | Same |

### Step 2 — Clone the Repository and Run the Installer

SSH into your server and run:

```bash
# Install git if not present
sudo apt update && sudo apt install -y git

# Clone the repository
git clone https://github.com/PRQELT/qelt-validator-node.git

# Enter the directory
cd qelt-validator-node

# Make the installer executable
chmod +x install-qelt-validator.sh

# Run the installer (requires root)
sudo bash install-qelt-validator.sh
```

The script is interactive and will guide you through 10 steps:

1. ✅ System checks (OS, RAM, disk, ports, bootnode connectivity)
2. ✅ Installing Java 21 + Hyperledger Besu 25.12.0 (SHA256 verified)
3. ✅ Creating a secure `besu` system user + directories
4. ✅ Deploying the QELT genesis configuration (SHA256 verified)
5. ✅ Generating (or importing) your validator key
6. ✅ Extracting your validator address + enode URL
7. ✅ Configuring the systemd service (with security hardening)
8. ✅ Optional: HTTPS RPC endpoint (nginx + Node.js middleware + SSL)
9. ✅ Firewall configuration (UFW)
10. ✅ Starting the node and verifying connectivity + sync

### Step 3 — Wait for Full Sync

After installation, your node needs to sync with the network. This may take several hours.

**Check sync status** (returns `false` when fully synced):
```bash
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq .result
```

**Compare your block with the network:**
```bash
echo "Local:   $(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 | jq -r .result)"
echo "Network: $(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' https://mainnet.qelt.ai | jq -r .result)"
```

When both numbers match, your node is fully synced.

**Watch live sync progress:**
```bash
sudo journalctl -u besu-qelt-validator -f
```

### Step 4 — Email Your Validator Details

Once synced, the installer will have shown you a ready-to-copy email template. You can also find your details at any time:

```bash
cat /data/qelt/VALIDATOR_INFO.txt
```

**📧 Send your Validator Address and Enode URL to: [laurent@qxmp.ai](mailto:laurent@qxmp.ai)**

Include:
- Your **Validator Address** (e.g. `0x1c0dffbe7183984870283b4c1db121f4c44ba28b`)
- Your **Enode URL** (e.g. `enode://abc...@84.247.133.98:30303`)
- Confirmation that your node is **fully synced**

### Step 5 — Wait for Admission

The QELT team will coordinate a vote among existing validators. QBFT requires a majority (currently 3 of 5 validators) to vote.

**Check if you've been admitted:**
```bash
curl -s -X POST --data '{"jsonrpc":"2.0","method":"qbft_getValidatorsByBlockNumber","params":["latest"],"id":1}' \
  http://127.0.0.1:8545 | jq .result
```

When your address appears in the list — **congratulations, you're a QELT validator!** Your node begins participating in consensus automatically. No restart needed.

---

## 📋 Network Information

| Parameter | Value |
|-----------|-------|
| Network Name | QELT Mainnet |
| Chain ID | `770` |
| Consensus | QBFT (Quorum Byzantine Fault Tolerance) |
| Block Time | 5 seconds |
| EVM Version | Cancun |
| Block Finality | Immediate (no reorgs) |
| Gas Limit | 50,000,000 |
| Client | Hyperledger Besu 25.12.0 |

### Public RPC Endpoints

```
https://mainnet.qelt.ai       — Validator 1 (Bootnode)
https://mainnet2.qelt.ai      — Validator 2
https://mainnet3.qelt.ai      — Validator 3
https://mainnet4.qelt.ai      — Validator 4
https://mainnet5.qelt.ai      — Validator 5
https://archivem.qelt.ai      — Archive Node (full history)
```

---

## 🛠️ Common Commands

```bash
# Service management
sudo systemctl status besu-qelt-validator    # Check status
sudo systemctl restart besu-qelt-validator   # Restart
sudo systemctl stop besu-qelt-validator      # Stop
sudo journalctl -u besu-qelt-validator -f    # Live logs

# Network queries (via local RPC)
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq -r .result

curl -s -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq -r .result

curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq .result
```

---

## 📁 Files Created by the Installer

| File | Purpose |
|------|---------|
| `/data/qelt/` | Blockchain data directory |
| `/data/qelt/keys/nodekey` | Your validator private key (**back this up!**) |
| `/data/qelt/static-nodes.json` | Bootnode peer entry |
| `/data/qelt/VALIDATOR_INFO.txt` | Summary of your node details |
| `/etc/qelt/genesis.json` | Network genesis configuration |
| `/etc/systemd/system/besu-qelt-validator.service` | Systemd service |
| `/opt/besu/` | Besu binary installation |

---

## 🔐 Security Features

The installer implements production security best practices:

- **Dedicated system user** (`besu`) — the node daemon never runs as root
- **Systemd sandboxing** — `ProtectHome`, `ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`
- **Strict key permissions** — `chmod 600` on node private key, `chmod 700` on keys directory
- **RPC localhost-only** by default — not exposed to the internet
- **SHA256 verification** of both the Besu binary and genesis file
- **UFW firewall** configuration (30303 TCP/UDP for P2P)
- **Node.js RPC middleware** with method whitelisting (if public RPC is enabled)
- **Nginx rate limiting** + security headers (if HTTPS endpoint is enabled)

### ⚠️ Protect Your Node Key

Your node key (`/data/qelt/keys/nodekey`) is your validator identity.
- **Back it up securely** — if lost, you lose your validator slot
- **Never share your private key** — if stolen, someone can sign blocks as you

---

## 🔄 Updating

### Updating the Installer
```bash
cd /root/qelt-validator-node
git pull
```

### Updating Besu
When a new Besu version is approved by the QELT team:
```bash
sudo systemctl stop besu-qelt-validator
# Download and extract the new version (update URL)
sudo rm -rf /opt/besu
sudo mkdir -p /opt/besu
sudo tar -xzf besu-NEW_VERSION.tar.gz -C /opt/besu --strip-components=1
sudo ln -sf /opt/besu/bin/besu /usr/local/bin/besu
besu --version  # Verify
sudo systemctl start besu-qelt-validator
```

⚠️ **Always check Besu release notes for breaking changes before upgrading.**

---

## 🆘 Troubleshooting

### Node won't start
```bash
sudo journalctl -u besu-qelt-validator --no-pager -n 50
```
Common causes: port 30303 already in use, insufficient RAM, wrong genesis, key permissions.

### No peers connecting
```bash
sudo ss -tlnp | grep 30303       # Check port is open
sudo ufw status | grep 30303     # Check firewall
```

### Sync stuck at block 0
- Verify genesis file matches: `sha256sum /etc/qelt/genesis.json` should return `fa5b3534...`
- Check bootnode enode URL in service file
- Ensure outbound + inbound traffic on port 30303

### View your validator details
```bash
cat /data/qelt/VALIDATOR_INFO.txt
besu public-key export-address --node-private-key-file=/data/qelt/keys/nodekey
```

---

## 📖 Additional Documentation

| Document | Description |
|----------|-------------|
| [VALIDATOR_ADMISSION.md](VALIDATOR_ADMISSION.md) | Complete admission process — for both new operators and existing validators |

---

## 📬 Contact

- **Validator admission requests:** [laurent@qxmp.ai](mailto:laurent@qxmp.ai)
- **Besu docs:** https://besu.hyperledger.org/
- **QBFT consensus:** https://besu.hyperledger.org/stable/private-networks/how-to/configure/consensus/qbft

---

## License

MIT License — Copyright 2026 QELT Network

---

*Built for the QELT Validator Expansion Program.*
