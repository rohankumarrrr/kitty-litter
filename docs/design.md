# Opal Horizon

Opal Horizon is The Kitty Litter's design system, and its only look. It's black opal: a near-black body, with colour entering only as light along an edge. It's dark only, and it's meant to feel like one system with an Opal Mac and iPhone: the same black glass, the same rim of cyan, violet and pink, the same plain SF Pro type in white.

This page is the spec. Every surface is built from it, and `DesignTests` checks the parts a test can: no orange anywhere, words that read at 4.5:1 on what they sit on, and tokens that stay Opal's.

- [Principles](#principles)
- [Colour](#colour)
- [Kittens](#kittens)
- [Type](#type)
- [Shape and space](#shape-and-space)
- [Light](#light): the rimlit card, floating glass, the Rimlight tile, the rim gradient, the meter
- [Controls](#controls)
- [Motion](#motion)
- [Which surface gets which](#which-surface-gets-which)
- [Conventions](#conventions)
- [Don't](#dont)
- [In code](#in-code)

## Principles

- **Colour enters only as light.** Surfaces are violet-black. Colour comes in along an edge: a card lit from below, a tab underlined in the rim's light, the line over what's new. Nothing's body is tinted or washed in a gradient.
- **The glow stays faint.** If it's the first thing you notice, it's too loud.
- **High contrast.** Titles and figures are white, and everything you read holds 4.5:1. Low-contrast grey on grey reads as unfinished.
- **Glass is only for what floats.** Menus, popovers, the Ask box and anything over other windows. Never content.
- **One primary per view.** One violet button at most, for the thing you most likely want.
- **Do what the apps you use do.** Where Slack, Discord, iMessage or macOS has a settled way, that's the way here. See [Conventions](#conventions).

## Colour

Every value here is a token in `Opal.swift`. Use the role, never a raw hex.

### Surfaces

| Role | Token | Colour | For |
|---|---|---|---|
| Chrome | `chrome` | `#0A080D` | A main window's frame and sidebar, which sit flush on it |
| Page | `page` | `#0C0A10` | The inset content panel, and a floating panel's body |
| Raised | `raised` | `#15121B` | Fields, a hovered row, a menu's glass |
| Control | `control` | `#1B1723` | A quiet button, a segmented track, a chip |
| Control hover | `controlHover` | `#262030` | A hovered control, the chosen segment |
| Selected | `selected` | `#1E1830` | A selected row, your own message |
| Border | `border` | `#241F2E` | Hairlines between things in content |
| Chrome border | `chromeBorder` | `#1F1B27` | Hairlines on the chrome |
| Field edge | `fieldEdge` | `#2B2536` | A field's edge, a quiet button's hairline |

### Words

| Role | Token | Colour | Sits on |
|---|---|---|---|
| Title, figure | `white` | `#FFFFFF` | Anything, including the primary button |
| Body | `body` | `#E7E4EC` | Any surface |
| Secondary: times, names, captions | `secondary` | `#A09AAD` | Any surface, hover and selected included |
| Dim | `dim` | `#837D90` | Opaque chrome, page, raised and cards only. On a control, a hovered or selected row, or glass over a bright desktop it's under 4.5:1, so use secondary there. A control's edge, such as an unticked box, can be dim, since it needs 3:1 |
| Faint | `faint` | `#5E586B` | Words on a disarmed control only, which don't need to read |
| Label | white at 55% | | Small capitals on any surface (5.7:1 or better) |

### Light

| Role | Token | Colour |
|---|---|---|
| Accent: focus ring, selection, a ticked box, an unread bar | `violet` | `#8A6CFF` |
| Primary button | `primary` | `#7458E8` |
| Primary button, hovered | `primaryHover` | `#7A5DEE` |
| Primary button, pressed | `primaryPressed` | `#664DCC` |
| "Now", working, links, reply counts, hover ink | `lilac` | `#B9A6FF` |

Violet isn't for words: it falls under 4.5:1 on a hovered row. Words in the accent use lilac. White on the primary is 4.88:1, so the primary's hover moves only a quarter of the way toward violet, the furthest white still reads at 4.5:1, and pressing darkens it.

Selected words in a message are drawn the other way round, so they read whatever they sit on: light words go to `page` on violet (5.3:1), and black words on a kitten's bubble go to `body` on `page`, since violet can be as light as that bubble. They look the same with or without the keyboard. Without it, AppKit swaps in its own grey, which black words disappeared under, so The Kitty Litter keeps Opal's.

### Status

| Role | Token | Colour | Tinted surface |
|---|---|---|---|
| Info | `info` | `#7FD6FF` | `infoSurface` `#132430` |
| Good, done | `good` | `#7FE3C4` | |
| Warning | `warning` | `#F3E6A8` | `warningSurface` `#26231A` |
| Error, needs you | `error` | `#FF7A9A`, as words `errorText` `#FF97B1` | `errorSurface` `#2A1420` |

- **No orange anywhere, warnings included.** The only warm warning colour is pale yellow. `DesignTests` fails on any orange in the code.
- Status colours and kitten colours never stand in for each other. A kitten's colour says who, and a status colour says how it's doing.
- A count of what needs you is a rose capsule with page-coloured figures in it (8:1).
- The cat's glint and a kitten's status dot use the same four: lilac while it works, rose when it needs you or failed, mint when it's done. Its glint flashes the rim's cyan when it celebrates.

### The rim

`rimCyan` `#45CFFF` → `rimViolet` `#805CFF` → `rimPink` `#FF4FB8`, left to right or top to bottom. It's the only gradient, and only ever a line or a glow: a tab's underline, a meter's fill, the unread line.

## Kittens

Each kitten has one soft identity colour from this palette, in its `kitten.json` as `color`. It's the kitten's jacket on the pixel cat, its Rimlight tile's light, its card's light, and anywhere else it's picked out. Shades wears the black jacket, and its light is the [card's](#the-rimlit-card) hue 245.

| Name | Colour | OKLCH |
|---|---|---|
| Teal | `#56AFB3` | 0.70 0.085 199 |
| Sky | `#7FBDE4` | 0.77 0.085 237 |
| Cornflower | `#6A8BCF` | 0.64 0.109 264 |
| Indigo | `#706CBB` | 0.57 0.120 284 |
| Orchid | `#B777BB` | 0.66 0.121 325 |
| Plum | `#9E5B82` | 0.56 0.101 345 |
| Rosewood | `#D799B1` | 0.75 0.080 354 |
| Sage | `#94B68C` | 0.74 0.070 140 |

Why these:

- They follow Opal's rimlit hues, teal through violet to pink, and add a sage, so eight kittens can be told apart at a glance.
- Chroma stays at about 0.07 to 0.12 in OKLCH, about what Opal's lilac and cyan carry, and well under the 0.15 to 0.21 that read as loud.
- Lightness stays between 0.55 and 0.77. Any lighter and a jacket washes into the cat's white fur. Any darker and it goes muddy on the near-black.
- None is orange, and none sits near a status colour: each is at least 0.06 away in OKLab from mint, pale yellow, rose, cyan and lilac, and each pair is at least 0.08 apart. `DesignTests` holds all of that.

**For a new kitten,** pick the first colour in the table that no other kitten wears. Once all eight are taken, pick the one worn by the kitten it's least often seen beside. A kitten with no `color` gets one from this palette picked from its folder, so it's the same every time, though it may share one. Never invent a colour outside the palette: a new colour comes into the palette first, through this page and `DesignTests`.

## Type

The face is the system's, SF Pro, unless you pick another in Settings, which every role then uses. Text size in Settings (Small, Default, Large or Larger) adds a step to every role: Small −1, Default 0, Large +2, Larger +4 points. Meta and labels grow half as fast, so they stay quieter than what they're about.

| Role | Small | Default | Large | Larger | Weight | Colour |
|---|---|---|---|---|---|---|
| Toolbar title | 14 | 15 | 17 | 19 | Semibold | White |
| Title: a card's, a heading, a name | 13 | 14 | 16 | 18 | Semibold | White |
| Body: what's said | 12 | 13 | 15 | 17 | Regular | Body |
| Meta: times, counts, captions | 10.5 | 11 | 12 | 13 | Regular | Secondary |
| Label: small capitals | 10.5 | 11 | 12 | 13 | Medium, tracked 0.09 em, uppercase | White at 55% |
| Figure | 31 | 32 | 34 | 36 | Light (300), tabular | White |
| Control: a button's words | 12 | 12 | 12 | 12 | Medium | Per style |

- **Labels** head a section or a card ("CHANNELS", "NEXT UP"), never a sentence.
- **Figures** are light with tabular digits, so a changing number holds still. A big clock goes to 200. A figure in a row is the body size, still tabular.
- **The phone** has a 32-point bold large title, white, at the top of each page, and its body follows the phone's own text size.
- One short line under a name and under a figure, in meta or secondary.

## Shape and space

| | Corner |
|---|---|
| Main window's inset panel | 15 |
| Card | 18 |
| Card floating on the desktop, like the cat's bubble | 20 |
| Field, menu row, list row highlight | 9 |
| Popover, menu, the Ask box | 16 |
| Sheet | 24 |
| Button, chip, segmented control, count | Capsule |

- **A main window:** the sidebar sits flush on the chrome. The content is one panel in `page`, inset 8 from the window on its three free sides, with 15 corners and a `chromeBorder` hairline at its edge. Its toolbar is pinned to the panel's top: the title in the toolbar role, one line under it, and its actions on the right, as icons with their names as tooltips where Slack's are icons.
- **Spacing:** 24 between containers and 24 inside a card on the Mac, 16 and 18 on a phone. Inside a list, 8 between rows' contents and 12 at the sides.
- **Hit targets:** 26 tall for a Mac control, 44 on the phone.
- **Hairlines** are 1 point, in `border` on content and `chromeBorder` on the chrome.

## Light

The recipes below are exact. `OpalLight.swift` draws each one, so a view calls the helper rather than drawing its own.

### The rimlit card

True black glass, lit only along its bottom edge. It's Opal's desktop widget card, the one the cat's bubble copies, since both float on the desktop. As CSS:

```css
.card { border-radius: 20px; background: linear-gradient(#141318e8, #060508f0);
        box-shadow: inset 0 0 0 1px rgba(255,255,255,.07); padding: 15px 18px 16px; }
.card::before { /* the glow rising from the bottom edge */
  inset: auto 0 0 0; height: 72%;
  background: radial-gradient(70% 90% at 50% 112%, hsla(var(--h),100%,60%,.3), transparent 72%); }
.card::after { /* the rim, brightening up the lower sides into the bottom edge */
  border-radius: 20px; padding: 1.2px;
  background: linear-gradient(transparent 58%, hsla(var(--h),100%,68%,.55) 82%, hsl(var(--h),100%,68%)); }
```

- **Body:** `#141318` at 91% at the top to `#060508` at 94% at the bottom, with a 1-point white-7% hairline just inside the edge.
- **Glow:** over the bottom 72% of the card, an ellipse centred 12% below the bottom edge, 70% of the card wide and 90% of the glow's height tall in radius, from the light at 30% to clear at 72% of the way out.
- **Rim:** a 1.2-point line around the edge, clear down to 58% of the height, the light at 55% by 82%, and full at the bottom.
- **Its light:** a hue as `hsl(h, 100%, 68%)` for the rim and `hsl(h, 100%, 60%)` for the glow. Shades' is hue 245. A kitten's card uses its own colour for both.
- `Opal.card(in:radius:light:)`.

### Floating glass

What floats over other windows: menus, popovers, the Ask box, the kittens view, Settings and the pairing code. It's the dark glass of a macOS menu. Like the card, it doesn't blur what's under it: it's dense enough to stand on its own.

- `raised` `#15121B` at 94%, a 1-point white-8% hairline just inside the edge, popover corners (16), and the system's window shadow.
- Words on it follow the [Words](#words) table for `raised`.
- `Opal.glass(_:)` fills and edges any path, a balloon's tail included.

### The Rimlight tile

A white glyph on a black tile, lit from below in its hue: an Opal Dock icon, and the frame for a kitten's cat.

- A rounded square with corners 22.5% of its side.
- The body is the card's black gradient. A glow of its light rises from the bottom centre: an ellipse centred on the bottom edge, as wide as the tile and 60% as tall in radius, from the light at 45% to clear.
- The rim is 1.5 points at a 40-point tile, scaled with it: white at 22% across the top, clear down the sides, brightening into the light along the bottom.
- The glyph is white. A pixel cat goes on it as it is.
- A kitten's tile takes the kitten's colour. A tile that isn't a kitten's, such as a section's in a sidebar, takes a hue drifting down the list from 172° to 344°, teal to pink.
- `Opal.tile(in:light:)`.

### The rim gradient

The rim's three stops as a line: under the open tab (2 points, under the label's width), the unread line (1 point, across the pane), and a meter's fill. `Opal.rim` is the gradient, and `Opal.rimLine(in:)` draws a line of it.

### The meter

A 3-point capsule track in white at 16%. Its fill runs cyan to violet while it's on plan, and violet to pink once it's past. A 1.5-point white tick, 9 points tall, marks where it should be. `Opal.meter(in:fraction:over:tick:)`.

## Controls

### Buttons

`QuietButton` is every button. All are capsules, 26 points tall, with the control role's words.

| Style | At rest | Hovered | Pressed | Words |
|---|---|---|---|---|
| `filled`, the primary | `primary` | `primaryHover` | `primaryPressed` | White |
| `plain`, quiet | `control` with a `fieldEdge` hairline | `controlHover` | `fieldEdge` | Body |
| `text` | Nothing | `control` | `controlHover` | Secondary, body when hovered |

- One primary per view. Most buttons are quiet or text.
- **Danger** is a quiet button whose words are `errorText`. It never fills in rose.
- **Disarmed:** the fill at 40% and words in `faint`.
- **A symbol** in place of words is 13-point medium, in the style's words, and lilac while what it started is going (a mic that's listening).
- **A pop-up**, a quiet button that picks one value from a menu, says what's picked with macOS's up and down chevrons after it (`showsChevrons`), never a ▾ typed into its words.
- **The focus ring** is 2 points of violet just inside the capsule, shown only when the keyboard moved there. On the primary it sits 2 points inside, in white, since its fill is violet already.
- Space presses a button that has the keyboard, and Return never does.

### Fields

`raised`, a 1-point `fieldEdge` edge, corners 9, body words, a placeholder in secondary, since it's often the box's only label, and a 2-point violet ring when it has the keyboard. The insertion point is lilac. `Opal.field(in:focused:)`.

### And the rest

- **Segmented control:** a `raised` capsule track with the chosen segment raised on it in `controlHover`, words body, the chosen one white.
- **Tabs:** underlined text, never pills. The open tab is white with a 2-point rim-gradient underline. Others are secondary.
- **Chips:** capsules on `control`, 22 tall, meta-size words in body.
- **Checkboxes and switches:** the system's, which follow the dark appearance, with the accent in violet. A drawn one is ticked in violet with a white tick, and its empty box has a 1.2-point `dim` edge. A drawn switch is a 32 by 18 capsule, violet with a white knob when it's on, and `control` with a 1.2-point `dim` edge and a body-coloured knob when it's off. A switch is for a whole row in Settings, a checkbox for an option beside other things, such as Also send to #channel.
- **Lists and tables:** hairline rows in `border` under small-capital headers. A hovered row is `raised`, a selected one `selected`, each with corners 9 inset from the edges.
- **Menus:** the system's menus, dark. A custom popover is floating glass.
- **Scrollers:** the system's overlay scrollers.

## Motion

- Short, easing out: Opal's curve is `cubic-bezier(.2, .8, .2, 1)`, `Motion.ease`.
- 120 ms for hover and press, 200 ms for something appearing, 280 ms for something moving.
- Nothing jumps on load, and nothing moves content when it appears on hover. A hover toolbar floats over the row instead.
- The cat's bubble and pill fade in over 200 ms and out over 120 ms, and take no clicks on their way out. The Ask box fades in, and goes at once when you press Return or Escape, as Spotlight does.
- Reduce Motion stills all of it, and the cats hold still. `Motion.isReduced` says when.

## Which surface gets which

| Surface | Gets |
|---|---|
| The Kitty Litter (the Messages window) | Chrome with the sidebar flush on it; the inset page panel with its toolbar; kittens on Rimlight tiles in their colours; message rows on the page, your own on `selected`; the box as a field |
| Settings | Floating glass, laid out as macOS's own Settings is: each setting's name on the left in body, a line on what it does under it in meta and secondary, and its control on the right, with hairlines between rows and small capitals over a group. Underlined tabs for its pages, switches, segmented controls, fields and pop-ups. Done is the one primary, at the bottom right |
| The cat's bubble | A rimlit card in Shades' hue 245, at 20 corners and the widget card's padding, like an Opal desktop widget, since both float on the desktop. A kitten asking or reporting is lit in that kitten's colour. Its stepped tail carries the rim's light down to the cat. A command sits in a code block |
| The Ask box | Floating glass, a field inside it, its mic a text button in the field, and a dropped file as a chip over what you type |
| The pill over the cat | A capsule of floating glass with body words |
| Approvals and questions | In the bubble's card. Allow is the primary, the rest quiet |
| The kittens view and the pairing code | Floating glass. Kittens on Rimlight tiles, with labels in small capitals and status in lilac, rose or mint |
| Menus and popovers | The system's dark menus, or floating glass |
| The phone page | The phone's pure black (`#000000`) with SF Pro, white text at set opacities, a 32-point bold large title on each page, rimlit cards, kittens on Rimlight tiles, the horizon at the foot, 24-point sheets |

## Conventions

Where an app you use every day has a settled way of doing something, do it that way.

- **A message's actions never sit above it.** They float as a small icon toolbar of floating glass at the row's top right, over the row, on hover, the way Slack and Discord do. Reactions and the thread's reply bar sit under the message.
- **Your own messages** sit on the right, on `selected`, like iMessage. Everyone else's are on the left.
- **A count** of what needs you is a rose capsule after the name, like a badge in the Dock or Slack.
- **The open place in a sidebar** is a `selected` row, not a coloured bar.
- **Return sends** in a box, and Shift-Return is a new line, as in Slack.
- **Escape closes** what floats: the Ask box, a popover, the kittens view, the pairing code. ⌘W closes Settings too, as it does any window.
- **A menu** ends with Settings… and Quit in a group of their own, as every Mac app's does. Its items are in Title Case, with … only where more is asked before it happens.
- **A notification** names who in its title and says what in its body, as Messages and Slack do, and Notification Center groups it with the rest of its thread.
- **Times** go after the name in meta, never on their own line.
- **Destructive actions** say what they do ("Delete", not "OK") and are never the primary.
- **A card's buttons** sit at its bottom right with the primary last, as in a macOS alert. An option that does more, such as Allow for this session, sits apart at the left.
- **An error that needs a setting changed** says which, and **Open System Settings** goes to that page.
- **A long answer** opens at its start, its last line fading to say there's more.
- **Empty places** say what will appear there and how, in one secondary line, never a big illustration.

## Don't

- Don't use orange, or any warm warning colour but pale yellow.
- Don't tint a card's body or wash it in a gradient. Its light comes from its bottom edge.
- Don't put glass on content.
- Don't let the glow get loud.
- Don't use pill tabs.
- Don't mix kitten colours with status colours.
- Don't use violet for words. Use lilac.
- Don't put dim words on a control, a hovered row or a selected one.
- Don't add a colour outside this page. Add it here first, and to `DesignTests`.
- Don't follow the system's light appearance. Opal is dark only, and `NSApp.appearance` stays dark.

## In code

- `Sources/Shades/UI/Opal.swift`: every colour token, the kitten palette, the rim's stops, the corners and spacing, and the colour arithmetic (mixing, luminance, contrast).
- `Sources/Shades/UI/OpalLight.swift`: the drawing helpers: `card`, `glass`, `tile`, `rim` and `rimLine`, `meter`, `field`.
- `Sources/Shades/UI/MessagesInk.swift`: the roles views draw with, such as `paper`, `text`, `soft` and `link`, mapped onto Opal's tokens, and the type roles at your text size and font.
- `Sources/Shades/UI/QuietButton.swift` and `QuietPanel.swift`: the buttons, the focus ring, and the floating panels.
- `Sources/Shades/UI/SettingsControls.swift`: Settings' underlined tab, segmented control, switch and field.
- `Sources/Shades/UI/Motion.swift`: the curve, the durations, and Reduce Motion.
- `Tests/ShadesTests/SelectionTests.swift`: fails on selected words under 4.5:1 or hard to see on any surface, and on a selection drawn differently without the keyboard.
- `Tests/ShadesTests/DesignTests.swift`: fails on any orange in `Sources/`, on any word role under 4.5:1 on a surface it sits on, on a kitten colour that's too loud, too pale, too close to another or to a status, and on a token that drifts from Opal's value.
- `swift run shades --demo --no-script --commands .agents/skills/verify-shades/journeys/opal.txt` draws a sheet of every primitive to `.verify/shades/opal/`.
