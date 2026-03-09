import React, { useState, useCallback, useMemo } from 'react';
import { View, Text, FlatList, TextInput, StyleSheet, Platform, Pressable, Alert } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { useColors } from '@/hooks/use-colors';
import { useChatStore } from '@/lib/chat-store';
import { Conversation } from '@/lib/types';
import { GlassCard } from '@/components/glass-card';
import { useRouter } from 'expo-router';

function formatTime(ts: number): string {
  const now = Date.now();
  const diff = now - ts;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'Just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(ts).toLocaleDateString();
}

export default function ConversationsScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { state, setActiveConversation, deleteConversation, createNewConversation } = useChatStore();
  const [searchQuery, setSearchQuery] = useState('');

  const filteredConversations = useMemo(() => {
    if (!searchQuery.trim()) return state.conversations;
    const q = searchQuery.toLowerCase();
    return state.conversations.filter(
      (c) =>
        c.title.toLowerCase().includes(q) ||
        c.messages.some((m) => m.content.toLowerCase().includes(q))
    );
  }, [state.conversations, searchQuery]);

  const handleSelect = useCallback(
    (conv: Conversation) => {
      if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      setActiveConversation(conv.id);
      router.navigate('/(tabs)');
    },
    [setActiveConversation, router]
  );

  const handleDelete = useCallback(
    (conv: Conversation) => {
      if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      if (Platform.OS === 'web') {
        if (confirm('Delete this conversation?')) {
          deleteConversation(conv.id);
        }
      } else {
        Alert.alert('Delete Conversation', `Delete "${conv.title}"?`, [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Delete',
            style: 'destructive',
            onPress: () => deleteConversation(conv.id),
          },
        ]);
      }
    },
    [deleteConversation]
  );

  const handleNewChat = useCallback(() => {
    if (Platform.OS !== 'web') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    createNewConversation();
    router.navigate('/(tabs)');
  }, [createNewConversation, router]);

  const getLastMessage = (conv: Conversation): string => {
    if (conv.messages.length === 0) return 'No messages yet';
    const last = conv.messages[conv.messages.length - 1];
    const preview = last.content.slice(0, 80);
    return preview + (last.content.length > 80 ? '...' : '');
  };

  const renderItem = useCallback(
    ({ item }: { item: Conversation }) => (
      <Pressable
        onPress={() => handleSelect(item)}
        onLongPress={() => handleDelete(item)}
        style={({ pressed }) => [{ opacity: pressed ? 0.7 : 1 }]}
      >
        <GlassCard style={styles.convCard}>
          <View style={styles.convHeader}>
            <Text style={[styles.convTitle, { color: colors.foreground }]} numberOfLines={1}>
              {item.title}
            </Text>
            <Text style={[styles.convTime, { color: colors.muted }]}>{formatTime(item.updatedAt)}</Text>
          </View>
          <Text style={[styles.convPreview, { color: colors.muted }]} numberOfLines={2}>
            {getLastMessage(item)}
          </Text>
          <View style={styles.convFooter}>
            <View style={[styles.modelBadge, { backgroundColor: colors.primary + '15' }]}>
              <Text style={[styles.modelBadgeText, { color: colors.primary }]}>
                {item.model === 'gpt-5.4-pro' ? 'Pro' : '5.4'} · {item.effort}
              </Text>
            </View>
            <Text style={[styles.msgCount, { color: colors.muted }]}>
              {item.messages.length} messages
            </Text>
          </View>
        </GlassCard>
      </Pressable>
    ),
    [colors, handleSelect, handleDelete]
  );

  return (
    <View style={[styles.screen, { backgroundColor: colors.background }]}>
      {/* Header */}
      <View style={[styles.header, { paddingTop: insets.top + 8 }]}>
        <GlassCard style={styles.headerGlass}>
          <View style={styles.headerRow}>
            <Text style={[styles.headerTitle, { color: colors.foreground }]}>Chats</Text>
            <Pressable
              onPress={handleNewChat}
              style={({ pressed }) => [styles.newBtn, { backgroundColor: colors.primary, opacity: pressed ? 0.8 : 1 }]}
            >
              <MaterialIcons name="add" size={22} color="#FFFFFF" />
            </Pressable>
          </View>
        </GlassCard>
      </View>

      {/* Search */}
      <View style={styles.searchContainer}>
        <View style={[styles.searchBar, { backgroundColor: colors.surface, borderColor: colors.border }]}>
          <MaterialIcons name="search" size={20} color={colors.muted} />
          <TextInput
            style={[styles.searchInput, { color: colors.foreground }]}
            placeholder="Search conversations..."
            placeholderTextColor={colors.muted}
            value={searchQuery}
            onChangeText={setSearchQuery}
            returnKeyType="search"
          />
          {searchQuery.length > 0 && (
            <Pressable onPress={() => setSearchQuery('')}>
              <MaterialIcons name="close" size={18} color={colors.muted} />
            </Pressable>
          )}
        </View>
      </View>

      {/* List */}
      <FlatList
        data={filteredConversations}
        renderItem={renderItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={[
          styles.listContent,
          filteredConversations.length === 0 && styles.emptyList,
        ]}
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <MaterialIcons name="chat-bubble-outline" size={56} color={colors.muted} />
            <Text style={[styles.emptyText, { color: colors.muted }]}>
              {searchQuery ? 'No conversations found' : 'No conversations yet'}
            </Text>
            {!searchQuery && (
              <Pressable
                onPress={handleNewChat}
                style={({ pressed }) => [styles.startBtn, { backgroundColor: colors.primary, opacity: pressed ? 0.8 : 1 }]}
              >
                <Text style={styles.startBtnText}>Start a new chat</Text>
              </Pressable>
            )}
          </View>
        }
        showsVerticalScrollIndicator={false}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  header: {
    zIndex: 10,
  },
  headerGlass: {
    borderRadius: 0,
    paddingHorizontal: 20,
    paddingVertical: 12,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerTitle: {
    fontSize: 32,
    fontWeight: '800',
  },
  newBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  searchContainer: {
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 12,
    borderWidth: 1,
    paddingHorizontal: 12,
    height: 40,
    gap: 8,
  },
  searchInput: {
    flex: 1,
    fontSize: 15,
  },
  listContent: {
    paddingHorizontal: 16,
    paddingBottom: 100,
    gap: 10,
  },
  emptyList: {
    flex: 1,
  },
  convCard: {
    padding: 16,
    gap: 6,
  },
  convHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  convTitle: {
    fontSize: 16,
    fontWeight: '600',
    flex: 1,
    marginRight: 8,
  },
  convTime: {
    fontSize: 12,
  },
  convPreview: {
    fontSize: 14,
    lineHeight: 19,
  },
  convFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: 4,
  },
  modelBadge: {
    borderRadius: 6,
    paddingHorizontal: 8,
    paddingVertical: 2,
  },
  modelBadgeText: {
    fontSize: 11,
    fontWeight: '600',
  },
  msgCount: {
    fontSize: 11,
  },
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    paddingTop: 80,
  },
  emptyText: {
    fontSize: 16,
  },
  startBtn: {
    borderRadius: 20,
    paddingHorizontal: 24,
    paddingVertical: 10,
    marginTop: 8,
  },
  startBtnText: {
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: '600',
  },
});
