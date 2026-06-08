import * as Clipboard from "expo-clipboard";
import * as DocumentPicker from "expo-document-picker";
import * as Haptics from "expo-haptics";
import {
  createAudioPlayer,
  RecordingPresets,
  requestRecordingPermissionsAsync,
  setAudioModeAsync,
  useAudioRecorder,
  useAudioRecorderState,
  type AudioPlayer,
} from "expo-audio";
import { File } from "expo-file-system";
import {
  Check,
  Copy,
  Download,
  FileAudio,
  MessageSquare,
  Mic,
  Plus,
  RotateCcw,
  Save,
  Send,
  Settings2,
  Sparkles,
  Square,
  Trash2,
  Upload,
  Volume2,
  Wifi,
} from "lucide-react-native";
import { useEffect, useMemo, useRef, useState, type ComponentType } from "react";
import {
  ActivityIndicator,
  Modal,
  Pressable,
  ScrollView,
  Switch,
  Text,
  TextInput,
  View,
  useWindowDimensions,
} from "react-native";

import { promptTemplates } from "@/data/prompt-templates";
import { defaultSettings, templates } from "@/data/templates";
import { conversationMarkdownExport, exportTextFile, transcriptMarkdownExport } from "@/lib/export-text";
import { documentAssetToAudio, probeModels, recordingUriToAudio, runConversation, synthesizeSpeech, transcribeAudio } from "@/lib/openai-compatible";
import { isIOS } from "@/lib/platform";
import { REDACTED_SETTING_VALUE, importSettingsText, redactedSettings, sanitizeSettings, settingsJsonExport } from "@/lib/settings-portability";
import { getWorkspaceJson, setWorkspaceJson } from "@/lib/workspace-storage";
import { useSettings } from "@/state/settings";
import { colors, radii, spacing } from "@/theme";
import type {
  ApiProbe,
  AsrResponseFormat,
  AsrSettings,
  ChatMessage,
  ClientSettings,
  ClientTemplate,
  ConversationMode,
  ConversationSettings,
  PromptTemplate,
  SpeechFormat,
  TtsSettings,
} from "@/types/client";

type TabId = "capture" | "chat" | "settings" | "templates";
type BusyState = "record" | "transcribe" | "chat" | "tts" | "probe" | null;
type Icon = ComponentType<{ color?: string; size?: number; strokeWidth?: number }>;
type ProviderKey = "asr" | "conversation" | "tts";
type ProviderDiagnostic = ApiProbe & { checkedAt: number };
type PendingConfirmation = {
  body: string;
  confirmLabel: string;
  onConfirm: () => void;
  title: string;
};
type WorkspaceSnapshot = {
  chatDraft: string;
  customProviderTemplates: ClientTemplate[];
  customPromptTemplates: PromptTemplate[];
  messages: ChatMessage[];
  rawResult: string;
  transcript: string;
};
type ProviderTemplateDraft = {
  description: string;
  name: string;
  tags: string;
};
type PromptTemplateDraft = {
  category: string;
  description: string;
  name: string;
  prompt: string;
  tags: string;
};

const tabs: Array<{ id: TabId; label: string; icon: Icon }> = [
  { id: "capture", label: "語音", icon: Mic },
  { id: "chat", label: "對話", icon: MessageSquare },
  { id: "settings", label: "設定", icon: Settings2 },
  { id: "templates", label: "範本", icon: Sparkles },
];
const providerKeys: ProviderKey[] = ["asr", "conversation", "tts"];
const emptyProviderTemplateDraft: ProviderTemplateDraft = {
  description: "",
  name: "",
  tags: "",
};
const emptyPromptTemplateDraft: PromptTemplateDraft = {
  category: "Custom",
  description: "",
  name: "",
  prompt: "",
  tags: "",
};
const emptyWorkspaceSnapshot: WorkspaceSnapshot = {
  chatDraft: "",
  customProviderTemplates: [],
  customPromptTemplates: [],
  messages: [],
  rawResult: "",
  transcript: "",
};
const maxUploadBytes = 512 * 1024 * 1024;
const maxUploadLabel = "512 MB";

