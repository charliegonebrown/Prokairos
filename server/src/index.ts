import {
  createPublicClient,
  createWalletClient,
  http,
  webSocket,
  formatEther,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { createServer } from "node:http";
import { loadConfig } from "./config.js";
import { Indexer } from "./indexer.js";
import { Executor } from "./executor.js";

async function main() {
  console.log("[main] Prokairos server starting...");

  const config = loadConfig();
  const account = privateKeyToAccount(config.privateKey);

  const transport = config.wsUrl
    ? webSocket(config.wsUrl)
    : http(config.rpcUrl);

  const chain = {
    id: config.chainId,
    name: config.chainId === 196 ? "X Layer" : "X Layer Testnet",
    nativeCurrency: { name: "OKB", symbol: "OKB", decimals: 18 },
    rpcUrls: {
      default: { http: [config.rpcUrl] },
    },
  } as const;

  const publicClient = createPublicClient({ chain, transport });

  const walletClient = createWalletClient({
    chain,
    transport: http(config.rpcUrl),
    account,
  });

  const indexer = new Indexer(publicClient, config);
  const executor = new Executor(publicClient, walletClient, indexer, config);

  await indexer.rebuild();
  await executor.checkBalance();

  let lastBlock = indexer.getLastSyncedBlock();
  let running = true;
  let executedCount = 0;
  let lastError = "";
  const startTime = Date.now();

  const shutdown = () => {
    console.log("\n[main] Shutting down...");
    running = false;
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  const port = parseInt(process.env.PORT || "10000");
  createServer(async (_req, res) => {
    let walletBalance = "unknown";
    try {
      const bal = await publicClient.getBalance({ address: account.address });
      walletBalance = formatEther(bal);
    } catch {}

    const uptimeMs = Date.now() - startTime;
    const uptimeMin = Math.floor(uptimeMs / 60000);
    const uptimeH = Math.floor(uptimeMin / 60);
    const uptime = uptimeH > 0
      ? `${uptimeH}h ${uptimeMin % 60}m`
      : `${uptimeMin}m`;

    res.writeHead(200, {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    });
    res.end(JSON.stringify({
      status: "ok",
      block: Number(lastBlock),
      activeSchedules: indexer.getActive().length,
      executedCount,
      uptime,
      uptimeMs,
      wallet: account.address,
      walletBalance: walletBalance + " OKB",
      chainId: config.chainId,
      lastError: lastError || null,
    }));
  }).listen(port, () => console.log(`[main] Health endpoint on :${port}`));

  console.log(`[main] Watching from block ${lastBlock}. Poll: ${config.pollIntervalMs}ms`);

  while (running) {
    try {
      const currentBlock = await publicClient.getBlockNumber();

      if (currentBlock > lastBlock) {
        await indexer.processNewLogs(lastBlock + 1n, currentBlock);
        const before = indexer.getActive().length;
        await executor.tick(currentBlock);
        const after = indexer.getActive().length;
        executedCount += Math.max(0, before - after);
        lastBlock = currentBlock;
        lastError = "";
      }
    } catch (err) {
      lastError = err instanceof Error ? err.message : String(err);
      console.error("[main] Error in loop:", lastError);
    }

    await sleep(config.pollIntervalMs);
  }

  console.log("[main] Stopped.");
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((err) => {
  console.error("[main] Fatal:", err);
  process.exit(1);
});
