import React, { useState, useRef, useCallback } from 'react';
import { View, TextInput, Text, Pressable, StyleSheet, Platform, KeyboardAvoidingView } from 'react-native';
import { Image } from 'expo-image';
import * as ImagePicker from 'expo-image-picker';
import * as Haptics from 'expo-haptics';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/use-colors';
import { ImageAttachment } from '@/lib/types';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';

interface ChatInputProps {
  onSend: (text: string, images?: ImageAttachment[]) => void;
  onStop?: () => void;
  isStreaming?: boolean;
  disabled?: boolean;
}

export function ChatInput({ onSend, onStop, isStreaming, disabled }: ChatInputProps) {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const [text, setText] = useState('');
  const [images, setImages] = useState<ImageAttachment[]>([]);
  const inputRef = useRef<TextInput>(null);

  const handlePickImage = useCallback(async () => {
    try {
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        allowsMultipleSelection: true,
        quality: 0.8,
        base64: true,
      });

      if (!result.canceled && result.assets) {
        const newImages: ImageAttachment[] = result.assets.map((asset) => ({
          uri: asset.uri,
          base64: asset.base64 || undefined,
          width: asset.width,
          height: asset.height,
          mimeType: asset.mimeType || 'image/jpeg',
        }));
        setImages((prev) => [...prev, ...newImages]);
        if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      }
    } catch (err) {
      console.error('Image picker error:', err);
    }
  }, []);

  const handleRemoveImage = useCallback((idx: number) => {
    setImages((prev) => prev.filter((_, i) => i !== idx));
    if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }, []);

  const handleSend = useCallback(() => {
    const trimmed = text.trim();
    if (!trimmed && images.length === 0) return;
    if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    onSend(trimmed, images.length > 0 ? images : undefined);
    setText('');
    setImages([]);
  }, [text, images, onSend]);

  const handleStop = useCallback(() => {
    if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    onStop?.();
  }, [onStop]);

  const canSend = (text.trim().length > 0 || images.length > 0) && !isStreaming && !disabled;

  const bottomPadding = Platform.OS === 'web' ? 16 : Math.max(insets.bottom, 12);

  return (
    <View style={[styles.container, { backgroundColor: colors.background, borderTopColor: colors.border, paddingBottom: bottomPadding }]}>
      {/* Image previews */}
      {images.length > 0 && (
        <View style={styles.imagePreviewRow}>
          {images.map((img, idx) => (
            <View key={idx} style={styles.imagePreviewWrapper}>
              <Image source={{ uri: img.uri }} style={styles.imagePreview} contentFit="cover" />
              <Pressable
                onPress={() => handleRemoveImage(idx)}
                style={({ pressed }) => [styles.removeImageBtn, { backgroundColor: colors.error, opacity: pressed ? 0.7 : 1 }]}
              >
                <Text style={{ color: '#FFF', fontSize: 12, fontWeight: '700' }}>✕</Text>
              </Pressable>
            </View>
          ))}
        </View>
      )}

      {/* Input row */}
      <View style={[styles.inputRow, { backgroundColor: colors.surface, borderColor: colors.border }]}>
        {/* Image picker button */}
        <Pressable
          onPress={handlePickImage}
          disabled={isStreaming || disabled}
          style={({ pressed }) => [styles.iconBtn, { opacity: pressed ? 0.5 : isStreaming ? 0.3 : 1 }]}
        >
          <MaterialIcons name="add-photo-alternate" size={24} color={colors.primary} />
        </Pressable>

        {/* Text input */}
        <TextInput
          ref={inputRef}
          style={[styles.textInput, { color: colors.foreground }]}
          placeholder="Message..."
          placeholderTextColor={colors.muted}
          value={text}
          onChangeText={setText}
          multiline
          maxLength={32000}
          editable={!isStreaming && !disabled}
          returnKeyType="default"
          blurOnSubmit={false}
        />

        {/* Send or Stop button */}
        {isStreaming ? (
          <Pressable
            onPress={handleStop}
            style={({ pressed }) => [styles.sendBtn, { backgroundColor: colors.error, opacity: pressed ? 0.8 : 1 }]}
          >
            <MaterialIcons name="stop" size={20} color="#FFFFFF" />
          </Pressable>
        ) : (
          <Pressable
            onPress={handleSend}
            disabled={!canSend}
            style={({ pressed }) => [
              styles.sendBtn,
              {
                backgroundColor: canSend ? colors.primary : colors.border,
                opacity: pressed && canSend ? 0.8 : 1,
              },
            ]}
          >
            <MaterialIcons name="arrow-upward" size={20} color="#FFFFFF" />
          </Pressable>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingTop: 8,
  },
  imagePreviewRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 8,
    paddingHorizontal: 4,
  },
  imagePreviewWrapper: {
    position: 'relative',
  },
  imagePreview: {
    width: 64,
    height: 64,
    borderRadius: 10,
  },
  removeImageBtn: {
    position: 'absolute',
    top: -4,
    right: -4,
    width: 20,
    height: 20,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    borderRadius: 24,
    borderWidth: 1,
    paddingHorizontal: 6,
    paddingVertical: 4,
    minHeight: 44,
    gap: 4,
  },
  iconBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  textInput: {
    flex: 1,
    fontSize: 16,
    lineHeight: 22,
    maxHeight: 120,
    paddingVertical: 8,
    paddingHorizontal: 4,
  },
  sendBtn: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 1,
  },
});
