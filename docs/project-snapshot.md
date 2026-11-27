# Prokairos — Project Snapshot

## One-line pitch
**Sign a payment once; a TapeOut circuit decides when it unlocks; our server delivers it, and anyone can deliver it if we go down.**

## What it does
Users schedule **one-time or recurring stablecoin payments** (USDT/USDC) on **X Layer** (OKX's Ethereum L2). Each payment is gated by a **TapeOut condition circuit** — an on-chain NAND-gate circuit that outputs `1` (go) or `0` (wait). Our server watches the chain and auto-executes due payments, earning a small tip. Anyone can also submit a due payment from a public "Due Payments" page as a fallback, earning the same tip. Funds sit in a **non-custodial contract** — only the receiver, the submitter tip, or a refund to the payer can ever receive them.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        USER (Browser + MetaMask)             │
│                                                              │
│   Site (static HTML)                                         │
│   ├── Create Schedule page     → createSchedule() tx         │
│   ├── My Schedules page        → reads chain via RPC         │
│   ├── Due Payments page        → execute() tx (earn tip)     │
│   └── Cancel / Reclaim         → cancel() / reclaim() tx     │
└──────────────┬───────────────────────────────────┬───────────┘
               │ (direct RPC to X Layer)           │
               ▼                                   ▼
┌──────────────────────────────────────────────────────────────┐
│              CircuitScheduler Contract (on X Layer)           │
│                                                              │
│  createSchedule() → pulls funds from payer, stores schedule  │
│  isReady(id)      → checks block, deadline, circuit output   │
│  execute(id)      → pays receiver + tip to msg.sender        │
│  cancel(id)       → payer stops & gets refund                │
│  reclaim(id)      → payer reclaims after deadline            │
│                                                              │
│         ┌──────────── STATICCALL ────────────┐               │
│         ▼                                    │               │
│  TapeOut Processor.eval(circuitId, inputs)   │               │
│  → returns 0x01 (go) or 0x00 (wait)         │               │
└──────────────────────────────────────────────────────────────┘
               ▲
               │ (polls every block via RPC)
┌──────────────┴───────────────────────────────────────────────┐
│              Server (Node.js on Render)                       │
│                                                              │
│  Indexer: rebuilds active schedule list from chain events     │
│  Executor: for each due schedule, calls isReady → execute     │
│  Health endpoint: GET / → {"status":"ok","block":N}          │
└──────────────────────────────────────────────────────────────┘
```

**Key design point:** The site reads directly from the chain — it never depends on the server. If the server goes down, users can still see their funds and submit due payments themselves.

---

## Smart Contract: CircuitScheduler

**Language:** Solidity 0.8.20 | **Framework:** Foundry | **Security:** OpenZeppelin SafeERC20 + ReentrancyGuard

### Schedule struct fields
| Field | Purpose |
|-------|---------|
| payer | Who created and funded the schedule |
| receiver | Who gets paid |
| token | ERC-20 stablecoin (USDC/USDT) |
| amount | Payment per run |
| tip | Reward per run for whoever submits the tx |
| processor | TapeOut processor contract address |
| circuitId | Which circuit to evaluate |
| circuitInputSpec | Target block number encoded as bytes |
| startBlock | Earliest block the first run can execute |
| interval | Blocks between runs (0 = one-time) |
| remaining | How many runs left |
| deadline | Last block any run may execute |
| nextDue | Next block a run becomes eligible |
| balance | Total funds locked (remaining × (amount + tip)) |
| cancelled | Whether the payer cancelled |

### Functions
| Function | Caller | What it does |
|----------|--------|-------------|
| `createSchedule(...)` | Payer | Validates inputs, pulls `remaining × (amount + tip)` from payer, stores schedule |
| `isReady(id)` view | Anyone | Returns true if: not cancelled, runs left, block >= nextDue, block <= deadline, funded, AND circuit output == 1 |
| `execute(id)` | Anyone | Re-checks readiness, pays receiver the amount, pays tip to msg.sender, advances nextDue, decrements remaining |
| `cancel(id)` | Payer only | Marks cancelled, refunds entire remaining balance to payer |
| `reclaim(id)` | Payer only | After deadline passes, refunds remaining balance |
| `getSchedule(id)` view | Anyone | Returns full schedule struct |
| `schedulesOf(addr)` view | Anyone | Returns array of schedule IDs for an address |
| `scheduleCount()` view | Anyone | Total schedules created |

### Events
- `ScheduleCreated(id, payer, receiver, token, amount, tip, processor, circuitId, startBlock, interval, remaining, deadline)`
- `ScheduleExecuted(id, submitter, receiver, amount, tip, runsLeft)`
- `ScheduleCancelled(id, refunded)`
- `ScheduleReclaimed(id, refunded)`

### Security features
- **ReentrancyGuard** on execute() — tested with a malicious reentrant ERC-20 token
- **SafeERC20** for all token transfers — handles non-standard return values
- **Checks-effects-interactions** pattern — state updated before external calls
- **No admin functions** — no one can move user funds; no pause on refunds
- **Immutable receiver/amount** — cannot be changed after creation
- **Custom errors** for gas-efficient reverts (NotPayer, ZeroAddress, ZeroAmount, InvalidSchedule, NotReady, AlreadyCancelled, NoRunsLeft, DeadlinePassed, DeadlineNotPassed, NothingToRefund)

### Test coverage: 44/44 tests passing
- 39 unit tests (creation, isReady, execute, cancel, reclaim, reentrancy, events, edge cases)
- 5 integration tests (full flows with ComparatorProcessor mock)

### Deployed addresses (testnet — chain 1952)
| Contract | Address |
|----------|---------|
| MockProcessor | `0x981F01Cd1a393584Ab764A51e8F6aa274C6a84f0` |
| MockERC20 (USDC, 6 decimals) | `0xe53e27F9301033265aF1464fbacE515B7FaDA796` |
| CircuitScheduler | `0xa679f1bA885c1e08D9C247992B32D80E847DC5aC` |

---

## Circuit: 32-bit Time Comparator

**Purpose:** Gates payments — outputs `1` when `currentBlock >= targetBlock`, allowing the payment to execute.

**Design:** Purely combinational (NAND gates only, no latches). Scans from MSB to LSB comparing bit pairs using gt (A AND NOT B), eq (XNOR), and chaining with OR/AND.

| Metric | Value |
|--------|-------|
| Input | 64 bits (32-bit current block + 32-bit target block, LSB-first) |
| Output | 1 bit |
| Original gate count | 352 NANDs (hand-designed) |
| Optimized gate count | **254 NANDs** (TapeSynth, dc2map+r2 strategy) |
| Netlist size | 1,778 bytes (optimized) |
| Tape-out cost estimate | ~0.026 OKB (254 gates) |
| Evaluation | Stateless `eval()`, not `step()` |

**How the contract uses it:**
```solidity
bytes memory input = abi.encodePacked(uint32(block.number), schedule.circuitInputSpec);
bytes memory result = ICircuitProcessor(processor).eval(circuitId, input);
// result[0] == 1 means "go", 0 means "wait"
```

**Files:**
- `circuits/time-comparator/reference.js` — JS reference model with 1,000+ tests
- `circuits/time-comparator/comparator.v` — Verilog source for TapeSynth
- `circuits/time-comparator/encode-tap02.js` — Manual TAP-02 binary encoder with 1,013 verification tests
- `circuits/time-comparator/tapeout.js` — Tape-out submission script (dry-run mode)
- `contracts/src/mocks/ComparatorProcessor.sol` — Solidity mock for Foundry tests

**Status:** Synthesized with TapeSynth, verified, ready to tape out on mainnet.

---

## Server (Submitter Service)

**Stack:** Node.js + TypeScript + viem | **Hosted on:** Render (Web Service)

### How it works
1. **Startup:** Rebuilds an index of all active schedules by reading the contract's `scheduleCount()` and `getSchedule()` for each
2. **Main loop (every ~1 second):**
   - Polls for the latest block number
   - Indexer processes new event logs (ScheduleCreated, Executed, Cancelled, Reclaimed) to keep the active set current
   - Executor filters for schedules where `nextDue <= currentBlock`
   - For each candidate: calls `isReady(id)` on-chain
   - If ready: simulates `execute(id)`, then sends the transaction
   - Earns the tip on success
3. **Resilience:**
   - Handles "already executed" reverts gracefully (someone else got there first)
   - Warns when OKB balance is low
   - Safe to restart — rebuilds state from chain
   - Graceful shutdown on SIGINT/SIGTERM
4. **Health endpoint:** `GET /` returns `{"status":"ok","block":N}` — keeps Render from killing the process

### Components
- `index.ts` — Main loop, viem client setup, health endpoint
- `indexer.ts` — Maintains in-memory set of active schedules from contract events
- `executor.ts` — Checks readiness and submits execute transactions
- `config.ts` — Loads env vars (PRIVATE_KEY, SCHEDULER_ADDRESS, RPC_URL, CHAIN_ID)
- `abi.ts` — CircuitScheduler ABI for viem

### Server wallet
- Address: `0xA21978b79287bEA930aD287BA9F48bBD302d695c`
- Balance: ~0.2 OKB (testnet)
- Private key stored in Render env vars (encrypted)

---

## Site (Frontend)

**Stack:** Single static HTML file (~1,500 lines), vanilla JS, raw RPC calls, MetaMask for wallet

### Pages

**1. Create Schedule (default page)**
- Toggle: One-time / Recurring
- Fields: Receiver address, Token (dropdown + "Add custom token" button), Amount, Tip per run, Start time (datetime picker → block estimate), Deadline, Interval + Count (recurring only)
- Total preview card: shows total locked, number of payments, per-run cost
- Flow: Approve token spend → Create schedule transaction
- Block-to-date conversion shown as estimates

**2. My Schedules**
- Lists all schedules for the connected wallet
- Each card shows: amount, token, receiver (truncated), status chip (Ready/Waiting/Completed/Expired/Cancelled), tip, runs remaining, next due estimate
- Status chips: green "Ready" with P logo, orange "Waiting", grey "Completed/Done", red "Cancelled/Expired"
- Click a card → bottom sheet modal with full details (all struct fields, block-to-date estimates)
- Action buttons: Cancel (refunds), Reclaim (after deadline)

**3. Due Payments (public)**
- Scans ALL schedules (not just the user's) for ready ones
- Shows: amount, receiver, "Earn X tip" badge, Submit button
- Anyone with a wallet can submit and earn the tip — this is the decentralized fallback

### UI/UX features
- Animated splash screen with "Prokairos" logo (clock-hand P mark swinging, letters revealing one by one, tagline fading in)
- Brand: maroon (#4A1C14), cream (#F1E3CC), camel (#B8916A) color scheme
- Fonts: Cormorant Garamond (display, italic), Jost (body)
- Mobile-first responsive design (bottom nav on mobile, top tabs on desktop)
- Bottom sheet modals on mobile, centered modals on desktop
- Toast notifications for transaction status
- Settings gear → reconfigure contract address, tokens, processor
- Tokens stored in localStorage with version tracking
- Custom token support: paste any ERC-20 address, auto-reads symbol + decimals

### Chain interaction
- Direct JSON-RPC calls (no ethers.js/viem dependency — raw `fetch`)
- Minimal ABI encoder/decoder built from scratch
- MetaMask for signing: `eth_requestAccounts`, `eth_sendTransaction`
- Listens for `accountsChanged` and `chainChanged` events

---

## Repo Structure

```
/contracts                    Foundry project
  /src
    CircuitScheduler.sol      Main contract (219 lines)
    /interfaces
      ICircuitProcessor.sol   TapeOut processor interface
    /mocks
      MockProcessor.sol       Configurable mock (returns true/false)
      MockERC20.sol           Test token with mint()
      ComparatorProcessor.sol Real comparator logic in Solidity
      ReentrantToken.sol      Malicious ERC20 for reentrancy test
  /test
    CircuitScheduler.t.sol    39 unit tests
    CircuitSchedulerIntegration.t.sol  5 integration tests
  /script
    Deploy.s.sol              DeployTestnet + DeployMainnet scripts

/circuits
  /time-comparator
    README.md                 Circuit design doc
    reference.js              JS reference model (1,016 tests)
    comparator.v              Verilog source for TapeSynth
    encode-tap02.js           TAP-02 binary encoder (1,013 verification tests)
    tapeout.js                Tape-out submission script

/server                       Node.js + TypeScript + viem
  /src
    index.ts                  Main loop + health endpoint
    indexer.ts                Schedule indexer (from events)
    executor.ts               Payment executor
    config.ts                 Env var loader
    abi.ts                    Contract ABI
  package.json                Dependencies: viem, tsx, typescript
  tsconfig.json

/site
  index.html                  Full app (~1,500 lines, self-contained)
  favicon.svg                 P-mark logo

/docs
  decisions.md                Day-1 research, deployed addresses, architecture decisions

CLAUDE.md                     Project spec and instructions
```

---

## Demo Script (from spec)

This is the scripted flow for the demo video:

1. **Recurring payment:** Create a recurring 10 USDC payment every ~2 minutes × 3 runs
2. **Circuit waiting:** Show the circuit is waiting (status: "Waiting")
3. **Circuit flips:** Time passes, circuit output goes to 1 (status: "Ready")
4. **Server pays:** Server auto-detects and executes the payment, tip earned
5. **Stop server:** Take the server down
6. **Fallback works:** Third payment appears on the "Due Payments" page
7. **Manual submit:** A second wallet connects and submits the due payment, earns the tip
8. **One-time payment:** Create a one-time payment
9. **Cancel + refund:** Cancel it immediately, show the refund arrives

**Key narrative points for judges:**
- Non-custodial: funds are always in the contract, never in our hands
- Circuit-gated: TapeOut circuit decides when payment unlocks
- Decentralized fallback: if our server dies, anyone can submit
- Tip incentive: submitters earn a reward, creating a self-sustaining execution market

---

## Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| Chain | X Layer (OKX L2, OP Stack, EVM-equivalent) |
| Gas token | OKB |
| Contract language | Solidity 0.8.20 |
| Contract framework | Foundry (forge, cast) |
| Contract security | OpenZeppelin (SafeERC20, ReentrancyGuard) |
| Circuit protocol | TapeOut (NAND/LATCH on-chain circuits) |
| Circuit tooling | TapeSynth (Verilog → TAP-02 netlist) |
| Server runtime | Node.js + TypeScript |
| Server chain lib | viem |
| Server hosting | Render (Web Service) |
| Frontend | Vanilla HTML/JS (single file, no build step) |
| Frontend wallet | MetaMask (window.ethereum) |
| Frontend hosting | TBD (GitHub Pages / Netlify / DeWEB) |

---

## Current Status (Nov 25, 2026)

| Component | Status | Notes |
|-----------|--------|-------|
| Smart contract | ✅ Done | 44/44 tests passing, deployed on testnet |
| Circuit design | ✅ Done | Synthesized to 254 NANDs, verified, ready to tape out |
| Server | ✅ Running | Live on Render, watching testnet blocks |
| Site | ✅ Built | Working locally, needs public hosting |
| E2E test (testnet) | ✅ Passed | Full flow verified on testnet |
| Tape-out (mainnet) | ⏳ Pending | Needs OKB on mainnet (~0.026 OKB) |
| Contract deploy (mainnet) | ⏳ Pending | Script ready, needs OKB |
| Site hosting | ⏳ Pending | GitHub Pages or Netlify (free) |
| Demo video | ⏳ Not started | Due Dec 4-6 |
| Submission | ⏳ Not started | Due Dec 7, 23:59 UTC |
