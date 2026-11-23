/**
 * Prokairos Time Comparator — 32-bit >= comparator from NAND gates.
 *
 * Input:  64 bits (LSB first per TapeOut convention)
 *   bits  0-31: current block number
 *   bits 32-63: target block number
 *
 * Output: 1 bit
 *   1 if current >= target, 0 otherwise
 *
 * Gate count: 11 per bit = 352 NAND gates total
 * Tape-out cost: ~0.0013 + 352 * 0.0001 = ~0.037 OKB
 */

// --- NAND-only primitives ---

function NAND(a, b) {
  return (a & b) ^ 1;
}

function NOT(a) {
  return NAND(a, a);
}

function AND(a, b) {
  return NOT(NAND(a, b));
}

function OR(a, b) {
  return NAND(NOT(a), NOT(b));
}

function XNOR(a, b) {
  const nab = NAND(a, b);
  const x1 = NAND(a, nab);
  const x2 = NAND(b, nab);
  const xor = NAND(x1, x2);
  return NOT(xor); // 5 gates
}

// --- 32-bit >= comparator ---

/**
 * Evaluate: is A >= B?
 * @param {number} a - current block number (uint32)
 * @param {number} b - target block number (uint32)
 * @returns {number} 1 if a >= b, 0 otherwise
 */
function gte32(a, b) {
  // Extract individual bits (bit 31 = MSB)
  const aBits = [];
  const bBits = [];
  for (let i = 0; i < 32; i++) {
    aBits[i] = (a >>> i) & 1;
    bBits[i] = (b >>> i) & 1;
  }

  // Base case: LSB (bit 0)
  // gt_0 = A_0 AND NOT(B_0)
  const gt0 = AND(aBits[0], NOT(bBits[0]));
  // eq_0 = A_0 XNOR B_0
  const eq0 = XNOR(aBits[0], bBits[0]);
  // result_0 = gt_0 OR eq_0 (if equal or A>B at LSB, >= holds so far)
  let result = OR(gt0, eq0);

  // Chain from bit 1 to bit 31 (MSB)
  for (let i = 1; i < 32; i++) {
    const gt_i = AND(aBits[i], NOT(bBits[i]));
    const eq_i = XNOR(aBits[i], bBits[i]);
    // result = OR(gt_i, AND(eq_i, prev_result))
    //        = NAND(NOT(gt_i), NAND(eq_i, prev_result))
    result = NAND(NOT(gt_i), NAND(eq_i, result));
  }

  return result;
}

/**
 * Evaluate from raw input bytes (as TapeOut would receive them).
 * @param {Uint8Array} input - 8 bytes: current (4 bytes LE) + target (4 bytes LE)
 * @returns {Uint8Array} - 1 byte: 0x01 or 0x00
 */
function evalFromBytes(input) {
  if (input.length < 8) throw new Error("Need 8 bytes input");
  const current = input[0] | (input[1] << 8) | (input[2] << 16) | (input[3] << 24);
  const target = input[4] | (input[5] << 8) | (input[6] << 16) | (input[7] << 24);
  return new Uint8Array([gte32(current >>> 0, target >>> 0)]);
}

// --- Gate-level netlist (for verification and TAP-02 export) ---

/**
 * Build the NAND netlist for a 32-bit >= comparator.
 * Returns an array of gates: { id, type: 'NAND', inputs: [wireA, wireB], output: wireOut }
 * Input wires: 'a0'-'a31' (current block bits), 'b0'-'b31' (target block bits)
 * Output wire: the last gate's output
 */
