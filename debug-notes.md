# Bug Analysis

## Issues Found:
1. **Model selector dropdown not working** - The Modal opens but the Pressable inside it uses `e.stopPropagation()` which may not work on web. Need to test the actual click behavior.
2. **API key input not working** - Need to check if TextInput is properly receiving focus on web. The `secureTextEntry` might cause issues.
3. **UI looks plain** - Need to:
   - Add more glass effects and depth
   - Better color scheme
   - More visual polish
   - Better spacing and typography
   - Gradient accents

## Root Causes:
- Model selector: The `handleModelChange` and `handleEffortChange` only work when there's an active conversation. If no conversation exists, changes are silently dropped.
- Settings API key: The TextInput may have focus issues. Need to verify.
- UI: Needs complete visual overhaul with better colors, gradients, and glass effects.

## Fix Plan:
1. Fix model selector to work without active conversation (update defaults)
2. Fix API key input
3. Complete UI redesign with premium look
