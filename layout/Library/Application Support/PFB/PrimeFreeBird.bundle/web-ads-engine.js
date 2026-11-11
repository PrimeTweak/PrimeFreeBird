// Block web ads, page engine: applies at the start of each page what WebKit's content blockers
// cannot express (page scripts, hiding by text, styles, policies), from web-ads-page.json.
// It runs before the page's own scripts and reports what it did to the pfbWebAds handler.
function pfbWebAdsEngine(data) {
    "use strict";
    const host = String(location.hostname || "").toLowerCase();
    if (!host) {
        return;
    }

    // A site name.* matches that name under any ending of one or two labels.
    const labels = host.split(".");
    const keys = new Set();
    for (let start = 0; start < labels.length; start++) {
        keys.add(labels.slice(start).join("."));
        for (let ending = 1; ending <= 2 && labels.length - ending > start; ending++) {
            keys.add(labels.slice(start, labels.length - ending).join(".") + ".*");
        }
    }
    const matches = (sites) => sites.some((site) => keys.has(site));
    if (matches(data.x) || matches(data.trusted)) {
        return;
    }

    // The page's own scripts may wrap these later; the engine keeps the originals.
    const N = {
        setTimeout: window.setTimeout.bind(window),
        listen: EventTarget.prototype.addEventListener,
        defineProperty: Object.defineProperty,
        descriptor: Object.getOwnPropertyDescriptor,
        fnToString: Function.prototype.toString,
        createElement: Document.prototype.createElement,
        MutationObserver: window.MutationObserver,
        parse: JSON.parse,
    };
    const listen = (target, type, handler, options) => N.listen.call(target, type, handler, options);
    const channel = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pfbWebAds;
    const post = (message) => {
        try {
            if (channel) {
                channel.postMessage(message);
            }
        } catch (error) {
            // A page that breaks the channel only loses the report.
        }
    };
    const magic = "pfb" + Math.random().toString(36).slice(2, 10);
    const mark = "data-" + magic;
    const report = { t: window.top === window ? "page" : "frame", host, rules: 0, scripts: [], errors: [],
        hidden: 0, removed: 0, styled: 0, csp: 0 };
    const fail = (what, error) => {
        if (report.errors.length < 6) {
            report.errors.push(String(what).slice(0, 80) + ": " + String((error && error.message) || error).slice(0, 80));
        }
    };

    const chosen = new Set();
    if (!matches(data.generichide)) {
        data.generic.forEach((id) => chosen.add(id));
    }
    for (const key of keys) {
        if (Object.prototype.hasOwnProperty.call(data.hosts, key)) {
            data.hosts[key].forEach((id) => chosen.add(id));
        }
    }
    const rules = [];
    for (const id of chosen) {
        const rule = data.rules[id];
        const last = rule[rule.length - 1];
        if (!Array.isArray(last)) {
            rules.push(rule);
        } else if (!matches(last)) {
            rules.push(rule.slice(0, -1));
        }
    }
    report.rules = rules.length;

    // Patterns: /regex/flags, or text matched anywhere; an empty one matches everything.
    const pattern = (text) => {
        if (text === undefined || text === "") {
            return null;
        }
        const literal = /^\/(.+)\/([dimsuy]*)$/.exec(text);
        if (literal) {
            return new RegExp(literal[1], literal[2]);
        }
        return new RegExp(String(text).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
    };
    const test = (regex, text) => regex === null || regex.test(text);
    const needle = (text) => {
        const negated = typeof text === "string" && text.startsWith("!");
        return { negated, regex: pattern(negated ? text.slice(1) : text) };
    };
    const needleMatches = (wanted, text) => test(wanted.regex, text) !== wanted.negated;
    const sourceOf = (value) => {
        try {
            return typeof value === "function" ? N.fnToString.call(value) : String(value);
        } catch (error) {
            return "";
        }
    };
    const isObject = (value) => value !== null && (typeof value === "object" || typeof value === "function");
    const whenReady = (run) => {
        if (document.readyState === "loading") {
            listen(document, "DOMContentLoaded", run, { once: true });
        } else {
            run();
        }
    };
    const observe = (options, run, untilLoad) => {
        let waiting = false;
        const observer = new N.MutationObserver(() => {
            if (!waiting) {
                waiting = true;
                N.setTimeout(() => {
                    waiting = false;
                    run();
                }, 50);
            }
        });
        observer.observe(document, options);
        if (untilLoad) {
            listen(window, "load", () => observer.disconnect(), { once: true });
        }
    };

    // Scripts abort with an error the page never sees.
    let swallowing = false;
    const abort = () => {
        if (!swallowing) {
            swallowing = true;
            listen(window, "error", (event) => {
                if (String(event.message).includes(magic)) {
                    event.preventDefault();
                    event.stopImmediatePropagation();
                }
            }, true);
        }
        throw new ReferenceError(magic);
    };

    // Runs then(owner, property) on the chain's last link, once the page has made the others.
    const onChain = (chain, then) => {
        const walk = (owner, path) => {
            const dot = path.indexOf(".");
            if (dot < 0) {
                then(owner, path);
                return;
            }
            const head = path.slice(0, dot);
            const rest = path.slice(dot + 1);
            let value;
            try {
                value = owner[head];
            } catch (error) {
                return;
            }
            if (isObject(value)) {
                walk(value, rest);
                return;
            }
            const existing = N.descriptor(owner, head);
            if (existing && !existing.configurable) {
                return;
            }
            let current = value;
            N.defineProperty(owner, head, {
                configurable: true,
                enumerable: true,
                get: () => current,
                set: (next) => {
                    current = next;
                    if (isObject(next)) {
                        walk(next, rest);
                    }
                },
            });
        };
        walk(window, chain);
    };
    // Replaces a property by an accessor that calls check() on each use and keeps its value.
    const guard = (owner, property, check) => {
        let found;
        for (let link = owner; link && !found; link = Object.getPrototypeOf(link)) {
            found = N.descriptor(link, property);
        }
        const own = N.descriptor(owner, property);
        if (own && !own.configurable) {
            return;
        }
        let value = found && !found.get ? found.value : undefined;
        N.defineProperty(owner, property, {
            configurable: true,
            enumerable: found ? found.enumerable : true,
            get() {
                check();
                return found && found.get ? found.get.call(this) : value;
            },
            set(next) {
                check();
                if (found && found.set) {
                    found.set.call(this, next);
                } else {
                    value = next;
                }
            },
        });
    };

    const constants = {
        "undefined": () => undefined, "false": () => false, "true": () => true, "null": () => null,
        "noopFunc": () => function () {}, "trueFunc": () => function () { return true; },
        "falseFunc": () => function () { return false; }, "emptyArr": () => [], "[]": () => [],
        "emptyObj": () => ({}), "{}": () => ({}), "": () => "", "emptyStr": () => "",
    };
    const setConstant = (chain, raw) => {
        if (!Object.prototype.hasOwnProperty.call(constants, raw) && !/^-?\d+$/.test(raw)) {
            throw new Error("value " + raw + " not known");
        }
        const value = /^-?\d+$/.test(raw) ? parseInt(raw, 10) : constants[raw]();
        onChain(chain, (owner, property) => {
            const existing = N.descriptor(owner, property);
            if (existing && !existing.configurable) {
                owner[property] = value;
                return;
            }
            N.defineProperty(owner, property, {
                configurable: true,
                enumerable: existing ? existing.enumerable : true,
                get: () => value,
                set: () => {},
            });
        });
    };

    const scriptText = (script) => {
        const text = script.textContent;
        if (text.trim()) {
            return text;
        }
        const inline = /^data:([^,]*),(.*)$/.exec(script.src.trim());
        if (!inline) {
            return "";
        }
        try {
            return inline[1].endsWith(";base64") ? atob(inline[2]) : decodeURIComponent(inline[2]);
        } catch (error) {
            return "";
        }
    };
    const abortCurrentScript = (target, text, context) => {
        const wanted = pattern(text);
        const where = pattern(context);
        const parts = String(target).split(".");
        const property = parts.pop();
        let owner = window;
        for (const part of parts) {
            owner = owner[part];
            if (!isObject(owner)) {
                return;
            }
        }
        guard(owner, property, () => {
            const script = document.currentScript;
            if (script instanceof HTMLScriptElement && test(where, script.src) && test(wanted, scriptText(script))) {
                abort();
            }
        });
    };

    // A stack in uBlock Origin's form: one "function url:line:1" per frame, tab separated.
    const stack = () => {
        const frames = [];
        const page = location.href.split("#")[0];
        for (let line of String(new Error(magic).stack).split(/[\n\r]+/)) {
            if (line.includes(magic)) {
                continue;
            }
            line = line.trim();
            const found = /(.*?@)?(\S+)(:\d+):\d+\)?$/.exec(line);
            if (!found) {
                continue;
            }
            let url = found[2].startsWith("(") ? found[2].slice(1) : found[2];
            url = url === page ? "inlineScript" : url.startsWith("<anonymous>") ? "injectedScript" : url;
            let name = found[1] !== undefined ? found[1].slice(0, -1) : line.slice(0, found.index).trim();
            name = name.startsWith("at") ? name.slice(2).trim() : name;
            frames.push(" " + `${name} ${url}${found[3]}:1`.trim());
        }
        frames[0] = `stackDepth:${frames.length - 1}`;
        return frames.join("\t");
    };
    const abortOnStackTrace = (chain, text) => {
        const wanted = pattern(text);
        onChain(chain, (owner, property) => guard(owner, property, () => {
            if (test(wanted, stack())) {
                abort();
            }
        }));
    };

    const defuseListeners = (type, handler) => {
        const types = pattern(type);
        const handlers = pattern(handler);
        const prototype = EventTarget.prototype;
        prototype.addEventListener = new Proxy(prototype.addEventListener, {
            apply(target, self, args) {
                const callback = args[1];
                const text = sourceOf(callback && typeof callback.handleEvent === "function" ? callback.handleEvent : callback);
                if (test(types, String(args[0])) && test(handlers, text)) {
                    return undefined;
                }
                return Reflect.apply(target, self, args);
            },
        });
    };

    const defuseTimers = (name, text, delay) => {
        const wanted = needle(text);
        const delayNegated = typeof delay === "string" && delay.startsWith("!");
        const delayValue = delay ? parseInt(delayNegated ? delay.slice(1) : delay, 10) : NaN;
        window[name] = new Proxy(window[name], {
            apply(target, self, args) {
                let defuse = needleMatches(wanted, sourceOf(args[0]));
                if (defuse && !isNaN(delayValue)) {
                    defuse = (Number(args[1]) === delayValue) !== delayNegated;
                }
                if (defuse) {
                    args[0] = function () {};
                }
                return Reflect.apply(target, self, args);
            },
        });
    };

    // Request properties: "key:pattern" pairs, a bare pattern standing for the url.
    const requestProps = (text) => {
        const wanted = [];
        for (const part of String(text || "").split(/\s+/).filter(Boolean)) {
            const pair = /^(\w+):(.+)$/.exec(part);
            if (pair && pair[1] !== "http" && pair[1] !== "https") {
                wanted.push([pair[1], pattern(pair[2])]);
            } else {
                wanted.push(["url", pattern(part)]);
            }
        }
        return wanted;
    };
    const requestMatches = (wanted, details) =>
        wanted.every(([key, regex]) => test(regex, details[key] === undefined ? "" : String(details[key])));
    const preventXhr = (text) => {
        const wanted = requestProps(text);
        if (!wanted.length) {
            return;
        }
        const prototype = XMLHttpRequest.prototype;
        const stopped = new WeakSet();
        prototype.open = new Proxy(prototype.open, {
            apply(target, self, args) {
                if (requestMatches(wanted, { method: String(args[0]).toUpperCase(), url: String(args[1]) })) {
                    stopped.add(self);
                } else {
                    stopped.delete(self);
                }
                return Reflect.apply(target, self, args);
            },
        });
        prototype.send = new Proxy(prototype.send, {
            apply(target, self, args) {
                if (!stopped.has(self)) {
                    return Reflect.apply(target, self, args);
                }
                const type = self.responseType;
                const empty = type === "" || type === "text" ? "" : null;
                const values = { readyState: 4, status: 200, statusText: "OK", response: empty, responseText: empty || "" };
                for (const key of Object.keys(values)) {
                    N.defineProperty(self, key, { configurable: true, value: values[key] });
                }
                N.setTimeout(() => {
                    self.dispatchEvent(new Event("readystatechange"));
                    self.dispatchEvent(new ProgressEvent("load"));
                    self.dispatchEvent(new ProgressEvent("loadend"));
                }, 1);
                return undefined;
            },
        });
    };
    const preventFetch = (text) => {
        const wanted = requestProps(text);
        if (!wanted.length) {
            return;
        }
        window.fetch = new Proxy(window.fetch, {
            apply(target, self, args) {
                const details = { url: "", method: "GET" };
                try {
                    const resource = args[0];
                    details.url = resource instanceof Request ? resource.url : String(resource);
                    details.method = resource instanceof Request ? resource.method : details.method;
                    if (args[1] && args[1].method) {
                        details.method = String(args[1].method).toUpperCase();
                    }
                } catch (error) {
                    // An unreadable request is let through.
                }
                if (requestMatches(wanted, details)) {
                    return Promise.resolve(new Response("", { status: 200, statusText: "OK" }));
                }
                return Reflect.apply(target, self, args);
            },
        });
    };

    // A script the parser writes is emptied before it runs.
    const removeNodeText = (name, text) => {
        const names = /^\/.+\/[a-z]*$/.test(name) ? pattern(name) : new RegExp("^" + String(name).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$", "i");
        const wanted = pattern(text);
        const handle = (node) => {
            if (names.test(node.nodeName) && test(wanted, node.textContent)) {
                node.textContent = "";
            }
        };
        const observer = new N.MutationObserver((records) => {
            for (const record of records) {
                record.addedNodes.forEach(handle);
            }
        });
        observer.observe(document, { childList: true, subtree: true });
        listen(window, "load", () => observer.disconnect(), { once: true });
    };

    const tokensOf = (text) => String(text || "").split(/\s*\|\s*/).filter(Boolean);
    const removeEverywhere = (tokens, selector, behavior, remove, defaultSelector) => {
        const names = tokensOf(tokens);
        if (!names.length) {
            return;
        }
        const target = selector || names.map(defaultSelector).join(",");
        const run = () => {
            for (const element of document.querySelectorAll(target)) {
                names.forEach((token) => remove(element, token));
            }
        };
        const stay = /\bstay\b/.test(behavior || "");
        if (/\bcomplete\b/.test(behavior || "")) {
            listen(window, "load", run, { once: true });
            return;
        }
        whenReady(run);
        listen(window, "load", run, { once: true });
        observe({ childList: true, subtree: true, attributes: true }, run, !stay);
    };
    const removeClass = (tokens, selector, behavior) => removeEverywhere(tokens, selector, behavior,
        (element, token) => element.classList.remove(token), (token) => "." + CSS.escape(token));
    const removeAttr = (tokens, selector, behavior) => removeEverywhere(tokens, selector, behavior,
        (element, token) => element.removeAttribute(token), (token) => "[" + CSS.escape(token) + "]");

    // Pruning paths: dot separated, [] for each item of an array, * for each property.
    const eachOwner = (root, path, found) => {
        const parts = String(path).split(".");
        const walk = (value, index) => {
            if (!isObject(value)) {
                return;
            }
            const part = parts[index];
            const last = index === parts.length - 1;
            if (part === "[]" || part === "*") {
                const keys = part === "[]" ? (Array.isArray(value) ? value.keys() : []) : Object.keys(value);
                for (const key of keys) {
                    if (last) {
                        found(value, key);
                    } else {
                        walk(value[key], index + 1);
                    }
                }
            } else if (last) {
                if (Object.prototype.hasOwnProperty.call(value, part)) {
                    found(value, part);
                }
            } else {
                walk(value[part], index + 1);
            }
        };
        walk(root, 0);
    };
    const onJson = (edit) => {
        JSON.parse = new Proxy(JSON.parse, {
            apply(target, self, args) {
                return edit(Reflect.apply(target, self, args));
            },
        });
        Response.prototype.json = new Proxy(Response.prototype.json, {
            apply(target, self, args) {
                return Reflect.apply(target, self, args).then(edit);
            },
        });
    };
    const jsonPrune = (prune, required) => {
        const prunePaths = String(prune || "").split(/\s+/).filter(Boolean);
        const requiredPaths = String(required || "").split(/\s+/).filter(Boolean);
        onJson((value) => {
            try {
                const present = requiredPaths.every((path) => {
                    let seen = false;
                    eachOwner(value, path, () => { seen = true; });
                    return seen;
                });
                if (present) {
                    prunePaths.forEach((path) => eachOwner(value, path, (owner, key) => delete owner[key]));
                }
            } catch (error) {
                fail("json-prune", error);
            }
            return value;
        });
    };
    // json-edit: removes what a query finds, written ..name, .name, .* and [?.path=="value"].
    const jsonQuery = (query) => {
        const steps = [];
        const reader = /\.\.([\w$-]+)|\.([\w$-]+)|\.\*|\[\?\.([\w$.-]+)\s*(==|!=)\s*("(?:[^"\\]|\\.)*"|[^\]]+)\]/y;
        for (let found; reader.lastIndex < query.length;) {
            const start = reader.lastIndex;
            found = reader.exec(query);
            if (!found || found.index !== start) {
                throw new Error("query not read");
            }
            if (found[1]) {
                steps.push(["deep", found[1]]);
            } else if (found[2]) {
                steps.push(["child", found[2]]);
            } else if (found[3]) {
                steps.push(["filter", found[3].split("."), found[4], N.parse(found[5].startsWith("\"") ? found[5] : JSON.stringify(found[5].trim()))]);
            } else {
                steps.push(["all"]);
            }
        }
        return (root) => {
            let found = [[null, null, root]];
            for (const step of steps) {
                const next = [];
                for (const [, , value] of found) {
                    if (!isObject(value)) {
                        continue;
                    }
                    if (step[0] === "child" && Object.prototype.hasOwnProperty.call(value, step[1])) {
                        next.push([value, step[1], value[step[1]]]);
                    } else if (step[0] === "all") {
                        Object.keys(value).forEach((key) => next.push([value, key, value[key]]));
                    } else if (step[0] === "deep") {
                        const visit = (node) => {
                            if (!isObject(node)) {
                                return;
                            }
                            if (Object.prototype.hasOwnProperty.call(node, step[1])) {
                                next.push([node, step[1], node[step[1]]]);
                            }
                            Object.keys(node).forEach((key) => visit(node[key]));
                        };
                        visit(value);
                    }
                }
                if (step[0] === "filter") {
                    found = found.filter(([, , value]) => {
                        let probe = value;
                        for (const key of step[1]) {
                            probe = isObject(probe) ? probe[key] : undefined;
                        }
                        return (probe === step[3]) === (step[2] === "==");
                    });
                } else {
                    found = next;
                }
            }
            const byOwner = new Map();
            for (const [owner, key] of found) {
                if (owner) {
                    byOwner.set(owner, (byOwner.get(owner) || []).concat([key]));
                }
            }
            for (const [owner, keys] of byOwner) {
                if (Array.isArray(owner)) {
                    keys.map(Number).sort((a, b) => b - a).forEach((index) => owner.splice(index, 1));
                } else {
                    keys.forEach((key) => delete owner[key]);
                }
            }
            return root;
        };
    };
    const jsonEdit = (query) => {
        const run = jsonQuery(String(query));
        onJson((value) => {
            try {
                return run(value);
            } catch (error) {
                fail("json-edit", error);
                return value;
            }
        });
    };

    const cookieValue = (name) => {
        for (const part of document.cookie.split(/\s*;\s*/)) {
            const equals = part.indexOf("=");
            if (equals > 0 && part.slice(0, equals) === name) {
                return part.slice(equals + 1);
            }
        }
        return undefined;
    };
    // A cookie that needs the server to see it reloads the page, once per session.
    const setCookie = (reloads, name, value, ...rest) => {
        const options = {};
        for (let index = 0; index < rest.length - 1; index++) {
            if (["reload", "domain", "dontOverwrite"].includes(rest[index])) {
                options[rest[index]] = rest[index + 1];
            }
        }
        const path = rest[0] === "none" ? "" : /^\//.test(rest[0] || "") ? rest[0] : "/";
        const encoded = encodeURIComponent(value === undefined ? "" : value);
        const existing = cookieValue(name);
        if (existing === encoded || (options.dontOverwrite === "1" && existing !== undefined)) {
            return;
        }
        document.cookie = name + "=" + encoded + (path ? "; path=" + path : "") +
            (options.domain ? "; domain=" + options.domain : "");
        if ((reloads || options.reload === "1") && cookieValue(name) === encoded) {
            const once = "pfb-reload-" + name;
            try {
                if (!sessionStorage.getItem(once)) {
                    sessionStorage.setItem(once, "1");
                    location.reload();
                }
            } catch (error) {
                // Without a session store the page is not reloaded.
            }
        }
    };
    const removeCookies = (name) => {
        const wanted = pattern(name);
        const remove = () => {
            const parts = location.hostname.split(".");
            for (const cookie of document.cookie.split(/\s*;\s*/)) {
                const key = cookie.split("=")[0].trim();
                if (!key || !test(wanted, key)) {
                    continue;
                }
                for (let start = 0; start <= parts.length - 1; start++) {
                    const domain = start === 0 ? "" : "; domain=." + parts.slice(start - 1).join(".");
                    for (const path of ["; path=/", ""]) {
                        document.cookie = key + "=; expires=Thu, 01 Jan 1970 00:00:00 GMT" + path + domain;
                    }
                }
            }
        };
        remove();
        whenReady(remove);
        listen(window, "load", remove, { once: true });
        listen(window, "beforeunload", remove);
    };

    const storageValues = { emptyArr: "[]", emptyObj: "{}", emptyStr: "" };
    const setStorage = (which, key, value) => {
        const storage = window[which];
        if (!key) {
            return;
        }
        if (value === "$remove$") {
            const keys = /^\/.+\/[a-z]*$/.test(key) ? pattern(key) : null;
            if (keys) {
                Object.keys(storage).filter((name) => keys.test(name)).forEach((name) => storage.removeItem(name));
            } else {
                storage.removeItem(key);
            }
            return;
        }
        storage.setItem(key, Object.prototype.hasOwnProperty.call(storageValues, value) ? storageValues[value] : value);
    };

    const preventDialog = (selector) => {
        const close = () => {
            for (const dialog of document.querySelectorAll("dialog")) {
                if (dialog.open && (!selector || dialog.matches(selector))) {
                    dialog.close();
                }
            }
        };
        whenReady(close);
        observe({ childList: true, subtree: true, attributes: true, attributeFilter: ["open"] }, close, false);
    };

    const scriptlets = {
        "set-constant": setConstant,
        "abort-on-property-read": (chain) => onChain(chain, (owner, property) => {
            const existing = N.descriptor(owner, property);
            if (!existing || existing.configurable) {
                N.defineProperty(owner, property, { configurable: true, get: abort, set: () => {} });
            }
        }),
        "abort-on-property-write": (chain) => onChain(chain, (owner, property) => {
            const existing = N.descriptor(owner, property);
            if (!existing || existing.configurable) {
                N.defineProperty(owner, property, { configurable: true, get: () => undefined, set: abort });
            }
        }),
        "abort-current-script": abortCurrentScript,
        "abort-on-stack-trace": abortOnStackTrace,
        "addEventListener-defuser": defuseListeners,
        "no-setTimeout-if": (text, delay) => defuseTimers("setTimeout", text, delay),
        "no-setInterval-if": (text, delay) => defuseTimers("setInterval", text, delay),
        "no-requestAnimationFrame-if": (text) => defuseTimers("requestAnimationFrame", text),
        "no-xhr-if": preventXhr,
        "no-fetch-if": preventFetch,
        "remove-node-text": removeNodeText,
        "remove-class": removeClass,
        "remove-attr": removeAttr,
        "json-prune": jsonPrune,
        "json-edit": jsonEdit,
        "set-cookie": (...args) => setCookie(false, ...args),
        "set-cookie-reload": (...args) => setCookie(true, ...args),
        "remove-cookie": removeCookies,
        "set-local-storage-item": (key, value) => setStorage("localStorage", key, value),
        "set-session-storage-item": (key, value) => setStorage("sessionStorage", key, value),
        "prevent-dialog": preventDialog,
    };
    const aliases = {
        "set": "set-constant", "aopr": "abort-on-property-read", "aopw": "abort-on-property-write",
        "acs": "abort-current-script", "acis": "abort-current-script", "aost": "abort-on-stack-trace",
        "aeld": "addEventListener-defuser", "prevent-addEventListener": "addEventListener-defuser",
        "nostif": "no-setTimeout-if", "prevent-setTimeout": "no-setTimeout-if", "nosiif": "no-setInterval-if",
        "norafif": "no-requestAnimationFrame-if", "rmnt": "remove-node-text", "rc": "remove-class",
        "ra": "remove-attr", "cookie-remover": "remove-cookie",
    };
    for (const rule of rules) {
        if (rule[0] !== "js") {
            continue;
        }
        const name = aliases[rule[1]] || rule[1];
        try {
            scriptlets[name](...rule.slice(2));
            report.scripts.push(rule[1]);
        } catch (error) {
            fail(rule[1] + "(" + rule.slice(2).join(", ") + ")", error);
        }
    }

    // Procedural selectors: CSS, with functions that filter or move from the elements it finds.
    const PROCEDURAL = new Set(["has-text", "xpath", "upward", "matches-path"]);
    const ACTIONS = new Set(["style", "remove", "remove-class"]);
    const closingParen = (text, start) => {
        let depth = 0;
        let quote = null;
        for (let index = start; index < text.length; index++) {
            const ch = text[index];
            if (ch === "\\") {
                index++;
            } else if (quote) {
                quote = ch === quote ? null : quote;
            } else if (ch === "\"" || ch === "'") {
                quote = ch;
            } else if (ch === "(") {
                depth++;
            } else if (ch === ")" && --depth === 0) {
                return index;
            }
        }
        return -1;
    };
    const functionsOf = (text) => {
        const found = [];
        let bracket = 0;
        let quote = null;
        for (let index = 0; index < text.length; index++) {
            const ch = text[index];
            if (ch === "\\") {
                index++;
            } else if (quote) {
                quote = ch === quote ? null : quote;
            } else if (ch === "\"" || ch === "'") {
                quote = ch;
            } else if (ch === "[") {
                bracket++;
            } else if (ch === "]") {
                bracket--;
            } else if (ch === ":" && !bracket) {
                const named = /^:(-?[a-zA-Z][\w-]*)\(/.exec(text.slice(index));
                if (named) {
                    const open = index + named[0].length - 1;
                    const close = closingParen(text, open);
                    if (close < 0) {
                        throw new Error("unclosed " + named[1]);
                    }
                    found.push({ name: named[1].toLowerCase(), arg: text.slice(open + 1, close), start: index, end: close + 1 });
                    index = close;
                }
            }
        }
        return found;
    };
    const isProcedural = (text) => functionsOf(text).some((fn) => PROCEDURAL.has(fn.name) ||
        ((fn.name === "has" || fn.name === "not") && (isProcedural(fn.arg) || (fn.name === "has" && fn.arg.includes(":has(")))));
    const elementIndex = (element) => {
        let index = 1;
        for (let sibling = element.previousElementSibling; sibling; sibling = sibling.previousElementSibling) {
            index++;
        }
        return index;
    };
    // CSS read from an element: " .a" below it, "> .a" its children, "+ .a" or "~ .a" its siblings.
    const from = (node, css) => {
        if (node === document) {
            const text = css.trim();
            return text ? Array.from(document.querySelectorAll(/^[>+~]/.test(text) ? ":root " + text : text)) : [document.documentElement];
        }
        const parent = node.parentElement;
        const anchor = parent ? ":scope > :nth-child(" + elementIndex(node) + ")" : ":root";
        return Array.from((parent || document).querySelectorAll(anchor + css));
    };
    const compile = (text, mode) => {
        const fns = functionsOf(text);
        const steps = [];
        let cssStart = 0;
        for (const fn of fns) {
            const procedural = PROCEDURAL.has(fn.name) || ACTIONS.has(fn.name) ||
                ((fn.name === "has" || fn.name === "not") && (isProcedural(fn.arg) || (fn.name === "has" && fn.arg.includes(":has("))));
            if (procedural) {
                // CSS ending on a combinator, written before a function, means any element there.
                const css = text.slice(cssStart, fn.start);
                steps.push(["css", /([>+~]|\s)\s*$/.test(css) ? css + "*" : css], [fn.name, fn.arg]);
                cssStart = fn.end;
            }
        }
        steps.push(["css", text.slice(cssStart).trimEnd()]);
        let action = ["hide"];
        const last = steps.length >= 3 ? steps[steps.length - 2] : null;
        if (last && ACTIONS.has(last[0]) && !steps[steps.length - 1][1].trim()) {
            action = last;
            steps.splice(steps.length - 2, 2);
        }
        const tasks = steps.map(([name, arg], index) => {
            if (name === "css") {
                if (index === 0) {
                    const css = arg;
                    if (mode === "self") {
                        return (nodes) => (css.trim() ? nodes.filter((node) => node.matches(css)) : nodes);
                    }
                    if (mode === "relative") {
                        const relative = /^\s*[>+~]/.test(css) ? css : " " + (css.trim() || "*");
                        return (nodes) => nodes.flatMap((node) => from(node, relative));
                    }
                    return () => (css.trim() ? Array.from(document.querySelectorAll(css)) : [document]);
                }
                return arg ? (nodes) => Array.from(new Set(nodes.flatMap((node) => from(node, arg)))) : (nodes) => nodes;
            }
            if (name === "has-text") {
                const wanted = pattern(arg);
                return (nodes) => nodes.filter((node) => test(wanted, (node === document ? document.documentElement : node).textContent));
            }
            if (name === "has") {
                const inner = compile(arg, "relative");
                return (nodes) => nodes.filter((node) => node !== document && inner.select([node]).length > 0);
            }
            if (name === "not") {
                const inner = compile(arg, "self");
                return (nodes) => nodes.filter((node) => node !== document && inner.select([node]).length === 0);
            }
            if (name === "xpath") {
                return (nodes) => nodes.flatMap((node) => {
                    const result = document.evaluate(arg, node, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
                    const found = [];
                    for (let index = 0; index < result.snapshotLength; index++) {
                        if (result.snapshotItem(index) instanceof Element) {
                            found.push(result.snapshotItem(index));
                        }
                    }
                    return found;
                });
            }
            if (name === "upward") {
                const count = /^\d+$/.test(arg.trim()) ? parseInt(arg, 10) : 0;
                return (nodes) => nodes.map((node) => {
                    if (!count) {
                        return node.parentElement && node.parentElement.closest(arg);
                    }
                    let up = node;
                    for (let index = 0; up && index < count; index++) {
                        up = up.parentElement;
                    }
                    return up;
                }).filter(Boolean);
            }
            if (name === "matches-path") {
                const wanted = pattern(arg);
                return (nodes) => (test(wanted, location.pathname + location.search) ? nodes : []);
            }
            throw new Error(":" + name + " not known");
        });
        return {
            action,
            select: (start) => tasks.reduce((nodes, task) => task(nodes), start || []),
        };
    };

    const sheet = [];
    const procedural = [];
    for (const rule of rules) {
        if (rule[0] === "css") {
            sheet.push(rule[1] + "{display:none!important}");
        } else if (rule[0] === "style") {
            sheet.push(rule[1] + "{" + rule[2] + "}");
        } else if (rule[0] === "proc") {
            try {
                const compiled = compile(rule[1], "root");
                compiled.text = rule[1];
                compiled.done = new WeakSet();
                if (compiled.action[0] === "style") {
                    compiled.attribute = mark + "-" + procedural.length;
                    sheet.push("[" + compiled.attribute + "]{" + compiled.action[1] + "}");
                }
                procedural.push(compiled);
            } catch (error) {
                fail(rule[1], error);
            }
        }
    }
    if (procedural.length) {
        sheet.push("[" + mark + "]{display:none!important}");
    }
    const policies = rules.filter((rule) => rule[0] === "csp").map((rule) => rule[1]);

    // A constructed sheet escapes the page's style-src policy; a style element is the fallback.
    let adopted = null;
    const addSheet = () => {
        if (!sheet.length) {
            return;
        }
        try {
            if (!adopted) {
                adopted = new CSSStyleSheet();
                adopted.replaceSync(sheet.join("\n"));
            }
            if (!document.adoptedStyleSheets.includes(adopted)) {
                document.adoptedStyleSheets = [...document.adoptedStyleSheets, adopted];
            }
        } catch (error) {
            const style = N.createElement.call(document, "style");
            style.textContent = sheet.join("\n");
            (document.head || document.documentElement).appendChild(style);
            sheet.length = 0;
        }
    };
    addSheet();
    whenReady(addSheet);
    listen(window, "load", addSheet, { once: true });

    const act = (rule, node) => {
        if (rule.done.has(node)) {
            return;
        }
        rule.done.add(node);
        const [action, arg] = rule.action;
        if (action === "remove") {
            node.remove();
            report.removed++;
        } else if (action === "remove-class") {
            tokensOf(arg).forEach((token) => node.classList.remove(token));
            report.styled++;
        } else if (action === "style") {
            node.setAttribute(rule.attribute, "");
            report.styled++;
        } else {
            node.setAttribute(mark, "");
            report.hidden++;
        }
    };
    const runProcedural = () => {
        for (const rule of procedural) {
            if (rule.failed) {
                continue;
            }
            try {
                rule.select().forEach((node) => node instanceof Element && act(rule, node));
            } catch (error) {
                rule.failed = true;
                fail(rule.text, error);
            }
        }
    };
    if (procedural.length) {
        whenReady(() => {
            runProcedural();
            observe({ childList: true, subtree: true, characterData: true }, runProcedural, false);
        });
    }

    // A policy only counts in the head, before the loads it is meant to stop.
    if (policies.length) {
        const insert = () => {
            if (!document.head) {
                return false;
            }
            for (const policy of policies) {
                const meta = N.createElement.call(document, "meta");
                meta.httpEquiv = "Content-Security-Policy";
                meta.content = policy;
                document.head.prepend(meta);
            }
            report.csp = policies.length;
            return true;
        };
        if (!insert()) {
            const observer = new N.MutationObserver(() => insert() && observer.disconnect());
            observer.observe(document, { childList: true, subtree: true });
        }
    }

    const scrollLocked = () => {
        const root = document.scrollingElement || document.documentElement;
        if (!root || !document.body || root.scrollHeight <= window.innerHeight * 1.2) {
            return false;
        }
        return [document.documentElement, document.body].some((element) => {
            const style = getComputedStyle(element);
            return style.overflow === "hidden" || style.overflowY === "hidden" || style.position === "fixed";
        });
    };
    let sent = false;
    const send = () => {
        if (sent) {
            return;
        }
        sent = true;
        try {
            for (const rule of rules) {
                if (rule[0] === "css") {
                    report.hidden += document.querySelectorAll(rule[1]).length;
                }
            }
        } catch (error) {
            // A selector the page cannot read counts nothing.
        }
        try {
            report.locked = scrollLocked();
        } catch (error) {
            report.locked = false;
        }
        if (report.t === "page" || report.errors.length) {
            post(report);
        }
    };
    listen(window, "load", () => N.setTimeout(send, 2000), { once: true });
    N.setTimeout(send, 15000);
}