function id() {
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export function AppShell() {
  const { loaded, resetSettings, saveSettings, settings } = useSettings();
  const recorder = useAudioRecorder({ ...RecordingPresets.HIGH_QUALITY, isMeteringEnabled: true });
  const recorderState = useAudioRecorderState(recorder, 250);
  const activeRequestRef = useRef<AbortController | null>(null);
  const playerRef = useRef<AudioPlayer | null>(null);
  const ttsObjectUrlRef = useRef<string | null>(null);
  const [activeTab, setActiveTab] = useState<TabId>("capture");
  const [busy, setBusy] = useState<BusyState>(null);
  const [notice, setNotice] = useState<string>("");
  const [transcript, setTranscript] = useState("");
  const [rawResult, setRawResult] = useState("");
  const [chatDraft, setChatDraft] = useState("");
  const [customProviderTemplates, setCustomProviderTemplates] = useState<ClientTemplate[]>([]);
  const [customPromptTemplates, setCustomPromptTemplates] = useState<PromptTemplate[]>([]);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [pendingConfirmation, setPendingConfirmation] = useState<PendingConfirmation | null>(null);
  const [workspaceLoaded, setWorkspaceLoaded] = useState(false);
  const [providerDiagnostics, setProviderDiagnostics] = useState<
    Partial<Record<ProviderKey, ProviderDiagnostic>>
  >({});
  const { width } = useWindowDimensions();
  const wide = width >= 900;

  useEffect(() => {
    return () => {
      activeRequestRef.current?.abort();
      activeRequestRef.current = null;
      replaceAudioPlayer(null);
    };
  }, []);

  useEffect(() => {
    let mounted = true;
    getWorkspaceJson<Partial<WorkspaceSnapshot>>()
      .then((snapshot) => {
        if (!mounted || !snapshot) {
          return;
        }
        const next = normalizeWorkspaceSnapshot(snapshot);
        setTranscript(next.transcript);
        setRawResult(next.rawResult);
        setChatDraft(next.chatDraft);
        setCustomProviderTemplates(next.customProviderTemplates);
        setCustomPromptTemplates(next.customPromptTemplates);
        setMessages(next.messages);
      })
      .finally(() => {
        if (mounted) {
          setWorkspaceLoaded(true);
        }
      });
    return () => {
      mounted = false;
    };
  }, []);

  useEffect(() => {
    if (!workspaceLoaded) {
      return undefined;
    }
    const handle = setTimeout(() => {
      void setWorkspaceJson({
        chatDraft,
        customProviderTemplates,
        customPromptTemplates,
        messages: messages.slice(-80),
        rawResult,
        transcript,
      }).catch(() => undefined);
    }, 250);
    return () => clearTimeout(handle);
  }, [chatDraft, customProviderTemplates, customPromptTemplates, messages, rawResult, transcript, workspaceLoaded]);

  const statusLine = useMemo(() => {
    const base = trimUrl(settings.asr.baseUrl);
    const format = settings.asr.responseFormat;
    return `${base} · ${settings.asr.model} · ${format}`;
  }, [settings.asr.baseUrl, settings.asr.model, settings.asr.responseFormat]);

  async function haptic() {
    if (isIOS()) {
      await Haptics.selectionAsync().catch(() => undefined);
    }
  }

  async function updateSettings(next: ClientSettings) {
    await saveSettings(next);
  }

  function confirmDestructiveAction({
    body,
    confirmLabel,
    onConfirm,
    title,
  }: {
    body: string;
    confirmLabel: string;
    onConfirm: () => void;
    title: string;
  }) {
    setPendingConfirmation({ body, confirmLabel, onConfirm, title });
  }

  function dismissConfirmation() {
    setPendingConfirmation(null);
  }

  function confirmPendingAction() {
    const action = pendingConfirmation?.onConfirm;
    setPendingConfirmation(null);
    action?.();
  }

  function beginRequest() {
    activeRequestRef.current?.abort();
    const controller = new AbortController();
    activeRequestRef.current = controller;
    return controller;
  }

  function finishRequest(controller: AbortController) {
    if (activeRequestRef.current === controller) {
      activeRequestRef.current = null;
      setBusy(null);
    }
  }

  function cancelRequest() {
    activeRequestRef.current?.abort();
    activeRequestRef.current = null;
    setBusy(null);
    setNotice("Request cancelled.");
  }

  function requestWasAborted(error: unknown, controller: AbortController) {
    return controller.signal.aborted || (error instanceof Error && error.name === "AbortError");
  }

  function replaceAudioPlayer(nextPlayer: AudioPlayer | null, nextUri?: string) {
    playerRef.current?.remove();
    playerRef.current = nextPlayer;
    releaseTtsObjectUrl(ttsObjectUrlRef.current);
    ttsObjectUrlRef.current = nextUri && isObjectUrl(nextUri) ? nextUri : null;
  }

  function releaseTtsObjectUrl(uri: string | null | undefined) {
    if (uri && isObjectUrl(uri) && typeof URL !== "undefined" && typeof URL.revokeObjectURL === "function") {
      URL.revokeObjectURL(uri);
    }
  }

  async function startRecording() {
    if (busy && busy !== "record") {
      setNotice("Cancel or finish the current request before recording.");
      return;
    }
    setNotice("");
    setBusy("record");
    let started = false;
    try {
      const permission = await requestRecordingPermissionsAsync();
      if (!permission.granted) {
        setNotice("Microphone permission was not granted.");
        return;
      }

      await setAudioModeAsync({ allowsRecording: true, playsInSilentMode: true });
      await recorder.prepareToRecordAsync();
      recorder.record();
      started = true;
      await haptic();
    } catch (error) {
      await setAudioModeAsync({ allowsRecording: false, playsInSilentMode: true }).catch(() => undefined);
      setNotice(error instanceof Error ? error.message : "Recording could not be started.");
    } finally {
      if (!started) {
        setBusy(null);
      }
    }
  }

  async function stopRecording() {
    if (!recorderState.isRecording) {
      setNotice("No active recording to stop.");
      return;
    }
    setBusy("transcribe");
    try {
      await recorder.stop();
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Recording could not be stopped.");
      setBusy(null);
      return;
    } finally {
      await setAudioModeAsync({ allowsRecording: false, playsInSilentMode: true }).catch(() => undefined);
    }
    const uri = recorderState.url ?? recorder.uri;
    if (uri) {
      await transcribe(recordingUriToAudio(uri));
      return;
    }
    setBusy(null);
    setNotice("Recording stopped, but no audio file URI was returned.");
  }

  async function pickAudio() {
    if (busy) {
      setNotice("Cancel or finish the current request before uploading audio.");
      return;
    }
    setNotice("");
    const result = await DocumentPicker.getDocumentAsync({
      type: ["audio/*", "video/*"],
      copyToCacheDirectory: true,
      multiple: false,
      base64: false,
    });
    if (result.canceled || !result.assets?.[0]) {
      return;
    }
    const validationError = validatePickedAudioFile(result.assets[0]);
    if (validationError) {
      setNotice(validationError);
      return;
    }
    setBusy("transcribe");
    await transcribe(documentAssetToAudio(result.assets[0]));
  }

  async function transcribe(audio: Parameters<typeof transcribeAudio>[1]) {
    const controller = beginRequest();
    try {
      const result = await transcribeAudio(settings.asr, audio, { signal: controller.signal });
      if (controller.signal.aborted || activeRequestRef.current !== controller) {
        return;
      }
      setTranscript(result.text);
      setRawResult(typeof result.raw === "string" ? result.raw : JSON.stringify(result.raw, null, 2));
      setNotice(`Transcribed ${audio.name}.`);
      setActiveTab("capture");
    } catch (error) {
      if (requestWasAborted(error, controller)) {
        return;
      }
      setNotice(error instanceof Error ? error.message : "Transcription failed.");
    } finally {
      finishRequest(controller);
    }
  }

  async function sendChat(sourceText = chatDraft) {
    const content = sourceText.trim();
    if (!content) {
      setNotice("No text to send.");
      return;
    }

    const userMessage: ChatMessage = { id: id(), role: "user", content, createdAt: Date.now() };
    const inputMessages = settings.keepConversationHistory ? [...messages, userMessage] : [userMessage];
    const assistantId = id();
    const pendingAssistant: ChatMessage = {
      id: assistantId,
      role: "assistant",
      content: "",
      createdAt: Date.now(),
    };
    setMessages((current) =>
      settings.keepConversationHistory
        ? [...current, userMessage, pendingAssistant]
        : [userMessage, pendingAssistant],
    );
    setChatDraft("");
    setBusy("chat");
    setActiveTab("chat");

    const controller = beginRequest();
    try {
      let streamed = "";
      const answer = await runConversation(settings.conversation, inputMessages, {
        signal: controller.signal,
        onDelta: (delta) => {
          if (controller.signal.aborted || activeRequestRef.current !== controller) {
            return;
          }
          streamed += delta;
          setMessages((current) =>
            current.map((message) =>
              message.id === assistantId
                ? { ...message, content: `${message.content}${delta}` }
                : message,
            ),
          );
        },
      });
      if (controller.signal.aborted || activeRequestRef.current !== controller) {
        return;
      }
      if (!streamed || streamed !== answer) {
        setMessages((current) =>
          current.map((message) =>
            message.id === assistantId ? { ...message, content: answer } : message,
          ),
        );
      }
      setNotice("Conversation response received.");
      if (settings.autoSpeak) {
        void speak(answer);
      }
    } catch (error) {
      if (requestWasAborted(error, controller)) {
        setMessages((current) =>
          current.map((message) =>
            message.id === assistantId
              ? {
                  ...message,
                  content: message.content
                    ? `${message.content}\n\nRequest cancelled.`
                    : "Request cancelled.",
                }
              : message,
          ),
        );
        return;
      }
      setMessages((current) =>
        current.map((message) =>
          message.id === assistantId
            ? {
                ...message,
                content:
                  error instanceof Error
                    ? `Request failed: ${error.message}`
                    : "Conversation request failed.",
              }
            : message,
        ),
      );
      setNotice(error instanceof Error ? error.message : "Conversation request failed.");
    } finally {
      finishRequest(controller);
    }
  }

  async function speak(text: string) {
    const input = text.trim();
    if (!input) {
      setNotice("No text to speak.");
      return;
    }
    setBusy("tts");
    const controller = beginRequest();
    try {
      const uri = await synthesizeSpeech(settings.tts, input, { signal: controller.signal });
      if (controller.signal.aborted || activeRequestRef.current !== controller) {
        releaseTtsObjectUrl(uri);
        return;
      }
      const player = createAudioPlayer(uri, { updateInterval: 250 });
      replaceAudioPlayer(player, uri);
      player.play();
      setNotice("TTS audio is playing.");
    } catch (error) {
      if (requestWasAborted(error, controller)) {
        return;
      }
      setNotice(error instanceof Error ? error.message : "TTS request failed.");
    } finally {
      finishRequest(controller);
    }
  }

  async function exportTranscript() {
    if (!transcript.trim()) {
      setNotice("No transcript to export.");
      return;
    }
    try {
      await exportTextFile(transcriptMarkdownExport(transcript, rawResult));
      setNotice("Transcript export started.");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Transcript export failed.");
    }
  }

  function clearTranscript() {
    confirmDestructiveAction({
      title: "Clear transcript?",
      body: "This removes the current transcript and raw ASR response from the workspace.",
      confirmLabel: "Clear",
      onConfirm: clearTranscriptNow,
    });
  }

  function clearTranscriptNow() {
    setTranscript("");
    setRawResult("");
    setNotice("Transcript cleared.");
  }

  async function clearWorkspace() {
    confirmDestructiveAction({
      title: "Clear workspace?",
      body: "This removes the transcript, raw ASR response, draft, conversation, and custom templates saved on this device.",
      confirmLabel: "Clear workspace",
      onConfirm: () => void clearWorkspaceNow(),
    });
  }

  async function clearWorkspaceNow() {
    try {
      await setWorkspaceJson(emptyWorkspaceSnapshot);
      setTranscript("");
      setRawResult("");
      setChatDraft("");
      setCustomProviderTemplates([]);
      setCustomPromptTemplates([]);
      setMessages([]);
      setNotice("Workspace cleared.");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Workspace clear failed.");
    }
  }

  function clearConversation() {
    confirmDestructiveAction({
      title: "Clear conversation?",
      body: "This removes all messages in the current conversation.",
      confirmLabel: "Clear",
      onConfirm: () => {
        setMessages([]);
        setNotice("Conversation cleared.");
      },
    });
  }

  function resetSettingsWithConfirmation() {
    confirmDestructiveAction({
      title: "Reset settings?",
      body: "This restores all provider settings to the app defaults. Local workspace data is not cleared.",
      confirmLabel: "Reset defaults",
      onConfirm: () => void resetSettings(),
    });
  }

  async function exportConversation() {
    if (!messages.length) {
      setNotice("No conversation to export.");
      return;
    }
    try {
      await exportTextFile(conversationMarkdownExport(messages));
      setNotice("Conversation export started.");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Conversation export failed.");
    }
  }

  async function exportSettings() {
    try {
      await exportTextFile(settingsJsonExport(settings));
      setNotice("Settings export started. Credentials and extra headers were redacted.");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Settings export failed.");
    }
  }

  async function importSettings() {
    setNotice("");
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: ["application/json", "text/json", "text/plain"],
        copyToCacheDirectory: true,
        multiple: false,
        base64: false,
      });
      if (result.canceled || !result.assets?.[0]) {
        return;
      }
      const text = await readPickedDocumentText(result.assets[0]);
      const next = importSettingsText(settings, text);
      await saveSettings(next);
      setNotice("Settings imported. Redacted credentials on this device were preserved.");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Settings import failed.");
    }
  }

  async function fetchProviderProbe(provider: ProviderKey, signal?: AbortSignal) {
    const config = providerConfig(settings, provider);
    const result = await probeModels(config.baseUrl, config.apiKey, config.extraHeadersJson, {
      label: config.label,
      signal,
      timeoutSec: config.timeoutSec,
    });
    return { ...result, checkedAt: Date.now() };
  }

  async function probeProvider(provider: ProviderKey) {
    setBusy("probe");
    const label = providerConfig(settings, provider).label;
    const controller = beginRequest();
    try {
      const result = await fetchProviderProbe(provider, controller.signal);
      if (controller.signal.aborted || activeRequestRef.current !== controller) {
        return;
      }
      setProviderDiagnostics((current) => ({ ...current, [provider]: result }));
      setNotice(result.ok ? `${label} provider is reachable.` : `${label}: ${result.message}`);
    } catch (error) {
      if (requestWasAborted(error, controller)) {
        return;
      }
      setNotice(error instanceof Error ? error.message : `${label} provider check failed.`);
    } finally {
      finishRequest(controller);
    }
  }

  async function probeAllProviders() {
    setBusy("probe");
    const controller = beginRequest();
    try {
      const results = await Promise.all(
        providerKeys.map(async (provider) => {
          const config = providerConfig(settings, provider);
          const result = await probeModels(config.baseUrl, config.apiKey, config.extraHeadersJson, {
            label: config.label,
            signal: controller.signal,
            timeoutSec: config.timeoutSec,
          });
          return [provider, { ...result, checkedAt: Date.now() }] as const;
        }),
      );
      if (controller.signal.aborted || activeRequestRef.current !== controller) {
        return;
      }
      setProviderDiagnostics(Object.fromEntries(results));
      const failed = results.filter(([, result]) => !result.ok);
      setNotice(
        failed.length
          ? `${failed.length} provider check${failed.length === 1 ? "" : "s"} failed.`
          : "All provider model endpoints are reachable.",
      );
    } catch (error) {
      if (requestWasAborted(error, controller)) {
        return;
      }
      setNotice(error instanceof Error ? error.message : "Provider checks failed.");
    } finally {
      finishRequest(controller);
    }
  }

  async function useProviderModel(provider: ProviderKey, modelId: string) {
    const label = providerConfig(settings, provider).label;
    const next =
      provider === "asr"
        ? { ...settings, asr: { ...settings.asr, model: modelId } }
        : provider === "tts"
          ? { ...settings, tts: { ...settings.tts, model: modelId } }
          : { ...settings, conversation: { ...settings.conversation, model: modelId } };
    await saveSettings(next);
    setNotice(`${label} model set to ${modelId}.`);
  }

  async function applyTemplate(templateId: string) {
    const template = [...customProviderTemplates, ...templates].find((item) => item.id === templateId);
    if (!template) {
      return;
    }
    await saveSettings(sanitizeSettings(settings, template.settings));
    setNotice(`Applied template: ${template.name}`);
  }

  function saveCustomProviderTemplate(draft: ProviderTemplateDraft) {
    const name = draft.name.trim();
    if (!name) {
      setNotice("Custom provider templates need a name.");
      return false;
    }
    const template: ClientTemplate = {
      id: `custom-provider-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      description: draft.description.trim() || "User-defined provider setup.",
      name,
      settings: providerTemplateSettings(settings),
      tags: draft.tags
        .split(",")
        .map((tag) => tag.trim())
        .filter(Boolean)
        .slice(0, 8),
    };
    setCustomProviderTemplates((current) => [template, ...current].slice(0, 30));
    setNotice(`Saved custom provider template: ${template.name}`);
    return true;
  }

  function deleteCustomProviderTemplate(templateId: string) {
    const template = customProviderTemplates.find((item) => item.id === templateId);
    confirmDestructiveAction({
      title: "Delete provider template?",
      body: `This removes ${template?.name ?? "this custom provider template"} from this device.`,
      confirmLabel: "Delete",
      onConfirm: () => deleteCustomProviderTemplateNow(templateId),
    });
  }

  function deleteCustomProviderTemplateNow(templateId: string) {
    setCustomProviderTemplates((current) => current.filter((template) => template.id !== templateId));
    setNotice("Custom provider template deleted.");
  }

  function loadPromptTemplate(template: PromptTemplate) {
    setChatDraft(template.prompt);
    setActiveTab("chat");
    setNotice(`Loaded prompt template: ${template.name}`);
  }

  async function runPromptTemplate(template: PromptTemplate) {
    if (!transcript.trim()) {
      setNotice("No transcript available for this prompt template.");
      return;
    }
    await sendChat(promptWithTranscript(template.prompt, transcript));
  }

  function saveCustomPromptTemplate(draft: PromptTemplateDraft) {
    const name = draft.name.trim();
    const prompt = draft.prompt.trim();
    if (!name || !prompt) {
      setNotice("Custom prompt templates need a name and prompt.");
      return false;
    }
    const template: PromptTemplate = {
      id: `custom-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      category: draft.category.trim() || "Custom",
      description: draft.description.trim() || "User-defined prompt workflow.",
      name,
      prompt,
      tags: draft.tags
        .split(",")
        .map((tag) => tag.trim())
        .filter(Boolean)
        .slice(0, 8),
    };
    setCustomPromptTemplates((current) => [template, ...current].slice(0, 40));
    setNotice(`Saved custom prompt template: ${template.name}`);
    return true;
  }

  function deleteCustomPromptTemplate(templateId: string) {
    const template = customPromptTemplates.find((item) => item.id === templateId);
    confirmDestructiveAction({
      title: "Delete prompt template?",
      body: `This removes ${template?.name ?? "this custom prompt template"} from this device.`,
      confirmLabel: "Delete",
      onConfirm: () => deleteCustomPromptTemplateNow(templateId),
    });
  }

  function deleteCustomPromptTemplateNow(templateId: string) {
    setCustomPromptTemplates((current) => current.filter((template) => template.id !== templateId));
    setNotice("Custom prompt template deleted.");
  }

  if (!loaded || !workspaceLoaded) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center", gap: spacing.md }}>
        <ActivityIndicator color={colors.green} />
        <Text style={{ color: colors.muted }}>Loading workspace</Text>
      </View>
    );
  }

  return (
    <>
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        style={{ flex: 1, backgroundColor: colors.canvas }}
        contentContainerStyle={{
          padding: width < 520 ? spacing.md : spacing.xl,
          gap: spacing.lg,
          maxWidth: 1160,
          width: "100%",
          alignSelf: "center",
        }}
      >
      <View
        style={{
          borderBottomWidth: 1,
          borderColor: colors.line,
          paddingBottom: spacing.lg,
          gap: spacing.md,
        }}
      >
        <View style={{ gap: spacing.xs }}>
          <Text style={{ color: colors.ink, fontSize: width < 520 ? 28 : 38, fontWeight: "900" }}>
            DF Voice App
          </Text>
          <Text selectable style={{ color: colors.muted, fontSize: 15, lineHeight: 22 }}>
            {statusLine}
          </Text>
        </View>

        <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
          {tabs.map((tab) => (
            <TabButton
              key={tab.id}
              active={activeTab === tab.id}
              icon={tab.icon}
              label={tab.label}
              onPress={() => setActiveTab(tab.id)}
            />
          ))}
          {busy && busy !== "record" ? (
            <CommandButton
              label="Cancel request"
              tone="danger"
              icon={Square}
              onPress={cancelRequest}
            />
          ) : null}
        </View>
      </View>

      <WorkflowOverview
        activeTab={activeTab}
        diagnostics={providerDiagnostics}
        messageCount={messages.length}
        onSelectTab={setActiveTab}
        settings={settings}
        transcriptLength={transcript.length}
        wide={wide}
      />

      {notice ? <Notice text={notice} onClear={() => setNotice("")} /> : null}

      {activeTab === "capture" ? (
        <CaptureView
          busy={busy}
          recorderState={{
            isRecording: recorderState.isRecording,
            durationMillis: recorderState.durationMillis,
            metering: recorderState.metering,
          }}
          transcript={transcript}
          rawResult={rawResult}
          onClearTranscript={clearTranscript}
          onCopy={async () => {
            await Clipboard.setStringAsync(transcript);
            setNotice("Transcript copied.");
          }}
          onExport={exportTranscript}
          onPickAudio={pickAudio}
          onSendToChat={() => sendChat(transcript)}
          onSpeak={() => speak(transcript)}
          onStartRecording={startRecording}
          onStopRecording={stopRecording}
        />
      ) : null}

      {activeTab === "chat" ? (
        <ChatView
          busy={busy}
          draft={chatDraft}
          messages={messages}
          transcript={transcript}
          onChangeDraft={setChatDraft}
          onClear={clearConversation}
          onExport={exportConversation}
          onSend={() => sendChat()}
          onSendTranscript={() => sendChat(transcript)}
          onSpeak={speak}
        />
      ) : null}

      {activeTab === "settings" ? (
        <SettingsView
          busy={busy}
          diagnostics={providerDiagnostics}
          settings={settings}
          wide={wide}
          onProbeAll={probeAllProviders}
          onProbeProvider={probeProvider}
          onClearWorkspace={clearWorkspace}
          onExportSettings={exportSettings}
          onImportSettings={importSettings}
          onReset={resetSettingsWithConfirmation}
          onUpdate={updateSettings}
          onUseModel={useProviderModel}
        />
      ) : null}

      {activeTab === "templates" ? (
        <TemplatesView
          busy={busy}
          customProviderTemplates={customProviderTemplates}
          customPromptTemplates={customPromptTemplates}
          current={settings}
          transcript={transcript}
          onApply={applyTemplate}
          onDeleteProvider={deleteCustomProviderTemplate}
          onDeletePrompt={deleteCustomPromptTemplate}
          onLoadPrompt={loadPromptTemplate}
          onRunPrompt={runPromptTemplate}
          onSaveProvider={saveCustomProviderTemplate}
          onSavePrompt={saveCustomPromptTemplate}
        />
      ) : null}
      </ScrollView>
      <ConfirmationDialog
        confirmation={pendingConfirmation}
        onCancel={dismissConfirmation}
        onConfirm={confirmPendingAction}
      />
    </>
  );
}

