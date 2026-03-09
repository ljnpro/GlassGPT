import React, { createContext, useContext, useReducer, useEffect, useCallback, useRef } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { v4 as uuidv4 } from 'uuid';
import {
  Conversation,
  Message,
  ModelId,
  ReasoningEffort,
  AppSettings,
  DEFAULT_SETTINGS,
  DEFAULT_MODEL,
  DEFAULT_EFFORT,
  ImageAttachment,
} from './types';

const CONVERSATIONS_KEY = 'liquid_glass_conversations';
const SETTINGS_KEY = 'liquid_glass_settings';

interface ChatState {
  conversations: Conversation[];
  activeConversationId: string | null;
  settings: AppSettings;
  isLoaded: boolean;
}

type ChatAction =
  | { type: 'LOAD_STATE'; conversations: Conversation[]; settings: AppSettings }
  | { type: 'NEW_CONVERSATION'; model: ModelId; effort: ReasoningEffort }
  | { type: 'SET_ACTIVE_CONVERSATION'; id: string | null }
  | { type: 'DELETE_CONVERSATION'; id: string }
  | { type: 'ADD_USER_MESSAGE'; conversationId: string; content: string; images?: ImageAttachment[] }
  | { type: 'ADD_ASSISTANT_MESSAGE'; conversationId: string; messageId: string }
  | { type: 'UPDATE_ASSISTANT_MESSAGE'; conversationId: string; messageId: string; content: string; reasoning?: string; isStreaming?: boolean }
  | { type: 'FINISH_ASSISTANT_MESSAGE'; conversationId: string; messageId: string; model?: ModelId; effort?: ReasoningEffort }
  | { type: 'UPDATE_CONVERSATION_MODEL'; conversationId: string; model: ModelId; effort: ReasoningEffort }
  | { type: 'UPDATE_CONVERSATION_TITLE'; conversationId: string; title: string }
  | { type: 'UPDATE_SETTINGS'; settings: Partial<AppSettings> }
  | { type: 'CLEAR_ALL_CONVERSATIONS' };

