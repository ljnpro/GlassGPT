import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import MaterialIcons from "@expo/vector-icons/MaterialIcons";
import { ScreenContainer } from "@/components/screen-container";
import { ChatInput } from "@/components/chat-input";
import { GlassCard } from "@/components/glass-card";
import { MessageBubble } from "@/components/message-bubble";
import { ModelSelector } from "@/components/model-selector";
import { useColors } from "@/hooks/use-colors";
import { useChatStore } from "@/lib/chat-store";
import { generateTitle, streamChatCompletion } from "@/lib/openai-service";
import { ImageAttachment, Message, MODELS } from "@/lib/types";
import { v4 as uuidv4 } from "uuid";

export default function ChatScreen() {
  const colors = useColors();
  const router = useRouter();
  const {
    state,
    dispatch,
    activeConversation,
    createNewConversation,
    setActiveConversation,
    currentModel,
    currentEffort,
    setCurrentModel,
    setCurrentEffort,
  } = useChatStore();

  const listRef = useRef<FlatList<Message>>(null);
  const abortRef = useRef<AbortController | null>(null);
  const latestStateRef = useRef(state);
  const stopRequestedRef = useRef(false);
  const latestAssistantTextRef = useRef("");
  const latestAssistantReasoningRef = useRef("");
  const [isStreaming, setIsStreaming] = useState(false);

  latestStateRef.current = state;

  useEffect(() => {
    return () => {
      abortRef.current?.abort();
    };
  }, []);

  useEffect(() => {
    if (activeConversation?.id && activeConversation.messages.length > 0) {
      requestAnimationFrame(() => {
        listRef.current?.scrollToOffset({ offset: 0, animated: false });
      });
    }
  }, [activeConversation?.id, activeConversation?.messages.length]);

  const messages = activeConversation?.messages ?? [];
  const reversedMessages = useMemo(() => [...messages].reverse(), [messages]);
  const hasApiKey = state.settings.apiKey.trim().length > 0;
  const isLoaded = state.isLoaded;
  const currentModelConfig = MODELS.find((item) => item.id === currentModel) ?? MODELS[0];

  const handleNewChat = useCallback(() => {
    if (isStreaming) {
      return;
    }

    if (Platform.OS !== "web") {
      void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    }

    setActiveConversation(null);
  }, [currentEffort, currentModel, dispatch, isStreaming, setActiveConversation]);

  const handleOpenSettings = useCallback(() => {
    router.navigate("/(tabs)/settings");
  }, [router]);

  const handleSend = useCallback(
    async (text: string, images?: ImageAttachment[]) => {
      const trimmed = text.trim();
      const apiKey = latestStateRef.current.settings.apiKey.trim();

      if (!trimmed && (!images || images.length === 0)) {
        return;
      }

      if (!apiKey) {
        router.navigate("/(tabs)/settings");
        return;
      }

      const modelAtSend = currentModel;
      const effortAtSend = currentEffort;

      let conversationId = activeConversation?.id ?? null;
      if (!conversationId) {
        conversationId = createNewConversation(modelAtSend, effortAtSend);
      }

      const existingConversation =
        latestStateRef.current.conversations.find((item) => item.id === conversationId) ?? null;
      const existingMessages = existingConversation?.messages ?? [];
      const shouldGenerateTitle = existingMessages.length === 0;

      const userMessage: Message = {
        id: uuidv4(),
        role: "user",
        content: trimmed,
        images,
        createdAt: Date.now(),
      };

      dispatch({
        type: "ADD_USER_MESSAGE",
        conversationId,
        content: trimmed,
        images,
      });

      const assistantMessageId = uuidv4();
      dispatch({
        type: "ADD_ASSISTANT_MESSAGE",
        conversationId,
        messageId: assistantMessageId,
      });

      requestAnimationFrame(() => {
        listRef.current?.scrollToOffset({ offset: 0, animated: true });
      });

      stopRequestedRef.current = false;
      latestAssistantTextRef.current = "";
      latestAssistantReasoningRef.current = "";
      setIsStreaming(true);

      const abortController = new AbortController();
      abortRef.current = abortController;

      const requestMessages: Message[] = [...existingMessages, userMessage];

      if (shouldGenerateTitle && trimmed.length > 0) {
        void (async () => {
          const title = await generateTitle(apiKey, trimmed);
          dispatch({
            type: "UPDATE_CONVERSATION_TITLE",
            conversationId: conversationId!,
            title: title || "New Chat",
          });
        })();
      }

      try {
        await streamChatCompletion(
          apiKey,
          requestMessages,
          modelAtSend,
          effortAtSend,
          {
            onToken: (fullText) => {
              latestAssistantTextRef.current = fullText;
              dispatch({
                type: "UPDATE_ASSISTANT_MESSAGE",
                conversationId: conversationId!,
                messageId: assistantMessageId,
                content: fullText,
                isStreaming: true,
              });
            },
            onReasoning: (fullReasoning) => {
              latestAssistantReasoningRef.current = fullReasoning;
              dispatch({
                type: "UPDATE_ASSISTANT_MESSAGE",
                conversationId: conversationId!,
                messageId: assistantMessageId,
                content: "",
                reasoning: fullReasoning,
                isStreaming: true,
              });
            },
            onDone: () => {
              if (
                stopRequestedRef.current &&
                latestAssistantTextRef.current.trim().length === 0 &&
                latestAssistantReasoningRef.current.trim().length === 0
              ) {
                dispatch({
                  type: "UPDATE_ASSISTANT_MESSAGE",
                  conversationId: conversationId!,
                  messageId: assistantMessageId,
                  content: "Response stopped.",
                  isStreaming: false,
                });
              }

              dispatch({
                type: "FINISH_ASSISTANT_MESSAGE",
                conversationId: conversationId!,
                messageId: assistantMessageId,
                model: modelAtSend,
                effort: effortAtSend,
              });

              if (Platform.OS !== "web") {
                void Haptics.selectionAsync();
              }

              abortRef.current = null;
              stopRequestedRef.current = false;
              latestAssistantTextRef.current = "";
              latestAssistantReasoningRef.current = "";
              setIsStreaming(false);
            },
            onError: (error) => {
              dispatch({
                type: "UPDATE_ASSISTANT_MESSAGE",
                conversationId: conversationId!,
                messageId: assistantMessageId,
                content: `Something went wrong.\n\n${error}`,
                isStreaming: false,
              });
              dispatch({
                type: "FINISH_ASSISTANT_MESSAGE",
                conversationId: conversationId!,
                messageId: assistantMessageId,
                model: modelAtSend,
                effort: effortAtSend,
              });

              if (Platform.OS !== "web") {
                void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
              }

              abortRef.current = null;
              stopRequestedRef.current = false;
              latestAssistantTextRef.current = "";
              latestAssistantReasoningRef.current = "";
              setIsStreaming(false);
            },
          },
          abortController.signal
        );
      } catch {
        abortRef.current = null;
        stopRequestedRef.current = false;
        latestAssistantTextRef.current = "";
        latestAssistantReasoningRef.current = "";
        setIsStreaming(false);
      }
    },
    [
      activeConversation?.id,
      createNewConversation,
      currentEffort,
      currentModel,
      dispatch,
      router,
    ]
  );

  const handleStop = useCallback(() => {
    stopRequestedRef.current = true;
    abortRef.current?.abort();
  }, []);

  const renderMessage = useCallback(({ item }: { item: Message }) => {
    return <MessageBubble message={item} />;
  }, []);

  const renderWelcome = useMemo(() => {
    if (!isLoaded) {
      return (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
          <Text style={[styles.loadingText, { color: colors.muted }]}>Loading your chats…</Text>
        </View>
      );
    }

    return (
      <View style={styles.welcomeContainer}>
        <GlassCard
          style={[
            styles.welcomeCard,
            {
              borderColor: colors.border,
              borderWidth: StyleSheet.hairlineWidth,
            },
          ]}
        >
          <View style={[styles.welcomeIconWrap, { backgroundColor: `${colors.primary}14` }]}>
            <MaterialIcons name="auto-awesome" size={28} color={colors.primary} />
          </View>

          <Text style={[styles.welcomeTitle, { color: colors.foreground }]}>
            {hasApiKey ? "Start a new conversation" : "Add your API key to begin"}
          </Text>

          <Text style={[styles.welcomeSubtitle, { color: colors.muted }]}>
            {hasApiKey
              ? "Ask anything, add images, or explore more detailed reasoning with your selected model."
              : "Open Settings to save your OpenAI API key. Your chats stay local to this app."}
          </Text>

          <View style={styles.badgeRow}>
            <View
              style={[
                styles.infoBadge,
                {
                  backgroundColor: `${colors.primary}14`,
                  borderColor: `${colors.primary}22`,
                },
              ]}
            >
              <Text style={[styles.infoBadgeText, { color: colors.primary }]}>
                {currentModelConfig.label}
              </Text>
            </View>
            <View
              style={[
                styles.infoBadge,
                {
                  backgroundColor: colors.surface,
                  borderColor: colors.border,
                },
              ]}
            >
              <Text style={[styles.infoBadgeText, { color: colors.foreground }]}>
                {currentEffort}
              </Text>
            </View>
          </View>

          {!hasApiKey ? (
            <Pressable
              accessibilityRole="button"
              onPress={handleOpenSettings}
              style={({ pressed }) => [
                styles.primaryButton,
                {
                  backgroundColor: colors.primary,
                  opacity: pressed ? 0.88 : 1,
                },
              ]}
            >
              <MaterialIcons name="settings" size={18} color="#FFFFFF" />
              <Text style={styles.primaryButtonText}>Open Settings</Text>
            </Pressable>
          ) : (
            <Text style={[styles.welcomeFootnote, { color: colors.muted }]}>
              Messages will stream in real time.
            </Text>
          )}
        </GlassCard>
      </View>
    );
  }, [
    colors.border,
    colors.foreground,
    colors.muted,
    colors.primary,
    colors.surface,
    currentEffort,
    currentModelConfig.label,
    handleOpenSettings,
    hasApiKey,
    isLoaded,
  ]);

  return (
    <ScreenContainer>
      <View style={[styles.screen, { backgroundColor: colors.background }]}>
        <View style={styles.headerContainer}>
          <GlassCard
            style={[
              styles.headerCard,
              {
                borderColor: colors.border,
                borderWidth: StyleSheet.hairlineWidth,
              },
            ]}
          >
            <View style={styles.headerRow}>
              <View style={styles.headerLeft}>
                <ModelSelector
                  model={currentModel}
                  effort={currentEffort}
                  onModelChange={setCurrentModel}
                  onEffortChange={setCurrentEffort}
                />
              </View>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="New Chat"
                disabled={isStreaming}
                onPress={handleNewChat}
                style={({ pressed }) => [
                  styles.newChatButton,
                  {
                    backgroundColor: `${colors.primary}14`,
                    opacity: pressed ? 0.82 : isStreaming ? 0.45 : 1,
                  },
                ]}
              >
                <MaterialIcons name="edit" size={16} color={colors.primary} />
                <Text style={[styles.newChatButtonText, { color: colors.primary }]}>New Chat</Text>
              </Pressable>
            </View>
          </GlassCard>
        </View>

        <KeyboardAvoidingView
          behavior={Platform.OS === "ios" ? "padding" : undefined}
          keyboardVerticalOffset={0}
          style={styles.flex}
        >
          <View style={styles.flex}>
            {messages.length > 0 ? (
              <FlatList
                ref={listRef}
                data={reversedMessages}
                inverted
                keyExtractor={(item) => item.id}
                renderItem={renderMessage}
                style={styles.flex}
                contentContainerStyle={styles.messagesContent}
                keyboardDismissMode={Platform.OS === "ios" ? "interactive" : "on-drag"}
                keyboardShouldPersistTaps="handled"
                showsVerticalScrollIndicator={false}
              />
            ) : (
              renderWelcome
            )}
          </View>

          <ChatInput
            disabled={!hasApiKey || !isLoaded}
            isStreaming={isStreaming}
            onSend={handleSend}
            onStop={handleStop}
          />
        </KeyboardAvoidingView>
      </View>
    </ScreenContainer>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  flex: {
    flex: 1,
  },
  headerContainer: {
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 10,
  },
  headerCard: {
    borderRadius: 24,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  headerRow: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  headerLeft: {
    flex: 1,
    alignItems: "flex-start",
    justifyContent: "center",
  },
  newChatButton: {
    alignItems: "center",
    borderRadius: 18,
    flexDirection: "row",
    gap: 6,
    height: 36,
    justifyContent: "center",
    width: 112,
  },
  newChatButtonText: {
    fontSize: 13,
    fontWeight: "700",
  },
  messagesContent: {
    paddingBottom: 8,
    paddingTop: 12,
  },
  loadingContainer: {
    alignItems: "center",
    flex: 1,
    justifyContent: "center",
    paddingHorizontal: 24,
  },
  loadingText: {
    fontSize: 14,
    marginTop: 12,
  },
  welcomeContainer: {
    alignItems: "center",
    flex: 1,
    justifyContent: "center",
    paddingHorizontal: 20,
  },
  welcomeCard: {
    alignItems: "center",
    borderRadius: 28,
    maxWidth: 420,
    paddingHorizontal: 24,
    paddingVertical: 28,
    width: "100%",
  },
  welcomeIconWrap: {
    alignItems: "center",
    borderRadius: 22,
    height: 44,
    justifyContent: "center",
    marginBottom: 14,
    width: 44,
  },
  welcomeTitle: {
    fontSize: 24,
    fontWeight: "800",
    letterSpacing: -0.4,
    textAlign: "center",
  },
  welcomeSubtitle: {
    fontSize: 15,
    lineHeight: 22,
    marginTop: 10,
    maxWidth: 320,
    textAlign: "center",
  },
  badgeRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 10,
    justifyContent: "center",
    marginTop: 18,
  },
  infoBadge: {
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  infoBadgeText: {
    fontSize: 12,
    fontWeight: "700",
  },
  primaryButton: {
    alignItems: "center",
    borderRadius: 999,
    flexDirection: "row",
    gap: 8,
    justifyContent: "center",
    marginTop: 20,
    paddingHorizontal: 18,
    paddingVertical: 12,
  },
  primaryButtonText: {
    color: "#FFFFFF",
    fontSize: 15,
    fontWeight: "700",
  },
  welcomeFootnote: {
    fontSize: 13,
    marginTop: 18,
    textAlign: "center",
  },
});
