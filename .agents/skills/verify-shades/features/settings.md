# Settings

Every setting in one place, a page at a time: **Agents** (the models and their modes), **Voice** (the hold keys and extra words), **Notifications** (Do Not Disturb, Also when a session finishes, and what each channel tells you), **Messages** (theme, text size, where Open goes, and the phone) and **Privacy** (the private apps). It opens from Settings... in the cat's menu, under the menu bar icon, or from Settings at the foot of Messages' sidebar or ⌘, there, over the window. A change takes as you make it, with nothing to save, and it never makes Shades the active app.

## Sub-features

- `settings-pages` turns between the five pages with the tabs at the top. The panel keeps its top right corner where it is.
- `settings-now` takes a change at once: a menu or a box when you pick or tick it, and a typed box when you press Return, move on or close Settings. Nothing has the keyboard until you click into a box, so a stray key can't type over a model.
- `settings-same-switch` is Do Not Disturb and each channel's notifications going through the same switch and the same menu as the menu bar and a channel's header. A change made there while Settings is open shows in it, and a change made in Settings never sets them back.
- `settings-text-size` draws what's said in Messages, and the box you type in, at Small, Default, Large or Larger.
- `settings-open` sends the bubble's Open, and a click on a notification, to Messages wherever it has the thread, or always to T3.

## How to get to it (user POV)

- Click the menu bar item, or right-click the cat, and choose Settings....
- Or press Settings at the bottom of Messages' sidebar, or ⌘, while Messages has the keyboard.
- Turn to a page with the tabs at the top. Press Done or Esc to close it.

## Driving it with the demo

Preconditions:

- A fresh demo. Demo mode doesn't save settings, and prints `[demo] settings aren't saved in demo mode` for each change instead.

Journey: `journeys/settings.txt`. `settings <page>` turns to a page, the same as its tab. `setting <row> [choice]` changes the control on that row, found by its label or a box's own words: it picks the choice from a menu, types it into a box and presses Return, or ticks a box or presses a button. It prints each control on the page afterwards.

- **Agents.** `settings`, then `draw`. `1-agents/settings.png` shows the tabs with Agents picked, the three models and two modes, with no box holding the keyboard. `setting Front door mode Accept edits` prints `Front door mode: Accept edits`.
- **Notifications.** `setting Also when a session finishes` prints `[x] Also when a session finishes`. `notifications steve mute`, the channel header's own menu, then `draw`. `2-notifications/settings.png` lists #general, #steve-pawsniak as Muted, the other kittens and Shades.
- **Messages.** `setting Phone` ticks the phone and the pairing code shows. `setting Open threads In T3` and `setting Text size Larger`, then `channels` and `channel steve`. `3-messages/channels.png` shows Steve's channel in bigger words and Settings at the foot of the sidebar, beside Theme and ⌘/ Shortcuts. `3-messages/settings.png` shows Theme, Larger, In T3, the phone ticked and Pair a phone....
- **From Messages.** `setting Done` closes it, then `sidebar Settings` opens it again, centred near the top of Messages, as `windows` shows.
- **Privacy.** `setting Private apps com.example.vault, com.example.diary` prints that list, and `4-privacy/settings.png` shows it in the box with the note under it.
- **The one switch.** `setting Do Not Disturb`, then `dnd` prints `dnd on cat=sleep`, and `menuitems` has `menu ✓ Do Not Disturb`.

## Gotchas

- Theme and a channel's button open a menu, which waits for a click, so `setting` won't press them. `colors` and `notifications` stand in for picking from them, and Settings shows the result.
- `front` must stay whatever was in front before the run. `window settings ... key=true` and `active=true` are expected while Settings has the keyboard.
