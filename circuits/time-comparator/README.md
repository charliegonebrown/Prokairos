# Time Comparator Circuit

32-bit unsigned `>=` comparator built entirely from NAND gates.

## Purpose

Gates Prokairos payments: outputs `1` when `currentBlock >= targetBlock`,
allowing the payment to execute.

## Interface

- **Inputs:** 64 bits (8 bytes), LSB-first per TapeOut convention
  - Bits 0-31: current block number (supplied by contract via `uint32(block.number)`)
  - Bits 32-63: target block number (stored in schedule's `circuitInputSpec`)
- **Output:** 1 bit — `1` if current >= target, `0` otherwise

## Gate count

- 11 NAND gates per bit × 32 bits = **352 NAND gates**
- Estimated tape-out cost: ~0.037 OKB

## How it works

Scans from MSB (bit 31) to LSB (bit 0):

1. At each bit position, compute:
   - `gt_i = A_i AND NOT(B_i)` — A is definitely greater here (3 gates)
   - `eq_i = A_i XNOR B_i` — bits are equal (5 gates)
2. Chain: `result_i = OR(gt_i, AND(eq_i, result_{i-1}))` (3 gates)
   - Implemented as: `NAND(NOT(gt_i), NAND(eq_i, result_{i-1}))`
3. Base case (bit 0): `result_0 = OR(gt_0, eq_0)`

All gates are NAND — no latches, purely combinational. Uses `eval()`, not `step()`.

## Files

- `reference.js` — JavaScript reference model with NAND-level simulation and 1000+ tests
- Contract mock: `contracts/src/mocks/ComparatorProcessor.sol`

## Tape-out instructions

Once OKB is available on mainnet (196):

1. Generate TAP-02 netlist from `reference.js` → `buildNetlist()`
2. Call `tapeout(netlist, 64, 1)` on a TapeOut processor contract with the fee
3. Record the returned circuit ID in `docs/decisions.md`
4. Update `contracts/script/Deploy.s.sol` with the real processor address and circuit ID

## Contract integration

The contract builds circuit input at call time:
```solidity
abi.encodePacked(uint32(block.number), s.circuitInputSpec)
```

Where `circuitInputSpec` = `abi.encodePacked(uint32(targetBlock))` set at schedule creation.
