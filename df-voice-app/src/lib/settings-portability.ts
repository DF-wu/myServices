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
    settings: redactedSettings(settings),
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
  return sanitizeSettings(current, incoming);
}

export function sanitizeSettings(
  current: ClientSettings,
  incoming: Partial<ClientSettings>,
): ClientSettings {
  return mergeImportedSettings(current, incoming);
}

export function redactedSettings(settings: ClientSettings): ClientSettings {
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
    apiKey: stringValue(incoming.apiKey, current.apiKey),
    baseUrl: stringValue(incoming.baseUrl, current.baseUrl),
    extraFormFieldsJson: stringValue(incoming.extraFormFieldsJson, current.extraFormFieldsJson),
    extraHeadersJson: stringValue(incoming.extraHeadersJson, current.extraHeadersJson),
    language: stringValue(incoming.language, current.language),
    model: stringValue(incoming.model, current.model),
    prompt: stringValue(incoming.prompt, current.prompt),
    responseFormat: enumValue<AsrResponseFormat>(
      incoming.responseFormat,
      current.responseFormat,
      ["json", "text", "verbose_json", "srt", "vtt"],
    ),
    temperature: rangedNumberValue(incoming.temperature, current.temperature, { max: 1, min: 0 }),
    timeoutSec: rangedNumberValue(incoming.timeoutSec, current.timeoutSec, { integer: true, min: 1 }),
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
    apiKey: stringValue(incoming.apiKey, current.apiKey),
    baseUrl: stringValue(incoming.baseUrl, current.baseUrl),
    extraBodyJson: stringValue(incoming.extraBodyJson, current.extraBodyJson),
    extraHeadersJson: stringValue(incoming.extraHeadersJson, current.extraHeadersJson),
    frequencyPenalty: rangedNumberValue(incoming.frequencyPenalty, current.frequencyPenalty, {
      max: 2,
      min: -2,
    }),
    maxOutputTokens: rangedNumberValue(incoming.maxOutputTokens, current.maxOutputTokens, {
      integer: true,
      min: 1,
    }),
    mode: enumValue<ConversationMode>(
      incoming.mode,
      current.mode,
      ["responses", "chat_completions"],
    ),
    model: stringValue(incoming.model, current.model),
    presencePenalty: rangedNumberValue(incoming.presencePenalty, current.presencePenalty, {
      max: 2,
      min: -2,
    }),
    stream: booleanValue(incoming.stream, current.stream),
    systemPrompt: stringValue(incoming.systemPrompt, current.systemPrompt),
    temperature: rangedNumberValue(incoming.temperature, current.temperature, { max: 2, min: 0 }),
    timeoutSec: rangedNumberValue(incoming.timeoutSec, current.timeoutSec, { integer: true, min: 1 }),
    topP: rangedNumberValue(incoming.topP, current.topP, { max: 1, min: 0 }),
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
    apiKey: stringValue(incoming.apiKey, current.apiKey),
    baseUrl: stringValue(incoming.baseUrl, current.baseUrl),
    extraBodyJson: stringValue(incoming.extraBodyJson, current.extraBodyJson),
    extraHeadersJson: stringValue(incoming.extraHeadersJson, current.extraHeadersJson),
    instructions: stringValue(incoming.instructions, current.instructions),
    model: stringValue(incoming.model, current.model),
    responseFormat: enumValue<SpeechFormat>(
      incoming.responseFormat,
      current.responseFormat,
      ["mp3", "opus", "aac", "flac", "wav", "pcm"],
    ),
    speed: rangedNumberValue(incoming.speed, current.speed, { max: 4, min: 0.25 }),
    timeoutSec: rangedNumberValue(incoming.timeoutSec, current.timeoutSec, { integer: true, min: 1 }),
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

function rangedNumberValue(
  value: unknown,
  fallback: number,
  {
    integer,
    max,
    min,
  }: {
    integer?: boolean;
    max?: number;
    min?: number;
  },
) {
  const parsed = numberValue(value, fallback);
  if (integer && !Number.isInteger(parsed)) {
    return fallback;
  }
  if (min !== undefined && parsed < min) {
    return fallback;
  }
  if (max !== undefined && parsed > max) {
    return fallback;
  }
  return parsed;
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
