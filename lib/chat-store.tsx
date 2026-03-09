import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useReducer,
  useRef,
} from "react";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { v4 as uuidv4 } from "uuid";

import {
  AppSettings,
  Conversation,
  DEFAULT_EFFORT,
  DEFAULT_MODEL,
  DEFAULT_SETTINGS,
  ImageAttachment,
  Message,
  ModelId,
  ReasoningEffort,
  ResponseUsage,
  normalizeModelId,
  normalizeReasoningEffort,
} from "./types";
import {
  StreamCompletionResult,
  generateTitle,
  streamChatCompletion,
} from "./openai-service";
import { deleteApiKey, getApiKey, saveApiKey } from "./secure-storage";

const CONVERSATIONS_KEY = "liquid_glass_conversations";
const SETTINGS_KEY = "liquid_glass_settings";
const DRAFT_CONVERSATION_ID = "";

interface ChatState {
  conversations: Conversation[];
  activeConversationId: string | null;
  settings: AppSettings;
  currentModel: ModelId;
  currentEffort: ReasoningEffort;
  isLoaded: boolean;
  isSending: boolean;
  streamingConversationId: string | null;
  streamingMessageId: string | null;
  lastError: string | null;
}

type ChatAction =
  | {
      type: "LOAD_STATE";
      conversations: Conversation[];
      settings: AppSettings;
      currentModel: ModelId;
      currentEffort: ReasoningEffort;
    }
  | { type: "SET_API_KEY"; apiKey: string }
  | { type: "SET_CURRENT_MODEL"; model: ModelId }
  | { type: "SET_CURRENT_EFFORT"; effort: ReasoningEffort }
  | { type: "CREATE_CONVERSATION"; conversation: Conversation }
  | { type: "SET_ACTIVE_CONVERSATION"; id: string | null }
  | { type: "DELETE_CONVERSATION"; id: string }
  | { type: "ADD_MESSAGE"; conversationId: string; message: Message }
  | { type: "UPDATE_MESSAGE"; conversationId: string; messageId: string; updates: Partial<Message> }
  | { type: "UPDATE_CONVERSATION"; conversationId: string; updates: Partial<Conversation> }
  | {
      type: "SET_STREAMING";
      isSending: boolean;
      conversationId?: string | null;
      messageId?: string | null;
      error?: string | null;
    }
  | { type: "CLEAR_ALL_CONVERSATIONS" }
  | { type: "ADD_CONVERSATION"; conversation: Conversation }
  | { type: "ADD_USER_MESSAGE"; conversationId: string; content: string; images?: ImageAttachment[] }
  | { type: "ADD_ASSISTANT_MESSAGE"; conversationId: string; messageId: string }
  | {
      type: "UPDATE_ASSISTANT_MESSAGE";
      conversationId: string;
      messageId: string;
      content?: string;
      reasoning?: string;
      isStreaming?: boolean;
    }
  | {
      type: "FINISH_ASSISTANT_MESSAGE";
      conversationId: string;
      messageId: string;
      model?: ModelId;
      effort?: ReasoningEffort;
      usage?: ResponseUsage;
    }
  | {
      type: "UPDATE_CONVERSATION_MODEL";
      conversationId: string;
      model: ModelId;
      effort: ReasoningEffort;
    }
  | { type: "UPDATE_CONVERSATION_TITLE"; conversationId: string; title: string }
  | { type: "UPDATE_SETTINGS"; settings: Partial<AppSettings> };

interface SendMessageParams {
  text: string;
  images?: ImageAttachment[];
  conversationId?: string | null;
  generateConversationTitle?: boolean;
}

interface ChatContextType {
  state: ChatState;
  dispatch: React.Dispatch<ChatAction>;
  activeConversation: Conversation | null;
  currentModel: ModelId;
  currentEffort: ReasoningEffort;
  setApiKey: (apiKey: string) => Promise<void>;
  setCurrentModel: (model: ModelId) => void;
  setCurrentEffort: (effort: ReasoningEffort) => void;
  createConversation: (options?: {
    model?: ModelId;
    effort?: ReasoningEffort;
    title?: string;
  }) => string;
  createNewConversation: (model?: ModelId, effort?: ReasoningEffort) => string;
  setActiveConversation: (id: string | null) => void;
  addMessage: (
    conversationId: string,
    message: Omit<Message, "id" | "createdAt"> & Partial<Pick<Message, "id" | "createdAt">>
  ) => string;
  updateMessage: (conversationId: string, messageId: string, updates: Partial<Message>) => void;
  deleteConversation: (id: string) => void;
  sendMessage: (params: SendMessageParams) => Promise<{
    conversationId: string;
    assistantMessageId: string;
  }>;
  stopStreaming: (conversationId?: string | null) => void;
}

