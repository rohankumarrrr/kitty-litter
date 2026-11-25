enum PhoneScriptWorld {
    static let browser = #"""
        (() => {
          'use strict';
          const native = __native;
          let clock = 0;
          const timers = new Map();
          let timerCount = 0;
          Date.now = () => native.startedAt + clock;
          globalThis.setTimeout = (fn, ms, ...args) => {
            timerCount += 1;
            timers.set(timerCount, { at: clock + Math.max(0, Number(ms) || 0), fn: () => fn(...args), every: 0, source: String(fn) });
            return timerCount;
          };
          globalThis.setInterval = (fn, ms, ...args) => {
            timerCount += 1;
            const every = Math.max(1, Number(ms) || 0);
            timers.set(timerCount, { at: clock + every, fn: () => fn(...args), every, source: String(fn) });
            return timerCount;
          };
          globalThis.clearTimeout = (id) => { timers.delete(id); };
          globalThis.clearInterval = globalThis.clearTimeout;
          const nextTimer = () => {
            let found = null;
            for (const [id, timer] of timers) if (!found || timer.at < found[1].at) found = [id, timer];
            return found;
          };
          globalThis.__clock = () => clock;
          globalThis.__nextTimerAt = () => { const next = nextTimer(); return next ? next[1].at : -1; };
          globalThis.__fireNextTimer = () => {
            const [id, timer] = nextTimer();
            clock = Math.max(clock, timer.at);
            if (timer.every) timer.at += timer.every; else timers.delete(id);
            timer.fn();
          };
          globalThis.__setClock = (at) => { clock = Math.max(clock, at); };
          globalThis.__timersDue = () => [...timers.values()].filter((timer) => timer.at <= clock).length;
          globalThis.__timers = () => [...timers.values()].map((timer) => (timer.at - clock) + ' ' + timer.source.replace(/\s+/g, ' ').slice(0, 60)).sort().join(' | ');

          globalThis.console = { log: (...parts) => native.log(parts.map(String).join(' ')), error: (...parts) => native.log(parts.map(String).join(' ')) };

          class DOMException extends Error {
            constructor(message, name) { super(message); this.name = name; }
          }
          globalThis.DOMException = DOMException;

          class Event {
            constructor(type, init = {}) {
              Object.assign(this, init);
              this.type = type;
              this.bubbles = Boolean(init.bubbles);
              this.cancelable = Boolean(init.cancelable);
              this.defaultPrevented = false;
              this.target = null;
              this.currentTarget = null;
              this.stopped = false;
            }
            preventDefault() { if (this.cancelable) this.defaultPrevented = true; }
            stopPropagation() { this.stopped = true; }
          }
          globalThis.Event = Event;
          globalThis.KeyboardEvent = class extends Event {};
          globalThis.MouseEvent = class extends Event {};

          class Target {
            constructor() { this.listeners = {}; }
            addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); }
            removeEventListener(type, fn) { this.listeners[type] = (this.listeners[type] || []).filter((other) => other !== fn); }
            get eventParent() { return null; }
            dispatchEvent(event) {
              if (!event.target) event.target = this;
              for (let node = this; node; node = event.bubbles ? node.eventParent : null) {
                event.currentTarget = node;
                const handler = node['on' + event.type];
                if (typeof handler === 'function') handler.call(node, event);
                for (const fn of [...(node.listeners[event.type] || [])]) fn.call(node, event);
                if (event.stopped) break;
              }
              return !event.defaultPrevented;
            }
          }

          class Node extends Target {
            constructor() { super(); this.parentNode = null; this.childNodes = []; }
            get eventParent() { return this.parentNode || (this === document.documentElement ? document : null); }
            get firstChild() { return this.childNodes[0] || null; }
            get lastChild() { return this.childNodes[this.childNodes.length - 1] || null; }
            get nextSibling() { return this.parentNode ? this.parentNode.childNodes[this.parentNode.childNodes.indexOf(this) + 1] || null : null; }
            get previousSibling() { return this.parentNode ? this.parentNode.childNodes[this.parentNode.childNodes.indexOf(this) - 1] || null : null; }
            get parentElement() { return this.parentNode instanceof Element ? this.parentNode : null; }
            remove() {
              if (!this.parentNode) return;
              const siblings = this.parentNode.childNodes;
              siblings.splice(siblings.indexOf(this), 1);
              this.parentNode = null;
            }
            contains(other) {
              for (let node = other; node; node = node.parentNode) if (node === this) return true;
              return false;
            }
          }

          class Text extends Node {
            constructor(data) { super(); this.data = String(data); this.nodeType = 3; }
            get textContent() { return this.data; }
            set textContent(text) { this.data = String(text); }
          }

          const adopt = (node) => {
            const adopted = node instanceof Node ? node : new Text(node);
            adopted.remove();
            return adopted;
          };

          const named = new Map();
          const reflected = { id: 'id', className: 'class', type: 'type', placeholder: 'placeholder', src: 'src', alt: 'alt', href: 'href', htmlFor: 'for', name: 'name', accept: 'accept' };
          const voids = new Set(['meta', 'link', 'input', 'br', 'img', 'hr']);

          class ClassList {
            constructor(element) { this.element = element; }
            get names() { return (this.element.getAttribute('class') || '').split(/\s+/).filter(Boolean); }
            set names(list) { this.element.setAttribute('class', list.join(' ')); }
            contains(name) { return this.names.includes(name); }
            add(...names) { this.names = [...new Set([...this.names, ...names])]; }
            remove(...names) { this.names = this.names.filter((name) => !names.includes(name)); }
            toggle(name, force) {
              const on = force === undefined ? !this.contains(name) : Boolean(force);
              if (on) this.add(name); else this.remove(name);
              return on;
            }
          }

          class Element extends Node {
            constructor(tag) {
              super();
              this.localName = tag.toLowerCase();
              this.tagName = tag.toUpperCase();
              this.nodeType = 1;
              this.attrs = new Map();
              this.dataset = {};
              this.style = { setProperty(name, value) { this[name] = String(value); }, removeProperty(name) { delete this[name]; }, getPropertyValue(name) { return this[name] || ''; } };
              this.classList = new ClassList(this);
              this.disabled = false;
              this.checked = false;
              this.open = false;
              this.files = [];
              this.scrollTop = 0;
              this.scrollHeight = 0;
              this.tabIndex = -1;
              this.textWrites = 0;
              this.ownValue = '';
            }
            get hidden() { return this.attrs.has('hidden'); }
            set hidden(on) { if (on) this.attrs.set('hidden', ''); else this.attrs.delete('hidden'); }
            get value() { return this.ownValue; }
            set value(text) { this.ownValue = String(text); }
            getAttribute(name) { return this.attrs.has(name) ? this.attrs.get(name) : null; }
            hasAttribute(name) { return this.attrs.has(name); }
            setAttribute(name, value) {
              if (name === 'id') named.set(String(value), this);
              this.attrs.set(name, String(value));
              if (name.startsWith('data-')) this.dataset[name.slice(5).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = String(value);
              if (name === 'disabled') this.disabled = true;
              if (name === 'checked') this.checked = true;
              if (name === 'value') this.ownValue = String(value);
            }
            removeAttribute(name) { this.attrs.delete(name); }
            get children() { return this.childNodes.filter((node) => node instanceof Element); }
            get childElementCount() { return this.children.length; }
            get firstElementChild() { return this.children[0] || null; }
            get textContent() { return this.childNodes.map((node) => node.textContent).join(''); }
            set textContent(text) {
              this.textWrites += 1;
              this.childNodes.forEach((node) => { node.parentNode = null; });
              this.childNodes = text === '' || text == null ? [] : [Object.assign(new Text(text), { parentNode: this })];
            }
            get innerText() { return this.textContent; }
            set innerHTML(markup) { throw new Error('innerHTML would read words as markup: ' + String(markup).slice(0, 40)); }
            get innerHTML() { throw new Error('innerHTML'); }
            get outerHTML() {
              const attrs = [...this.attrs].map(([name, value]) => ' ' + name + (value === '' ? '' : '="' + value + '"')).join('');
              return '<' + this.localName + attrs + '>' + this.childNodes.map((node) => node instanceof Element ? node.outerHTML : node.data).join('') + '</' + this.localName + '>';
            }
            appendChild(node) { this.append(node); return node; }
            append(...nodes) {
              for (const node of nodes.map(adopt)) { node.parentNode = this; this.childNodes.push(node); }
            }
            prepend(...nodes) {
              const adopted = nodes.map(adopt);
              adopted.forEach((node) => { node.parentNode = this; });
              this.childNodes.unshift(...adopted);
            }
            insertBefore(node, before) {
              const adopted = adopt(node);
              const at = before ? this.childNodes.indexOf(before) : -1;
              adopted.parentNode = this;
              if (at < 0) this.childNodes.push(adopted); else this.childNodes.splice(at, 0, adopted);
              return adopted;
            }
            after(...nodes) {
              const parent = this.parentNode;
              if (!parent) return;
              const next = this.nextSibling;
              for (const node of nodes) parent.insertBefore(node, next);
            }
            replaceChildren(...nodes) {
              this.childNodes.forEach((node) => { node.parentNode = null; });
              this.childNodes = [];
              this.append(...nodes);
            }
            get descendants() {
              const found = [];
              const walk = (node) => {
                for (const child of node.childNodes) {
                  if (!(child instanceof Element)) continue;
                  found.push(child);
                  walk(child);
                }
              };
              walk(this);
              return found;
            }
            querySelectorAll(selector) { return this.descendants.filter((node) => matches(node, selector)); }
            querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
            matches(selector) { return matches(this, selector); }
            closest(selector) {
              for (let node = this; node instanceof Element; node = node.parentNode) if (matches(node, selector)) return node;
              return null;
            }
            getElementById(id) {
              const node = named.get(id);
              return node && node !== this && this.contains(node) && node.id === id ? node : this.descendants.find((other) => other.id === id) || null;
            }
            getBoundingClientRect() { return { top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0, x: 0, y: 0 }; }
            getClientRects() { return []; }
            scrollIntoView() { native.scrolledTo(this.dataset.id || this.id || ''); }
            focus() { document.activeElement = this; }
            blur() { if (document.activeElement === this) document.activeElement = document.body; }
            click() {
              if (this.disabled) return;
              if (this.localName === 'input' && this.type === 'checkbox') this.checked = !this.checked;
              const go = this.dispatchEvent(new Event('click', { bubbles: true, cancelable: true }));
              if (!go) return;
              const form = this.closest('form');
              if (this.localName === 'button' && (this.getAttribute('type') || 'submit') === 'submit' && form) form.requestSubmit();
              if (this.localName === 'input' && this.type === 'file') native.picking();
              if (this.localName === 'a' && this.href) native.followed(this.href, this.getAttribute('target') || '');
            }
            requestSubmit() { this.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); }
            showModal() {
              if (this.open) throw new DOMException('already open', 'InvalidStateError');
              this.open = true;
              this.modal = true;
              const first = this.querySelector('[autofocus]');
              if (first) first.focus();
            }
            close() {
              if (!this.open) return;
              this.open = false;
              this.modal = false;
              this.dispatchEvent(new Event('close'));
            }
          }
          for (const [property, attribute] of Object.entries(reflected)) {
            Object.defineProperty(Element.prototype, property, {
              get() { return this.getAttribute(attribute) || ''; },
              set(value) { this.setAttribute(attribute, value); },
            });
          }

          const parseCompound = (text) => {
            const parts = { tag: null, id: null, classes: [], attrs: [], not: [] };
            const pattern = /^(\*|[a-zA-Z][a-zA-Z0-9-]*)|#([\w-]+)|\.([\w-]+)|\[([\w-]+)(?:=["']?([^"'\]]*)["']?)?\]|:not\(([^)]*)\)/g;
            let match;
            let used = 0;
            while ((match = pattern.exec(text)) && match[0]) {
              used += match[0].length;
              if (match[1] && match[1] !== '*') parts.tag = match[1].toLowerCase();
              if (match[2]) parts.id = match[2];
              if (match[3]) parts.classes.push(match[3]);
              if (match[4]) parts.attrs.push([match[4], match[5]]);
              if (match[6]) parts.not.push(parseCompound(match[6]));
            }
            if (used !== text.length) throw new Error('the stand-in browser reads no selector like ' + text);
            return parts;
          };
          const fits = (node, parts) => node instanceof Element
            && (!parts.tag || node.localName === parts.tag)
            && (!parts.id || node.id === parts.id)
            && parts.classes.every((name) => node.classList.contains(name))
            && parts.attrs.every(([name, value]) => value === undefined ? node.hasAttribute(name) : node.getAttribute(name) === value)
            && parts.not.every((inner) => !fits(node, inner));
          const parseChain = (selector) => {
            const tokens = selector.trim().replace(/\s*>\s*/g, ' > ').split(/\s+/);
            const chain = [];
            let combinator = ' ';
            for (const token of tokens) {
              if (token === '>') { combinator = '>'; continue; }
              chain.push({ combinator, parts: parseCompound(token) });
              combinator = ' ';
            }
            return chain;
          };
          const fitsChain = (node, chain, index) => {
            if (!fits(node, chain[index].parts)) return false;
            if (index === 0) return true;
            if (chain[index].combinator === '>') return fitsChain(node.parentNode, chain, index - 1);
            for (let up = node.parentNode; up instanceof Element; up = up.parentNode) if (fitsChain(up, chain, index - 1)) return true;
            return false;
          };
          const matches = (node, selector) => selector.split(',').some((part) => {
            const chain = parseChain(part);
            return fitsChain(node, chain, chain.length - 1);
          });

          class Document extends Target {
            constructor() {
              super();
              this.visibilityState = 'visible';
              this.activeElement = null;
              this.documentElement = null;
            }
            get eventParent() { return globalThis.window; }
            get body() { return this.documentElement.querySelector('body'); }
            get head() { return this.documentElement.querySelector('head'); }
            createElement(tag) { return new Element(tag); }
            createElementNS(space, tag) { return new Element(tag); }
            createTextNode(text) { return new Text(text); }
            getElementById(id) { return this.documentElement.getElementById(id); }
            querySelectorAll(selector) { return [this.documentElement, ...this.documentElement.descendants].filter((node) => matches(node, selector)); }
            querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
            getSelection() { return { isCollapsed: true, anchorNode: null }; }
          }
          const document = new Document();
          globalThis.document = document;

          const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", '#39': "'" };
          const unescape = (text) => text.replace(/&(amp|lt|gt|quot|apos|#39);/g, (_, name) => entities[name]);
          globalThis.__build = (html) => {
            const root = new Element('html');
            const stack = [root];
            const tokens = /<!--[\s\S]*?-->|<!doctype[^>]*>|<\/([a-zA-Z0-9-]+)\s*>|<([a-zA-Z0-9-]+)((?:\s+[^\s=>\/]+(?:="[^"]*")?)*)\s*(\/?)>|([^<]+)/gi;
            let match;
            while ((match = tokens.exec(html))) {
              const top = stack[stack.length - 1];
              if (match[1]) {
                const name = match[1].toLowerCase();
                if (name === 'html') continue;
                while (stack.length > 1) if (stack.pop().localName === name) break;
              } else if (match[2]) {
                const name = match[2].toLowerCase();
                if (name === 'html') continue;
                const node = new Element(name);
                for (const attribute of match[3].matchAll(/([^\s=]+)(?:="([^"]*)")?/g)) node.setAttribute(attribute[1], unescape(attribute[2] || ''));
                if (node.hasAttribute('tabindex')) node.tabIndex = Number(node.getAttribute('tabindex'));
                top.append(node);
                if (!match[4] && !voids.has(name)) stack.push(node);
              } else if (match[5] && top !== root) {
                top.append(new Text(unescape(match[5])));
              }
            }
            document.documentElement = root;
            root.clientHeight = 844;
            document.activeElement = document.body;
          };

          const parseAddress = (address) => {
            const [beforeHash, ...hash] = String(address).split('#');
            const [path, ...search] = beforeHash.split('?');
            return { path, search: search.length ? '?' + search.join('?') : '', hash: hash.length ? '#' + hash.join('#') : '' };
          };
          const place = { pathname: '/', search: '', hash: '' };
          globalThis.location = {
            hostname: 'mac.example',
            host: 'mac.example',
            protocol: 'https:',
            get pathname() { return place.pathname; },
            get search() { return place.search; },
            get hash() { return place.hash; },
            set hash(text) {
              const next = text === '' || text.startsWith('#') ? text : '#' + text;
              if (next === place.hash) return;
              place.hash = next;
              setTimeout(() => globalThis.window.dispatchEvent(new Event('hashchange')), 0);
            },
            get href() { return 'https://mac.example' + place.pathname + place.search + place.hash; },
          };
          const move = (address) => {
            const next = parseAddress(address);
            if (next.path) place.pathname = next.path;
            place.search = next.search;
            place.hash = next.hash;
          };
          globalThis.__open = (address) => move(address);
          globalThis.history = {
            state: null,
            length: 1,
            pushState(state, title, address) { this.state = state; this.length += 1; move(address); },
            replaceState(state, title, address) { this.state = state; move(address); },
            back() {},
          };

          const storage = new Map(Object.entries(JSON.parse(native.storage)));
          globalThis.localStorage = {
            getItem: (name) => storage.has(name) ? storage.get(name) : null,
            setItem: (name, value) => { storage.set(name, String(value)); native.stored(JSON.stringify(Object.fromEntries(storage))); },
            removeItem: (name) => { storage.delete(name); native.stored(JSON.stringify(Object.fromEntries(storage))); },
            clear: () => { storage.clear(); native.stored('{}'); },
          };

          globalThis.URLSearchParams = class {
            constructor(text = '') {
              this.pairs = String(text).replace(/^\?/, '').split('&').filter(Boolean).map((pair) => {
                const [name, ...value] = pair.split('=');
                const read = (part) => decodeURIComponent(part.replace(/\+/g, ' '));
                return [read(name), read(value.join('='))];
              });
            }
            get(name) { const found = this.pairs.find((pair) => pair[0] === name); return found ? found[1] : null; }
            has(name) { return this.pairs.some((pair) => pair[0] === name); }
          };
          globalThis.URL = class {
            constructor(address) {
              const match = /^([a-zA-Z][a-zA-Z0-9+.-]*:)\/\/([^/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$/.exec(String(address));
              if (!match) throw new TypeError('not an address: ' + address);
              this.protocol = match[1].toLowerCase();
              this.host = match[2].replace(/^[^@]*@/, '').toLowerCase();
              this.hostname = this.host.replace(/:\d+$/, '');
              this.pathname = match[3] || '/';
              this.search = match[4] || '';
              this.hash = match[5] || '';
              this.href = String(address);
            }
          };

          globalThis.TextDecoderStream = class {};
          globalThis.AbortController = class {
            constructor() {
              const signal = new Target();
              signal.aborted = false;
              this.signal = signal;
            }
            abort() {
              if (this.signal.aborted) return;
              this.signal.aborted = true;
              this.signal.dispatchEvent(new Event('abort'));
            }
          };

          const calls = new Map();
          const aborted = () => new DOMException('The operation was aborted.', 'AbortError');
          const response = (status, text, call) => ({
            status,
            ok: status >= 200 && status < 300,
            headers: { get: () => null },
            json: async () => JSON.parse(text),
            text: async () => text,
            body: call ? { pipeThrough: () => ({ getReader: () => ({ read: () => read(call) }) }) } : null,
          });
          const read = (call) => new Promise((resolve, reject) => {
            if (call.error) return reject(call.error);
            if (call.chunks.length) return resolve({ value: call.chunks.shift(), done: false });
            if (call.done) return resolve({ value: undefined, done: true });
            call.reads.push({ resolve, reject });
          });
          globalThis.fetch = (address, options = {}) => new Promise((resolve, reject) => {
            const signal = options.signal;
            if (signal && signal.aborted) return reject(aborted());
            const id = native.request(options.method || 'GET', String(address), JSON.stringify(options.headers || {}), options.body == null ? '' : String(options.body));
            const call = { resolve, reject, answered: false, chunks: [], reads: [], done: false, error: null };
            calls.set(id, call);
            if (signal) {
              signal.addEventListener('abort', () => {
                if (call.error || call.done) return;
                call.error = aborted();
                native.closed(id);
                if (!call.answered) reject(call.error);
                call.reads.splice(0).forEach((waiting) => waiting.reject(call.error));
              });
            }
          });
          globalThis.__answer = (id, status, text) => {
            const call = calls.get(id);
            if (!call || call.answered || call.error) return false;
            call.answered = true;
            call.done = true;
            call.resolve(response(status, text, null));
            return true;
          };
          globalThis.__stream = (id) => {
            const call = calls.get(id);
            if (!call || call.answered || call.error) return false;
            call.answered = true;
            call.resolve(response(200, '', call));
            return true;
          };
          globalThis.__chunk = (id, text) => {
            const call = calls.get(id);
            if (!call || call.done || call.error) return false;
            const waiting = call.reads.shift();
            if (waiting) waiting.resolve({ value: text, done: false }); else call.chunks.push(text);
            return true;
          };
          globalThis.__end = (id) => {
            const call = calls.get(id);
            if (!call || call.done || call.error) return false;
            call.done = true;
            call.reads.splice(0).forEach((waiting) => waiting.resolve({ value: undefined, done: true }));
            return true;
          };
          globalThis.__fail = (id) => {
            const call = calls.get(id);
            if (!call || call.done || call.error) return false;
            call.error = new TypeError('Load failed');
            if (!call.answered) call.reject(call.error);
            call.reads.splice(0).forEach((waiting) => waiting.reject(call.error));
            return true;
          };

          const view = new Target();
          Object.assign(view, {
            innerHeight: 844,
            innerWidth: 390,
            scrollX: 0,
            scrollY: 0,
            scrollTo(x, y) { this.scrollY = Math.max(0, Number(y) || 0); },
            scrollBy(x, y) { this.scrollY = Math.max(0, this.scrollY + (Number(y) || 0)); },
            open(address, target, features) { native.followed(String(address), String(target || '') + ' ' + String(features || '')); return null; },
          });
          globalThis.window = new Proxy(globalThis, {
            get: (world, name) => name in view ? (typeof view[name] === 'function' ? view[name].bind(view) : view[name]) : world[name],
            set: (world, name, value) => { if (name in view) view[name] = value; else world[name] = value; return true; },
            has: (world, name) => name in view || name in world,
          });
          for (const name of ['addEventListener', 'removeEventListener', 'dispatchEvent', 'scrollTo', 'scrollBy', 'open']) globalThis[name] = view[name].bind(view);
          for (const name of ['innerHeight', 'innerWidth', 'scrollX', 'scrollY']) Object.defineProperty(globalThis, name, { get: () => view[name], set: (value) => { view[name] = value; } });
          globalThis.navigator = { userAgent: 'iPhone', standalone: native.standalone, onLine: true };
          globalThis.matchMedia = (query) => ({ matches: query.includes('standalone') && native.standalone, addEventListener() {} });
          globalThis.getComputedStyle = () => ({ lineHeight: '20px', visibility: 'visible', willChange: 'auto' });
          globalThis.__visible = (visible) => {
            document.visibilityState = visible ? 'visible' : 'hidden';
            document.dispatchEvent(new Event('visibilitychange'));
          };

          const shown = (node) => {
            for (let up = node; up instanceof Element; up = up.parentNode) {
              if (up.hidden || (up.localName === 'dialog' && !up.open)) return false;
            }
            return true;
          };
          const reachable = (node) => {
            const sheet = document.querySelectorAll('dialog').find((dialog) => dialog.modal);
            return !sheet || sheet.contains(node);
          };
          const said = (node, text) => text == null || node.textContent.trim() === text || (node.getAttribute('aria-label') || '').split(', ')[0] === text;
          const find = (selector, text) => {
            const nodes = document.querySelectorAll(selector).filter((node) => said(node, text));
            if (!nodes.length) return 'nothing is ' + selector + (text == null ? '' : ' saying ' + text);
            const seen = nodes.filter(shown);
            if (!seen.length) return selector + ' is hidden';
            const open = seen.filter(reachable);
            if (!open.length) return selector + ' is covered by a sheet';
            return open[0];
          };
          globalThis.__tap = (selector, text) => {
            const node = find(selector, text);
            if (typeof node === 'string') return node;
            if (node.disabled) return selector + ' is turned off';
            node.focus();
            node.click();
            return 'tapped';
          };
          globalThis.__type = (selector, text) => {
            const node = find(selector, null);
            if (typeof node === 'string') return node;
            node.focus();
            node.value = node.value + text;
            node.dispatchEvent(new Event('input', { bubbles: true }));
            return 'typed';
          };
          globalThis.__press = (selector, text, key) => {
            const node = find(selector, text);
            if (typeof node === 'string') return node;
            node.focus();
            const go = node.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
            if (!go) return 'pressed';
            if (node.localName === 'button' && (key === 'Enter' || key === ' ')) node.click();
            else if (node.localName === 'a' && key === 'Enter') node.click();
            else if (node.localName === 'textarea' && key === 'Enter') {
              node.value += '\n';
              node.dispatchEvent(new Event('input', { bubbles: true }));
            } else if (node.localName === 'input' && key === 'Enter' && node.closest('form')) node.closest('form').requestSubmit();
            return 'pressed';
          };
        })();
        """#
}
