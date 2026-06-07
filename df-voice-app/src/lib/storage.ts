import * as SecureStore from "expo-secure-store";

import { isWeb } from "@/lib/platform";

const memoryStore = new Map<string, string>();

function webStorage() {
  if (!isWeb() || typeof globalThis.localStorage === "undefined") {
    return null;
  }
  return globalThis.localStorage;
}

export async function getString(key: string): Promise<string | null> {
  const storage = webStorage();
  if (storage) {
    return storage.getItem(key);
  }

  if (await SecureStore.isAvailableAsync()) {
    return SecureStore.getItemAsync(key);
  }

  return memoryStore.get(key) ?? null;
}

export async function setString(key: string, value: string): Promise<void> {
  const storage = webStorage();
  if (storage) {
    storage.setItem(key, value);
    return;
  }

  if (await SecureStore.isAvailableAsync()) {
    await SecureStore.setItemAsync(key, value);
    return;
  }

  memoryStore.set(key, value);
}

export async function getJson<T>(key: string): Promise<T | null> {
  const raw = await getString(key);
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export async function setJson<T>(key: string, value: T): Promise<void> {
  await setString(key, JSON.stringify(value));
}
