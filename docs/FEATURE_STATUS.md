# Current release: 0.10.0

The default notch is now a focused Dynamic Island: compact pill, one expanded activity at a time, up to two compact live activity indicators, automatic activity priority, countdown/media treatments, activity menu, press-and-hold/hover expansion, Escape/upward-drag/outside-click dismissal, and pinning. The expanded panel stays 440 points wide (subject to camera and screen clearance) and sizes to selected content. Classic horizontal and vertical layouts remain optional. Studio has a matching preview.

Validation: 51 groups / 682 assertions passed, including focused geometry, all-modules size independence, small-screen containment and live-activity priority. The compact pill, expanded voice card, activity menu, running timer, cancellation and Escape collapse were inspected in the native app. No live microphone recording was made for these checks. Existing permission/account/distribution limits still apply.

---

# Current release: 0.9.0

Added notch task cards, task names/search/archive/restore, task-specific voice follow-ups, routine proposals from task conversations, and revision-checked queued steering for active guided tasks. Added opt-in scheduled execution for an exact approved set of local app/window/audio/wait actions. Workflow changes revoke that execution match; Stop All pauses automatic schedules. Existing routines retain review-first behavior.

Release checks: 50 groups / 668 assertions passed, including task queue revision/size limits, legacy routine migration, exact expanded-action matching, and excluded automatic actions. Browser DOM regressions passed. Live UI checks on 15 November 2026 verified a completed Calculator launch, task rename/archive/restore, the task card in the wrapping notch, and routine approval controls. Voice accuracy and active guided-task steering still need permission-dependent end-to-end validation. Full unattended agents, multi-account service management, broad provider/site validation, hosted execution while closed, and production signing/updating remain incomplete.

The earlier release status and implementation history follow.

---

# Current release: 0.8.0

Added user-selected website file attachments up to 20 MB with chunked transport, document-bound expiring grants, MIME types and staging cleanup; opt-in browser task history with explicit reconnection/resumption; automatic observe/scroll continuation; and reviewed service-action forms for all five selected sources. Reload browser extension version 0.3.0.

Service forms implement Gmail draft/send, Drive text-file creation, Calendar events without attendees, Slack channel messages and Notion paragraph append. Google write scopes are optional and require reconnecting. Slack/Notion capabilities must be granted at the provider. Destination and content are frozen for review before submission. Network failures never trigger mutation replay.

Validation: 49 regression groups / 644 assertions passed, browser DOM fixtures passed, and the release was built and signature checked. Service writes have local request-format coverage, not live account validation. No account mutations were sent during development.

Still incomplete: fully unattended computer/browser agents, multi-account management, complete service CRUD/search/pagination, browser frames and cross-site continuity, signed/notarized automatic updates, hosted execution while closed, and broad website/account end-to-end validation. The Brave extension and exact-ID native host are installed. A local form task passed live through Gemini planning, reviewed typing, reviewed clicking and visible result verification. Stable signing and update hosting require external setup.

The implementation history below describes earlier versions and their boundaries at the time.

---

# Newtv1 feature status

This is an implementation checklist, not a claim of complete parity or superiority. Version 0.7.0 includes reviewed browser actions, task follow-ups, response preferences and natural-language schedule proposals; external permissions and provider access remain prerequisites for live validation.

