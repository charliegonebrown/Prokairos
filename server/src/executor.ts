import {
  type PublicClient,
  type WalletClient,
  type Hex,
  formatEther,
} from "viem";
import { CircuitSchedulerAbi } from "./abi.js";
import type { Config } from "./config.js";
import type { Indexer, ActiveSchedule } from "./indexer.js";

export class Executor {
  private pending = new Set<bigint>();

  constructor(
    private client: PublicClient,
    private wallet: WalletClient,
    private indexer: Indexer,
    private config: Config
  ) {}

  async tick(blockNumber: bigint): Promise<void> {
    const schedules = this.indexer.getActive();
    if (schedules.length === 0) return;

    const candidates = schedules.filter(
      (s) =>
        s.nextDue <= blockNumber &&
        s.deadline >= blockNumber &&
        !this.pending.has(s.id)
    );

    if (candidates.length === 0) return;

    const readyChecks = await Promise.allSettled(
      candidates.map((s) => this.checkReady(s.id))
    );

    for (let i = 0; i < candidates.length; i++) {
      const result = readyChecks[i];
      if (result.status === "fulfilled" && result.value) {
        await this.tryExecute(candidates[i], blockNumber);
      }
    }
  }

  private async checkReady(id: bigint): Promise<boolean> {
    try {
      return await this.client.readContract({
        address: this.config.schedulerAddress,
        abi: CircuitSchedulerAbi,
        functionName: "isReady",
        args: [id],
      });
    } catch {
      return false;
    }
  }

  private async tryExecute(
    schedule: ActiveSchedule,
    blockNumber: bigint
  ): Promise<void> {
    const id = schedule.id;
    this.pending.add(id);

    try {
      const { request } = await this.client.simulateContract({
        address: this.config.schedulerAddress,
        abi: CircuitSchedulerAbi,
        functionName: "execute",
        args: [id],
        account: this.wallet.account!,
      });

      const hash = await this.wallet.writeContract(request);
      console.log(
        `[executor] Sent execute(${id}) at block ${blockNumber} → tx ${hash}`
      );

      const receipt = await this.client.waitForTransactionReceipt({ hash });

      if (receipt.status === "success") {
        console.log(
          `[executor] ✓ Schedule #${id} executed. Tip earned: ${schedule.tip} (raw). Gas: ${receipt.gasUsed}`
        );
      } else {
        console.log(`[executor] ✗ Schedule #${id} tx reverted: ${hash}`);
      }
    } catch (err: unknown) {
      const msg =
        err instanceof Error ? err.message : String(err);

      if (msg.includes("NoRunsLeft") || msg.includes("AlreadyCancelled")) {
        console.log(`[executor] Schedule #${id} already done, removing`);
      } else if (msg.includes("NotReady")) {
        // Someone else executed it, or circuit flipped back — no action needed
      } else {
        console.error(`[executor] Error executing #${id}: ${msg}`);
      }
    } finally {
      this.pending.delete(id);
    }
  }

  async checkBalance(): Promise<void> {
    const address = this.wallet.account!.address;
    const balance = await this.client.getBalance({ address });
    const formatted = formatEther(balance);
    console.log(`[executor] Wallet ${address} balance: ${formatted} OKB`);

    if (balance < 1_000_000_000_000_000n) {
      console.warn("[executor] ⚠ Low OKB balance! May not be able to submit txs.");
    }
  }
}
