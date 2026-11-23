# Prokairos

Circuit-triggered scheduled stablecoin payments on X Layer.

Sign a payment once; a TapeOut circuit decides when it unlocks; a server delivers it, and anyone can deliver it if the server goes down.

## Architecture

```
DeWEB site (static) ──create / cancel / submit──┐
                                                 ▼
Server (submitter) ──execute(id) when ready──▶ CircuitScheduler ──pays──▶ Receiver
                                                 │
                                                 ▼ reads 0 or 1
                                        TapeOut condition circuit
```

## Repo layout

```
/contracts   Foundry — CircuitScheduler.sol, tests, mocks, deploy scripts
/circuits    Time comparator circuit: reference model, truth tables
/server      Node.js + TypeScript + viem submitter service
/site        Static front end (single HTML, viem via CDN)
/brand       Logo, wordmark, badge SVGs and color palette
/docs        Architecture notes, decisions log
```

## Deployed (X Layer testnet 1952)

| Contract | Address |
|---|---|
| CircuitScheduler | `0xa679f1bA885c1e08D9C247992B32D80E847DC5aC` |
| MockProcessor | `0x981F01Cd1a393584Ab764A51e8F6aa274C6a84f0` |
| MockERC20 (USDC) | `0xe53e27F9301033265aF1464fbacE515B7FaDA796` |

## Quick start

### Contracts (Foundry)

```bash
cd contracts
forge install
forge test
```

### Server

```bash
cd server
npm install
cp .env.example .env
# Fill in PRIVATE_KEY (submitter wallet with OKB for gas)
npm run dev
```

**Environment variables:**

| Variable | Required | Default |
|---|---|---|
| `PRIVATE_KEY` | yes | — |
| `SCHEDULER_ADDRESS` | yes | — |
| `RPC_URL` | no | `https://testrpc.xlayer.tech` |
| `WS_URL` | no | — |
| `CHAIN_ID` | no | `1952` |
| `POLL_INTERVAL_MS` | no | `1000` |

### Site

Open `site/index.html` in a browser (or serve it):

```bash
cd site && python -m http.server 8080
```

Connect MetaMask (X Layer testnet), configure contract addresses via the gear icon, and create schedules.

## Deploy server to Render

1. Push this repo to GitHub.
2. On [render.com](https://render.com), create a **Web Service** (or Background Worker).
3. Connect the GitHub repo.
4. Settings:
   - **Root directory:** `server`
   - **Build command:** `npm install && npm run build`
   - **Start command:** `npm start`
   - **Environment:** Node
5. Add environment variables in the Render dashboard:
   - `PRIVATE_KEY` — submitter wallet private key
   - `SCHEDULER_ADDRESS` — `0xa679f1bA885c1e08D9C247992B32D80E847DC5aC`
   - `RPC_URL` — `https://testrpc.xlayer.tech`
   - `CHAIN_ID` — `1952`
   - `POLL_INTERVAL_MS` — `1000`

The server is a long-running polling loop, so a **Background Worker** is the best fit (no HTTP port needed). A free-tier Web Service also works but Render may spin it down after inactivity.

## Brand

- **Palette:** Cream `#F1E3CC`, Camel `#B8916A`, Maroon `#4A1C14`, Ink `#2A120D`, Sand `#E2C9A6`
- **Display font:** Cormorant Garamond Italic 600
- **Body font:** Jost 400/500/600

## License

MIT
