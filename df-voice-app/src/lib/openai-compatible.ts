import { File, Paths } from "expo-file-system";

import { isWeb } from "@/lib/platform";
import type {
  ApiProbe,
  AsrSettings,
  ChatMessage,
  ConversationSettings,
  TranscriptionResult,
  TtsSettings,
  UploadableAudio,
} from "@/types/client";

type RequestOptions = {
  signal?: AbortSignal;
};

class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

class TimeoutError extends Error {
  constructor(timeoutSec: number) {
    super(`Request timed out after ${timeoutSec} seconds.`);
    this.name = "TimeoutError";
  }
}

function endpoint(baseUrl: string, path: string) {
  const cleanBase = baseUrl.trim().replace(/\/+$/, "");
  const cleanPath = path.startsWith("/") ? path : `/${path}`;
  if (cleanBase.endsWith("/v1")) {
    return `${cleanBase}${cleanPath}`;
  }
  return `${cleanBase}/v1${cleanPath}`;
}

function authHeaders(
  apiKey: string,
  extra?: HeadersInit,
  extraHeadersJson = "",
): HeadersInit {
  return {
    ...(apiKey.trim() ? { Authorization: `Bearer ${apiKey.trim()}` } : {}),
    ...headersFromJson(extraHeadersJson),
    ...extra,
  };
}

function timeoutSignal(timeoutSec: number, externalSignal?: AbortSignal) {
  const controller = new AbortController();
  let timedOut = false;
  const abortForTimeout = () => {
    timedOut = true;
    controller.abort();
  };
  const abortForExternal = () => controller.abort();
  const timeout = setTimeout(abortForTimeout, Math.max(1, timeoutSec) * 1000);
  if (externalSignal?.aborted) {
    abortForExternal();
  } else {
    externalSignal?.addEventListener("abort", abortForExternal, { once: true });
  }
  return {
    signal: controller.signal,
    timedOut: () => timedOut,
    cancel: () => {
      clearTimeout(timeout);
      externalSignal?.removeEventListener("abort", abortForExternal);
    },
  };
}

async function readError(response: Response) {
  const body = await response.text().catch(() => "");
  try {
    const parsed = JSON.parse(body) as { error?: { message?: string }; detail?: string };
    return parsed.error?.message ?? parsed.detail ?? body;
  } catch {
    return body || response.statusText || "Request failed";
  }
}

async function ensureOk(response: Response) {
  if (!response.ok) {
    throw new ApiError(response.status, await readError(response));
  }
}

function appendAudio(form: FormData, audio: UploadableAudio) {
  if (audio.file) {
    form.append("file", audio.file, audio.name);
    return;
  }
  if (!audio.uri) {
    throw new Error("No audio file or URI available");
  }
  form.append("file", {
    uri: audio.uri,
    name: audio.name,
    type: audio.mimeType,
  } as unknown as Blob);
}

function appendExtraFormFields(form: FormData, extraFormFieldsJson: string) {
  const fields = jsonObjectFromText(extraFormFieldsJson, "ASR extra form fields JSON");
  for (const [key, value] of Object.entries(fields)) {
    appendFormValue(form, key, value);
  }
}

function appendFormValue(form: FormData, key: string, value: unknown) {
  if (value === null || value === undefined) {
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      appendFormValue(form, key, item);
    }
    return;
  }
  if (typeof value === "object") {
    form.append(key, JSON.stringify(value));
    return;
  }
  form.append(key, String(value));
}

