export const runtimeOS = process.env.EXPO_OS ?? "web";

export function isWeb() {
  return runtimeOS === "web";
}

export function isIOS() {
  return runtimeOS === "ios";
}