async function readPickedDocumentText(asset: {
  file?: Blob;
  uri: string;
}) {
  if (asset.file && typeof asset.file.text === "function") {
    return asset.file.text();
  }
  return new File(asset.uri).text();
}

function validatePickedAudioFile(asset: { file?: Blob; name?: string; size?: number }) {
  const size = typeof asset.size === "number" ? asset.size : asset.file?.size;
  if (size === undefined) {
    return null;
  }
  if (size <= 0) {
    return "Selected file is empty.";
  }
  if (size > maxUploadBytes) {
    return `Selected file is larger than ${maxUploadLabel}.`;
  }
  return null;
}

function ConfirmationDialog({
  confirmation,
  onCancel,
  onConfirm,
}: {
  confirmation: PendingConfirmation | null;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <Modal
      animationType="fade"
      transparent
      visible={Boolean(confirmation)}
      onRequestClose={onCancel}
    >
      <View
        style={{
          alignItems: "center",
          backgroundColor: "rgba(12, 19, 24, 0.58)",
          flex: 1,
          justifyContent: "center",
          padding: spacing.lg,
        }}
      >
        <View
          accessibilityRole="alert"
          testID="confirmation-dialog"
          style={{
            backgroundColor: colors.panel,
            borderColor: colors.black,
            borderRadius: radii.medium,
            borderWidth: 1,
            gap: spacing.md,
            maxWidth: 460,
            padding: spacing.lg,
            width: "100%",
          }}
        >
          <View style={{ gap: spacing.xs }}>
            <Text style={eyebrowStyle}>Confirm action</Text>
            <Text style={{ color: colors.ink, fontSize: 22, fontWeight: "900" }}>
              {confirmation?.title ?? ""}
            </Text>
            <Text selectable style={{ color: colors.muted, lineHeight: 22 }}>
              {confirmation?.body ?? ""}
            </Text>
          </View>
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm, justifyContent: "flex-end" }}>
            <CommandButton label="Cancel" tone="plain" icon={Square} onPress={onCancel} />
            <CommandButton
              label={confirmation?.confirmLabel ?? "Confirm"}
              tone="danger"
              icon={Trash2}
              onPress={onConfirm}
            />
          </View>
        </View>
      </View>
    </Modal>
  );
}

function WorkflowOverview({
  activeTab,
  diagnostics,
  messageCount,
  onSelectTab,
  settings,
  transcriptLength,
  wide,
}: {
  activeTab: TabId;
  diagnostics: Partial<Record<ProviderKey, ProviderDiagnostic>>;
  messageCount: number;
  onSelectTab: (tab: TabId) => void;
  settings: ClientSettings;
  transcriptLength: number;
  wide: boolean;
}) {
  const steps: Array<{
    detail: string;
    icon: Icon;
    key: ProviderKey;
    metric: string;
    tab: TabId;
    title: string;
  }> = [
    {
      detail: `${trimUrl(settings.asr.baseUrl)} · ${settings.asr.model}`,
      icon: Mic,
      key: "asr",
      metric: transcriptLength ? `${transcriptLength} chars` : settings.asr.responseFormat,
      tab: "capture",
      title: "Capture",
    },
    {
      detail: `${settings.conversation.mode === "responses" ? "Responses" : "Chat Completions"} · ${settings.conversation.model}`,
      icon: MessageSquare,
      key: "conversation",
      metric: `${messageCount} messages`,
      tab: "chat",
      title: "Reason",
    },
    {
      detail: `${trimUrl(settings.tts.baseUrl)} · ${settings.tts.voice}`,
      icon: Volume2,
      key: "tts",
      metric: settings.tts.responseFormat.toUpperCase(),
      tab: "settings",
      title: "Speak",
    },
  ];

  return (
    <View
      style={{
        backgroundColor: colors.black,
        borderColor: colors.black,
        borderRadius: radii.large,
        borderWidth: 1,
        overflow: "hidden",
      }}
    >
      <View
        style={{
          gap: spacing.lg,
          padding: wide ? spacing.xl : spacing.lg,
        }}
      >
        <View
          style={{
            alignItems: wide ? "center" : "flex-start",
            flexDirection: wide ? "row" : "column",
            gap: spacing.lg,
            justifyContent: "space-between",
          }}
        >
          <View style={{ flex: 1, gap: spacing.sm, minWidth: 240 }}>
            <Text style={{ color: colors.cyanSoft, fontSize: 12, fontWeight: "900", textTransform: "uppercase" }}>
              Voice pipeline
            </Text>
            <Text style={{ color: colors.white, fontSize: wide ? 28 : 23, fontWeight: "900", lineHeight: wide ? 34 : 29 }}>
              Local ASR, model reasoning, and speech output in one workbench.
            </Text>
            <Text selectable style={{ color: "#b8c6cf", fontSize: 15, lineHeight: 22 }}>
              {statusSummary(settings)}
            </Text>
          </View>

          <View
            style={{
              alignItems: wide ? "flex-end" : "stretch",
              gap: spacing.sm,
              minWidth: wide ? 260 : "100%",
            }}
          >
            <StatusPill diagnostic={diagnostics.asr} label="ASR" />
            <StatusPill diagnostic={diagnostics.conversation} label="Conversation" />
            <StatusPill diagnostic={diagnostics.tts} label="TTS" />
          </View>
        </View>

        <View style={{ flexDirection: wide ? "row" : "column", gap: spacing.md }}>
          {steps.map((step, index) => (
            <WorkflowStepCard
              key={step.key}
              active={activeTab === step.tab}
              detail={step.detail}
              diagnostic={diagnostics[step.key]}
              icon={step.icon}
              index={index + 1}
              metric={step.metric}
              onPress={() => onSelectTab(step.tab)}
              title={step.title}
            />
          ))}
        </View>
      </View>
    </View>
  );
}

