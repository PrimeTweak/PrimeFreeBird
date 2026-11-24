// Probe for walls against ad blockers, removed once read: in each page and large frame, a few times, what
// holds the wall's words up to the page, what lies at the middle of the screen with the page engine's
// verdict on each layer, the frames on the page and its scroll lock, to the pfbWallProbe handler.
(function () {
    "use strict";
    const host = String(location.hostname || "").toLowerCase();
    const channel = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pfbWallProbe;
    if (!host || !channel || /(^|\.)(x\.com|twitter\.com|twimg\.com|t\.co)$/.test(host)) {
        return;
    }
    const words = /\bad[\s-]?block|bloqueur|bloqueador|werbeblocker|blocco (?:degli |della )?(?:annunci|pubblicit)|advertentieblokker|blokowani\w* reklam/i;
    const styleOf = window.getComputedStyle.bind(window);
    const pointStack = Document.prototype.elementsFromPoint;
    const where = window.top === window ? "page" : "frame";
    const begun = Date.now();
    const post = (lines) => {
        try {
            channel.postMessage({ host, where, lines });
        } catch (error) {
            // A page that breaks the channel only loses the lines.
        }
    };
    const nameOf = (node) => {
        if (!(node instanceof Element)) {
            return String(node && node.nodeName);
        }
        const kinds = typeof node.className === "string" ? node.className.trim().split(/\s+/).filter(Boolean).slice(0, 2) : [];
        return (node.tagName.toLowerCase() + (node.id ? "#" + node.id : "") + kinds.map((kind) => "." + kind).join("")).slice(0, 60);
    };
    const textOf = (node) => (String(node.textContent || "") + (node.shadowRoot ? String(node.shadowRoot.textContent || "") : "")).trim();
    const share = (node) => {
        const box = node.getBoundingClientRect();
        const width = Math.max(0, Math.min(box.right, innerWidth) - Math.max(box.left, 0));
        const height = Math.max(0, Math.min(box.bottom, innerHeight) - Math.max(box.top, 0));
        return (width * height) / Math.max(1, innerWidth * innerHeight);
    };
    const inPage = (node) => node instanceof Element && node !== document.body && node !== document.documentElement;
    const describe = (node) => {
        if (!(node instanceof Element)) {
            return String(node && node.nodeName);
        }
        const style = styleOf(node);
        const box = node.getBoundingClientRect();
        const text = textOf(node);
        return nameOf(node) + " [" + style.position + " z " + style.zIndex + " at " + Math.round(box.left) + "," + Math.round(box.top) + " " +
            Math.round(box.width) + "x" + Math.round(box.height) + " share " + share(node).toFixed(2) + " opacity " + style.opacity +
            (style.display === "none" ? " display none" : "") + " text " + text.length + (words.test(text) ? " words" : "") +
            (node.shadowRoot ? " open shadow" : "") + (node.tagName.includes("-") ? " custom" : "") + "]";
    };
    // The page engine's test on a layer, step by step.
    const verdict = (node) => {
        if (!inPage(node)) {
            return "page root";
        }
        let floating = null;
        for (let link = node; inPage(link); link = link.parentElement) {
            if (styleOf(link).position === "fixed") {
                floating = link;
            }
        }
        if (!floating) {
            return "not floating";
        }
        let wall = null;
        let length = 0;
        let stop = "";
        for (let link = node; inPage(link); link = link.parentElement) {
            const text = textOf(link);
            if (text.length > 1500 || (wall && text.length > length + 80)) {
                stop = ", stops at " + nameOf(link) + " text " + text.length;
                break;
            }
            const position = styleOf(link).position;
            if ((position === "fixed" || position === "absolute") && words.test(text)) {
                wall = link;
                length = text.length;
            }
        }
        if (!wall) {
            return "floats in " + nameOf(floating) + ", no positioned layer with the words" + stop;
        }
        return "wall " + nameOf(wall) + " share " + share(wall).toFixed(2) + (share(wall) >= 0.25 ? ", would be taken off" : ", too small");
    };
    // The first shown text with the words, in the page or its open shadow roots.
    const unseen = /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/;
    const wordsIn = (root) => {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        for (let text = walker.nextNode(); text; text = walker.nextNode()) {
            if (words.test(text.data) && !unseen.test(text.parentNode.nodeName)) {
                return text.parentNode;
            }
        }
        for (const element of root.querySelectorAll("*")) {
            const found = element.shadowRoot && wordsIn(element.shadowRoot);
            if (found) {
                return found;
            }
        }
        return null;
    };
    const chain = (node) => {
        const lines = [];
        for (let link = node; link && lines.length < 14; ) {
            if (link instanceof ShadowRoot) {
                lines.push("(open shadow root of)");
                link = link.host;
                continue;
            }
            lines.push(describe(link));
            if (link === document.documentElement) {
                break;
            }
            link = link.parentNode;
        }
        return lines;
    };
    let last = "";
    let sent = 0;
    const snapshot = () => {
        if (!document.body || sent >= 6) {
            return;
        }
        const found = wordsIn(document.body);
        if (where === "frame" && !found && (innerWidth < 200 || innerHeight < 200)) {
            return;
        }
        const html = styleOf(document.documentElement);
        const body = styleOf(document.body);
        const lines = [];
        lines.push(innerWidth + "x" + innerHeight + " " + location.pathname.slice(0, 50) + ", html " + html.overflowY + " " + html.position +
            ", body " + body.overflowY + " " + body.position + ", text " + textOf(document.body).length);
        if (found) {
            lines.push("words in " + (found instanceof Element ? nameOf(found) : String(found.nodeName)) + ", up to the page:");
            chain(found).forEach((line) => lines.push("  " + line));
        } else {
            lines.push("no words in this document");
        }
        lines.push("middle of the screen, top first:");
        try {
            pointStack.call(document, innerWidth / 2, innerHeight / 2).slice(0, 8).forEach((node) => lines.push("  " + describe(node) + " -> " + verdict(node)));
        } catch (error) {
            lines.push("  no stack: " + error);
        }
        Array.from(document.querySelectorAll("iframe")).slice(0, 8).forEach((frame) => {
            lines.push("iframe " + describe(frame) + " src " + String(frame.src || "none").replace(/^https?:\/\//, "").slice(0, 70));
        });
        const key = lines.join("|");
        if (key === last) {
            return;
        }
        last = key;
        sent++;
        post([((Date.now() - begun) / 1000).toFixed(1) + "s"].concat(lines));
    };
    const start = () => [0, 1000, 2500, 5000, 9000, 15000, 25000].forEach((delay) => setTimeout(snapshot, delay));
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", start, { once: true });
    } else {
        start();
    }
})();
