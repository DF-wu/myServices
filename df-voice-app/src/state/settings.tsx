import { createContext, type ReactNode, use, useCallback, useEffect, useMemo, useState } from "react";

import { defaultSettings } from "@/data/templates";
import { sanitizeSettings } from "@/lib/settings-portability";
import { getJson, setJson } from "@/lib/storage";
import type { ClientSettings } from "@/types/client";

const SETTINGS_KEY = "df-voice-app.settings.v1";

type SettingsContextValue = {
  settings: ClientSettings;
  loaded: boolean;
  saveSettings: (settings: ClientSettings) => Promise<void>;
  resetSettings: () => Promise<void>;
};

const SettingsContext = createContext<SettingsContextValue | null>(null);

export function SettingsProvider({ children }: { children: ReactNode }) {
  const [settings, setSettings] = useState<ClientSettings>(defaultSettings);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let mounted = true;
    getJson<ClientSettings>(SETTINGS_KEY)
      .then((stored) => {
        if (mounted && stored) {
          setSettings(sanitizeSettings(defaultSettings, stored));
        }
      })
      .finally(() => {
        if (mounted) {
          setLoaded(true);
        }
      });
    return () => {
      mounted = false;
    };
  }, []);

  const saveSettings = useCallback(async (next: ClientSettings) => {
    const sanitized = sanitizeSettings(defaultSettings, next);
    setSettings(sanitized);
    await setJson(SETTINGS_KEY, sanitized);
  }, []);

  const resetSettings = useCallback(async () => {
    setSettings(defaultSettings);
    await setJson(SETTINGS_KEY, defaultSettings);
  }, []);

  const value = useMemo(
    () => ({ settings, loaded, saveSettings, resetSettings }),
    [loaded, resetSettings, saveSettings, settings],
  );

  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}

export function useSettings() {
  const context = use(SettingsContext);
  if (!context) {
    throw new Error("useSettings must be used inside SettingsProvider");
  }
  return context;
}
