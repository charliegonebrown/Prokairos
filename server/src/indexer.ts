import {
  type PublicClient,
  type Log,
  parseEventLogs,
} from "viem";
import { CircuitSchedulerAbi } from "./abi.js";
import type { Config } from "./config.js";

export interface ActiveSchedule {
  id: bigint;
  nextDue: bigint;
  deadline: bigint;
  remaining: bigint;
  interval: bigint;
  tip: bigint;
}

export class Indexer {
  private active = new Map<bigint, ActiveSchedule>();
  private lastSyncedBlock = 0n;

  constructor(
    private client: PublicClient,
    private config: Config
  ) {}

  getActive(): ActiveSchedule[] {
    return [...this.active.values()];
  }

  async rebuild(): Promise<void> {
    console.log("[indexer] Rebuilding schedule index from chain...");

    const count = await this.client.readContract({
      address: this.config.schedulerAddress,
      abi: CircuitSchedulerAbi,
      functionName: "scheduleCount",
    });

    console.log(`[indexer] ${count} total schedules on-chain`);

    const currentBlock = await this.client.getBlockNumber();

    for (let i = 1n; i <= count; i++) {
      const s = await this.client.readContract({
        address: this.config.schedulerAddress,
        abi: CircuitSchedulerAbi,
        functionName: "getSchedule",
        args: [i],
      });

      if (!s.cancelled && s.remaining > 0n && s.deadline >= currentBlock) {
        this.active.set(i, {
          id: i,
          nextDue: s.nextDue,
          deadline: s.deadline,
          remaining: s.remaining,
          interval: s.interval,
          tip: s.tip,
        });
      }
    }

    this.lastSyncedBlock = currentBlock;
    console.log(`[indexer] ${this.active.size} active schedules indexed`);
  }

  async processNewLogs(fromBlock: bigint, toBlock: bigint): Promise<void> {
    if (fromBlock > toBlock) return;

    const logs = await this.client.getLogs({
      address: this.config.schedulerAddress,
      fromBlock,
      toBlock,
    });

    if (logs.length === 0) return;

    const parsed = parseEventLogs({
      abi: CircuitSchedulerAbi,
      logs: logs as Log[],
    });

    for (const log of parsed) {
      if (log.eventName === "ScheduleCreated") {
        const args = log.args;
        this.active.set(args.id, {
          id: args.id,
          nextDue: args.startBlock,
          deadline: args.deadline,
          remaining: args.remaining,
          interval: args.interval,
          tip: args.tip,
        });
        console.log(`[indexer] New schedule #${args.id}`);
      }

      if (log.eventName === "ScheduleExecuted") {
        const args = log.args;
        const entry = this.active.get(args.id);
        if (entry) {
          entry.remaining = args.runsLeft;
          if (args.runsLeft === 0n) {
            this.active.delete(args.id);
            console.log(`[indexer] Schedule #${args.id} completed`);
          } else if (entry.interval > 0n) {
            entry.nextDue = BigInt(log.blockNumber) + entry.interval;
          }
        }
      }

      if (log.eventName === "ScheduleCancelled") {
        this.active.delete(log.args.id);
        console.log(`[indexer] Schedule #${log.args.id} cancelled`);
      }

      if (log.eventName === "ScheduleReclaimed") {
        this.active.delete(log.args.id);
        console.log(`[indexer] Schedule #${log.args.id} reclaimed`);
      }
    }

    this.lastSyncedBlock = toBlock;
  }

  getLastSyncedBlock(): bigint {
    return this.lastSyncedBlock;
  }
}
