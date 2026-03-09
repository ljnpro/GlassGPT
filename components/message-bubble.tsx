import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  FlatList,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
  type ListRenderItemInfo,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Image } from 'expo-image';
import * as Clipboard from 'expo-clipboard';
import * as Haptics from 'expo-haptics';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { useColors } from '@/hooks/use-colors';
import { ImageAttachment, Message, ModelId, ReasoningEffort } from '@/lib/types';
import { MarkdownRenderer } from './markdown-renderer';

interface MessageBubbleProps {
  message: Message;
}

interface ThemeColors {
  primary: string;
  background: string;
  surface: string;
  foreground: string;
  muted: string;
  border: string;
  success: string;
  warning: string;
  error: string;
}

interface ImageViewerModalProps {
  attachments: ImageAttachment[];
  visible: boolean;
  index: number;
  onIndexChange: (index: number) => void;
  onClose: () => void;
}

interface AttachmentGridProps {
  attachments: ImageAttachment[];
  onPressImage: (index: number) => void;
}

interface ReasoningSectionProps {
  reasoning: string;
  isStreaming?: boolean;
  defaultExpanded?: boolean;
  colors: ThemeColors;
}

const MODEL_LABELS: Record<ModelId, string> = {
  'gpt-5.4': 'GPT-5.4',
  'gpt-5.4-pro': 'GPT-5.4 Pro',
};

const EFFORT_LABELS: Record<ReasoningEffort, string> = {
  none: 'None',
  low: 'Low',
  medium: 'Medium',
  high: 'High',
  xhigh: 'xHigh',
};

function withOpacity(color: string, opacity: number): string {
  const normalizedOpacity = Math.max(0, Math.min(1, opacity));

  if (color.startsWith('#')) {
    let hex = color.slice(1);

    if (hex.length === 3) {
      hex = hex
        .split('')
        .map((char) => char + char)
        .join('');
    }

    if (hex.length === 6) {
      const red = parseInt(hex.slice(0, 2), 16);
      const green = parseInt(hex.slice(2, 4), 16);
      const blue = parseInt(hex.slice(4, 6), 16);
      return `rgba(${red}, ${green}, ${blue}, ${normalizedOpacity})`;
    }
  }

  if (color.startsWith('rgb(')) {
    return color.replace('rgb(', 'rgba(').replace(')', `, ${normalizedOpacity})`);
  }

  if (color.startsWith('rgba(')) {
    return color.replace(/rgba\(([^,]+),([^,]+),([^,]+),[^)]+\)/, `rgba($1,$2,$3,${normalizedOpacity})`);
  }

  return color;
}

function triggerLightImpact(): void {
  if (Platform.OS !== 'web') {
    void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => undefined);
  }
}

function triggerSuccessFeedback(): void {
  if (Platform.OS !== 'web') {
    void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => undefined);
  }
}

function getAttachmentUri(attachment: ImageAttachment): string {
  if (attachment.base64) {
    return `data:${attachment.mimeType || 'image/jpeg'};base64,${attachment.base64}`;
  }
  return attachment.uri;
}

function getPreviewHeight(attachment: ImageAttachment): number {
  if (!attachment.width || !attachment.height) {
    return 196;
  }

  const aspectRatio = attachment.height / attachment.width;
  const estimatedHeight = 220 * aspectRatio;
  return Math.max(140, Math.min(280, estimatedHeight));
}

function AssistantMetaBadges({
  model,
  effort,
  colors,
}: {
  model?: ModelId;
  effort?: ReasoningEffort;
  colors: ThemeColors;
}) {
  if (!model && !effort) {
    return null;
  }

  return (
    <View style={styles.metaRow}>
      {model ? (
        <View
          style={[
            styles.metaBadge,
            {
              backgroundColor: withOpacity(colors.primary, 0.14),
              borderColor: withOpacity(colors.primary, 0.22),
            },
          ]}
        >
          <Text style={[styles.metaBadgeText, { color: colors.primary }]}>{MODEL_LABELS[model]}</Text>
        </View>
      ) : null}

      {effort ? (
        <View
          style={[
            styles.metaBadge,
            {
              backgroundColor: withOpacity(colors.foreground, 0.06),
              borderColor: withOpacity(colors.border, 0.8),
            },
          ]}
        >
          <Text style={[styles.metaBadgeText, { color: colors.muted }]}>{EFFORT_LABELS[effort]}</Text>
        </View>
      ) : null}
    </View>
  );
}

