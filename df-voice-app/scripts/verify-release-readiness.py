#!/usr/bin/env python3
"""Audit the release-readiness contract for DF Voice App.

This check is intentionally static. Browser, mock-provider, build, and Android
runtime behavior are covered by the dedicated verification scripts.
"""

from __future__ import annotations

import json
import pathlib
import re
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
PARENT = ROOT.parent
WORKFLOW = PARENT / ".github" / "workflows" / "df-voice-app-ci.yml"


@dataclass(frozen=True)
class Check:
    name: str
    run: Callable[[], None]


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def read_json(relative_path: str) -> dict[str, Any]:
    return json.loads(read_text(relative_path))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_file(relative_path: str) -> None:
    path = ROOT / relative_path
    require(path.exists(), f"missing required file: {relative_path}")


def require_contains(source: str, needles: list[str], label: str) -> None:
    missing = [needle for needle in needles if needle not in source]
    require(not missing, f"{label} missing: {', '.join(missing)}")


def check_project_hygiene() -> None:
    for path in [
        ".env.example",
        ".gitignore",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "README.md",
        "SECURITY.md",
        "requirements-dev.txt",
        "test-artifacts/.gitkeep",
    ]:
        require_file(path)

    gitignore = read_text(".gitignore")
    require_contains(
        gitignore,
        [
            "node_modules/",
            ".expo/",
            "dist/",
            "test-artifacts/*",
            "!test-artifacts/.gitkeep",
            ".env*.local",
            "/android",
            "/ios",
        ],
        ".gitignore",
    )
    package = read_json("package.json")
    require(package["name"] == "df-voice-app", "package name must stay scoped")
    require(package["private"] is True, "package must stay private until release publishing is intentional")
    require(package["license"] == "MIT", "package license must be MIT")
    require("playwright==" in read_text("requirements-dev.txt"), "Playwright dev requirement missing")


def check_platform_contracts() -> None:
    app = read_json("app.json")["expo"]
    eas = read_json("eas.json")

    require(app["name"] == "DF Voice App", "app name mismatch")
    require(app["slug"] == "df-voice-app", "app slug mismatch")
    require(app["scheme"] == "df-voice-app", "deep link scheme mismatch")
    require(app["ios"]["bundleIdentifier"] == "app.dfvoice.app", "iOS bundle id mismatch")
    require(app["ios"]["supportsTablet"] is True, "iOS tablet support should remain enabled")
    require("NSMicrophoneUsageDescription" in app["ios"]["infoPlist"], "iOS microphone text missing")
    require(app["android"]["package"] == "app.dfvoice.app", "Android package mismatch")
    require(app["web"]["display"] == "standalone", "web app must be installable")
    require(app["web"]["lang"] == "zh-Hant", "web language must target Traditional Chinese")
    require(app["web"]["output"] == "static", "web export must remain static")
    require("CapsWriter" in app["web"]["description"], "web description must mention CapsWriter")
    require("OpenAI-compatible" in app["web"]["description"], "web description must mention OpenAI compatibility")
    plugins = app["plugins"]
    require("expo-router" in plugins, "expo-router plugin missing")
    require("expo-secure-store" in plugins, "secure settings storage plugin missing")
    require("expo-sharing" in plugins, "native audio sharing plugin missing")
    require("./plugins/with-local-http-android" in plugins, "Android local HTTP plugin missing")
    audio_plugin = next(
        (plugin for plugin in plugins if isinstance(plugin, list) and plugin[0] == "expo-audio"),
        None,
    )
    require(audio_plugin is not None, "expo-audio plugin missing")
    require(audio_plugin[1]["recordAudioAndroid"] is True, "Android audio recording must stay enabled")
    require(audio_plugin[1]["enableBackgroundRecording"] is False, "background recording must stay disabled")
    require(eas["build"]["preview"]["android"]["buildType"] == "apk", "preview build must produce Android APK")
    require(
        eas["build"]["production"]["android"]["buildType"] == "app-bundle",
        "production build must produce Android app bundle",
    )


def check_openai_compatible_client() -> None:
    client = read_text("src/lib/openai-compatible.ts")
    require_contains(
        client,
        [
            "export async function transcribeAudio",
            "\"/audio/transcriptions\"",
            "FormData",
            "appendExtraFormFields",
            "export async function runConversation",
            "\"/chat/completions\"",
            "\"/responses\"",
            "settings.mode === \"responses\"",
            "readConversationStream",
            "extractChatStreamDelta",
            "extractResponseStreamDelta",
            "export async function synthesizeSpeech",
            "\"/audio/speech\"",
            "arrayBuffer",
            "URL.createObjectURL",
            "new File(Paths.cache",
            "export async function probeModels",
            "\"/models\"",
            "requireHttpBaseUrl",
            "requireText",
            "TimeoutError",
            "AbortController",
            "headersFromJson",
            "jsonObjectFromText",
        ],
        "OpenAI-compatible client",
    )


