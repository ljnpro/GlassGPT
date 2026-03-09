import React, { useCallback, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  GestureResponderEvent,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import MaterialIcons from "@expo/vector-icons/MaterialIcons";
import { ScreenContainer } from "@/components/screen-container";
import { GlassCard } from "@/components/glass-card";
import { useColors } from "@/hooks/use-colors";
import { useChatStore } from "@/lib/chat-store";
import { Conversation, MODELS } from "@/lib/types";

type Colors = ReturnType<typeof useColors>;

function getModelLabel(modelId: Conversation["model"]): string {
  return MODELS.find((item) => item.id === modelId)?.label ?? modelId;
}

function formatConversationDate(timestamp: number): string {
  const date = new Date(timestamp);
  const now = new Date();

  const isSameDay =
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();

  if (isSameDay) {
    return date.toLocaleTimeString([], {
      hour: "numeric",
      minute: "2-digit",
    });
  }

  const yesterday = new Date();
  yesterday.setDate(now.getDate() - 1);

  const isYesterday =
    date.getFullYear() === yesterday.getFullYear() &&
    date.getMonth() === yesterday.getMonth() &&
    date.getDate() === yesterday.getDate();

  if (isYesterday) {
    return "Yesterday";
  }

  const isSameYear = date.getFullYear() === now.getFullYear();

  return date.toLocaleDateString([], {
    month: "short",
    day: "numeric",
    ...(isSameYear ? null : { year: "numeric" }),
  });
}

function getConversationPreview(conversation: Conversation): string {
  for (let index = conversation.messages.length - 1; index >= 0; index -= 1) {
    const message = conversation.messages[index];

    if (message.content.trim().length > 0) {
      return message.content.replace(/\s+/g, " ").trim();
    }

    if (message.images && message.images.length > 0) {
      return message.images.length > 1 ? `${message.images.length} photos` : "Photo";
    }

    if (message.isStreaming) {
      return "Streaming response…";
    }
  }

  return "No messages yet";
}

function getSearchText(conversation: Conversation): string {
  const messagesText = conversation.messages
    .map((message) => {
      const imageText = message.images && message.images.length > 0 ? " photo" : "";
      return `${message.content}${imageText}`;
    })
    .join(" ");

  return `${conversation.title} ${messagesText}`.toLowerCase();
}

function ConversationRow({
  colors,
  conversation,
  isActive,
  onDelete,
  onSelect,
}: {
  colors: Colors;
  conversation: Conversation;
  isActive: boolean;
  onDelete: (conversation: Conversation) => void;
  onSelect: (conversation: Conversation) => void;
}) {
  const suppressNextPressRef = useRef(false);
  const preview = getConversationPreview(conversation);

  const handlePress = useCallback(() => {
    if (suppressNextPressRef.current) {
      suppressNextPressRef.current = false;
      return;
    }

    onSelect(conversation);
  }, [conversation, onSelect]);

  const handleLongPress = useCallback(() => {
    suppressNextPressRef.current = true;
    onDelete(conversation);
  }, [conversation, onDelete]);

  const handleDeletePress = useCallback(
    (event: GestureResponderEvent) => {
      event.stopPropagation();
      onDelete(conversation);
    },
    [conversation, onDelete]
  );

  return (
    <Pressable
      delayLongPress={220}
      onLongPress={handleLongPress}
      onPress={handlePress}
      style={({ pressed }) => [
        {
          opacity: pressed ? 0.94 : 1,
        },
      ]}
    >
      <GlassCard
        style={[
          styles.rowCard,
          {
            borderColor: isActive ? `${colors.primary}66` : colors.border,
            borderWidth: StyleSheet.hairlineWidth,
          },
        ]}
      >
        <View style={styles.rowHeader}>
          <View style={styles.rowHeaderText}>
            <Text
              numberOfLines={1}
              style={[
                styles.rowTitle,
                {
                  color: colors.foreground,
                },
              ]}
            >
              {conversation.title || "New Chat"}
            </Text>
            <Text
              numberOfLines={2}
              style={[
                styles.rowPreview,
                {
                  color: colors.muted,
                },
              ]}
            >
              {preview}
            </Text>
          </View>

          <View style={styles.rowHeaderActions}>
            <Text
              style={[
                styles.rowDate,
                {
                  color: colors.muted,
                },
              ]}
            >
              {formatConversationDate(conversation.updatedAt)}
            </Text>

            <Pressable
              accessibilityLabel={`Delete ${conversation.title || "conversation"}`}
              accessibilityRole="button"
              onPress={handleDeletePress}
              style={({ pressed }) => [
                styles.deleteButton,
                {
                  backgroundColor: `${colors.error}12`,
                  opacity: pressed ? 0.78 : 1,
                },
              ]}
            >
              <MaterialIcons name="delete-outline" size={16} color={colors.error} />
            </Pressable>
          </View>
        </View>

        <View style={styles.rowFooter}>
          <View
            style={[
              styles.modelBadge,
              {
                backgroundColor: `${colors.primary}12`,
                borderColor: `${colors.primary}22`,
              },
            ]}
          >
            <Text
              style={[
                styles.modelBadgeText,
                {
                  color: colors.primary,
                },
              ]}
            >
              {getModelLabel(conversation.model)} · {conversation.effort}
            </Text>
          </View>

          <View style={styles.rowMeta}>
            <Text
              style={[
                styles.rowMetaText,
                {
                  color: colors.muted,
                },
              ]}
            >
              {conversation.messages.length} messages
            </Text>
            <MaterialIcons name="chevron-right" size={18} color={colors.muted} />
          </View>
        </View>
      </GlassCard>
    </Pressable>
  );
}

export default function ConversationsScreen() {
  const colors = useColors();
  const router = useRouter();
  const {
    state,
    dispatch,
    currentEffort,
    currentModel,
    deleteConversation,
    setActiveConversation,
  } = useChatStore();

  const [searchQuery, setSearchQuery] = useState("");

  const sortedConversations = useMemo(() => {
    return [...state.conversations].sort((left, right) => right.updatedAt - left.updatedAt);
  }, [state.conversations]);

  const filteredConversations = useMemo(() => {
    const normalized = searchQuery.trim().toLowerCase();

    if (!normalized) {
      return sortedConversations;
    }

    return sortedConversations.filter((conversation) =>
      getSearchText(conversation).includes(normalized)
    );
  }, [searchQuery, sortedConversations]);

  const handleSelectConversation = useCallback(
    (conversation: Conversation) => {
      if (Platform.OS !== "web") {
        void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      }

      setActiveConversation(conversation.id);
      router.navigate("/(tabs)");
    },
    [router, setActiveConversation]
  );

  const handleDeleteConversation = useCallback(
    (conversation: Conversation) => {
      const performDelete = () => {
        deleteConversation(conversation.id);

        if (Platform.OS !== "web") {
          void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        }
      };

      if (Platform.OS !== "web") {
        void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      }

      if (Platform.OS === "web") {
        const confirmFn = (
          globalThis as typeof globalThis & {
            confirm?: (message?: string) => boolean;
          }
        ).confirm;

        if (confirmFn?.(`Delete "${conversation.title || "this conversation"}"?`)) {
          performDelete();
        }

        return;
      }

      Alert.alert("Delete Conversation", `Delete "${conversation.title || "this conversation"}"?`, [
        {
          text: "Cancel",
          style: "cancel",
        },
        {
          text: "Delete",
          style: "destructive",
          onPress: performDelete,
        },
      ]);
    },
    [deleteConversation]
  );

  const handleNewChat = useCallback(() => {
    if (Platform.OS !== "web") {
      void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    }

    setActiveConversation(null);
    router.navigate("/(tabs)");
  }, [currentEffort, currentModel, dispatch, router, setActiveConversation]);

  const renderConversation = useCallback(
    ({ item }: { item: Conversation }) => {
      return (
        <ConversationRow
          colors={colors}
          conversation={item}
          isActive={state.activeConversationId === item.id}
          onDelete={handleDeleteConversation}
          onSelect={handleSelectConversation}
        />
      );
    },
    [colors, handleDeleteConversation, handleSelectConversation, state.activeConversationId]
  );

  const renderEmptyState = useCallback(() => {
    if (!state.isLoaded) {
      return (
        <View style={styles.emptyState}>
          <ActivityIndicator size="large" color={colors.primary} />
          <Text style={[styles.emptyTitle, { color: colors.foreground }]}>Loading history…</Text>
        </View>
      );
    }

    const isSearching = searchQuery.trim().length > 0;

    return (
      <View style={styles.emptyState}>
        <View style={[styles.emptyIconWrap, { backgroundColor: `${colors.primary}12` }]}>
          <MaterialIcons name="history" size={28} color={colors.primary} />
        </View>
        <Text style={[styles.emptyTitle, { color: colors.foreground }]}>
          {isSearching ? "No matches found" : "No conversations yet"}
        </Text>
        <Text style={[styles.emptySubtitle, { color: colors.muted }]}>
          {isSearching
            ? "Try a different search term."
            : "Your recent chats will appear here. Start a new conversation to begin."}
        </Text>
        {!isSearching ? (
          <Pressable
            accessibilityRole="button"
            onPress={handleNewChat}
            style={({ pressed }) => [
              styles.emptyPrimaryButton,
              {
                backgroundColor: colors.primary,
                opacity: pressed ? 0.88 : 1,
              },
            ]}
          >
            <MaterialIcons name="add" size={18} color="#FFFFFF" />
            <Text style={styles.emptyPrimaryButtonText}>New Chat</Text>
          </Pressable>
        ) : null}
      </View>
    );
  }, [colors.foreground, colors.muted, colors.primary, handleNewChat, searchQuery, state.isLoaded]);

  return (
    <ScreenContainer>
      <View style={[styles.screen, { backgroundColor: colors.background }]}>
        <View style={styles.topSection}>
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
              <View style={styles.headerTextWrap}>
                <Text style={[styles.headerTitle, { color: colors.foreground }]}>History</Text>
                <Text style={[styles.headerSubtitle, { color: colors.muted }]}>
                  {state.conversations.length} saved conversation
                  {state.conversations.length === 1 ? "" : "s"}
                </Text>
              </View>

              <Pressable
                accessibilityRole="button"
                accessibilityLabel="New Chat"
                onPress={handleNewChat}
                style={({ pressed }) => [
                  styles.newChatButton,
                  {
                    backgroundColor: `${colors.primary}14`,
                    opacity: pressed ? 0.82 : 1,
                  },
                ]}
              >
                <MaterialIcons name="add" size={18} color={colors.primary} />
                <Text style={[styles.newChatButtonText, { color: colors.primary }]}>New Chat</Text>
              </Pressable>
            </View>
          </GlassCard>

          <GlassCard
            style={[
              styles.searchCard,
              {
                borderColor: colors.border,
                borderWidth: StyleSheet.hairlineWidth,
              },
            ]}
          >
            <View style={[styles.searchBar, { backgroundColor: colors.surface }]}>
              <MaterialIcons name="search" size={18} color={colors.muted} />
              <TextInput
                autoCapitalize="none"
                autoCorrect={false}
                clearButtonMode="never"
                keyboardAppearance={Platform.OS === "ios" ? "default" : undefined}
                placeholder="Search conversations"
                placeholderTextColor={colors.muted}
                returnKeyType="search"
                style={[styles.searchInput, { color: colors.foreground }]}
                value={searchQuery}
                onChangeText={setSearchQuery}
              />
              {searchQuery.length > 0 ? (
                <Pressable
                  accessibilityLabel="Clear search"
                  onPress={() => setSearchQuery("")}
                  style={({ pressed }) => [
                    styles.searchClearButton,
                    {
                      backgroundColor: `${colors.muted}18`,
                      opacity: pressed ? 0.8 : 1,
                    },
                  ]}
                >
                  <MaterialIcons name="close" size={14} color={colors.muted} />
                </Pressable>
              ) : null}
            </View>
          </GlassCard>
        </View>

        <FlatList
          contentContainerStyle={[
            styles.listContent,
            filteredConversations.length === 0 && styles.listContentEmpty,
          ]}
          data={filteredConversations}
          keyboardDismissMode={Platform.OS === "ios" ? "interactive" : "on-drag"}
          keyboardShouldPersistTaps="handled"
          keyExtractor={(item) => item.id}
          ListEmptyComponent={renderEmptyState}
          renderItem={renderConversation}
          showsVerticalScrollIndicator={false}
        />
      </View>
    </ScreenContainer>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  topSection: {
    gap: 12,
    paddingBottom: 10,
    paddingHorizontal: 16,
    paddingTop: 8,
  },
  headerCard: {
    borderRadius: 24,
    paddingHorizontal: 16,
    paddingVertical: 16,
  },
  headerRow: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  headerTextWrap: {
    flex: 1,
    paddingRight: 12,
  },
  headerTitle: {
    fontSize: 30,
    fontWeight: "800",
    letterSpacing: -0.6,
  },
  headerSubtitle: {
    fontSize: 14,
    marginTop: 4,
  },
  newChatButton: {
    alignItems: "center",
    borderRadius: 18,
    flexDirection: "row",
    gap: 6,
    height: 36,
    justifyContent: "center",
    paddingHorizontal: 12,
  },
  newChatButtonText: {
    fontSize: 13,
    fontWeight: "700",
  },
  searchCard: {
    borderRadius: 20,
    padding: 8,
  },
  searchBar: {
    alignItems: "center",
    borderRadius: 16,
    flexDirection: "row",
    gap: 10,
    minHeight: 46,
    paddingHorizontal: 14,
  },
  searchInput: {
    flex: 1,
    fontSize: 16,
    paddingVertical: 10,
  },
  searchClearButton: {
    alignItems: "center",
    borderRadius: 11,
    height: 22,
    justifyContent: "center",
    width: 22,
  },
  listContent: {
    gap: 12,
    paddingBottom: 28,
    paddingHorizontal: 16,
  },
  listContentEmpty: {
    flexGrow: 1,
    justifyContent: "center",
  },
  rowCard: {
    borderRadius: 24,
    paddingHorizontal: 16,
    paddingVertical: 16,
  },
  rowHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
  },
  rowHeaderText: {
    flex: 1,
    paddingRight: 12,
  },
  rowTitle: {
    fontSize: 17,
    fontWeight: "700",
    letterSpacing: -0.2,
  },
  rowPreview: {
    fontSize: 14,
    lineHeight: 20,
    marginTop: 6,
  },
  rowHeaderActions: {
    alignItems: "flex-end",
    gap: 10,
  },
  rowDate: {
    fontSize: 12,
    fontWeight: "600",
  },
  deleteButton: {
    alignItems: "center",
    borderRadius: 14,
    height: 28,
    justifyContent: "center",
    width: 28,
  },
  rowFooter: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
    marginTop: 14,
  },
  modelBadge: {
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  modelBadgeText: {
    fontSize: 11,
    fontWeight: "700",
  },
  rowMeta: {
    alignItems: "center",
    flexDirection: "row",
    gap: 2,
  },
  rowMetaText: {
    fontSize: 12,
    fontWeight: "600",
  },
  emptyState: {
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 24,
  },
  emptyIconWrap: {
    alignItems: "center",
    borderRadius: 24,
    height: 48,
    justifyContent: "center",
    marginBottom: 16,
    width: 48,
  },
  emptyTitle: {
    fontSize: 22,
    fontWeight: "800",
    letterSpacing: -0.3,
    textAlign: "center",
  },
  emptySubtitle: {
    fontSize: 15,
    lineHeight: 22,
    marginTop: 10,
    maxWidth: 320,
    textAlign: "center",
  },
  emptyPrimaryButton: {
    alignItems: "center",
    borderRadius: 999,
    flexDirection: "row",
    gap: 8,
    justifyContent: "center",
    marginTop: 20,
    paddingHorizontal: 18,
    paddingVertical: 12,
  },
  emptyPrimaryButtonText: {
    color: "#FFFFFF",
    fontSize: 15,
    fontWeight: "700",
  },
});
