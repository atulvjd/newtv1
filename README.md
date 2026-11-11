# Newtv1

A native macOS voice control app built with SwiftUI, Speech, Accessibility, and Quartz. No JavaScript runtime, cloud account, or API key required for the built-in commands.

## Companion modes

Open **Companion** from the sidebar or notch window button. Its mode cards and the notch's mode menu share the same selection:

| Mode | Behavior |
| --- | --- |
| Command | Direct local commands and workflows |
| Talk | Questions, cited web answers, and contextual follow-ups |
| Guide | Capture, preview, approve sharing once, and ask about the screen |
| Dictate | Insert recognized speech into the last active app's focused field |
| Agent | Translate a task into a reviewed plan and show execution in Tasks |

**Settings → Companion & voice** has recognition language, vocabulary, push-to-talk, installed Mac voices, playback speed, and local-memory controls. Hold-to-talk uses Option–Space and sends on release without a wake phrase. The normal listening button captures one request and automatically stops after you finish. Settings includes a 0.6–3 second pause control, with 1.4 seconds as the default. Enable Keep listening for more requests for continuous wake-phrase operation. Continuous Dictate inserts text after each pause; say “Newt, stop dictation” (or your custom phrase) to end it. Switch to the destination field before starting.

Spoken replies are opt-in. Recognition pauses during playback and resumes only if it was already listening. Starting to talk interrupts playback. Languages and on-device availability depend on Apple; network recognition remains separately opt-in. This is not a streaming audio-to-audio service.

### Screen context and guidance

Manual capture requires macOS 14+ and Screen Recording permission. Choose a display and **Capture preview**. Newtv1 excludes its own windows. The image stays in memory until you choose **Use this screen** and **Ask about screen**. That approval is consumed by one request. The image is dropped after completion or failure. **Read text locally** uses Apple Vision without an API request.

Guide answers can include up to eight validated rectangles. **Show highlights** draws numbered, click-through marks for 15 seconds. They do not click or type. Capture again when the layout changes. **Hide highlights**, `Newt, hide guide`, switching target apps, and Stop remove the marks.

### Tasks and conversation history

Agent tasks show a goal, approval state, proposed steps, progress, and result. Plans execute one at a time and stop on the first error. During agent-driven Mac control, Escape or physical mouse input cancels execution; completed actions are not rolled back. This is bounded plan execution, not a self-correcting browser agent.

Up to 30 question/answer pairs stay in memory, and recent text supplies follow-up context. **Remember conversations on this Mac** optionally writes text history to `~/Library/Application Support/Newtv1/conversations.json` with owner-only file permissions. Screenshots and keys are excluded. Disabling memory stops loading/saving; **Clear conversation history** removes previously saved text after confirmation.

Read the [HeyClicky review](docs/HEYCLICKY_REVIEW.md) for the public-site research, feature map, privacy comparison, gaps, and acceptance milestones. Complete parity and measured superiority are not claimed.

Newtv1 lives at the MacBook notch. It starts as an accessory app with no Dock icon or dashboard window. Hover over the notch to expand it; move away to collapse it. Click the sparkle or pin button to keep the controls expanded. The compact wings show microphone and execution status without placing controls behind the camera. The notch expands horizontally across the display by default, with modules side by side and listening controls at the right. Horizontal sections scroll when needed. The expanded panel includes live transcription, listening, Stop, and a command-center button. Closing the command center leaves the notch running.

## Notch Studio

Open **Notch Studio** in the command-center sidebar, use the sliders button in the expanded notch, or choose **Customize Notch** in the menu-bar menu. Changes are saved locally and applied to the real panel immediately. The live preview shows the same module content and chosen finish.

