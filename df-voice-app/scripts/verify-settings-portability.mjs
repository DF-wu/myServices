#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdir, rm, symlink } from "node:fs/promises";
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

await linkRuntimeAliases();

const {
  REDACTED_SETTING_VALUE,
  importSettingsText,
  redactedSettings,
  sanitizeSettings,
  settingsJsonExport,
} = await import(`../${buildDir}/lib/settings-portability.js`);
const { defaultSettings, templates } = await import(`../${buildDir}/data/templates.js`);
const { promptTemplates } = await import(`../${buildDir}/data/prompt-templates.js`);

const current = {
  asr: {
    apiKey: "asr-secret",
    baseUrl: "http://localhost:6017/v1",
    extraFormFieldsJson: "",
    extraHeadersJson: '{"x-route":"asr"}',
    language: "zh",
    maxUploadMb: 100,
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

const redacted = redactedSettings(current);
assert.equal(redacted.asr.apiKey, REDACTED_SETTING_VALUE);
assert.equal(redacted.asr.extraHeadersJson, REDACTED_SETTING_VALUE);
assert.equal(redacted.conversation.apiKey, REDACTED_SETTING_VALUE);
assert.equal(redacted.conversation.extraHeadersJson, REDACTED_SETTING_VALUE);
assert.equal(redacted.tts.apiKey, REDACTED_SETTING_VALUE);
assert.equal(redacted.tts.extraHeadersJson, REDACTED_SETTING_VALUE);
assert.equal(JSON.stringify(redacted).includes("asr-secret"), false);
assert.equal(JSON.stringify(redacted).includes("chat-secret"), false);
assert.equal(JSON.stringify(redacted).includes("tts-secret"), false);

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
        maxUploadMb: 64,
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
assert.equal(sanitized.asr.maxUploadMb, 64);
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
    maxUploadMb: 1.5,
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
assert.equal(stored.asr.maxUploadMb, current.asr.maxUploadMb);
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

assert.equal(JSON.stringify(defaultSettings).includes("secret"), false);
validateSettings(defaultSettings, "default settings");

assert.ok(templates.length >= 4, "expected provider templates for local, cloud, emulator, and desktop use");
assertUniqueIds(templates, "provider templates");
assert.ok(
  templates.some((template) => template.id === "capswriter-local"),
  "missing CapsWriter local provider template",
);
assert.ok(
  templates.some((template) => template.settings.conversation.mode === "responses"),
  "provider templates must include a Responses configuration",
);
assert.ok(
  templates.some((template) => template.settings.conversation.mode === "chat_completions"),
  "provider templates must include a Chat Completions configuration",
);
assert.ok(
  templates.some((template) => JSON.stringify(template.settings).includes("10.0.2.2")),
  "provider templates must include an Android emulator host setup",
);

for (const template of templates) {
  assertNonEmptyString(template.id, "provider template id");
  assert.match(template.id, /^[a-z0-9]+(?:-[a-z0-9]+)*$/);
  assertNonEmptyString(template.name, `${template.id} name`);
  assertNonEmptyString(template.description, `${template.id} description`);
  assert.ok(template.tags.length > 0, `${template.id} must have tags`);
  validateSettings(template.settings, `${template.id} settings`);
  assert.equal(template.settings.asr.apiKey, "", `${template.id} must not embed an ASR API key`);
  assert.equal(template.settings.conversation.apiKey, "", `${template.id} must not embed a chat API key`);
  assert.equal(template.settings.tts.apiKey, "", `${template.id} must not embed a TTS API key`);
  assert.equal(template.settings.asr.extraHeadersJson, "", `${template.id} must not embed ASR headers`);
  assert.equal(template.settings.conversation.extraHeadersJson, "", `${template.id} must not embed chat headers`);
  assert.equal(template.settings.tts.extraHeadersJson, "", `${template.id} must not embed TTS headers`);
}

assert.ok(promptTemplates.length >= 5, "expected a useful prompt workflow library");
assertUniqueIds(promptTemplates, "prompt templates");
assert.ok(
  promptTemplates.some((template) => template.id === "clean-transcript"),
  "missing transcript cleanup prompt template",
);
assert.ok(
  new Set(promptTemplates.map((template) => template.category)).size >= 4,
  "prompt templates should cover multiple workflow categories",
);

for (const template of promptTemplates) {
  assertNonEmptyString(template.id, "prompt template id");
  assert.match(template.id, /^[a-z0-9]+(?:-[a-z0-9]+)*$/);
  assertNonEmptyString(template.name, `${template.id} name`);
  assertNonEmptyString(template.category, `${template.id} category`);
  assertNonEmptyString(template.description, `${template.id} description`);
  assert.ok(template.tags.length > 0, `${template.id} must have tags`);
  assert.ok(template.prompt.trim().length >= 30, `${template.id} prompt should be production-useful`);
}

console.log("voice app logic verification passed");

async function linkRuntimeAliases() {
  const aliasRoot = `${buildDir}/node_modules/@`;
  await mkdir(aliasRoot, { recursive: true });
  await symlink("../../config", `${aliasRoot}/config`);
  await symlink("../../data", `${aliasRoot}/data`);
  await symlink("../../lib", `${aliasRoot}/lib`);
  await symlink("../../types", `${aliasRoot}/types`);
}

function validateSettings(settings, label) {
  assertOneOf(settings.asr.responseFormat, ["json", "text", "verbose_json", "srt", "vtt"], `${label} ASR format`);
  assertNumberRange(settings.asr.temperature, 0, 1, `${label} ASR temperature`);
  assertIntegerAtLeast(settings.asr.timeoutSec, 1, `${label} ASR timeout`);
  assertIntegerAtLeast(settings.asr.maxUploadMb, 1, `${label} ASR upload limit`);
  assertValidUrl(settings.asr.baseUrl, `${label} ASR base URL`);
  assertNonEmptyString(settings.asr.model, `${label} ASR model`);
  assertJsonObjectText(settings.asr.extraFormFieldsJson, `${label} ASR extra form fields`);
  assertJsonObjectText(settings.asr.extraHeadersJson, `${label} ASR extra headers`);

  assertOneOf(settings.conversation.mode, ["responses", "chat_completions"], `${label} conversation mode`);
  assertNumberRange(settings.conversation.temperature, 0, 2, `${label} conversation temperature`);
  assertNumberRange(settings.conversation.topP, 0, 1, `${label} conversation top_p`);
  assertNumberRange(settings.conversation.frequencyPenalty, -2, 2, `${label} frequency penalty`);
  assertNumberRange(settings.conversation.presencePenalty, -2, 2, `${label} presence penalty`);
  assertIntegerAtLeast(settings.conversation.maxOutputTokens, 1, `${label} max output tokens`);
  assertIntegerAtLeast(settings.conversation.timeoutSec, 1, `${label} conversation timeout`);
  assertValidUrl(settings.conversation.baseUrl, `${label} conversation base URL`);
  assertNonEmptyString(settings.conversation.model, `${label} conversation model`);
  assertNonEmptyString(settings.conversation.systemPrompt, `${label} system prompt`);
  assertJsonObjectText(settings.conversation.extraBodyJson, `${label} conversation extra body`);
  assertJsonObjectText(settings.conversation.extraHeadersJson, `${label} conversation extra headers`);

  assertOneOf(settings.tts.responseFormat, ["mp3", "opus", "aac", "flac", "wav", "pcm"], `${label} TTS format`);
  assertNumberRange(settings.tts.speed, 0.25, 4, `${label} TTS speed`);
  assertIntegerAtLeast(settings.tts.timeoutSec, 1, `${label} TTS timeout`);
  assertValidUrl(settings.tts.baseUrl, `${label} TTS base URL`);
  assertNonEmptyString(settings.tts.model, `${label} TTS model`);
  assertNonEmptyString(settings.tts.voice, `${label} TTS voice`);
  assertJsonObjectText(settings.tts.extraBodyJson, `${label} TTS extra body`);
  assertJsonObjectText(settings.tts.extraHeadersJson, `${label} TTS extra headers`);

  assert.equal(typeof settings.autoSpeak, "boolean", `${label} autoSpeak must be boolean`);
  assert.equal(typeof settings.keepConversationHistory, "boolean", `${label} history flag must be boolean`);
}

function assertUniqueIds(values, label) {
  const ids = values.map((value) => value.id);
  assert.deepEqual(ids, [...new Set(ids)], `${label} must have unique ids`);
}

function assertNonEmptyString(value, label) {
  assert.equal(typeof value, "string", `${label} must be a string`);
  assert.ok(value.trim().length > 0, `${label} must not be empty`);
}

function assertOneOf(value, allowed, label) {
  assert.ok(allowed.includes(value), `${label} must be one of ${allowed.join(", ")}`);
}

function assertNumberRange(value, min, max, label) {
  assert.equal(typeof value, "number", `${label} must be a number`);
  assert.ok(Number.isFinite(value), `${label} must be finite`);
  assert.ok(value >= min && value <= max, `${label} must be between ${min} and ${max}`);
}

function assertIntegerAtLeast(value, min, label) {
  assertNumberRange(value, min, Number.MAX_SAFE_INTEGER, label);
  assert.ok(Number.isInteger(value), `${label} must be an integer`);
}

function assertValidUrl(value, label) {
  assertNonEmptyString(value, label);
  const parsed = new URL(value);
  assert.ok(["http:", "https:"].includes(parsed.protocol), `${label} must use HTTP(S)`);
}

function assertJsonObjectText(value, label) {
  assert.equal(typeof value, "string", `${label} must be a string`);
  if (!value.trim()) {
    return;
  }
  const parsed = JSON.parse(value);
  assert.ok(parsed && typeof parsed === "object" && !Array.isArray(parsed), `${label} must be a JSON object`);
}
