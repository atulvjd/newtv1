# HeyClicky review and Newtv1 implementation

**Historical baseline:** the comparison below describes version 0.5.0. For 0.6.0 additions and current limits, use [the current feature checklist](FEATURE_STATUS.md).

Reviewed 5 November 2026 from public product pages, FAQ, pricing, trust disclosures, privacy policy, and the published Mac/Windows release history. This review does not establish independent speed, accuracy, reliability, or security benchmarks.

## What the product is

HeyClicky presents a desktop voice companion that explains screens and delegates tasks. Its FAQ separates conversation from agents that perform work. [Product and FAQ](https://www.heyclicky.com/)

The useful interaction loop is invoke → speak → supply context → understand the answer → inspect or approve work → interrupt or follow up. Reproducing the notch alone would miss most of that product.

## Capability map

The competitor column summarizes advertised features in the [release history](https://www.heyclicky.com/changelog), including Mac v1.1.2 from 30 October 2026. The Newtv1 column describes this repository's 0.5.0 implementation; permission- and API-dependent paths need live validation on the user's machine.

| Area | HeyClicky advertises | Newtv1 0.5.0 |
| --- | --- | --- |
| Home | Notch and resizable window | Custom notch, Companion, Brain, Tasks, settings |
| Conversation | Voice and contextual follow-ups | Talk mode, bounded text context, optional local history |
| Invocation | Hold shortcut and speak | Optional hold/release Option–Space, plus continuous listening |
| Screen help | Sees requested screens | Manual capture, preview, single-request sharing approval |
| Drawing | 2D and interactive 3D | Numbered rectangular guidance; no 3D generation |
| Dictation | Multilingual insertion | Apple recognition into the last active app |
| Languages | Automatic multilingual recognition | Explicit supported-language picker; no automatic switching |
| Speech | Multiple spoken voices | Installed Mac voices, speed and preview |
| Captions | Spoken-answer captions | Full text answers; no timed subtitle overlay |
| Agents | Background work and follow-ups | Serialized reviewed plans and task cards |
| Driving | Mouse/keyboard and takeover | AX/Quartz actions; input interruption during agent control |
| Browser | Chromium extension | No extension; normal browser app shortcuts only |
| Integrations | Connected accounts and services | Not implemented |
| Routines | Scheduled editable jobs | Manual saved workflows; no scheduler |
| Memory | Cross-day context | Opt-in local text history; no image persistence |
| Updates | Signed automatic updates | Local build/sign script; updater remains open |
| Platforms | Mac and Windows | macOS only |

## Data and pricing disclosures

The [trust page](https://www.heyclicky.com/trust) says screen inspection starts on invocation, raw screenshots are not retained, and generated analysis/prompts are retained. It describes cloud processing and analytics/crash reporting. These are vendor statements, not audit findings.

The [privacy policy](https://www.heyclicky.com/privacy-policy) describes screenshot/voice transmission through a backend, AI providers, server retention, and browser-extension access to signed-in pages. Provider examples differ across that policy, the trust page, and newer release notes; treat those examples as nonexhaustive.

At review time the [pricing page](https://www.heyclicky.com/#pricing) advertises Free, Pro ($20/month), and Max ($100/month). Free lists 25 talk and 25 agent messages monthly; Pro lists unlimited talk/dictation and 150 agent messages; Max lists 1,000 agent messages. Newtv1 uses the owner's API project. Usage cost depends on model, context, and tools; no always-cheaper claim is made.

## Concrete improvements implemented in Newtv1

These are engineering choices, rather than measured claims of superiority:

- Direct commands, supported on-device dictation, and OCR can work without an OpenAI request.
- A screenshot is not uploaded merely because a shortcut was pressed. The preview exposes what will be sent. Approval applies to one request and is consumed before the upload.
- The screen-guide response contains advice and checked coordinates, not executable actions. Click-through overlays expire after 15 seconds. They never click the marked controls automatically.
- The guide prompt treats screen text as untrusted content. Action generation remains a separate path through the command parser, workflow limits, permission preflight, and review sheet.
- Generated shell commands are rejected. Agent plans stop on the first failure. Tasks show the plan, approval state, current step, result, error, or cancellation.
- During agent Mac control, Escape and physical mouse input are monitored for takeover. Events injected by Newtv1 are tagged and excluded from that test. Completed actions are not rolled back.
- Notch Studio gives the owner control over layout, color, sections, shortcuts, profiles, and hover behavior.
- Text history is opt-in, saved with owner-only file permissions, and clearable. Screenshots and keys are excluded. Disabling memory stops future loading/saving; Clear history removes previous saved text.

## Important boundaries

Agent mode is a bounded command-plan executor. It does not observe and replan after every step, control authenticated browser pages through a DOM bridge, provide scoped service connectors, schedule recurring jobs, or continue tasks as a hosted background service.

Recognition depends on Apple language models, devices, and permissions. This is not streaming audio-to-audio conversation. Long recognition sessions renew periodically; short hold-to-talk requests are the intended use. Spoken replies pause recognition to reduce self-transcription.

Screen capture requires macOS 14+. It excludes Newtv1 windows and targets one selected display. A preview can become stale; users are told to recapture after layout changes. Switching target apps hides existing guidance. Generated guide accuracy is not established by coordinate validation alone.

The earlier live OpenAI check returned `insufficient_quota`. Local signing can also require fresh Mac control, recording, or Keychain approval after a rebuild. This release cannot fix account billing or grant itself those permissions. Automated fixtures validate data and control logic; they do not establish live recognition or vision quality.

## Acceptance milestones before claiming superiority

1. Use stable signing, grant the final build's permissions, restore Keychain access, and confirm API quota.
2. Measure a repeatable app-task suite: completion rate, first-response latency, dictation correction rate, guidance accuracy, and user-takeover delay.
3. Add bounded observe/act/verify recovery before promising autonomous driving.
4. Build a browser bridge and scoped connector authorization before promising signed-in web tasks.
5. Add a persistent scheduler with visible runs, budgets, and per-routine approval rules.
6. Add richer diagrams and 3D explanations after the basic conversation/task loop is dependable.
