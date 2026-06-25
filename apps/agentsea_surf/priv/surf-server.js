// AgentSea Surf — Node browser-automation sidecar (Playwright).
//
// Speaks newline-delimited JSON over stdin/stdout with AgentSea.Surf.Sidecar:
//   in : {"id":N,"command":"navigate"|"text"|"screenshot"|"click"|"eval","args":{...}}
//   out: {"id":N,"ok":true,"result":...} | {"id":N,"ok":false,"error":"..."}
//
// Requires Playwright:  npm install playwright && npx playwright install chromium
//
// (This is the production server. The test suite drives the sidecar against a
//  dependency-free fake instead, so this file is not exercised in CI.)

const readline = require("readline");

let browser, page;

async function ensurePage() {
  if (!page) {
    const { chromium } = require("playwright");
    browser = await chromium.launch();
    page = await browser.newPage();
  }
  return page;
}

async function handle(command, args) {
  const p = await ensurePage();
  switch (command) {
    case "navigate":
      await p.goto(args.url, { waitUntil: "domcontentloaded" });
      return { url: p.url() };
    case "text":
      return await p.innerText("body");
    case "screenshot":
      return { base64: (await p.screenshot()).toString("base64") };
    case "click":
      await p.click(args.selector);
      return { clicked: args.selector };
    case "eval":
      return await p.evaluate(args.script);
    default:
      throw new Error(`unknown command: ${command}`);
  }
}

const rl = readline.createInterface({ input: process.stdin });

rl.on("line", async (line) => {
  line = line.trim();
  if (!line) return;
  let req;
  try {
    req = JSON.parse(line);
  } catch (e) {
    return;
  }
  try {
    const result = await handle(req.command, req.args || {});
    process.stdout.write(JSON.stringify({ id: req.id, ok: true, result }) + "\n");
  } catch (e) {
    process.stdout.write(
      JSON.stringify({ id: req.id, ok: false, error: String(e.message || e) }) + "\n",
    );
  }
});

process.on("exit", () => browser && browser.close());
