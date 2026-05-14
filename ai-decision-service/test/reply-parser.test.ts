import assert from "node:assert/strict";
import test from "node:test";

import {
  normalizeReplyText,
  parseContextualConfirmationReply,
  parseDeterministicReply
} from "../src/reply-parser/deterministic-reply-parser.js";

test("normalizeReplyText removes accents, punctuation, and extra whitespace", () => {
  assert.equal(normalizeReplyText("  Sí!!   "), "si");
  assert.equal(normalizeReplyText("¿Quizás?"), "quizas");
});

test("parser classifies clear session replies", () => {
  assert.equal(parseDeterministicReply("confirmo"), "confirmed");
  assert.equal(parseDeterministicReply("voy"), "confirmed");
  assert.equal(parseDeterministicReply("no puedo"), "declined");
  assert.equal(parseDeterministicReply("capaz"), "maybe");
});

test("parser keeps bare acknowledgements ambiguous without confirmation context", () => {
  assert.equal(parseDeterministicReply("ok"), "ambiguous");
  assert.equal(parseDeterministicReply("dale"), "ambiguous");
  assert.equal(parseDeterministicReply("no"), "ambiguous");
  assert.equal(parseDeterministicReply("yes"), "ambiguous");
});

test("parser avoids false positives for qualified replies", () => {
  assert.equal(parseDeterministicReply("si pero llego tarde"), "ambiguous");
  assert.equal(parseDeterministicReply("no se si puedo ir"), "maybe");
  assert.equal(parseDeterministicReply("no me gusta ese horario"), "ambiguous");
  assert.equal(
    parseDeterministicReply("Hola Sessia, soy Tamara. Quiero conectar mis sesiones por WhatsApp."),
    "ambiguous"
  );
});

test("parser classifies clear payment reports", () => {
  assert.equal(parseDeterministicReply("ya pague"), "payment_reported");
  assert.equal(parseDeterministicReply("transfer sent"), "payment_reported");
});

test("contextual parser resolves short replies after a confirmation request", () => {
  assert.equal(parseContextualConfirmationReply("dale"), "confirmed");
  assert.equal(parseContextualConfirmationReply("yes"), "confirmed");
  assert.equal(parseContextualConfirmationReply("no"), "declined");
  assert.equal(parseContextualConfirmationReply("capaz"), "maybe");
});
