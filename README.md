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

### Step 2 — Download and Run the Installer

SSH into your server and run:

```bash
# Download the installer
wget https://raw.githubusercontent.com/PRQELT/qelt-validator-node/main/install-qelt-validator.sh

# Make it executable
chmod +x install-qelt-validator.sh

# Run it (requires root)
sudo ./install-qelt-validator.sh
```

The script is interactive and will guide you through:
1. ✅ System checks (OS, RAM, disk, ports)
2. ✅ Installing Java 21 + Hyperledger Besu 25.12.0
3. ✅ Creating a secure system user + directories
4. ✅ Deploying the QELT genesis configuration
5. ✅ Generating (or importing) your validator key
6. ✅ Configuring the systemd service
7. ✅ Optional: HTTPS RPC endpoint (nginx + SSL)
8. ✅ Firewall configuration
9. ✅ Starting the node and verifying connectivity

### Step 3 — Wait for Full Sync

After the installer finishes, your node needs to sync with the network. Monitor progress:

```bash
# Watch live logs
sudo journalctl -u besu-qelt-validator -f

# Check sync status (returns "false" when fully synced)
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq .result

# Check your current block height
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq -r .result

# Compare with the network
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  https://mainnet.qelt.ai | jq -r .result
```

### Step 4 — Send Your Validator Address

At the end of the installation, the script displays your **Validator Address**. You can also find it anytime:

```bash
cat /data/qelt/VALIDATOR_INFO.txt
```

**📧 Email your Validator Address to: [laurent@qxmp.ai](mailto:laurent@qxmp.ai)**

Include in your email:
- Your **Validator Address** (e.g. `0x1234...5678`)
- Your **Enode URL** (e.g. `enode://abc...def@YOUR_IP:30303`)
- Confirmation that your node is **fully synced**

### Step 5 — Wait for Admission

Once the QELT team receives your information, existing validators will vote to admit your node to the network. QBFT requires a majority vote (currently 3 of 5 existing validators).

You can check if you've been admitted:

```bash
curl -s -X POST --data '{"jsonrpc":"2.0","method":"qbft_getValidatorsByBlockNumber","params":["latest"],"id":1}' \
  http://127.0.0.1:8545 | jq .result
```

When your address appears in the list — **congratulations, you're a QELT validator!** Your node will begin participating in consensus automatically.

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

# Network queries
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

## 🔐 Security

The installer implements production security best practices:

- **Dedicated system user** (`besu`) — the node daemon never runs as root
- **Systemd sandboxing** — `ProtectHome`, `ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`
- **Strict key permissions** — `chmod 600` on node private key
- **RPC localhost-only** by default — not exposed to the internet
- **SHA256 verification** of both the Besu binary and genesis file
- **UFW firewall** configuration
- **Node.js RPC middleware** (method whitelisting) if public RPC is enabled
- **Nginx rate limiting** + security headers if HTTPS endpoint is enabled

### ⚠️ Protect Your Node Key

Your node key (`/data/qelt/keys/nodekey`) is your validator identity.
- **Back it up securely** — if lost, you lose your validator slot
- **Never share your private key** — if stolen, someone can sign blocks as you

---

## 📖 Additional Documentation

| Document | Description |
|----------|-------------|
| [VALIDATOR_ADMISSION.md](VALIDATOR_ADMISSION.md) | Complete admission process — for both new operators and existing validators |
| [RESEARCH_BRIEF.md](RESEARCH_BRIEF.md) | Technical research and design decisions behind the installer |

---

## 🆘 Troubleshooting

### Node won't start
```bash
sudo journalctl -u besu-qelt-validator --no-pager -n 50
```
Common causes: port 30303 in use, insufficient RAM, wrong genesis, key permissions.

### No peers connecting
```bash
# Check port is open
sudo ss -tlnp | grep 30303
# Check bootnode reachability
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' https://mainnet.qelt.ai
```

### Sync stuck at block 0
Verify genesis file matches the network and bootnode enode URL is correct.

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
