# CLAUDE.md: CircuitPay (X Layer TapeOut Accelerate hackathon)

You are helping me (a student developer) design and build **CircuitPay**: circuit-triggered scheduled
payments on X Layer. Act as my senior engineer and architect: plan before coding, explain decisions
simply, keep scope small, and push back when something is risky or will not fit the deadline.

**Hard deadline:** submission by **Dec 7, 2026, 23:59 UTC**. Build window: Nov 22 to Dec 6.

---

## 1. What we are building

Users schedule **one-time or recurring stablecoin payments** (USDT / USDC / USDG) on **X Layer**.
Each payment is gated by a **TapeOut condition circuit** that outputs `1` (go) or `0` (wait).

- **Our server** is the main submitter: it watches blocks and executes due payments, earning a small tip.
- **Anyone** can also submit a due payment from a public "Due payments" page (fallback), earning the tip.
- Funds sit in a **non-custodial contract**; only the receiver, the submitter tip, or a refund to the payer
  can ever receive them.

One-line pitch: *Sign a payment once; a TapeOut circuit decides when it unlocks; our server delivers it,
and anyone can deliver it if we go down.*

### Background facts (verify anything you rely on)
- X Layer: OKX's Ethereum L2 on the OP Stack, EVM-equivalent, gas token **OKB**, ~1-second blocks.
  Mainnet chain ID **196**, testnet chain ID **1952**. Public mainnet RPC: `https://rpc.xlayer.tech`.
- Smart contracts cannot run on timers. Something must send a transaction to trigger them.
- TapeOut: on-chain circuits built from NAND + LATCH tokens; a taped-out circuit is an NFT.
  Evaluating a circuit is a free read-only call. Circuits **cannot call other contracts** and have
  **no writable state**; the caller must supply all inputs.
- DeWEB: TapeOut's on-chain website hosting (a site lives in a circuit's ERC-6551 "container").
  A DeWEB site is static: it cannot run server code.
- TapeOut docs / tooling to consult: TapeKit (official kernel/addresses), TAP-02 (circuit netlist
  format and what one tick computes), TAP-10 (DeWEB access layer).

---

## 2. Architecture

```
DeWEB website (static, on X Layer) ──create / cancel / submit──┐
                                                               ▼
Our server (main submitter) ──────execute(id) when ready──▶ CircuitScheduler contract ──pays──▶ Receiver
                                                               │
                                                               ▼ reads 0 or 1
                                                   TapeOut condition circuit
```

The contract is the **only** place money moves, and it pays only when the circuit outputs exactly 1.

### Repo layout (monorepo)
```
/contracts   Foundry project: CircuitScheduler.sol, interfaces, tests, deploy scripts
/circuits    Circuit specs (truth tables, bit widths), local reference models, TapeOut IDs/addresses
/server      Node.js + TypeScript + viem submitter service
/site        Static DeWEB front end (HTML/JS or small bundled app, viem)
/docs        Architecture notes, decisions log, demo script
```

---

## 3. Smart contract spec: `CircuitScheduler`

**Schedule fields:** `payer`, `receiver`, `token`, `amount` (per run), `tip` (per run, to submitter),
`circuit` (+ input spec), `startBlock`, `interval` (blocks; 0 = one-time), `remaining` (runs left;
1 = one-time), `deadline` (last block a run may execute), `nextDue`.

**Functions**
| Function | Caller | Behaviour |
|---|---|---|
| `createSchedule(...)` | payer | pulls `count * (amount + tip)` (+ protocol fee if enabled) and stores the schedule |
| `isReady(id)` view | anyone | true if due, not expired, funded, and circuit output == 1 |
| `execute(id)` | anyone (server first) | re-checks, pays receiver, pays tip to `msg.sender`, advances `nextDue`, decrements `remaining` |
| `cancel(id)` | payer | stops future runs, refunds unused balance |
| `reclaim(id)` | payer | refunds after `deadline` if a run was never executed |
| `schedulesOf(addr)` view | site | lists a user's schedule IDs |

**Invariants (must be tested)**
1. A run executes at most once (checks-effects-interactions + `ReentrancyGuard`).
2. Nothing executes before `nextDue`, after `deadline`, or while the circuit returns 0.
3. Receiver and amount are immutable after creation.
4. No admin function can move user funds. A pause may block **new** schedules only, never refunds.
5. Events for create / execute / cancel / reclaim.

**Tooling:** Solidity, Foundry, OpenZeppelin (`SafeERC20`, `ReentrancyGuard`). Verify on Sourcify
(no API key) or OKLink.