export async function transcribeAudio(
  settings: AsrSettings,
  audio: UploadableAudio,
  options: RequestOptions = {},
): Promise<TranscriptionResult> {
  const form = new FormData();
  appendAudio(form, audio);
  form.append("model", settings.model);
  form.append("response_format", settings.responseFormat);
  form.append("temperature", String(settings.temperature));
  if (settings.language.trim()) {
    form.append("language", settings.language.trim());
  }
  if (settings.prompt.trim()) {
    form.append("prompt", settings.prompt.trim());
  }
  appendExtraFormFields(form, settings.extraFormFieldsJson);

  const { signal, timedOut, cancel } = timeoutSignal(settings.timeoutSec, options.signal);
  try {
    const response = await fetch(endpoint(settings.baseUrl, "/audio/transcriptions"), {
      method: "POST",
      headers: authHeaders(settings.apiKey, undefined, settings.extraHeadersJson),
      body: form,
      signal,
    });
    await ensureOk(response);
    const contentType = response.headers.get("content-type") ?? "";
    if (settings.responseFormat === "text" || settings.responseFormat === "srt" || settings.responseFormat === "vtt") {
      const text = await response.text();
      return { text, raw: text, contentType };
    }

    const raw = (await response.json()) as unknown;
    return { text: extractTranscriptionText(raw), raw, contentType };
  } catch (error) {
    if (isAbortError(error) && timedOut()) {
      throw new TimeoutError(settings.timeoutSec);
    }
    throw error;
  } finally {
    cancel();
  }
}

export async function runConversation(
  settings: ConversationSettings,
  messages: ChatMessage[],
  options: RequestOptions & { onDelta?: (delta: string) => void } = {},
): Promise<string> {
  const payload =
    settings.mode === "responses"
      ? responsesPayload(settings, messages)
      : chatCompletionsPayload(settings, messages);
  const extraBody = jsonObjectFromText(settings.extraBodyJson, "Conversation extra body JSON");
  const path = settings.mode === "responses" ? "/responses" : "/chat/completions";
  const { signal, timedOut, cancel } = timeoutSignal(settings.timeoutSec, options.signal);
  try {
    const response = await fetch(endpoint(settings.baseUrl, path), {
      method: "POST",
      headers: authHeaders(
        settings.apiKey,
        { "Content-Type": "application/json" },
        settings.extraHeadersJson,
      ),
      body: JSON.stringify({ ...payload, ...extraBody }),
      signal,
    });
    await ensureOk(response);
    if (settings.stream) {
      return readConversationStream(response, settings.mode, options.onDelta);
    }
    const json = (await response.json()) as unknown;
    return settings.mode === "responses" ? extractResponseText(json) : extractChatText(json);
  } catch (error) {
    if (isAbortError(error) && timedOut()) {
      throw new TimeoutError(settings.timeoutSec);
    }
    throw error;
  } finally {
    cancel();
  }
}

export async function synthesizeSpeech(
  settings: TtsSettings,
  input: string,
  options: RequestOptions = {},
): Promise<string> {
  const { signal, timedOut, cancel } = timeoutSignal(settings.timeoutSec, options.signal);
  const extraBody = jsonObjectFromText(settings.extraBodyJson, "TTS extra body JSON");
  try {
    const response = await fetch(endpoint(settings.baseUrl, "/audio/speech"), {
      method: "POST",
      headers: authHeaders(
        settings.apiKey,
        { "Content-Type": "application/json" },
        settings.extraHeadersJson,
      ),
      body: JSON.stringify({
        model: settings.model,
        voice: settings.voice,
        input,
        response_format: settings.responseFormat,
        speed: settings.speed,
        ...(settings.instructions.trim() ? { instructions: settings.instructions.trim() } : {}),
        ...extraBody,
      }),
      signal,
    });
    await ensureOk(response);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (isWeb()) {
      const blob = new Blob([bytes], { type: `audio/${settings.responseFormat}` });
      return URL.createObjectURL(blob);
    }

    const file = new File(Paths.cache, `df-voice-tts-${Date.now()}.${settings.responseFormat}`);
    file.write(bytes);
    return file.uri;
  } catch (error) {
    if (isAbortError(error) && timedOut()) {
      throw new TimeoutError(settings.timeoutSec);
    }
    throw error;
  } finally {
    cancel();
  }
}