function WorkflowStepCard({
  active,
  detail,
  diagnostic,
  icon: IconComponent,
  index,
  metric,
  onPress,
  title,
}: {
  active: boolean;
  detail: string;
  diagnostic?: ProviderDiagnostic;
  icon: Icon;
  index: number;
  metric: string;
  onPress: () => void;
  title: string;
}) {
  const reachable = diagnostic?.ok === true;
  const failed = diagnostic?.ok === false;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected: active }}
      onPress={onPress}
      style={({ pressed }) => ({
        backgroundColor: active ? colors.white : colors.blackSoft,
        borderColor: active ? colors.white : "rgba(255,255,255,0.15)",
        borderRadius: radii.medium,
        borderWidth: 1,
        flex: 1,
        gap: spacing.md,
        minHeight: 154,
        minWidth: 0,
        opacity: pressed ? 0.78 : 1,
        padding: spacing.md,
      })}
    >
      <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: spacing.sm }}>
        <View
          style={{
            alignItems: "center",
            backgroundColor: active ? colors.black : "rgba(255,255,255,0.1)",
            borderRadius: radii.small,
            height: 40,
            justifyContent: "center",
            width: 40,
          }}
        >
          <IconComponent color={active ? colors.white : colors.cyanSoft} size={19} strokeWidth={2.5} />
        </View>
        <Text style={{ color: active ? colors.muted : "#9fb0ba", fontSize: 12, fontWeight: "900" }}>
          {String(index).padStart(2, "0")}
        </Text>
      </View>

      <View style={{ gap: spacing.xs }}>
        <Text style={{ color: active ? colors.ink : colors.white, fontSize: 20, fontWeight: "900" }}>
          {title}
        </Text>
        <Text selectable numberOfLines={2} style={{ color: active ? colors.muted : "#b8c6cf", lineHeight: 20 }}>
          {detail}
        </Text>
      </View>

      <View style={{ flexDirection: "row", justifyContent: "space-between", gap: spacing.sm, alignItems: "center" }}>
        <Text
          style={{
            color: active ? colors.ink : colors.white,
            fontSize: 13,
            fontWeight: "900",
          }}
        >
          {metric}
        </Text>
        <View
          style={{
            backgroundColor: failed ? colors.coralSoft : reachable ? colors.greenSoft : colors.steelSoft,
            borderRadius: 999,
            paddingHorizontal: spacing.sm,
            paddingVertical: spacing.xs,
          }}
        >
          <Text style={{ color: failed ? colors.coral : reachable ? colors.green : colors.steel, fontSize: 12, fontWeight: "900" }}>
            {failed ? "Issue" : reachable ? "Ready" : "Check"}
          </Text>
        </View>
      </View>
    </Pressable>
  );
}

function StatusPill({ diagnostic, label }: { diagnostic?: ProviderDiagnostic; label: string }) {
  const failed = diagnostic?.ok === false;
  const reachable = diagnostic?.ok === true;
  return (
    <View
      style={{
        alignItems: "center",
        alignSelf: "stretch",
        backgroundColor: failed ? "rgba(188,79,61,0.18)" : reachable ? "rgba(24,118,90,0.2)" : "rgba(255,255,255,0.1)",
        borderColor: failed ? colors.coral : reachable ? colors.green : "rgba(255,255,255,0.2)",
        borderRadius: 999,
        borderWidth: 1,
        flexDirection: "row",
        gap: spacing.sm,
        justifyContent: "space-between",
        minHeight: 36,
        paddingHorizontal: spacing.md,
      }}
    >
      <Text style={{ color: colors.white, fontWeight: "900" }}>{label}</Text>
      <Text style={{ color: failed ? colors.coralSoft : reachable ? colors.greenSoft : "#b8c6cf", fontWeight: "800" }}>
        {failed ? "Failed" : reachable ? "Reachable" : "Not checked"}
      </Text>
    </View>
  );
}

function CaptureView({
  busy,
  onClearTranscript,
  onCopy,
  onExport,
  onPickAudio,
  onSendToChat,
  onSpeak,
  onStartRecording,
  onStopRecording,
  rawResult,
  recorderState,
  transcript,
}: {
  busy: BusyState;
  onClearTranscript: () => void;
  onCopy: () => void;
  onExport: () => void;
  onPickAudio: () => void;
  onSendToChat: () => void;
  onSpeak: () => void;
  onStartRecording: () => void;
  onStopRecording: () => void;
  rawResult: string;
  recorderState: { isRecording: boolean; durationMillis: number; metering?: number };
  transcript: string;
}) {
  const seconds = Math.round(recorderState.durationMillis / 1000);
  const level = Math.max(0, Math.min(1, ((recorderState.metering ?? -60) + 60) / 60));
  const requestBusy = busy !== null;
  return (
    <View style={{ gap: spacing.lg }}>
      <Surface>
        <View style={{ gap: spacing.lg }}>
          <View style={{ flexDirection: "row", justifyContent: "space-between", gap: spacing.md, flexWrap: "wrap" }}>
            <View style={{ gap: spacing.xs, flex: 1, minWidth: 240 }}>
              <Text style={eyebrowStyle}>Live capture</Text>
              <Text style={{ color: colors.ink, fontSize: 22, fontWeight: "800" }}>
                {recorderState.isRecording ? "Recording microphone audio" : "Record or upload audio"}
              </Text>
              <Text selectable style={{ color: colors.muted, lineHeight: 21 }}>
                OpenAI Whisper compatible ASR endpoint, including local CapsWriter HTTP API.
              </Text>
            </View>
            <View style={{ alignItems: "flex-end", gap: spacing.xs, minWidth: 96 }}>
              <Text style={{ color: colors.ink, fontSize: 32, fontWeight: "900", fontVariant: ["tabular-nums"] }}>
                {seconds}s
              </Text>
              <Text style={{ color: colors.faint }}>duration</Text>
            </View>
          </View>

          <View style={{ height: 10, borderRadius: 999, backgroundColor: colors.line, overflow: "hidden" }}>
            <View style={{ width: `${Math.max(4, level * 100)}%`, height: "100%", backgroundColor: recorderState.isRecording ? colors.coral : colors.green }} />
          </View>

          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
            {recorderState.isRecording ? (
              <CommandButton label="Stop" tone="danger" icon={Square} loading={busy === "transcribe"} disabled={busy === "transcribe"} onPress={onStopRecording} />
            ) : (
              <CommandButton label="Record" tone="primary" icon={Mic} loading={busy === "record"} disabled={requestBusy} onPress={onStartRecording} />
            )}
            <CommandButton label="Upload" tone="secondary" icon={Upload} loading={busy === "transcribe"} disabled={requestBusy} onPress={onPickAudio} />
          </View>
        </View>
      </Surface>

      <Surface>
        <View style={{ gap: spacing.md }}>
          <View style={{ flexDirection: "row", justifyContent: "space-between", gap: spacing.md, flexWrap: "wrap" }}>
            <View style={{ gap: spacing.xs, flex: 1, minWidth: 220 }}>
              <Text style={eyebrowStyle}>Transcript</Text>
              <Text style={{ color: colors.ink, fontSize: 20, fontWeight: "800" }}>
                {transcript ? `${transcript.length} chars` : "No transcript yet"}
              </Text>
            </View>
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
              <IconOnly disabled={!transcript} icon={Copy} label="Copy" onPress={onCopy} />
              <IconOnly disabled={!transcript} icon={Download} label="Export transcript" onPress={onExport} />
              <IconOnly disabled={!transcript || requestBusy} icon={Send} label="Send to chat" onPress={onSendToChat} />
              <IconOnly disabled={!transcript || requestBusy} icon={Volume2} label="Speak" onPress={onSpeak} />
              <IconOnly disabled={!transcript && !rawResult} icon={RotateCcw} label="Clear transcript" onPress={onClearTranscript} />
            </View>
          </View>
          <Text selectable style={{ color: transcript ? colors.ink : colors.faint, fontSize: 17, lineHeight: 26 }}>
            {transcript || "Start a recording or upload an audio/video file. The result will appear here."}
          </Text>
        </View>
      </Surface>

      {rawResult ? (
        <Surface subtle>
          <View style={{ gap: spacing.sm }}>
            <Text style={eyebrowStyle}>Raw response</Text>
            <Text selectable style={{ color: colors.muted, fontFamily: "monospace", lineHeight: 18 }}>
              {rawResult}
            </Text>
          </View>
        </Surface>
      ) : null}
    </View>
  );
}