function chatReducer(state: ChatState, action: ChatAction): ChatState {
  switch (action.type) {
    case 'LOAD_STATE':
      return { ...state, conversations: action.conversations, settings: action.settings, isLoaded: true };

    case 'NEW_CONVERSATION': {
      const newConv: Conversation = {
        id: uuidv4(),
        title: 'New Chat',
        messages: [],
        model: action.model,
        effort: action.effort,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      return {
        ...state,
        conversations: [newConv, ...state.conversations],
        activeConversationId: newConv.id,
      };
    }

    case 'SET_ACTIVE_CONVERSATION':
      return { ...state, activeConversationId: action.id };

    case 'DELETE_CONVERSATION': {
      const filtered = state.conversations.filter((c) => c.id !== action.id);
      return {
        ...state,
        conversations: filtered,
        activeConversationId: state.activeConversationId === action.id ? null : state.activeConversationId,
      };
    }

    case 'ADD_USER_MESSAGE': {
      const msg: Message = {
        id: uuidv4(),
        role: 'user',
        content: action.content,
        images: action.images,
        createdAt: Date.now(),
      };
      return {
        ...state,
        conversations: state.conversations.map((c) =>
          c.id === action.conversationId
            ? { ...c, messages: [...c.messages, msg], updatedAt: Date.now() }
            : c
        ),
      };
    }

    case 'ADD_ASSISTANT_MESSAGE': {
      const assistantMsg: Message = {
        id: action.messageId,
        role: 'assistant',
        content: '',
        createdAt: Date.now(),
        isStreaming: true,
      };
      return {
        ...state,
        conversations: state.conversations.map((c) =>
          c.id === action.conversationId
            ? { ...c, messages: [...c.messages, assistantMsg], updatedAt: Date.now() }
            : c
        ),
      };
    }

    case 'UPDATE_ASSISTANT_MESSAGE': {
      return {
        ...state,
        conversations: state.conversations.map((c) =>
          c.id === action.conversationId
            ? {
                ...c,
                messages: c.messages.map((m) =>
                  m.id === action.messageId
                    ? {
                        ...m,
                        content: action.content,
                        reasoning: action.reasoning ?? m.reasoning,
                        isStreaming: action.isStreaming ?? m.isStreaming,
                      }
                    : m
                ),
                updatedAt: Date.now(),
              }
            : c
        ),
      };
    }

    case 'FINISH_ASSISTANT_MESSAGE': {
      return {
        ...state,
        conversations: state.conversations.map((c) =>
          c.id === action.conversationId
            ? {
                ...c,
                messages: c.messages.map((m) =>
                  m.id === action.messageId
                    ? { ...m, isStreaming: false, model: action.model, effort: action.effort }
                    : m
                ),
                updatedAt: Date.now(),
              }
            : c
        ),
      };
    }

    case 'UPDATE_CONVERSATION_MODEL': {
      return {
        ...state,
        conversations: state.conversations.map((c) =>
          c.id === action.conversationId
            ? { ...c, model: action.model, effort: action.effort }
            : c
        ),
      };
    }

    case 'UPDATE_CONVERSATION_TITLE': {
      return {
        ...state,
        conversations: state.conversations.map((c) =>
          c.id === action.conversationId ? { ...c, title: action.title } : c
        ),
      };
    }

    case 'UPDATE_SETTINGS':
      return { ...state, settings: { ...state.settings, ...action.settings } };

    case 'CLEAR_ALL_CONVERSATIONS':
      return { ...state, conversations: [], activeConversationId: null };

    default:
      return state;
  }
}

const initialState: ChatState = {
  conversations: [],
  activeConversationId: null,
  settings: DEFAULT_SETTINGS,
  isLoaded: false,
};

interface ChatContextType {
  state: ChatState;
  dispatch: React.Dispatch<ChatAction>;
  activeConversation: Conversation | null;
  createNewConversation: (model?: ModelId, effort?: ReasoningEffort) => string;
  deleteConversation: (id: string) => void;
  setActiveConversation: (id: string | null) => void;
}

const ChatContext = createContext<ChatContextType | null>(null);

export function ChatProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(chatReducer, initialState);
  const stateRef = useRef(state);
  stateRef.current = state;

  // Load persisted state
  useEffect(() => {
    (async () => {
      try {
        const [convJson, settingsJson] = await Promise.all([
          AsyncStorage.getItem(CONVERSATIONS_KEY),
          AsyncStorage.getItem(SETTINGS_KEY),
        ]);
        const conversations = convJson ? JSON.parse(convJson) : [];
        const settings = settingsJson ? { ...DEFAULT_SETTINGS, ...JSON.parse(settingsJson) } : DEFAULT_SETTINGS;
        dispatch({ type: 'LOAD_STATE', conversations, settings });
      } catch (e) {
        console.error('Failed to load state:', e);
        dispatch({ type: 'LOAD_STATE', conversations: [], settings: DEFAULT_SETTINGS });
      }
    })();
  }, []);

  // Persist on changes
  useEffect(() => {
    if (!state.isLoaded) return;
    AsyncStorage.setItem(CONVERSATIONS_KEY, JSON.stringify(state.conversations)).catch(console.error);
  }, [state.conversations, state.isLoaded]);

  useEffect(() => {
    if (!state.isLoaded) return;
    AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify(state.settings)).catch(console.error);
  }, [state.settings, state.isLoaded]);

  const activeConversation = state.activeConversationId
    ? state.conversations.find((c) => c.id === state.activeConversationId) ?? null
    : null;

  const createNewConversation = useCallback(
    (model?: ModelId, effort?: ReasoningEffort) => {
      const m = model ?? stateRef.current.settings.defaultModel ?? DEFAULT_MODEL;
      const e = effort ?? stateRef.current.settings.defaultEffort ?? DEFAULT_EFFORT;
      const id = uuidv4();
      const newConv: Conversation = {
        id,
        title: 'New Chat',
        messages: [],
        model: m,
        effort: e,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      dispatch({
        type: 'LOAD_STATE',
        conversations: [newConv, ...stateRef.current.conversations],
        settings: stateRef.current.settings,
      });
      dispatch({ type: 'SET_ACTIVE_CONVERSATION', id });
      return id;
    },
    []
  );

  const deleteConversation = useCallback((id: string) => {
    dispatch({ type: 'DELETE_CONVERSATION', id });
  }, []);

  const setActiveConversation = useCallback((id: string | null) => {
    dispatch({ type: 'SET_ACTIVE_CONVERSATION', id });
  }, []);

  return (
    <ChatContext.Provider
      value={{ state, dispatch, activeConversation, createNewConversation, deleteConversation, setActiveConversation }}
    >
      {children}
    </ChatContext.Provider>
  );
}

export function useChatStore() {
  const ctx = useContext(ChatContext);
  if (!ctx) throw new Error('useChatStore must be used within ChatProvider');
  return ctx;
}