const ChatContext = createContext<ChatContextType | null>(null);

const initialState: ChatState = {
  conversations: [],
  activeConversationId: null,
  settings: DEFAULT_SETTINGS,
  currentModel: DEFAULT_MODEL,
  currentEffort: DEFAULT_EFFORT,
  isLoaded: false,
  isSending: false,
  streamingConversationId: null,
  streamingMessageId: null,
  lastError: null,
};

function safeJsonParse<T>(value: string | null): T | null {
  if (!value) {
    return null;
  }

  try {
    return JSON.parse(value) as T;
  } catch {
    return null;
  }
}

function normalizeUsage(value: unknown): ResponseUsage | undefined {
  if (!value || typeof value !== "object") {
    return undefined;
  }

  const usage = value as Record<string, unknown>;
  const normalized: ResponseUsage = {};

  if (typeof usage.inputTokens === "number") {
    normalized.inputTokens = usage.inputTokens;
  }

  if (typeof usage.outputTokens === "number") {
    normalized.outputTokens = usage.outputTokens;
  }

  if (typeof usage.totalTokens === "number") {
    normalized.totalTokens = usage.totalTokens;
  }

  if (typeof usage.reasoningTokens === "number") {
    normalized.reasoningTokens = usage.reasoningTokens;
  }

  if (typeof usage.cachedInputTokens === "number") {
    normalized.cachedInputTokens = usage.cachedInputTokens;
  }

  if (
    normalized.inputTokens === undefined &&
    normalized.outputTokens === undefined &&
    normalized.totalTokens === undefined &&
    normalized.reasoningTokens === undefined &&
    normalized.cachedInputTokens === undefined
  ) {
    return undefined;
  }

  return normalized;
}

function normalizeImages(value: unknown): ImageAttachment[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const images = value
    .map((image) => {
      if (!image || typeof image !== "object") {
        return null;
      }

      const record = image as Record<string, unknown>;
      if (typeof record.uri !== "string" || record.uri.length === 0) {
        return null;
      }

      const normalized: ImageAttachment = {
        uri: record.uri,
      };

      if (typeof record.base64 === "string") normalized.base64 = record.base64;
      if (typeof record.width === "number") normalized.width = record.width;
      if (typeof record.height === "number") normalized.height = record.height;
      if (typeof record.mimeType === "string") normalized.mimeType = record.mimeType;
      if (typeof record.fileName === "string") normalized.fileName = record.fileName;

      return normalized;
    })
    .filter((image): image is ImageAttachment => image !== null);

  return images.length > 0 ? images : undefined;
}

function normalizeMessage(value: unknown): Message {
  const now = Date.now();

  if (!value || typeof value !== "object") {
    return {
      id: uuidv4(),
      role: "user",
      content: "",
      createdAt: now,
      isStreaming: false,
    };
  }

  const record = value as Record<string, unknown>;
  const model = record.model ? normalizeModelId(record.model) : undefined;
  const effort = model ? normalizeReasoningEffort(model, record.effort) : undefined;
  const role =
    record.role === "assistant" || record.role === "system" || record.role === "user"
      ? record.role
      : "user";

  return {
    id: typeof record.id === "string" && record.id.length > 0 ? record.id : uuidv4(),
    role,
    content: typeof record.content === "string" ? record.content : "",
    images: normalizeImages(record.images),
    reasoning: typeof record.reasoning === "string" ? record.reasoning : undefined,
    model,
    effort,
    usage: normalizeUsage(record.usage),
    error: typeof record.error === "string" ? record.error : undefined,
    createdAt: typeof record.createdAt === "number" ? record.createdAt : now,
    isStreaming: false,
  };
}

function sortConversations(conversations: Conversation[]): Conversation[] {
  return [...conversations].sort((a, b) => b.updatedAt - a.updatedAt);
}

function normalizeConversation(
  value: unknown,
  fallbackModel: ModelId,
  fallbackEffort: ReasoningEffort
): Conversation {
  const now = Date.now();

  if (!value || typeof value !== "object") {
    return {
      id: uuidv4(),
      title: "New Chat",
      messages: [],
      model: fallbackModel,
      effort: fallbackEffort,
      createdAt: now,
      updatedAt: now,
    };
  }

  const record = value as Record<string, unknown>;
  const model = normalizeModelId(record.model ?? fallbackModel);
  const effort = normalizeReasoningEffort(model, record.effort ?? fallbackEffort);
  const messages = Array.isArray(record.messages) ? record.messages.map(normalizeMessage) : [];
  const createdAt = typeof record.createdAt === "number" ? record.createdAt : now;
  const lastMessageTime = messages.length > 0 ? messages[messages.length - 1].createdAt : createdAt;
  const updatedAt =
    typeof record.updatedAt === "number" ? Math.max(record.updatedAt, lastMessageTime) : lastMessageTime;

  return {
    id: typeof record.id === "string" && record.id.length > 0 ? record.id : uuidv4(),
    title:
      typeof record.title === "string" && record.title.trim().length > 0
        ? record.title.trim()
        : "New Chat",
    messages,
    model,
    effort,
    createdAt,
    updatedAt,
  };
}

