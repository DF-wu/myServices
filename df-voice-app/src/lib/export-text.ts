import { Share } from "react-native";

import { isWeb } from "@/lib/platform";
import type { ChatMessage } from "@/types/client";

export type TextExport = {
  filename: string;
  mimeType: "application/json" | "text/markdown" | "text/plain";
  text: string;
  title: string;
};

export async function exportTextFile(file: TextExport) {
  if (isWeb()) {
    downloadOnWeb(file);
    return;
  }
  await Share.share({
    title: file.title,
    message: file.text,
  });
}

export function transcriptMarkdownExport(transcript: string, rawResult: string): TextExport {
  const timestamp = new Date().toISOString();
  return {
    filename: `df-voice-transcript-${safeTimestamp(timestamp)}.md`,
    mimeType: "text/markdown",
    title: "DF Voice transcript",
    text: [
      "# DF Voice Transcript",
      "",
      `Exported: ${timestamp}`,
      "",
      "## Transcript",
      "",
      transcript.trim(),
      ...(rawResult.trim() ? ["", "## Raw ASR Response", "", "```text", rawResult.trim(), "```"] : []),
      "",
    ].join("\n"),
  };
}

export function conversationMarkdownExport(messages: ChatMessage[]): TextExport {
  const timestamp = new Date().toISOString();
  return {
    filename: `df-voice-conversation-${safeTimestamp(timestamp)}.md`,
    mimeType: "text/markdown",
    title: "DF Voice conversation",
    text: [
      "# DF Voice Conversation",
      "",
      `Exported: ${timestamp}`,
      "",
      ...messages.flatMap((message) => [
        `## ${message.role === "assistant" ? "Assistant" : message.role === "system" ? "System" : "User"}`,
        "",
        message.content.trim(),
        "",
      ]),
    ].join("\n"),
  };
}

function downloadOnWeb(file: TextExport) {
  if (typeof document === "undefined" || typeof URL === "undefined" || typeof Blob === "undefined") {
    throw new Error("File downloads are not available in this web runtime.");
  }
  const blob = new Blob([file.text], { type: `${file.mimeType};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = file.filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

function safeTimestamp(timestamp: string) {
  return timestamp.replace(/[:.]/g, "-");
}
