import React, { useState, useCallback } from 'react';
import { View, Text, Pressable, StyleSheet, Platform } from 'react-native';
import { Image } from 'expo-image';
import * as Clipboard from 'expo-clipboard';
import * as Haptics from 'expo-haptics';
import { useColors } from '@/hooks/use-colors';
import { Message } from '@/lib/types';
import { MarkdownRenderer } from './markdown-renderer';
import { GlassCard } from './glass-card';

interface MessageBubbleProps {
  message: Message;
}

function ReasoningSection({ reasoning, colors }: { reasoning: string; colors: any }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <Pressable
      onPress={() => {
        setExpanded(!expanded);
        if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      }}
      style={({ pressed }) => [{ opacity: pressed ? 0.7 : 1 }]}
    >
      <View style={[styles.reasoningHeader, { borderColor: colors.border }]}>
        <Text style={[styles.reasoningLabel, { color: colors.muted }]}>
          {expanded ? '▼' : '▶'} Thinking
        </Text>
        <Text style={[styles.reasoningToggle, { color: colors.primary }]}>
          {expanded ? 'Hide' : 'Show'}
        </Text>
      </View>
      {expanded && (
        <View style={[styles.reasoningContent, { backgroundColor: colors.surface }]}>
          <Text style={{ color: colors.muted, fontSize: 14, lineHeight: 20, fontStyle: 'italic' }} selectable>
            {reasoning}
          </Text>
        </View>
      )}
    </Pressable>
  );
}

export function MessageBubble({ message }: MessageBubbleProps) {
  const colors = useColors();
  const isUser = message.role === 'user';
  const [showActions, setShowActions] = useState(false);

  const handleLongPress = useCallback(() => {
    if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    setShowActions(!showActions);
  }, [showActions]);

  const handleCopy = useCallback(async () => {
    await Clipboard.setStringAsync(message.content);
    if (Platform.OS !== 'web') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setShowActions(false);
  }, [message.content]);

  if (isUser) {
    return (
      <View style={styles.userRow}>
        <Pressable
          onLongPress={handleLongPress}
          style={({ pressed }) => [{ opacity: pressed ? 0.9 : 1, maxWidth: '85%' }]}
        >
          <View style={[styles.userBubble, { backgroundColor: colors.primary }]}>
            {message.images && message.images.length > 0 && (
              <View style={styles.imageGrid}>
                {message.images.map((img, idx) => (
                  <Image
                    key={idx}
                    source={{ uri: img.uri || (img.base64 ? `data:${img.mimeType || 'image/jpeg'};base64,${img.base64}` : '') }}
                    style={styles.attachedImage}
                    contentFit="cover"
                    transition={200}
                  />
                ))}
              </View>
            )}
            {message.content ? (
              <Text style={styles.userText} selectable>
                {message.content}
              </Text>
            ) : null}
          </View>
          {showActions && (
            <View style={[styles.actionBar, { backgroundColor: colors.surface, borderColor: colors.border }]}>
              <Pressable onPress={handleCopy} style={({ pressed }) => [styles.actionBtn, { opacity: pressed ? 0.6 : 1 }]}>
                <Text style={{ color: colors.primary, fontSize: 13, fontWeight: '600' }}>Copy</Text>
              </Pressable>
            </View>
          )}
        </Pressable>
      </View>
    );
  }

  // Assistant message
  return (
    <View style={styles.assistantRow}>
      <Pressable
        onLongPress={handleLongPress}
        style={({ pressed }) => [{ opacity: pressed ? 0.95 : 1, maxWidth: '92%' }]}
      >
        <GlassCard style={styles.assistantBubble}>
          {message.reasoning ? (
            <ReasoningSection reasoning={message.reasoning} colors={colors} />
          ) : null}
          {message.content ? (
            <MarkdownRenderer content={message.content} isStreaming={message.isStreaming} />
          ) : message.isStreaming ? (
            <View style={styles.typingIndicator}>
              <Text style={{ color: colors.muted, fontSize: 24 }}>•••</Text>
            </View>
          ) : null}
        </GlassCard>
        {showActions && (
          <View style={[styles.actionBar, { backgroundColor: colors.surface, borderColor: colors.border }]}>
            <Pressable onPress={handleCopy} style={({ pressed }) => [styles.actionBtn, { opacity: pressed ? 0.6 : 1 }]}>
              <Text style={{ color: colors.primary, fontSize: 13, fontWeight: '600' }}>Copy</Text>
            </Pressable>
          </View>
        )}
        {message.model && !message.isStreaming && (
          <Text style={[styles.modelTag, { color: colors.muted }]}>
            {message.model}{message.effort ? ` · ${message.effort}` : ''}
          </Text>
        )}
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  userRow: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    paddingHorizontal: 16,
    marginBottom: 12,
  },
  assistantRow: {
    flexDirection: 'row',
    justifyContent: 'flex-start',
    paddingHorizontal: 16,
    marginBottom: 12,
  },
  userBubble: {
    borderRadius: 20,
    borderBottomRightRadius: 6,
    paddingHorizontal: 16,
    paddingVertical: 10,
    gap: 8,
  },
  userText: {
    color: '#FFFFFF',
    fontSize: 16,
    lineHeight: 22,
  },
  assistantBubble: {
    borderRadius: 20,
    borderBottomLeftRadius: 6,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  imageGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  attachedImage: {
    width: 120,
    height: 120,
    borderRadius: 12,
  },
  typingIndicator: {
    paddingVertical: 4,
  },
  actionBar: {
    flexDirection: 'row',
    borderRadius: 10,
    borderWidth: 1,
    marginTop: 4,
    alignSelf: 'flex-start',
    overflow: 'hidden',
  },
  actionBtn: {
    paddingHorizontal: 14,
    paddingVertical: 6,
  },
  modelTag: {
    fontSize: 11,
    marginTop: 4,
    marginLeft: 4,
  },
  reasoningHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingBottom: 8,
    marginBottom: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  reasoningLabel: {
    fontSize: 13,
    fontWeight: '600',
  },
  reasoningToggle: {
    fontSize: 13,
    fontWeight: '600',
  },
  reasoningContent: {
    borderRadius: 8,
    padding: 10,
    marginBottom: 8,
  },
});