function patchConversation(
  conversations: Conversation[],
  conversationId: string,
  updater: (conversation: Conversation) => Conversation
): Conversation[] {
  if (!conversationId) {
    return conversations;
  }

  let changed = false;

  const nextConversations = conversations.map((conversation) => {
    if (conversation.id !== conversationId) {
      return conversation;
    }

    changed = true;
    return updater(conversation);
  });

  return changed ? sortConversations(nextConversations) : conversations;
}

function buildDraftConversation(model: ModelId, effort: ReasoningEffort): Conversation {
  return {
    id: DRAFT_CONVERSATION_ID,
    title: "New Chat",
    messages: [],
    model,
    effort,
    createdAt: 0,
    updatedAt: 0,
  };
}

function updateGlobalSelection(
  state: ChatState,
  model: ModelId,
  effortInput: ReasoningEffort | undefined,
  conversationId?: string | null
): ChatState {
  const nextModel = normalizeModelId(model);
  const nextEffort = normalizeReasoningEffort(nextModel, effortInput);

  let nextConversations = state.conversations;

  if (conversationId) {
    nextConversations = patchConversation(state.conversations, conversationId, (conversation) => ({
      ...conversation,
      model: nextModel,
      effort: nextEffort,
    }));
  }

  return {
    ...state,
    conversations: nextConversations,
    currentModel: nextModel,
    currentEffort: nextEffort,
    settings: {
      ...state.settings,
      defaultModel: nextModel,
      defaultEffort: nextEffort,
    },
  };
}