function ReasoningSection({
  reasoning,
  isStreaming,
  defaultExpanded = false,
  colors,
}: ReasoningSectionProps) {
  const [expanded, setExpanded] = useState(defaultExpanded);

  useEffect(() => {
    if (defaultExpanded && reasoning.trim().length > 0) {
      setExpanded(true);
    }
  }, [defaultExpanded, reasoning]);

  const handleToggle = useCallback(() => {
    triggerLightImpact();
    setExpanded((current) => !current);
  }, []);

  return (
    <View
      style={[
        styles.reasoningContainer,
        {
          backgroundColor: withOpacity(colors.foreground, 0.03),
          borderColor: withOpacity(colors.border, 0.72),
        },
      ]}
    >
      <Pressable onPress={handleToggle} style={({ pressed }) => [styles.reasoningHeader, pressed && styles.pressed]}>
        <View style={styles.reasoningTitleRow}>
          <Text style={[styles.reasoningTitle, { color: colors.muted }]}>Thinking...</Text>
          {isStreaming ? (
            <View style={[styles.reasoningLiveDot, { backgroundColor: colors.primary }]} />
          ) : null}
        </View>

        <View style={styles.reasoningRightRow}>
          <Text style={[styles.reasoningToggleText, { color: colors.primary }]}>
            {expanded ? 'Hide' : 'Show'}
          </Text>
          <MaterialIcons
            name={expanded ? 'keyboard-arrow-down' : 'keyboard-arrow-right'}
            size={18}
            color={colors.primary}
          />
        </View>
      </Pressable>

      {expanded ? (
        <View style={styles.reasoningBody}>
          <MarkdownRenderer content={reasoning} compact />
        </View>
      ) : null}
    </View>
  );
}

function AttachmentGrid({ attachments, onPressImage }: AttachmentGridProps) {
  const columns = attachments.length > 1 ? 2 : 1;

  const renderItem = useCallback(
    ({ item, index }: ListRenderItemInfo<ImageAttachment>) => {
      const isSingle = columns === 1;
      const height = isSingle ? getPreviewHeight(item) : 128;

      return (
        <View style={isSingle ? styles.singleAttachmentCell : styles.multiAttachmentCell}>
          <Pressable
            onPress={() => onPressImage(index)}
            style={({ pressed }) => [styles.attachmentPressable, pressed && styles.pressed]}
          >
            <Image
              source={{ uri: getAttachmentUri(item) }}
              style={[styles.attachmentImage, { height }]}
              contentFit="cover"
              transition={120}
            />
          </Pressable>
        </View>
      );
    },
    [columns, onPressImage]
  );

  return (
    <FlatList
      data={attachments}
      key={`attachments-${columns}`}
      numColumns={columns}
      renderItem={renderItem}
      keyExtractor={(item, index) => `${item.uri}-${index}`}
      scrollEnabled={false}
      removeClippedSubviews={false}
      columnWrapperStyle={columns > 1 ? styles.attachmentColumnWrapper : undefined}
      contentContainerStyle={styles.attachmentListContent}
      showsVerticalScrollIndicator={false}
    />
  );
}

function ImageViewerModal({
  attachments,
  visible,
  index,
  onIndexChange,
  onClose,
}: ImageViewerModalProps) {
  const colors = useColors() as ThemeColors;
  const insets = useSafeAreaInsets();
  const { width, height } = useWindowDimensions();
  const listRef = useRef<FlatList<ImageAttachment>>(null);

  useEffect(() => {
    if (!visible || attachments.length === 0) {
      return;
    }

    const timeout = setTimeout(() => {
      listRef.current?.scrollToIndex({
        index: Math.max(0, Math.min(index, attachments.length - 1)),
        animated: false,
      });
    }, 0);

    return () => {
      clearTimeout(timeout);
    };
  }, [attachments.length, index, visible]);

  const handleClose = useCallback(() => {
    triggerLightImpact();
    onClose();
  }, [onClose]);

  const handleMomentumEnd = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      const nextIndex = Math.round(event.nativeEvent.contentOffset.x / Math.max(width, 1));
      if (nextIndex !== index) {
        onIndexChange(nextIndex);
      }
    },
    [index, onIndexChange, width]
  );

  const handleScrollToIndexFailed = useCallback(
    ({ index: failedIndex }: { index: number }) => {
      requestAnimationFrame(() => {
        listRef.current?.scrollToOffset({
          offset: width * failedIndex,
          animated: false,
        });
      });
    },
    [width]
  );

  const renderItem = useCallback(
    ({ item }: ListRenderItemInfo<ImageAttachment>) => {
      const maxHeight = height - insets.top - insets.bottom - 96;

      return (
        <View style={[styles.viewerPage, { width }]}>
          <View style={[styles.viewerImageFrame, { maxWidth: width - 24, maxHeight }]}>
            <Image
              source={{ uri: getAttachmentUri(item) }}
              style={styles.viewerImage}
              contentFit="contain"
              transition={150}
            />
          </View>
        </View>
      );
    },
    [height, insets.bottom, insets.top, width]
  );

  if (attachments.length === 0) {
    return null;
  }

  return (
    <Modal
      visible={visible}
      animationType="fade"
      transparent={false}
      statusBarTranslucent
      onRequestClose={handleClose}
    >
      <View style={styles.viewerRoot}>
        <View style={[styles.viewerHeader, { paddingTop: insets.top + 10 }]}>
          <View
            style={[
              styles.viewerCounterChip,
              {
                backgroundColor: withOpacity(colors.surface, 0.18),
                borderColor: withOpacity('#FFFFFF', 0.12),
              },
            ]}
          >
            <Text style={styles.viewerCounterText}>
              {index + 1} of {attachments.length}
            </Text>
          </View>

          <Pressable
            onPress={handleClose}
            style={({ pressed }) => [
              styles.viewerCloseButton,
              {
                backgroundColor: withOpacity(colors.surface, pressed ? 0.28 : 0.18),
                borderColor: withOpacity('#FFFFFF', 0.12),
              },
            ]}
          >
            <MaterialIcons name="close" size={22} color="#FFFFFF" />
          </Pressable>
        </View>

        <FlatList
          ref={listRef}
          data={attachments}
          horizontal
          pagingEnabled
          initialScrollIndex={Math.max(0, Math.min(index, attachments.length - 1))}
          renderItem={renderItem}
          keyExtractor={(item, itemIndex) => `${item.uri}-${itemIndex}`}
          getItemLayout={(_, itemIndex) => ({
            length: width,
            offset: width * itemIndex,
            index: itemIndex,
          })}
          onMomentumScrollEnd={handleMomentumEnd}
          onScrollToIndexFailed={handleScrollToIndexFailed}
          showsHorizontalScrollIndicator={false}
          removeClippedSubviews={false}
          style={styles.viewerList}
        />
      </View>
    </Modal>
  );
}

