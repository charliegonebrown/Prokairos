import { type Hex } from "viem";

export interface Config {
  rpcUrl: string;
  wsUrl?: string;
  schedulerAddress: Hex;
  privateKey: Hex;
  pollIntervalMs: number;
  chainId: number;
}

export function loadConfig(): Config {
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("PRIVATE_KEY env var is required");
  }

  return {
    rpcUrl: process.env.RPC_URL || "https://testrpc.xlayer.tech",
    wsUrl: process.env.WS_URL,
    schedulerAddress: requireHex("SCHEDULER_ADDRESS"),
    privateKey: privateKey as Hex,
    pollIntervalMs: Number(process.env.POLL_INTERVAL_MS) || 1000,
    chainId: Number(process.env.CHAIN_ID) || 1952,
  };
}

function requireHex(name: string): Hex {
  const val = process.env[name];
  if (!val) throw new Error(`${name} env var is required`);
  if (!val.startsWith("0x")) throw new Error(`${name} must start with 0x`);
  return val as Hex;
}
