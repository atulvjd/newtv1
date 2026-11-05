# Newtv1

A native macOS voice control app built with SwiftUI, Speech, Accessibility, and Quartz. No JavaScript runtime, cloud account, or API key required for the built-in commands.

Newtv1 lives at the MacBook notch. It starts as an accessory app with no Dock icon or dashboard window. Hover over the notch to expand it; move away to collapse it. Click the sparkle or pin button to keep the controls expanded. The compact wings show microphone and execution status without placing controls behind the camera. The expanded panel includes live transcription, listening, Stop, and a command-center button. Closing the command center leaves the notch running.

The panel uses [NSScreen safe-area and auxiliary-area geometry](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea-gr2n) and follows the built-in notched display when available. Reconnecting displays recalculates placement. A display without a camera cutout gets a top-center island. The panel joins desktop Spaces and uses the full-screen auxiliary window behavior; system-owned screens such as the lock screen remain outside its control.

Newtv1 is a working first implementation, not a kernel extension or a claim of superiority to commercial voice assistants. Its control comes from macOS permissions. It does not bypass System Integrity Protection, control secure password fields, or guarantee access to every app.

## Build and open

Requires an Apple silicon or Intel Mac running macOS 13+, and the Xcode command line tools with Swift 5.9+.

```sh
bash scripts/build-app.sh
open dist/Newtv1.app
```

The build script produces an ad hoc signed application bundle. Launch the `.app`, rather than `swift run`, so macOS associates microphone and speech permissions with Newtv1. You can move the bundle to Applications manually. For a consistent identity across rebuilds, set `NEWTV1_SIGN_IDENTITY` to your Apple signing identity. Distribution to other Macs requires Developer ID signing and notarization.

To build a faster development bundle:

```sh
bash scripts/build-app.sh debug
```

## First run

1. Open Newtv1. Hover over the notch, then choose **Set up Accessibility**, or open **Settings** from the menu-bar icon. Turn on Newtv1 in macOS System Settings. If necessary, add `dist/Newtv1.app` with the `+` button.
2. Click **Start listening**. Allow the Microphone and Speech Recognition prompts. Recognition defaults to on-device English (`en-US`); it will stop with an explanation if the recognizer cannot run on-device. You can explicitly enable Apple network recognition in Settings.
3. Switch to the app you want to control. Press **Option–Space** to toggle listening from any app.
4. Say **“New TV One, show numbers”**, pause, then **“New TV One, click twelve”**. Or say **“New TV One, open Safari then left half”**. Recognition accepts both the spaced spoken form and `Newtv1`.

The renamed app has a new bundle identity, `dev.newtv1.mac`, so macOS may ask you to grant its privacy permissions again. Previous saved workflows and preferences are copied from the original development app’s defaults on first launch. Quit the old development app before using Option–Space in Newtv1 so both versions do not compete for the same shortcut.

Listening must be manually enabled. The wake phrase is a prefix check over transcribed speech, not a dedicated low-power keyword detector. While listening, the audio engine is active even when no wake phrase is spoken. There is a short pause between utterances while the recognition session resets. Do not use Newtv1 where accidental voice activation would have serious consequences.

**Option–Space** toggles the microphone. **Command–period** inside Newtv1 stops execution. The menu bar also has **Stop All Actions**. While listening, **“Newtv1, stop”** cancels the current task and stops listening. Completed actions are not rolled back. An action already submitted to another app may still finish.

## Commands

| Control | Examples |
| --- | --- |
| Apps | `open Safari`, `switch to Notes`, `quit Safari` |
| Browser | `go to apple.com`, `search for coffee`, `new tab`, `next tab`, `go back` |
| Click | `show numbers`, `click twelve`, `click Save`, `hide numbers` |
| Input | `type Hello world`, `press command shift s`, `press return`, `copy`, `paste`, `undo` |
| Scroll | `scroll down`, `scroll up five`, `scroll right 3` |
| Windows | `left half`, `right half`, `top half`, `bottom half`, `maximize window`, `center window`, `minimize window` |
| Mac | `volume fifty`, `mute`, `unmute`, `take a screenshot`, `lock screen`, `sleep my mac` |
| Files | `reveal downloads`, `reveal ~/Documents` |
| Sequences | `open Safari then left half`, `wait 2 seconds`, `run focus mode` |
| Shell | `shell pwd` — always requires on-screen approval |

Literal commands (`type`, `write`, `dictate`, `search`, `shell`) consume the entire remainder, including the word “then”. For example, `open Notes then type tea then coffee` types “tea then coffee”. Use separate workflow lines for sequences involving literal commands.

Quit, lock, sleep, and shell steps open a review sheet **before any step in that plan executes**. While listening, “Newtv1, confirm” approves non-shell, non-AI plans and “Newtv1, cancel” dismisses them. Shell and AI plans require an on-screen click. Shell commands run through `/bin/zsh -c` as your current user, not root, with a 30-second process timeout and at most 16 KiB displayed output. Stop/timeout terminates the direct process; detached subprocesses may survive. Do not start persistent background jobs through this command runner.