function chatReducer(state: ChatState, action: ChatAction): ChatState {
  switch (action.type) {
    case "LOAD_STATE":
      return {
        ...state,
        conversations: sortConversations(action.conversations),
        settings: action.settings,
        currentModel: action.currentModel,
        currentEffort: action.currentEffort,
        isLoaded: true,
        isSending: false,
        streamingConversationId: null,
        streamingMessageId: null,
        lastError: null,
      };

    case "SET_API_KEY":
      return {
        ...state,
        settings: {
          ...state.settings,
          apiKey: action.apiKey.trim(),
        },
      };

    case "SET_CURRENT_MODEL":
      return updateGlobalSelection(
        state,
        action.model,
        state.currentEffort,
        state.activeConversationId
      );

    case "SET_CURRENT_EFFORT":
      return updateGlobalSelection(
        state,
        state.currentModel,
        action.effort,
        state.activeConversationId
      );

    case "CREATE_CONVERSATION":
    case "ADD_CONVERSATION": {
      const normalizedConversation = normalizeConversation(
        action.conversation,
        state.currentModel,
        state.currentEffort
      );

      const conversations = sortConversations([
        normalizedConversation,
        ...state.conversations.filter((conversation) => conversation.id !== normalizedConversation.id),
      ]);

      return {
        ...state,
        conversations,
        activeConversationId: normalizedConversation.id,
        currentModel: normalizedConversation.model,
        currentEffort: normalizedConversation.effort,
      };
    }

    case "SET_ACTIVE_CONVERSATION": {
      if (!action.id) {
        return {
          ...state,
          activeConversationId: null,
          currentModel: state.settings.defaultModel,
          currentEffort: state.settings.defaultEffort,
        };
      }

      const conversation =
        state.conversations.find((item) => item.id === action.id) ?? null;

      if (!conversation) {
        return {
          ...state,
          activeConversationId: action.id,
        };
      }

      return {
        ...state,
        activeConversationId: action.id,
        currentModel: conversation.model,
        currentEffort: conversation.effort,
      };
    }

    case "DELETE_CONVERSATION": {
      const nextConversations = state.conversations.filter(
        (conversation) => conversation.id !== action.id
      );
      const deletingActive = state.activeConversationId === action.id;

      return {
        ...state,
        conversations: nextConversations,
        activeConversationId: deletingActive ? null : state.activeConversationId,
        currentModel: deletingActive ? state.settings.defaultModel : state.currentModel,
        currentEffort: deletingActive ? state.settings.defaultEffort : state.currentEffort,
        streamingConversationId:
          state.streamingConversationId === action.id ? null : state.streamingConversationId,
        streamingMessageId:
          state.streamingConversationId === action.id ? null : state.streamingMessageId,
        isSending: state.streamingConversationId === action.id ? false : state.isSending,
      };
    }

    case "ADD_MESSAGE": {
      const message = normalizeMessage(action.message);
      const selectionModel = message.model ?? state.currentModel;
      const selectionEffort = normalizeReasoningEffort(
        selectionModel,
        message.effort ?? state.currentEffort
      );

      return {
        ...state,
        conversations: patchConversation(state.conversations, action.conversationId, (conversation) => ({
          ...conversation,
          model: selectionModel,
          effort: selectionEffort,
          messages: [...conversation.messages, message],
          updatedAt: Date.now(),
        })),
      };
    }

    case "UPDATE_MESSAGE":
      return {
        ...state,
        conversations: patchConversation(state.conversations, action.conversationId, (conversation) => ({
          ...conversation,
          messages: conversation.messages.map((message) => {
            if (message.id !== action.messageId) {
              return message;
            }

            const mergedMessage: Message = {
              ...message,
              ...action.updates,
            };

            if (action.updates.images !== undefined) {
              mergedMessage.images = normalizeImages(action.updates.images);
            }

            if (action.updates.usage !== undefined) {
              mergedMessage.usage = normalizeUsage(action.updates.usage);
            }

            if (mergedMessage.model) {
              mergedMessage.model = normalizeModelId(mergedMessage.model);
              mergedMessage.effort = normalizeReasoningEffort(
                mergedMessage.model,
                mergedMessage.effort
              );
            }

            return mergedMessage;
          }),
          updatedAt: Date.now(),
        })),
      };

    case "UPDATE_CONVERSATION":
      return {
        ...state,
        conversations: patchConversation(state.conversations, action.conversationId, (conversation) => {
          const nextModel = action.updates.model
            ? normalizeModelId(action.updates.model)
            : conversation.model;
          const nextEffort = normalizeReasoningEffort(
            nextModel,
            action.updates.effort ?? conversation.effort
          );

          return {
            ...conversation,
            ...action.updates,
            model: nextModel,
            effort: nextEffort,
            title:
              typeof action.updates.title === "string" && action.updates.title.trim().length > 0
                ? action.updates.title.trim()
                : conversation.title,
            messages: Array.isArray(action.updates.messages)
              ? action.updates.messages.map(normalizeMessage)
              : conversation.messages,
            updatedAt:
              typeof action.updates.updatedAt === "number"
                ? action.updates.updatedAt
                : conversation.updatedAt,
          };
        }),
      };

    case "SET_STREAMING":
      return {
        ...state,
        isSending: action.isSending,
        streamingConversationId: action.conversationId ?? null,
        streamingMessageId: action.messageId ?? null,
        lastError: action.error ?? null,
      };

    case "ADD_USER_MESSAGE": {
      const message: Message = {
        id: uuidv4(),
        role: "user",
        content: action.content,
        images: normalizeImages(action.images),
        model: state.currentModel,
        effort: state.currentEffort,
        createdAt: Date.now(),
        isStreaming: false,
      };

      return {
        ...state,
        conversations: patchConversation(state.conversations, action.conversationId, (conversation) => ({
          ...conversation,
          model: state.currentModel,
          effort: state.currentEffort,
          messages: [...conversation.messages, message],
          updatedAt: Date.now(),
        })),
      };
    }

    case "ADD_ASSISTANT_MESSAGE": {
      const assistantMessage: Message = {
        id: action.messageId,
        role: "assistant",
        content: "",
        model: state.currentModel,
        effort: state.currentEffort,
        createdAt: Date.now(),
        isStreaming: true,
      };

      return {
        ...state,
        conversations: patchConversation(state.conversations, action.conversationId, (conversation) => ({
          ...conversation,
          model: state.currentModel,
          effort: state.currentEffort,
          messages: [...conversation.messages, assistantMessage],
          updatedAt: Date.now(),
        })),
      };
    }

    case "UPDATE_ASSISTANT_MESSAGE":
      return {
        ...state,
        conversations: patchConversation(state.conversations, action.conversationId, (conversation) => ({
          ...conversation,
          messages: conversation.messages.map((message) => {
            if (message.id !== action.messageId) {
              return message;
            }

            const nextContent =
              action.content === undefined
                ? message.content
                : action.content === "" && action.reasoning !== undefined
                  ? message.content
                  : action.content;

            return {
              ...message,
              content: nextContent,
              reasoning:
                action.reasoning === undefined ? message.reasoning : action.reasoning,
              isStreaming:
                action.isStreaming === undefined ? message.isStreaming : action.isStreaming,
            };
          }),
          updatedAt: Date.now(),
        })),
      };

    case "FINISH_ASSISTANT_MESSAGE": {
      const finalModel = normalizeModelId(action.model ?? state.currentModel);
      const finalEffort = normalizeReasoningEffort(
        finalModel,
        action.effort ?? state.currentEffort
      );

      return {
        ...state,
        conversations: patchConversation(state.conversations, action.conversationId, (conversation) => ({
          ...conversation,
          model: finalModel,
          effort: finalEffort,
          messages: conversation.messages.map((message) =>
            message.id === action.messageId
              ? {
                  ...message,
                  isStreaming: false,
                  model: finalModel,
                  effort: finalEffort,
                  usage: action.usage ?? message.usage,
                }
              : message
          ),
          updatedAt: Date.now(),
        })),
      };
    }

    case "UPDATE_CONVERSATION_MODEL":
      return updateGlobalSelection(
        state,
        action.model,
        action.effort,
        action.conversationId || null
      );

    case "UPDATE_CONVERSATION_TITLE":
      return {
        ...state,
        conversations: patchConversation(state.conversations, action.conversationId, (conversation) => ({
          ...conversation,
          title:
            action.title.trim().length > 0 ? action.title.trim() : conversation.title,
        })),
      };

    case "UPDATE_SETTINGS": {
      const nextApiKey =
        action.settings.apiKey === undefined
          ? state.settings.apiKey
          : action.settings.apiKey.trim();

      const nextDefaultModel = normalizeModelId(
        action.settings.defaultModel ?? state.settings.defaultModel
      );
      const nextDefaultEffort = normalizeReasoningEffort(
        nextDefaultModel,
        action.settings.defaultEffort ?? state.settings.defaultEffort
      );

      const shouldSyncDraftSelection = state.activeConversationId === null;

      return {
        ...state,
        settings: {
          ...state.settings,
          ...action.settings,
          apiKey: nextApiKey,
          defaultModel: nextDefaultModel,
          defaultEffort: nextDefaultEffort,
        },
        currentModel: shouldSyncDraftSelection ? nextDefaultModel : state.currentModel,
        currentEffort: shouldSyncDraftSelection ? nextDefaultEffort : state.currentEffort,
      };
    }

    case "CLEAR_ALL_CONVERSATIONS":
      return {
        ...state,
        conversations: [],
        activeConversationId: null,
        currentModel: state.settings.defaultModel,
        currentEffort: state.settings.defaultEffort,
        isSending: false,
        streamingConversationId: null,
        streamingMessageId: null,
        lastError: null,
      };

    default:
      return state;
  }
}

