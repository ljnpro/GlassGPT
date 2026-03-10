import React, { useCallback, useMemo, useRef, useState } from "react";
import {
  Alert,
  FlatList,
  Platform,
  Pressable,
  StyleSheet,
  TextInput,
  View,
  type ListRenderItem,
  type NativeSyntheticEvent,
  type TextInputContentSizeChangeEventData,
} from "react-native";
import { Image } from "expo-image";
import * as ImagePicker from "expo-image-picker";
import * as ImageManipulator from "expo-image-manipulator";
import * as Haptics from "expo-haptics";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useColors } from "@/hooks/use-colors";
import { GlassCard } from "./glass-card";
import { IconSymbol } from "@/components/ui/icon-symbol";
import { type ImageAttachment } from "@/lib/types";

interface ChatInputProps {
  onSend: (text: string, images?: ImageAttachment[]) => void;
  onStop?: () => void;
  isStreaming?: boolean;
  disabled?: boolean;
}

const MAX_ATTACHMENTS = 8;
const TEXT_LINE_HEIGHT = 22;
const MIN_INPUT_HEIGHT = 22;
const MAX_INPUT_HEIGHT = TEXT_LINE_HEIGHT * 6;

export function ChatInput({
  onSend,
  onStop,
  isStreaming = false,
  disabled = false,
}: ChatInputProps) {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const inputRef = useRef<TextInput>(null);

  const [text, setText] = useState("");
  const [attachments, setAttachments] = useState<ImageAttachment[]>([]);
  const [inputHeight, setInputHeight] = useState(MIN_INPUT_HEIGHT);
  const [isPickingImage, setIsPickingImage] = useState(false);

  const isDark = colors.background.toLowerCase() === "#000000";
  const trimmedText = text.trim();

  const canPickImages = !disabled && !isStreaming && !isPickingImage;
  const canSend = !disabled && !isStreaming && (trimmedText.length > 0 || attachments.length > 0);
  const composerInputHeight = useMemo(() => {
    return Math.max(MIN_INPUT_HEIGHT, Math.min(MAX_INPUT_HEIGHT, inputHeight));
  }, [inputHeight]);

  const bottomPadding = Platform.OS === "web" ? 14 : Math.max(insets.bottom, 12);
  const secondaryButtonBackground = isDark
    ? "rgba(255,255,255,0.08)"
    : "rgba(120,120,128,0.12)";
  const previewRemoveBackground = isDark
    ? "rgba(28,28,30,0.92)"
    : "rgba(255,255,255,0.92)";
  const thumbnailBorderColor = isDark
    ? "rgba(255,255,255,0.10)"
    : "rgba(60,60,67,0.10)";
  const disabledSendBackground = isDark
    ? "rgba(118,118,128,0.20)"
    : "rgba(120,120,128,0.22)";

  const playLightHaptic = useCallback(async () => {
    if (Platform.OS !== "web") {
      await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    }
  }, []);

  const playMediumHaptic = useCallback(async () => {
    if (Platform.OS !== "web") {
      await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    }
  }, []);

  const handleContentSizeChange = useCallback(
    (event: NativeSyntheticEvent<TextInputContentSizeChangeEventData>) => {
      const nextHeight = Math.max(
        MIN_INPUT_HEIGHT,
        Math.min(MAX_INPUT_HEIGHT, Math.ceil(event.nativeEvent.contentSize.height))
      );

      if (Math.abs(nextHeight - inputHeight) > 1) {
        setInputHeight(nextHeight);
      }
    },
    [inputHeight]
  );

  const handlePickImage = useCallback(async () => {
    if (!canPickImages) {
      return;
    }

    const remainingSlots = MAX_ATTACHMENTS - attachments.length;

    if (remainingSlots <= 0) {
      Alert.alert(
        "Attachment limit reached",
        `You can attach up to ${MAX_ATTACHMENTS} images to one message.`
      );
      return;
    }

    try {
      setIsPickingImage(true);

      if (Platform.OS !== "web") {
        const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();

        if (!permission.granted) {
          Alert.alert(
            "Photos access required",
            "Allow photo library access to attach images to your message."
          );
          return;
        }
      }

      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ["images"],
        allowsMultipleSelection: remainingSlots > 1,
        selectionLimit: remainingSlots,
        quality: 0.9,
        // Don't request base64 from picker – we'll get it from ImageManipulator
        // after converting to JPEG (handles HEIC and other unsupported formats).
        base64: false,
      });

      if (result.canceled || !result.assets?.length) {
        return;
      }

      // Convert every picked image to JPEG via ImageManipulator.
      // This ensures HEIC and other non-standard formats are converted to a
      // format that OpenAI accepts, and gives us a clean base64 string.
      const nextAttachments: ImageAttachment[] = await Promise.all(
        result.assets.map(async (asset) => {
          try {
            const manipulated = await ImageManipulator.manipulateAsync(
              asset.uri,
              // Resize large images to max 2048px on longest side to save tokens
              asset.width > 2048 || asset.height > 2048
                ? [
                    asset.width >= asset.height
                      ? { resize: { width: 2048 } }
                      : { resize: { height: 2048 } },
                  ]
                : [],
              {
                compress: 0.85,
                format: ImageManipulator.SaveFormat.JPEG,
                base64: true,
              }
            );

            return {
              uri: manipulated.uri,
              base64: manipulated.base64 ?? undefined,
              width: manipulated.width,
              height: manipulated.height,
              mimeType: "image/jpeg" as const,
            };
          } catch (manipError) {
            // Fallback: use original asset if manipulation fails
            console.warn("Image manipulation failed, using original:", manipError);
            return {
              uri: asset.uri,
              base64: asset.base64 ?? undefined,
              width: asset.width,
              height: asset.height,
              mimeType: (asset.mimeType ?? "image/jpeg") as string,
            };
          }
        })
      );

      setAttachments((current) => [...current, ...nextAttachments].slice(0, MAX_ATTACHMENTS));
      await playLightHaptic();

      requestAnimationFrame(() => {
        inputRef.current?.focus();
      });
    } catch (error) {
      console.error("Failed to pick an image:", error);
      Alert.alert("Unable to attach image", "Please try again.");
    } finally {
      setIsPickingImage(false);
    }
  }, [attachments.length, canPickImages, playLightHaptic]);

  const handleRemoveAttachment = useCallback(
    async (index: number) => {
      setAttachments((current) => current.filter((_, currentIndex) => currentIndex !== index));
      await playLightHaptic();
    },
    [playLightHaptic]
  );

  const handleSend = useCallback(async () => {
    if (!canSend) {
      return;
    }

    await playLightHaptic();
    onSend(trimmedText, attachments.length > 0 ? attachments : undefined);

    setText("");
    setAttachments([]);
    setInputHeight(MIN_INPUT_HEIGHT);

    requestAnimationFrame(() => {
      inputRef.current?.focus();
    });
  }, [attachments, canSend, onSend, playLightHaptic, trimmedText]);

  const handleStop = useCallback(async () => {
    await playMediumHaptic();
    onStop?.();
  }, [onStop, playMediumHaptic]);

  const renderAttachment: ListRenderItem<ImageAttachment> = useCallback(
    ({ item, index }) => {
      return (
        <View style={styles.thumbnailShell}>
          <View
            style={[
              styles.thumbnailFrame,
              {
                borderColor: thumbnailBorderColor,
                backgroundColor: colors.surface,
              },
            ]}
          >
            <Image
              source={{ uri: item.uri }}
              style={styles.thumbnailImage}
              contentFit="cover"
              transition={120}
            />
          </View>

          <Pressable
            onPress={() => {
              void handleRemoveAttachment(index);
            }}
            hitSlop={8}
            style={({ pressed }) => [
              styles.removeAttachmentButton,
              {
                backgroundColor: previewRemoveBackground,
                opacity: pressed ? 0.8 : 1,
              },
            ]}
          >
            <IconSymbol
              name="xmark.circle.fill"
              size={18}
              color={colors.error}
            />
          </Pressable>
        </View>
      );
    },
    [colors.error, colors.surface, handleRemoveAttachment, previewRemoveBackground, thumbnailBorderColor]
  );

  return (
    <View style={[styles.outer, { paddingBottom: bottomPadding }]}>
      {attachments.length > 0 ? (
        <GlassCard style={styles.previewCard}>
          <FlatList
            data={attachments}
            horizontal
            keyExtractor={(item, index) => `${item.uri}-${index}`}
            renderItem={renderAttachment}
            showsHorizontalScrollIndicator={false}
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={styles.previewListContent}
            ItemSeparatorComponent={() => <View style={styles.thumbnailSeparator} />}
          />
        </GlassCard>
      ) : null}

      <GlassCard style={styles.composerCard}>
        <View style={styles.composerRow}>
          <Pressable
            onPress={() => {
              void handlePickImage();
            }}
            disabled={!canPickImages}
            style={({ pressed }) => [
              styles.secondaryButton,
              {
                backgroundColor: secondaryButtonBackground,
                opacity: pressed ? 0.78 : canPickImages ? 1 : 0.45,
              },
            ]}
          >
            <IconSymbol
              name="photo"
              size={20}
              color={canPickImages ? colors.primary : colors.muted}
            />
          </Pressable>

          <View style={styles.inputColumn}>
            <TextInput
              ref={inputRef}
              value={text}
              onChangeText={setText}
              onContentSizeChange={handleContentSizeChange}
              style={[
                styles.input,
                {
                  color: colors.foreground,
                  height: composerInputHeight,
                },
              ]}
              placeholder={disabled ? "Add your OpenAI API key in Settings" : "Message"}
              placeholderTextColor={colors.muted}
              multiline
              maxLength={32000}
              editable={!disabled && !isStreaming}
              scrollEnabled={composerInputHeight >= MAX_INPUT_HEIGHT}
              autoCorrect
              blurOnSubmit={false}
              returnKeyType="default"
              textAlignVertical="top"
              keyboardAppearance={isDark ? "dark" : "light"}
            />
          </View>

          {isStreaming ? (
            <Pressable
              onPress={() => {
                void handleStop();
              }}
              style={({ pressed }) => [
                styles.sendButton,
                {
                  backgroundColor: colors.error,
                  opacity: pressed ? 0.84 : 1,
                },
              ]}
            >
              <IconSymbol
                name="stop.fill"
                size={16}
                color="#FFFFFF"
              />
            </Pressable>
          ) : (
            <Pressable
              onPress={() => {
                void handleSend();
              }}
              disabled={!canSend}
              style={({ pressed }) => [
                styles.sendButton,
                {
                  backgroundColor: canSend ? colors.primary : disabledSendBackground,
                  opacity: pressed ? 0.84 : canSend ? 1 : 0.9,
                },
              ]}
            >
              <IconSymbol
                name="paperplane.fill"
                size={18}
                color={canSend ? "#FFFFFF" : "rgba(255,255,255,0.82)"}
              />
            </Pressable>
          )}
        </View>
      </GlassCard>
    </View>
  );
}