def check_configurable_settings_contract() -> None:
    types = read_text("src/types/client.ts")
    for section, fields in {
        "AsrSettings": [
            "baseUrl",
            "apiKey",
            "model",
            "responseFormat",
            "language",
            "prompt",
            "temperature",
            "timeoutSec",
            "maxUploadMb",
            "extraHeadersJson",
            "extraFormFieldsJson",
        ],
        "ConversationSettings": [
            "baseUrl",
            "apiKey",
            "mode",
            "model",
            "systemPrompt",
            "temperature",
            "topP",
            "frequencyPenalty",
            "presencePenalty",
            "maxOutputTokens",
            "stream",
            "timeoutSec",
            "extraHeadersJson",
            "extraBodyJson",
        ],
        "TtsSettings": [
            "baseUrl",
            "apiKey",
            "model",
            "voice",
            "responseFormat",
            "speed",
            "instructions",
            "timeoutSec",
            "extraHeadersJson",
            "extraBodyJson",
        ],
    }.items():
        require(f"export type {section}" in types, f"{section} missing from client types")
        require_contains(types, [f"{field}:" for field in fields], section)

    shell = read_text("src/components/app-shell.tsx")
    require_contains(
        shell,
        [
            "Field label=\"Base URL\"",
            "Field label=\"API key\"",
            "Field label=\"Model\"",
            "Segmented<AsrResponseFormat>",
            "Field label=\"Language\"",
            "Prompt / vocabulary hint",
            "NumericField label=\"Temperature\"",
            "NumericField label=\"Timeout seconds\"",
            "NumericField label=\"Max upload MB\"",
            "JsonField label=\"Extra headers JSON\"",
            "JsonField label=\"Extra form fields JSON\"",
            "Segmented<ConversationMode>",
            "Field label=\"System prompt\"",
            "NumericField label=\"Top P\"",
            "NumericField label=\"Max output tokens\"",
            "NumericField label=\"Frequency penalty\"",
            "NumericField label=\"Presence penalty\"",
            "SwitchRow label=\"Keep history\"",
            "SwitchRow label=\"Auto speak replies\"",
            "SwitchRow label=\"Streaming responses\"",
            "Copy ${message.role} message",
            "Message copied.",
            "stopAudioPlayback",
            "Stop audio",
            "Save audio",
            "saveTtsAudio",
            "exportAudioFile",
            "TTS audio stopped.",
            "JsonField label=\"Extra body JSON\"",
            "Field label=\"Voice\"",
            "Segmented<SpeechFormat>",
            "Field label=\"Voice instructions\"",
            "onChangeTranscript",
            "Transcript text",
            "Cancel or finish the current request before recording.",
            "Cancel or finish the current request before uploading audio.",
            "Recording could not be started.",
            "Recording could not be stopped.",
            "validatePickedAudioFile",
            "uploadLimitBytes",
            "Selected file is empty.",
            "Selected file is larger than",
            "disabled={requestBusy",
            "function NumericField",
            "function JsonField",
        ],
        "settings UI",
    )


def check_templates_and_persistence() -> None:
    provider_templates = read_text("src/data/templates.ts")
    prompt_templates = read_text("src/data/prompt-templates.ts")
    shell = read_text("src/components/app-shell.tsx")
    portability = read_text("src/lib/settings-portability.ts")
    storage = read_text("src/lib/storage.ts")
    workspace_storage = read_text("src/lib/workspace-storage.ts")

    provider_ids = set(re.findall(r'id: "([^"]+)"', provider_templates))
    prompt_ids = set(re.findall(r'id: "([^"]+)"', prompt_templates))
    require(
        {"capswriter-local", "openai-compatible-cloud", "android-emulator-host", "lm-studio-chat"}
        <= provider_ids,
        f"provider templates incomplete: {sorted(provider_ids)}",
    )
    require(
        {"clean-transcript", "meeting-summary", "action-items", "reply-draft", "english-brief"} <= prompt_ids,
        f"prompt templates incomplete: {sorted(prompt_ids)}",
    )
    require_contains(
        shell,
        [
            "saveCustomProviderTemplate",
            "saveCustomPromptTemplate",
            "customProviderTemplates",
            "customPromptTemplates",
            "getWorkspaceJson",
            "setWorkspaceJson",
            "settingsJsonExport",
            "importSettingsText",
        ],
        "template and workspace UI",
    )
    require_contains(
        portability,
        [
            "REDACTED_SETTING_VALUE",
            "settingsJsonExport",
            "importSettingsText",
            "sanitizeSettings",
            "rangedNumberValue",
            "enumValue",
            "mergeCredentials",
        ],
        "settings portability",
    )
    require("expo-secure-store" in storage, "native settings must use SecureStore when available")
    require("localStorage" in storage, "web settings storage must use localStorage")
    require("Paths.document" in workspace_storage, "native workspace must use an app-private document file")