export async function probeModels(
  baseUrl: string,
  apiKey: string,
  extraHeadersJson = "",
  options: RequestOptions & { timeoutSec?: number } = {},
): Promise<ApiProbe> {
  const modelsEndpoint = endpoint(baseUrl, "/models");
  const timeout = options.timeoutSec ?? 30;
  const { signal, timedOut, cancel } = timeoutSignal(timeout, options.signal);
  try {
    const response = await fetch(modelsEndpoint, {
      headers: authHeaders(apiKey, undefined, extraHeadersJson),
      signal,
    });
    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        endpoint: modelsEndpoint,
        message: await readError(response),
        modelIds: [],
      };
    }
    const raw = (await response.json().catch(() => ({}))) as unknown;
    const modelIds = extractModelIds(raw);
    return {
      ok: true,
      status: response.status,
      endpoint: modelsEndpoint,
      message: modelIds.length
        ? `${modelIds.length} model${modelIds.length === 1 ? "" : "s"} available`
        : "Model endpoint reachable",
      modelIds,
    };
  } catch (error) {
    if (isAbortError(error) && timedOut()) {
      return {
        ok: false,
        endpoint: modelsEndpoint,
        message: `Request timed out after ${timeout} seconds.`,
        modelIds: [],
      };
    }
    if (isAbortError(error)) {
      throw error;
    }
    return {
      ok: false,
      endpoint: modelsEndpoint,
      message: error instanceof Error ? error.message : "Network request failed",
      modelIds: [],
    };
  } finally {
    cancel();
  }
}

function isAbortError(error: unknown) {
  return error instanceof Error && error.name === "AbortError";
}

function jsonObjectFromText(text: string, label: string): Record<string, unknown> {
  if (!text.trim()) {
    return {};
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`${label} is not valid JSON.`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`${label} must be a JSON object.`);
  }
  return parsed as Record<string, unknown>;
}

function headersFromJson(text: string): Record<string, string> {
  const headers = jsonObjectFromText(text, "Extra headers JSON");
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(headers)) {
    if (value === null || value === undefined) {
      continue;
    }
    if (typeof value === "object") {
      throw new Error(`Header ${key} must be a string, number, or boolean.`);
    }
    result[key] = String(value);
  }
  return result;
}

export function documentAssetToAudio(asset: {
  uri: string;
  name: string;
  mimeType?: string;
  size?: number;
  file?: Blob;
}): UploadableAudio {
  return {
    uri: asset.uri,
    file: asset.file,
    name: asset.name || "audio.m4a",
    mimeType: asset.mimeType || "audio/m4a",
    size: asset.size,
  };
}

export function recordingUriToAudio(uri: string): UploadableAudio {
  return {
    uri,
    name: "recording.m4a",
    mimeType: "audio/m4a",
  };
}

function chatCompletionsPayload(settings: ConversationSettings, messages: ChatMessage[]) {
  return {
    model: settings.model,
    messages: [
      ...(settings.systemPrompt.trim()
        ? [{ role: "system", content: settings.systemPrompt.trim() }]
        : []),
      ...messages.map((message) => ({
        role: message.role,
        content: message.content,
      })),
    ],
    temperature: settings.temperature,
    top_p: settings.topP,
    frequency_penalty: settings.frequencyPenalty,
    presence_penalty: settings.presencePenalty,
    max_tokens: settings.maxOutputTokens,
    stream: settings.stream,
  };
}

function responsesPayload(settings: ConversationSettings, messages: ChatMessage[]) {
  return {
    model: settings.model,
    input: [
      ...(settings.systemPrompt.trim()
        ? [{ role: "system", content: settings.systemPrompt.trim() }]
        : []),
      ...messages.map((message) => ({
        role: message.role,
        content: message.content,
      })),
    ],
    temperature: settings.temperature,
    top_p: settings.topP,
    max_output_tokens: settings.maxOutputTokens,
    stream: settings.stream,
  };
}

async function readConversationStream(
  response: Response,
  mode: ConversationSettings["mode"],
  onDelta?: (delta: string) => void,
) {
  let text = "";
  const emit = (delta: string) => {
    if (!delta) {
      return;
    }
    text += delta;
    onDelta?.(delta);
  };

  const consume = (event: SseEvent) => {
    if (event.data.trim() === "[DONE]") {
      return;
    }
    const parsed = parseJson(event.data);
    if (!parsed) {
      return;
    }
    const delta =
      mode === "responses"
        ? extractResponseStreamDelta(event.event, parsed, text.length > 0)
        : extractChatStreamDelta(parsed);
    emit(delta);
  };

  await readSse(response, consume);
  return text;
}

