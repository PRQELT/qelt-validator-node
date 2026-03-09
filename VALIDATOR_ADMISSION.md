# QELT Mainnet — Validator Admission Guide

**For both new validator operators AND existing validator operators who vote them in.**

---

## Table of Contents

1. [Overview — How QBFT Admission Works](#overview)
2. [For New Validator Operators](#for-new-validator-operators)
3. [For Existing Validators (Voting)](#for-existing-validators-voting)
4. [Verification](#verification)
5. [Removing a Validator](#removing-a-validator)
6. [Liveness & Safety Considerations](#liveness--safety-considerations)
7. [Troubleshooting](#troubleshooting)

---

## Overview

QELT uses **QBFT (Quorum Byzantine Fault Tolerance)** with **block-header validator selection**. Validator admission is governed by on-chain voting — there is no smart contract involved. The protocol is built into the consensus engine itself.

### Key Facts

| Parameter | Value |
|-----------|-------|
| Current validators | 5 |
| Votes needed to admit | **3 of 5** (strictly more than 50%) |
| Vote mechanism | `qbft_proposeValidatorVote` JSON-RPC call |
| When admission activates | When the on-chain vote threshold is met (recorded in block headers) |
| Epoch length | 30,000 blocks (~41.7 hours) |
| What epochs do | Reset unrecorded pending votes; recorded votes persist |

### How It Works (Simplified)

```
New Operator                      Existing Validators              Blockchain
    │                                     │                           │
    ├─ Runs installer script             │                           │
    ├─ Node syncs to chain tip            │                           │
    ├─ Shares validator address ─────────►│                           │
    │                                     │                           │
    │                    Validator A calls │                           │
    │                    proposeValidatorVote ──────────────────────►  │
    │                                     │     Vote in block header  │
    │                    Validator B calls │                           │
    │                    proposeValidatorVote ──────────────────────►  │
    │                                     │     Vote in block header  │
    │                    Validator C calls │                           │
    │                    proposeValidatorVote ──────────────────────►  │
    │                                     │     3/5 threshold met!    │
    │                                     │                           │
    │◄──────────────────── New validator now participates in consensus │
    │                                     │                           │
```

---

## For New Validator Operators

### Step 1: Run the Installer

```bash
# Download and run the installer
sudo ./install-qelt-validator.sh
```

At the end, the script will display your **Validator Address** — this is the address the existing validators will vote for:

```
  ╔══════════════════════════════════════════════════════════╗
  ║           YOUR VALIDATOR IDENTITY                       ║
  ╠══════════════════════════════════════════════════════════╣
  ║ Validator Address: 0xYOUR_ADDRESS_HERE                   ║
  ║                                                          ║
  ║ ⚠  SAVE THIS ADDRESS — you will need it to request      ║
  ║    admission to the QELT validator set.                  ║
  ╚══════════════════════════════════════════════════════════╝
```

### Step 2: Wait for Full Sync

**⚠ CRITICAL:** Your node MUST be fully synced before requesting admission.

Why? When you are voted in, the total validator count increases. If your node is offline or not synced, it counts as a "fault" — potentially reducing the network's fault tolerance to zero. This could halt block production for the entire network.

**Monitor sync progress:**
```bash
# Watch live logs
sudo journalctl -u besu-qelt-validator -f

# Check sync status (returns "false" when fully synced)
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq .result

# Check current block number
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq -r .result

# Check peer count (should be ≥ 1)
curl -s -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq -r .result
```

**Compare your block height with the network:**
```bash
# Your node's block
LOCAL=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq -r .result)

# Network's block (via public endpoint)
REMOTE=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  https://mainnet.qelt.ai | jq -r .result)

echo "Local: $LOCAL | Network: $REMOTE"
```

When both values match (or are within a few blocks), you are synced.

### Step 3: Send Your Information to the QELT Team

Contact the QELT network administrators and provide:

1. **Validator Address:** `0xYOUR_ADDRESS_HERE`
2. **Enode URL:** `enode://YOUR_PUBLIC_KEY@YOUR_IP:30303`
3. **Confirmation that your node is fully synced**

You can find these values at any time:
```bash
cat /data/qelt/VALIDATOR_INFO.txt
```

### Step 4: Verify Admission

After the QELT team coordinates the vote among existing validators, check if you've been added:

```bash
# Check the current validator set
curl -s -X POST --data '{"jsonrpc":"2.0","method":"qbft_getValidatorsByBlockNumber","params":["latest"],"id":1}' \
  http://127.0.0.1:8545 | jq .result

# Your address should appear in the list
```

Once your address appears in the validator list, your node will automatically begin participating in consensus — no restart required.

---

## For Existing Validators (Voting)

### Prerequisites

- Your node must have the **QBFT** API namespace enabled in `--rpc-http-api`
- You must have local RPC access (localhost:8545)

### Step 1: Verify the New Node is Ready

Before casting your vote, confirm:

1. **The new node is synced:** Ask the operator to confirm `eth_syncing` returns `false`
2. **The new node has peers:** Ask the operator to confirm peer count > 0
3. **You have the correct validator address:** Double-check the 0x address with the operator

### Step 2: Cast Your Vote

```bash
# Replace NEW_VALIDATOR_ADDRESS with the actual address
curl -X POST --data '{
  "jsonrpc":"2.0",
  "method":"qbft_proposeValidatorVote",
  "params":["NEW_VALIDATOR_ADDRESS", true],
  "id":1
}' http://localhost:8545
```

**Example:**
```bash
curl -X POST --data '{
  "jsonrpc":"2.0",
  "method":"qbft_proposeValidatorVote",
  "params":["0x1234567890abcdef1234567890abcdef12345678", true],
  "id":1
}' http://localhost:8545
```

Expected response:
```json
{"jsonrpc":"2.0","id":1,"result":true}
```

### Important Notes About Voting

- The vote is **not immediately written to the chain**. It is stored locally and included in the next block that YOUR node proposes.
- QBFT uses round-robin block proposing, so your vote may take several blocks to appear on-chain.
- You only need to call `proposeValidatorVote` once. The local proposal persists across epoch boundaries.
- You need **3 of 5** existing validators to vote for the new address.

### Step 3: Verify the Vote Passed

After all required votes are cast:

```bash
# Check current validator set — the new address should appear
curl -s -X POST --data '{
  "jsonrpc":"2.0",
  "method":"qbft_getValidatorsByBlockNumber",
  "params":["latest"],
  "id":1
}' http://localhost:8545 | jq .result
```

### Step 4: Clean Up (Optional)

After successful admission, discard the local vote proposal:

```bash
curl -X POST --data '{
  "jsonrpc":"2.0",
  "method":"qbft_discardValidatorVote",
  "params":["NEW_VALIDATOR_ADDRESS"],
  "id":1
}' http://localhost:8545
```

---

## Verification

### Check Validator Set at Any Block

```bash
# At latest block
curl -s -X POST --data '{
  "jsonrpc":"2.0",
  "method":"qbft_getValidatorsByBlockNumber",
  "params":["latest"],
  "id":1
}' http://localhost:8545 | jq .result

# At a specific block (hex)
curl -s -X POST --data '{
  "jsonrpc":"2.0",
  "method":"qbft_getValidatorsByBlockNumber",
  "params":["0x7530"],
  "id":1
}' http://localhost:8545 | jq .result
```

### Check Pending Votes

```bash
curl -s -X POST --data '{
  "jsonrpc":"2.0",
  "method":"qbft_getPendingVotes",
  "params":[],
  "id":1
}' http://localhost:8545 | jq .result
```

---

## Removing a Validator

If a validator needs to be removed (e.g., compromised key, operator leaves, accidental admission):

```bash
# Vote to REMOVE — note the second parameter is "false"
curl -X POST --data '{
  "jsonrpc":"2.0",
  "method":"qbft_proposeValidatorVote",
  "params":["ADDRESS_TO_REMOVE", false],
  "id":1
}' http://localhost:8545
```

Same threshold applies: more than 50% of current validators must vote to remove.

---

## Liveness & Safety Considerations

### ⚠ The 2/3 Rule

QBFT requires **≥ 2/3 of validators** to sign each block. The network can tolerate up to **⌊(N-1)/3⌋** faulty or offline nodes.

| Total Validators | Fault Tolerance | Min Signers | RISK if adding offline node |
|:---:|:---:|:---:|---|
| 5 | 1 | 4 | Adding a 6th that's offline → fault tolerance consumed |
| 6 | 1 | 4 | Only 1 more failure allowed before network halt |
| 7 | 2 | 5 | Safer — can tolerate 2 failures |

### Rule: NEVER vote in a node that isn't fully synced and peered

If you increase the validator set size with a non-participating node:
- The fault tolerance does NOT increase (until N reaches the next threshold)
- You've "used up" one fault slot on a node that can't sign blocks
- One more failure in the existing set = **network halt**

### Recovery from a stalled network

If the network halts due to insufficient validators:
1. Restart all available validator nodes
2. Ensure P2P connectivity between all alive nodes
3. Wait for consensus to resume (QBFT has backoff behavior)
4. As a last resort, Besu supports genesis `transitions` overrides to force a validator set change — this requires coordinated manual intervention across all nodes

---

## Troubleshooting

### "Method not enabled" when calling qbft_proposeValidatorVote

The QBFT API namespace is not enabled. Edit the systemd service to include QBFT:
```
--rpc-http-api=ETH,NET,QBFT,WEB3,TXPOOL
```
Then: `sudo systemctl daemon-reload && sudo systemctl restart besu-qelt-validator`

### Vote cast but validator not appearing in set

- Votes are included when your node proposes a block (round-robin). Wait for a few rounds.
- Check that 3 of 5 validators have actually voted.
- If an epoch boundary passes before enough votes accumulate in blocks, the unrecorded votes reset — but local proposals persist and will be re-injected in the next epoch.

### New validator synced but not producing blocks after admission

- Verify the validator address appears in `qbft_getValidatorsByBlockNumber`
- Check that the node's private key derives to the correct address:
  ```bash
  besu public-key export-address --node-private-key-file=/data/qelt/keys/nodekey
  ```
- Check logs for consensus errors: `sudo journalctl -u besu-qelt-validator --since "10 min ago" | grep -i "error\|consensus\|validator"`

### Network stalled after adding new validator

- If the new node is offline: vote it out immediately using `proposeValidatorVote(address, false)`
- Restart all available validators if needed
- Monitor with: `curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' https://mainnet.qelt.ai | jq`

---

## Summary Checklist

### New Operator Checklist
- [ ] Ran installer script
- [ ] Node is syncing / has peers
- [ ] Node is FULLY SYNCED (eth_syncing = false)
- [ ] Sent validator address to QELT team
- [ ] Verified admission via qbft_getValidatorsByBlockNumber
- [ ] Backed up node key securely

### Existing Validator Checklist (per vote)
- [ ] Confirmed new node is fully synced
- [ ] Confirmed new node has correct genesis
- [ ] Verified the validator address with the operator
- [ ] Called qbft_proposeValidatorVote(address, true)
- [ ] Verified admission via qbft_getValidatorsByBlockNumber
- [ ] Called qbft_discardValidatorVote to clean up

---

*Document prepared for the QELT Validator Expansion Program, 2026.*
