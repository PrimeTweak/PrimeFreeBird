// Probe for empty ad spaces, removed once read: on each page and large frame, at its opening, its load and
// 5 and 15 s later, the empty blocks at least 50 px high in its first eight screens, how they are made and
// named, to the pfbGapProbe handler.
(function () {
    "use strict";
    const host = String(location.hostname || "").toLowerCase();
    const channel = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pfbGapProbe;
    if (!host || !channel || /(^|\.)(x\.com|twitter\.com|twimg\.com|t\.co)$/.test(host)) {
        return;
    }
    const where = window.top === window ? "page" : "frame";
    const begun = Date.now();
    const styleOf = window.getComputedStyle.bind(window);
    const adWords = /^(ad|ads|adv|advert|adverts|advertising|advertisement|adslot|adunit|adbox|adcontainer|adwrapper|gpt|dfp|pub|pubs|publicite|publicites|publicity|banner|banners|sponsor|sponsored|teads|outbrain|taboola|prebid|bigbox|leaderboard|billboard|halfpage|native|promo|commercial)$/;
    const post = (lines) => {
        try {
            channel.postMessage({ host, where, lines });
        } catch (error) {
            // A page that breaks the channel only loses the lines.
        }
    };
    const short = (text, size) => String(text).replace(/\s+/g, " ").trim().slice(0, size);
    const nameOf = (node) => {
        const kinds = typeof node.className === "string" ? node.className.trim().split(/\s+/).filter(Boolean).slice(0, 3) : [];
        return short(node.tagName.toLowerCase() + (node.id ? "#" + node.id : "") + kinds.map((kind) => "." + kind).join(""), 70);
    };
    const shown = (node) => {
        const style = styleOf(node);
        return style.display !== "none" && style.visibility !== "hidden" && parseFloat(style.opacity) > 0.05;
    };
    const media = "img,video,canvas,svg,picture,object,embed,iframe";
    // Words, pictures or frames a reader can see; an empty block has none.
    const content = (node) => {
        const raw = String(node.textContent || "").replace(/\s+/g, "");
        if (raw.length > 400 || String(node.innerText || "").replace(/\s+/g, "").length > 3) {
            return "text";
        }
        for (const item of [node].concat(Array.from(node.querySelectorAll(media)))) {
            if (!item.matches(media)) {
                continue;
            }
            const box = item.getBoundingClientRect();
            if (box.width >= 40 && box.height >= 40 && shown(item) && item.tagName !== "IFRAME") {
                return item.tagName.toLowerCase();
            }
        }
        return "";
    };
    const tokensOf = (node) => {
        const names = [node.id, typeof node.className === "string" ? node.className : ""];
        for (const attribute of Array.from(node.attributes)) {
            if (attribute.name.startsWith("data-")) {
                names.push(attribute.name.slice(5), short(attribute.value, 40));
            }
        }
        return names.join(" ").toLowerCase().split(/[^a-z0-9]+/).filter((token) => adWords.test(token));
    };
    const describeBlock = (node, index) => {
        const box = node.getBoundingClientRect();
        const style = styleOf(node);
        const lines = [];
        const chain = [];
        for (let link = node, steps = 0; link && link !== document.body && steps < 5; link = link.parentElement, steps++) {
            chain.push(nameOf(link) + "(" + Math.round(link.getBoundingClientRect().height) + ")");
        }
        lines.push("#" + index + " y " + Math.round(box.top + scrollY) + " h " + Math.round(box.height) + " w " + Math.round(box.width) + ": " + chain.join(" < "));
        const image = style.backgroundImage === "none" ? "none" : short(style.backgroundImage.replace(/^url\("?https?:\/\/([^/"]+).*$/, "url $1"), 40);
        lines.push("  style: height " + style.height + ", min-height " + style.minHeight + ", padding " + style.paddingTop + "/" + style.paddingBottom +
            ", margin " + style.marginTop + "/" + style.marginBottom + ", background " + style.backgroundColor + " image " + image +
            ", " + style.display + " " + style.position + (style.aspectRatio && style.aspectRatio !== "auto" ? ", ratio " + style.aspectRatio : ""));
        const inside = Array.from(node.querySelectorAll("*"));
        const tags = {};
        inside.forEach((item) => {
            tags[item.tagName.toLowerCase()] = (tags[item.tagName.toLowerCase()] || 0) + 1;
        });
        const counted = Object.entries(tags).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([tag, count]) => tag + " " + count).join(", ");
        const named = inside.filter((item) => item.id || (typeof item.className === "string" && item.className.trim())).slice(0, 6).map(nameOf);
        lines.push("  inside: " + inside.length + " elements (" + (counted || "none") + ")" + (named.length ? ", named " + named.join(" ") : ""));
        Array.from(node.querySelectorAll("iframe")).slice(0, 3).forEach((frame) => {
            const frameBox = frame.getBoundingClientRect();
            lines.push("  iframe " + Math.round(frameBox.width) + "x" + Math.round(frameBox.height) + (shown(frame) ? "" : " hidden") + " src " +
                short(String(frame.getAttribute("src") || "none").replace(/^https?:\/\//, ""), 60));
        });
        const data = [];
        [node].concat(inside).slice(0, 40).forEach((item) => {
            Array.from(item.attributes).forEach((attribute) => {
                if (attribute.name.startsWith("data-") && data.length < 6) {
                    data.push(short(attribute.name + "=" + attribute.value, 50));
                }
            });
        });
        const words = new Set();
        [node].concat(inside).forEach((item) => tokensOf(item).forEach((token) => words.add(token)));
        let up = [];
        for (let link = node.parentElement, steps = 0; link && link !== document.body && steps < 3; link = link.parentElement, steps++) {
            up = up.concat(tokensOf(link));
        }
        lines.push("  data: " + (data.join(" ") || "none") + "; ad words in it: " + (Array.from(words).join(" ") || "none") +
            "; above it: " + (Array.from(new Set(up)).join(" ") || "none"));
        return lines;
    };
    // The outermost empty blocks, in page order, within the first eight screens.
    const emptyBlocks = () => {
        const found = [];
        const reach = 8 * innerHeight;
        const visit = (node) => {
            for (const child of Array.from(node.children)) {
                if (found.length >= 12 || /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|LINK|META)$/.test(child.tagName) || !shown(child)) {
                    continue;
                }
                const box = child.getBoundingClientRect();
                if (box.top + scrollY > reach) {
                    continue;
                }
                const kind = content(child);
                if (!kind) {
                    if (box.height >= 50 && box.width >= Math.min(200, innerWidth / 2)) {
                        found.push(child);
                    }
                    continue;
                }
                visit(child);
            }
        };
        visit(document.body);
        return found;
    };
    let last = "";
    let sent = 0;
    const snapshot = (moment) => {
        if (!document.body || sent >= 4 || (where === "frame" && (innerWidth < 300 || innerHeight < 300))) {
            return;
        }
        const blocks = emptyBlocks();
        let lines = [innerWidth + "x" + innerHeight + " " + short(location.pathname, 50) + ", " + blocks.length + " empty blocks"];
        blocks.forEach((block, index) => {
            lines = lines.concat(describeBlock(block, index + 1));
        });
        const key = lines.join("|");
        if (key === last) {
            return;
        }
        last = key;
        sent++;
        post([moment + " at " + ((Date.now() - begun) / 1000).toFixed(1) + "s"].concat(lines));
    };
    const start = () => {
        snapshot("opening");
        if (document.readyState === "complete") {
            snapshot("load");
        } else {
            window.addEventListener("load", () => setTimeout(() => snapshot("load"), 500), { once: true });
        }
        setTimeout(() => snapshot("5 s"), 5000);
        setTimeout(() => snapshot("15 s"), 15000);
    };
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", start, { once: true });
    } else {
        start();
    }
})();
