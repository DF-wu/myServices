#!/usr/bin/env node
import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import { spawnSync } from "node:child_process";

const buildDir = "test-artifacts/logic-build";

await rm(buildDir, { force: true, recursive: true });

const tsc = spawnSync(
  "npx",
  ["tsc", "--project", "tsconfig.verify.json", "--pretty", "false"],
  { encoding: "utf-8", stdio: "pipe" },
);

if (tsc.status !== 0) {
  process.stderr.write(tsc.stdout);
  process.stderr.write(tsc.stderr);
  process.exit(tsc.status ?? 1);
}

const {
  REDACTED_SETTING_VALUE,
  importSettingsText,
  sanitizeSettings,
  settingsJsonExport,
} = await import(`../${buildDir}/lib/settings-portability.js`);

const current = {
  asr: {
    apiKey: "asr-secret",
    baseUrl: "http://localhost:6017/v1",
    extraFormFieldsJson: "",
    extraHeadersJson: '{"x-route":"asr"}',
    language: "zh",
    model: "whisper-1",
    prompt: "terms",
    responseFormat: "verbose_json",
    temperature: 0,
    timeoutSec: 30,
  },
  autoSpeak: false,
  conversation: {
    apiKey: "chat-secret",
    baseUrl: "http://localhost:1234/v1",
    extraBodyJson: "",
    extraHeadersJson: '{"x-route":"chat"}',
    frequencyPenalty: 0,
    maxOutputTokens: 64,
    mode: "responses",
    model: "local-model",
    presencePenalty: 0,
    stream: true,
    systemPrompt: "Reply clearly.",
    temperature: 0.2,
    timeoutSec: 30,
    topP: 1,
  },
  keepConversationHistory: true,
  tts: {
    apiKey: "tts-secret",
    baseUrl: "http://localhost:8880/v1",
    extraBodyJson: "",
    extraHeadersJson: '{"x-route":"tts"}',
    instructions: "",
    model: "tts-1",
    responseFormat: "wav",
    speed: 1,
    timeoutSec: 30,
    voice: "alloy",
  },
};

const exported = settingsJsonExport(current);
const exportedPayload = JSON.parse(exported.text);
assert.equal(exportedPayload.app, "df-voice-app");
assert.equal(exportedPayload.redacted, true);
assert.equal(exportedPayload.settings.asr.apiKey, REDACTED_SETTING_VALUE);
assert.equal(exportedPayload.settings.asr.extraHeadersJson, REDACTED_SETTING_VALUE);
assert.equal(exported.text.includes("asr-secret"), false);
assert.equal(exported.text.includes("chat-secret"), false);
assert.equal(exported.text.includes("tts-secret"), false);

const imported = importSettingsText(
  current,
  JSON.stringify({
    app: "df-voice-app",
    exportedAt: "2026-06-08T00:00:00.000Z",
    redacted: true,
    settings: {
      autoSpeak: true,
      conversation: {
        apiKey: REDACTED_SETTING_VALUE,
        maxOutputTokens: 128,
        mode: "chat_completions",
        model: "imported-model",
      },
      tts: {
        responseFormat: "mp3",
        speed: 1.25,
      },
    },
    version: 1,
  }),
);
assert.equal(imported.autoSpeak, true);
assert.equal(imported.conversation.apiKey, "chat-secret");
assert.equal(imported.conversation.maxOutputTokens, 128);
assert.equal(imported.conversation.mode, "chat_completions");
assert.equal(imported.conversation.model, "imported-model");
assert.equal(imported.tts.responseFormat, "mp3");
assert.equal(imported.tts.speed, 1.25);

const sanitized = importSettingsText(
  current,
  JSON.stringify({
    app: "df-voice-app",
    settings: {
      autoSpeak: "yes",
      asr: {
        responseFormat: "docx",
        temperature: 1.5,
        timeoutSec: 1.5,
        unknown: "ignored",
      },
      conversation: {
        frequencyPenalty: -3,
        maxOutputTokens: 1.5,
        mode: "legacy_completions",
        presencePenalty: 3,
        stream: "true",
        temperature: 3,
        timeoutSec: 0,
        topP: 1.4,
      },
      tts: {
        responseFormat: "ogg",
        speed: 5,
        timeoutSec: 0.5,
      },
    },
  }),
);
assert.equal(sanitized.autoSpeak, current.autoSpeak);
assert.equal(sanitized.asr.responseFormat, current.asr.responseFormat);
assert.equal(sanitized.asr.temperature, current.asr.temperature);
assert.equal(sanitized.asr.timeoutSec, current.asr.timeoutSec);
assert.equal(sanitized.asr.unknown, undefined);
assert.equal(sanitized.conversation.frequencyPenalty, current.conversation.frequencyPenalty);
assert.equal(sanitized.conversation.maxOutputTokens, current.conversation.maxOutputTokens);
assert.equal(sanitized.conversation.mode, current.conversation.mode);
assert.equal(sanitized.conversation.presencePenalty, current.conversation.presencePenalty);
assert.equal(sanitized.conversation.stream, current.conversation.stream);
assert.equal(sanitized.conversation.temperature, current.conversation.temperature);
assert.equal(sanitized.conversation.timeoutSec, current.conversation.timeoutSec);
assert.equal(sanitized.conversation.topP, current.conversation.topP);
assert.equal(sanitized.tts.responseFormat, current.tts.responseFormat);
assert.equal(sanitized.tts.speed, current.tts.speed);
assert.equal(sanitized.tts.timeoutSec, current.tts.timeoutSec);

const stored = sanitizeSettings(current, {
  asr: {
    apiKey: "stored-asr-secret",
    extraHeadersJson: '{"x-stored":"asr"}',
    temperature: 0.75,
    timeoutSec: 0,
  },
  conversation: { maxOutputTokens: 512, topP: 1.25 },
  tts: {
    apiKey: "stored-tts-secret",
    extraHeadersJson: '{"x-stored":"tts"}',
    speed: 0.5,
    timeoutSec: 1.5,
  },
});
assert.equal(stored.asr.apiKey, "stored-asr-secret");
assert.equal(stored.asr.extraHeadersJson, '{"x-stored":"asr"}');
assert.equal(stored.asr.temperature, 0.75);
assert.equal(stored.asr.timeoutSec, current.asr.timeoutSec);
assert.equal(stored.conversation.maxOutputTokens, 512);
assert.equal(stored.conversation.topP, current.conversation.topP);
assert.equal(stored.tts.apiKey, "stored-tts-secret");
assert.equal(stored.tts.extraHeadersJson, '{"x-stored":"tts"}');
assert.equal(stored.tts.speed, 0.5);
assert.equal(stored.tts.timeoutSec, current.tts.timeoutSec);

assert.throws(
  () => importSettingsText(current, "{bad json"),
  /not valid JSON/,
);
assert.throws(
  () => importSettingsText(current, "[]"),
  /must be a JSON object/,
);

console.log("settings portability logic verification passed");