function buildNetlist() {
  const gates = [];
  let wireId = 0;

  function nand(inA, inB) {
    const out = `w${wireId++}`;
    gates.push({ type: "NAND", inputs: [inA, inB], output: out });
    return out;
  }

  function not(a) {
    return nand(a, a);
  }

  function and(a, b) {
    return not(nand(a, b));
  }

  function or(a, b) {
    return nand(not(a), not(b));
  }

  function xnor(a, b) {
    const nab = nand(a, b);
    const x1 = nand(a, nab);
    const x2 = nand(b, nab);
    const xorOut = nand(x1, x2);
    return not(xorOut);
  }

  // Bit 0 (LSB) — base case
  const gt0 = and(`a0`, not(`b0`));
  const eq0 = xnor(`a0`, `b0`);
  let result = or(gt0, eq0);

  // Bits 1-31
  for (let i = 1; i < 32; i++) {
    const gt_i = and(`a${i}`, not(`b${i}`));
    const eq_i = xnor(`a${i}`, `b${i}`);
    result = nand(not(gt_i), nand(eq_i, result));
  }

  return { gates, outputWire: result, gateCount: gates.length };
}

// --- Tests ---

function runTests() {
  let passed = 0;
  let failed = 0;

  function assert(condition, msg) {
    if (condition) {
      passed++;
    } else {
      failed++;
      console.log(`  FAIL: ${msg}`);
    }
  }

  // Basic comparisons
  assert(gte32(100, 50) === 1, "100 >= 50");
  assert(gte32(50, 100) === 0, "50 >= 100 should be false");
  assert(gte32(100, 100) === 1, "100 >= 100 (equal)");
  assert(gte32(0, 0) === 1, "0 >= 0");
  assert(gte32(1, 0) === 1, "1 >= 0");
  assert(gte32(0, 1) === 0, "0 >= 1 should be false");

  // Edge cases
  assert(gte32(0xFFFFFFFF >>> 0, 0) === 1, "max >= 0");
  assert(gte32(0, 0xFFFFFFFF >>> 0) === 0, "0 >= max should be false");
  assert(gte32(0xFFFFFFFF >>> 0, 0xFFFFFFFF >>> 0) === 1, "max >= max");
  assert(gte32(0x80000000 >>> 0, 0x7FFFFFFF >>> 0) === 1, "MSB set >= MSB clear");
  assert(gte32(0x7FFFFFFF >>> 0, 0x80000000 >>> 0) === 0, "MSB clear >= MSB set should be false");

  // Adjacent values
  assert(gte32(1000, 999) === 1, "1000 >= 999");
  assert(gte32(999, 1000) === 0, "999 >= 1000 should be false");

  // Byte-level eval
  const input = new Uint8Array(8);
  // current = 100 (LE: 0x64, 0x00, 0x00, 0x00)
  input[0] = 100; input[1] = 0; input[2] = 0; input[3] = 0;
  // target = 50 (LE: 0x32, 0x00, 0x00, 0x00)
  input[4] = 50; input[5] = 0; input[6] = 0; input[7] = 0;
  assert(evalFromBytes(input)[0] === 1, "evalFromBytes(100, 50) = 1");

  input[0] = 50; input[4] = 100;
  assert(evalFromBytes(input)[0] === 0, "evalFromBytes(50, 100) = 0");

  // Netlist verification
  const netlist = buildNetlist();
  assert(netlist.gateCount === 352, `gate count should be 352, got ${netlist.gateCount}`);

  // Random tests (compare against native JS)
  for (let i = 0; i < 1000; i++) {
    const a = (Math.random() * 0xFFFFFFFF) >>> 0;
    const b = (Math.random() * 0xFFFFFFFF) >>> 0;
    const expected = (a >= b) ? 1 : 0;
    const got = gte32(a, b);
    if (got !== expected) {
      failed++;
      console.log(`  FAIL: gte32(${a}, ${b}) = ${got}, expected ${expected}`);
      break;
    }
    passed++;
  }

  console.log(`\nResults: ${passed} passed, ${failed} failed`);
  return failed === 0;
}

// Run if executed directly
runTests();

// Export for use in server
if (typeof module !== "undefined") {
  module.exports = { gte32, evalFromBytes, buildNetlist, NAND, NOT, AND, OR, XNOR };
}
