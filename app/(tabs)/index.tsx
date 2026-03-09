import React, { useCallback, useRef, useState, useEffect } from 'react';
import { View, Text, FlatList, StyleSheet, Platform, Pressable, KeyboardAvoidingView } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { useColors } from '@/hooks/use-colors';
import { useChatStore } from '@/lib/chat-store';
import { streamChatCompletion, generateTitle } from '@/lib/openai-service';
import { Message, ImageAttachment, ModelId, ReasoningEffort } from '@/lib/types';
import { MessageBubble } from '@/components/message-bubble';
import { ChatInput } from '@/components/chat-input';
import { ModelSelector } from '@/components/model-selector';
import { GlassCard } from '@/components/glass-card';
import { v4 as uuidv4 } from 'uuid';

export default function ChatScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const { state, dispatch, activeConversation, createNewConversation } = useChatStore();
  const flatListRef = useRef<FlatList>(null);
  const abortRef = useRef<AbortController | null>(null);
  const [isStreaming, setIsStreaming] = useState(false);

  // Current model/effort from active conversation or defaults
  const currentModel = activeConversation?.model ?? state.settings.defaultModel;
  const currentEffort = activeConversation?.effort ?? state.settings.defaultEffort;

  const handleModelChange = useCallback(
    (model: ModelId) => {
      if (activeConversation) {
        dispatch({
          type: 'UPDATE_CONVERSATION_MODEL',
          conversationId: activeConversation.id,
          model,
          effort: currentEffort,
        });
      }
    },
    [activeConversation, currentEffort, dispatch]
  );

  const handleEffortChange = useCallback(
    (effort: ReasoningEffort) => {
      if (activeConversation) {
        dispatch({
          type: 'UPDATE_CONVERSATION_MODEL',
          conversationId: activeConversation.id,
          model: currentModel,
          effort,
        });
      }
    },
    [activeConversation, currentModel, dispatch]
  );

  const handleNewChat = useCallback(() => {
    if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    createNewConversation();
  }, [createNewConversation]);

  const handleSend = useCallback(
    async (text: string, images?: ImageAttachment[]) => {
      const apiKey = state.settings.apiKey;
      if (!apiKey) return;

      let convId = activeConversation?.id;
      if (!convId) {
        convId = createNewConversation(currentModel, currentEffort);
      }

      // Add user message
      dispatch({
        type: 'ADD_USER_MESSAGE',
        conversationId: convId,
        content: text,
        images,
      });

      // Create assistant message placeholder
      const assistantMsgId = uuidv4();
      dispatch({
        type: 'ADD_ASSISTANT_MESSAGE',
        conversationId: convId,
        messageId: assistantMsgId,
      });

      setIsStreaming(true);
      const abortController = new AbortController();
      abortRef.current = abortController;

      // Build messages for API
      const conv = state.conversations.find((c) => c.id === convId);
      const allMessages: Message[] = [
        ...(conv?.messages || []),
        {
          id: uuidv4(),
          role: 'user' as const,
          content: text,
          images,
          createdAt: Date.now(),
        },
      ];

      try {
        await streamChatCompletion(
          apiKey,
          allMessages,
          currentModel,
          currentEffort,
          {
            onToken: (fullText) => {
              dispatch({
                type: 'UPDATE_ASSISTANT_MESSAGE',
                conversationId: convId!,
                messageId: assistantMsgId,
                content: fullText,
                isStreaming: true,
              });
            },
            onReasoning: (fullReasoning) => {
              dispatch({
                type: 'UPDATE_ASSISTANT_MESSAGE',
                conversationId: convId!,
                messageId: assistantMsgId,
                content: '',
                reasoning: fullReasoning,
                isStreaming: true,
              });
            },
            onDone: () => {
              dispatch({
                type: 'FINISH_ASSISTANT_MESSAGE',
                conversationId: convId!,
                messageId: assistantMsgId,
                model: currentModel,
                effort: currentEffort,
              });
              setIsStreaming(false);
              abortRef.current = null;
            },
            onError: (error) => {
              dispatch({
                type: 'UPDATE_ASSISTANT_MESSAGE',
                conversationId: convId!,
                messageId: assistantMsgId,
                content: `⚠️ Error: ${error}`,
                isStreaming: false,
              });
              dispatch({
                type: 'FINISH_ASSISTANT_MESSAGE',
                conversationId: convId!,
                messageId: assistantMsgId,
              });
              setIsStreaming(false);
              abortRef.current = null;
            },
          },
          abortController.signal
        );
      } catch (err: any) {
        setIsStreaming(false);
        abortRef.current = null;
      }

      // Generate title if first message
      if (conv?.messages.length === 0 || !conv) {
        const title = await generateTitle(apiKey, text);
        dispatch({ type: 'UPDATE_CONVERSATION_TITLE', conversationId: convId!, title });
      }
    },
    [state, activeConversation, currentModel, currentEffort, dispatch, createNewConversation]
  );

  const handleStop = useCallback(() => {
    abortRef.current?.abort();
    setIsStreaming(false);
  }, []);

  const messages = activeConversation?.messages || [];
  const hasApiKey = !!state.settings.apiKey;

  const renderMessage = useCallback(
    ({ item }: { item: Message }) => <MessageBubble message={item} />,
    []
  );

  // Empty state
  const EmptyState = useCallback(
    () => (
      <View style={styles.emptyContainer}>
        <View style={styles.emptyContent}>
          <GlassCard style={styles.emptyCard}>
            <MaterialIcons name="auto-awesome" size={48} color={colors.primary} />
            <Text style={[styles.emptyTitle, { color: colors.foreground }]}>
              {hasApiKey ? 'Start a conversation' : 'Welcome to Liquid Glass Chat'}
            </Text>
            <Text style={[styles.emptySubtitle, { color: colors.muted }]}>
              {hasApiKey
                ? `Using ${currentModel === 'gpt-5.4-pro' ? 'GPT-5.4 Pro' : 'GPT-5.4'} with ${currentEffort} reasoning`
                : 'Go to Settings to add your OpenAI API key to get started'}
            </Text>
          </GlassCard>
        </View>
      </View>
    ),
    [hasApiKey, currentModel, currentEffort, colors]
  );

  return (
    <View style={[styles.screen, { backgroundColor: colors.background }]}>
      {/* Top Bar */}
      <View style={[styles.topBar, { paddingTop: insets.top + 4, borderBottomColor: colors.border }]}>
        <GlassCard style={styles.topBarGlass}>
          <View style={styles.topBarContent}>
            <ModelSelector
              model={currentModel}
              effort={currentEffort}
              onModelChange={handleModelChange}
              onEffortChange={handleEffortChange}
            />
            <Pressable
              onPress={handleNewChat}
              style={({ pressed }) => [styles.newChatBtn, { opacity: pressed ? 0.6 : 1 }]}
            >
              <MaterialIcons name="edit" size={22} color={colors.primary} />
            </Pressable>
          </View>
        </GlassCard>
      </View>

      {/* Messages */}
      <KeyboardAvoidingView
        style={styles.flex1}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={0}
      >
        <FlatList
          ref={flatListRef}
          data={messages}
          renderItem={renderMessage}
          keyExtractor={(item) => item.id}
          contentContainerStyle={[
            styles.messageList,
            messages.length === 0 && styles.emptyList,
          ]}
          ListEmptyComponent={EmptyState}
          onContentSizeChange={() => {
            if (messages.length > 0) {
              flatListRef.current?.scrollToEnd({ animated: true });
            }
          }}
          showsVerticalScrollIndicator={false}
          keyboardDismissMode="interactive"
          keyboardShouldPersistTaps="handled"
        />

        {/* Input */}
        <ChatInput
          onSend={handleSend}
          onStop={handleStop}
          isStreaming={isStreaming}
          disabled={!hasApiKey}
        />
      </KeyboardAvoidingView>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  flex1: {
    flex: 1,
  },
  topBar: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    zIndex: 10,
  },
  topBarGlass: {
    borderRadius: 0,
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  topBarContent: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  newChatBtn: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
  },
  messageList: {
    paddingTop: 16,
    paddingBottom: 8,
  },
  emptyList: {
    flex: 1,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
  },
  emptyContent: {
    width: '100%',
    maxWidth: 320,
  },
  emptyCard: {
    padding: 32,
    alignItems: 'center',
    gap: 12,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '700',
    textAlign: 'center',
  },
  emptySubtitle: {
    fontSize: 14,
    textAlign: 'center',
    lineHeight: 20,
  },
});