function ChatView({
  busy,
  draft,
  messages,
  onChangeDraft,
  onClear,
  onSend,
  onSendTranscript,
  onSpeak,
  onExport,
  transcript,
}: {
  busy: BusyState;
  draft: string;
  messages: ChatMessage[];
  onChangeDraft: (value: string) => void;
  onClear: () => void;
  onExport: () => void;
  onSend: () => void;
  onSendTranscript: () => void;
  onSpeak: (text: string) => void;
  transcript: string;
}) {
  const requestBusy = busy !== null;
  return (
    <View style={{ gap: spacing.lg }}>
      <Surface>
        <View style={{ gap: spacing.md }}>
          <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: spacing.md, flexWrap: "wrap" }}>
            <View style={{ gap: spacing.xs, flex: 1, minWidth: 220 }}>
              <Text style={eyebrowStyle}>Conversation</Text>
              <Text style={{ color: colors.ink, fontSize: 22, fontWeight: "800" }}>
                Chat Completions / Responses
              </Text>
            </View>
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
              <CommandButton label="Export" tone="secondary" icon={Download} disabled={!messages.length} onPress={onExport} />
              <CommandButton label="Clear" tone="plain" icon={RotateCcw} onPress={onClear} />
            </View>
          </View>
          <TextInput
            multiline
            value={draft}
            onChangeText={onChangeDraft}
            placeholder="Type a message, or send the latest transcript."
            placeholderTextColor={colors.faint}
            style={inputStyle({ minHeight: 110, textAlignVertical: "top" })}
          />
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
            <CommandButton label="Send" tone="primary" icon={Send} loading={busy === "chat"} disabled={requestBusy || !draft.trim()} onPress={onSend} />
            <CommandButton label="Use transcript" tone="secondary" icon={FileAudio} disabled={!transcript || requestBusy} onPress={onSendTranscript} />
          </View>
        </View>
      </Surface>

      <View style={{ gap: spacing.md }}>
        {messages.length === 0 ? (
          <Surface subtle>
            <Text style={{ color: colors.muted, lineHeight: 22 }}>
              Conversation history is empty. Send a transcript or type a prompt to test your provider.
            </Text>
          </Surface>
        ) : null}
        {messages.map((message) => (
          <View
            key={message.id}
            style={{
              borderWidth: 1,
              borderColor: message.role === "assistant" ? colors.green : colors.line,
              backgroundColor: message.role === "assistant" ? colors.greenSoft : colors.panel,
              borderRadius: radii.medium,
              padding: spacing.md,
              gap: spacing.sm,
            }}
          >
            <View style={{ flexDirection: "row", justifyContent: "space-between", gap: spacing.md }}>
              <Text style={{ color: colors.ink, fontWeight: "800" }}>
                {message.role === "assistant" ? "Assistant" : "User"}
              </Text>
              {message.role === "assistant" ? <IconOnly disabled={requestBusy} icon={Volume2} label="Speak" onPress={() => onSpeak(message.content)} /> : null}
            </View>
            <Text selectable style={{ color: colors.ink, lineHeight: 23 }}>
              {message.content || (message.role === "assistant" ? "Waiting for response..." : "")}
            </Text>
          </View>
        ))}
      </View>
    </View>
  );
}

function SettingsView({
  busy,
  diagnostics,
  onExportSettings,
  onImportSettings,
  onClearWorkspace,
  onProbeAll,
  onProbeProvider,
  onReset,
  onUpdate,
  onUseModel,
  settings,
  wide,
}: {
  busy: BusyState;
  diagnostics: Partial<Record<ProviderKey, ProviderDiagnostic>>;
  onClearWorkspace: () => void;
  onProbeAll: () => void;
  onProbeProvider: (provider: ProviderKey) => void;
  onExportSettings: () => void;
  onImportSettings: () => void;
  onReset: () => void;
  onUpdate: (settings: ClientSettings) => void;
  onUseModel: (provider: ProviderKey, modelId: string) => void;
  settings: ClientSettings;
  wide: boolean;
}) {
  const requestBusy = busy !== null;
  const updateAsr = <K extends keyof AsrSettings>(key: K, value: AsrSettings[K]) =>
    onUpdate({ ...settings, asr: { ...settings.asr, [key]: value } });
  const updateConversation = <K extends keyof ConversationSettings>(key: K, value: ConversationSettings[K]) =>
    onUpdate({ ...settings, conversation: { ...settings.conversation, [key]: value } });
  const updateTts = <K extends keyof TtsSettings>(key: K, value: TtsSettings[K]) =>
    onUpdate({ ...settings, tts: { ...settings.tts, [key]: value } });

  return (
    <View style={{ gap: spacing.lg }}>
      <Surface>
        <View style={{ gap: spacing.md }}>
          <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: spacing.md, flexWrap: "wrap" }}>
            <PanelTitle icon={Wifi} eyebrow="Diagnostics" title="Provider checks" />
            <CommandButton label="Check all" tone="secondary" icon={Wifi} loading={busy === "probe"} disabled={requestBusy} onPress={onProbeAll} />
          </View>
          <View style={{ flexDirection: wide ? "row" : "column", gap: spacing.md }}>
            <ProviderProbeCard
              label="ASR"
              model={settings.asr.model}
              result={diagnostics.asr}
              onPress={() => onProbeProvider("asr")}
              onUseModel={(modelId) => onUseModel("asr", modelId)}
              disabled={requestBusy}
              style={{ flex: 1 }}
            />
            <ProviderProbeCard
              label="Chat"
              model={settings.conversation.model}
              result={diagnostics.conversation}
              onPress={() => onProbeProvider("conversation")}
              onUseModel={(modelId) => onUseModel("conversation", modelId)}
              disabled={requestBusy}
              style={{ flex: 1 }}
            />
            <ProviderProbeCard
              label="TTS"
              model={settings.tts.model}
              result={diagnostics.tts}
              onPress={() => onProbeProvider("tts")}
              onUseModel={(modelId) => onUseModel("tts", modelId)}
              disabled={requestBusy}
              style={{ flex: 1 }}
            />
          </View>
        </View>
      </Surface>

      <Surface>
        <View style={{ gap: spacing.md }}>
          <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: spacing.md, flexWrap: "wrap" }}>
            <PanelTitle icon={Settings2} eyebrow="Portability" title="Settings backup" />
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
              <CommandButton label="Export settings" tone="secondary" icon={Download} onPress={onExportSettings} />
              <CommandButton label="Import settings" tone="plain" icon={Upload} onPress={onImportSettings} />
            </View>
          </View>
        </View>
      </Surface>

      <Surface>
        <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: spacing.md, flexWrap: "wrap" }}>
          <PanelTitle icon={Trash2} eyebrow="Local data" title="Workspace storage" />
          <CommandButton label="Clear workspace" tone="danger" icon={Trash2} onPress={onClearWorkspace} />
        </View>
      </Surface>

      <View style={{ flexDirection: wide ? "row" : "column", gap: spacing.lg }}>
        <Surface style={{ flex: 1 }}>
          <View style={{ gap: spacing.md }}>
            <PanelTitle icon={Mic} eyebrow="ASR" title="Transcription provider" />
            <Field label="Base URL" value={settings.asr.baseUrl} onChangeText={(value) => updateAsr("baseUrl", value)} />
            <Field label="API key" value={settings.asr.apiKey} secureTextEntry onChangeText={(value) => updateAsr("apiKey", value)} />
            <Field label="Model" value={settings.asr.model} onChangeText={(value) => updateAsr("model", value)} />
            <Segmented<AsrResponseFormat>
              label="Response format"
              value={settings.asr.responseFormat}
              options={[
                { label: "JSON", value: "json" },
                { label: "Text", value: "text" },
                { label: "Verbose", value: "verbose_json" },
                { label: "SRT", value: "srt" },
                { label: "VTT", value: "vtt" },
              ]}
              onChange={(value) => updateAsr("responseFormat", value)}
            />
            <Field label="Language" value={settings.asr.language} onChangeText={(value) => updateAsr("language", value)} />
            <Field label="Prompt / vocabulary hint" value={settings.asr.prompt} multiline onChangeText={(value) => updateAsr("prompt", value)} />
            <NumericField label="Temperature" min={0} max={1} value={settings.asr.temperature} onChange={(value) => updateAsr("temperature", value)} />
            <NumericField label="Timeout seconds" min={1} integer value={settings.asr.timeoutSec} onChange={(value) => updateAsr("timeoutSec", value)} />
            <JsonField label="Extra headers JSON" mode="headers" value={settings.asr.extraHeadersJson} onChangeText={(value) => updateAsr("extraHeadersJson", value)} />
            <JsonField label="Extra form fields JSON" mode="object" value={settings.asr.extraFormFieldsJson} onChangeText={(value) => updateAsr("extraFormFieldsJson", value)} />
          </View>
        </Surface>

        <Surface style={{ flex: 1 }}>
          <View style={{ gap: spacing.md }}>
            <PanelTitle icon={MessageSquare} eyebrow="Conversation" title="Chat provider" />
            <Field label="Base URL" value={settings.conversation.baseUrl} onChangeText={(value) => updateConversation("baseUrl", value)} />
            <Field label="API key" value={settings.conversation.apiKey} secureTextEntry onChangeText={(value) => updateConversation("apiKey", value)} />
            <Segmented<ConversationMode>
              label="API mode"
              value={settings.conversation.mode}
              options={[
                { label: "Responses", value: "responses" },
                { label: "Chat", value: "chat_completions" },
              ]}
              onChange={(value) => updateConversation("mode", value)}
            />
            <Field label="Model" value={settings.conversation.model} onChangeText={(value) => updateConversation("model", value)} />
            <Field label="System prompt" value={settings.conversation.systemPrompt} multiline onChangeText={(value) => updateConversation("systemPrompt", value)} />
            <View style={{ flexDirection: wide ? "row" : "column", gap: spacing.md }}>
              <NumericField label="Temperature" min={0} max={2} value={settings.conversation.temperature} onChange={(value) => updateConversation("temperature", value)} style={{ flex: 1 }} />
              <NumericField label="Top P" min={0} max={1} value={settings.conversation.topP} onChange={(value) => updateConversation("topP", value)} style={{ flex: 1 }} />
              <NumericField label="Max output tokens" min={1} integer value={settings.conversation.maxOutputTokens} onChange={(value) => updateConversation("maxOutputTokens", value)} style={{ flex: 1 }} />
            </View>
            <View style={{ flexDirection: wide ? "row" : "column", gap: spacing.md }}>
              <NumericField label="Frequency penalty" min={-2} max={2} value={settings.conversation.frequencyPenalty} onChange={(value) => updateConversation("frequencyPenalty", value)} style={{ flex: 1 }} />
              <NumericField label="Presence penalty" min={-2} max={2} value={settings.conversation.presencePenalty} onChange={(value) => updateConversation("presencePenalty", value)} style={{ flex: 1 }} />
              <NumericField label="Timeout seconds" min={1} integer value={settings.conversation.timeoutSec} onChange={(value) => updateConversation("timeoutSec", value)} style={{ flex: 1 }} />
            </View>
            <SwitchRow label="Keep history" value={settings.keepConversationHistory} onValueChange={(value) => onUpdate({ ...settings, keepConversationHistory: value })} />
            <SwitchRow label="Auto speak replies" value={settings.autoSpeak} onValueChange={(value) => onUpdate({ ...settings, autoSpeak: value })} />
            <SwitchRow label="Streaming responses" value={settings.conversation.stream} onValueChange={(value) => updateConversation("stream", value)} />
            <JsonField label="Extra headers JSON" mode="headers" value={settings.conversation.extraHeadersJson} onChangeText={(value) => updateConversation("extraHeadersJson", value)} />
            <JsonField label="Extra body JSON" mode="object" value={settings.conversation.extraBodyJson} onChangeText={(value) => updateConversation("extraBodyJson", value)} />
          </View>
        </Surface>
      </View>

      <Surface>
        <View style={{ gap: spacing.md }}>
          <PanelTitle icon={Volume2} eyebrow="TTS" title="Speech provider" />
          <View style={{ flexDirection: wide ? "row" : "column", gap: spacing.md }}>
            <Field label="Base URL" value={settings.tts.baseUrl} onChangeText={(value) => updateTts("baseUrl", value)} style={{ flex: 2 }} />
            <Field label="API key" value={settings.tts.apiKey} secureTextEntry onChangeText={(value) => updateTts("apiKey", value)} style={{ flex: 1 }} />
          </View>
          <View style={{ flexDirection: wide ? "row" : "column", gap: spacing.md }}>
            <Field label="Model" value={settings.tts.model} onChangeText={(value) => updateTts("model", value)} style={{ flex: 1 }} />
            <Field label="Voice" value={settings.tts.voice} onChangeText={(value) => updateTts("voice", value)} style={{ flex: 1 }} />
            <NumericField label="Speed" min={0.25} max={4} value={settings.tts.speed} onChange={(value) => updateTts("speed", value)} style={{ flex: 1 }} />
            <NumericField label="Timeout seconds" min={1} integer value={settings.tts.timeoutSec} onChange={(value) => updateTts("timeoutSec", value)} style={{ flex: 1 }} />
          </View>
          <Segmented<SpeechFormat>
            label="Speech format"
            value={settings.tts.responseFormat}
            options={[
              { label: "MP3", value: "mp3" },
              { label: "Opus", value: "opus" },
              { label: "AAC", value: "aac" },
              { label: "FLAC", value: "flac" },
              { label: "WAV", value: "wav" },
              { label: "PCM", value: "pcm" },
            ]}
            onChange={(value) => updateTts("responseFormat", value)}
          />
          <Field label="Voice instructions" value={settings.tts.instructions} multiline onChangeText={(value) => updateTts("instructions", value)} />
          <JsonField label="Extra headers JSON" mode="headers" value={settings.tts.extraHeadersJson} onChangeText={(value) => updateTts("extraHeadersJson", value)} />
          <JsonField label="Extra body JSON" mode="object" value={settings.tts.extraBodyJson} onChangeText={(value) => updateTts("extraBodyJson", value)} />
          <CommandButton label="Reset defaults" tone="plain" icon={RotateCcw} onPress={onReset} />
        </View>
      </Surface>
    </View>
  );
}

