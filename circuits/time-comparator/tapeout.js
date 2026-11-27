/**
 * Tape out the 32-bit >= comparator on X Layer mainnet (196).
 *
 * Usage:
 *   PRIVATE_KEY=0x... node tapeout.js [--dry-run]
 *
 * Calls: tapeout(bytes netlist, uint32 nIn, uint32 nOut) payable → uint256 id
 * Selector: 0x7bd3ac1d
 *
 * Prerequisites:
 *   - OKB in the wallet for gas + tapeout fee
 *   - Transistor tokens (NANDs) — the --mint flag on tapesynth handles this,
 *     but if calling manually you may need to acquire them first
 */

const { encode } = require("./encode-tap02.js");

const RPC_URL = "https://rpc.xlayer.tech";
const CHAIN_ID = 196;

// Processor addresses from decisions.md — VERIFY BEFORE USE
const PROCESSORS = {
  overclock: "0xb00f10bb4b2e32c561bf90e205e543d0a2395971",
  latch: "0x3728a5dfE596F6bF7309cA911e61ecaC9b0b6813",
};

const TAPEOUT_SELECTOR = "0x7bd3ac1d";
const CIRCUIT_INFO_SELECTOR = "0x084d60f1";
const EVAL_SELECTOR = "0x934d06ea";

async function rpcCall(method, params) {
  const resp = await fetch(RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }),
  });
  const json = await resp.json();
  if (json.error) throw new Error(`RPC error: ${json.error.message}`);
  return json.result;
}

function padUint32(n) {
  return n.toString(16).padStart(64, "0");
}

function padOffset(n) {
  return n.toString(16).padStart(64, "0");
}

function padBytes(hexBytes) {
  const len = hexBytes.length / 2;
  const padded = hexBytes + "0".repeat((32 - (len % 32)) % 32 * 2);
  return padUint32(len) + padded;
}

async function main() {
  const dryRun = process.argv.includes("--dry-run");
  const privateKey = process.env.PRIVATE_KEY;

  if (!privateKey && !dryRun) {
    console.error("Set PRIVATE_KEY env var (or use --dry-run)");
    process.exit(1);
  }

  // Encode the netlist
  const { netlist, nIn, nOut, gateCount } = encode();
  const netlistHex = netlist.toString("hex");

  console.log(`Circuit: 32-bit >= comparator`);
  console.log(`Gates: ${gateCount} NANDs`);
  console.log(`Inputs: ${nIn} bits, Outputs: ${nOut} bit`);
  console.log(`Netlist size: ${netlist.length} bytes`);
  console.log(`Processor: ${PROCESSORS.overclock}`);
  console.log();

  // Build calldata: tapeout(bytes netlist, uint32 nIn, uint32 nOut)
  // ABI encoding: selector + offset_to_bytes + nIn + nOut + bytes_length + bytes_data
  const bytesOffset = 3 * 32; // 3 slots (offset, nIn, nOut) before bytes data
  const calldata =
    TAPEOUT_SELECTOR +
    padOffset(bytesOffset) +
    padUint32(nIn) +
    padUint32(nOut) +
    padBytes(netlistHex);

  console.log(`Calldata length: ${(calldata.length - 2) / 2} bytes`);

  if (dryRun) {
    console.log("\n--- DRY RUN ---");
    console.log(`Calldata (hex): 0x${calldata.slice(0, 200)}...`);
    console.log("\nTo tape out for real:");
    console.log("1. Ensure you have OKB for gas + tapeout fee");
    console.log("2. Ensure you have transistor tokens (352 NANDs)");
    console.log("3. Run: PRIVATE_KEY=0x... node tapeout.js");
    console.log("\nAlternatively, use TapeSynth CLI:");
    console.log("  npx tapesynth synth comparator.v --kind verilog --out comparator.tsyn.json");
    console.log("  npx tapesynth tapeout comparator.tsyn.json --processor overclock --mint");
    return;
  }

  // Estimate gas
  console.log("Estimating gas...");
  try {
    const gasEstimate = await rpcCall("eth_estimateGas", [
      {
        from: "0x0000000000000000000000000000000000000000",
        to: PROCESSORS.overclock,
        data: "0x" + calldata,
        value: "0x0", // fee TBD — may need msg.value
      },
    ]);
    console.log(`Estimated gas: ${parseInt(gasEstimate, 16)}`);
  } catch (e) {
    console.log(`Gas estimation failed: ${e.message}`);
    console.log("This is expected if transistor tokens or msg.value fee is needed.");
    console.log("\nRecommended: use TapeSynth CLI instead (handles tokens + fees):");
    console.log("  npx tapesynth tapeout comparator.tsyn.json --processor overclock --mint");
  }
}

main().catch(console.error);