- **Five presets:** Default, Minimal, Studio, Focus, and Island.
- **Appearance:** choose black, a tinted gradient, or glass; pick any accent color; adjust opacity, border strength, corner radius, microphone waveform, and module spacing.
- **Layout:** attach to the hardware notch or use a floating island; select a display; choose a full-width horizontal bar or vertical panel, adjust bar height or custom width, resting wing width, floating gap and horizontal offset. Camera clearance and screen boundaries are enforced. A disconnected display falls back to an available display.
- **Wing actions:** independently assign microphone, expand/pin, Brain, command center, numbered controls, screenshot, or clock.
- **Sections:** show, hide, and reorder Voice, Shortcuts, Workflows, Activity, Clock, Timer, and Notes. Move sections with the up/down buttons. Listening, Stop, customization, and command-center controls stay available even with all sections hidden.
- **Quick buttons:** create, edit, reorder, and remove up to eight named buttons using SF Symbols and supported commands. Workflow buttons resolve against your saved workflows. Risky commands keep their normal approval sheet; importing a profile never executes its commands.
- **Behavior:** set hover activation and closing delays, expansion for listening/execution/errors, pinning on the next launch, and animation. macOS Reduce Motion is respected.
- **Motion:** the status point breathes gently at rest, sends out audio-responsive ripples while listening, and shows orbiting trails while working. The command-center orb uses the same visual language. The notch expands over 420 ms and closes over 260 ms, with its native window and contents resizing together; interrupted transitions continue from their current frame. Turn motion off in Behavior, or use macOS Reduce Motion for a static indicator and immediate resizing. Appearance includes a status-motion preview that needs no microphone or API access.
- **Profiles:** export or import versioned JSON through the Profiles menu. Profiles include notch appearance, layout, behavior, sections, and custom button commands. They exclude API keys, scratchpad notes, saved workflows, and question history. Review imported button commands in Modules before using them. Profiles are limited to 128 KB and imported values are normalized to valid bounds.

The Timer section offers 5-, 15-, and 25-minute timers with cancellation and a completion indicator. Timers are session-only, use wall-clock time, and do not keep the Mac awake; completion is noticed after wake if the Mac sleeps. The Clock follows your Mac's local time. Scratchpad text is edited in **Notch Studio → Modules** and autosaved locally; the notch displays it without taking keyboard focus from your active app.

