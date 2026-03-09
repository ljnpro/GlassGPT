import AsyncStorage from "@react-native-async-storage/async-storage";
import { Platform } from "react-native";
import * as SecureStore from "expo-secure-store";

export const API_KEY_STORAGE_KEY = "openai_api_key";

let secureStoreAvailabilityPromise: Promise<boolean> | null = null;

async function isSecureStoreAvailable(): Promise<boolean> {
  if (Platform.OS === "web") {
    return false;
  }

  if (!secureStoreAvailabilityPromise) {
    secureStoreAvailabilityPromise = SecureStore.isAvailableAsync().catch(() => false);
  }

  return secureStoreAvailabilityPromise;
}

async function setStoredValue(key: string, value: string): Promise<void> {
  if (Platform.OS === "web") {
    await AsyncStorage.setItem(key, value);
    return;
  }

  if (await isSecureStoreAvailable()) {
    await SecureStore.setItemAsync(key, value);
    await AsyncStorage.removeItem(key);
    return;
  }

  await AsyncStorage.setItem(key, value);
}

async function getStoredValue(key: string): Promise<string | null> {
  if (Platform.OS === "web") {
    return AsyncStorage.getItem(key);
  }

  if (await isSecureStoreAvailable()) {
    const secureValue = await SecureStore.getItemAsync(key);
    if (secureValue !== null) {
      return secureValue;
    }
  }

  return AsyncStorage.getItem(key);
}

async function deleteStoredValue(key: string): Promise<void> {
  if (Platform.OS === "web") {
    await AsyncStorage.removeItem(key);
    return;
  }

  if (await isSecureStoreAvailable()) {
    await SecureStore.deleteItemAsync(key);
  }

  await AsyncStorage.removeItem(key);
}

export async function saveApiKey(key: string): Promise<void> {
  const normalizedKey = key.trim();

  if (!normalizedKey) {
    await deleteApiKey();
    return;
  }

  await setStoredValue(API_KEY_STORAGE_KEY, normalizedKey);
}

export async function getApiKey(): Promise<string | null> {
  const value = await getStoredValue(API_KEY_STORAGE_KEY);
  const normalizedValue = value?.trim() ?? "";
  return normalizedValue.length > 0 ? normalizedValue : null;
}

export async function deleteApiKey(): Promise<void> {
  await deleteStoredValue(API_KEY_STORAGE_KEY);
}