export function MessageBubble({ message }: MessageBubbleProps) {
  const colors = useColors() as ThemeColors;
  const [copiedVisible, setCopiedVisible] = useState(false);
  const [viewerVisible, setViewerVisible] = useState(false);
  const [viewerIndex, setViewerIndex] = useState(0);
  const copiedTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const isUser = message.role === 'user';
  const hasText = message.content.trim().length > 0;
  const attachments = message.images ?? [];
  const hasAttachments = attachments.length > 0;
  const canCopy = hasText;
  const showMeta = !isUser && Boolean(message.model || message.effort);
  const shouldAutoExpandReasoning = Boolean(message.isStreaming && !message.content.trim());

  useEffect(() => {
    return () => {
      if (copiedTimeoutRef.current) {
        clearTimeout(copiedTimeoutRef.current);
      }
    };
  }, []);

  const bubbleStyle = useMemo(
    () => [
      styles.bubble,
      isUser ? styles.userBubble : styles.assistantBubble,
      isUser ? styles.userShadow : styles.assistantShadow,
      {
        backgroundColor: isUser ? colors.primary : withOpacity(colors.surface, Platform.OS === 'ios' ? 0.94 : 1),
        borderColor: isUser
          ? withOpacity('#FFFFFF', 0.12)
          : withOpacity(colors.border, Platform.OS === 'ios' ? 0.65 : 0.92),
      },
    ],
    [colors.border, colors.primary, colors.surface, isUser]
  );

  const handleCopyMessage = useCallback(async () => {
    if (!canCopy) {
      return;
    }

    try {
      await Clipboard.setStringAsync(message.content);
      triggerSuccessFeedback();
      setCopiedVisible(true);

      if (copiedTimeoutRef.current) {
        clearTimeout(copiedTimeoutRef.current);
      }

      copiedTimeoutRef.current = setTimeout(() => {
        setCopiedVisible(false);
      }, 1400);
    } catch {
      // Ignore clipboard errors.
    }
  }, [canCopy, message.content]);

  const handleImagePress = useCallback((index: number) => {
    triggerLightImpact();
    setViewerIndex(index);
    setViewerVisible(true);
  }, []);

  const handleViewerClose = useCallback(() => {
    setViewerVisible(false);
  }, []);

  return (
    <>
      <View style={[styles.row, isUser ? styles.userRow : styles.assistantRow]}>
        <View style={[styles.contentWrapper, isUser ? styles.userContentWrapper : styles.assistantContentWrapper]}>
          <Pressable
            onLongPress={canCopy ? handleCopyMessage : undefined}
            delayLongPress={220}
            style={({ pressed }) => [styles.bubblePressable, pressed && styles.pressed]}
          >
            <View style={bubbleStyle}>
              {!isUser ? (
                <AssistantMetaBadges model={message.model} effort={message.effort} colors={colors} />
              ) : null}

              {hasAttachments ? <AttachmentGrid attachments={attachments} onPressImage={handleImagePress} /> : null}

              {!isUser && message.reasoning ? (
                <ReasoningSection
                  reasoning={message.reasoning}
                  isStreaming={message.isStreaming}
                  defaultExpanded={shouldAutoExpandReasoning}
                  colors={colors}
                />
              ) : null}

              {hasText ? (
                isUser ? (
                  <Text style={styles.userText}>{message.content}</Text>
                ) : (
                  <MarkdownRenderer content={message.content} isStreaming={message.isStreaming} />
                )
              ) : !isUser && message.isStreaming && !message.reasoning ? (
                <MarkdownRenderer content="" isStreaming />
              ) : null}
            </View>
          </Pressable>

          {copiedVisible ? (
            <View
              style={[
                styles.copiedPill,
                isUser ? styles.copiedPillUser : styles.copiedPillAssistant,
                {
                  backgroundColor: withOpacity(colors.surface, 0.96),
                  borderColor: withOpacity(colors.border, 0.9),
                },
              ]}
            >
              <Text style={[styles.copiedPillText, { color: colors.muted }]}>Copied</Text>
            </View>
          ) : null}
        </View>
      </View>

      <ImageViewerModal
        attachments={attachments}
        visible={viewerVisible}
        index={viewerIndex}
        onIndexChange={setViewerIndex}
        onClose={handleViewerClose}
      />
    </>
  );
}

