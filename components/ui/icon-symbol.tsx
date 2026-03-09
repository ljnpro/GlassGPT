import MaterialIcons from "@expo/vector-icons/MaterialIcons";
import { type SymbolWeight } from "expo-symbols";
import { type ComponentProps } from "react";
import {
  type OpaqueColorValue,
  type StyleProp,
  type TextStyle,
} from "react-native";

const MAPPING = {
  "house.fill": "home",
  "clock.fill": "history",
  "gearshape.fill": "settings",
  "paperplane.fill": "send",
  "plus.circle.fill": "add-circle",
  "xmark.circle.fill": "cancel",
  photo: "photo",
  "stop.fill": "stop",
  "chevron.down": "expand-more",
  "square.on.square": "content-copy",
  trash: "delete-outline",
  magnifyingglass: "search",
  eye: "visibility",
  "eye.slash": "visibility-off",
  eraser: "backspace",
  "checkmark.circle.fill": "check-circle",
  "chevron.left.forwardslash.chevron.right": "code",
  "chevron.right": "chevron-right",
  "bubble.left.and.bubble.right.fill": "chat",
  "plus.bubble.fill": "add-comment",
  "text.bubble.fill": "chat-bubble",
} as const satisfies Record<string, ComponentProps<typeof MaterialIcons>["name"]>;

export type IconSymbolName = keyof typeof MAPPING;

export function IconSymbol({
  name,
  size = 24,
  color,
  style,
}: {
  name: IconSymbolName;
  size?: number;
  color: string | OpaqueColorValue;
  style?: StyleProp<TextStyle>;
  weight?: SymbolWeight;
}) {
  return <MaterialIcons color={color} size={size} name={MAPPING[name]} style={style} />;
}
