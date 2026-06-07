import type { ConversationMode } from "@/types/client";

function envValue(name: keyof typeof process.env, fallback: string) {
  const value = process.env[name];
  return value?.trim() ? value.trim() : fallback;
}

function conversationMode(): ConversationMode {
  return process.env.EXPO_PUBLIC_DF_VOICE_CONVERSATION_MODE === "responses"
    ? "responses"
    : "chat_completions";
}

export const providerDefaults = {
  asrBaseUrl: envValue("EXPO_PUBLIC_DF_VOICE_ASR_BASE_URL", "http://localhost:6017/v1"),
  asrModel: envValue("EXPO_PUBLIC_DF_VOICE_ASR_MODEL", "whisper-1"),
  conversationBaseUrl: envValue(
    "EXPO_PUBLIC_DF_VOICE_CONVERSATION_BASE_URL",
    "http://localhost:1234/v1",
  ),
  conversationModel: envValue("EXPO_PUBLIC_DF_VOICE_CONVERSATION_MODEL", "local-model"),
  conversationMode: conversationMode(),
  ttsBaseUrl: envValue("EXPO_PUBLIC_DF_VOICE_TTS_BASE_URL", "http://localhost:8880/v1"),
  ttsModel: envValue("EXPO_PUBLIC_DF_VOICE_TTS_MODEL", "tts-1"),
  ttsVoice: envValue("EXPO_PUBLIC_DF_VOICE_TTS_VOICE", "alloy"),
} as const;