const styles = StyleSheet.create({
  row: {
    paddingHorizontal: 16,
    marginBottom: 14,
  },
  userRow: {
    alignItems: 'flex-end',
  },
  assistantRow: {
    alignItems: 'flex-start',
  },
  contentWrapper: {
    maxWidth: '100%',
  },
  userContentWrapper: {
    maxWidth: '84%',
    alignItems: 'flex-end',
  },
  assistantContentWrapper: {
    maxWidth: '90%',
    alignItems: 'flex-start',
  },
  bubblePressable: {
    maxWidth: '100%',
    alignSelf: 'stretch',
  },
  bubble: {
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
    padding: 8,
    gap: 8,
  },
  userBubble: {
    borderBottomRightRadius: 6,
    minWidth: 60,
  },
  assistantBubble: {
    borderBottomLeftRadius: 6,
    minWidth: 68,
  },
  userShadow: {
    shadowColor: '#000000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.12,
    shadowRadius: 16,
    elevation: 2,
  },
  assistantShadow: {
    shadowColor: '#000000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.08,
    shadowRadius: 20,
    elevation: 2,
  },
  pressed: {
    opacity: 0.94,
  },
  userText: {
    color: '#FFFFFF',
    fontSize: 16,
    lineHeight: 22,
    paddingHorizontal: 4,
    paddingVertical: 2,
  },
  metaRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 2,
  },
  metaBadge: {
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderWidth: StyleSheet.hairlineWidth,
    marginRight: 6,
    marginBottom: 2,
  },
  metaBadgeText: {
    fontSize: 11,
    fontWeight: '700',
  },
  attachmentListContent: {
    paddingBottom: 0,
  },
  attachmentColumnWrapper: {
    justifyContent: 'space-between',
  },
  singleAttachmentCell: {
    width: '100%',
  },
  multiAttachmentCell: {
    width: '48.7%',
    marginBottom: 8,
  },
  attachmentPressable: {
    borderRadius: 14,
    overflow: 'hidden',
  },
  attachmentImage: {
    width: '100%',
    borderRadius: 14,
    backgroundColor: 'rgba(127,127,127,0.12)',
  },
  reasoningContainer: {
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  reasoningHeader: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    minHeight: 44,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  reasoningTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  reasoningTitle: {
    fontSize: 13,
    fontWeight: '700',
  },
  reasoningLiveDot: {
    width: 7,
    height: 7,
    borderRadius: 3.5,
    marginLeft: 8,
  },
  reasoningRightRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  reasoningToggleText: {
    fontSize: 13,
    fontWeight: '600',
    marginRight: 2,
  },
  reasoningBody: {
    paddingHorizontal: 12,
    paddingBottom: 12,
    paddingTop: 2,
  },
  copiedPill: {
    marginTop: 6,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  copiedPillUser: {
    alignSelf: 'flex-end',
  },
  copiedPillAssistant: {
    alignSelf: 'flex-start',
  },
  copiedPillText: {
    fontSize: 12,
    fontWeight: '600',
  },
  viewerRoot: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.96)',
  },
  viewerHeader: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 10,
    paddingHorizontal: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  viewerCounterChip: {
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  viewerCounterText: {
    color: '#FFFFFF',
    fontSize: 13,
    fontWeight: '700',
  },
  viewerCloseButton: {
    width: 38,
    height: 38,
    borderRadius: 19,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  viewerList: {
    flex: 1,
  },
  viewerPage: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
  },
  viewerImageFrame: {
    width: '100%',
    height: '100%',
  },
  viewerImage: {
    width: '100%',
    height: '100%',
  },
});