| Feature | Implementation | Verification / boundary |
| --- | --- | --- |
| Horizontal notch and customization | Full-display bar, vertical alternative, profiles, themes, reordering, configurable wings | Camera-safe geometry and migration fixtures; notch and workspace checked in 0.6.0 |
| Spotify / Apple Music | Metadata, covers, transport, progress | Spotify metadata/artwork verified live; Automation permission required |
| Timed lyrics | Load local UTF-8 LRC, current line follows playback | Timestamp, offset, and malformed input fixtures; no lyrics scraping/provider |
| Calendar | EventKit connection, calendar selection, next 24 hours | User grants Calendar access; reads only, never sends calendar contents to AI |
| Downloads | Selected folder, partial-download names/sizes, recent files | Folder permission from picker; sizes are received bytes, not estimated percentages |
| File shelf | Persistent file bookmarks, drag in/out, reveal, remove references | Does not move/delete original files |
| System monitor | CPU history, memory approximation, disk capacity, battery | Public Mach/IOKit readings; no GPU/temperature/fan controls |
| Audio controls | Output device, supported system volume/mute | Public CoreAudio; device-dependent; no per-app mixer |
| Camera mirror | Explicit start, live preview, Stop/on-disappear shutdown | Camera permission required; no recording or AI upload |
| Clipboard | Opt-in session-only text/image/file history, clear, recopy | 20 items; known concealed types excluded, not a guarantee of secret detection |
| Snippets | Saved named text, date/time variables, copy/edit/remove | Manual copying; no global trigger expansion |
| Notifications | Local Newt inbox for timer, routine, task updates | Does not mirror other apps' notifications |
| Schedules | Saved once/daily/weekdays/weekly routines, edit, disable, due review, missed-run coalescing | DST and recurrence fixtures; app must run; every occurrence requires review |
| Browser extension | MV3 activeTab text preview and native messaging receiver | Packaged source + user-run host installer; one-tab DOM click/type/select/scroll/Back driver with action reviews; unpacked distribution |
| Browser context | Freshness validation, local preview, one-request AI approval | Rejects invalid schemes, credentials, oversized/stale contexts; no cookies or form values |
| Connected services | Google Desktop OAuth + PKCE for Gmail, Drive and Calendar; Keychain-backed Slack/Notion integration tokens; local list/content previews and one-request AI approval | Read-only viewers; provider setup and live validation required; Outlook/OneDrive excluded |
| Task recovery | Local before/after observations, launch/window checks, remaining-step review | Other app-specific results are explicitly unverified; failed actions can partially complete |
| Guided agents | Opt-in per-task AX-label sharing, one reviewed action per round, up to 8 observations, replan after failure | No screenshot upload in this loop; API quota + AX access required; not unattended autonomous driving |
| Task history | Optional local persistence with memory setting, interruption status on restart | Restored work never resumes automatically |
| Captions | Speech delegate updates a click-through caption panel | Uses installed Mac voices; caption preference in voice settings |
| Multilingual speech | Optional cloud transcription without fixed language, detected-language Mac voice | Off by default; audio sent before wake filtering; API quota required; no language-count or quality claim |
| Visual explanations | Bounded node/link data, 2D selection, orbitable 3D primitives, import/export, local example, AI generation | Schema/bounds fixtures; no generated scripts; no physical simulation guarantee |

## Still open

- A tested per-app audio mixer and per-app output routing.
- Mirroring other applications' notifications. No private notification-database scraping is included.
- Live installed-extension validation of the new browser driver; uploads, cross-site connection continuity, frames and unattended browser actions remain open.
- Service write actions, full service pagination/search, nested Notion content, Slack private channels/DMs, Drive binary document extraction, and public OAuth distribution/verification.
- Hosted background agents, execution while the app is closed, and fully unattended recovery.
- Signed/notarized distribution and automatic updates. A stable Apple Developer identity and update hosting are not configured.
- Live end-to-end API, multilingual recognition, camera, calendar, and permission-dependent control validation on the final signed build.

## Browser setup

1. Build the app with `bash scripts/build-app.sh`.
2. Open your Chromium browser's Extensions page, enable developer mode, and Load unpacked → this repo's `browser-extension` directory.
3. Copy the extension ID, then run `bash scripts/install-browser-host.sh EXTENSION_ID`. This writes per-user native messaging manifests for installed supported browsers, restricted to that exact ID.
4. Click the extension on an HTTP(S) page, preview the text, and save it locally.
5. In Newtv1 → Browser, load the preview, inspect it, and approve one question if you want AI help.

The native helper stores only the most recent preview at `~/Library/Application Support/Newtv1/BrowserInbox/page.json` with owner-only permissions. Clear preview removes it. Context expires after 15 minutes. The extension excludes form values, editable regions, hidden elements, subframes, URL query strings and fragments. Visible text can still contain private information; inspect both previews.

Move/reinstall the app only after updating the native host manifest. The extension is unpacked development software, not a published Chrome Web Store extension.

## API implementation references

