# Newtv1 feature status

This is an implementation checklist, not a claim of complete parity or superiority. Version 0.6.0 adds the following working code paths; external permissions and provider access remain prerequisites for live validation.

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
| Browser extension | MV3 activeTab text preview and native messaging receiver | Packaged source + user-run host installer; no DOM click/type driver or store distribution |
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
- A browser DOM action driver with stale-document checks and action/result verification.
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