## Workflows

Create and edit routines in **Workflows**. Put one command on each line. Say `Newtv1, run focus mode` to run the included example:

```text
open Safari
left half
open Notes
right half
volume 25
```

Workflows can call other workflows. Cycles, more than eight nested calls, and more than fifty expanded actions are rejected. All steps are parsed before execution; execution stops at the first failure. Workflows and settings are stored in Newtv1’s macOS UserDefaults domain, `dev.newtv1.mac`. Activity is kept in memory and is not written to an audit file.

## Optional local natural-language planner

The built-in parser works without a model. For freer phrasing, install and start [Ollama](https://ollama.com), download a local model that supports structured outputs, then enable **Natural language with Ollama** in Newtv1 Settings and enter the exact installed model name.

Newtv1 sends unrecognized requests to `http://127.0.0.1:11434/api/chat`, along with the target app name and saved workflow names. It does not send screenshots or file contents. It refuses HTTP redirects and model names containing `cloud`; the Ollama server configuration and the selected model still determine where inference runs. There is no model bundled in this project.

The model returns canonical commands using [Ollama structured outputs](https://github.com/ollama/ollama/blob/main/docs/capabilities/structured-outputs.mdx). Newtv1 validates and expands them through the same parser as direct commands. Every AI plan requires on-screen review, and generated shell steps are rejected even when nested inside a workflow. The planner is a translator, not a self-correcting agent: it cannot see or verify the screen, and model quality will affect results.

## Architecture

- `Newtv1Core`: independent parser, typed actions, risk classification, workflow expansion, model-plan validation.
- `SpeechController`: Apple Speech/AVAudioEngine, partial transcription, pause-to-submit, session reset, explicit microphone state.
- `Automation`: AXUIElement control discovery and window management, Quartz input events, numbered overlays, constrained app/URL launching, cancellable process execution.
- `AppModel`: last external app tracking, serialized execution, review queue, in-memory results, persistence, global Carbon hotkey.
- `LocalPlanner`: optional loopback-only Ollama client.
- `ContentView`: native command center, workflows, guide, settings, and review sheets.
- `NotchController`: persistent nonactivating notch panel, hardware cutout geometry, hover and pin behavior, display-change handling, and on-demand command-center window.

## Verification

```sh
swift run Newtv1CoreChecks
bash scripts/build-app.sh
codesign --verify --deep --strict dist/Newtv1.app
```

The dependency-free regression runner works with Command Line Tools alone; XCTest is not required. It exits nonzero on failure. Automated checks exercise parsing, literal text boundaries, numeric bounds, workflow expansion and cycles, maximum lengths, risk propagation, and generated-plan restrictions. They do not click your desktop, record your microphone, quit apps, lock the Mac, or execute arbitrary shell commands.

For end-to-end checks after granting permissions:

- Launch Newtv1: verify only the notch panel and menu-bar icon appear, with no Dock icon or dashboard. Hover to expand, click the sparkle to pin, and unpin then move away to collapse.
- Open the command center from the notch, close it, and verify the notch stays visible. Confirming risky commands must still open the command center for review.

- Open TextEdit with a blank document. Switch back to Newtv1 and type `type Hello from Newtv1`. Verify it returns to TextEdit and types there.
- In a normal app window, try `left half`, `right half`, and `center window`.
- In Safari, run `show numbers`, then `click` a visible numbered control. Change apps and verify the old overlay disappears.
- Create a two-step workflow, run it, restart Newtv1, and verify it persists.
- Try `shell pwd`: verify the exact command appears for review and does not execute until clicked.
- Start a workflow containing `wait 10`, then stop it; later steps must not run.
- Enable listening and verify `Newtv1, open Notes` works while speech without the “Newtv1” prefix does not execute in wake-phrase mode.
- If using Ollama, review a plan for a freeform request before approving it.

## Current boundaries

- English recognition only. Microphone and Accessibility permissions must be granted by you in macOS.
- Accessibility coverage depends on the app. Custom canvases, games, some browser content, protected fields, and full-screen windows may restrict control. Number scanning is bounded to 150 controls, 1,200 visited nodes, and approximately two seconds; slow apps can make it take longer.
- Window tiling is across the visible bounds of the current window’s display. Spaces management and arbitrary mouse dragging are not implemented.
- Screen Recording permission is requested only for screenshots. If macOS requires it, quit and reopen Newtv1 after enabling it. Desktop folder access may also need approval.
- The global hotkey may conflict with another installed application. The menu bar toggle is an alternative.
- An ad hoc signature may need fresh privacy grants after rebuilding. Use a stable signing identity for daily use.
- No driver, kernel extension, root helper, endpoint security monitor, always-on startup daemon, or guaranteed “anything” automation is included. Apple documents [system extensions](https://developer.apple.com/system-extensions/) and [deprecated kernel extensions](https://developer.apple.com/support/kernel-extensions) for the capabilities that require them.
