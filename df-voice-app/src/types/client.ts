export type AsrResponseFormat = "json" | "text" | "verbose_json" | "srt" | "vtt";

export type ConversationMode = "responses" | "chat_completions";

export type SpeechFormat = "mp3" | "opus" | "aac" | "flac" | "wav" | "pcm";

export type Role = "user" | "assistant" | "system";

export type ChatMessage = {
  id: string;
  role: Role;
  content: string;
  createdAt: number;
};

export type UploadableAudio = {
  uri?: string;
  file?: Blob;
  name: string;
  mimeType: string;
  size?: number;
};

export type AsrSettings = {
  baseUrl: string;
  apiKey: string;
  model: string;
  responseFormat: AsrResponseFormat;
  language: string;
  prompt: string;
  temperature: number;
  timeoutSec: number;
  extraHeadersJson: string;
  extraFormFieldsJson: string;
};

export type ConversationSettings = {
  baseUrl: string;
  apiKey: string;
  mode: ConversationMode;
  model: string;
  systemPrompt: string;
  temperature: number;
  topP: number;
  frequencyPenalty: number;
  presencePenalty: number;
  maxOutputTokens: number;
  stream: boolean;
  timeoutSec: number;
  extraHeadersJson: string;
  extraBodyJson: string;
};

export type TtsSettings = {
  baseUrl: string;
  apiKey: string;
  model: string;
  voice: string;
  responseFormat: SpeechFormat;
  speed: number;
  instructions: string;
  timeoutSec: number;
  extraHeadersJson: string;
  extraBodyJson: string;
};

export type ClientSettings = {
  asr: AsrSettings;
  conversation: ConversationSettings;
  tts: TtsSettings;
  autoSpeak: boolean;
  keepConversationHistory: boolean;
};

export type ClientTemplate = {
  id: string;
  name: string;
  description: string;
  tags: string[];
  settings: ClientSettings;
};

export type ApiProbe = {
  ok: boolean;
  status?: number;
  message: string;
  endpoint?: string;
  modelIds?: string[];
};

export type TranscriptionResult = {
  text: string;
  raw: unknown;
  contentType: string;
};