---

## 4. Circuits

| Circuit | Inputs (supplied by contract) | Output 1 when | Priority |
|---|---|---|---|
| Time reached (comparator) | current block bits, target block bits | current >= target | MVP |
| Time AND approvals | time bit + 3 approval bits | time reached and >= 2 of 3 approved | if time allows |
| All members paid | one paid-bit per member | all paid | savings-group stretch |
| Deadline OR confirmation | time bit + confirm bit | either true | escrow stretch |

Guidelines: small bit widths (e.g. low 32 bits of block number), prefer **combinational** circuits fed
by the contract over latch-based counters, and keep a local reference model of each circuit so contract
tests run without the chain (use a mock circuit contract in Foundry tests).

---

## 5. Server (main submitter)

Node.js + TypeScript + viem. Loop on every new block (WebSocket subscription, fallback RPC):
1. Maintain an index of active schedules from contract events (rebuildable from chain).
2. For schedules with `nextDue <= block`, call `isReady(id)`.
3. If ready: simulate `execute(id)`, then send it.
4. Log tips; optional receiver notification.

Rules: dedicated wallet with a small OKB float; private key only via env var / secrets manager;
**never commit keys or `.env`**; alert when stopped, lagging, or low on OKB; idempotent and safe to
restart; handle "already executed" reverts quietly (someone else got there first).

---

## 6. DeWEB site

Pages: **Create schedule** (One-time / Recurring toggle, receiver, token, amount, start block with
estimated date, interval, count, condition circuit, tip, total shown before signing), **My schedules**
(status, live circuit output, history, Cancel / Reclaim), **Due payments** (public list of ready runs
with a Submit button and tip shown), **Incoming** (stretch).

Rules: read state from chain (events + views), never depend on our server to show a user their funds;
label block-to-date conversions as estimates; keep bundle small for on-chain storage.

---

## 7. Day-1 checks (do these first, with me)

Before production code, help me answer:
- [ ] Can a Solidity contract call a TapeOut circuit's evaluation inside a transaction? What interface?
- [ ] Gas cost of one evaluation of a 32-bit comparator circuit.
- [ ] Is TapeOut on X Layer testnet (1952) or only mainnet (196)? Record addresses from TapeKit.
- [ ] How latches tick (TAP-02): lazy on read or per block?
- [ ] Does wallet connect/sign work on a DeWEB site via the TapeOut gateway?
- [ ] DeWEB publish cost (container fee in OKB) and size limits on X Layer.
- [ ] Stablecoin addresses (USDT/USDC/USDG) and faucets on the chosen network.

**Fallback if contracts cannot call circuits:** the contract checks a block-number condition directly;
the server and site evaluate the circuit off-chain and display it. Tell me clearly if we hit this.

---

## 8. Milestones

| Dates | Deliverable | Done when |
|---|---|---|
| Nov 22-23 | Day-1 checks | answers recorded in `/docs/decisions.md` |
| Nov 23-27 | Contract + tests | all functions pass Foundry tests incl. double-execute, early-execute, cancel, reclaim |
| Nov 24-28 | Condition circuits | time circuit taped out; address recorded; contract reads it |
| Nov 27-30 | Server | executes a due payment on testnet within 5 s, survives restart |
| Nov 28-Dec 2 | DeWEB site | create, list, cancel, Due payments work via gateway |
| Dec 2-4 | Deploy + E2E | demo script runs twice with no manual fixes |
| Dec 4-6 | Video + write-up | < 3 min video, description, business model |
| Dec 7 | Submit | Google Form before 23:59 UTC |

Demo script: recurring 10 USDT every 2 minutes x3 -> circuit waiting -> flips -> server pays ->
stop server -> payment appears on Due payments -> second wallet submits and earns tip -> one-time
payment created and cancelled (refund).

---

## 9. How to work with me

- **Plan first.** For any non-trivial task, propose a short plan and wait for my OK before large changes.
- **Small steps.** One component at a time; run tests after each change; show me how to run them.
- **Explain simply.** I'm learning; explain the "why" in plain words, briefly.
- **Ask before:** deploying to mainnet, spending real funds, adding dependencies, or changing the spec.
- **Security first:** no secrets in code or git; checks-effects-interactions; test edge cases.
- **Scope guard:** if a feature risks the Dec 7 deadline, say so and suggest cutting it.
- **Keep `/docs/decisions.md` updated** with each important decision and why.
- Don't invent TapeOut interfaces or addresses: if unknown, say so and help me find them.
