import React, { useCallback, useEffect, useMemo, useRef } from "react";
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
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import MaterialIcons from "@expo/vector-icons/MaterialIcons";

import { ChatInput } from "@/components/chat-input";
import { GlassCard } from "@/components/glass-card";
import { MessageBubble } from "@/components/message-bubble";
import { ModelSelector } from "@/components/model-selector";
import { ScreenContainer } from "@/components/screen-container";
import { useColors } from "@/hooks/use-colors";
import { useChatStore } from "@/lib/chat-store";
import { ImageAttachment, Message, MODELS } from "@/lib/types";

export default function ChatScreen() {
  const colors = useColors();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const {
    state,
    activeConversation,
    setActiveConversation,
    currentModel,
    currentEffort,
    setCurrentModel,
    setCurrentEffort,
    sendMessage,
    stopStreaming,
  } = useChatStore();

  const listRef = useRef<FlatList<Message>>(null);

  const messages = activeConversation?.messages ?? [];
  const reversedMessages = useMemo(() => [...messages].reverse(), [messages]);
  const hasApiKey = state.settings.apiKey.trim().length > 0;
  const isLoaded = state.isLoaded;
  const isStreaming = state.isSending;
  const currentModelConfig = MODELS.find((item) => item.id === currentModel) ?? MODELS[0];
  const activeConversationTitle =
    activeConversation && activeConversation.id !== "" ? activeConversation.title : "New Chat";

  const lastVisibleFingerprint = useMemo(() => {
    const lastMessage = messages[messages.length - 1];
    if (!lastMessage) {
      return "empty";
    }

    return `${lastMessage.id}:${lastMessage.content.length}:${lastMessage.reasoning?.length ?? 0}:${
      lastMessage.isStreaming ? "1" : "0"
    }`;
  }, [messages]);

  useEffect(() => {
    if (messages.length === 0) {
      return;
    }

    const frame = requestAnimationFrame(() => {
      listRef.current?.scrollToOffset({ offset: 0, animated: true });
    });

    return () => cancelAnimationFrame(frame);
  }, [lastVisibleFingerprint, messages.length]);

  const handleNewChat = useCallback(() => {
    if (isStreaming) {
      return;
    }

    if (Platform.OS !== "web") {
      void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    }

    setActiveConversation(null);
  }, [isStreaming, setActiveConversation]);

  const handleOpenSettings = useCallback(() => {
    router.navigate("/(tabs)/settings");
  }, [router]);

  const handleSend = useCallback(
    async (text: string, images?: ImageAttachment[]) => {
      const trimmed = text.trim();

      if (!trimmed && (!images || images.length === 0)) {
        return;
      }

      if (!state.settings.apiKey.trim()) {
        router.navigate("/(tabs)/settings");
        return;
      }

      try {
        await sendMessage({
          text: trimmed,
          images,
          conversationId: state.activeConversationId,
        });
      } catch (error) {
        console.error("Failed to send message:", error);
      }
    },
    [router, sendMessage, state.activeConversationId, state.settings.apiKey]
  );

  const handleStop = useCallback(() => {
    stopStreaming();
  }, [stopStreaming]);

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
            {hasApiKey ? "Start a beautiful new conversation" : "Add your API key to begin"}
          </Text>

          <Text style={[styles.welcomeSubtitle, { color: colors.muted }]}>
            {hasApiKey
              ? "Ask anything, attach images, and watch responses stream live with a native iOS feel."
              : "Open Settings to save your OpenAI API key securely on this device and start chatting."}
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
                  opacity: pressed ? 0.9 : 1,
                },
              ]}
            >
              <MaterialIcons name="settings" size={18} color="#FFFFFF" />
              <Text style={styles.primaryButtonText}>Open Settings</Text>
            </Pressable>
          ) : (
            <Text style={[styles.welcomeFootnote, { color: colors.muted }]}>
              Responses will stream in real time.
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
      <View style={[styles.screen, { backgroundColor: "transparent" }]}>
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
            <View style={styles.headerTopRow}>
              <View style={styles.headerTextBlock}>
                <Text style={[styles.headerTitle, { color: colors.foreground }]}>
                  {messages.length > 0 ? activeConversationTitle : "Liquid Glass Chat"}
                </Text>
                <Text style={[styles.headerSubtitle, { color: colors.muted }]}>
                  {hasApiKey
                    ? "Private chats with your own OpenAI key"
                    : "Add an API key in Settings to start"}
                </Text>
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
                    opacity: pressed ? 0.88 : isStreaming ? 0.5 : 1,
                  },
                ]}
              >
                <MaterialIcons name="edit" size={16} color={colors.primary} />
                <Text style={[styles.newChatButtonText, { color: colors.primary }]}>New Chat</Text>
              </Pressable>
            </View>

            <View style={styles.selectorRow}>
              <ModelSelector
                model={currentModel}
                effort={currentEffort}
                onModelChange={setCurrentModel}
                onEffortChange={setCurrentEffort}
              />
            </View>
          </GlassCard>

          {state.lastError ? (
            <GlassCard
              style={[
                styles.errorCard,
                {
                  borderColor: `${colors.error}2F`,
                  borderWidth: StyleSheet.hairlineWidth,
                },
              ]}
            >
              <MaterialIcons name="error-outline" size={18} color={colors.error} />
              <Text style={[styles.errorText, { color: colors.error }]} numberOfLines={3}>
                {state.lastError}
              </Text>
            </GlassCard>
          ) : null}
        </View>

        <KeyboardAvoidingView
          behavior={Platform.OS === "ios" ? "padding" : undefined}
          keyboardVerticalOffset={Platform.OS === "ios" ? Math.max(insets.bottom, 10) + 58 : 0}
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
    gap: 10,
  },
  headerCard: {
    borderRadius: 24,
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  headerTopRow: {
    alignItems: "flex-start",
    flexDirection: "row",
    justifyContent: "space-between",
    gap: 12,
  },
  headerTextBlock: {
    flex: 1,
    paddingRight: 4,
  },
  headerTitle: {
    fontSize: 22,
    fontWeight: "800",
    letterSpacing: -0.45,
  },
  headerSubtitle: {
    fontSize: 13,
    marginTop: 4,
  },
  selectorRow: {
    marginTop: 14,
    alignItems: "flex-start",
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
  errorCard: {
    borderRadius: 18,
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  errorText: {
    flex: 1,
    fontSize: 13,
    lineHeight: 18,
    fontWeight: "600",
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
