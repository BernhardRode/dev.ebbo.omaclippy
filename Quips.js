// Pure JS quip logic: no QML/Quickshell imports here on purpose, so this
// file loads unmodified under plain `node` for tests (see tests/quips.test.js),
// mirroring how the other first-party/third-party plugins keep their model
// logic in a plain .js file (see e.g. vstoms.netbird/Model.js).

// Original, parody quips in the classic Clippy voice, aimed at a Linux/
// Hyprland desktop rather than Word/Excel. Deliberately not verbatim
// Microsoft copy -- new lines in the same spirit.
var QUIP_BANK = [
  "It looks like you're compiling something. Would you like help waiting?",
  "I noticed you haven't rebooted in 40 days. Bold. I respect it.",
  "It looks like you're staring at a stack trace. Have you tried reading it?",
  "Did you know? Pressing Super and typing usually finds the thing you want.",
  "It looks like you're about to force-push to main. Living dangerously today?",
  "I see you have 47 terminal tabs open. Would you like a 48th?",
  "It looks like you're writing a commit message. 'fix stuff' is always an option.",
  "Fun fact: that bug isn't a bug, it's an undocumented feature request.",
  "It looks like you're customizing your rice again instead of shipping. Relatable.",
  "Would you like help formatting that? I'm mostly kidding, your code is fine.",
  "It looks like it's been a while since you closed any browser tabs.",
  "I noticed a semicolon missing. Or maybe you're just writing Python.",
  "It looks like you're deep in a rabbit hole. Hydrate, then keep going.",
  "Would you like me to remind you what you were doing 20 minutes ago?",
  "It looks like that merge conflict has been open for a while. We can talk about it.",
  "Nice keybind. I definitely didn't watch you fumble it three times first.",
  "It looks like you're about to `rm -rf` something. No judgement, just checking.",
  "I see a lot of unstaged changes. They're not going to commit themselves.",
  "It looks like your uptime is longer than your last full night's sleep.",
  "Would you like help? No? Great, I'll just hover here looking concerned."
]

// Picks a random quip from the bank, avoiding an immediate repeat of
// `lastQuip` when the bank has more than one entry. `randomFn` defaults to
// Math.random but is injectable so tests can make the pick deterministic.
function pickQuip(lastQuip, randomFn) {
  var random = typeof randomFn === "function" ? randomFn : Math.random
  if (QUIP_BANK.length === 0) return ""
  if (QUIP_BANK.length === 1) return QUIP_BANK[0]

  var candidate = QUIP_BANK[Math.floor(random() * QUIP_BANK.length)]
  var attempts = 0
  // Bounded retry: a handful of re-rolls is enough to dodge one repeat
  // without ever risking an infinite loop if randomFn is degenerate.
  while (candidate === lastQuip && attempts < 5) {
    candidate = QUIP_BANK[Math.floor(random() * QUIP_BANK.length)]
    attempts += 1
  }
  return candidate
}

// Builds the one-shot prompt sent to `claude -p`. Kept short and
// self-contained so the CLI has no reason to ask a clarifying question or
// use tools -- it's meant to return one line and exit.
function buildPrompt() {
  return "You are Clippy, the classic Microsoft Office assistant, reimagined as a " +
    "sarcastic-but-helpful sidekick for a Linux/Hyprland desktop. Reply with exactly " +
    "one short, cheerful, slightly-too-eager sentence (max 140 characters): either an " +
    "unsolicited tip or a wry observation, in Clippy's voice, starting with \"It looks " +
    "like\" only if it fits naturally. Plain text only -- no quotes, no markdown, no " +
    "preamble, no sign-off, just the sentence."
}

// Builds the prompt for a user-initiated message (typed into the popup
// dialog), as opposed to an unsolicited buildPrompt() tip. Keeps the same
// one-line, no-markdown contract so sanitizeAgentOutput's assumptions still
// hold regardless of which prompt produced the reply.
function buildAskPrompt(userText) {
  var text = typeof userText === "string" ? userText.trim() : ""
  return "You are Clippy, the classic Microsoft Office assistant, reimagined as a " +
    "sarcastic-but-helpful sidekick for a Linux/Hyprland desktop. The user just typed " +
    "you this message: " + JSON.stringify(text) + ". Reply in character, one short " +
    "sentence (max 140 characters). Plain text only -- no quotes, no markdown, no " +
    "preamble, no sign-off, just the sentence."
}

var MAX_QUIP_LENGTH = 160

// Turns raw `claude -p` stdout into a single display-ready line, or "" if
// nothing usable came back (empty output, or output that's suspiciously
// long/structured, e.g. the CLI fell into a multi-paragraph answer).
function sanitizeAgentOutput(raw) {
  if (typeof raw !== "string") return ""
  var text = raw
    .replace(/```[\s\S]*?```/g, " ") // drop any code fences the model added anyway
    .replace(/[\r\n]+/g, " ") // collapse to one line
    .replace(/^["'\s]+|["'\s]+$/g, "") // trim surrounding quotes/whitespace
    .replace(/\s+/g, " ")
    .trim()

  if (text.length === 0) return ""
  if (text.length > MAX_QUIP_LENGTH) text = text.slice(0, MAX_QUIP_LENGTH - 1).trim() + "…"
  return text
}

module.exports = {
  QUIP_BANK: QUIP_BANK,
  pickQuip: pickQuip,
  buildPrompt: buildPrompt,
  buildAskPrompt: buildAskPrompt,
  sanitizeAgentOutput: sanitizeAgentOutput,
  MAX_QUIP_LENGTH: MAX_QUIP_LENGTH
}