function createFallbackTitle(text: string, images?: ImageAttachment[]): string {
  const trimmedText = text.trim();

  if (trimmedText.length > 0) {
    const singleLine = trimmedText.replace(/\s+/g, " ").trim();
    return singleLine.length <= 40 ? singleLine : `${singleLine.slice(0, 37).trim()}…`;
  }

  if (images && images.length > 0) {
    return "Image Chat";
  }

  return "New Chat";
}

function buildErrorMessage(existingText: string, errorMessage: string): string {
  const trimmedExisting = existingText.trim();
  const trimmedError = errorMessage.trim();

  if (!trimmedExisting) {
    return `⚠️ ${trimmedError}`;
  }

  return `${trimmedExisting}\n\n⚠️ ${trimmedError}`;
}

export function ChatProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(chatReducer, initialState);
  const stateRef = useRef(state);
  const controllersRef = useRef<Map<string, AbortController>>(new Map());
  const lastPersistedApiKeyRef = useRef<string>("");

  stateRef.current = state;

  useEffect(() => {
    let isMounted = true;

    const loadState = async () => {
      try {
        const [conversationsJson, settingsJson, secureApiKey] = await Promise.all([
          AsyncStorage.getItem(CONVERSATIONS_KEY),
          AsyncStorage.getItem(SETTINGS_KEY),
          getApiKey(),
        ]);

        const parsedSettings = safeJsonParse<Partial<AppSettings>>(settingsJson) ?? {};
        const legacyApiKey =
          typeof parsedSettings.apiKey === "string" ? parsedSettings.apiKey.trim() : "";
        const resolvedApiKey = (secureApiKey ?? legacyApiKey).trim();

        if (!secureApiKey && legacyApiKey) {
          try {
            await saveApiKey(legacyApiKey);
          } catch (error) {
            console.error("Failed to migrate API key to secure storage:", error);
          }
        }

        const loadedModel = normalizeModelId(parsedSettings.defaultModel ?? DEFAULT_MODEL);
        const loadedEffort = normalizeReasoningEffort(
          loadedModel,
          parsedSettings.defaultEffort ?? DEFAULT_EFFORT
        );

        const settings: AppSettings = {
          ...DEFAULT_SETTINGS,
          ...parsedSettings,
          apiKey: resolvedApiKey,
          defaultModel: loadedModel,
          defaultEffort: loadedEffort,
        };

        const parsedConversations = safeJsonParse<unknown[]>(conversationsJson);
        const conversations = Array.isArray(parsedConversations)
          ? parsedConversations.map((conversation) =>
              normalizeConversation(conversation, loadedModel, loadedEffort)
            )
          : [];

        lastPersistedApiKeyRef.current = resolvedApiKey;

        if (!isMounted) {
          return;
        }

        dispatch({
          type: "LOAD_STATE",
          conversations,
          settings,
          currentModel: loadedModel,
          currentEffort: loadedEffort,
        });
      } catch (error) {
        console.error("Failed to load chat state:", error);

        if (!isMounted) {
          return;
        }

        dispatch({
          type: "LOAD_STATE",
          conversations: [],
          settings: DEFAULT_SETTINGS,
          currentModel: DEFAULT_MODEL,
          currentEffort: DEFAULT_EFFORT,
        });
      }
    };

    void loadState();

    return () => {
      isMounted = false;

      for (const controller of controllersRef.current.values()) {
        controller.abort();
      }

      controllersRef.current.clear();
    };
  }, []);

  useEffect(() => {
    if (!state.isLoaded) {
      return;
    }

    void AsyncStorage.setItem(CONVERSATIONS_KEY, JSON.stringify(state.conversations)).catch((error) => {
      console.error("Failed to persist conversations:", error);
    });
  }, [state.conversations, state.isLoaded]);

  useEffect(() => {
    if (!state.isLoaded) {
      return;
    }

    const persistedSettings = {
      defaultModel: state.settings.defaultModel,
      defaultEffort: state.settings.defaultEffort,
      theme: state.settings.theme,
    };

    void AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify(persistedSettings)).catch((error) => {
      console.error("Failed to persist settings:", error);
    });
  }, [
    state.settings.defaultEffort,
    state.settings.defaultModel,
    state.settings.theme,
    state.isLoaded,
  ]);

  useEffect(() => {
    if (!state.isLoaded) {
      return;
    }

    const currentApiKey = state.settings.apiKey.trim();

    if (lastPersistedApiKeyRef.current === currentApiKey) {
      return;
    }

    lastPersistedApiKeyRef.current = currentApiKey;

    const persistApiKey = async () => {
      try {
        if (currentApiKey) {
          await saveApiKey(currentApiKey);
        } else {
          await deleteApiKey();
        }
      } catch (error) {
        console.error("Failed to persist API key:", error);
      }
    };

    void persistApiKey();
  }, [state.settings.apiKey, state.isLoaded]);

  const rawActiveConversation = useMemo(() => {
    if (!state.activeConversationId) {
      return null;
    }

    return (
      state.conversations.find((conversation) => conversation.id === state.activeConversationId) ??
      null
    );
  }, [state.activeConversationId, state.conversations]);

  const activeConversation = useMemo<Conversation | null>(() => {
    if (!rawActiveConversation) {
      return buildDraftConversation(state.currentModel, state.currentEffort);
    }

    return rawActiveConversation;
  }, [rawActiveConversation, state.currentEffort, state.currentModel]);

  const setApiKey = useCallback(async (apiKey: string) => {
    const normalizedApiKey = apiKey.trim();

    if (normalizedApiKey) {
      await saveApiKey(normalizedApiKey);
    } else {
      await deleteApiKey();
    }

    lastPersistedApiKeyRef.current = normalizedApiKey;
    dispatch({ type: "SET_API_KEY", apiKey: normalizedApiKey });
  }, []);

  const setCurrentModel = useCallback((model: ModelId) => {
    dispatch({ type: "SET_CURRENT_MODEL", model });
  }, []);

  const setCurrentEffort = useCallback((effort: ReasoningEffort) => {
    dispatch({ type: "SET_CURRENT_EFFORT", effort });
  }, []);

  const createConversation = useCallback(
    (options?: { model?: ModelId; effort?: ReasoningEffort; title?: string }) => {
      const currentState = stateRef.current;
      const model = normalizeModelId(options?.model ?? currentState.currentModel);
      const effort = normalizeReasoningEffort(
        model,
        options?.effort ?? currentState.currentEffort
      );
      const now = Date.now();

      const conversation: Conversation = {
        id: uuidv4(),
        title: options?.title?.trim() || "New Chat",
        messages: [],
        model,
        effort,
        createdAt: now,
        updatedAt: now,
      };

      dispatch({ type: "CREATE_CONVERSATION", conversation });
      return conversation.id;
    },
    []
  );

  const createNewConversation = useCallback(
    (model?: ModelId, effort?: ReasoningEffort) => {
      return createConversation({ model, effort });
    },
    [createConversation]
  );

  const setActiveConversation = useCallback((id: string | null) => {
    dispatch({ type: "SET_ACTIVE_CONVERSATION", id });
  }, []);

  const addMessage = useCallback(
    (
      conversationId: string,
      message: Omit<Message, "id" | "createdAt"> & Partial<Pick<Message, "id" | "createdAt">>
    ) => {
      const preparedModel = message.model ? normalizeModelId(message.model) : undefined;
      const preparedMessage: Message = {
        id: message.id ?? uuidv4(),
        role: message.role,
        content: message.content ?? "",
        images: normalizeImages(message.images),
        reasoning: message.reasoning,
        model: preparedModel,
        effort: preparedModel
          ? normalizeReasoningEffort(preparedModel, message.effort)
          : undefined,
        usage: normalizeUsage(message.usage),
        error: message.error,
        createdAt: message.createdAt ?? Date.now(),
        isStreaming: message.isStreaming ?? false,
      };

      dispatch({ type: "ADD_MESSAGE", conversationId, message: preparedMessage });
      return preparedMessage.id;
    },
    []
  );

  const updateMessage = useCallback(
    (conversationId: string, messageId: string, updates: Partial<Message>) => {
      dispatch({ type: "UPDATE_MESSAGE", conversationId, messageId, updates });
    },
    []
  );

  const stopStreaming = useCallback((conversationId?: string | null) => {
    const currentState = stateRef.current;
    const targetConversationId =
      conversationId ?? currentState.streamingConversationId ?? currentState.activeConversationId;

    if (!targetConversationId) {
      return;
    }

    const controller = controllersRef.current.get(targetConversationId);
    if (!controller) {
      return;
    }

    controller.abort();
  }, []);

  const deleteConversation = useCallback((id: string) => {
    const controller = controllersRef.current.get(id);

    if (controller) {
      controller.abort();
      controllersRef.current.delete(id);
    }

    dispatch({ type: "DELETE_CONVERSATION", id });
  }, []);

  const sendMessage = useCallback(
    async (params: SendMessageParams) => {
      const currentState = stateRef.current;
      const text = params.text.trim();
      const images = params.images?.filter((image) => !!image?.uri) ?? [];

      if (!text && images.length === 0) {
        throw new Error("Message cannot be empty.");
      }

      const apiKey = currentState.settings.apiKey.trim();
      if (!apiKey) {
        throw new Error("Missing OpenAI API key.");
      }

      let conversationId = params.conversationId ?? currentState.activeConversationId;
      const model = currentState.currentModel;
      const effort = normalizeReasoningEffort(model, currentState.currentEffort);

      const existingConversation =
        conversationId && conversationId.length > 0
          ? currentState.conversations.find((conversation) => conversation.id === conversationId) ??
            null
          : null;

      if (!conversationId || !existingConversation) {
        conversationId = createConversation({ model, effort });
      } else {
        dispatch({ type: "SET_ACTIVE_CONVERSATION", id: conversationId });
      }

      const targetConversationId = conversationId;
      const previousConversation =
        stateRef.current.conversations.find((conversation) => conversation.id === targetConversationId) ??
        null;
      const hadNoMessages = !previousConversation || previousConversation.messages.length === 0;

      dispatch({
        type: "UPDATE_CONVERSATION_MODEL",
        conversationId: targetConversationId,
        model,
        effort,
      });

      const userMessage: Message = {
        id: uuidv4(),
        role: "user",
        content: text,
        images,
        model,
        effort,
        createdAt: Date.now(),
        isStreaming: false,
      };

      const assistantMessageId = uuidv4();
      const assistantMessage: Message = {
        id: assistantMessageId,
        role: "assistant",
        content: "",
        model,
        effort,
        createdAt: Date.now(),
        isStreaming: true,
      };

      dispatch({
        type: "ADD_MESSAGE",
        conversationId: targetConversationId,
        message: userMessage,
      });

      dispatch({
        type: "ADD_MESSAGE",
        conversationId: targetConversationId,
        message: assistantMessage,
      });

      dispatch({
        type: "SET_STREAMING",
        isSending: true,
        conversationId: targetConversationId,
        messageId: assistantMessageId,
        error: null,
      });

      const oldController = controllersRef.current.get(targetConversationId);
      if (oldController) {
        oldController.abort();
      }

      const abortController = new AbortController();
      controllersRef.current.set(targetConversationId, abortController);

      const historyMessages = [...(previousConversation?.messages ?? []), userMessage];

      if (hadNoMessages) {
        const fallbackTitle = createFallbackTitle(text, images);
        if (fallbackTitle !== "New Chat") {
          dispatch({
            type: "UPDATE_CONVERSATION_TITLE",
            conversationId: targetConversationId,
            title: fallbackTitle,
          });
        }

        if ((params.generateConversationTitle ?? true) && text.length > 0) {
          void generateTitle(apiKey, text)
            .then((title) => {
              if (title && title !== "New Chat") {
                dispatch({
                  type: "UPDATE_CONVERSATION_TITLE",
                  conversationId: targetConversationId,
                  title,
                });
              }
            })
            .catch(() => undefined);
        }
      }

      let finalized = false;

      const finalizeSuccess = (result?: StreamCompletionResult) => {
        if (finalized) {
          return;
        }

        finalized = true;
        controllersRef.current.delete(targetConversationId);

        const updates: Partial<Message> = {
          isStreaming: false,
          model,
          effort,
          usage: result?.usage,
          error: undefined,
        };

        if (typeof result?.outputText === "string") {
          updates.content = result.outputText;
        }

        if (typeof result?.reasoning === "string" && result.reasoning.length > 0) {
          updates.reasoning = result.reasoning;
        }

        dispatch({
          type: "UPDATE_MESSAGE",
          conversationId: targetConversationId,
          messageId: assistantMessageId,
          updates,
        });

        dispatch({
          type: "SET_STREAMING",
          isSending: false,
          conversationId: null,
          messageId: null,
          error: null,
        });
      };

      const finalizeError = (errorMessage: string) => {
        if (finalized) {
          return;
        }

        finalized = true;
        controllersRef.current.delete(targetConversationId);

        const latestConversation =
          stateRef.current.conversations.find(
            (conversation) => conversation.id === targetConversationId
          ) ?? null;
        const latestAssistantMessage =
          latestConversation?.messages.find((message) => message.id === assistantMessageId) ?? null;

        dispatch({
          type: "UPDATE_MESSAGE",
          conversationId: targetConversationId,
          messageId: assistantMessageId,
          updates: {
            content: buildErrorMessage(latestAssistantMessage?.content ?? "", errorMessage),
            isStreaming: false,
            model,
            effort,
            error: errorMessage,
          },
        });

        dispatch({
          type: "SET_STREAMING",
          isSending: false,
          conversationId: null,
          messageId: null,
          error: errorMessage,
        });
      };

      const runStream = async () => {
        try {
          const result = await streamChatCompletion(
            apiKey,
            historyMessages,
            model,
            effort,
            {
              onToken: (fullText) => {
                updateMessage(targetConversationId, assistantMessageId, {
                  content: fullText,
                  isStreaming: true,
                  model,
                  effort,
                });
              },
              onReasoning: (fullReasoning) => {
                updateMessage(targetConversationId, assistantMessageId, {
                  reasoning: fullReasoning,
                  isStreaming: true,
                });
              },
              onDone: (resultFromCallback) => {
                finalizeSuccess(resultFromCallback);
              },
              onError: (errorMessage) => {
                finalizeError(errorMessage);
              },
            },
            abortController.signal
          );

          if (!finalized) {
            finalizeSuccess(result);
          }
        } catch (error) {
          const message =
            error instanceof Error && error.message.trim().length > 0
              ? error.message.trim()
              : "Unknown error";
          finalizeError(message);
        }
      };

      void runStream();

      return {
        conversationId: targetConversationId,
        assistantMessageId,
      };
    },
    [createConversation, updateMessage]
  );

  const value = useMemo<ChatContextType>(
    () => ({
      state,
      dispatch,
      activeConversation,
      currentModel: state.currentModel,
      currentEffort: state.currentEffort,
      setApiKey,
      setCurrentModel,
      setCurrentEffort,
      createConversation,
      createNewConversation,
      setActiveConversation,
      addMessage,
      updateMessage,
      deleteConversation,
      sendMessage,
      stopStreaming,
    }),
    [
      activeConversation,
      addMessage,
      createConversation,
      createNewConversation,
      deleteConversation,
      sendMessage,
      setActiveConversation,
      setApiKey,
      setCurrentEffort,
      setCurrentModel,
      state,
      stopStreaming,
      updateMessage,
    ]
  );

  return <ChatContext.Provider value={value}>{children}</ChatContext.Provider>;
}

export function useChatStore() {
  const context = useContext(ChatContext);

  if (!context) {
    throw new Error("useChatStore must be used within ChatProvider");
  }

  return context;
}
