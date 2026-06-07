import { Stack } from "expo-router/stack";
import { StatusBar } from "expo-status-bar";

import { SettingsProvider } from "@/state/settings";
import { colors } from "@/theme";

export default function RootLayout() {
  return (
    <SettingsProvider>
      <StatusBar style="dark" />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: colors.canvas },
          headerShadowVisible: false,
          headerTintColor: colors.ink,
          headerTitleStyle: {
            fontWeight: "800",
            fontSize: 18,
          },
          contentStyle: { backgroundColor: colors.canvas },
        }}
      >
        <Stack.Screen name="index" options={{ title: "DF Voice App" }} />
      </Stack>
    </SettingsProvider>
  );
}
