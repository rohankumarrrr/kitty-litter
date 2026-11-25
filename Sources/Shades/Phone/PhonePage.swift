import Foundation
import ShadesCore

enum PhonePage {
    static let html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="dark">
        <meta name="theme-color" content="#000000">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
        <meta name="apple-mobile-web-app-title" content="Kitty Litter">
        <title>The Kitty Litter</title>
        <link rel="manifest" href="/manifest.json">
        <link rel="apple-touch-icon" href="/icon.png">
        <link rel="stylesheet" href="/app.css">
        <script src="/app.js" defer></script>
        </head>
        <body>
        <header id="top">
          <nav id="bar">
            <button id="back" type="button" hidden><svg class="symbol" viewBox="0 0 24 24" aria-hidden="true"><path d="M15 4l-8 8 8 8"/></svg><span id="backtitle"></span></button>
            <p id="bartitle" aria-hidden="true"></p>
            <div id="actions">
              <button id="unread" class="symbolic" type="button" hidden><svg class="symbol" viewBox="0 0 24 24" aria-hidden="true"><path d="M13 5H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1v-7"/><path d="M3 7l9 6 3-2"/><circle class="fill" cx="19" cy="5" r="3"/></svg><span class="unseen">Mark unread</span></button>
              <button id="read" class="symbolic" type="button" hidden><svg class="symbol" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 10l9-6 9 6v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/><path d="M3 10l9 6 9-6"/></svg><span class="unseen">Mark as read</span></button>
              <button id="find" class="symbolic" type="button" hidden><svg class="symbol" viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5 21 21"/></svg><span class="unseen">Search</span></button>
            </div>
          </nav>
          <form id="search" hidden>
            <svg class="symbol" viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5 21 21"/></svg>
            <input id="query" type="search" enterkeyhint="search" autocomplete="off" placeholder="Search messages" aria-label="Search messages">
            <button id="searchcancel" type="button">Cancel</button>
          </form>
          <button id="jumpnew" type="button" hidden></button>
          <div id="banner" role="status"></div>
        </header>
        <div id="head" hidden>
          <span id="headcat" class="tile" hidden></span>
          <div id="names">
            <h1 id="title">The Kitty Litter</h1>
            <p id="subtitle"></p>
            <button id="link" type="button" hidden></button>
            <button id="t3" type="button" hidden>Open in T3</button>
            <button id="backlog" type="button" hidden></button>
          </div>
        </div>
        <div id="notify" class="lit" hidden>
          <p id="notifytext"></p>
          <button id="notifybutton" class="go" type="button" hidden>Turn on</button>
        </div>
        <main id="rows"></main>
        <main id="found" hidden></main>
        <form id="box" hidden>
          <label id="label" for="words"></label>
          <div id="attached" hidden></div>
          <div class="field">
            <button id="attach" class="symbolic" type="button" aria-label="Add a photo or file"><svg class="symbol" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg></button>
            <div class="entry">
              <textarea id="words" rows="1"></textarea>
              <button id="send" type="submit"><span class="disc"><svg class="symbol" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19V5M6 11l6-6 6 6"/></svg></span><span class="unseen">Send</span></button>
            </div>
          </div>
          <input id="pick" type="file" accept="image/*,application/pdf" multiple hidden>
          <label id="alsolabel" hidden><input type="checkbox" id="also"> <span id="alsotext"></span></label>
        </form>
        <dialog id="linksheet" class="sheet" aria-labelledby="linktitle">
          <p id="linktitle"></p>
          <p id="linkaddress"></p>
          <div class="buttons">
            <button id="linkcancel" type="button" autofocus>Cancel</button>
            <a id="linkopen" class="go" target="_blank" rel="noopener noreferrer">Open</a>
            <button id="linkshow" class="go" type="button" hidden>Show</button>
          </div>
        </dialog>
        <dialog id="reactsheet" class="sheet" aria-label="React">
          <div id="marks"></div>
        </dialog>
        <section id="pair" hidden>
          <h1>Pair this phone</h1>
          <p id="pairhow">Turn on The Kitty Litter on my phone in Settings on your Mac, and it shows a code. Scan it with your camera, or type it here.</p>
          <form id="pairform">
            <input id="code" autocomplete="one-time-code" autocapitalize="characters" autocorrect="off" spellcheck="false" placeholder="ABCD-EFGH" aria-label="Code">
            <button type="submit" class="go">Pair</button>
          </form>
          <p id="pairnote" role="status"></p>
        </section>
        </body>
        </html>
        """

    static let style = """
        :root {
          font: 106.25%/1.35 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
          -webkit-text-size-adjust: 100%;
        }
        /* Outside the repo: Safari on iPhone starts at 16px whatever its Text Size says, and only gives that setting through -apple-system-body. */
        @supports (-webkit-touch-callout: none) {
          :root { font: -apple-system-body; line-height: 1.35; }
        }
        * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
        html { background: var(--page); color: var(--body); }
        body { margin: 0; min-height: 100dvh; display: flex; flex-direction: column; font-size: var(--size, 100%); }
        button { font: inherit; color: inherit; background: none; border: 0; padding: 0; cursor: pointer; min-width: 44px; min-height: 44px; }
        [hidden] { display: none !important; }
        .unseen { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
        .symbol { width: 22px; height: 22px; flex: none; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
        .symbol .fill { fill: currentColor; stroke: none; }
        .symbolic { display: inline-grid; place-items: center; color: var(--lilac); border-radius: 999px; }
        .symbolic:active { background: var(--control); }

        #top { position: sticky; top: var(--above, 0px); z-index: 2; background: var(--page);
          padding: env(safe-area-inset-top) calc(env(safe-area-inset-right) + 8px) 0 calc(env(safe-area-inset-left) + 8px); }
        #top.collapsed { background: var(--glass); box-shadow: 0 1px var(--glass-edge); -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px); }
        #bar { display: grid; grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr); align-items: center; min-height: 44px; }
        /* Outside the repo: WebKit bug 244139: Safari on iPhone doesn't always redraw what changes in a sticky bar, but does redraw a part on a layer of its own. */
        #bar > * { will-change: transform; }
        #back { grid-column: 1; justify-self: start; display: flex; align-items: center; gap: 2px; max-width: 100%; padding-right: 8px;
          color: var(--lilac); white-space: nowrap; overflow: hidden; }
        #back .symbol { stroke-width: 2.2; }
        #backtitle { overflow: hidden; text-overflow: ellipsis; }
        #bartitle { grid-column: 2; margin: 0; max-width: calc(100vw - 200px); color: var(--white); font-weight: 600; white-space: nowrap; overflow: hidden;
          text-overflow: ellipsis; visibility: hidden; }
        #top.collapsed #bartitle { visibility: visible; }
        #actions { grid-column: 3; justify-self: end; display: flex; }
        #search { position: relative; display: flex; align-items: center; gap: 4px; min-height: 52px; padding: 4px 0 4px 8px; }
        #search .symbol { position: absolute; left: 18px; width: 18px; height: 18px; color: var(--secondary); pointer-events: none; }
        /* Outside the repo: Safari on iPhone zooms in on a field under 16px as you type. */
        #query { flex: 1; min-width: 0; font: inherit; font-size: max(16px, 1em); color: var(--white); caret-color: var(--lilac); background: var(--raised);
          border: 1px solid var(--field-edge); border-radius: 12px; padding: 8px 12px 8px 36px; min-height: 44px; }
        #query::placeholder, #words::placeholder, #code::placeholder, .card input::placeholder { color: var(--secondary); }
        #searchcancel { color: var(--lilac); padding: 0 8px; }
        #jumpnew { position: absolute; left: 50%; top: calc(100% + 8px); transform: translateX(-50%); white-space: nowrap; padding: 0 16px;
          color: var(--lilac); background: var(--glass); box-shadow: inset 0 0 0 1px var(--glass-edge), 0 4px 16px rgba(0, 0, 0, .5);
          border-radius: 999px; font-size: calc(15em / 17); font-weight: 600; }
        #banner { color: var(--error-text); background: var(--error-surface); font-size: calc(15em / 17);
          margin: 0 calc(-8px - env(safe-area-inset-right)) 0 calc(-8px - env(safe-area-inset-left));
          padding: 10px calc(env(safe-area-inset-right) + 16px) 10px calc(env(safe-area-inset-left) + 16px); }
        #banner:empty { padding: 0; }

        #head { display: flex; align-items: center; gap: 12px; padding: 2px calc(env(safe-area-inset-right) + 16px) 10px calc(env(safe-area-inset-left) + 16px); }
        #names { flex: 1; min-width: 0; }
        #title { margin: 0; color: var(--white); font-size: calc(32em / 17); font-weight: 700; line-height: 1.15; overflow-wrap: anywhere; }
        #subtitle { margin: 2px 0 0; color: var(--secondary); font-size: calc(15em / 17); }
        #subtitle:empty { display: none; }
        #link, #t3, #backlog { display: block; color: var(--lilac); font-size: calc(15em / 17); text-align: left; margin: -8px 0 -12px; }

        .card, .lit { --light: var(--shades); position: relative;
          background: radial-gradient(70% 64.8% at 50% 108.64%, color-mix(in srgb, var(--rim, var(--light)) 30%, transparent), transparent 72%),
            linear-gradient(var(--card-top), var(--card-bottom));
          box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .07); }
        .card::after, .lit::after { content: ''; position: absolute; inset: 0; border-radius: inherit; padding: 1.2px; pointer-events: none;
          background: linear-gradient(transparent 58%, color-mix(in srgb, var(--rim, var(--light)) 55%, transparent) 82%, var(--rim, var(--light)));
          -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0); -webkit-mask-composite: xor; mask-composite: exclude; }
        .tile { --light: var(--shades); position: relative; flex: none; width: 40px; height: 40px; border-radius: 22.5%; display: grid; place-items: center;
          color: var(--white);
          background: radial-gradient(100% 60% at 50% 100%, color-mix(in srgb, var(--light) 45%, transparent), transparent),
            linear-gradient(var(--card-top-solid), var(--card-bottom-solid)); }
        .tile::after { content: ''; position: absolute; inset: 0; border-radius: inherit; padding: 1.5px; pointer-events: none;
          background: linear-gradient(rgba(255, 255, 255, .22), transparent 40%, transparent 60%, var(--light));
          -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0); -webkit-mask-composite: xor; mask-composite: exclude; }

        #notify { display: flex; align-items: center; gap: 12px; padding: 14px 16px; border-radius: 18px;
          margin: 8px calc(env(safe-area-inset-right) + 16px) 12px calc(env(safe-area-inset-left) + 16px); }
        #notifytext { flex: 1; margin: 0; color: var(--body); font-size: calc(15em / 17); }

        main { flex: 1; padding: 4px calc(env(safe-area-inset-right) + 16px) 24px calc(env(safe-area-inset-left) + 16px); }
        .group, .section span { color: var(--label); font-size: calc(12em / 17); font-weight: 500; letter-spacing: .09em; text-transform: uppercase; }
        .group { margin: 24px 0 6px; }
        .place { display: flex; align-items: center; gap: 12px; width: calc(100% + 16px); margin: 0 -8px; padding: 6px 8px; border-radius: 14px; text-align: left; }
        .place:active, .issue:active, .hit:active, .digest:active, .replybar:active { background: var(--raised); }
        .place .name { flex: 1; color: var(--body); }
        .place.unread .name { color: var(--white); font-weight: 600; }
        .count { background: var(--error); color: var(--page); border-radius: 999px; padding: 1px 8px; font-size: calc(13em / 17); font-weight: 700; font-variant-numeric: tabular-nums; }
        .unreadcount { color: var(--secondary); font-size: calc(13em / 17); font-variant-numeric: tabular-nums; }
        .dot { width: 8px; height: 8px; flex: none; background: var(--secondary); }
        .cat { width: 32px; height: 32px; flex: none; image-rendering: -webkit-optimize-contrast; image-rendering: pixelated; }
        .cat.small { width: 16px; height: 16px; }
        .face { width: 16px; height: 16px; flex: none; border-radius: 4px; background: var(--selected); box-shadow: inset 0 0 0 1px var(--dim); }
        .you { width: 32px; height: 32px; flex: none; border-radius: 50%; object-fit: cover; box-shadow: 0 0 0 .5px var(--border); }
        .you.small { width: 16px; height: 16px; }

        .day { text-align: center; color: var(--secondary); font-size: calc(13em / 17); font-weight: 600; margin: 20px 0 6px; }
        .msg { margin: 6px 0; display: flex; flex-direction: column; align-items: flex-start; }
        .msg.mine { align-items: flex-end; }
        .msg.withcat { padding-left: 40px; }
        .said { display: flex; align-items: flex-end; gap: 8px; align-self: stretch; }
        .msg.mine .said { justify-content: flex-end; }
        .said .cat { margin-left: -40px; }
        .msg.withyou { padding-right: 40px; }
        .said .you { margin-right: -40px; }
        .meta { color: var(--secondary); font-size: calc(13em / 17); margin: 4px 12px 3px; }
        .bubble { position: relative; max-width: 86%; padding: 9px 14px; border-radius: 18px; color: var(--body);
          white-space: pre-wrap; overflow-wrap: anywhere; }
        .mine .bubble { --under: var(--fill, var(--selected)); background: var(--under); }
        .mine .bubble.faded { --under: color-mix(in srgb, var(--fill, var(--selected)) 55%, var(--page)); color: var(--secondary); }
        .bubble.lit { --under: var(--card-bottom-solid); }
        .bubble.lit.faded { --rim: color-mix(in srgb, var(--light) 55%, transparent); color: var(--secondary); }
        .msg.landed .bubble { outline: 2px solid var(--violet); outline-offset: 2px; }
        .bubble code { font: .9em ui-monospace, Menlo, monospace; }
        .bubble a, .bubble .link { color: var(--lilac); }
        .bubble .link { text-decoration: underline; text-decoration-color: color-mix(in srgb, var(--lilac) 50%, transparent); cursor: pointer; }
        .bubble p, .bubble h4, .bubble blockquote { margin: 0; }
        .bubble > * + * { margin-top: .5em; }
        .bubble > .item + .item { margin-top: .15em; }
        .bubble h4 { font-size: 1em; color: var(--white); }
        .bubble strong { color: var(--white); }
        .bubble blockquote { padding-left: 10px; border-left: 3px solid var(--field-edge); }
        .bubble .item { display: flex; gap: .4em; }
        .bubble .marker { flex: none; min-width: .8em; }
        .bubble .code { border-radius: 10px; background: rgba(255, 255, 255, .06); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .06); }
        .bubble pre { margin: 0; padding: 8px 10px; font: calc(14em / 17)/1.4 ui-monospace, Menlo, monospace; white-space: pre; overflow-x: auto; }
        .bubble .copy { position: relative; display: block; margin: -8px 0 -18px auto; padding: 0 10px; color: var(--lilac); font-size: calc(13em / 17); }
        .bubble .table { overflow-x: auto; }
        .bubble table { border-collapse: collapse; font-size: calc(15em / 17); white-space: normal; }
        .bubble th, .bubble td { overflow-wrap: normal; border: 1px solid var(--field-edge); padding: 3px 8px; text-align: left; vertical-align: top; }
        .bubble th { color: var(--white); background: rgba(255, 255, 255, .04); }
        .bubble hr { border: 0; border-top: 1px solid var(--field-edge); margin: .6em 0; }
        .chip { display: inline-block; border-radius: 999px; padding: 0 8px; font-size: calc(14em / 17); font-weight: 600; color: var(--body);
          background: var(--control); box-shadow: inset 0 0 0 1px var(--field-edge); white-space: nowrap; }
        .chip[data-state=open] { color: var(--good); }
        .chip[data-state=merged] { color: var(--lilac); }
        .chip[data-state=closed] { color: var(--error-text); }
        .bubble.cut { max-height: calc(40.5em + 18px); overflow: hidden; }
        .bubble.cut::before { content: ''; position: absolute; left: 0; right: 0; bottom: 0; height: 4em; pointer-events: none;
          background: linear-gradient(transparent, var(--under)); }
        .more { color: var(--secondary); font-size: calc(14em / 17); margin: -8px 12px -12px; }
        .failure { color: var(--error-text); font-size: calc(13em / 17); margin: 3px 12px 0; }
        .retry { color: var(--lilac); font-size: calc(14em / 17); font-weight: 600; margin: -8px 12px -12px; }
        .open, .react { color: var(--lilac); font-size: calc(14em / 17); font-weight: 600; margin: -8px 12px -12px; }
        .open:not(:focus), .react:not(:focus) { position: absolute; width: 1px; min-width: 0; height: 1px; min-height: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
        .reactions { display: flex; flex-wrap: wrap; gap: 4px; margin: 4px 8px 0; }
        .reactions button { position: relative; min-height: 32px; background: var(--control); box-shadow: inset 0 0 0 1px var(--field-edge);
          border-radius: 999px; padding: 0 10px; font-size: calc(15em / 17); }
        .reactions button::after { content: ''; position: absolute; inset: -6px 0; }
        .context { color: var(--secondary); font-size: calc(13em / 17); margin: 0 12px -6px; text-align: left; }
        .replybar { display: flex; flex-wrap: wrap; align-items: center; gap: 2px 6px; margin: 0 6px -4px; padding: 4px 8px; border-radius: 10px; font-size: calc(13em / 17);
          white-space: nowrap; text-align: left; }
        .replybar b { color: var(--lilac); }
        .replybar .waiting { color: var(--error-text); font-weight: 600; }
        .replybar .unread { width: 8px; height: 8px; flex: none; border-radius: 50%; background: var(--violet); }
        .replybar span { color: var(--secondary); }
        .replies { display: flex; align-items: center; gap: 10px; color: var(--secondary); font-size: calc(13em / 17); margin: 14px 4px 4px; }
        .replies::after { content: ''; flex: 1; border-top: 1px solid var(--border); }
        .new { display: flex; align-items: center; gap: 10px; color: var(--error-text); font-size: calc(13em / 17); font-weight: 600; margin: 14px 4px 4px; }
        .new::before { content: ''; flex: 1; height: 1px; background: var(--rim-line); }
        .digest { display: block; width: 100%; text-align: left; padding: 12px 8px; border-bottom: 1px solid var(--border); }
        .digest h3 { margin: 0 0 6px; color: var(--white); font-size: calc(15em / 17); font-weight: 600; }
        .digest.unread h3::before { content: ''; display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: var(--violet); margin-right: 6px; }
        .digest p { margin: 2px 0 6px; overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
        .digest small { color: var(--secondary); font-size: calc(13em / 17); }
        .digest .who { display: flex; align-items: center; gap: 6px; }
        .digest .more { color: var(--lilac); font-weight: 600; margin: 0; }
        #alsolabel { display: flex; align-items: center; gap: 8px; min-height: 44px; color: var(--secondary); font-size: calc(14em / 17); margin: 0 4px -8px; }
        #also { accent-color: var(--violet); width: 18px; height: 18px; margin: 0; }
        .section { display: flex; justify-content: space-between; align-items: baseline; margin: 24px 0 6px; }
        .section button { color: var(--lilac); font-size: calc(15em / 17); margin: -12px 0; }
        .heading { display: flex; align-items: center; gap: 12px; margin: 18px 0 4px; }
        .heading b { color: var(--white); font-weight: 600; }
        .heading p { margin: 0; color: var(--secondary); font-size: calc(14em / 17); }
        .issue { display: block; width: 100%; text-align: left; padding: 8px 4px 8px 52px; border-radius: 12px; }
        .issue .line { display: flex; align-items: center; gap: 8px; color: var(--body); }
        .issue small { display: block; color: var(--secondary); font-size: calc(14em / 17); margin-left: 16px; }
        .note { color: var(--secondary); text-align: center; font-size: calc(15em / 17); margin: 28px 16px; }
        .backlog { padding: 10px 4px; }
        .backlog p { margin: 0; color: var(--white); overflow-wrap: anywhere; }
        .backlog small { display: block; margin-top: 3px; color: var(--secondary); font-size: calc(14em / 17); overflow-wrap: anywhere; }
        .older { display: block; width: calc(100% - 32px); color: var(--lilac); background: none; border: 0; font: inherit; margin-block: 12px; }
        .older:disabled { color: var(--secondary); }
        .hit { display: block; width: 100%; text-align: left; padding: 12px 8px; border-bottom: 1px solid var(--border); }
        .hit small { color: var(--secondary); font-size: calc(13em / 17); }
        .hit p { margin: 4px 0 0; color: var(--body); overflow-wrap: anywhere; }
        .hit b { color: var(--white); }

        .card { border-radius: 18px; padding: 14px 16px 16px; margin: 10px 0; }
        .card header { display: flex; align-items: center; gap: 10px; color: var(--secondary); font-size: calc(13em / 17); }
        .card header .title { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--white); font-weight: 600; font-size: calc(15em / 13); }
        .card .text { margin: 10px 0 0; white-space: pre-wrap; overflow-wrap: anywhere; color: var(--body); }
        .card.approval .text { font: calc(14em / 17)/1.4 ui-monospace, Menlo, monospace; }
        .card .answer { margin: 8px 0 0; padding-left: 10px; border-left: 3px solid var(--field-edge); white-space: pre-wrap; overflow-wrap: anywhere; }
        .card .footer { margin: 8px 0 0; color: var(--secondary); font-size: calc(13em / 17); }
        .card .part { margin: 14px 0 0; }
        .card header + .part { margin: 0; }
        .buttons { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 14px; }
        .buttons button { color: var(--body); background: var(--control); box-shadow: inset 0 0 0 1px var(--field-edge); border-radius: 999px; padding: 0 18px; font-size: calc(15em / 17); }
        .buttons button:active { background: var(--control-hover); }
        .buttons button.picked { color: var(--white); background: var(--selected); box-shadow: inset 0 0 0 1.5px var(--violet); }
        .buttons button.go, .buttons a.go, #notifybutton, #pairform button { color: var(--white); background: var(--primary); box-shadow: none;
          border-radius: 999px; padding: 0 18px; font-size: calc(15em / 17); font-weight: 600; }
        .buttons button.go:active, .buttons a.go:active, #notifybutton:active, #pairform button:active { background: var(--primary-pressed); }
        .buttons button:disabled, #send:disabled .disc { opacity: .4; }
        .card input, #pairform input { width: 100%; font: inherit; font-size: max(16px, 1em); color: var(--white); caret-color: var(--lilac); background: var(--raised);
          border: 1px solid var(--field-edge); border-radius: 12px; padding: 8px 12px; min-height: 44px; margin-top: 8px; }

        #box { position: sticky; bottom: var(--below, 0px); background: var(--glass); box-shadow: 0 -1px var(--glass-edge); -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px);
          padding: 8px calc(env(safe-area-inset-right) + 12px) calc(env(safe-area-inset-bottom) + 8px) calc(env(safe-area-inset-left) + 8px); }
        #label { display: block; color: var(--secondary); font-size: calc(13em / 17); margin: 0 4px 6px 8px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .field { display: flex; align-items: flex-end; gap: 4px; }
        #attach { color: var(--body); }
        .entry { flex: 1; min-width: 0; display: flex; align-items: flex-end; background: var(--raised); box-shadow: inset 0 0 0 1px var(--field-edge); border-radius: 22px; }
        #words { flex: 1; min-width: 0; resize: none; font: inherit; font-size: max(16px, 1em); color: var(--white); caret-color: var(--lilac); background: none; border: 0;
          outline: none; padding: 11px 4px 11px 15px; min-height: 44px; max-height: 40vh; }
        #words::placeholder { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        #send { display: grid; place-items: center; }
        #send .disc { display: grid; place-items: center; width: 30px; height: 30px; border-radius: 50%; color: var(--white); background: var(--primary); }
        #send .symbol { width: 18px; height: 18px; stroke-width: 2.4; }
        #attached { display: flex; flex-wrap: wrap; gap: 6px; margin: 0 0 8px 8px; }
        .attachment { display: flex; align-items: center; gap: 8px; padding: 2px 0 2px 8px; border-radius: 12px; background: var(--raised); box-shadow: inset 0 0 0 1px var(--field-edge); max-width: 100%; min-width: 0; }
        .attachment img { width: 36px; height: 36px; border-radius: 8px; object-fit: cover; flex: none; }
        .attachment span { font-size: calc(14em / 17); white-space: nowrap; }
        .attachment .name { overflow: hidden; text-overflow: ellipsis; min-width: 0; max-width: 40vw; }
        .attachment .state { flex: none; }
        .attachment button { color: var(--secondary); }
        .attachment.going img { filter: brightness(.55); }
        .attachment.going span { color: var(--secondary); }
        .pictures { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 4px; max-width: 86%; }
        .mine .pictures { margin-left: auto; justify-content: flex-end; }
        .picture { max-width: 66%; max-height: 240px; border-radius: 14px; display: block; }
        .pictures.several .picture { width: 31%; max-width: 120px; height: 96px; object-fit: cover; }
        .web { color: var(--body); text-align: left; }
        .file { display: flex; align-items: center; gap: 8px; margin-top: 4px; padding: 8px 12px; border-radius: 12px; color: var(--body);
          background: var(--raised); box-shadow: inset 0 0 0 1px var(--field-edge); font-size: calc(14em / 17); max-width: 86%; overflow-wrap: anywhere; }

        /* Outside the repo: a closed dialog is hidden only by the browser's own rule, which a display set here would override. */
        .sheet[open] { position: fixed; margin: 0; width: auto; max-width: none; display: flex; flex-direction: column;
          inset: auto calc(env(safe-area-inset-right) + 8px) calc(env(safe-area-inset-bottom) + 8px) calc(env(safe-area-inset-left) + 8px);
          max-height: calc(100dvh - env(safe-area-inset-top) - env(safe-area-inset-bottom) - 24px);
          color: var(--body); background: var(--glass); border: 0; box-shadow: inset 0 0 0 1px var(--glass-edge), 0 12px 40px rgba(0, 0, 0, .6);
          border-radius: 24px; padding: 18px 18px 16px; }
        dialog::backdrop { background: rgba(0, 0, 0, .55); }
        #linktitle { margin: 0; color: var(--white); font-size: calc(15em / 17); font-weight: 600; overflow-wrap: anywhere; }
        #linkaddress { margin: 8px 0 0; color: var(--body); font: calc(14em / 17)/1.4 ui-monospace, Menlo, monospace; overflow-wrap: anywhere; overflow-y: auto; min-height: 0; }
        #linksheet .buttons { justify-content: flex-end; }
        #linksheet .buttons .go { display: inline-flex; align-items: center; min-height: 44px; text-decoration: none; }
        #marks { display: flex; justify-content: space-between; }
        #marks button { font-size: calc(26em / 17); min-width: 50px; min-height: 50px; border-radius: 999px; }
        #marks button:active { background: var(--control); }
        #marks button.on { background: var(--selected); box-shadow: inset 0 0 0 1.5px var(--violet); }

        #pair { padding: calc(env(safe-area-inset-top) + 56px) calc(env(safe-area-inset-right) + 20px) 24px calc(env(safe-area-inset-left) + 20px); }
        #pair h1 { color: var(--white); font-size: calc(32em / 17); font-weight: 700; line-height: 1.15; margin: 0 0 10px; }
        #pair p { color: var(--secondary); }
        #pairnote { color: var(--error-text) !important; }
        #pairform { display: flex; gap: 8px; align-items: center; }
        #pairform input { margin: 0; font-size: calc(22em / 17); letter-spacing: .1em; text-transform: uppercase; }

        """

    static let colors: String = {
        let hex = Opal.hex
        let rgba = { (color: UInt32, alpha: CGFloat) in
            "rgba(\(color >> 16 & 0xff), \(color >> 8 & 0xff), \(color & 0xff), \(alpha))"
        }
        return """

            :root { color-scheme: dark;
              --page: #000000; --white: #ffffff; --body: rgba(255, 255, 255, 0.8); --secondary: rgba(255, 255, 255, 0.62); --label: rgba(255, 255, 255, 0.62);
              --dim: \(hex(Opal.dim)); --raised: \(hex(Opal.raised)); --control: \(hex(Opal.control)); --control-hover: \(hex(Opal.controlHover));
              --selected: \(hex(Opal.selected)); --border: \(hex(Opal.border)); --field-edge: \(hex(Opal.fieldEdge));
              --violet: \(hex(Opal.violet)); --primary: \(hex(Opal.primary)); --primary-pressed: \(hex(Opal.primaryPressed)); --lilac: \(hex(Opal.lilac));
              --good: \(hex(Opal.good)); --error: \(hex(Opal.error)); --error-text: \(hex(Opal.errorText)); --error-surface: \(hex(Opal.errorSurface));
              --glass: \(rgba(Opal.raised, 0.94)); --glass-edge: rgba(255, 255, 255, 0.08);
              --card-top: \(rgba(Opal.cardTop, Opal.cardTopAlpha)); --card-bottom: \(rgba(Opal.cardBottom, Opal.cardBottomAlpha));
              --card-top-solid: \(hex(Opal.cardTop)); --card-bottom-solid: \(hex(Opal.cardBottom));
              --shades: \(hex(Opal.hue(Opal.shadesHue, lightness: 0.68)));
              --rim-line: linear-gradient(90deg, \(hex(Opal.rimCyan)), \(hex(Opal.rimViolet)), \(hex(Opal.rimPink))); }

            """
    }()

    static func size(_ size: TextSize) -> String {
        guard size != .standard else { return "" }
        return "\n:root { --size: calc(100% * \(Int(MessagesInk.body(at: size))) / \(Int(MessagesInk.body(at: .standard)))); }\n"
    }

    static let script = #"""
        'use strict';
        const $ = (id) => document.getElementById(id);
        const conversation = (key) => /^(c|t|r):/.test(key);
        const words = {
          unreachable: "Can't reach your Mac. The Kitty Litter has to be running, and your Mac awake.",
          gone: "That's changed since. Have another look.",
          wrongCode: "That code didn't work. Turn pairing on again in The Kitty Litter on your Mac for a new one.",
          pairHomeScreen: "Turn on The Kitty Litter on my phone in Settings on your Mac, and it shows a code. Type it here, since scanning it opens Safari rather than this app.",
          stillPaired: "That code didn't work, but this phone is still paired.",
          answer: 'Send answer', openInT3: 'Open in T3', more: 'Show more', less: 'Show less', done: 'Done', clear: 'Clear', copy: 'Copy', copied: 'Copied', react: 'React', openThread: 'Open thread',
          waiting: (count) => count + ' waiting', unread: (count) => count + ' unread',
          openLink: (host) => 'Open a link to ' + host + '?',
          showPicture: (host) => 'Show a picture from ' + host + '?', pictureFrom: (host) => '🖼 Picture from ' + host,
          couldntShow: "Couldn't show it.", tooMany: 'One message takes up to 10 files.',
          several: 'Pick as many as you like.',
          sending: 'Sending…', retry: 'Try again',
          notifyAsk: 'Get a notification when something needs you.',
          notifyRefused: "Notifications didn't turn on, since your Mac couldn't use this phone's push service.",
          cantRead: 'The Kitty Litter can only read photos and PDFs.',
          tooBig: "That's too big to send. Try something under 10 MB.",
          homeScreen: 'For notifications on an iPhone, add this page to your Home Screen with Share, then pair it there.',
          searchHint: 'Type a word or two from the message.',
          searchNothing: 'No messages with those words.',
          searchMore: (count) => 'The newest ' + count + '. Add a word to narrow it down.',
        };

        let key = new URLSearchParams(location.search).get('key') || 'home';
        let pass = localStorage.getItem('shades.key');
        let stream = null;
        let received = null;
        let heard = 0;
        const page = Math.random().toString(36).slice(2);
        let view = null;
        let retry = null;
        let keptUnread = null;
        let jumped = false;
        let atFoot = false;
        let footY = 0;
        const expanded = new Set();
        const answers = new Map();
        let landing = null;

        function el(tag, className, text) {
          const node = document.createElement(tag);
          if (className) node.className = className;
          if (text != null) node.textContent = text;
          return node;
        }

        function banner(text) {
          if ($('banner').textContent !== (text || '')) $('banner').textContent = text || '';
        }

        function reached() {
          if ($('banner').textContent === words.unreachable) banner('');
        }

        function headers(extra) {
          return Object.assign({ Authorization: 'Bearer ' + pass }, extra);
        }

        async function post(path, body) {
          try {
            return await fetch(path, {
              method: 'POST', cache: 'no-store',
              headers: headers({ 'Content-Type': 'application/json', 'X-Shades': '1' }),
              body: JSON.stringify(body),
            });
          } catch (error) {
            return null;
          }
        }

        let began = 0;
        let shownAt = 0;
        const waiting = [];
        async function request(path, body) {
          const sent = Date.now();
          const response = await post(path, body);
          if (!response || response.status !== 503) return response;
          if (shownAt < sent) {
            const shown = new Promise((resolve) => { waiting.push(resolve); setTimeout(resolve, 10000); });
            if (began < sent) listen();
            await shown;
          }
          return post(path, body);
        }

        async function act(body, quiet) {
          const asked = Date.now();
          const holding = pass;
          const response = await request('/act', body);
          if (response && response.ok) {
            if (quiet) reached(); else banner('');
            if (!quiet) setTimeout(() => { if (stream && heard < asked) listen(); }, 3000);
            return response.json();
          }
          if (response && response.status === 401) { refused(holding); return null; }
          if (!quiet) banner(response && response.status === 409 ? words.gone : words.unreachable);
          return null;
        }

        async function start() {
          clearTimeout(retry);
          const code = new URLSearchParams(location.hash.slice(1)).get('pair');
          if (code) {
            history.replaceState(history.state, '', location.pathname + location.search);
            if (!(await pair(code)) && !pass) return;
          }
          if (!pass) return pairing();
          let hello = null;
          const holding = pass;
          try { hello = await fetch('/hello', { headers: headers(), cache: 'no-store' }); } catch (error) {}
          if (hello && hello.status === 401) {
            if (!refused(holding)) return;
            if (code) $('pairnote').textContent = words.wrongCode;
            return;
          }
          $('pair').hidden = true;
          $('top').hidden = false;
          if (!hello || !hello.ok) { banner(words.unreachable); retry = setTimeout(start, 5000); return; }
          for (const id of ['head', 'rows', 'find']) $(id).hidden = false;
          listen();
          notifications().catch(() => {});
        }

        let pushKey = null;
        async function notifications() {
          if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
            return offer(words.homeScreen, false);
          }
          const registration = await navigator.serviceWorker.register('/sw.js');
          for (const shown of await registration.getNotifications()) shown.close();
          if (Notification.permission === 'denied') return offer(null);
          const response = await fetch('/push', { headers: headers(), cache: 'no-store' });
          if (!response.ok) return offer(null);
          pushKey = (await response.json()).key;
          let subscription = await registration.pushManager.getSubscription();
          if (subscription && encode(subscription.options.applicationServerKey) !== pushKey) {
            await subscription.unsubscribe();
            subscription = null;
          }
          if (subscription && Notification.permission === 'granted') {
            const kept = await keep(subscription);
            if (!kept || kept.ok) return offer(null);
          }
          offer(words.notifyAsk, true);
        }

        function offer(text, asks) {
          $('notifytext').textContent = text || '';
          $('notifybutton').hidden = !asks;
          $('notify').hidden = !text || key !== 'home';
        }

        $('notifybutton').onclick = async () => {
          $('notifybutton').disabled = true;
          try {
            if (await Notification.requestPermission() !== 'granted') return offer(null);
            const registration = await navigator.serviceWorker.ready;
            const subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: decode(pushKey) });
            const kept = await keep(subscription);
            if (!kept || !kept.ok) return banner(kept ? words.notifyRefused : words.unreachable);
            offer(null);
          } catch (error) {
            banner(words.unreachable);
          } finally {
            $('notifybutton').disabled = false;
          }
        };

        function keep(subscription) {
          const json = subscription.toJSON();
          return post('/push', { endpoint: json.endpoint, p256dh: json.keys.p256dh, auth: json.keys.auth });
        }

        function encode(buffer) {
          return btoa(String.fromCharCode(...new Uint8Array(buffer))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
        }

        function decode(text) {
          const base64 = text.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((text.length + 3) % 4);
          return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
        }

        function refused(holding) {
          if (holding !== pass) return false;
          pairing();
          return true;
        }

        function pairing() {
          if (stream) stream.abort();
          stream = null;
          pass = null;
          localStorage.removeItem('shades.key');
          $('found').replaceChildren();
          $('bar').hidden = false;
          banner('');
          for (const id of ['top', 'head', 'rows', 'box', 'search', 'found']) $(id).hidden = true;
          if (navigator.standalone || matchMedia('(display-mode: standalone)').matches) $('pairhow').textContent = words.pairHomeScreen;
          $('pair').hidden = false;
        }

        async function pair(code) {
          const response = await post('/pair', { code });
          if (response && response.ok) {
            pass = (await response.json()).key;
            localStorage.setItem('shades.key', pass);
            $('pairnote').textContent = '';
            return true;
          }
          if (pass) {
            banner(response ? words.stillPaired : words.unreachable);
            return false;
          }
          pairing();
          $('pairnote').textContent = response ? words.wrongCode : words.unreachable;
          return false;
        }

        // Outside the repo: EventSource can't send headers.
        async function listen() {
          if (stream) stream.abort();
          const mine = new AbortController();
          stream = mine;
          received = null;
          heard = began = Date.now();
          const holding = pass;
          try {
            const response = await fetch('/events?key=' + encodeURIComponent(key) + '&page=' + page, { headers: headers(), cache: 'no-store', signal: mine.signal });
            if (response.status === 401) return refused(holding);
            if (!response.ok || !response.body) throw new Error(String(response.status));
            const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
            let buffer = '';
            for (;;) {
              const { value, done } = await reader.read();
              if (done) break;
              heard = Date.now();
              buffer += value;
              let end;
              while ((end = buffer.indexOf('\n\n')) >= 0) {
                const event = buffer.slice(0, end);
                buffer = buffer.slice(end + 2);
                for (const line of event.split('\n')) {
                  if (line.startsWith('data: ')) { reached(); show(whole(JSON.parse(line.slice(6)))); shownAt = Date.now(); waiting.splice(0).forEach((resolve) => resolve()); }
                }
              }
            }
          } catch (error) {}
          if (mine.signal.aborted || stream !== mine) return;
          stream = null;
          banner(words.unreachable);
          retry = setTimeout(start, 3000);
        }

        // Outside the repo: after the lock screen, another app or a new network, an iPhone can leave a stream open that never says anything again, and nothing tells the page.
        setInterval(() => { if (stream && Date.now() - heard > 25000) listen(); }, 5000);
        function revive(quiet) { if (stream && Date.now() - heard > quiet) listen(); }
        window.addEventListener('pageshow', (event) => { if (event.persisted) revive(0); });
        window.addEventListener('online', () => revive(0));

        function whole(next) {
          const before = new Map((received ? received.rows : []).map((row) => [row.id, row]));
          next.rows = next.rows.map((row) => (row.kind === 'same' ? before.get(row.id) : row));
          received = next;
          return next;
        }

        function go(next, push = true) {
          if (!next || next === key) return;
          if (!$('search').hidden) searching(false);
          key = next;
          banner('');
          for (const id of ['back', 'headcat', 'link', 't3', 'backlog', 'unread', 'read']) $(id).hidden = true;
          for (const id of ['title', 'subtitle', 'bartitle']) $(id).textContent = '';
          keptUnread = null;
          jumped = false;
          view = null;
          if (push) history.pushState({ key }, '', '?key=' + encodeURIComponent(key));
          $('rows').replaceChildren();
          listen();
        }

        window.addEventListener('popstate', (event) => go((event.state && event.state.key) || 'home', false));

        let held = null;
        function selecting() {
          const selection = document.getSelection();
          return Boolean(selection && !selection.isCollapsed && $('rows').contains(selection.anchorNode));
        }
        document.addEventListener('selectionchange', () => {
          if (!held || selecting()) return;
          const next = held;
          held = null;
          show(next);
        });

        function lowestInSight() {
          const seen = [...$('rows').children].filter(child => {
            const box = child.getBoundingClientRect();
            return child.dataset.id && box.bottom > 0 && box.top < window.innerHeight;
          }).pop();
          return seen ? { id: seen.dataset.id, top: seen.getBoundingClientRect().top } : null;
        }

        let drawn = new WeakMap();
        function place(nodes) {
          const rows = $('rows');
          let at = rows.firstChild;
          for (const node of nodes) {
            if (node === at) { at = at.nextSibling; continue; }
            rows.insertBefore(node, at);
          }
          while (at) { const next = at.nextSibling; at.remove(); at = next; }
        }

        function show(next) {
          if (view && view.key === next.key && selecting()) { held = next; return; }
          held = null;
          const fresh = !view || view.key !== next.key;
          const before = view;
          const nearBottom = !jumped && window.innerHeight + window.scrollY >= document.body.scrollHeight - 60;
          if (next.key !== key) {
            key = next.key;
            history.replaceState({ key }, '', '?key=' + encodeURIComponent(key));
          }
          view = next;
          $('title').textContent = next.title;
          $('bartitle').textContent = next.title;
          $('subtitle').textContent = next.subtitle || '';
          $('headcat').replaceChildren(...(next.cat ? [cat(next.cat)] : []));
          lit($('headcat'), next.cat);
          $('headcat').hidden = !next.cat;
          $('link').hidden = !next.link;
          $('link').textContent = next.link ? next.link.label : '';
          $('t3').hidden = !next.t3;
          $('backlog').hidden = !next.backlog;
          $('backlog').textContent = next.backlog ? next.backlog.label : '';
          $('back').hidden = !next.back;
          $('backtitle').textContent = next.back ? next.backTitle : '';
          $('unread').hidden = !next.unread;
          $('read').hidden = !(next.places.find((place) => place.key === next.key) || {}).unread;
          $('box').hidden = !next.box || !$('search').hidden;
          if (fresh || !next.box || !next.box.files) unattach();
          if (next.box) {
            $('label').textContent = next.box.label;
            $('words').placeholder = next.box.placeholder;
            sendable();
            $('attach').hidden = !next.box.files;
            $('alsolabel').hidden = !next.box.also;
            $('alsotext').textContent = next.box.also || '';
            if (fresh) $('also').checked = false;
          }
          const kept = fresh || nearBottom || !conversation(key) ? null : lowestInSight();
          if (fresh || !before || before.you !== next.you) drawn = new WeakMap();
          place(key === 'home' ? places(next.places) : next.rows.map(item => {
            let node = drawn.get(item);
            if (!node) {
              node = row(item);
              if (item.id) node.dataset.id = item.id;
              drawn.set(item, node);
            }
            return node;
          }));
          cutLong();
          $('notify').hidden = key !== 'home' || !$('notifytext').textContent;
          if (conversation(key) && (fresh || nearBottom)) window.scrollTo(0, document.body.scrollHeight);
          else if (fresh) window.scrollTo(0, 0);
          else if (kept) {
            const node = [...$('rows').children].find(child => child.dataset.id === kept.id);
            if (node) window.scrollBy(0, node.getBoundingClientRect().top - kept.top);
          }
          foot();
          if (landing && landing.key !== next.key) landing = null;
          const landed = landing && [...$('rows').children].find(child => child.dataset.id === landing.id);
          if (landed) {
            landing = null;
            landed.scrollIntoView({ block: 'center' });
            landed.classList.add('landed');
            setTimeout(() => landed.classList.remove('landed'), 2500);
          }
          showJump();
          collapse();
          seen();
        }

        function cutLong() {
          const fresh = [...$('rows').querySelectorAll('.msg > .said > .bubble:not(.measured)')];
          fresh.forEach((bubble) => bubble.classList.add('measured'));
          const long = fresh.filter((bubble) => bubble.scrollHeight > 40 * parseFloat(getComputedStyle(bubble).lineHeight));
          for (const bubble of long) {
            const id = bubble.closest('.msg').dataset.id;
            const open = expanded.has(id);
            bubble.classList.toggle('cut', !open);
            const more = el('button', 'more', open ? words.less : words.more);
            more.type = 'button';
            more.onclick = () => {
              if (expanded.has(id)) expanded.delete(id); else expanded.add(id);
              const cut = bubble.classList.toggle('cut');
              more.textContent = cut ? words.more : words.less;
            };
            bubble.parentNode.after(more);
          }
        }

        function seen() {
          if (view && conversation(key) && $('search').hidden && document.visibilityState === 'visible' && keptUnread !== key) act({ act: 'seen', key }, true);
        }

        function showJump() {
          const line = $('rows').querySelector('.new');
          $('jumpnew').hidden = !line || line.getBoundingClientRect().bottom > $('top').getBoundingClientRect().bottom;
          $('jumpnew').textContent = line ? line.dataset.jump : '';
        }

        function foot() {
          const bottom = window.innerHeight + window.scrollY >= document.body.scrollHeight - 60;
          if (bottom || window.scrollY < footY) atFoot = bottom && conversation(key);
          footY = window.scrollY;
        }

        function settle() {
          if (atFoot && !jumped && $('search').hidden) window.scrollTo(0, document.body.scrollHeight);
        }

        function collapse() {
          $('top').classList.toggle('collapsed', $('head').hidden || $('title').getBoundingClientRect().top < $('bar').getBoundingClientRect().bottom);
        }
        // Outside the repo: with the keyboard up, Safari on iPhone slides the visual viewport down the page instead of making the page shorter.
        function followKeyboard() {
          const seen = window.visualViewport;
          const zoomed = seen.scale > 1.01;
          const above = zoomed ? 0 : Math.max(0, seen.offsetTop);
          const below = zoomed ? 0 : Math.max(0, document.documentElement.clientHeight - seen.height - seen.offsetTop);
          document.documentElement.style.setProperty('--above', above + 'px');
          document.documentElement.style.setProperty('--below', below + 'px');
        }
        if (window.visualViewport) {
          visualViewport.addEventListener('resize', followKeyboard);
          visualViewport.addEventListener('scroll', followKeyboard);
        }
        window.addEventListener('scroll', () => {
          if (window.innerHeight + window.scrollY >= document.body.scrollHeight - 2) jumped = false;
          foot();
          showJump();
          collapse();
        }, { passive: true });
        $('jumpnew').onclick = () => {
          const line = $('rows').querySelector('.new');
          if (!line) return;
          jumped = true;
          window.scrollBy(0, line.getBoundingClientRect().top - $('top').getBoundingClientRect().bottom - 8);
        };
        $('read').onclick = () => act({ act: 'read', key });
        $('unread').onclick = () => {
          if (!view || !view.unread) return;
          keptUnread = key;
          act({ act: 'unread', key, id: view.unread });
        };

        let finding = null;
        function searching(open) {
          for (const id of ['search', 'found']) $(id).hidden = !open;
          for (const id of ['bar', 'head', 'rows']) $(id).hidden = open;
          $('box').hidden = open || !(view && view.box);
          clearTimeout(finding);
          $('query').value = '';
          $('found').replaceChildren(el('p', 'note', words.searchHint));
          if (open) { window.scrollTo(0, 0); $('query').focus(); }
          else window.scrollTo(0, conversation(key) ? document.body.scrollHeight : 0);
          collapse();
        }
        $('find').addEventListener('click', () => searching(true));
        $('searchcancel').addEventListener('click', () => {
          searching(false);
          seen();
        });
        $('search').addEventListener('submit', (event) => { event.preventDefault(); $('query').blur(); });
        $('query').addEventListener('input', () => { clearTimeout(finding); finding = setTimeout(find, 250); });

        async function find() {
          const asked = $('query').value;
          if (asked.trim().length < 2) return $('found').replaceChildren(el('p', 'note', words.searchHint));
          const holding = pass;
          const response = await request('/search', { words: asked });
          if (asked !== $('query').value || $('search').hidden) return;
          if (response && response.status === 401) return refused(holding);
          if (!response || !response.ok) return banner(response && response.status === 409 ? words.gone : words.unreachable);
          banner('');
          const result = await response.json();
          const hits = result.found.map((item) => {
            const node = el('button', 'hit');
            node.type = 'button';
            node.append(el('small', null, item.name + ' · ' + item.detail), marked(item.text, item.marks));
            node.onclick = () => {
              landing = { key: item.open, id: item.id };
              searching(false);
              if (item.open === key && view) show(view); else go(item.open);
            };
            return node;
          });
          if (!hits.length) hits.push(el('p', 'note', words.searchNothing));
          if (result.more) hits.push(el('p', 'note', words.searchMore(result.found.length)));
          $('found').replaceChildren(...hits);
        }

        function marked(text, marks) {
          const node = el('p');
          let at = 0;
          for (const [start, length] of marks) {
            if (start < at) continue;
            node.append(text.slice(at, start), el('b', null, text.slice(start, start + length)));
            at = start + length;
          }
          node.append(text.slice(at));
          return node;
        }

        function cat(key, small) {
          const node = el('img', small ? 'cat small' : 'cat');
          node.alt = '';
          node.src = '/cat/dark/' + key + '.png';
          return node;
        }

        function lit(node, key) {
          const jacket = (key || '').split('/')[1];
          if (jacket && jacket !== 'shades') node.style.setProperty('--light', '#' + jacket);
          else node.style.removeProperty('--light');
          return node;
        }

        function drift(index, count) {
          return 'hsl(' + (172 + 172 * index / Math.max(count - 1, 1)) + ' 100% 68%)';
        }

        function tile(child) {
          const node = el('span', 'tile');
          node.append(child);
          return node;
        }

        function you(small) {
          const node = el('img', small ? 'you small' : 'you');
          node.alt = '';
          node.src = view.you;
          return node;
        }
        function face(color) {
          if (view.you) return you(true);
          const node = el('span', 'face');
          if (color) node.style.background = color;
          return node;
        }

        const icons = {
          activity: ['M6 16v-5a6 6 0 0 1 12 0v5l2 2H4z', 'M10 21h4'],
          threads: ['M4 4h11a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H9l-4 3v-3H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z',
            'M19 9h1a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-1v3l-4-3h-4a1 1 0 0 1-1-1v-1'],
        };
        function icon(name) {
          const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
          svg.setAttribute('viewBox', '0 0 24 24');
          svg.setAttribute('aria-hidden', 'true');
          svg.setAttribute('class', 'symbol');
          for (const d of icons[name] || []) {
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.setAttribute('d', d);
            svg.append(path);
          }
          return svg;
        }

        function dot(color) {
          const node = el('span', 'dot');
          if (color) node.style.background = color;
          return node;
        }

        function places(list) {
          const nodes = [];
          const glyphs = list.filter((place) => place.icon);
          let group;
          for (const place of list) {
            if (place.group && place.group !== group) nodes.push(el('h2', 'group', place.group));
            group = place.group;
            const button = el('button', 'place' + (place.unread || place.count ? ' unread' : ''));
            button.type = 'button';
            const art = place.icon ? icon(place.icon) : cat(place.cat);
            const lights = place.icon ? tile(art) : lit(tile(art), place.cat);
            if (place.icon) lights.style.setProperty('--light', drift(glyphs.indexOf(place), glyphs.length));
            button.append(lights);
            button.append(el('span', 'name', place.title));
            if (place.count) button.append(el('span', 'count', String(place.count)));
            else if (place.unread) button.append(el('span', 'unreadcount', String(place.unread)));
            if (place.dot) button.append(dot(place.dot));
            button.setAttribute('aria-label', [place.title, place.state, place.count && words.waiting(place.count), place.unread && words.unread(place.unread)].filter(Boolean).join(', '));
            button.onclick = () => go(place.key);
            nodes.push(button);
          }
          return nodes;
        }

        const time = (at) => new Date(at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });

        function replybar(item) {
          if (!item.replies && !item.going && !item.waiting) return null;
          const bar = el('button', 'replybar');
          bar.type = 'button';
          for (const person of item.faces || []) bar.append(person.cat ? cat(person.cat, true) : face(person.color));
          if (item.unread) bar.append(el('span', 'unread'));
          if (item.waiting) bar.append(el('span', 'waiting', 'Needs you'));
          if (item.replies) bar.append(el('b', null, item.replies === 1 ? '1 reply' : item.replies + ' replies'));
          if (item.lastReply) bar.append(el('span', null, item.lastReply));
          if (item.going) bar.append(el('span', null, 'Working on it'));
          bar.onclick = () => go(item.open);
          return bar;
        }

        function row(item) {
          switch (item.kind) {
            case 'day': return el('div', 'day', item.text);
            case 'note': return el('p', 'note', item.text);
            case 'backlog': {
              const node = el('div', 'backlog');
              node.append(el('p', null, item.title));
              if (item.detail) node.append(el('small', null, item.detail));
              return node;
            }
            case 'older': {
              const node = el('button', 'note older', item.text);
              node.type = 'button';
              node.disabled = !!item.done;
              node.onclick = () => act({ act: 'older', key }, true);
              return node;
            }
            case 'message': return message(item);
            case 'parent': {
              const node = message(item);
              const bar = replybar(item);
              if (bar) node.append(bar);
              else node.append(button(words.openThread, () => go(item.open), 'open'));
              node.querySelector('.bubble')?.addEventListener('click', (event) => {
                if (!selecting() && !event.target.closest('[role=link], button')) go(item.open);
              });
              return node;
            }
            case 'replies': return el('div', 'replies', item.text);
            case 'new': {
              const node = el('div', 'new', item.text);
              node.dataset.jump = item.detail;
              return node;
            }
            case 'digest': {
              const node = el('button', 'digest' + (item.unread ? ' unread' : ''));
              node.type = 'button';
              node.append(el('h3', null, item.title), who(item, item.at), el('p', null, item.text || ''));
              if (item.reply) node.append(who(item.reply, item.reply.at), el('p', null, item.reply.text || ''));
              if (item.more) node.append(el('p', 'more', item.more === 1 ? '1 more reply' : item.more + ' more replies'));
              node.onclick = () => go(item.open);
              return node;
            }
            case 'section': {
              const node = el('div', 'section');
              node.append(el('span', null, item.title));
              if (item.clear) {
                const clear = el('button', null, words.clear);
                clear.type = 'button';
                clear.onclick = () => act({ act: 'clear', kind: item.clear });
                node.append(clear);
              }
              return node;
            }
            case 'heading': {
              const node = el('div', 'heading');
              const name = el('div');
              name.append(el('b', null, item.name), el('p', null, item.detail));
              node.append(lit(tile(cat(item.cat)), item.cat), name);
              return node;
            }
            case 'issue': {
              const node = el('button', 'issue');
              node.type = 'button';
              const line = el('span', 'line');
              line.append(dot(item.dot), el('span', null, item.title));
              node.append(line, el('small', null, item.detail));
              node.onclick = () => { if (item.open) go(item.open); else if (item.t3) openInT3(item.t3); };
              return node;
            }
            default: return card(item);
          }
        }

        function who(item, at) {
          const node = el('small', 'who');
          node.append(item.cat ? cat(item.cat, true) : face(item.color), item.name + ' · ' + time(at));
          return node;
        }

        function message(item) {
          const yours = item.mine && view.you;
          const node = el('div', 'msg' + (item.mine ? ' mine' : '') + (item.cat ? ' withcat' : '') + (yours ? ' withyou' : ''));
          if (item.context) {
            const context = el('button', 'context', item.context);
            context.type = 'button';
            context.onclick = () => go(item.open);
            node.append(context);
          }
          const meta = item.mine ? [item.sending ? words.sending : time(item.at)] : [item.name, item.detail, time(item.at)];
          node.append(el('div', 'meta', meta.filter(Boolean).join(' · ')));
          const said = el('div', 'said');
          if (item.cat) said.append(cat(item.cat));
          if (said.childElementCount || item.text || yours) node.append(said);
          if (item.text) {
            const bubble = el('div', 'bubble' + (item.mine ? '' : ' lit') + (item.faded ? ' faded' : ''));
            bubble.append(...(item.markup ? markup(item.markup) : [item.text]));
            if (item.mine && item.color) bubble.style.setProperty('--fill', item.color);
            if (!item.mine) lit(bubble, item.cat);
            said.append(bubble);
          }
          if (yours) said.append(you());
          if (item.files) {
            const pictures = el('div', 'pictures' + (item.files.filter((file) => file.picture).length > 1 ? ' several' : ''));
            item.files.forEach((file) => {
              if (file.picture) {
                const picture = el('img', 'picture');
                picture.onload = settle;
                picture.src = file.picture;
                picture.alt = file.name;
                pictures.append(picture);
              } else if (file.web) {
                const host = new URL(file.web).host;
                const label = file.failed ? file.name + ' · ' + words.couldntShow : words.pictureFrom(host);
                pictures.append(button(label, () => ask(file.web, () => act({ act: 'picture', id: item.id, value: file.web })), 'file web'));
              } else {
                pictures.append(el('div', 'file', '📄 ' + file.name));
              }
            });
            if (pictures.childElementCount) node.append(pictures);
          }
          if (item.failure) node.append(el('div', 'failure', item.failure));
          if (item.retry) {
            node.append(button(words.retry, (event) => {
              event.target.disabled = true;
              act({ act: 'retry', id: item.id }).then((done) => { if (!done) event.target.disabled = false; });
            }, 'retry'));
          }
          if (item.reactions && item.reactions.length) {
            const marks = el('div', 'reactions');
            for (const reaction of item.reactions) marks.append(button(reaction.label, () => act({ act: 'react', id: item.id, value: reaction.value })));
            node.append(marks);
          }
          const bubble = node.querySelector('.bubble');
          if (item.reactions && bubble && item.kind !== 'parent') {
            bubble.addEventListener('click', (event) => {
              if (selecting() || event.target.closest('[role=link], button')) return;
              react(item);
            });
            node.append(button(words.react, () => react(item), 'react'));
          }
          return node;
        }

        function react(item) {
          $('marks').replaceChildren(...view.marks.map((mark) => {
            const on = item.reactions.some((reaction) => reaction.value === mark.value);
            const pick = button(mark.label, () => { $('reactsheet').close(); act({ act: 'react', id: item.id, value: mark.value }); }, on ? 'on' : null);
            pick.setAttribute('aria-pressed', String(on));
            return pick;
          }));
          if (!$('reactsheet').open) $('reactsheet').showModal();
          $('marks').firstChild.focus();
        }

        function markup(blocks) {
          return blocks.map((block) => {
            if (block.kind === 'code') return code(block.code);
            if (block.kind === 'table') return table(block.rows);
            if (block.kind === 'rule') return el('hr');
            const node = el({ heading: 'h4', quote: 'blockquote', item: 'div' }[block.kind] || 'p', block.kind === 'item' ? 'item' : null);
            let words = node;
            if (block.kind === 'item') {
              node.style.paddingLeft = (block.depth - 1) * 1.2 + 'em';
              words = el('span');
              node.append(el('span', 'marker', block.marker), words);
            }
            words.append(...block.spans.map(span));
            return node;
          });
        }

        function span(part) {
          let node = document.createTextNode(part.text);
          for (const [on, tag] of [[part.code, 'code'], [part.strike, 's'], [part.italic, 'em'], [part.bold, 'strong']]) {
            if (!on) continue;
            const wrap = el(tag);
            wrap.append(node);
            node = wrap;
          }
          if (part.pull) {
            node = el('span', 'chip', part.pull.state ? part.text + ' · ' + part.pull.state : part.text);
            node.dataset.state = part.pull.state || '';
          }
          if (!part.link || !/^https?:\/\//i.test(part.link)) return node;
          // Outside the repo: a browser lets a long press, a middle click or a new window follow any href.
          const link = el('span', 'link');
          link.setAttribute('role', 'link');
          link.tabIndex = 0;
          link.append(node);
          link.onclick = () => ask(part.link);
          // Outside the repo: an Enter that isn't held back goes on to press whatever the sheet just put the keyboard on.
          link.onkeydown = (event) => { if (event.key === 'Enter') { event.preventDefault(); ask(part.link); } };
          return link;
        }

        function code(text) {
          const node = el('div', 'code');
          const copy = button(words.copy, async () => {
            try { await navigator.clipboard.writeText(text); } catch (error) { return; }
            copy.textContent = words.copied;
            setTimeout(() => { copy.textContent = words.copy; }, 1200);
          }, 'copy');
          node.append(copy, el('pre', null, text));
          return node;
        }

        function table(rows) {
          const node = el('div', 'table');
          const grid = el('table');
          rows.forEach((row, index) => {
            const line = el('tr');
            for (const cell of row) {
              const box = el(index ? 'td' : 'th');
              box.append(...cell.map(span));
              line.append(box);
            }
            grid.append(line);
          });
          node.append(grid);
          return node;
        }

        let showing = null;
        function ask(link, show) {
          showing = show || null;
          $('linktitle').textContent = show ? words.showPicture(new URL(link).host) : words.openLink(new URL(link).host);
          $('linkaddress').textContent = link;
          $('linkaddress').scrollTop = 0;
          $('linkopen').hidden = !!show;
          $('linkshow').hidden = !show;
          if (show) $('linkopen').removeAttribute('href'); else $('linkopen').href = link;
          if (!$('linksheet').open) $('linksheet').showModal();
        }

        function button(label, onclick, className) {
          const node = el('button', className, label);
          node.type = 'button';
          node.onclick = onclick;
          return node;
        }

        function card(item) {
          const node = lit(el('article', 'card ' + item.kind), item.cat);
          const header = el('header');
          header.append(cat(item.cat), el('span', 'title', item.title));
          if (item.at) header.append(el('time', null, time(item.at)));
          node.append(header);
          if (!(item.parts || []).some((part) => part.text === item.text)) node.append(el('p', 'text', item.text));
          if (item.answer) node.append(el('p', 'answer', item.answer));
          if (item.kind === 'question') question(item, node);
          const buttons = el('div', 'buttons');
          if (item.kind === 'approval') {
            for (const choice of item.choices) {
              buttons.append(button(choice.label, (event) => {
                buttons.querySelectorAll('button').forEach((b) => { b.disabled = true; });
                act({ act: 'approval', id: item.id, value: choice.value });
              }, choice.value === 'accept' ? 'go' : null));
            }
          }
          if (item.kind === 'ask' || item.kind === 'change') {
            for (const choice of item.choices) {
              if (choice.value === 'reply') { buttons.append(button(choice.label, () => go(item.open))); continue; }
              buttons.append(button(choice.label, () => {
                buttons.querySelectorAll('button').forEach((b) => { b.disabled = true; });
                act({ act: 'ask', id: item.id, value: choice.value });
              }, choice.value === 'accept' ? 'go' : null));
            }
          }
          if (item.kind === 'report') {
            buttons.append(button(item.choices[0].label, () => go(item.open)));
            if (item.done) buttons.append(button(words.done, () => act({ act: 'done', id: item.id })));
          }
          if (item.t3) buttons.append(button(words.openInT3, () => openInT3(item.t3)));
          if (buttons.childElementCount) node.append(buttons);
          if (item.footer) node.append(el('p', 'footer', item.footer));
          return node;
        }

        function question(item, node) {
          const parts = item.parts || [];
          if (!parts.length) return;
          const picked = answers.get(item.id) || parts.map(() => []);
          answers.set(item.id, picked);
          const send = button(words.answer, () => {
            send.disabled = true;
            act({ act: 'answer', id: item.id, answers: picked }).then((done) => { if (done) answers.delete(item.id); else send.disabled = false; });
          }, 'go');
          const ready = () => { send.disabled = picked.some((answer) => !answer.join('').trim()); };
          const instant = parts.length === 1 && !parts[0].words && !parts[0].several;
          parts.forEach((part, index) => {
            const box = el('div', 'part');
            box.append(el('p', 'text', (parts.length > 1 ? (index + 1) + ' of ' + parts.length + ': ' : '') + part.text));
            const choices = el('div', 'buttons');
            for (const choice of part.choices) {
              const pick = button(choice.label, () => {
                if (instant) {
                  choices.querySelectorAll('button').forEach((b) => { b.disabled = true; });
                  act({ act: 'answer', id: item.id, answers: [[choice.value]] });
                  return;
                }
                const was = chosen(part, picked[index]);
                const now = !part.several ? [choice.value] : was.includes(choice.value) ? was.filter((value) => value !== choice.value) : was.concat(choice.value);
                picked[index] = part.choices.map((c) => c.value).filter((value) => now.includes(value));
                choices.querySelectorAll('button').forEach((b, i) => mark(b, picked[index].includes(part.choices[i].value)));
                if (input) input.value = '';
                ready();
              });
              if (!instant) mark(pick, chosen(part, picked[index]).includes(choice.value));
              choices.append(pick);
            }
            let input = null;
            if (part.words) {
              input = el('input');
              input.placeholder = 'Your answer';
              if (!chosen(part, picked[index]).length) input.value = picked[index][0] || '';
              input.oninput = () => {
                picked[index] = [input.value];
                choices.querySelectorAll('button').forEach((b) => mark(b, false));
                ready();
              };
            }
            if (choices.childElementCount) box.append(choices);
            if (part.several) box.append(el('p', 'footer', words.several));
            if (input) box.append(input);
            node.append(box);
          });
          if (!instant) {
            ready();
            const row = el('div', 'buttons');
            row.append(send);
            node.append(row);
          }
        }

        function chosen(part, answer) {
          return answer.every((value) => part.choices.some((choice) => choice.value === value)) ? answer : [];
        }

        function mark(button, picked) {
          button.classList.toggle('picked', picked);
          button.setAttribute('aria-pressed', String(picked));
        }

        $('back').onclick = () => { if (view && view.back) go(view.back); };
        $('link').onclick = () => { if (view && view.link) go(view.link.open); };
        $('t3').onclick = () => { if (view && view.t3) openInT3(view.t3); };
        $('backlog').onclick = () => { if (view && view.backlog) go(view.backlog.open); };

        // Outside the repo: T3 Code's own page is at this host on the usual HTTPS port, and asks you to sign in itself.
        function openInT3(path) {
          window.open('https://' + location.hostname + path, '_blank', 'noopener,noreferrer');
        }
        $('linkcancel').onclick = () => $('linksheet').close();
        $('linkopen').onclick = () => $('linksheet').close();
        // Outside the repo: a tap on a dialog's backdrop lands on the dialog itself, outside its box.
        for (const sheet of document.querySelectorAll('dialog')) {
          sheet.onclick = (event) => {
            const box = sheet.getBoundingClientRect();
            const outside = event.clientY < box.top || event.clientY > box.bottom || event.clientX < box.left || event.clientX > box.right;
            if (event.target === sheet && outside) sheet.close();
          };
        }
        $('linkshow').onclick = () => {
          $('linksheet').close();
          if (showing) showing();
          showing = null;
        };

        $('box').onsubmit = async (event) => {
          event.preventDefault();
          const text = $('words').value.trim();
          if ((!text && !attached.length) || uploading) return;
          $('send').disabled = true;
          const done = await act({ act: 'send', key, text, also: !$('alsolabel').hidden && $('also').checked, files: attached.map((file) => file.id) });
          if (!done) return sendable();
          $('words').value = '';
          $('also').checked = false;
          attached = [];
          chips();
          fit();
          if (done.open) return go(done.open);
          jumped = false;
          window.scrollTo(0, document.body.scrollHeight);
          foot();
        };

        let attached = [];
        let uploading = false;
        $('attach').onclick = () => $('pick').click();
        $('pick').onchange = () => {
          const files = [...$('pick').files];
          $('pick').value = '';
          attach(files);
        };
        $('words').addEventListener('paste', (event) => {
          const files = [...(event.clipboardData ? event.clipboardData.files : [])];
          if (!files.length || !view || !view.box || !view.box.files) return;
          event.preventDefault();
          attach(files);
        });

        async function attach(files) {
          if (!files.length || uploading) return;
          banner(attached.length + files.length > 10 ? words.tooMany : '');
          uploading = true;
          $('send').disabled = true;
          try {
            for (const file of files.slice(0, 10 - attached.length)) {
              const isPicture = file.type.startsWith('image/');
              if (!isPicture && file.type !== 'application/pdf') { banner(words.cantRead); continue; }
              const name = isPicture ? (file.name || 'photo').replace(/\.[^.]*$/, '') + '.jpg' : file.name;
              const going = { name, picture: null, sent: 0 };
              attached.push(going);
              chips();
              const blob = isPicture ? await shrink(file) : file;
              if (isPicture) { going.picture = await preview(blob); chips(); }
              if (!attached.includes(going)) continue;
              if (blob.size > 10 * 1024 * 1024) { drop(going); banner(words.tooBig); continue; }
              const holding = pass;
              const response = await upload(blob, name, going);
              if (!attached.includes(going)) continue;
              if (response.status === 401 && refused(holding)) return;
              if (!response.ok) { drop(going); banner(response.status === 413 ? words.tooBig : words.unreachable); continue; }
              going.id = response.id;
              delete going.sent;
              chips();
            }
          } catch (error) {
            banner(words.unreachable);
          } finally {
            uploading = false;
            sendable();
          }
        }

        // Outside the repo: XMLHttpRequest reports upload progress, which fetch can't.
        function upload(blob, name, going) {
          return new Promise((resolve) => {
            const request = new XMLHttpRequest();
            going.cancel = () => request.abort();
            request.open('POST', '/file');
            const sent = headers({ 'Content-Type': blob.type || 'application/octet-stream', 'X-Shades': '1', 'X-Name': encodeURIComponent(name) });
            for (const header of Object.keys(sent)) request.setRequestHeader(header, sent[header]);
            request.upload.onprogress = (event) => {
              if (!event.lengthComputable || going.sent === undefined) return;
              going.sent = event.loaded / event.total;
              chips();
            };
            request.onload = () => {
              let id = null;
              try { id = JSON.parse(request.responseText).id; } catch (error) {}
              resolve({ status: request.status, ok: request.status >= 200 && request.status < 300 && Boolean(id), id });
            };
            request.onerror = request.onabort = () => resolve({ status: 0, ok: false });
            request.send(blob);
          });
        }

        function drop(file) {
          attached = attached.filter((other) => other !== file);
          chips();
        }

        function chips() {
          $('attached').replaceChildren(...attached.map((file) => {
            const chip = el('div', 'attachment' + (file.sent === undefined ? '' : ' going'));
            if (file.picture) {
              const picture = el('img');
              picture.src = file.picture;
              picture.alt = '';
              chip.append(picture);
            }
            chip.append(el('span', 'name', file.name));
            if (file.sent !== undefined) chip.append(el('span', 'state', file.sent > 0 && file.sent < 1 ? Math.round(file.sent * 100) + '%' : words.sending));
            const remove = button('✕', () => {
              drop(file);
              forget([file]);
            });
            remove.setAttribute('aria-label', 'Remove ' + file.name);
            chip.append(remove);
            return chip;
          }));
          $('attached').hidden = !attached.length;
          sendable();
        }

        function sendable() {
          $('send').disabled = !(view && view.box && view.box.ready) || uploading || (!$('words').value.trim() && !attached.length);
        }

        function preview(blob) {
          return new Promise((resolve) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => resolve(null);
            reader.readAsDataURL(blob);
          });
        }

        function unattach() {
          forget(attached);
          attached = [];
          chips();
        }

        function forget(files) {
          for (const file of files) {
            if (file.sent !== undefined) file.cancel && file.cancel();
            else post('/act', { act: 'unattach', id: file.id });
          }
        }

        // Outside the repo: a model scales a picture down to about 1.15 megapixels and 1568 pixels a side before reading it.
        async function shrink(file) {
          const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
          const scale = Math.min(1, 1568 / Math.max(bitmap.width, bitmap.height), Math.sqrt(1150000 / (bitmap.width * bitmap.height)));
          const canvas = document.createElement('canvas');
          canvas.width = Math.floor(bitmap.width * scale);
          canvas.height = Math.floor(bitmap.height * scale);
          canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
          return new Promise((resolve, reject) => canvas.toBlob((blob) => blob ? resolve(blob) : reject(new Error('no picture')), 'image/jpeg', 0.8));
        }

        function fit() {
          const words = $('words');
          words.style.height = 'auto';
          words.style.height = words.scrollHeight + 'px';
        }
        $('words').addEventListener('input', fit);
        $('words').addEventListener('input', sendable);

        $('pairform').onsubmit = async (event) => {
          event.preventDefault();
          if (await pair($('code').value)) start();
        };

        window.addEventListener('hashchange', () => {
          if (new URLSearchParams(location.hash.slice(1)).get('pair')) start();
        });

        document.addEventListener('visibilitychange', () => {
          if (document.visibilityState !== 'visible') return;
          seen();
          revive(15000);
        });

        start();
        """#

    static let manifest = """
        {"name": "The Kitty Litter", "short_name": "Kitty Litter", "start_url": "/?key=home", "scope": "/", "display": "standalone",
         "background_color": "#000000", "theme_color": "#000000", "icons": [{"src": "/icon.png", "sizes": "180x180", "type": "image/png"}]}
        """

    static let worker = #"""
        'use strict';
        self.addEventListener('push', (event) => {
          let message = {};
          try { message = event.data ? event.data.json() : {}; } catch (error) {}
          event.waitUntil(self.registration.showNotification(message.title || 'The Kitty Litter', { tag: message.tag, icon: '/icon.png', data: { key: message.key } }));
        });
        self.addEventListener('notificationclick', (event) => {
          event.notification.close();
          const url = '/?key=' + encodeURIComponent((event.notification.data && event.notification.data.key) || 'activity');
          event.waitUntil((async () => {
            for (const client of await clients.matchAll({ type: 'window', includeUncontrolled: true })) {
              await client.navigate(url);
              return client.focus();
            }
            return clients.openWindow(url);
          })());
        });
        """#
}
