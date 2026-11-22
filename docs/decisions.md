# CircuitPay — Decisions Log

## Day-1 Checks (2026-11-22)

### 1. Can a Solidity contract call a TapeOut circuit during a transaction?

**YES.** The TapeOut "processor" contract exposes view functions that any contract can STATICCALL:

```solidity
function eval(uint256 id, bytes calldata inputs) external view returns (bytes memory);
function step(uint256 id, bytes calldata state, bytes calldata inputs) external view returns (bytes memory newState, bytes memory outputs);
function circuitInfo(uint256 id) external view returns (uint32 nIn, uint32 nOut, uint32 nState, uint32 gateCount);
function netlist(uint256 id) external view returns (bytes memory);
```

- `eval` — for **combinational** (NAND-only) circuits. Stateless; pass inputs, get outputs.
- `step` — for **sequential** (LATCH) circuits. Caller supplies state; gets new state + outputs.

**Sources:** overclock `src/tapeout.js` ABI (verified against 86 mainnet circuits / 688 samples); latch, fusebox, evergate repos all call `eval` on mainnet.

**Decision:** Our MVP time-comparator circuit will be **combinational** (NAND-only), so we use `eval()`. No state management needed in our contract.

---

### 2. Gas cost of one `eval` call

**Not yet measured.** Community repos call it routinely in transactions, suggesting it's affordable for small circuits. We will benchmark a 32-bit comparator on mainnet (free `eth_call`) once taped out.

**TODO:** Call `eval` on an existing circuit via `eth_call` and measure gas with `eth_estimateGas`.

---

### 3. Is TapeOut on X Layer testnet (1952) or only mainnet (196)?

**Mainnet only.** Overclock's README explicitly states "TapeOut has no testnet" and deploys a stand-in (`TapeOutLocal.sol` / `MockProcessor.sol`) for testnet work. No TapeKit factory, opener, or processor address was found for chain 1952 in any repo.

**Decision:** We will:
- Write a **mock processor** contract (like Overclock did) for Foundry tests and testnet.
- Deploy and test our CircuitScheduler on **testnet (1952)** with the mock.
- For the demo, tape out the real circuit on **mainnet (196)** and point the contract at the real processor.

---

### 4. How latches tick

**Latches do NOT auto-tick.** State is **caller-held** and advanced one beat per `step()` call:
- One `step` call = one clock edge = one beat.
- A LATCH delays output by one beat.
- The caller must pass in the current state and receives the new state.

For combinational circuits (our MVP), this is irrelevant — `eval()` is pure and stateless.

**Source:** tapesynth ("one beat = one clock edge; a LATCH delays one beat"), fusebox ("state lives in the wallet and is passed in on each call"), overclock.

---

### 5. Wallet connect on a DeWEB site

**Not directly confirmed**, but multiple hackathon projects (fusebox, AjoChain, latch) build DeWEB sites that sign transactions and interact with contracts. AjoChain specifically describes MetaMask/wallet interactions from its DeWEB frontend.

**Decision:** Assume it works; validate when we build the site.

---

### 6. DeWEB publish cost and size limits

- **Container open fee:** 0.08 OKB (confirmed by fusebox deployment log).
- **File storage:** Files are split into chunks and stored on-chain with SHA-256 hashes.
- **Size limit:** No hard limit documented, but all projects keep bundles small (single HTML file or small Vite build). Tapesynth's 256 KB limit applies to its synth API, not DeWEB.
- **Constraint:** Must be fully self-contained — no off-chain references (CDN scripts, external CSS, etc.).
- **Naming:** Published at `<circuitId>.2.<processorId>.tape` via tapekit.org gateway.
- **Publish tool:** `npx tapesynth publish <dir> --processor <addr> --id <n>` or manual scripts.

**Decision:** Keep bundle small. Inline all JS/CSS. Use viem from a CDN-free build.

---

### 7. Stablecoin addresses and faucets

**X Layer mainnet (196):**
| Token | Address | Source |
|-------|---------|--------|
| USDT0 | `0x779Ded0c9e1022225f8E0630b35a9b54bE713736` | latch repo |
| USDC  | `0x74b7f16337b8972027f6196a17a631ac6de26d22` | Circle blog (needs verification) |

**X Layer testnet (1952):**
| Token | Address | Source |
|-------|---------|--------|
| USDC (Circle) | `0xDec90b78111Ba2fc6FC6d84d8B9ec159A2d4b9B3` | Circle docs |
| TestUSDT (AjoChain) | `0xBA2F34E38056aFEc0ab39BD48a0688f4c3680840` | AjoChain repo |

**Faucets:** Circle has a testnet USDC faucet (URL not confirmed). OKB testnet faucet not confirmed. We may need to deploy our own test ERC-20 on testnet.

**Decision:** Use USDC on mainnet for the final demo. Deploy a simple MockERC20 on testnet for development.

---

## Key TapeKit Addresses (Mainnet 196)

| Contract | Address | Source |
|----------|---------|--------|
| Factory | `0x1f09daefa827f02cbb40967cc91b259763760761` | overclock `src/tapeout.js` |
| Opener | `0x536add8f30f03b69f6fbf29d425a816a0dc50106` | overclock `src/tapeout.js` |
| Processor (latch) | `0x3728a5dfE596F6bF7309cA911e61ecaC9b0b6813` | latch repo |
| Processor (overclock) | `0xb00f10bb4b2f32c561bf90e205e543d0a2395971` | overclock repo |

**Warning from latch repo:** "Factory, opener, and processor numbers move. Confirm current addresses in the TapeOut docs before you send anything."

---

## Architecture Decisions

### Use combinational circuits only (MVP)
- Simpler: `eval()` is stateless, no state to store/pass.
- Our time-comparator just compares bits — naturally combinational.
- Avoids complexity of managing LATCH state in the contract.

### Mock processor for testing
- Foundry tests use a `MockProcessor` that returns configurable outputs.
- No dependency on mainnet for unit/integration tests.
- Fork tests can optionally hit mainnet to verify against real circuits.

### Target network strategy
- **Development + tests:** Local Foundry + mock processor.
- **Integration testing:** X Layer testnet (1952) with mock processor + mock ERC-20.
- **Demo:** X Layer mainnet (196) with real TapeOut circuit + real USDC.