function ProviderProbeCard({
  disabled,
  label,
  model,
  onPress,
  onUseModel,
  result,
  style,
}: {
  disabled?: boolean;
  label: string;
  model: string;
  onPress: () => void;
  onUseModel: (modelId: string) => void;
  result?: ProviderDiagnostic;
  style?: object;
}) {
  const ok = result?.ok;
  const modelIds = result?.modelIds ?? [];
  const modelPreview = modelIds.slice(0, 4);
  return (
    <View
      style={[
        {
          borderWidth: 1,
          borderColor: ok === undefined ? colors.line : ok ? colors.green : colors.danger,
          backgroundColor: ok === undefined ? colors.panel : ok ? colors.greenSoft : colors.coralSoft,
          borderRadius: radii.medium,
          padding: spacing.md,
          gap: spacing.sm,
        },
        style,
      ]}
    >
      <View style={{ flexDirection: "row", justifyContent: "space-between", gap: spacing.sm, alignItems: "center" }}>
        <View style={{ gap: 2, flex: 1 }}>
          <Text style={eyebrowStyle}>{label}</Text>
          <Text selectable style={{ color: colors.ink, fontWeight: "800" }}>
            {ok === undefined ? "Not checked" : ok ? "Reachable" : "Failed"}
          </Text>
        </View>
        <IconOnly disabled={disabled} icon={Wifi} label={`Check ${label}`} onPress={onPress} />
      </View>
      <Text selectable style={{ color: colors.muted, lineHeight: 20 }}>
        {result
          ? `${result.status ? `HTTP ${result.status} · ` : ""}${result.message}`
          : `Configured model: ${model}`}
      </Text>
      {modelPreview.length ? (
        <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.xs }}>
          {modelPreview.map((modelId) => {
            const selected = modelId === model;
            return (
              <Pressable
                key={modelId}
                accessibilityRole="button"
                accessibilityLabel={`Use ${modelId} for ${label}`}
                accessibilityState={{ selected }}
                disabled={disabled}
                onPress={() => onUseModel(modelId)}
                style={({ pressed }) => ({
                  borderWidth: 1,
                  borderColor: selected ? colors.black : colors.line,
                  backgroundColor: selected ? colors.black : colors.panel,
                  borderRadius: radii.small,
                  paddingHorizontal: spacing.sm,
                  paddingVertical: spacing.xs,
                  opacity: disabled ? 0.45 : pressed ? 0.75 : 1,
                })}
              >
                <Text style={{ color: selected ? colors.white : colors.ink, fontSize: 12, fontWeight: "800" }}>
                  {modelId}
                </Text>
              </Pressable>
            );
          })}
          {modelIds.length > modelPreview.length ? (
            <Text style={{ color: colors.muted, paddingVertical: spacing.xs, fontWeight: "800" }}>
              +{modelIds.length - modelPreview.length}
            </Text>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

function TemplatesView({
  busy,
  customProviderTemplates,
  customPromptTemplates,
  current,
  onApply,
  onDeleteProvider,
  onDeletePrompt,
  onLoadPrompt,
  onRunPrompt,
  onSaveProvider,
  onSavePrompt,
  transcript,
}: {
  busy: BusyState;
  customProviderTemplates: ClientTemplate[];
  customPromptTemplates: PromptTemplate[];
  current: ClientSettings;
  onApply: (templateId: string) => void;
  onDeleteProvider: (templateId: string) => void;
  onDeletePrompt: (templateId: string) => void;
  onLoadPrompt: (template: PromptTemplate) => void;
  onRunPrompt: (template: PromptTemplate) => void;
  onSaveProvider: (draft: ProviderTemplateDraft) => boolean;
  onSavePrompt: (draft: PromptTemplateDraft) => boolean;
  transcript: string;
}) {
  const requestBusy = busy !== null;
  const [providerDraft, setProviderDraft] = useState<ProviderTemplateDraft>(emptyProviderTemplateDraft);
  const [draft, setDraft] = useState<PromptTemplateDraft>(emptyPromptTemplateDraft);
  const promptLibrary = [...customPromptTemplates, ...promptTemplates];
  const providerLibrary = [...customProviderTemplates, ...templates];
  const updateProviderDraft = (key: keyof ProviderTemplateDraft, value: string) =>
    setProviderDraft((currentDraft) => ({ ...currentDraft, [key]: value }));
  const saveProviderDraft = () => {
    if (onSaveProvider(providerDraft)) {
      setProviderDraft(emptyProviderTemplateDraft);
    }
  };
  const updateDraft = (key: keyof PromptTemplateDraft, value: string) =>
    setDraft((currentDraft) => ({ ...currentDraft, [key]: value }));
  const saveDraft = () => {
    if (onSavePrompt(draft)) {
      setDraft(emptyPromptTemplateDraft);
    }
  };

  return (
    <View style={{ gap: spacing.lg }}>
      <View style={{ gap: spacing.md }}>
        <PanelTitle icon={Sparkles} eyebrow="Workflows" title="Prompt templates" />

        <Surface subtle>
          <View style={{ gap: spacing.md }}>
            <PanelTitle icon={Plus} eyebrow="Custom" title="Create prompt template" />
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.md }}>
              <Field label="Name" value={draft.name} onChangeText={(value) => updateDraft("name", value)} style={{ flex: 1, minWidth: 180 }} />
              <Field label="Category" value={draft.category} onChangeText={(value) => updateDraft("category", value)} style={{ flex: 1, minWidth: 160 }} />
              <Field label="Tags" value={draft.tags} onChangeText={(value) => updateDraft("tags", value)} style={{ flex: 1, minWidth: 180 }} />
            </View>
            <Field label="Description" value={draft.description} onChangeText={(value) => updateDraft("description", value)} />
            <Field label="Prompt" value={draft.prompt} multiline onChangeText={(value) => updateDraft("prompt", value)} />
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
              <CommandButton
                label="Save custom prompt"
                tone="primary"
                icon={Save}
                disabled={!draft.name.trim() || !draft.prompt.trim()}
                onPress={saveDraft}
              />
              <CommandButton label="Reset form" tone="plain" icon={RotateCcw} onPress={() => setDraft(emptyPromptTemplateDraft)} />
            </View>
          </View>
        </Surface>

        {promptLibrary.map((template) => {
          const custom = template.id.startsWith("custom-");
          return (
            <TemplateCard
              key={template.id}
              title={template.name}
              description={template.description}
              eyebrow={custom ? `${template.category} · Custom` : template.category}
              tags={template.tags}
              actions={
                <>
                  <CommandButton label="Use prompt" tone="secondary" icon={MessageSquare} onPress={() => onLoadPrompt(template)} />
                  <CommandButton
                    label="Run with transcript"
                    tone="primary"
                    icon={Send}
                    disabled={!transcript.trim() || requestBusy}
                    loading={busy === "chat"}
                    onPress={() => onRunPrompt(template)}
                  />
                  {custom ? (
                    <IconOnly icon={Trash2} label={`Delete ${template.name}`} onPress={() => onDeletePrompt(template.id)} />
                  ) : null}
                </>
              }
            />
          );
        })}
      </View>

      <View style={{ gap: spacing.md }}>
        <PanelTitle icon={Settings2} eyebrow="Providers" title="Provider templates" />

        <Surface subtle>
          <View style={{ gap: spacing.md }}>
            <PanelTitle icon={Plus} eyebrow="Custom" title="Save current provider setup" />
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.md }}>
              <Field label="Provider template name" value={providerDraft.name} onChangeText={(value) => updateProviderDraft("name", value)} style={{ flex: 1, minWidth: 220 }} />
              <Field label="Provider template tags" value={providerDraft.tags} onChangeText={(value) => updateProviderDraft("tags", value)} style={{ flex: 1, minWidth: 220 }} />
            </View>
            <Field label="Provider template description" value={providerDraft.description} onChangeText={(value) => updateProviderDraft("description", value)} />
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
              <CommandButton
                label="Save provider template"
                tone="primary"
                icon={Save}
                disabled={!providerDraft.name.trim()}
                onPress={saveProviderDraft}
              />
              <CommandButton label="Reset provider form" tone="plain" icon={RotateCcw} onPress={() => setProviderDraft(emptyProviderTemplateDraft)} />
            </View>
          </View>
        </Surface>

        {providerLibrary.map((template) => {
          const custom = template.id.startsWith("custom-provider-");
          const selected =
            current.asr.baseUrl === template.settings.asr.baseUrl &&
            current.conversation.baseUrl === template.settings.conversation.baseUrl &&
            current.conversation.mode === template.settings.conversation.mode;
          return (
            <TemplateCard
              key={template.id}
              title={template.name}
              description={template.description}
              eyebrow={selected ? "Applied" : custom ? "Custom setup" : "Setup"}
              tags={template.tags}
              selected={selected}
              actions={
                <>
                  <CommandButton
                    label={selected ? "Applied" : "Apply"}
                    tone={selected ? "secondary" : "primary"}
                    icon={selected ? Check : Save}
                    onPress={() => onApply(template.id)}
                  />
                  {custom ? (
                    <IconOnly icon={Trash2} label={`Delete ${template.name}`} onPress={() => onDeleteProvider(template.id)} />
                  ) : null}
                </>
              }
            />
          );
        })}
      </View>
    </View>
  );
}

