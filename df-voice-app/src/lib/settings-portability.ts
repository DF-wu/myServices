import type {
  AsrResponseFormat,
  ClientSettings,
  ConversationMode,
  ConversationSettings,
  SpeechFormat,
} from "@/types/client";

export const REDACTED_SETTING_VALUE = "__DF_VOICE_REDACTED__";

type SettingsExport = {
  app: "df-voice-app";
  exportedAt: string;
  redacted: true;
  settings: ClientSettings;
  version: 1;
};

const credentialFields = ["apiKey", "extraHeadersJson"] as const;

export function settingsJsonExport(settings: ClientSettings) {
  const exportedAt = new Date().toISOString();
  const payload: SettingsExport = {
    app: "df-voice-app",
    exportedAt,
    redacted: true,
    settings: redactSettings(settings),
    version: 1,
  };
  return {
    filename: `df-voice-settings-${safeTimestamp(exportedAt)}.json`,
    mimeType: "application/json" as const,
    text: `${JSON.stringify(payload, null, 2)}\n`,
    title: "DF Voice settings",
  };
}

export function importSettingsText(current: ClientSettings, text: string): ClientSettings {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("Settings import is not valid JSON.");
  }

  const incoming = unwrapSettingsPayload(parsed);
  return mergeImportedSettings(current, incoming);
}

function redactSettings(settings: ClientSettings): ClientSettings {
  return {
    ...settings,
    asr: redactCredentials(settings.asr),
    conversation: redactCredentials(settings.conversation),
    tts: redactCredentials(settings.tts),
  };
}

function redactCredentials<T extends { apiKey: string; extraHeadersJson: string }>(value: T): T {
  return {
    ...value,
    apiKey: value.apiKey ? REDACTED_SETTING_VALUE : "",
    extraHeadersJson: value.extraHeadersJson ? REDACTED_SETTING_VALUE : "",
  };
}

function unwrapSettingsPayload(parsed: unknown): Partial<ClientSettings> {
  if (!isRecord(parsed)) {
    throw new Error("Settings import must be a JSON object.");
  }

  if (parsed.app === "df-voice-app" && isRecord(parsed.settings)) {
    return parsed.settings as Partial<ClientSettings>;
  }

  return parsed as Partial<ClientSettings>;
}

function mergeImportedSettings(current: ClientSettings, incoming: Partial<ClientSettings>): ClientSettings {
  return {
    asr: mergeAsrSettings(current.asr, incoming.asr),
    autoSpeak: booleanValue(incoming.autoSpeak, current.autoSpeak),
    conversation: mergeConversationSettings(current.conversation, incoming.conversation),
    keepConversationHistory: booleanValue(
      incoming.keepConversationHistory,
      current.keepConversationHistory,
    ),
    tts: mergeTtsSettings(current.tts, incoming.tts),
  };
}

function mergeAsrSettings(
  current: ClientSettings["asr"],
  incoming?: Partial<ClientSettings["asr"]>,
) {
  if (!isRecord(incoming)) {
    return current;
  }
  return mergeCredentials(current, {
    ...current,
    baseUrl: stringValue(incoming.baseUrl, current.baseUrl),
    extraFormFieldsJson: stringValue(incoming.extraFormFieldsJson, current.extraFormFieldsJson),
    language: stringValue(incoming.language, current.language),
    model: stringValue(incoming.model, current.model),
    prompt: stringValue(incoming.prompt, current.prompt),
    responseFormat: enumValue<AsrResponseFormat>(
      incoming.responseFormat,
      current.responseFormat,
      ["json", "text", "verbose_json", "srt", "vtt"],
    ),
    temperature: numberValue(incoming.temperature, current.temperature),
    timeoutSec: positiveNumberValue(incoming.timeoutSec, current.timeoutSec),
  });
}

function mergeConversationSettings(
  current: ConversationSettings,
  incoming?: Partial<ConversationSettings>,
) {
  if (!isRecord(incoming)) {
    return current;
  }
  return mergeCredentials(current, {
    ...current,
    baseUrl: stringValue(incoming.baseUrl, current.baseUrl),
    extraBodyJson: stringValue(incoming.extraBodyJson, current.extraBodyJson),
    frequencyPenalty: numberValue(incoming.frequencyPenalty, current.frequencyPenalty),
    maxOutputTokens: positiveNumberValue(incoming.maxOutputTokens, current.maxOutputTokens),
    mode: enumValue<ConversationMode>(
      incoming.mode,
      current.mode,
      ["responses", "chat_completions"],
    ),
    model: stringValue(incoming.model, current.model),
    presencePenalty: numberValue(incoming.presencePenalty, current.presencePenalty),
    stream: booleanValue(incoming.stream, current.stream),
    systemPrompt: stringValue(incoming.systemPrompt, current.systemPrompt),
    temperature: numberValue(incoming.temperature, current.temperature),
    timeoutSec: positiveNumberValue(incoming.timeoutSec, current.timeoutSec),
    topP: numberValue(incoming.topP, current.topP),
  });
}

function mergeTtsSettings(
  current: ClientSettings["tts"],
  incoming?: Partial<ClientSettings["tts"]>,
) {
  if (!isRecord(incoming)) {
    return current;
  }
  return mergeCredentials(current, {
    ...current,
    baseUrl: stringValue(incoming.baseUrl, current.baseUrl),
    extraBodyJson: stringValue(incoming.extraBodyJson, current.extraBodyJson),
    instructions: stringValue(incoming.instructions, current.instructions),
    model: stringValue(incoming.model, current.model),
    responseFormat: enumValue<SpeechFormat>(
      incoming.responseFormat,
      current.responseFormat,
      ["mp3", "opus", "aac", "flac", "wav", "pcm"],
    ),
    speed: positiveNumberValue(incoming.speed, current.speed),
    timeoutSec: positiveNumberValue(incoming.timeoutSec, current.timeoutSec),
    voice: stringValue(incoming.voice, current.voice),
  });
}

function mergeCredentials<T extends { apiKey: string; extraHeadersJson: string }>(
  current: T,
  next: T,
): T {
  for (const field of credentialFields) {
    if (next[field] === REDACTED_SETTING_VALUE) {
      next[field] = current[field];
    }
  }
  return next;
}

function stringValue(value: unknown, fallback: string) {
  return typeof value === "string" ? value : fallback;
}

function numberValue(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function positiveNumberValue(value: unknown, fallback: number) {
  const parsed = numberValue(value, fallback);
  return parsed > 0 ? parsed : fallback;
}

function booleanValue(value: unknown, fallback: boolean) {
  return typeof value === "boolean" ? value : fallback;
}

function enumValue<T extends string>(value: unknown, fallback: T, allowed: readonly T[]) {
  return typeof value === "string" && allowed.includes(value as T) ? (value as T) : fallback;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function safeTimestamp(timestamp: string) {
  return timestamp.replace(/[:.]/g, "-");
}
