# Security

## Supported Scope

Security fixes should target the current `main` or `master` branch of DF Voice App.

## Reporting

Do not file public issues for secrets, credential exposure, or exploitable request-handling bugs. Report privately to the repository owner or maintainer.

## Credential Handling

- API keys entered in the app are stored with `expo-secure-store` on native platforms when available.
- Web builds use browser `localStorage`; avoid storing production keys on shared browsers.
- `.env.example` only contains public Expo defaults. Never put provider API keys in `EXPO_PUBLIC_*` variables because those values are bundled into web and native clients.
- Settings exports redact API keys and extra headers. Importing a redacted export preserves credentials already stored on the current device.

## Network Model

The Android config enables cleartext HTTP so local CapsWriter, LAN, `localhost`, and `10.0.2.2` provider endpoints work. Use HTTPS for remote or production providers.
