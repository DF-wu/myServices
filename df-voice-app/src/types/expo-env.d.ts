declare const process: {
  env: {
    EXPO_OS?: "ios" | "android" | "web";
    EXPO_PUBLIC_DF_VOICE_ASR_BASE_URL?: string;
    EXPO_PUBLIC_DF_VOICE_ASR_MODEL?: string;
    EXPO_PUBLIC_DF_VOICE_CONVERSATION_BASE_URL?: string;
    EXPO_PUBLIC_DF_VOICE_CONVERSATION_MODEL?: string;
    EXPO_PUBLIC_DF_VOICE_CONVERSATION_MODE?: "chat_completions" | "responses";
    EXPO_PUBLIC_DF_VOICE_TTS_BASE_URL?: string;
    EXPO_PUBLIC_DF_VOICE_TTS_MODEL?: string;
    EXPO_PUBLIC_DF_VOICE_TTS_VOICE?: string;
  };
};
