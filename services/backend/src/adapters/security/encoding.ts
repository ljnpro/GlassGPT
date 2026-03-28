const HEX_RADIX = 16;

export const decodeHex = (value: string): Uint8Array => {
  if (value.length % 2 !== 0) {
    throw new Error('invalid_hex_length');
  }

  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < value.length; index += 2) {
    const byte = Number.parseInt(value.slice(index, index + 2), HEX_RADIX);
    if (Number.isNaN(byte)) {
      throw new Error('invalid_hex_payload');
    }
    bytes[index / 2] = byte;
  }

  return bytes;
};

export const encodeBase64Url = (value: ArrayBuffer | Uint8Array): string => {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
};

export const decodeBase64Url = (value: string): Uint8Array => {
  const normalized = value.replaceAll('-', '+').replaceAll('_', '/');
  const padding = normalized.length % 4 === 0 ? '' : '='.repeat(4 - (normalized.length % 4));
  const binary = atob(`${normalized}${padding}`);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
};
