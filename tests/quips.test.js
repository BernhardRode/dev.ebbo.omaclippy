const assert = require("assert")
const Quips = require("../Quips.js")

// pickQuip -------------------------------------------------------------

;(function pickQuipReturnsAKnownLine() {
  // Arrange
  const random = () => 0 // always picks index 0

  // Act
  const quip = Quips.pickQuip(null, random)

  // Assert
  assert.ok(Quips.QUIP_BANK.includes(quip), "picked quip must come from the bank")
})()

;(function pickQuipAvoidsImmediateRepeatWhenPossible() {
  // Arrange: alternate between index 0 and index 1 on each call.
  let calls = 0
  const random = () => (calls++ % 2 === 0 ? 0 : 1 / Quips.QUIP_BANK.length)
  const lastQuip = Quips.QUIP_BANK[0]

  // Act
  const quip = Quips.pickQuip(lastQuip, random)

  // Assert
  assert.notStrictEqual(quip, lastQuip)
})()

;(function pickQuipGivesUpAfterBoundedRetriesInsteadOfLooping() {
  // Arrange: a degenerate randomFn that always returns the same quip as
  // lastQuip. This must terminate rather than loop forever.
  const lastQuip = Quips.QUIP_BANK[2]
  const random = () => 2 / Quips.QUIP_BANK.length

  // Act
  const quip = Quips.pickQuip(lastQuip, random)

  // Assert: it still returns *a* valid quip (equal to lastQuip is fine here --
  // the point under test is that it returns at all).
  assert.ok(Quips.QUIP_BANK.includes(quip))
})()

// buildPrompt ------------------------------------------------------------

;(function buildPromptMentionsClippyAndStaysReasonablyShort() {
  // Act
  const prompt = Quips.buildPrompt()

  // Assert
  assert.ok(prompt.toLowerCase().includes("clippy"))
  assert.ok(prompt.length < 600, "prompt should stay well under a typical arg-length concern")
})()

// buildAskPrompt -----------------------------------------------------------

;(function buildAskPromptEmbedsTheUsersTextSafely() {
  // Arrange: text containing a quote and a backslash, which JSON.stringify
  // must escape so the prompt stays one well-formed argv string.
  const userText = 'close all my "important" tabs\\now'

  // Act
  const prompt = Quips.buildAskPrompt(userText)

  // Assert
  assert.ok(prompt.includes(JSON.stringify(userText)))
  assert.ok(prompt.toLowerCase().includes("clippy"))
})()

;(function buildAskPromptTrimsWhitespaceAndTreatsNonStringsAsEmpty() {
  assert.ok(Quips.buildAskPrompt("  hi there  \n").includes(JSON.stringify("hi there")))
  assert.ok(Quips.buildAskPrompt(undefined).includes(JSON.stringify("")))
})()

// sanitizeAgentOutput ------------------------------------------------------

;(function sanitizeAgentOutputCollapsesNewlinesAndTrimsQuotes() {
  // Arrange
  const raw = '  "It looks like you\'re \ntesting\r\nsomething."  '

  // Act
  const clean = Quips.sanitizeAgentOutput(raw)

  // Assert
  assert.strictEqual(clean, "It looks like you're testing something.")
})()

;(function sanitizeAgentOutputStripsCodeFences() {
  // Arrange
  const raw = "Sure thing:\n```\nignore me\n```\nHere's your tip."

  // Act
  const clean = Quips.sanitizeAgentOutput(raw)

  // Assert
  assert.ok(!clean.includes("```"))
  assert.ok(clean.includes("Here's your tip."))
})()

;(function sanitizeAgentOutputReturnsEmptyStringForBlankOrNonStringInput() {
  assert.strictEqual(Quips.sanitizeAgentOutput(""), "")
  assert.strictEqual(Quips.sanitizeAgentOutput("   \n  "), "")
  assert.strictEqual(Quips.sanitizeAgentOutput(undefined), "")
  assert.strictEqual(Quips.sanitizeAgentOutput(null), "")
})()

;(function sanitizeAgentOutputTruncatesOverlyLongReplies() {
  // Arrange
  const raw = "x".repeat(500)

  // Act
  const clean = Quips.sanitizeAgentOutput(raw)

  // Assert
  assert.ok(clean.length <= Quips.MAX_QUIP_LENGTH)
  assert.ok(clean.endsWith("…"))
})()

console.log("clippy quips tests: all passed")
