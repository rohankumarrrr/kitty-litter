# Talking to T3 Code

Shades runs every agent through [T3 Code](https://t3.codes), a local app with a server inside. There's no public API for this. Everything below was read from the app's own bundle and checked against the running server, version 0.1.6, orchestration protocol 2.

All wire formats live in `Sources/ShadesT3/T3Wire.swift`, so a T3 update should only ever mean changing that one file. When T3 updates, run the probes in `Sources/Probes/T3`.

## How it connects

One WebSocket does nearly everything, because approvals and live streaming need it anyway. Uploads and two startup checks use plain HTTP.

1. **Find the server.** Read `<home>/userdata/server-runtime.json` for `origin`. `<home>` is `$T3CODE_HOME` or `~/.t3`. The port is never assumed, and the file is read again on every reconnect, because T3 can come back on another port.
2. **Check the version.** `GET /.well-known/t3/environment` needs no sign-in and gives `orchestrationProtocolVersion`, `serverVersion` and `environmentId`. Anything but protocol 2 stops here with a clear message.
3. **Sign in.** See below.
4. **Open the socket.** `GET /ws?orchestrationProtocol=2` with `Authorization: Bearer <token>`. Without the query item the server answers 426.

If T3 goes away, the client keeps trying, and backs off to one try every 5 seconds. A call made while T3 is down tries straight away and fails fast with "T3 Code isn't running." When T3 returns, subscriptions are sent again: the thread list takes a fresh snapshot, and a running turn resumes after the last event it saw.

## Sign-in

```
t3 auth session issue --scope orchestration:read --scope orchestration:operate --ttl 30d --label Shades --json
```

This is T3's documented way to sign in a headless client. It needs no clicks, because anyone who can run it as this user already has this access. It takes about 0.8 s, and only happens on the first run and when renewing.

- The token goes in the login Keychain under service `dev.shades.t3-session`, with the session ID as the account. It's never logged or written anywhere else.
- A saved token is checked with `GET /api/auth/session` on each connect.
- With 7 days left, the client signs in again and revokes the old session. If the server answers 401 on reconnect, it does the same.
- The session shows up as "Shades" in T3's list of connections.

### Why not MCP?

MCP's OAuth flow needs a person to approve it on the `/connect-agent` page, its sessions are only good for `/mcp`, and MCP deliberately can't answer permission requests. Shades has to answer them, so it needs this surface anyway. A session with a subject of `mcp-client` is refused everywhere except `/mcp`, and pretending to be one would dodge that approval step, so Shades doesn't.

### The Keychain and rebuilds

Keychain items belong to the exact signed code that made them. A rebuilt app with an ad hoc signature counts as a different app, so it can't read the old item.

macOS would normally ask about that with a dialog on every rebuild, so the store turns prompts off. An unreadable item means signing in again, about 0.8 s and no dialog, and the last build's session gets revoked. The old item can't be deleted or changed by the new build, so it stays behind, harmless, until something signed like the old build removes it, or you delete it in Keychain Access.

A few things learned the hard way:

- **Never call `SecItemUpdate` on these items.** Changing an attribute on another build's item shows a dialog even with `SecKeychainSetUserInteractionAllowed(false)`. Reading, deleting and listing attributes don't.
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
| `orchestration.subscribeThread` | One thread's events. Also one whole thread, for Messages. |
| `orchestration.subscribeShell` | Every thread, for the dashboard. Also one full snapshot, for Messages. |
| `orchestration.getTurnItem` | The words of an approval or a question. |
| `orchestration.getThreadProjection` | A thread's final report, a fallback for those words, and a settled thread's runtime mode. |
| `projects.ensureScratch` | The "No project" project. The client remembers it. |
| `projects.mutate` | Registers the router's own folder as a project, the first time. |
| `attachments.createUploadUrl` | A signed URL for one upload. |

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

A follow-up is a `message.dispatch` command with `dispatchMode {"type":"start_immediately"}` and no `deliveryIntent`. Leaving out `modelSelection` keeps the thread's own model, which is how the router forwards a message into a session. That always gives the message its own run: it starts now on an idle thread and queues behind an active one. Adding `deliveryIntent: "auto"`, as T3's own composer does, can steer a run that's already going, and then there's no separate turn to report on.

Only send `thread.runtime-mode.set` when the mode really changes. For providers that can't switch mode inside a session, it ends the session, and the next turn pays to start a new one.

#### Who a message is from

`message.dispatch` sends `createdBy: "user"`. A launch sends none, and T3 records the user, which we measured on real threads Shades started. Agents using T3's tools show `createdBy: "agent"`.

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

An option sends its `value`, or its `label` if it has none, and your own words go in as they are, unless `allowCustomAnswer` is `false`. A `multiSelect` question wants a list of values, so an option for one goes as a list of one, while your own words stay a string. T3's own composer won't send until every question has an answer, so Messages asks them one at a time and sends them together. A question with no `id`, or one sharing its `id` with another, has nowhere of its own to file its answer, and is answered in T3. As with approvals, the thread is the request's own, which for a subagent isn't the listed one. `probe-t3 question` checks it live: a thread asks two questions at once, Shades answers each with an option, and the thread carries on with both answers.

### Reports and settling

- Each turn item has a `runId`, so asking for one run's report can come back empty when that run said nothing, rather than with the words of the run before.
- `orchestration.getThreadProjection` gives a thread's turn items, and took about 60 ms even on threads with hundreds of them. The final report is the newest `assistant_message` with no `parentItemId`, since subagents have one. Claude's thinking also arrives as `assistant_message`, with `thinking` in its ID.
- The same projection says who started a thread, which decides whether it gets your screen. `lineage.parentThreadId` only covers subagents, so a thread from `t3_thread_launch` has none. Its `thread.createdBy` is `"agent"`, and the first user message in `messages` has a `senderThreadId` naming the thread that launched it, even if it was launched idle. `"user"` means a person or Shades started it. `probe-t3 origin <thread>` shows the result.
- `{"type": "thread.settle", "commandId": …, "threadId": …}` settles a thread. It can still take a follow-up afterwards, which was checked live.

### Who said what

Messages reads a thread's turn items and folds them into exchanges: someone asked, and the agent answered. The fold is `T3Transcript.exchanges`, and it's pure.

- **The full list.** `orchestration.subscribeShell` with `omitIdleSubagents: false` and `omitOlderSettled: false` gives one snapshot of every thread that isn't archived, subagents included. A real one was 234 threads and 470 KB, in 143 ms. The client interrupts the stream after that first snapshot. The snapshot's `archivedThreads` key exists but is empty, so an archived thread can't be named, and a sender in one shows as someone else.
- **Shell fields.** `settledAt` is set exactly when a thread is settled. `pullRequests` is `[{number, url, snapshot: {state, title, …}}]`, where `state` is `open`, `merged` or `closed`, and the last one counts.
- **A `user_message` item** has `text`, `messageId`, `createdBy` (`user` or `agent`), `creationSource`, `senderThreadId` and `inputIntent` (`turn_start`, `queued_turn` or `steer`). A missing or `user` `createdBy` is a person. `agent` with `senderThreadId` is that thread, or the nearest listed thread above it for a subagent. Anything else, including a value T3 adds later, is never treated as a person.
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

### Opening a thread

`t3code://threads/<environmentId>/<threadId>`, with both parts percent-encoded. The app comes to the front and navigates there. The thread's `lastVisitedAt` updating is a good way to check it worked.

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
