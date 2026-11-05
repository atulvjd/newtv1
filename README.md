# Vox

A native macOS voice control app built with SwiftUI, Speech, Accessibility, and Quartz. No JavaScript runtime, cloud account, or API key required for the built-in commands.

Vox is a working first implementation, not a kernel extension or a claim of superiority to commercial voice assistants. Its control comes from macOS permissions. It does not bypass System Integrity Protection, control secure password fields, or guarantee access to every app.

## Build and open

Requires an Apple silicon or Intel Mac running macOS 13+, and the Xcode command line tools with Swift 5.9+.

```sh
bash scripts/build-app.sh
open dist/Vox.app
```

The build script produces an ad hoc signed application bundle. Launch the `.app`, rather than `swift run`, so macOS associates microphone and speech permissions with Vox. You can move the bundle to Applications manually. For a consistent identity across rebuilds, set `VOX_SIGN_IDENTITY` to your Apple signing identity. Distribution to other Macs requires Developer ID signing and notarization.

To build a faster development bundle:

```sh
bash scripts/build-app.sh debug
```

## First run

1. Open Vox → Settings → Accessibility → Enable. Turn on Vox in macOS System Settings. If necessary, add `dist/Vox.app` with the `+` button.
2. Click **Start listening**. Allow the Microphone and Speech Recognition prompts. Recognition defaults to on-device English (`en-US`); it will stop with an explanation if the recognizer cannot run on-device. You can explicitly enable Apple network recognition in Settings.
3. Switch to the app you want to control. Press **Option–Space** to toggle listening from any app.
4. Say **“Vox, show numbers”**, pause, then **“Vox, click twelve”**. Or say **“Vox, open Safari then left half”**.

Listening must be manually enabled. The wake phrase is a prefix check over transcribed speech, not a dedicated low-power keyword detector. While listening, the audio engine is active even when no wake phrase is spoken. There is a short pause between utterances while the recognition session resets. Do not use Vox where accidental voice activation would have serious consequences.

**Option–Space** toggles the microphone. **Command–period** inside Vox stops execution. The menu bar also has **Stop All Actions**. While listening, **“Vox, stop”** cancels the current task and stops listening. Completed actions are not rolled back. An action already submitted to another app may still finish.

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

Quit, lock, sleep, and shell steps open a review sheet **before any step in that plan executes**. While listening, “Vox, confirm” approves non-shell, non-AI plans and “Vox, cancel” dismisses them. Shell and AI plans require an on-screen click. Shell commands run through `/bin/zsh -c` as your current user, not root, with a 30-second process timeout and at most 16 KiB displayed output. Stop/timeout terminates the direct process; detached subprocesses may survive. Do not start persistent background jobs through this command runner.

## Workflows

Create and edit routines in **Workflows**. Put one command on each line. Say `Vox, run focus mode` to run the included example:

```text
open Safari
left half
open Notes
right half
volume 25
```

Workflows can call other workflows. Cycles, more than eight nested calls, and more than fifty expanded actions are rejected. All steps are parsed before execution; execution stops at the first failure. Workflows and settings are stored in Vox’s macOS UserDefaults domain, `dev.vox.mac`. Activity is kept in memory and is not written to an audit file.

## Optional local natural-language planner

The built-in parser works without a model. For freer phrasing, install and start [Ollama](https://ollama.com), download a local model that supports structured outputs, then enable **Natural language with Ollama** in Vox Settings and enter the exact installed model name.

Vox sends unrecognized requests to `http://127.0.0.1:11434/api/chat`, along with the target app name and saved workflow names. It does not send screenshots or file contents. It refuses HTTP redirects and model names containing `cloud`; the Ollama server configuration and the selected model still determine where inference runs. There is no model bundled in this project.

The model returns canonical commands using [Ollama structured outputs](https://github.com/ollama/ollama/blob/main/docs/capabilities/structured-outputs.mdx). Vox validates and expands them through the same parser as direct commands. Every AI plan requires on-screen review, and generated shell steps are rejected even when nested inside a workflow. The planner is a translator, not a self-correcting agent: it cannot see or verify the screen, and model quality will affect results.

## Architecture

- `VoxCore`: independent parser, typed actions, risk classification, workflow expansion, model-plan validation.
- `SpeechController`: Apple Speech/AVAudioEngine, partial transcription, pause-to-submit, session reset, explicit microphone state.
- `Automation`: AXUIElement control discovery and window management, Quartz input events, numbered overlays, constrained app/URL launching, cancellable process execution.
- `AppModel`: last external app tracking, serialized execution, review queue, in-memory results, persistence, global Carbon hotkey.
- `LocalPlanner`: optional loopback-only Ollama client.
- `ContentView`: native command center, workflows, guide, settings, and review sheets.

## Verification

```sh
swift run VoxCoreChecks
bash scripts/build-app.sh
codesign --verify --deep --strict dist/Vox.app
```

The dependency-free regression runner works with Command Line Tools alone; XCTest is not required. It exits nonzero on failure. Automated checks exercise parsing, literal text boundaries, numeric bounds, workflow expansion and cycles, maximum lengths, risk propagation, and generated-plan restrictions. They do not click your desktop, record your microphone, quit apps, lock the Mac, or execute arbitrary shell commands.

For end-to-end checks after granting permissions:

- Open TextEdit with a blank document. Switch back to Vox and type `type Hello from Vox`. Verify it returns to TextEdit and types there.
- In a normal app window, try `left half`, `right half`, and `center window`.
- In Safari, run `show numbers`, then `click` a visible numbered control. Change apps and verify the old overlay disappears.
- Create a two-step workflow, run it, restart Vox, and verify it persists.
- Try `shell pwd`: verify the exact command appears for review and does not execute until clicked.
- Start a workflow containing `wait 10`, then stop it; later steps must not run.
- Enable listening and verify `Vox, open Notes` works while speech without the “Vox” prefix does not execute in wake-phrase mode.
- If using Ollama, review a plan for a freeform request before approving it.

## Current boundaries

- English recognition only. Microphone and Accessibility permissions must be granted by you in macOS.
- Accessibility coverage depends on the app. Custom canvases, games, some browser content, protected fields, and full-screen windows may restrict control. Number scanning is bounded to 150 controls, 1,200 visited nodes, and approximately two seconds; slow apps can make it take longer.
- Window tiling is across the visible bounds of the current window’s display. Spaces management and arbitrary mouse dragging are not implemented.
- Screen Recording permission is requested only for screenshots. If macOS requires it, quit and reopen Vox after enabling it. Desktop folder access may also need approval.
- The global hotkey may conflict with another installed application. The menu bar toggle is an alternative.
- An ad hoc signature may need fresh privacy grants after rebuilding. Use a stable signing identity for daily use.
- No driver, kernel extension, root helper, endpoint security monitor, always-on startup daemon, or guaranteed “anything” automation is included. Apple documents [system extensions](https://developer.apple.com/system-extensions/) and [deprecated kernel extensions](https://developer.apple.com/support/kernel-extensions) for the capabilities that require them.
