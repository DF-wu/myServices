import type { ClientSettings } from "@/types/client";

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
    ...current,
    ...incoming,
    asr: mergeProvider(current.asr, incoming.asr),
    conversation: mergeProvider(current.conversation, incoming.conversation),
    tts: mergeProvider(current.tts, incoming.tts),
  };
}

function mergeProvider<T extends { apiKey: string; extraHeadersJson: string }>(
  current: T,
  incoming?: Partial<T>,
): T {
  if (!incoming || !isRecord(incoming)) {
    return current;
  }
  const next = { ...current, ...incoming };
  for (const field of credentialFields) {
    if (next[field] === REDACTED_SETTING_VALUE) {
      next[field] = current[field];
    }
  }
  return next;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function safeTimestamp(timestamp: string) {
  return timestamp.replace(/[:.]/g, "-");
}
