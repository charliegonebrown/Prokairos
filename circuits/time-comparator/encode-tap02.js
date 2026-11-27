/**
 * Encode the 32-bit >= comparator netlist into TAP-02 binary format.
 *
 * TAP-02 signal numbering:
 *   0 = constant 0
 *   1 = constant 1
 *   2 .. 2+nIn-1 = input bits (a0..a31 then b0..b31)
 *   2+nIn .. = gate output signals, one per NAND, in record order
 *
 * NAND record: 0x00 | a:u24 | b:u24 = 7 bytes
 * u24 = 3-byte big-endian unsigned integer
 */

const { buildNetlist } = require("./reference.js");

const N_IN = 64;  // 32 bits current + 32 bits target
const N_OUT = 1;

function encode() {
  const { gates, outputWire, gateCount } = buildNetlist();

  // Build wire-name → signal-index map
  const signalMap = new Map();
  // Inputs: a0..a31 → signals 2..33, b0..b31 → signals 34..65
  for (let i = 0; i < 32; i++) signalMap.set(`a${i}`, 2 + i);
  for (let i = 0; i < 32; i++) signalMap.set(`b${i}`, 34 + i);

  // Gate outputs: w0, w1, ... → signals 66, 67, ...
  let nextSignal = 2 + N_IN; // = 66
  for (const gate of gates) {
    signalMap.set(gate.output, nextSignal++);
  }

  // Verify output wire is the last signal
  const outputSignal = signalMap.get(outputWire);
  const totalSignals = nextSignal;
  const expectedOutputStart = totalSignals - N_OUT;
  if (outputSignal !== expectedOutputStart) {
    throw new Error(
      `Output wire ${outputWire} is signal ${outputSignal}, ` +
      `but TAP-02 expects the last ${N_OUT} signal(s) to be output (signal ${expectedOutputStart})`
    );
  }

  // Encode each NAND gate as a 7-byte record
  const buf = Buffer.alloc(gateCount * 7);
  let offset = 0;

  for (const gate of gates) {
    if (gate.type !== "NAND") throw new Error(`Unexpected gate type: ${gate.type}`);

    const a = signalMap.get(gate.inputs[0]);
    const b = signalMap.get(gate.inputs[1]);

    if (a === undefined) throw new Error(`Unknown wire: ${gate.inputs[0]}`);
    if (b === undefined) throw new Error(`Unknown wire: ${gate.inputs[1]}`);

    const gateSignal = signalMap.get(gate.output);
    if (a >= gateSignal || b >= gateSignal) {
      throw new Error(`Forward reference in gate ${gate.output}: inputs [${a}, ${b}] >= output ${gateSignal}`);
    }

    // Opcode
    buf[offset] = 0x00;
    // Input A as u24 big-endian
    buf[offset + 1] = (a >> 16) & 0xFF;
    buf[offset + 2] = (a >> 8) & 0xFF;
    buf[offset + 3] = a & 0xFF;
    // Input B as u24 big-endian
    buf[offset + 4] = (b >> 16) & 0xFF;
    buf[offset + 5] = (b >> 8) & 0xFF;
    buf[offset + 6] = b & 0xFF;

    offset += 7;
  }

  return { netlist: buf, nIn: N_IN, nOut: N_OUT, gateCount };
}

// Verify by simulating the TAP-02 binary
function simulate(netlistBuf, nIn, nOut, inputBits) {
  const totalGates = netlistBuf.length / 7;
  const totalSignals = 2 + nIn + totalGates;
  const signals = new Uint8Array(totalSignals);

  signals[0] = 0; // constant 0
  signals[1] = 1; // constant 1

  // Set input signals
  for (let i = 0; i < nIn && i < inputBits.length; i++) {
    signals[2 + i] = inputBits[i] & 1;
  }

  // Evaluate each NAND gate
  let sig = 2 + nIn;
  for (let g = 0; g < totalGates; g++) {
    const off = g * 7;
    if (netlistBuf[off] !== 0x00) throw new Error(`Bad opcode at gate ${g}`);
    const a = (netlistBuf[off + 1] << 16) | (netlistBuf[off + 2] << 8) | netlistBuf[off + 3];
    const b = (netlistBuf[off + 4] << 16) | (netlistBuf[off + 5] << 8) | netlistBuf[off + 6];
    signals[sig] = (signals[a] & signals[b]) ^ 1; // NAND
    sig++;
  }

  // Output is the last nOut signals
  const outputStart = totalSignals - nOut;
  return Array.from(signals.slice(outputStart, outputStart + nOut));
}

// Build input bits from two uint32 values (LSB first)
function makeInputBits(current, target) {
  const bits = new Uint8Array(64);
  for (let i = 0; i < 32; i++) {
    bits[i] = (current >>> i) & 1;
    bits[32 + i] = (target >>> i) & 1;
  }
  return bits;
}

// --- Main ---
const { netlist, nIn, nOut, gateCount } = encode();
console.log(`Encoded ${gateCount} NAND gates into ${netlist.length} bytes`);
console.log(`nIn=${nIn}, nOut=${nOut}`);
console.log(`Netlist hex (first 70 bytes): 0x${netlist.subarray(0, 70).toString("hex")}`);
console.log(`Netlist hex (full): 0x${netlist.toString("hex")}`);

// Verification tests
let passed = 0;
const testCases = [
  [100, 50, 1],
  [50, 100, 0],
  [100, 100, 1],
  [0, 0, 1],
  [1, 0, 1],
  [0, 1, 0],
  [0xFFFFFFFF >>> 0, 0, 1],
  [0, 0xFFFFFFFF >>> 0, 0],
  [0xFFFFFFFF >>> 0, 0xFFFFFFFF >>> 0, 1],
  [0x80000000 >>> 0, 0x7FFFFFFF >>> 0, 1],
  [0x7FFFFFFF >>> 0, 0x80000000 >>> 0, 0],
  [1000, 999, 1],
  [999, 1000, 0],
];

for (const [a, b, expected] of testCases) {
  const result = simulate(netlist, nIn, nOut, makeInputBits(a, b));
  if (result[0] !== expected) {
    console.error(`FAIL: ${a} >= ${b} expected ${expected}, got ${result[0]}`);
  } else {
    passed++;
  }
}

// Random tests
for (let i = 0; i < 1000; i++) {
  const a = (Math.random() * 0xFFFFFFFF) >>> 0;
  const b = (Math.random() * 0xFFFFFFFF) >>> 0;
  const expected = a >= b ? 1 : 0;
  const result = simulate(netlist, nIn, nOut, makeInputBits(a, b));
  if (result[0] !== expected) {
    console.error(`FAIL: ${a} >= ${b} expected ${expected}, got ${result[0]}`);
    break;
  }
  passed++;
}

console.log(`\nVerification: ${passed}/${testCases.length + 1000} tests passed`);

if (typeof module !== "undefined") {
  module.exports = { encode, simulate, makeInputBits };
}
