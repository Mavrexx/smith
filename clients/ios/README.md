# Smith native iPhone companion

This is an XcodeGen-compatible SwiftUI source project for the existing Smith Core. It is not a second assistant and contains no Gemini API key, Neon URL, server access code, Tailscale key, signing key, or notification credential.

## Environmental interface

The iPhone app now follows the Smith environmental design:

- Idle: a perfectly centred Smith orb, subtle blueprint grid, time, date and a small connection/privacy status only.
- Awake: Smith stays central while a one-handed Command Centre grows around the orb.
- Workspace: requested content appears beneath a compact, always-visible Smith orb.
- Conversation: never the default screen; it opens only from the Command Centre, a deep link, or a command such as `Smith, pull up chat`.
- Closing Conversation returns to Command Centre. Closing another workspace restores centred idle.
- The first orb tap requests microphone permission when required. The same Gemini Live session then remains hands-free and interruptible until muted or stopped.

## Generate and test on a Mac

1. Install current Xcode and command-line tools.
2. Install XcodeGen with Homebrew: `brew install xcodegen`.
3. Copy this folder to the Mac or open the repository through a trusted private workflow.
4. Replace bundle identifiers and `group.com.farhan.smith` with identifiers owned by your Apple team.
5. Replace `YOUR-TAILNET-HOST.ts.net` in entitlements. Keep the `smith://` scheme because private Tailscale universal links have an Apple-CDN limitation.
6. Run `xcodegen generate` inside `clients/ios`.
7. Open `Smith.xcodeproj`, choose your team for all targets, and enable the declared capabilities.
8. Run the `SmithTests` unit-test target, then build in Simulator and on a physical iPhone.
9. Enter the private Tailscale HTTPS origin in Settings and register with the existing one-time setup access code. The code is not persisted.

## Architecture

- `SmithModel`: idle/awake/workspace state machine; Conversation is optional, not the root interface.
- `SmithEnvironmentIntentParser`: deterministic allow-listed UI command parser; ordinary conversation does not move the interface.
- `SmithAPI`: HTTPS-only Core configuration, Keychain device credential, short session, and one-time realtime ticket.
- `SmithVoiceSession`: the existing Smith JSON protocol at `/ws/smith/realtime`, user/assistant transcript separation, heartbeat, reconnect, barge-in reset and immediate microphone mute.
- `SmithAudioController`: AVAudioSession voice-chat mode, PCM16 capture at 16 kHz, PCM16 output at 24 kHz, Bluetooth routing, call/route recovery and definite stop.
- `SmithIntents`, `SmithWidgets`, `SmithShare`, `SmithNotificationService`: Siri/Shortcuts, Live Activity, Share Extension and notification scaffolds around the same Core.
- `SmithKeychain`: this-device-only credential persistence.

## Apple-host verification still required

This Windows/WSL host cannot compile, sign, simulate or install an iOS app. On a Mac, run XcodeGen, `xcodebuild test`, a Simulator layout pass and a physical-iPhone pass covering microphone permission, always-listening mute/unmute, interruption, reconnect, lock screen, Bluetooth and Tailscale network handoff. Signing, App Groups, Siri, associated domains, push, Live Activities, app icons and privacy-manifest provisioning remain Apple-team responsibilities.
