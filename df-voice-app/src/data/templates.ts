import { providerDefaults } from "@/config/provider-defaults";
import type { ClientSettings, ClientTemplate } from "@/types/client";

export const defaultSettings: ClientSettings = {
  asr: {
    baseUrl: providerDefaults.asrBaseUrl,
    apiKey: "",
    model: providerDefaults.asrModel,
    responseFormat: "verbose_json",
    language: "zh",
    prompt: "專有名詞、產品名、人名請優先保留原文。",
    temperature: 0,
    timeoutSec: 180,
    maxUploadMb: 100,
    extraHeadersJson: "",
    extraFormFieldsJson: "",
  },
  conversation: {
    baseUrl: providerDefaults.conversationBaseUrl,
    apiKey: "",
    mode: providerDefaults.conversationMode,
    model: providerDefaults.conversationModel,
    systemPrompt:
      "你是精準、直接的語音工作助理。先理解使用者口述內容，再用繁體中文給出可直接使用的回覆。",
    temperature: 0.4,
    topP: 1,
    frequencyPenalty: 0,
    presencePenalty: 0,
    maxOutputTokens: 1200,
    stream: false,
    timeoutSec: 120,
    extraHeadersJson: "",
    extraBodyJson: "",
  },
  tts: {
    baseUrl: providerDefaults.ttsBaseUrl,
    apiKey: "",
    model: providerDefaults.ttsModel,
    voice: providerDefaults.ttsVoice,
    responseFormat: "mp3",
    speed: 1,
    instructions: "語氣自然清楚，適合工作場景。",
    timeoutSec: 120,
    extraHeadersJson: "",
    extraBodyJson: "",
  },
  autoSpeak: false,
  keepConversationHistory: true,
};

export const templates: ClientTemplate[] = [
  {
    id: "capswriter-local",
    name: "CapsWriter 本機 ASR",
    description:
      "ASR 走本機 CapsWriter OpenAI Whisper 相容 HTTP API；對話與 TTS 指向本機 OpenAI-compatible 服務。",
    tags: ["offline", "capswriter", "local-first"],
    settings: defaultSettings,
  },
  {
    id: "openai-compatible-cloud",
    name: "OpenAI / 相容雲端",
    description:
      "所有服務都走同一個 /v1 base URL，適合 OpenAI、代理閘道或企業內部相容服務。",
    tags: ["cloud", "responses", "tts"],
    settings: {
      ...defaultSettings,
      asr: {
        ...defaultSettings.asr,
        baseUrl: "https://api.openai.com/v1",
        model: "whisper-1",
      },
      conversation: {
        ...defaultSettings.conversation,
        baseUrl: "https://api.openai.com/v1",
        mode: "responses",
        model: "gpt-4.1-mini",
        stream: true,
      },
      tts: {
        ...defaultSettings.tts,
        baseUrl: "https://api.openai.com/v1",
        model: "tts-1",
        voice: "alloy",
      },
    },
  },
  {
    id: "android-emulator-host",
    name: "Android Emulator Host",
    description:
      "Android emulator 連到開發機上的本機 ASR、LM Studio 或本機 TTS。10.0.2.2 會指回 host machine。",
    tags: ["android", "emulator", "local"],
    settings: {
      ...defaultSettings,
      asr: {
        ...defaultSettings.asr,
        baseUrl: "http://10.0.2.2:6017/v1",
      },
      conversation: {
        ...defaultSettings.conversation,
        baseUrl: "http://10.0.2.2:1234/v1",
        stream: true,
      },
      tts: {
        ...defaultSettings.tts,
        baseUrl: "http://10.0.2.2:8880/v1",
      },
    },
  },
  {
    id: "lm-studio-chat",
    name: "CapsWriter + LM Studio",
    description:
      "ASR 保持本機 CapsWriter，對話改走 LM Studio 或 Ollama OpenAI 相容端點。",
    tags: ["desktop", "lmstudio", "ollama"],
    settings: {
      ...defaultSettings,
      conversation: {
        ...defaultSettings.conversation,
        baseUrl: "http://localhost:1234/v1",
        mode: "chat_completions",
        model: "local-model",
        temperature: 0.2,
        stream: true,
      },
      tts: {
        ...defaultSettings.tts,
        baseUrl: "http://localhost:8880/v1",
      },
    },
  },
];
