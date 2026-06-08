import * as Sharing from "expo-sharing";
import { Share } from "react-native";

import { isWeb } from "@/lib/platform";
import type { SpeechFormat } from "@/types/client";

type AudioExport = {
  createdAt: number;
  format: SpeechFormat;
  uri: string;
};

export async function exportAudioFile(file: AudioExport) {
  const filename = audioFilename(file.createdAt, file.format);
  if (isWeb()) {
    downloadAudioOnWeb(file.uri, filename);
    return filename;
  }

  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(file.uri, {
      dialogTitle: "Save DF Voice audio",
      mimeType: audioMimeType(file.format),
    });
    return filename;
  }

  await Share.share({
    title: "DF Voice audio",
    url: file.uri,
    message: file.uri,
  });
  return filename;
}

function downloadAudioOnWeb(uri: string, filename: string) {
  if (typeof document === "undefined") {
    throw new Error("Audio downloads are not available in this web runtime.");
  }
  const anchor = document.createElement("a");
  anchor.href = uri;
  anchor.download = filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
}

function audioFilename(createdAt: number, format: SpeechFormat) {
  return `df-voice-speech-${safeTimestamp(new Date(createdAt).toISOString())}.${format}`;
}

function audioMimeType(format: SpeechFormat) {
  if (format === "opus") {
    return "audio/ogg";
  }
  if (format === "pcm") {
    return "audio/L16";
  }
  return `audio/${format}`;
}

function safeTimestamp(timestamp: string) {
  return timestamp.replace(/[:.]/g, "-");
}
