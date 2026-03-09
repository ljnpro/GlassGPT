import { Platform } from 'react-native';
import * as SecureStore from 'expo-secure-store';

const API_KEY_STORAGE = 'openai_api_key';

export async function saveApiKey(key: string): Promise<void> {
  if (Platform.OS === 'web') {
    localStorage.setItem(API_KEY_STORAGE, key);
  } else {
    await SecureStore.setItemAsync(API_KEY_STORAGE, key);
  }
}

export async function getApiKey(): Promise<string | null> {
  if (Platform.OS === 'web') {
    return localStorage.getItem(API_KEY_STORAGE);
  }
  return SecureStore.getItemAsync(API_KEY_STORAGE);
}

export async function deleteApiKey(): Promise<void> {
  if (Platform.OS === 'web') {
    localStorage.removeItem(API_KEY_STORAGE);
  } else {
    await SecureStore.deleteItemAsync(API_KEY_STORAGE);
  }
}