The modular customization approach takes inspiration from [Vorssaint's Dynamic Island](https://github.com/vorssaint/vorssaint-utils). Newtv1's configuration model, profile format, panel implementation, and editor are original to this project; the external toolkit is not installed or bundled.

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
4. Say **“Newt, show numbers”**, pause, then **“Newt, click twelve”**. Or say **“Newt, open Safari then left half”**. Default wake phrases are “Newt”, “New”, “Hey Newt”, and “Hey New”. `Newtv1` is the app name, not a wake phrase. Set an optional custom phrase in Settings; it replaces the defaults and also accepts “Hey” before it. Clearing the field restores Newt/New. Changing the phrase stops recognition so it can restart with updated vocabulary.

The renamed app has a new bundle identity, `dev.newtv1.mac`, so macOS may ask you to grant its privacy permissions again. Previous saved workflows and preferences are copied from the original development app’s defaults on first launch. Quit the old development app before using Option–Space in Newtv1 so both versions do not compete for the same shortcut.

### Mac control permission already on, but commands still fail

On macOS 27, the permission pane is **Privacy & Security → Device Control and Data Access**; older macOS versions call it **Accessibility**. The app's Settings page shows the detected pane name, running version, and exact application path. The version is also visible in the sidebar.

If the app still reports no access while its switch is on, quit Newtv1, remove the old Newtv1 entry from that pane, add the exact `.app` displayed in Newtv1 Settings, turn it on, and reopen it. Grant the permission to Newtv1 rather than the old development app. macOS may ask you to authenticate this change. The app cannot grant itself access.

This project uses an ad hoc development signature when `NEWTV1_SIGN_IDENTITY` is unset. Rebuilding changes the app's signed identity and may invalidate a previous privacy grant. A stable Apple signing identity is the intended path for daily-use builds. The build script reports when it used development signing.

Newtv1 checks whether an entire expanded command plan needs Mac control access **before executing its first step**. A blocked workflow opens setup instead of launching apps and then failing on its first window action. A pending request can be retried manually after access is detected; granting access does not execute it automatically. Stopping or quitting the app discards the waiting request.

Listening starts manually. Single-request capture accepts speech directly, waits for quiet audio and a stable transcript, finalizes recognition, then stops the microphone and submits once. Continuous listening applies the configured wake phrase. Local recognition preserves text across recognition segments. Cloud recording retains bounded segments and transcribes them together after you finish. Initial silence stops capture after 12 seconds. Requests have a three-minute recording limit, which shows an error before executing an incomplete request. Microphone power guides pause detection and can be affected by background voices or noise.

**Option–Space** toggles the microphone. **Command–period** inside Newtv1 stops execution. The menu bar also has **Stop All Actions**. While listening, **“Newt, stop”** cancels the current task and stops listening. Completed actions are not rolled back. An action already submitted to another app may still finish.

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

Quit, lock, sleep, and shell steps open a review sheet **before any step in that plan executes**. While listening, “Newt, confirm” approves non-shell, non-AI plans and “Newt, cancel” dismisses them. Shell and AI plans require an on-screen click. Shell commands run through `/bin/zsh -c` as your current user, not root, with a 30-second process timeout and at most 16 KiB displayed output. Stop/timeout terminates the direct process; detached subprocesses may survive. Do not start persistent background jobs through this command runner.

## Workflows

Create and edit routines in **Workflows**. Put one command on each line. Say `Newt, run focus mode` to run the included example:

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

## OpenAI brain and web search

Open **Settings → OpenAI brain** to save or replace an API key in macOS Keychain. Keys are never stored in source files, preferences, environment files, or activity history. Use the remove button to disconnect. Enable the brain to use OpenAI for questions and natural-language action planning; the OpenAI option takes precedence over Ollama when both are enabled. The default model is `gpt-5.4-mini`, and you can choose another compatible Responses API model in Settings.

- `ask Why is the sky blue?` — answer a question.
- `research the latest Mac news` or `look up the weather in Mumbai` — search the web and show a cited answer.
- `search for interesting science discoveries` — use the brain when enabled; the original browser-search behavior remains when disabled.
- Describe a Mac task in your own words — review the translated steps before approving them.
- Say `Newt, ask …` to use the brain by voice. Read answers in the **Brain** tab, also accessible from the notch's sparkle button in its footer.

The client uses the official [Responses API structured output format](https://developers.openai.com/api/docs/guides/structured-outputs) for action translation and [web search](https://developers.openai.com/api/docs/guides/tools-web-search) for lookups. Search citations appear as clickable inline links. Search is limited to two tool calls per answer; requests have finite output and time limits. Responses are requested with `store: false`. API usage and searches consume API credits; model access and quota depend on your OpenAI project.

Text questions, recent conversation context, and searches are sent to OpenAI. Action planning also sends the last target app name and workflow names. Guide mode separately sends a screenshot explicitly approved for that one request. These clients do not upload raw audio or local file contents. Search and guide answers cannot run actions. Every generated action plan requires review and rejects shell commands, including inside workflows. Text history is session-only unless the owner enables local memory.

For terminal setup, the build also produces `Newtv1Setup`. Run it with the absolute path to `dist/Newtv1.app`; it reads the key from hidden terminal input and saves it to Keychain with access for the signed app. Quit and reopen Newtv1 after terminal setup. macOS may request Keychain access again after rebuilding an ad hoc signed app. Rotate any key that has been exposed in chat or shared logs.

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
- In Notch Studio, try each preset, change the accent and placement, hide/reorder sections, and assign both wing buttons. Changes should update the real notch without a restart.
- Export a profile, change the layout, then import the profile and verify its settings return. Verify no imported command runs automatically. Reject an unsupported profile version or an oversized profile without changing settings.
- Add a quick button for `run focus mode`, edit it, and move it in the order. Try a shell button and confirm it still requires review before execution.
- Start and cancel a timer. Edit the scratchpad, quit and reopen Newtv1, and check that notes and notch settings persist while the timer does not.
- Open the command center from the notch, close it, and verify the notch stays visible. Confirming risky commands must still open the command center for review.

- Open TextEdit with a blank document. Switch back to Newtv1 and type `type Hello from Newtv1`. Verify it returns to TextEdit and types there.
- In a normal app window, try `left half`, `right half`, and `center window`.
- In Safari, run `show numbers`, then `click` a visible numbered control. Change apps and verify the old overlay disappears.
- Create a two-step workflow, run it, restart Newtv1, and verify it persists.
- Try `shell pwd`: verify the exact command appears for review and does not execute until clicked.
- Start a workflow containing `wait 10`, then stop it; later steps must not run.
- Enable listening and verify `Newt, open Notes` works while speech without the “Newt” prefix does not execute in wake-phrase mode.
- If using Ollama, review a plan for a freeform request before approving it.

## Current boundaries

- English recognition only. Microphone and Accessibility permissions must be granted by you in macOS.
- Accessibility coverage depends on the app. Custom canvases, games, some browser content, protected fields, and full-screen windows may restrict control. Number scanning is bounded to 150 controls, 1,200 visited nodes, and approximately two seconds; slow apps can make it take longer.
- Window tiling is across the visible bounds of the current window’s display. Spaces management and arbitrary mouse dragging are not implemented.
- Screen Recording permission is requested only for screenshots. If macOS requires it, quit and reopen Newtv1 after enabling it. Desktop folder access may also need approval.
- The global hotkey may conflict with another installed application. The menu bar toggle is an alternative.
- An ad hoc signature may need fresh privacy grants after rebuilding. Use a stable signing identity for daily use.
- No driver, kernel extension, root helper, endpoint security monitor, always-on startup daemon, or guaranteed “anything” automation is included. Apple documents [system extensions](https://developer.apple.com/system-extensions/) and [deprecated kernel extensions](https://developer.apple.com/support/kernel-extensions) for the capabilities that require them.

### Media in the notch

The **Now Playing** module shows Spotify and Apple Music track details, available album artwork, playback progress, and previous/play/pause/next controls. Click **Connect Spotify / Music** once, with your player running, and allow macOS Automation access. Reading media stays local; Spotify artwork loads from its cover URL. A playing source takes priority over a paused one. Polling runs every two seconds and never opens a closed player. Disconnect from the module menu to stop monitoring. Hide or reorder Now Playing in Notch Studio → Modules. Browser tabs, YouTube, and other players are not currently integrated.

## Version 0.6 utilities and companion expansion

Open **Utilities** for Calendar, selected-folder Downloads, the file shelf, system readings, audio outputs, camera mirror, clipboard history, text snippets, and Newt's inbox. Enable their notch sections in **Notch Studio → Modules**. New sections start hidden so existing layouts are preserved. Clipboard monitoring is session-only and opt-in. Camera, Calendar, and folder access start only through their connection controls.

**Routines** saves once, daily, weekday, or weekly command sequences. Every due occurrence waits for review. Missed occurrences coalesce into one review; Newtv1 does not wake the Mac or execute while closed. **Tasks** shows local execution observations and offers reviewed remaining-step recovery. App launches and window geometry have postcondition checks; arbitrary click/typing outcomes are not automatically verified. Optional memory also retains task history. Interrupted tasks never restart themselves.

In **Companion → Agent**, preview target controls and optionally allow up to eight AX-label observations for one typed task. Newt proposes one reviewed action per round, observes again, and can replan. This sends the app/window title and control labels to OpenAI; field values and screenshots are excluded. Stop or declining a step ends that task's observation permission. Inspect an agent's final explanation before marking it complete.

**Diagrams** provides a local example, 2D node inspection, orbitable 3D scenes, and JSON import/export. AI generation requires the configured OpenAI key. Only bounded scene primitives and links are accepted; no generated code runs.

**Settings → Companion & voice** includes live spoken captions and optional automatic-language transcription through OpenAI. Automatic recognition is off by default and uses `gpt-4o-mini-transcribe`; audio segments are uploaded before wake-phrase filtering, with normal API costs. Hold-to-talk is preferable for deliberate short requests. Local Apple recognition remains the default. Speech segments pause recording while uploading; this is not a continuous realtime audio conversation.

The media module's menu can load timed `.lrc` lyrics for the current song. Audio output controls use system/device volume; per-app mixing is not implemented.

See [the current feature checklist and browser installation steps](docs/FEATURE_STATUS.md) for implemented features, validation boundaries, and remaining work. The earlier HeyClicky review describes the 0.5.0 baseline; this checklist describes 0.6.0.

### Connected services

Connections now includes read-only Gmail, Google Drive, Google Calendar, Slack and Notion viewers, with Keychain credentials, local content previews and explicit one-request AI sharing. Google requires your Desktop OAuth client; Slack and Notion require integration tokens and granted content access. Outlook and OneDrive are excluded as requested. See [setup and current limits](docs/FEATURE_STATUS.md#service-setup).

### Gemini provider (0.6.1)

Settings → AI brain now selects OpenAI or Gemini, with separate Keychain credentials and model settings. Gemini defaults to `gemini-2.5-flash` and uses Google's native API for answers, Google Search grounding, reviewed command planning, screen guidance, diagrams and optional audio transcription. Existing action, image and diagram validation still applies. Provider changes stop active listening/work and clear content-sharing approvals; conversational context is limited to the selected provider. Existing history without a provider is treated as OpenAI history.

Save a Gemini key in Settings, or use the built setup helper with `Newtv1Setup /absolute/path/to/Newtv1.app --gemini --verify` and enter the key through hidden stdin. Keys never belong in source code or the browser extension. Automatic audio transcription sends recordings to the selected provider only when explicitly enabled. Local Apple speech recognition remains the default.

Implementation references: [Gemini generateContent](https://ai.google.dev/api/generate-content), [structured output](https://ai.google.dev/gemini-api/docs/structured-output), and [Google Search grounding](https://ai.google.dev/gemini-api/docs/google-search).
