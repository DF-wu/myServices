import { File, Paths } from "expo-file-system";

import { isWeb } from "@/lib/platform";

const WORKSPACE_FILE = "df-voice-app-workspace.json";
const WEB_WORKSPACE_KEY = "df-voice-app.workspace.v1";

export async function getWorkspaceJson<T>(): Promise<T | null> {
  try {
    const raw = isWeb() ? webStorage()?.getItem(WEB_WORKSPACE_KEY) : await readWorkspaceFile();
    if (!raw) {
      return null;
    }
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export async function setWorkspaceJson<T>(value: T): Promise<void> {
  const raw = JSON.stringify(value);
  if (isWeb()) {
    webStorage()?.setItem(WEB_WORKSPACE_KEY, raw);
    return;
  }
  workspaceFile().write(raw);
}

function webStorage() {
  if (typeof globalThis.localStorage === "undefined") {
    return null;
  }
  return globalThis.localStorage;
}

async function readWorkspaceFile() {
  const file = workspaceFile();
  if (!file.exists) {
    return null;
  }
  return file.text();
}

function workspaceFile() {
  return new File(Paths.document, WORKSPACE_FILE);
}