function TemplateCard({
  actions,
  description,
  eyebrow,
  selected,
  tags,
  title,
}: {
  actions: React.ReactNode;
  description: string;
  eyebrow: string;
  selected?: boolean;
  tags: string[];
  title: string;
}) {
  return (
    <View
      style={{
        borderWidth: 1,
        borderColor: selected ? colors.green : colors.line,
        backgroundColor: selected ? colors.greenSoft : colors.panel,
        borderRadius: radii.medium,
        padding: spacing.lg,
        gap: spacing.md,
      }}
    >
      <View style={{ flexDirection: "row", justifyContent: "space-between", gap: spacing.md, flexWrap: "wrap" }}>
        <View style={{ gap: spacing.xs, flex: 1, minWidth: 220 }}>
          <Text style={eyebrowStyle}>{eyebrow}</Text>
          <Text style={{ color: colors.ink, fontSize: 20, fontWeight: "800" }}>{title}</Text>
          <Text selectable style={{ color: colors.muted, lineHeight: 21 }}>{description}</Text>
        </View>
        <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>{actions}</View>
      </View>
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
        {tags.map((tag) => (
          <Text key={tag} style={{ backgroundColor: colors.cyanSoft, color: colors.cyan, paddingHorizontal: spacing.sm, paddingVertical: spacing.xs, borderRadius: radii.small, fontWeight: "700" }}>
            {tag}
          </Text>
        ))}
      </View>
    </View>
  );
}

function Surface({
  children,
  subtle,
  style,
}: {
  children: React.ReactNode;
  subtle?: boolean;
  style?: object;
}) {
  return (
    <View
      style={[
        {
          borderWidth: 1,
          borderColor: subtle ? colors.line : colors.black,
          backgroundColor: subtle ? colors.panelAlt : colors.panel,
          borderRadius: radii.medium,
          padding: spacing.lg,
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

function PanelTitle({ eyebrow, icon: IconComponent, title }: { eyebrow: string; icon: Icon; title: string }) {
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: spacing.sm }}>
      <View style={{ width: 38, height: 38, borderRadius: radii.small, alignItems: "center", justifyContent: "center", backgroundColor: colors.black }}>
        <IconComponent size={19} color={colors.white} strokeWidth={2.5} />
      </View>
      <View style={{ gap: 2 }}>
        <Text style={eyebrowStyle}>{eyebrow}</Text>
        <Text style={{ color: colors.ink, fontWeight: "800", fontSize: 20 }}>{title}</Text>
      </View>
    </View>
  );
}

function TabButton({ active, icon: IconComponent, label, onPress }: { active: boolean; icon: Icon; label: string; onPress: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected: active }}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: 44,
        minWidth: 86,
        borderRadius: radii.small,
        borderWidth: 1,
        borderColor: active ? colors.black : colors.line,
        backgroundColor: active ? colors.black : colors.panel,
        paddingHorizontal: spacing.md,
        alignItems: "center",
        justifyContent: "center",
        flexDirection: "row",
        gap: spacing.sm,
        opacity: pressed ? 0.78 : 1,
      })}
    >
      <IconComponent size={17} color={active ? colors.white : colors.ink} strokeWidth={2.4} />
      <Text style={{ color: active ? colors.white : colors.ink, fontWeight: "800" }}>{label}</Text>
    </Pressable>
  );
}

function CommandButton({
  disabled,
  icon: IconComponent,
  label,
  loading,
  onPress,
  tone,
}: {
  disabled?: boolean;
  icon: Icon;
  label: string;
  loading?: boolean;
  onPress: () => void;
  tone: "primary" | "secondary" | "danger" | "plain";
}) {
  const palette = {
    primary: { background: colors.black, border: colors.black, text: colors.white },
    secondary: { background: colors.greenSoft, border: colors.green, text: colors.green },
    danger: { background: colors.coralSoft, border: colors.coral, text: colors.coral },
    plain: { background: colors.panel, border: colors.line, text: colors.ink },
  }[tone];

  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled || loading}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: 44,
        borderRadius: radii.small,
        borderWidth: 1,
        borderColor: palette.border,
        backgroundColor: palette.background,
        paddingHorizontal: spacing.md,
        alignItems: "center",
        justifyContent: "center",
        flexDirection: "row",
        gap: spacing.sm,
        opacity: disabled ? 0.45 : pressed ? 0.75 : 1,
      })}
    >
      {loading ? <ActivityIndicator color={palette.text} /> : <IconComponent size={18} color={palette.text} strokeWidth={2.4} />}
      <Text style={{ color: palette.text, fontWeight: "800" }}>{label}</Text>
    </Pressable>
  );
}

function IconOnly({ disabled, icon: IconComponent, label, onPress }: { disabled?: boolean; icon: Icon; label: string; onPress: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => ({
        width: 44,
        height: 44,
        borderRadius: radii.small,
        borderWidth: 1,
        borderColor: colors.line,
        backgroundColor: colors.panel,
        alignItems: "center",
        justifyContent: "center",
        opacity: disabled ? 0.4 : pressed ? 0.7 : 1,
      })}
    >
      <IconComponent size={18} color={colors.ink} strokeWidth={2.4} />
    </Pressable>
  );
}

function Field({
  hint,
  hintTone = "muted",
  label,
  multiline,
  onChangeText,
  secureTextEntry,
  style,
  value,
}: {
  hint?: string;
  hintTone?: "danger" | "muted" | "success";
  label: string;
  multiline?: boolean;
  onChangeText: (value: string) => void;
  secureTextEntry?: boolean;
  style?: object;
  value: string;
}) {
  return (
    <View style={[{ gap: spacing.xs }, style]}>
      <Text style={labelStyle}>{label}</Text>
      <TextInput
        accessibilityLabel={label}
        value={value}
        onChangeText={onChangeText}
        multiline={multiline}
        secureTextEntry={secureTextEntry}
        placeholderTextColor={colors.faint}
        style={inputStyle({ minHeight: multiline ? 92 : 44, textAlignVertical: multiline ? "top" : "center" })}
      />
      {hint ? (
        <Text selectable style={{ color: hintColor(hintTone), fontSize: 12, fontWeight: "700", lineHeight: 18 }}>
          {hint}
        </Text>
      ) : null}
    </View>
  );
}

function JsonField({
  label,
  mode,
  onChangeText,
  value,
}: {
  label: string;
  mode: "headers" | "object";
  onChangeText: (value: string) => void;
  value: string;
}) {
  const validation = validateJsonField(value, mode);
  return (
    <Field
      hint={validation?.message}
      hintTone={validation?.tone}
      label={label}
      multiline
      value={value}
      onChangeText={onChangeText}
    />
  );
}

function NumericField({
  integer,
  label,
  max,
  min,
  onChange,
  style,
  value,
}: {
  integer?: boolean;
  label: string;
  max?: number;
  min?: number;
  onChange: (value: number) => void;
  style?: object;
  value: number;
}) {
  const [draft, setDraft] = useState(String(value));
  const parsed = parseNumericDraft(draft);
  const draftIsBlank = !draft.trim();
  const valid = parsed !== null && isValidNumericValue(parsed, { integer, max, min });
  const hint = !draftIsBlank && !valid ? numericValidationMessage({ integer, max, min }) : undefined;

  useEffect(() => {
    setDraft(String(value));
  }, [value]);

  function commit(text: string) {
    const next = parseNumericDraft(text);
    if (next !== null && isValidNumericValue(next, { integer, max, min })) {
      onChange(next);
      return;
    }
    setDraft(String(value));
  }

  return (
    <View style={[{ gap: spacing.xs }, style]}>
      <Text style={labelStyle}>{label}</Text>
      <TextInput
        accessibilityLabel={label}
        value={draft}
        keyboardType={min !== undefined && min < 0 ? "numbers-and-punctuation" : "numeric"}
        onChangeText={(text) => {
          setDraft(text);
          const next = parseNumericDraft(text);
          if (next !== null && isValidNumericValue(next, { integer, max, min })) {
            onChange(next);
          }
        }}
        onBlur={() => commit(draft)}
        onSubmitEditing={() => commit(draft)}
        style={inputStyle({ minHeight: 44 })}
      />
      {hint ? (
        <Text selectable style={{ color: colors.danger, fontSize: 12, fontWeight: "700", lineHeight: 18 }}>
          {hint}
        </Text>
      ) : null}
    </View>
  );
}

