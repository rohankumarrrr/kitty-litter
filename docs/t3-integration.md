# Talking to T3 Code

The Kitty Litter runs every agent through [T3 Code](https://t3.codes), a local app with a server inside. There's no public API for this. Everything below was read from the app's own bundle and checked against the running server, version 0.1.6, orchestration protocol 2.

All wire formats live in `Sources/ShadesT3/T3Wire.swift`, so a T3 update should only ever mean changing that one file. When T3 updates, run the probes in `Sources/Probes/T3`.

## How it connects

One WebSocket does nearly everything, because approvals and live streaming need it anyway. Uploads and two startup checks use plain HTTP.

1. **Find the server.** Read `<home>/userdata/server-runtime.json` for `origin`. `<home>` is `$T3CODE_HOME` or `~/.t3`. The port is never assumed, and the file is read again on every reconnect, because T3 can come back on another port.
2. **Check the version.** `GET /.well-known/t3/environment` needs no sign-in and gives `orchestrationProtocolVersion`, `serverVersion` and `environmentId`. Anything but protocol 2 stops here with a clear message.
3. **Sign in.** See below.
4. **Open the socket.** `GET /ws?orchestrationProtocol=2` with `Authorization: Bearer <token>`. Without the query item the server answers 426.

If T3 goes away, the client keeps trying, and backs off to one try every 5 seconds. A call made while T3 is down tries straight away and fails fast with "I can't reach T3 Code. Open it and try again." Messages says the same while it can't read. When T3 returns, subscriptions are sent again: the thread list takes a fresh snapshot, and a running turn resumes after the last event it saw.

## Sign-in

```
t3 auth session issue --scope orchestration:read --scope orchestration:operate --scope filesystem:read --ttl 30d --label Shades --json
```

This is T3's documented way to sign in a headless client. It needs no clicks, because anyone who can run it as this user already has this access. It usually takes about 0.8 s, though right after an install it has taken around 40 seconds, and it happens on the first run of each build and when renewing. `filesystem:read` is only for a picture a reply points at in its thread's folder, which `assets.createUrl` won't hand out without it. A saved session without it isn't usable, so the first launch that wants it signs in again and revokes the old one.

- The token goes in the login Keychain under service `dev.shades.t3-session`, with the session ID as the account. It's never logged or written anywhere else.
- Only the installed app, at `/Applications/Shades.app` where `scripts/install.sh` puts it, uses that service. Any other copy, built from source as `swift run shades` makes, bundled elsewhere by `scripts/bundle.sh`, or trying a flow out with `--ask`, `--hand-off` or `--fix`, keeps its sign-in under `dev.shades.t3-session.trial` and shows up as "Shades trial", so it can never save a sign-in where the app looks, or revoke the app's as one an older build left. Several such copies can run at once without being able to read each other's sign-ins, so one never revokes a sign-in there it can't read, since another copy may still be using it. Those stay in T3's list until they run out. Such a copy keeps to itself the way one trying a flow out does: phone keys in memory, so it can't replace the app's, no phone page on your tailnet, no notifications, an inbox that's never read from or written to `inbox.json`, and no `health.json`, which is what `scripts/install.sh` waits for from the installed app. `probe-t3` and `--channels-check` sign in only for as long as they run, and sign out.
- A saved token is checked with `GET /api/auth/session` on each connect. Its `scopes` lists only T3's older scopes, so the check reads `permissions`, which lists them all, `filesystem:read` included. `probe-t3 keychain` shows a second launch reusing the first one's session.
- With 7 days left, the client signs in again and revokes the old session. If the server answers 401 on reconnect, or to the saved token at launch, as it does once a session's been revoked, it does the same.
- The session shows up as "Shades" in T3's list of connections.

### Why not MCP?

MCP's OAuth flow needs a person to approve it on the `/connect-agent` page, its sessions are only good for `/mcp`, and MCP deliberately can't answer permission requests. The Kitty Litter has to answer them, so it needs this surface anyway. A session with a subject of `mcp-client` is refused everywhere except `/mcp`, and pretending to be one would dodge that approval step, so The Kitty Litter doesn't.

### The Keychain and rebuilds

Keychain items belong to the signed code that made them. The stores add them with macOS's default access, which lets only the app itself read them without asking, matched by its identifier and certificate, and macOS also gives each item a partition list. For an app signed with a Team ID, as `scripts/bundle.sh` signs it with an Apple Development certificate when there is one, that list names the team, so the next build signed by the team reads the session without a dialog, and other apps of the team would still be asked. For an app signed without one, as the self-signed certificate from `scripts/make-dev-cert.sh` signs it, the list names only the exact binary that made it, by its hash. So each new build can't read the last one's item, even signed with the same certificate, and signs in again. Nothing in the stores changes with the signature: the same `SecItemAdd` gets whichever partition the build's signature calls for.

Moving onto a team signs in once more, since the first build signed by the team can't read what a build without one saved. After that, installs keep the session. So once a team-signed copy is installed, `scripts/install.sh` refuses a build that isn't signed by the same team unless you pass `--change-team`, and the self-check's `signature` finding says when a build has no team.

Without a team, macOS would normally ask about that with a dialog on every rebuild, so the store turns prompts off. An unreadable item means signing in again, with no dialog, and the installed app revokes the last build's session. A new sign-in only ever deletes an item its own run saved. Another build's item, readable or not, stays behind, harmless, until something signed like that build removes it, or you delete it in Keychain Access.

A few things learned the hard way:

- **Never change or delete another build's item.** Changing an attribute on one shows a dialog even with `SecKeychainSetUserInteractionAllowed(false)`, and so does deleting one this build can read, and the call waits until the dialog's answered. That held a whole launch once: a new scope made the saved sign-in unusable, so the first launch of the new build signed in again and deleted the one the last build had saved. Reading and listing attributes don't. `T3AuthTests` covers a launch over items earlier builds left. The phone's keys follow the same rule, on the main thread, where a dialog would hold the whole app: each change is an item of its own, the newest one that can be read counts, saving what's already there touches nothing, a phone coming back with the subscription it already has saves nothing, whatever order its JSON came in, and only items this run saved are deleted. `PhoneKeychainTests` covers that.
- **Nothing waits on signing in for good.** The self-check gives T3 10 seconds to answer, then writes `health.json` anyway, since `scripts/install.sh` rolls back a copy that never reports. If T3 hasn't answered, it says it's still connecting, and writes the report again by itself once T3 does. Only if T3 still hasn't answered two minutes later does it say to answer a Keychain dialog if one's showing, since a Keychain call waiting on its dialog is the one part of signing in with no limit.
- **Take turns with the prompt switch.** `SecKeychainSetUserInteractionAllowed` is process-wide, and at launch the phone's keys load on the main thread while signing in reads T3's off it, so one store turning prompts back on when it finished turned them on in the middle of the other's read. Both go through `KeychainPrompts.off`, which one caller holds at a time. `T3CredentialsTests` covers that.
- **Keychain failures aren't fatal.** Sign-in then only lasts until the app quits, and each launch leaves a session behind until it expires. This was seen once, with error -25293, just after a process was killed in the middle of a dialog. It cleared up by itself within minutes.
- The data protection Keychain isn't an option: it needs an entitlement an open-source build can't have (error -34018).

## The RPC

It's [Effect RPC](https://effect.website) with its JSON serialization. Each WebSocket message is one JSON frame, or in principle a list of them.

| Direction | Frame |
| --- | --- |
| Out | `{"_tag":"Request","id":"1","tag":"<method>","payload":{…},"headers":[]}` |
| Out | `{"_tag":"Ack","requestId":"1"}` after every chunk, or the stream stalls |
| Out | `{"_tag":"Interrupt","requestId":"1"}` to end a stream |
| Out / in | `{"_tag":"Ping"}` / `{"_tag":"Pong"}` |
| In | `{"_tag":"Chunk","requestId":"1","values":[…]}` |
| In | `{"_tag":"Exit","requestId":"1","exit":{"_tag":"Success","value":…}}` |
| In | `{"_tag":"Exit","requestId":"1","exit":{"_tag":"Failure","cause":[…]}}` |

A `cause` entry is `Fail` with an `error` (`detail` and `message` are for people), `Die` with a `defect`, or `Interrupt`. A `Die` starting `Unknown request tag` or `Expected ` means the server didn't recognize the method or payload, which the client reports as a version mismatch.

### Calls used

| Method | Used for |
| --- | --- |
| `orchestration.launchThread` | New thread. Answers `threadId`, `projection` and `sequence`. |
| `orchestration.dispatchCommand` | Follow-ups, approvals, answers to questions, settling, archiving, mode changes. Answers `sequence`. |
| `orchestration.subscribeThread` | One thread's events. Also one whole thread, for The Kitty Litter. |
| `orchestration.subscribeShell` | Every thread, for the dashboard. Also one full snapshot, for The Kitty Litter. |
| `orchestration.getTurnItem` | The words of an approval or a question. |
| `orchestration.getThreadProjection` | A thread's final report, a fallback for those words, and a settled thread's runtime mode. |
| `orchestration.searchThreads` | Which threads have the words you searched The Kitty Litter for. |
| `projects.ensureScratch` | The "No project" project. The client remembers it. |
| `projects.mutate` | Registers the router's own folder as a project, the first time. |
| `attachments.createUploadUrl` | A signed URL for one upload. |
| `assets.createUrl` | A signed URL for something T3 keeps: `{"_tag":"attachment","attachmentId":…,"disposition":"inline"}` for a picture sent with a message, or `{"_tag":"workspace-file","threadId":…,"path":…}` for a file in a thread's folder. |

### Starting and following up

A new thread needs a project, so a thread with no project uses the one from `projects.ensureScratch`, with `workspaceStrategy {"type":"root"}`. T3 gives each one its own scratch folder.

```json
{
  "commandId": "<uuid>", "threadId": "<uuid>", "projectId": "<id>",
  "title": "…", "generateTitle": false,
  "modelSelection": {"instanceId": "codex", "model": "gpt-6.1-sol", "options": [{"id": "reasoningEffort", "value": "low"}]},
  "runtimeMode": "auto", "interactionMode": "default",
  "workspaceStrategy": {"type": "root"},
  "initialMessage": {"messageId": "<uuid>", "text": "…", "attachments": []}
}
```

The router doesn't start in scratch. A scratch folder is made new for each thread, so there's nowhere to put settings for it in advance, and the router needs some (see [kittens.md](kittens.md#whats-enforced)). Its folder is registered once with `projects.mutate` and `{"type": "project.create", "commandId", "projectId", "title", "workspaceRoot"}`, which answers with the project. T3 turns away a second project at the same folder.

The effort option is `reasoningEffort` for Codex and `effort` for Claude and the rest. `generateTitle: true` has T3 write a title in the background.

A follow-up is a `message.dispatch` command with `dispatchMode {"type":"start_immediately"}` and no `deliveryIntent`. Leaving out `modelSelection` keeps the thread's own model, which is how the router forwards a message into a session. That always gives the message its own run: it starts now on an idle thread and queues behind an active one, which is the same as T3's `queue_after_active`. The cat's own turns and the words the router passes on are sent this way.

What you send into a thread yourself, from The Kitty Litter or your phone, adds `deliveryIntent: "steer"` unless Settings says Queue, which is what T3's own composer sends for a steer. T3 turns it into `steer_active` on the thread's latest live run, so the message joins that run and what the agent says next answers it. On an idle thread, or one whose turn has already ended, it starts a run of its own as before. T3 refuses a steer into a run that's still `preparing` or `starting`, or already stopping, with "Target run … is starting and cannot be steered", so then The Kitty Litter sends it again without the intent, and it waits its turn. A steered message's run was started by another message, so the turn tracker finds it from the message's own `user_message` item, whose `runId` is the run it joined, and follows that run to its end. On Claude a steer cut a count short and was answered within the run. On Codex it joined the run and was answered once the message being written was done. `probe-t3 steer` tries both, and a steer sent before the run is going.

Only send `thread.runtime-mode.set` when the mode really changes. For providers that can't switch mode inside a session, it ends the session, and the next turn pays to start a new one.

#### Who a message is from

`message.dispatch` sends `createdBy: "user"`. A launch sends none, and T3 records the user, which we measured on real threads The Kitty Litter started. Agents using T3's tools show `createdBy: "agent"`.

Kittens rely on this to believe a correction, as [kittens.md](kittens.md#corrections) describes. It has a limit: it stops an agent using T3's tools from speaking as the user, but not a process holding the user's T3 credentials.

### Following a turn

Subscribe with `{"threadId":…, "afterSequence":…, "acceptBoundedSnapshot":true}`. Sequences are global across threads, so gaps are normal. Without `afterSequence` you get a snapshot first, then live events.

- **Text** arrives as `turn-item.updated` with `type: "assistant_message"`. `text` is the whole message so far, not a delta, which makes replays harmless. Short replies often arrive whole, with `streaming: false`. Items with a `parentItemId` belong to subagents.
- **The turn's run** is found by `userMessageId` in `run.created` / `run.updated`. It's over at `completed`, `failed`, `interrupted`, `cancelled` or `rolled_back`. `waiting` isn't an ending: it comes just before `completed` while the checkpoint is saved.
- **Errors** arrive as a turn item with `type: "error"` and `failure.message`.

A new thread can subscribe with `afterSequence` set to what the launch answered. A follow-up subscribes without it, at the same moment it sends the message, because the event that names its run can land inside the commit the answer's `sequence` points to.

### The thread list

The shell stream sends a `snapshot`, then `thread.updated`, `thread.removed`, `project.updated` and `project.removed`.

- A snapshot with `resolvedRepositoryIdentityRoots` only refreshes projects and has an empty `threads`. Treat it as a full snapshot and the dashboard goes blank, as it would about 100 ms after every connect.
- `omitOlderSettled` and `omitIdleSubagents` took a real list from 179 threads to 35. Servers that don't know these flags ignore them.
- `omitOlderSettled` never drops an unsettled thread. Settled ones were dropped from about 33 hours old upward, with some up to 67 hours old kept. So a run that settled and got that old while the app was off can be missed by [the inbox](kittens.md#the-inbox).
- `latestRunId` and `latestRunCompletedAt` say which run a thread last finished and when. The inbox compares that ID with the last one it filed on every list, so a finish while the app was off looks the same as one while it was on. `status` stays `completed` after a thread settles, and `idle` means it has no finished run. The self-check says so if completed threads stop naming a run.
- `lineage.relationshipToParent == "subagent"` and `lineage.sideChat` threads don't get listed. A subagent's approval shows on its nearest listed parent, but answering it must name the subagent's own thread.

| Shell `status` | `AgentStatus` |
| --- | --- |
| `preparing`, `queued`, `starting` | `starting` |
| `running`, `waiting` | `running` |
| `completed`, `failed` | same |
| `interrupted`, `cancelled`, `rolled_back` | `interrupted` |
| `idle`, anything new | `idle` |

A blocking `pendingRuntimeRequest` overrides this: `user_input` is `waitingForAnswer`, and the approval kinds are `waitingForApproval`.

A thread's turn can end while work it started carries on, and it wakes up again when that work hands back. So a `completed` thread with anything in `pendingBackgroundTasks`, or with an active thread whose `lineage.parentThreadId` is this one, counts as `running`. The app also waits a few seconds before reporting a thread as finished, to cover the gap between a child finishing and its parent waking.

### Search

The Kitty Litter's ⌘F sends `{"query": "...", "limit": 50}`, the only keys every server takes. T3 wants 2 to 200 letters, and newer servers take more keys, which older ones turn away. It answers with `matches`, one for each message, each with a `threadId`, a `snippet`, a `source` of `user` or `assistant`, and on newer servers a `messageId` and a `quality`. Only `threadId` is read. The snippet comes from what was sent, which for your own messages can be the screen and instructions that went with your words, so it never shows. The Kitty Litter reads each thread named the usual way, which leaves those out, and searches what's left. It's about 30 ms on a real list of a few hundred threads. `swift run probe-t3 search <words>` says how many threads T3 names, how fast, and how many of them are listed, and nothing they say.

### Approvals

The shell only gives `pendingRuntimeRequest {id, kind, createdAt, blocking}`. The words are on a turn item with `type: "approval_request"`, whose ID is `turn-item:runtime-request:<encodeURIComponent(requestId)>`.

The `prompt` there isn't what you'd expect. Claude puts the command or path in it, but Codex puts its *reason for asking*, such as "May I run this exact command?". The actual command is on the `command_execution` item with the same `nativeItemRef.nativeId`, as `input`, wrapped like `/bin/zsh -lc '…'`. A file change works the same way, with `fileName` on a `file_change` item.

To answer:

```json
{"type": "runtime-request.respond", "commandId": "<uuid>", "threadId": "…", "requestId": "…", "decision": "accept"}
```

Decisions are `accept`, `acceptForSession`, `acceptAlways`, `decline` and `cancel`. Some requests only allow a subset, listed in the item's `options`.

Testing tip: under `approval-required`, Codex runs with its `untrusted` policy, which runs commands it knows are safe without asking. A plain `echo` won't prompt, but `echo x > /tmp/file` will.

### Questions

A blocking `pendingRuntimeRequest` of kind `user_input` is an agent asking something. The words are on a turn item with `type: "user_input_request"`, at the same ID an approval would use, with `questions: [{id, question, options: [{label, description, value}], multiSelect, allowCustomAnswer}]`. The cat's bubble shows the first question and its options.

The same command answers it, with `answers` in place of `decision`, filed under each question's `id`:

```json
{"type": "runtime-request.respond", "commandId": "<uuid>", "threadId": "…", "requestId": "…", "answers": {"<question id>": "Blue", "<another>": ["Large"]}}
```

An option sends its `value`, or its `label` if it has none, and your own words go in as they are, unless `allowCustomAnswer` is `false`. A `multiSelect` question wants a list of the values picked, even of one, while your own words stay a string. T3's own composer won't send until every question has an answer, so The Kitty Litter asks them one at a time and sends them together. A question with no `id` has nowhere to file its answer, and is answered in T3, as is one whose turn item can't be read. T3 files one answer under each `id`, so different questions sharing one are asked together, in your own words, and the same question asked twice, which Claude's IDs make possible since they're the question's words, is asked once. As with approvals, the thread is the request's own, which for a subagent isn't the listed one. `probe-t3 question` checks it live: a thread asks two questions at once, one taking several choices, The Kitty Litter answers the first with an option and the second with two, and the thread carries on with all three.

### Reports and settling

- Each turn item has a `runId`, so asking for one run's report can come back empty when that run said nothing, rather than with the words of the run before.
- `orchestration.getThreadProjection` gives a thread's turn items, and took about 60 ms even on threads with hundreds of them. The final report is the newest `assistant_message` with no `parentItemId`, since subagents have one. Claude's thinking also arrives as `assistant_message`, with `thinking` in its ID.
- The same projection says who started a thread, which decides whether it gets your screen. `lineage.parentThreadId` only covers subagents, so a thread from `t3_thread_launch` has none. Its `thread.createdBy` is `"agent"`, and the first user message in `messages` has a `senderThreadId` naming the thread that launched it, even if it was launched idle. `"user"` means a person or The Kitty Litter started it. `probe-t3 origin <thread>` shows the result.
- `{"type": "thread.settle", "commandId": …, "threadId": …}` settles a thread. It can still take a follow-up afterwards, which was checked live.

### Who said what

The Kitty Litter reads a thread's turn items and folds them into exchanges: someone asked, and the agent answered. The fold is `T3Transcript.exchanges`, and it's pure.

- **The full list.** `orchestration.subscribeShell` with `omitIdleSubagents: false` and `omitOlderSettled: false` gives one snapshot of every thread that isn't archived, subagents included. A real one was 234 threads and 470 KB, in 143 ms. The client interrupts the stream after that first snapshot. The snapshot's `archivedThreads` key exists but is empty, so an archived thread can't be named, and a sender in one shows as someone else.
- **Shell fields.** `settledAt` is set exactly when a thread is settled. `pullRequests` is `[{number, url, snapshot: {state, title, …}}]`, where `state` is `open`, `merged` or `closed`, and the last one counts. Its `url` is how a link to it in a message finds its state for the chip The Kitty Litter draws.
- **A `user_message` item** has `text`, `messageId`, `createdBy` (`user` or `agent`), `creationSource`, `senderThreadId` and `inputIntent` (`turn_start`, `queued_turn` or `steer`). A missing or `user` `createdBy` is a person. `agent` with `senderThreadId` is that thread, or the nearest listed thread above it for a subagent. Anything else, including a value T3 adds later, is never treated as a person. What a schedule sends has a `scheduledTaskId`, and the `createdBy` of whoever set the schedule up, which is `agent` with no `senderThreadId` for one made with T3's `schedule_task` tool. It's read as the schedule whatever it says, so a kitten's scheduled run is its own work, and its report starts a thread in its channel instead of the schedule's prompt doing so as someone else.
- **Items T3 writes itself.** Some `user_message` items carry a non-null `idleCompaction` or `workflowScript`. Some of those say `createdBy: user`, so they're skipped by name. Notifications and delegated completions are their own `notification` item type, so skipping by type removes them, and a reply after one carries on the same exchange.
- **Words.** Only what's above the first `---` line of a person's message is theirs, from `Prompts.ownWords`, whatever ends that line, and it comes out as nothing if it still has a screen tag that isn't alone in backticks. Imported threads mark what the coding tool behind them wrote as the user's, in tags such as `<system-reminder>` and `<task-notification>`, so `T3Wire.withoutToolBlocks` takes those out of what's above the line. It only knows the tags found in real threads, because people write hyphenated tags too, so a new one reads as the person until it's added to `T3Wire.toolTags`. Agents' messages and replies keep their `---` lines, which are usually just markdown, and lose any screen block. `Prompts.withoutBlocks` counts tags to balance them, so nested blocks come out whole, one that never closes goes through the end, and an extra closing tag takes what came before it. A tag alone in backticks is someone writing about it, so it stays, but a block in backticks still comes out. T3 leaves `Ultrathink:` on the front of some messages, and uses `[User attached one or more files without additional text. Respond using the conversation context and the attached files.]` for one that's only attachments.
- **Pairing a reply with its ask.** A reply goes to the exchange its run started, matching the run's `userMessageId` to the message's `messageId`, which keeps a queued follow-up from taking an earlier answer. Runs are missing on most of T3's old items (72% of assistant items across its history), so without one it goes to the latest exchange. A steer shares the run it joined, and what comes after it answers the steer. A later reply clears an earlier failure from its exchange, as `finalReport` only counts errors from the last run.

- **The whole thread.** `orchestration.getThreadProjection` never answers with more than the latest 75 or so rows, and commands, reasoning and tool calls count as rows. That left 8 of 19 real kitten threads with no user message at all. `orchestration.subscribeThread` with no `acceptBoundedSnapshot` and no `afterSequence` starts with the whole thread, as a `snapshot` item, and the client interrupts it after that, the same way as the full list. Those 19 threads came to 11.3 MB. The largest of 192 was 15 MB, and took about a second. The socket accepts frames up to 64 MB, so a much larger thread would drop the connection.

### Attachments

1. `attachments.createUploadUrl` with `{"type":"image","name":…,"mimeType":…,"sizeBytes":…}` gives `attachmentId` and `relativeUrl`. The URL is signed, lasts 10 minutes and needs no sign-in.
2. `POST` the exact bytes to it. The server answers 204, and checks the size.
3. Send `{"type":"image","id":<attachmentId>,"name":…,"mimeType":…,"sizeBytes":…}` in the message.

Images can be GIF, JPEG, PNG or WebP, up to 10 MB each and 80 MB per message. Nothing here checks that the bytes really are an image, so a corrupt one reaches the model.

T3 saves each one as `userdata/attachments/<threadId>-<id>.<ext>`, readable by anything running as you, and doesn't remove it later, even when the thread goes. It sends Claude the image inside the message, as base64, so denying the folder doesn't stop an attached image arriving. It also adds that folder to every Claude thread's additional directories. The base64 ends up in T3's provider log and Claude's transcript too.

A user message's turn item lists what came with it, as `attachments: [{"type":"image","id":…,"name":…,"mimeType":…,"sizeBytes":…}]`, so The Kitty Litter sends each dropped or attached picture named for its file, and pairs them up again by name after a restart. A message from before that has one called `screen.jpg`, which pairs with the one file its screen block names. Names are only read from a message with one screen block besides The Kitty Litter's warning about it, since a router's hand-off follows that block and could carry one of its own naming the look at your screen. `assets.createUrl` with the `attachment` resource gives a signed `relativeUrl` under `/api/assets/`, good for an hour, which needs no sign-in, and only `orchestration:read`. `probe-t3 picture` sends a made-up picture to a test thread, reads it back and fetches its copy.

### A picture in a thread's folder

`assets.createUrl` with `{"_tag":"workspace-file","threadId":…,"path":…}` needs `filesystem:read`. T3 finds the thread's own folder, its worktree or its project, makes a relative path of an absolute one, and turns away anything outside it, after resolving symbolic links, along with anything that isn't a file T3 previews, such as a picture, a page or a PDF, and its own internal files. The Kitty Litter only asks for picture names, and only shows what decodes as a picture. `probe-t3 picture <thread> <path>` asks for one and prints its size. Run against a thread whose folder is a copy of this repo, `assets/cat.png` came back at 256×256, and `../../../../shades/assets/cat.png`, an absolute path outside the folder, `Package.swift`, and a symbolic link in the folder pointing at a picture outside it, all came back refused.

### Opening a thread

`t3code://threads/<environmentId>/<threadId>`, with both parts percent-encoded as `encodeURIComponent` does, the way T3 builds its own thread links. A thread ID can hold colons, and even a `%`, as `thread:project:mcp%3A…` does, so a `%` goes as `%25`. The app comes to the front and its router goes to `/<environmentId>/<threadId>`, decoding both. The thread's `lastVisitedAt` updating is a good way to check it worked.

The environment ID is the `environmentId` from `/.well-known/t3/environment`, read as The Kitty Litter connects, or else `userdata/environment-id`. Both are the server's own persisted ID, the one its links are built from, so they can't differ from what T3 routes on. If The Kitty Litter has neither, or macOS doesn't open the link, the cat says which, with macOS's error code, rather than nothing.

## What's stable and what isn't

None of this is promised by T3. Roughly, from most to least likely to last:

| Likely stable | Could change any release |
| --- | --- |
| `t3 auth session issue`, documented for headless clients | Every RPC method name and payload |
| `server-runtime.json` and `/.well-known/t3/environment` | Event and turn item shapes |
| `orchestrationProtocolVersion`, which exists to flag breaks | The turn item ID conventions used for approvals |
| The `t3code://threads/…` link | How each provider fills in `prompt` |

The client is built to notice rather than misbehave. Unknown stream items and fields are skipped, a thread row it can't read is dropped alone, a bad protocol version stops it at connect, and unknown methods or payloads report a version mismatch. If the approval item IDs stop working, it reads the whole thread, and failing that shows a generic summary.

## Other things worth knowing

- Every Claude thread gets T3's MCP server, with `mcp__t3-code__*` passed as allowed tools, in every runtime mode. There's no setting per thread or project to leave them out. A deny rule in the folder's `.claude/settings.json` still wins, because T3 loads the user, project and local settings. T3's own check on sending is that a thread can't message or start one with a broader runtime or interaction mode than its own, which says nothing about whether it's seen your screen.
- Revoking a session with the CLI doesn't hang up a socket that's already open, at least not within 20 s, since the CLI is a separate process. It takes effect at the next connect.
- There's also a `t3 thread` CLI for starting and messaging threads, which wasn't needed here.
- `~/.t3/userdata/statev2.sqlite` is handy for seeing real shapes, opened with `mode=ro`, but the app must never read it.

## Measured

On an Apple Silicon Mac, against server 0.1.6, with `gpt-6.1-sol` at low effort:

| What | Time |
| --- | --- |
| First connect, including sign-in | 0.8 to 0.95 s |
| Connect with a saved sign-in | 10 to 30 ms |
| First thread list | 120 to 170 ms |
| Calling `start` to `.started` | 15 to 50 ms |
| The same, with a 361 KB image | 26 ms |
| Calling `start` to the server's `requestedAt` | 7 to 16 ms |
| Server's `completedAt` to `.finished` | 17 to 26 ms |
| Answering an approval | 7 to 11 ms |
| Back up after a server restart, with a new sign-in | 0.8 s |

So the client adds about 40 ms to a turn. The rest is the model: replying "ok" usually took 4 to 8 s, but once took 84 s, with the server's own timestamps showing the run had started 83 s before the first message.
