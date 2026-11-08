import ShadesCore

/// The page a phone opens. It only draws what the Mac sends and says what you did, and every word on it is put there
/// as text, never as markup, since it's what kittens said.
enum PhonePage {
    static let html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="light dark">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-title" content="Shades">
        <title>Shades</title>
        <link rel="manifest" href="/manifest.json">
        <link rel="apple-touch-icon" href="/icon.png">
        <link rel="stylesheet" href="/app.css">
        <script src="/app.js" defer></script>
        </head>
        <body>
        <header id="top">
          <button id="back" type="button" hidden></button>
          <div id="head">
            <span id="headcat" hidden></span>
            <div id="names">
              <h1 id="title">Shades</h1>
              <p id="subtitle"></p>
            </div>
            <button id="link" type="button" hidden></button>
          </div>
        </header>
        <div id="banner" role="status" hidden></div>
        <div id="notify" hidden>
          <p id="notifytext"></p>
          <button id="notifybutton" type="button" hidden>Turn on</button>
        </div>
        <main id="rows"></main>
        <form id="box" hidden>
          <label id="label" for="words"></label>
          <div id="attached" hidden>
            <img id="attachedpicture" alt="">
            <span id="attachedname"></span>
            <button id="unattach" type="button" aria-label="Remove attachment">✕</button>
          </div>
          <div class="field">
            <button id="attach" class="tool" type="button" aria-label="Attach a photo or file">📎</button>
            <button id="camera" class="tool" type="button" aria-label="Take a photo">📷</button>
            <textarea id="words" rows="1" enterkeyhint="send"></textarea>
            <button id="send" type="submit">Send</button>
          </div>
          <input id="pick" type="file" accept="image/*,application/pdf" hidden>
          <input id="snap" type="file" accept="image/*" capture="environment" hidden>
          <label id="alsolabel" hidden><input type="checkbox" id="also"> <span id="alsotext"></span></label>
        </form>
        <div id="linksheet" role="dialog" aria-labelledby="linktitle" hidden>
          <p id="linktitle"></p>
          <p id="linkaddress"></p>
          <div class="buttons">
            <button id="linkcancel" type="button">Cancel</button>
            <a id="linkopen" class="go" target="_blank" rel="noopener noreferrer">Open</a>
          </div>
        </div>
        <section id="pair" hidden>
          <h1>Pair this phone</h1>
          <p>Turn on Messages on your phone in Shades' Settings on your Mac, and it shows a code. Scan it with your camera, or type it here.</p>
          <form id="pairform">
            <input id="code" autocomplete="one-time-code" autocapitalize="characters" autocorrect="off" spellcheck="false" placeholder="ABCD-EFGH" aria-label="Code">
            <button type="submit">Pair</button>
          </form>
          <p id="pairnote" role="status"></p>
        </section>
        </body>
        </html>
        """

    static let style = """
        :root {
          --paper: #f9f9f9; --text: #1d1d1f; --soft: #6e6e73; --line: #d2d2d7; --grey: #e9e9eb;
          --you: #0071e3; --on-you: #ffffff; --card: #ffffff; --warn: #c9341c; --badge: #ff3b5c; --cats: light;
          font: 17px/1.35 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
          -webkit-text-size-adjust: 100%;
        }
        @media (prefers-color-scheme: dark) {
          :root { --paper: #1d1d1f; --text: #f5f5f7; --soft: #98989d; --line: #3a3a3c; --grey: #3a3a3c; --card: #2c2c2e; --warn: #ff6b55; --cats: dark; }
        }
        * { box-sizing: border-box; }
        html, body { margin: 0; background: var(--paper); color: var(--text); }
        body { min-height: 100dvh; display: flex; flex-direction: column; }
        button { font: inherit; color: inherit; background: none; border: 0; padding: 0; cursor: pointer; }
        [hidden] { display: none !important; }

        #top { position: sticky; top: 0; z-index: 2; background: var(--paper); border-bottom: 1px solid var(--line);
          padding: calc(env(safe-area-inset-top) + 10px) 16px 10px; }
        #back { color: var(--you); font-size: 15px; margin-bottom: 4px; display: block; max-width: 100%;
          white-space: nowrap; overflow: hidden; text-overflow: ellipsis; text-align: left; }
        #head { display: flex; align-items: center; gap: 10px; }
        #names { flex: 1; min-width: 0; }
        #link { color: var(--you); font-size: 15px; flex: none; }
        #title { font-size: 20px; margin: 0; font-weight: 600; overflow-wrap: anywhere; }
        #subtitle { margin: 2px 0 0; color: var(--soft); font-size: 13px; }
        #subtitle:empty { display: none; }
        #banner { background: var(--warn); color: #fff; padding: 8px 16px; font-size: 14px; }
        #notify { display: flex; align-items: center; gap: 12px; margin: 12px 12px 0; padding: 10px 14px; border-radius: 14px;
          background: var(--card); border: 1px solid var(--line); }
        #notifytext { flex: 1; margin: 0; color: var(--soft); font-size: 14px; }
        #notifybutton { background: var(--you); color: var(--on-you); border-radius: 999px; padding: 6px 14px; font-size: 15px; }

        main { flex: 1; padding: 8px 12px 16px; }
        .group { color: var(--soft); font-size: 12px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; margin: 22px 4px 6px; }
        .place { display: flex; align-items: center; gap: 12px; width: 100%; padding: 12px 8px; border-radius: 12px; text-align: left; }
        .place:active, .issue:active { background: var(--grey); }
        .place .name { flex: 1; font-size: 17px; }
        .place.unread .name { font-weight: 600; }
        .place.asleep { opacity: .45; }
        .count { background: var(--badge); color: #fff; border-radius: 999px; padding: 1px 8px; font-size: 13px; font-weight: 700; font-variant-numeric: tabular-nums; }
        .icon { width: 32px; height: 32px; flex: none; display: grid; place-items: center; color: var(--soft); }
        .icon svg { width: 22px; height: 22px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
        .place.unread .icon { color: var(--text); }
        .dot { width: 8px; height: 8px; flex: none; background: var(--soft); }
        /* The window's pixel art, kept crisp: each of its pixels is a whole number of the phone's at 16 and 32. */
        .cat { width: 32px; height: 32px; flex: none; image-rendering: -webkit-optimize-contrast; image-rendering: pixelated; }
        .cat.small { width: 16px; height: 16px; }
        .face { width: 16px; height: 16px; flex: none; border-radius: 4px; background: var(--you); }
        .you { width: 32px; height: 32px; flex: none; border-radius: 50%; object-fit: cover; box-shadow: 0 0 0 .5px var(--line); }
        .you.small { width: 16px; height: 16px; }

        .day { text-align: center; color: var(--soft); font-size: 12px; margin: 18px 0 6px; }
        .msg { margin: 6px 0; display: flex; flex-direction: column; align-items: flex-start; }
        .msg.mine { align-items: flex-end; }
        .msg.withcat { padding-left: 40px; }
        .said { display: flex; align-items: flex-end; gap: 8px; align-self: stretch; }
        .msg.mine .said { justify-content: flex-end; }
        .said .cat { margin-left: -40px; }
        .msg.withyou { padding-right: 40px; }
        .said .you { margin-right: -40px; }
        .meta { color: var(--soft); font-size: 12px; margin: 4px 12px 3px; }
        .bubble { max-width: 86%; padding: 9px 14px; border-radius: 18px; background: var(--grey); color: var(--text);
          white-space: pre-wrap; overflow-wrap: anywhere; }
        .bubble.going { opacity: .55; }
        .bubble code { font: .9em ui-monospace, Menlo, monospace; }
        .bubble a, .bubble .link { color: inherit; }
        .bubble .link { text-decoration: underline; cursor: pointer; }
        .bubble p, .bubble h4, .bubble blockquote { margin: 0; }
        .bubble > * + * { margin-top: .5em; }
        .bubble > .item + .item { margin-top: .15em; }
        .bubble h4 { font-size: 1em; }
        .bubble blockquote { padding-left: 10px; border-left: 3px solid color-mix(in srgb, currentColor 35%, transparent); }
        .bubble .item { display: flex; gap: .4em; }
        .bubble .marker { flex: none; min-width: .8em; }
        .bubble .code { border-radius: 10px; background: color-mix(in srgb, currentColor 9%, transparent); }
        .bubble pre { margin: 0; padding: 8px 10px; font: 14px/1.4 ui-monospace, Menlo, monospace; white-space: pre; overflow-x: auto; }
        .bubble .copy { display: block; margin: 0 0 -6px auto; padding: 4px 10px 0; font-size: 13px; opacity: .7; }
        .bubble .table { overflow-x: auto; }
        .bubble table { border-collapse: collapse; font-size: 15px; white-space: normal; }
        .bubble th, .bubble td { overflow-wrap: normal; border: 1px solid color-mix(in srgb, currentColor 25%, transparent); padding: 3px 8px; text-align: left; vertical-align: top; }
        .bubble th { background: color-mix(in srgb, currentColor 6%, transparent); }
        .bubble hr { border: 0; border-top: 1px solid color-mix(in srgb, currentColor 25%, transparent); margin: .6em 0; }
        /* GitHub's own colours for a pull request's state, as the window draws them. */
        .chip { display: inline-block; border-radius: 999px; padding: 0 8px; font-size: 14px; font-weight: 600; color: #fff; background: #6e7781; white-space: nowrap; }
        .chip[data-state=open] { background: #1f883d; }
        .chip[data-state=merged] { background: #8250df; }
        .chip[data-state=closed] { background: #cf222e; }
        /* However long the address, the sheet stays on screen and the address scrolls inside it. */
        #linksheet { position: fixed; left: 12px; right: 12px; bottom: calc(env(safe-area-inset-bottom) + 12px); z-index: 3;
          max-height: calc(100dvh - env(safe-area-inset-top) - env(safe-area-inset-bottom) - 24px); display: flex; flex-direction: column;
          background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 12px 14px; box-shadow: 0 6px 24px rgba(0, 0, 0, .25); }
        #linktitle { margin: 0; color: var(--soft); font-size: 13px; font-weight: 600; overflow-wrap: anywhere; }
        #linkaddress { margin: 6px 0 0; font: 14px/1.4 ui-monospace, Menlo, monospace; overflow-wrap: anywhere; overflow-y: auto; min-height: 0; }
        #linksheet .buttons { justify-content: flex-end; }
        #linksheet .buttons a { background: var(--you); color: var(--on-you); border-radius: 999px; padding: 8px 16px; font-size: 15px; text-decoration: none; }
        .bubble.cut { max-height: 16.5em; overflow: hidden; -webkit-mask-image: linear-gradient(#000 75%, transparent); }
        .more { color: var(--soft); font-size: 14px; margin: 4px 12px 0; }
        .failure { color: var(--warn); font-size: 13px; margin: 3px 12px 0; }
        .retry { color: var(--you); font-size: 14px; font-weight: 600; margin: 4px 12px 0; }
        .context { color: var(--soft); font-size: 12px; margin: 6px 12px 0; text-align: left; }
        .replybar { display: flex; align-items: center; gap: 6px; margin: 4px 6px 0; padding: 4px 8px; border-radius: 10px; font-size: 13px; }
        .replybar:active { background: var(--grey); }
        .replybar b { color: var(--you); }
        .replybar .waiting { color: var(--badge); font-weight: 600; }
        .replybar span { color: var(--soft); }
        .replies { display: flex; align-items: center; gap: 10px; color: var(--soft); font-size: 13px; margin: 12px 4px 4px; }
        .replies::after { content: ''; flex: 1; border-top: 1px solid var(--line); }
        .digest { display: block; width: 100%; text-align: left; padding: 12px 8px; border-bottom: 1px solid var(--line); }
        .digest:active { background: var(--grey); }
        .digest h3 { margin: 0 0 6px; font-size: 14px; }
        .digest.unread h3::before { content: ''; display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: var(--badge); margin-right: 6px; }
        .digest p { margin: 2px 0 6px; overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
        .digest small { color: var(--soft); }
        .digest .who { display: flex; align-items: center; gap: 6px; }
        .digest .more { color: var(--you); font-weight: 600; margin: 0; }
        #alsolabel { display: flex; align-items: center; gap: 6px; color: var(--soft); font-size: 13px; margin: 6px 4px 0; }
        .section { display: flex; justify-content: space-between; align-items: baseline; margin: 22px 4px 6px; }
        .section span { color: var(--soft); font-size: 12px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; }
        .section button { color: var(--you); font-size: 14px; }
        .heading { display: flex; align-items: center; gap: 10px; margin: 16px 4px 4px; }
        .heading p { margin: 0; color: var(--soft); font-size: 13px; }
        .issue { display: block; width: 100%; text-align: left; padding: 8px 4px 8px 46px; border-radius: 10px; }
        .issue .line { display: flex; align-items: center; gap: 8px; }
        .issue small { display: block; color: var(--soft); font-size: 13px; margin-left: 16px; }
        .note { color: var(--soft); text-align: center; font-size: 15px; margin: 24px 16px; }
        .older { display: block; width: calc(100% - 32px); background: none; border: 0; font: inherit; }

        .card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 12px 14px; margin: 10px 0; }
        .card header { display: flex; align-items: center; gap: 10px; color: var(--soft); font-size: 13px; }
        .card header .title { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text); font-weight: 600; font-size: 15px; }
        .card .text { margin: 8px 0 0; white-space: pre-wrap; overflow-wrap: anywhere; }
        .card.approval .text { font: 14px/1.4 ui-monospace, Menlo, monospace; }
        .card .answer { margin: 8px 0 0; padding-left: 10px; border-left: 3px solid var(--line); white-space: pre-wrap; overflow-wrap: anywhere; }
        .card .footer { margin: 8px 0 0; color: var(--soft); font-size: 13px; }
        .card .part { margin: 12px 0 0; }
        .buttons { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
        .buttons button, #pairform button { background: var(--grey); border-radius: 999px; padding: 8px 16px; font-size: 15px; }
        .buttons button.picked { background: var(--you); color: var(--on-you); }
        .buttons button.go { background: var(--you); color: var(--on-you); }
        .buttons button:disabled, #send:disabled { opacity: .4; }
        .card input, #pairform input { width: 100%; font: inherit; color: inherit; background: var(--paper); border: 1px solid var(--line);
          border-radius: 10px; padding: 8px 10px; margin-top: 8px; }

        #box { position: sticky; bottom: 0; background: var(--paper); border-top: 1px solid var(--line);
          padding: 8px 12px calc(env(safe-area-inset-bottom) + 8px); }
        #label { display: block; color: var(--soft); font-size: 12px; margin: 0 4px 6px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .field { display: flex; align-items: flex-end; gap: 8px; }
        #words { flex: 1; resize: none; font: inherit; color: inherit; background: var(--grey); border: 0; border-radius: 18px;
          padding: 8px 14px; max-height: 40vh; }
        #send { background: var(--you); color: var(--on-you); border-radius: 18px; padding: 8px 14px; font-weight: 600; }
        .tool { font-size: 20px; padding: 6px 2px; line-height: 1; }
        .tool:disabled { opacity: .4; }
        #attached { display: flex; align-items: center; gap: 10px; margin: 0 0 8px; padding: 6px 8px; border-radius: 12px; background: var(--grey); }
        #attached img { width: 44px; height: 44px; border-radius: 8px; object-fit: cover; flex: none; }
        #attached img:not([src]) { display: none; }
        #attachedname { flex: 1; font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        #unattach { color: var(--soft); padding: 4px 8px; }
        .picture { max-width: 66%; max-height: 240px; border-radius: 14px; margin-top: 4px; display: block; }
        .file { display: flex; align-items: center; gap: 8px; margin-top: 4px; padding: 8px 12px; border-radius: 12px;
          background: var(--card); border: 1px solid var(--line); font-size: 14px; max-width: 86%; overflow-wrap: anywhere; }

        #pair { padding: calc(env(safe-area-inset-top) + 40px) 24px 24px; }
        #pair h1 { font-size: 24px; margin: 0 0 8px; }
        #pair p { color: var(--soft); }
        #pairform { display: flex; gap: 8px; align-items: center; }
        #pairform input { margin: 0; font-size: 22px; letter-spacing: .1em; text-transform: uppercase; }
        """

    /// The theme you picked for Messages, over the page's own colours in light and dark alike. Each is a hex colour
    /// worked out on the Mac, so nothing from the theme's file reaches the page as it was written.
    static func colors(_ theme: ColorTheme?) -> String {
        guard let theme else { return "" }
        let hex = ColorTheme.hex
        return """

            :root { color-scheme: \(theme.isDark ? "dark" : "light"); --cats: \(theme.isDark ? "dark" : "light");
              --paper: \(hex(theme.paper)); --text: \(hex(theme.text)); --soft: \(hex(theme.soft)); --line: \(hex(theme.line));
              --grey: \(hex(theme.bubble)); --card: \(hex(theme.hover)); --you: \(hex(theme.accent)); --on-you: \(hex(theme.words(on: theme.accent))); }

            """
    }

    static let script = #"""
        'use strict';
        const $ = (id) => document.getElementById(id);
        const conversation = (key) => key === 'general' || /^(c|t|r):/.test(key);
        const words = {
          unreachable: "Can't reach your Mac. Shades has to be running, and your Mac awake.",
          gone: "That's changed since. Have another look.",
          wrongCode: "That code didn't work. Turn pairing on again in Shades on your Mac for a new one.",
          answer: 'Send answer', more: 'Show more', less: 'Show less', done: 'Done', clear: 'Clear', copy: 'Copy', copied: 'Copied',
          openLink: (host) => 'Open a link to ' + host + '?',
          several: 'Pick as many as you like.',
          sending: 'Sending...', retry: 'Try again',
          notifyAsk: 'Get a notification when something needs you.',
          cantRead: 'Shades can only read photos and PDFs.',
          tooBig: "That's too big to send. Try something under 10 MB.",
          homeScreen: 'For notifications on an iPhone, add this page to your Home Screen with Share, then pair it there.',
        };

        let key = new URLSearchParams(location.search).get('key') || 'home';
        // Kept for this address and port only, and sent only by this page. A cookie would go to every port on the name.
        let pass = localStorage.getItem('shades.key');
        let stream = null;
        let view = null;
        let retry = null;
        const expanded = new Set();
        const answers = new Map();

        function el(tag, className, text) {
          const node = document.createElement(tag);
          if (className) node.className = className;
          if (text != null) node.textContent = text;
          return node;
        }

        function banner(text) {
          $('banner').textContent = text || '';
          $('banner').hidden = !text;
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

        async function act(body, quiet) {
          const response = await post('/act', body);
          if (response && response.ok) { banner(''); return response.json(); }
          if (response && response.status === 401) { pairing(); return null; }
          if (!quiet) banner(response && response.status === 409 ? words.gone : words.unreachable);
          return null;
        }

        async function start() {
          clearTimeout(retry);
          const code = new URLSearchParams(location.hash.slice(1)).get('pair');
          if (code) {
            history.replaceState(history.state, '', location.pathname + location.search);
            if (!(await pair(code))) return;
          }
          if (!pass) return pairing();
          let hello = null;
          try { hello = await fetch('/hello', { headers: headers(), cache: 'no-store' }); } catch (error) {}
          if (hello && hello.status === 401) return pairing();
          if (!hello || !hello.ok) { banner(words.unreachable); retry = setTimeout(start, 5000); return; }
          $('pair').hidden = true;
          for (const id of ['top', 'rows']) $(id).hidden = false;
          listen();
          notifications().catch(() => {});
        }

        // Only who and what kind, as on the Mac. An iPhone only offers this to a page on its Home Screen.
        let pushKey = null;
        async function notifications() {
          if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
            return offer(words.homeScreen, false);
          }
          const registration = await navigator.serviceWorker.register('/sw.js');
          // Opening the page is looking at what they were about.
          for (const shown of await registration.getNotifications()) shown.close();
          if (Notification.permission === 'denied') return offer(null);
          const response = await fetch('/push', { headers: headers(), cache: 'no-store' });
          if (!response.ok) return offer(null);
          pushKey = (await response.json()).key;
          let subscription = await registration.pushManager.getSubscription();
          // Shades has a new signing key, such as after it was set up again, so this subscription goes nowhere now.
          if (subscription && encode(subscription.options.applicationServerKey) !== pushKey) {
            await subscription.unsubscribe();
            subscription = null;
          }
          if (subscription && Notification.permission === 'granted') {
            await keep(subscription);
            return offer(null);
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
            await keep(subscription);
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

        function pairing() {
          if (stream) stream.abort();
          stream = null;
          pass = null;
          localStorage.removeItem('shades.key');
          for (const id of ['top', 'rows', 'box', 'banner']) $(id).hidden = true;
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
          pairing();
          $('pairnote').textContent = response ? words.wrongCode : words.unreachable;
          return false;
        }

        // Server-sent events, read by hand, since EventSource can't send the key.
        async function listen() {
          if (stream) stream.abort();
          const mine = new AbortController();
          stream = mine;
          try {
            const response = await fetch('/events?key=' + encodeURIComponent(key), { headers: headers(), cache: 'no-store', signal: mine.signal });
            if (response.status === 401) return pairing();
            if (!response.ok || !response.body) throw new Error(String(response.status));
            const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
            let buffer = '';
            for (;;) {
              const { value, done } = await reader.read();
              if (done) break;
              buffer += value;
              let end;
              while ((end = buffer.indexOf('\n\n')) >= 0) {
                const event = buffer.slice(0, end);
                buffer = buffer.slice(end + 2);
                for (const line of event.split('\n')) {
                  if (line.startsWith('data: ')) { banner(''); show(JSON.parse(line.slice(6))); }
                }
              }
            }
          } catch (error) {}
          if (mine.signal.aborted || stream !== mine) return;
          banner(words.unreachable);
          retry = setTimeout(start, 3000);
        }

        function go(next, push = true) {
          if (!next || next === key) return;
          key = next;
          view = null;
          if (push) history.pushState({ key }, '', '?key=' + encodeURIComponent(key));
          $('rows').replaceChildren();
          listen();
        }

        window.addEventListener('popstate', (event) => go((event.state && event.state.key) || 'home', false));

        // Drawing the rows again would take away what you're selecting, so what's new waits until you're done.
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

        function show(next) {
          if (view && view.key === next.key && selecting()) { held = next; return; }
          held = null;
          const fresh = !view || view.key !== next.key;
          const nearBottom = window.innerHeight + window.scrollY >= document.body.scrollHeight - 60;
          if (next.key !== key) {
            key = next.key;
            history.replaceState({ key }, '', '?key=' + encodeURIComponent(key));
          }
          view = next;
          $('title').textContent = next.title;
          $('subtitle').textContent = next.subtitle || '';
          $('headcat').replaceChildren(...(next.cat ? [cat(next.cat)] : []));
          $('headcat').hidden = !next.cat;
          $('link').hidden = !next.link;
          $('link').textContent = next.link ? next.link.label : '';
          $('back').hidden = !next.back;
          $('back').textContent = next.back ? '‹ ' + next.backTitle : '';
          $('box').hidden = !next.box;
          // A file is for where you attached it, so it never follows you anywhere else.
          if (fresh || !next.box || !next.box.files) unattach();
          if (next.box) {
            $('label').textContent = next.box.label;
            $('words').placeholder = next.box.placeholder;
            $('send').disabled = !next.box.ready || uploading;
            for (const id of ['attach', 'camera']) $(id).hidden = !next.box.files;
            $('alsolabel').hidden = !next.box.also;
            $('alsotext').textContent = next.box.also || '';
            if (fresh) $('also').checked = false;
          }
          // Older posts come in where each thread started, which can be among what you're reading, so the lowest
          // message on the screen stays where it was.
          const kept = fresh || nearBottom || !conversation(key) ? null : lowestInSight();
          $('rows').replaceChildren(...(key === 'home' ? places(next.places) : next.rows.map(item => {
            const node = row(item);
            if (item.id) node.dataset.id = item.id;
            return node;
          })));
          $('notify').hidden = key !== 'home' || !$('notifytext').textContent;
          if (conversation(key) && (fresh || nearBottom)) window.scrollTo(0, document.body.scrollHeight);
          else if (fresh) window.scrollTo(0, 0);
          else if (kept) {
            const node = [...$('rows').children].find(child => child.dataset.id === kept.id);
            if (node) window.scrollBy(0, node.getBoundingClientRect().top - kept.top);
          }
          if (conversation(key) && document.visibilityState === 'visible') act({ act: 'seen', key }, true);
        }

        // The window's own cats, drawn on the Mac. The outline is light on a dark page, so it follows the page.
        const scheme = () => getComputedStyle(document.documentElement).getPropertyValue('--cats').trim() === 'dark' ? 'dark' : 'light';
        function cat(key, small) {
          const node = el('img', small ? 'cat small' : 'cat');
          node.alt = '';
          node.src = '/cat/' + scheme() + '/' + key + '.png';
          return node;
        }
        matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { if (view) show(view); });

        // You, where the window draws your picture, or a square in your colour.
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

        // Drawn to match the window's symbols for Activity, Threads and #general.
        const icons = {
          activity: ['M6 16v-5a6 6 0 0 1 12 0v5l2 2H4z', 'M10 21h4'],
          threads: ['M4 4h11a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H9l-4 3v-3H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z',
            'M19 9h1a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-1v3l-4-3h-4a1 1 0 0 1-1-1v-1'],
          channel: ['M10 4 8 20', 'M16 4l-2 16', 'M4 9h16', 'M3 15h16'],
        };
        function icon(name) {
          const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
          svg.setAttribute('viewBox', '0 0 24 24');
          svg.setAttribute('aria-hidden', 'true');
          for (const d of icons[name] || icons.channel) {
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.setAttribute('d', d);
            svg.append(path);
          }
          const node = el('span', 'icon');
          node.append(svg);
          return node;
        }

        function dot(color) {
          const node = el('span', 'dot');
          if (color) node.style.background = color;
          return node;
        }

        function places(list) {
          const nodes = [];
          let group;
          for (const place of list) {
            if (place.group && place.group !== group) nodes.push(el('h2', 'group', place.group));
            group = place.group;
            const button = el('button', 'place' + (place.unread || place.count ? ' unread' : '') + (place.asleep ? ' asleep' : ''));
            button.type = 'button';
            button.append(place.icon ? icon(place.icon) : cat(place.cat));
            button.append(el('span', 'name', place.title));
            if (place.count) button.append(el('span', 'count', String(place.count)));
            if (place.dot) button.append(dot(place.dot));
            button.onclick = () => go(place.key);
            nodes.push(button);
          }
          return nodes;
        }

        const time = (at) => new Date(at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });

        // Slack's reply bar under a thread's parent: who replied, how many, and when the last one was.
        function replybar(item) {
          if (!item.replies && !item.going && !item.waiting) return null;
          const bar = el('button', 'replybar');
          bar.type = 'button';
          for (const person of item.faces || []) bar.append(person.cat ? cat(person.cat, true) : face(person.color));
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
              node.querySelector('.bubble')?.addEventListener('click', () => { if (!selecting()) go(item.open); });
              return node;
            }
            case 'replies': return el('div', 'replies', item.text);
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
              node.append(cat(item.cat), name);
              return node;
            }
            case 'issue': {
              const node = el('button', 'issue');
              node.type = 'button';
              const line = el('span', 'line');
              line.append(dot(item.dot), el('span', null, item.title));
              node.append(line, el('small', null, item.detail));
              node.onclick = () => go(item.open);
              return node;
            }
            default: return card(item);
          }
        }

        // Who said something in Threads, with their cat, or your square.
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
          // As in the window, their cat sits beside the bottom of what they said, and your picture beside yours.
          const said = el('div', 'said');
          if (item.cat) said.append(cat(item.cat));
          if (said.childElementCount || item.text || yours) node.append(said);
          if (item.text) {
            const bubble = el('div', 'bubble' + (item.going || item.sending ? ' going' : ''));
            bubble.append(...(item.markup ? markup(item.markup) : [item.text]));
            if (item.color) { bubble.style.background = item.color; bubble.style.color = item.ink; }
            said.append(bubble);
            if (item.text.length > 600) {
              const open = expanded.has(item.id);
              bubble.classList.toggle('cut', !open);
              const more = el('button', 'more', open ? words.less : words.more);
              more.type = 'button';
              more.onclick = () => {
                if (expanded.has(item.id)) expanded.delete(item.id); else expanded.add(item.id);
                const cut = bubble.classList.toggle('cut');
                more.textContent = cut ? words.more : words.less;
              };
              node.append(more);
            }
          }
          if (yours) said.append(you());
          if (item.picture) {
            const picture = el('img', 'picture');
            picture.src = item.picture;
            picture.alt = item.file || '';
            node.append(picture);
          } else if (item.file) {
            node.append(el('div', 'file', '📄 ' + item.file));
          }
          if (item.failure) node.append(el('div', 'failure', item.failure));
          if (item.retry) {
            node.append(button(words.retry, (event) => {
              event.target.disabled = true;
              act({ act: 'retry', id: item.id }).then((done) => { if (!done) event.target.disabled = false; });
            }, 'retry'));
          }
          return node;
        }

        // A kitten's markdown as the Mac read it, built as nodes and never markup. Only web addresses are links, and
        // tapping one shows where it goes, in full, before anything opens it.
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
          // No href, so nothing but ask() can follow it: not a long press, a middle click or a second window.
          const link = el('span', 'link');
          link.setAttribute('role', 'link');
          link.tabIndex = 0;
          link.append(node);
          link.onclick = () => ask(part.link);
          link.onkeydown = (event) => { if (event.key === 'Enter') ask(part.link); };
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

        // Only Open, a link you tap yourself, goes anywhere.
        function ask(link) {
          $('linktitle').textContent = words.openLink(new URL(link).host);
          $('linkaddress').textContent = link;
          $('linkaddress').scrollTop = 0;
          $('linkopen').href = link;
          $('linksheet').hidden = false;
        }

        function button(label, onclick, className) {
          const node = el('button', className, label);
          node.type = 'button';
          node.onclick = onclick;
          return node;
        }

        function card(item) {
          const node = el('article', 'card ' + item.kind);
          const header = el('header');
          header.append(cat(item.cat), el('span', 'title', item.title));
          if (item.at) header.append(el('time', null, time(item.at)));
          node.append(header, el('p', 'text', item.text));
          if (item.answer) node.append(el('p', 'answer', item.answer));
          if (item.kind === 'question') question(item, node);
          const buttons = el('div', 'buttons');
          if (item.kind === 'approval') {
            for (const choice of item.choices) {
              buttons.append(button(choice.label, (event) => {
                buttons.querySelectorAll('button').forEach((b) => { b.disabled = true; });
                act({ act: 'approval', id: item.id, value: choice.value });
              }));
            }
          }
          if (item.kind === 'report') {
            buttons.append(button(item.choices[0].label, () => go(item.open)));
            if (item.done) buttons.append(button(words.done, () => act({ act: 'done', id: item.id })));
          }
          if (buttons.childElementCount) node.append(buttons);
          if (item.footer) node.append(el('p', 'footer', item.footer));
          return node;
        }

        // Every part at once, since T3 takes them together. A single choice with nothing to type goes on the tap.
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
            if (parts.length > 1 || part.text !== item.text) box.append(el('p', 'text', (parts.length > 1 ? (index + 1) + ' of ' + parts.length + ': ' : '') + part.text));
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

        // What's picked of a part's choices, which is nothing while it holds your own words.
        function chosen(part, answer) {
          return answer.every((value) => part.choices.some((choice) => choice.value === value)) ? answer : [];
        }

        function mark(button, picked) {
          button.classList.toggle('picked', picked);
          button.setAttribute('aria-pressed', String(picked));
        }

        $('back').onclick = () => { if (view && view.back) go(view.back); };
        $('link').onclick = () => { if (view && view.link) go(view.link.open); };
        $('linkcancel').onclick = () => { $('linksheet').hidden = true; };
        $('linkopen').onclick = () => { $('linksheet').hidden = true; };

        $('box').onsubmit = async (event) => {
          event.preventDefault();
          const text = $('words').value.trim();
          if ((!text && !attached) || uploading) return;
          $('send').disabled = true;
          const done = await act({ act: 'send', key, text, also: !$('alsolabel').hidden && $('also').checked, file: attached && attached.id });
          $('send').disabled = false;
          if (!done) return;
          $('words').value = '';
          $('also').checked = false;
          unattach();
          fit();
          if (done.open) go(done.open);
        };

        // A photo or file goes to the Mac first, so the message itself stays small. A photo is made smaller here,
        // since the Mac only ever sends a picture the size of a screenshot.
        let attached = null;
        let uploading = false;
        $('attach').onclick = () => $('pick').click();
        $('camera').onclick = () => $('snap').click();
        for (const id of ['pick', 'snap']) {
          $(id).onchange = () => {
            const file = $(id).files[0];
            $(id).value = '';
            if (file) attach(file);
          };
        }
        $('unattach').onclick = unattach;
        $('words').addEventListener('paste', (event) => {
          const file = [...(event.clipboardData ? event.clipboardData.files : [])][0];
          if (!file || !view || !view.box || !view.box.files) return;
          event.preventDefault();
          attach(file);
        });

        async function attach(file) {
          const isPicture = file.type.startsWith('image/');
          if (!isPicture && file.type !== 'application/pdf') return banner(words.cantRead);
          uploading = true;
          $('send').disabled = true;
          try {
            const blob = isPicture ? await shrink(file) : file;
            const name = isPicture ? (file.name || 'photo').replace(/\.[^.]*$/, '') + '.jpg' : file.name;
            if (blob.size > 10 * 1024 * 1024) return banner(words.tooBig);
            const response = await fetch('/file', {
              method: 'POST', cache: 'no-store', body: blob,
              headers: headers({ 'Content-Type': blob.type || 'application/octet-stream', 'X-Shades': '1', 'X-Name': encodeURIComponent(name) }),
            });
            if (response.status === 401) return pairing();
            if (!response.ok) return banner(response.status === 413 ? words.tooBig : words.unreachable);
            unattach();
            attached = { id: (await response.json()).id, name, picture: isPicture ? await preview(blob) : null };
            $('attachedname').textContent = name;
            if (attached.picture) $('attachedpicture').src = attached.picture; else $('attachedpicture').removeAttribute('src');
            $('attached').hidden = false;
            banner('');
          } catch (error) {
            banner(words.unreachable);
          } finally {
            uploading = false;
            $('send').disabled = !(view && view.box && view.box.ready);
          }
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
          attached = null;
          $('attached').hidden = true;
          $('attachedpicture').removeAttribute('src');
        }

        async function shrink(file) {
          const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
          const scale = Math.min(1, 2048 / Math.max(bitmap.width, bitmap.height));
          const canvas = document.createElement('canvas');
          canvas.width = Math.round(bitmap.width * scale);
          canvas.height = Math.round(bitmap.height * scale);
          canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
          return new Promise((resolve, reject) => canvas.toBlob((blob) => blob ? resolve(blob) : reject(new Error('no picture')), 'image/jpeg', 0.85));
        }

        function fit() {
          const words = $('words');
          words.style.height = 'auto';
          words.style.height = words.scrollHeight + 'px';
        }
        $('words').addEventListener('input', fit);

        $('pairform').onsubmit = async (event) => {
          event.preventDefault();
          if (await pair($('code').value)) start();
        };

        document.addEventListener('visibilitychange', () => {
          if (document.visibilityState === 'visible' && view && conversation(key)) act({ act: 'seen', key }, true);
        });

        start();
        """#

    static let manifest = """
        {"name": "Shades", "short_name": "Shades", "start_url": "/?key=home", "scope": "/", "display": "standalone",
         "background_color": "#1d1d1f", "theme_color": "#1d1d1f", "icons": [{"src": "/icon.png", "sizes": "180x180", "type": "image/png"}]}
        """

    /// Runs on the phone even with the page closed. Each push says only who and what kind, and tapping it opens
    /// the page of the thread it's about.
    static let worker = #"""
        'use strict';
        self.addEventListener('push', (event) => {
          let message = {};
          try { message = event.data ? event.data.json() : {}; } catch (error) {}
          event.waitUntil(self.registration.showNotification(message.title || 'Shades', { tag: message.tag, icon: '/icon.png', data: { key: message.key } }));
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