const styles = StyleSheet.create({
  outer: {
    paddingHorizontal: 12,
    paddingTop: 8,
  },
  previewCard: {
    borderRadius: 20,
    paddingVertical: 10,
    paddingHorizontal: 10,
    marginBottom: 8,
  },
  previewListContent: {
    paddingRight: 2,
  },
  thumbnailSeparator: {
    width: 10,
  },
  thumbnailShell: {
    position: "relative",
  },
  thumbnailFrame: {
    width: 72,
    height: 72,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: "hidden",
  },
  thumbnailImage: {
    width: "100%",
    height: "100%",
  },
  removeAttachmentButton: {
    position: "absolute",
    top: -6,
    right: -6,
    width: 24,
    height: 24,
    borderRadius: 12,
    alignItems: "center",
    justifyContent: "center",
    shadowColor: "#000000",
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.18,
    shadowRadius: 6,
    elevation: 4,
  },
  composerCard: {
    borderRadius: 28,
    paddingHorizontal: 8,
    paddingVertical: 6,
  },
  composerRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  secondaryButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: "center",
    justifyContent: "center",
  },
  inputColumn: {
    flex: 1,
    minHeight: 36,
    justifyContent: "center",
  },
  input: {
    fontSize: 17,
    lineHeight: TEXT_LINE_HEIGHT,
    paddingTop: 0,
    paddingBottom: 0,
    paddingHorizontal: 2,
    minHeight: MIN_INPUT_HEIGHT,
    maxHeight: MAX_INPUT_HEIGHT,
  },
  sendButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: "center",
    justifyContent: "center",
  },
});