Structured diagram generation follows the [official OpenAI structured output format](https://developers.openai.com/api/docs/guides/structured-outputs). Optional audio transcription uses the [official transcription endpoint](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create). Both have local bounds checks and cancellation; no live success is claimed from fixtures alone.

## Service setup

Connections supports the five selected sources: Gmail, Google Drive, Google Calendar, Slack and Notion. Outlook and OneDrive are excluded.

- **Google:** create a Desktop OAuth client in your Google Cloud project, configure the consent screen/test users, and enable Gmail, Drive and Calendar APIs. Download the client JSON and select **Connect Google**. The loopback flow uses PKCE and random state. Read-only grants cover all three sources. Client credentials and refresh tokens stay in Keychain. Gmail lists 15 inbox messages; Drive lists 30 recent files and previews Google Docs/plain text; Calendar lists 30 upcoming primary-calendar events.
- **Slack:** create a workspace app with `channels:read` and `channels:history`, install it, and invite it to the public channels it should read. Save the bot token in Connections. The viewer lists 50 public channels and reads 15 recent messages. Workspace policies and rate limits apply.
- **Notion:** create an internal integration with Read content capability, grant selected pages, and save its token. The viewer lists 30 accessible pages and reads up to 100 top-level blocks. Nested content and further pages are marked as omitted. It pins the supported `2025-09-03` API version; see [Notion versioning](https://developers.notion.com/reference/versioning), [search](https://developers.notion.com/reference/post-search), and [block children](https://developers.notion.com/reference/get-block-children).

Refresh and select an item to preview locally. Only the explicit one-request approval sends preview content to OpenAI. No service content is sent automatically. Disconnect removes the local credential; revoke provider grants separately. These code paths have not been validated against your accounts, and this development app does not bundle a provider-owned production OAuth client.

## Local validation

The packaged 0.6.0 release passed 41 regression groups / 422 assertions, extension JavaScript syntax, installer shell syntax, and four native-host malformed framing/input checks. Workspace UI was checked for Connections (Google and Slack setup), Utilities, routine editing and the rendered local 3D example. CPU/memory/disk/battery and current audio output populated on the machine. Account OAuth, cloud transcription/AI, Calendar and camera remain dependent on user setup and have not been claimed as live end-to-end successes.

## Gemini support (0.6.1)

The AI provider picker supports Gemini and OpenAI with separate Keychain credentials and model settings. Gemini uses native `generateContent`, JSON schemas for reviewed actions/guidance/diagrams, inline JPEG/WAV input, and Google Search grounding with linked sources. Provider switching stops active work/listening, revokes current sharing approvals, disables cloud transcription until re-enabled, and keeps follow-up context within the selected provider. Provider errors are sanitized; blocked, truncated and empty responses are rejected. The default Gemini model is `gemini-2.5-flash`.

Validation on 7 November 2026: Gemini key accepted by Google's model endpoint; native Newtv1 live action planning produced a locally validated plan requiring review, and Google Search returned clickable source citations. The 0.6.1 package passes 42 groups / 441 assertions and signature verification. Multimodal request translation has local fixtures; no live microphone recording or private screen upload was used for these checks.

## Version 0.7 additions

Browser has a native-port bridge restricted to one explicitly connected tab, bounded visible-text/control snapshots, reviewed actions, document/revision/expiry checks, one-time command claiming and receipts. Text replacement checks that the field retained its value; clicks are marked dispatched and followed by fresh observation, not claimed as semantic successes. AI planning pauses after 40 requests. Password/file fields are excluded; a cross-site navigation ends access. No extension store release or live account-driving success is claimed.

Tasks supports per-job follow-ups, provider-separated conversation context and continuation with another approved batch of fresh AX labels. Task conversations are included in opt-in local history. Routines supports reviewed create/update/pause/resume/delete proposals and multiple weekly weekdays. Saving changes never executes the routine immediately. Settings includes explicit persisted response preferences.

0.7.0 release validation: 47 groups / 587 assertions passed, browser DOM fixtures passed, four malformed native-host framing/input checks passed, and package signature verification passed. Browser and Routines screens were inspected in the running packaged app. The routine UI displayed a Tuesday/Thursday schedule beginning 17 November 2026 at 17:00 local time. Installed-extension action execution, provider account writes and unattended execution are not validated or claimed.

Installation validation: Brave 1.99.57 / extension 0.3.0, 14 November 2026. macOS native-host lookup uses Google/Chrome compatibility registration. The helper is installed under Newtv1/NativeHost in Application Support. Local demo result: Hello, Newt. Service account writes and real-site uploads remain untested.
