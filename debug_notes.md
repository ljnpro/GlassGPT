# ModelBadge Debug Notes

## Screenshot Observation (IMG_7847.PNG)
- Top-left: A glass capsule/circle containing only a chevron.down (V) icon — NO text visible
- Top-right: A glass circle containing the square.and.pencil icon (new chat button) — this renders correctly
- The ModelBadge HStack has: Text(model.displayName) + "·" + Text(effort.displayName) + chevron.down
- But only the chevron.down is visible — all Text views are invisible/hidden

## Root Cause (CONFIRMED from Reddit r/iOSProgramming)
iOS 26 treats absolutely anything in a toolbar like a button and prefers icon-only style.
SwiftUI aggressively truncates/hides text in toolbar items, especially in topBarLeading.

## Solution (CONFIRMED working from Reddit)
Two key modifiers needed:
1. `.fixedSize(horizontal: true, vertical: false)` — prevents text truncation
2. `.sharedBackgroundVisibility(.hidden)` — removes the automatic glass background (optional, since we apply our own)

Example that works:
```swift
ToolbarItem(placement: .topBarLeading) {
    Text("Format")
        .font(.title2)
        .fixedSize(horizontal: true, vertical: false)
}
.sharedBackgroundVisibility(.hidden)
```

## Plan
Apply `.fixedSize(horizontal: true, vertical: false)` to the ModelBadge's outer HStack.
