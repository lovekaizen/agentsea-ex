// A dependency-free fake of the Surf Node sidecar server, for testing the
// Port/protocol/correlation logic against a real Node subprocess (no Playwright,
// no browser, no network). Same newline-delimited JSON protocol.

const readline = require("readline");
const rl = readline.createInterface({ input: process.stdin });

let currentUrl = null;

// Returns {result} on success, or {error} for an unknown command.
function handle(command, args) {
  switch (command) {
    case "navigate":
      currentUrl = args.url;
      return { result: { url: currentUrl } };
    case "text":
      return { result: `Fake page content for ${currentUrl}` };
    case "screenshot":
      return { result: { base64: Buffer.from("fake-image").toString("base64") } };
    case "click":
      return { result: { clicked: args.selector } };
    case "eval":
      return { result: "evaluated" };
    default:
      return { error: `unknown command: ${command}` };
  }
}

rl.on("line", (line) => {
  line = line.trim();
  if (!line) return;

  let req;
  try {
    req = JSON.parse(line);
  } catch (e) {
    return;
  }

  const outcome = handle(req.command, req.args || {});
  const response =
    "error" in outcome
      ? { id: req.id, ok: false, error: outcome.error }
      : { id: req.id, ok: true, result: outcome.result };

  process.stdout.write(JSON.stringify(response) + "\n");
});