type SseEvent = {
  event: string;
  data: string;
};

async function readSse(response: Response, onEvent: (event: SseEvent) => void) {
  const body = response.body;
  if (!body || !("getReader" in body) || typeof TextDecoder === "undefined") {
    parseSseText(await response.text(), onEvent);
    return;
  }

  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    buffer = drainSseBuffer(buffer, onEvent);
  }

  buffer += decoder.decode();
  if (buffer.trim()) {
    parseSseText(buffer, onEvent);
  }
}

function drainSseBuffer(buffer: string, onEvent: (event: SseEvent) => void) {
  const normalized = buffer.replace(/\r\n/g, "\n");
  const blocks = normalized.split("\n\n");
  const rest = blocks.pop() ?? "";
  for (const block of blocks) {
    parseSseBlock(block, onEvent);
  }
  return rest;
}

function parseSseText(text: string, onEvent: (event: SseEvent) => void) {
  for (const block of text.replace(/\r\n/g, "\n").split("\n\n")) {
    parseSseBlock(block, onEvent);
  }
}

function parseSseBlock(block: string, onEvent: (event: SseEvent) => void) {
  if (!block.trim()) {
    return;
  }
  let event = "message";
  const data: string[] = [];
  for (const line of block.split("\n")) {
    if (!line || line.startsWith(":")) {
      continue;
    }
    if (line.startsWith("event:")) {
      event = line.slice("event:".length).trim();
    } else if (line.startsWith("data:")) {
      data.push(line.slice("data:".length).trimStart());
    }
  }
  if (data.length) {
    onEvent({ event, data: data.join("\n") });
  }
}

function parseJson(data: string): unknown | null {
  try {
    return JSON.parse(data);
  } catch {
    return null;
  }
}

function extractChatStreamDelta(raw: unknown): string {
  const value = raw as {
    choices?: Array<{ delta?: { content?: string | Array<{ text?: string }> } }>;
  };
  const content = value.choices?.[0]?.delta?.content;
  if (typeof content === "string") {
    return content;
  }
  if (Array.isArray(content)) {
    return content.map((part) => part.text ?? "").join("");
  }
  return "";
}

function extractResponseStreamDelta(event: string, raw: unknown, hasStreamedText: boolean): string {
  const value = raw as {
    type?: string;
    delta?: string;
    output_text?: string;
  };
  const type = value.type ?? event;
  if (type === "response.output_text.delta" && typeof value.delta === "string") {
    return value.delta;
  }
  if (
    type === "response.completed" &&
    !hasStreamedText &&
    typeof value.output_text === "string"
  ) {
    return value.output_text;
  }
  return "";
}

function extractTranscriptionText(raw: unknown): string {
  if (typeof raw === "string") {
    return raw;
  }
  if (raw && typeof raw === "object" && "text" in raw && typeof raw.text === "string") {
    return raw.text;
  }
  return JSON.stringify(raw, null, 2);
}

function extractChatText(raw: unknown): string {
  const value = raw as {
    choices?: Array<{ message?: { content?: string | Array<{ text?: string }> } }>;
  };
  const content = value.choices?.[0]?.message?.content;
  if (typeof content === "string") {
    return content;
  }
  if (Array.isArray(content)) {
    return content.map((part) => part.text ?? "").join("");
  }
  return JSON.stringify(raw, null, 2);
}

function extractResponseText(raw: unknown): string {
  const value = raw as {
    output_text?: string;
    output?: Array<{ content?: Array<{ text?: string; type?: string }> }>;
  };
  if (value.output_text) {
    return value.output_text;
  }
  const text = value.output
    ?.flatMap((item) => item.content ?? [])
    .map((part) => part.text ?? "")
    .join("");
  return text || JSON.stringify(raw, null, 2);
}

function extractModelIds(raw: unknown): string[] {
  const value = raw as { data?: Array<{ id?: unknown }> };
  if (!Array.isArray(value.data)) {
    return [];
  }
  return value.data
    .map((model) => model.id)
    .filter((modelId): modelId is string => typeof modelId === "string" && modelId.length > 0);
}