function parseNumericDraft(text: string) {
  const normalized = text.trim();
  if (!normalized || normalized === "-" || normalized === "." || normalized === "-.") {
    return null;
  }
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function isValidNumericValue(
  value: number,
  {
    integer,
    max,
    min,
  }: {
    integer?: boolean;
    max?: number;
    min?: number;
  },
) {
  if (!Number.isFinite(value)) {
    return false;
  }
  if (integer && !Number.isInteger(value)) {
    return false;
  }
  if (min !== undefined && value < min) {
    return false;
  }
  if (max !== undefined && value > max) {
    return false;
  }
  return true;
}

function numericValidationMessage({
  integer,
  max,
  min,
}: {
  integer?: boolean;
  max?: number;
  min?: number;
}) {
  const noun = integer ? "whole number" : "number";
  if (min !== undefined && max !== undefined) {
    return `Enter a ${noun} from ${min} to ${max}.`;
  }
  if (min !== undefined) {
    return `Enter a ${noun} of at least ${min}.`;
  }
  if (max !== undefined) {
    return `Enter a ${noun} of ${max} or less.`;
  }
  return `Enter a valid ${noun}.`;
}

function Segmented<T extends string>({
  label,
  onChange,
  options,
  value,
}: {
  label: string;
  onChange: (value: T) => void;
  options: Array<{ label: string; value: T }>;
  value: T;
}) {
  return (
    <View style={{ gap: spacing.xs }}>
      <Text style={labelStyle}>{label}</Text>
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.sm }}>
        {options.map((option) => {
          const selected = value === option.value;
          return (
            <Pressable
              key={option.value}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              onPress={() => onChange(option.value)}
              style={({ pressed }) => ({
                minHeight: 44,
                borderRadius: radii.small,
                borderWidth: 1,
                borderColor: selected ? colors.black : colors.line,
                backgroundColor: selected ? colors.black : colors.panel,
                paddingHorizontal: spacing.md,
                alignItems: "center",
                justifyContent: "center",
                opacity: pressed ? 0.75 : 1,
              })}
            >
              <Text style={{ color: selected ? colors.white : colors.ink, fontWeight: "800" }}>{option.label}</Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

function SwitchRow({ label, onValueChange, value }: { label: string; onValueChange: (value: boolean) => void; value: boolean }) {
  return (
    <View style={{ minHeight: 44, flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: spacing.md }}>
      <Text style={labelStyle}>{label}</Text>
      <Switch value={value} onValueChange={onValueChange} trackColor={{ false: colors.line, true: colors.greenSoft }} thumbColor={value ? colors.green : colors.faint} />
    </View>
  );
}

function Notice({ onClear, text }: { onClear: () => void; text: string }) {
  return (
    <Pressable onPress={onClear} style={{ borderWidth: 1, borderColor: colors.gold, backgroundColor: colors.goldSoft, borderRadius: radii.medium, padding: spacing.md }}>
      <Text selectable style={{ color: colors.ink, lineHeight: 21 }}>
        {text}
      </Text>
    </Pressable>
  );
}

function inputStyle(extra?: object) {
  return {
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: radii.small,
    backgroundColor: colors.white,
    color: colors.ink,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    fontSize: 15,
    lineHeight: 21,
    ...extra,
  };
}

const labelStyle = {
  color: colors.muted,
  fontSize: 13,
  fontWeight: "800" as const,
};

const eyebrowStyle = {
  color: colors.coral,
  fontSize: 12,
  fontWeight: "900" as const,
  textTransform: "uppercase" as const,
};

function trimUrl(url: string) {
  return url.replace(/^https?:\/\//, "").replace(/\/$/, "");
}

function isObjectUrl(uri?: string | null) {
  return typeof uri === "string" && uri.startsWith("blob:");
}

function providerConfig(settings: ClientSettings, provider: ProviderKey) {
  if (provider === "asr") {
    return {
      label: "ASR",
      baseUrl: settings.asr.baseUrl,
      apiKey: settings.asr.apiKey,
      extraHeadersJson: settings.asr.extraHeadersJson,
      timeoutSec: settings.asr.timeoutSec,
    };
  }
  if (provider === "tts") {
    return {
      label: "TTS",
      baseUrl: settings.tts.baseUrl,
      apiKey: settings.tts.apiKey,
      extraHeadersJson: settings.tts.extraHeadersJson,
      timeoutSec: settings.tts.timeoutSec,
    };
  }
  return {
    label: "Conversation",
    baseUrl: settings.conversation.baseUrl,
    apiKey: settings.conversation.apiKey,
    extraHeadersJson: settings.conversation.extraHeadersJson,
    timeoutSec: settings.conversation.timeoutSec,
  };
}

function statusSummary(settings: ClientSettings) {
  const chatMode =
    settings.conversation.mode === "responses" ? "Responses API" : "Chat Completions";
  return [
    `ASR ${trimUrl(settings.asr.baseUrl)}`,
    `${chatMode} ${settings.conversation.model}`,
    `TTS ${settings.tts.voice}/${settings.tts.responseFormat}`,
  ].join(" · ");
}

function validateJsonField(text: string, mode: "headers" | "object") {
  if (!text.trim()) {
    return null;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return { message: "Invalid JSON syntax.", tone: "danger" as const };
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { message: "Must be a JSON object.", tone: "danger" as const };
  }
  if (mode === "headers") {
    const invalidHeader = Object.values(parsed).some(
      (value) => value !== null && value !== undefined && typeof value === "object",
    );
    if (invalidHeader) {
      return {
        message: "Header values must be strings, numbers, booleans, or null.",
        tone: "danger" as const,
      };
    }
    return { message: "Valid headers JSON.", tone: "success" as const };
  }
  return { message: "Valid JSON object.", tone: "success" as const };
}

function hintColor(tone: "danger" | "muted" | "success") {
  if (tone === "danger") {
    return colors.danger;
  }
  if (tone === "success") {
    return colors.green;
  }
  return colors.faint;
}

function promptWithTranscript(prompt: string, transcript: string) {
  return `${prompt.trim()}\n\nTranscript:\n${transcript.trim()}`;
}

function providerTemplateSettings(settings: ClientSettings) {
  const sanitized = redactedSettings(sanitizeSettings(defaultSettings, settings));
  return {
    ...sanitized,
    asr: redactedProviderCredentials(sanitized.asr),
    conversation: redactedProviderCredentials(sanitized.conversation),
    tts: redactedProviderCredentials(sanitized.tts),
  };
}

function redactedProviderCredentials<T extends { apiKey: string; extraHeadersJson: string }>(value: T): T {
  return {
    ...value,
    apiKey: REDACTED_SETTING_VALUE,
    extraHeadersJson: REDACTED_SETTING_VALUE,
  };
}

function normalizeWorkspaceSnapshot(snapshot: Partial<WorkspaceSnapshot>): WorkspaceSnapshot {
  return {
    chatDraft: typeof snapshot.chatDraft === "string" ? snapshot.chatDraft : "",
    customProviderTemplates: Array.isArray(snapshot.customProviderTemplates)
      ? snapshot.customProviderTemplates.filter(isClientTemplate).slice(0, 30)
          .map((template) => ({
            ...template,
            settings: providerTemplateSettings(template.settings),
          }))
      : [],
    customPromptTemplates: Array.isArray(snapshot.customPromptTemplates)
      ? snapshot.customPromptTemplates.filter(isPromptTemplate).slice(0, 40)
      : [],
    messages: Array.isArray(snapshot.messages)
      ? snapshot.messages.filter(isChatMessage).slice(-80)
      : [],
    rawResult: typeof snapshot.rawResult === "string" ? snapshot.rawResult : "",
    transcript: typeof snapshot.transcript === "string" ? snapshot.transcript : "",
  };
}

function isClientTemplate(value: unknown): value is ClientTemplate {
  if (!isRecord(value)) {
    return false;
  }
  return (
    typeof value.id === "string" &&
    value.id.startsWith("custom-provider-") &&
    typeof value.name === "string" &&
    typeof value.description === "string" &&
    isStringArray(value.tags) &&
    isClientSettings(value.settings)
  );
}

function isPromptTemplate(value: unknown): value is PromptTemplate {
  if (!isRecord(value)) {
    return false;
  }
  return (
    typeof value.id === "string" &&
    value.id.startsWith("custom-") &&
    typeof value.name === "string" &&
    typeof value.category === "string" &&
    typeof value.description === "string" &&
    typeof value.prompt === "string" &&
    isStringArray(value.tags)
  );
}

function isChatMessage(value: unknown): value is ChatMessage {
  if (!isRecord(value)) {
    return false;
  }
  return (
    typeof value.id === "string" &&
    typeof value.content === "string" &&
    typeof value.createdAt === "number" &&
    (value.role === "user" || value.role === "assistant" || value.role === "system")
  );
}

function isClientSettings(value: unknown): value is ClientSettings {
  if (!isRecord(value)) {
    return false;
  }
  return (
    isAsrSettings(value.asr) &&
    isConversationSettings(value.conversation) &&
    isTtsSettings(value.tts) &&
    typeof value.autoSpeak === "boolean" &&
    typeof value.keepConversationHistory === "boolean"
  );
}

function isAsrSettings(value: unknown): value is AsrSettings {
  if (!isRecord(value)) {
    return false;
  }
  return (
    typeof value.baseUrl === "string" &&
    typeof value.apiKey === "string" &&
    typeof value.model === "string" &&
    (value.responseFormat === "json" ||
      value.responseFormat === "text" ||
      value.responseFormat === "verbose_json" ||
      value.responseFormat === "srt" ||
      value.responseFormat === "vtt") &&
    typeof value.language === "string" &&
    typeof value.prompt === "string" &&
    typeof value.temperature === "number" &&
    typeof value.timeoutSec === "number" &&
    typeof value.extraHeadersJson === "string" &&
    typeof value.extraFormFieldsJson === "string"
  );
}

function isConversationSettings(value: unknown): value is ConversationSettings {
  if (!isRecord(value)) {
    return false;
  }
  return (
    typeof value.baseUrl === "string" &&
    typeof value.apiKey === "string" &&
    (value.mode === "responses" || value.mode === "chat_completions") &&
    typeof value.model === "string" &&
    typeof value.systemPrompt === "string" &&
    typeof value.temperature === "number" &&
    typeof value.topP === "number" &&
    typeof value.frequencyPenalty === "number" &&
    typeof value.presencePenalty === "number" &&
    typeof value.maxOutputTokens === "number" &&
    typeof value.stream === "boolean" &&
    typeof value.timeoutSec === "number" &&
    typeof value.extraHeadersJson === "string" &&
    typeof value.extraBodyJson === "string"
  );
}

function isTtsSettings(value: unknown): value is TtsSettings {
  if (!isRecord(value)) {
    return false;
  }
  return (
    typeof value.baseUrl === "string" &&
    typeof value.apiKey === "string" &&
    typeof value.model === "string" &&
    typeof value.voice === "string" &&
    (value.responseFormat === "mp3" ||
      value.responseFormat === "opus" ||
      value.responseFormat === "aac" ||
      value.responseFormat === "flac" ||
      value.responseFormat === "wav" ||
      value.responseFormat === "pcm") &&
    typeof value.speed === "number" &&
    typeof value.instructions === "string" &&
    typeof value.timeoutSec === "number" &&
    typeof value.extraHeadersJson === "string" &&
    typeof value.extraBodyJson === "string"
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}