def check_verification_gates() -> None:
    package = read_json("package.json")
    scripts = package["scripts"]
    for name in [
        "verify:release",
        "verify:static",
        "verify:web:server",
        "verify:web-build",
        "verify:mock:server",
        "verify:android-config",
        "verify:android-build",
        "verify:android-runtime",
        "verify:audit",
        "verify:ci",
    ]:
        require(name in scripts, f"missing package script {name}")
    require("verify:release" in scripts["verify:static"], "verify:static must include release readiness audit")
    require("verify:static" in scripts["verify:ci"], "verify:ci must include static gate")
    require("verify:web:server" in scripts["verify:ci"], "verify:ci must include web smoke")
    require("verify:web-build" in scripts["verify:ci"], "verify:ci must include static web export")
    require("verify:mock:server" in scripts["verify:ci"], "verify:ci must include mock provider integration")
    require("verify:android-config" in scripts["verify:ci"], "verify:ci must include Android config gate")
    require("verify:audit" in scripts["verify:ci"], "verify:ci must include high-severity audit")

    web = read_text("scripts/verify-web.py")
    require_contains(
        web,
        [
            "assert_layout",
            "width\": 1366",
            "width\": 390",
            "web-home.png",
            "web-mobile.png",
            "web-settings-mobile.png",
            "smallButtons",
            "horizontal overflow",
            "console_errors",
            "Provider checks",
            "Prompt templates",
            "Provider template name",
            "Lab provider setup",
        ],
        "web smoke verifier",
    )
    asr_mock = read_text("scripts/verify-asr-mock.py")
    openai_mock = read_text("scripts/verify-openai-mock.py")
    require_contains(
        asr_mock,
        [
            "verify_response_format",
            "\"text\"",
            "\"srt\"",
            "\"vtt\"",
            "verify_transcript_copy",
            "Transcript copied.",
            "verify_transcript_edit",
            "verify_missing_asr_settings",
            "verify_missing_tts_settings",
            "verify_empty_upload",
            "verify_upload_limit",
            "Selected file is larger than 1 MB.",
            "verify_cancel_transcription",
            "verify_timeout_transcription",
            "Stop audio",
            "Save audio",
            "df-voice-speech-",
            "TTS audio stopped.",
            "to_be_disabled",
        ],
        "ASR mock verifier",
    )
    require_contains(
        openai_mock,
        [
            "\"chat_completions\"",
            "\"responses\"",
            "stream=False",
            "run_diagnostics",
            "run_cancel_case",
            "run_timeout_case",
            "run_missing_conversation_settings_case",
            "Copy assistant message",
            "verify_export=True",
            "to_be_disabled",
        ],
        "conversation mock verifier",
    )


def check_docs_and_ci() -> None:
    readme = read_text("README.md")
    architecture = read_text("docs/ARCHITECTURE.md")
    compatibility = read_text("docs/PROVIDER_COMPATIBILITY.md")
    contributing = read_text("CONTRIBUTING.md")
    security = read_text("SECURITY.md")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    require_contains(
        readme,
        [
            "web, Android, and optional iOS",
            "CapsWriter ASR",
            "CAPSWRITER_HTTP_API_ENABLE=true",
            "CAPSWRITER_HTTP_API_MAX_UPLOAD_MB",
            "6016",
            "6017",
            "Chat Completions",
            "Responses",
            "TTS",
            "Provider Settings",
            "verify:release",
            "verify:ci",
            "verify:android-runtime",
        ],
        "README",
    )
    require_contains(
        architecture,
        [
            "Runtime Layers",
            "Data Flow",
            "maxUploadMb",
            "Persistence",
            "Native Strategy",
            "Verification",
        ],
        "architecture docs",
    )
    require_contains(
        compatibility,
        [
            "POST /v1/audio/transcriptions",
            "CapsWriter HTTP API",
            "CAPSWRITER_HTTP_API_MAX_UPLOAD_MB",
            "GET /v1/models",
            "POST /v1/chat/completions",
            "POST /v1/responses",
            "POST /v1/audio/speech",
        ],
        "provider compatibility docs",
    )
    require_contains(contributing, ["focused commits", "verify:static", "verify:mock:server"], "contributing docs")
    require_contains(security, ["expo-secure-store", "localStorage", "EXPO_PUBLIC_*"], "security docs")
    require_contains(
        workflow,
        [
            "DF Voice App CI",
            "df-voice-app/**",
            "actions/setup-node@v4",
            "actions/setup-python@v5",
            "python -m playwright install --with-deps chromium",
            "npm run verify:ci",
        ],
        "GitHub Actions workflow",
    )


CHECKS = [
    Check("project hygiene", check_project_hygiene),
    Check("platform contracts", check_platform_contracts),
    Check("OpenAI-compatible client", check_openai_compatible_client),
    Check("configurable settings", check_configurable_settings_contract),
    Check("templates and persistence", check_templates_and_persistence),
    Check("verification gates", check_verification_gates),
    Check("docs and CI", check_docs_and_ci),
]


def main() -> int:
    failures: list[str] = []
    for check in CHECKS:
        try:
            check.run()
        except (AssertionError, KeyError, OSError, json.JSONDecodeError) as error:
            failures.append(f"{check.name}: {error}")
            print(f"FAIL {check.name}: {error}")
        else:
            print(f"ok {check.name}")

    if failures:
        print("\nrelease readiness audit failed")
        return 1

    print(f"release readiness audit passed ({len(CHECKS)} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
