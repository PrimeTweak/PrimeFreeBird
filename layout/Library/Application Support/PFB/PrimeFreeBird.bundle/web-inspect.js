// Block web ads' page inspector, run by the stethoscope on the page open in Twitter's browser: the page's size
// and scroll lock, a wall against ad blockers with the page engine's verdict, empty blocks, blocks named for
// ads with what the engine does with them, and the page's frames, for the report's WEB PAGE part.
(function () {
    "use strict";
    const lines = [];
    const add = (line) => lines.length < 300 && lines.push(String(line).replace(/\s+/g, " ").slice(0, 220));
    const styleOf = (node) => getComputedStyle(node);
    const wallWords = /\bad[\s-]?block|bloqueur|bloqueador|werbeblocker|blocco (?:degli |della )?(?:annunci|pubblicit)|advertentieblokker|blokowani\w* reklam/i;
    const adNames = /^(ad|ads|adv|advert|adverts|advertising|advertisement|adslot|adunit|adbox|adcontainer|adwrapper|gpt|dfp|pub|pubs|publicite|publicites|banner|banners|sponsor|sponsored|teads|outbrain|taboola|prebid|bigbox|leaderboard|billboard|halfpage)$/;
    const media = "img,video,canvas,svg,picture,object,embed,iframe";
    const body = document.body;
    const root = document.documentElement;
    if (!body) {
        return "no page body yet";
    }
    const inPage = (node) => node instanceof Element && node !== body && node !== root;
    const nameOf = (node) => {
        if (!(node instanceof Element)) {
            return String(node && node.nodeName);
        }
        const kinds = typeof node.className === "string" ? node.className.trim().split(/\s+/).filter(Boolean).slice(0, 3) : [];
        return (node.tagName.toLowerCase() + (node.id ? "#" + node.id : "") + kinds.map((kind) => "." + kind).join("")).slice(0, 70);
    };
    const adWord = (node) => {
        const names = (node.id + " " + (typeof node.className === "string" ? node.className : "")).toLowerCase();
        return names.split(/[^a-z0-9]+/).find((token) => adNames.test(token)) || "";
    };
    const textOf = (node) => (String(node.textContent || "") + (node.shadowRoot ? String(node.shadowRoot.textContent || "") : "")).trim();
    const seenText = (node) => String(node.innerText || "").replace(/\s+/g, "").length;
    const shown = (node) => {
        const style = styleOf(node);
        return style.display !== "none" && style.visibility !== "hidden" && parseFloat(style.opacity) > 0.05;
    };
    const share = (node) => {
        const box = node.getBoundingClientRect();
        const width = Math.max(0, Math.min(box.right, innerWidth) - Math.max(box.left, 0));
        const height = Math.max(0, Math.min(box.bottom, innerHeight) - Math.max(box.top, 0));
        return (width * height) / Math.max(1, innerWidth * innerHeight);
    };
    const big = (node) => {
        const box = node.getBoundingClientRect();
        return box.width >= 40 && box.height >= 40;
    };
    const pictured = (node) => {
        const image = styleOf(node).backgroundImage;
        return node.matches(media) || (image !== "none" && image.includes("url("));
    };
    const pictures = (node) => [node].concat(Array.from(node.querySelectorAll("*"))).filter((item) => pictured(item) && big(item) && shown(item)).length;
    const roomOf = (node) => {
        const style = styleOf(node);
        return node.getBoundingClientRect().height - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
    };
    const layer = (node) => {
        const style = styleOf(node);
        const box = node.getBoundingClientRect();
        const text = textOf(node);
        return nameOf(node) + " [" + style.position + " z " + style.zIndex + " at " + Math.round(box.left) + "," + Math.round(box.top) + " " +
            Math.round(box.width) + "x" + Math.round(box.height) + " share " + share(node).toFixed(2) + " opacity " + style.opacity +
            (style.display === "none" ? " display none" : "") + " text " + text.length + (wallWords.test(text) ? " words" : "") +
            (node.shadowRoot ? " open shadow" : "") + (node.tagName.includes("-") ? " custom" : "") + "]";
    };

    // The page.
    const html = styleOf(root);
    const bodyStyle = styleOf(body);
    add("page " + innerWidth + "x" + innerHeight + ", scrolled " + Math.round(scrollY) + ", html " + html.overflowY + " " + html.position +
        ", body " + bodyStyle.overflowY + " " + bodyStyle.position + ", text " + textOf(body).length);

    // A wall: where its words are, and the page engine's verdict on each layer at the middle of the screen.
    const unseen = /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/;
    const wordsIn = (top) => {
        const walker = document.createTreeWalker(top, NodeFilter.SHOW_TEXT);
        for (let text = walker.nextNode(); text; text = walker.nextNode()) {
            if (wallWords.test(text.data) && !unseen.test(text.parentNode.nodeName)) {
                return text.parentNode;
            }
        }
        for (const element of top.querySelectorAll("*")) {
            const found = element.shadowRoot && wordsIn(element.shadowRoot);
            if (found) {
                return found;
            }
        }
        return null;
    };
    const limit = Math.max(1500, textOf(body).length / 4);
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
            if (text.length > limit || (wall && text.length > length + 80)) {
                stop = ", stops at " + nameOf(link) + " text " + text.length;
                break;
            }
            const position = styleOf(link).position;
            if ((position === "fixed" || position === "absolute") && wallWords.test(text)) {
                wall = link;
                length = text.length;
            }
        }
        if (!wall) {
            return "floats in " + nameOf(floating) + ", no positioned layer with the words" + stop;
        }
        return "wall " + nameOf(wall) + " share " + share(wall).toFixed(2) + (share(wall) >= 0.25 ? ", taken off" : ", too small");
    };
    const words = wordsIn(body);
    if (words) {
        add("wall words in " + nameOf(words) + ", up to the page:");
        for (let link = words, steps = 0; link && steps < 14; steps++) {
            if (link instanceof ShadowRoot) {
                add("  (open shadow root of)");
                link = link.host;
                continue;
            }
            add("  " + layer(link));
            if (link === root) {
                break;
            }
            link = link.parentNode;
        }
    } else {
        add("no wall words on the page");
    }
    add("middle of the screen, top first:");
    document.elementsFromPoint(innerWidth / 2, innerHeight / 2).slice(0, 8).forEach((node) => add("  " + layer(node) + " -> " + verdict(node)));

    // Blocks: how each is made and named, within the first eight screens.
    const describe = (node, label) => {
        const box = node.getBoundingClientRect();
        const style = styleOf(node);
        const chain = [];
        for (let link = node, steps = 0; link && link !== body && steps < 5; link = link.parentElement, steps++) {
            chain.push(nameOf(link) + "(" + Math.round(link.getBoundingClientRect().height) + ")");
        }
        add(label + " y " + Math.round(box.top + scrollY) + " h " + Math.round(box.height) + " w " + Math.round(box.width) + ": " + chain.join(" < "));
        const image = style.backgroundImage === "none" ? "none" : style.backgroundImage.replace(/^url\("?https?:\/\/([^/"]+).*$/, "url $1").slice(0, 40);
        add("  style: height " + style.height + ", min-height " + style.minHeight + ", padding " + style.paddingTop + "/" + style.paddingBottom +
            ", background " + style.backgroundColor + " image " + image + ", " + style.display + " " + style.position);
        const inside = Array.from(node.querySelectorAll("*"));
        add("  shows: text " + seenText(node) + ", pictures " + pictures(node) + ", scripts " + node.querySelectorAll("script").length +
            ", inside " + inside.length + (inside.length ? " (" + inside.filter((item) => item.id || (typeof item.className === "string" && item.className.trim())).slice(0, 6).map(nameOf).join(" ") + ")" : ""));
        Array.from(node.querySelectorAll("iframe")).slice(0, 3).forEach((frame) => {
            const frameBox = frame.getBoundingClientRect();
            add("  iframe " + Math.round(frameBox.width) + "x" + Math.round(frameBox.height) + (shown(frame) ? "" : " hidden") + " src " +
                String(frame.getAttribute("src") || "none").replace(/^https?:\/\//, "").slice(0, 60));
        });
    };
    const reach = 8 * innerHeight;
    const empties = [];
    const visit = (node) => {
        for (const child of Array.from(node.children)) {
            if (empties.length >= 10 || unseen.test(child.tagName) || !shown(child) || child.getBoundingClientRect().top + scrollY > reach) {
                continue;
            }
            if (seenText(child) > 3 || pictures(child)) {
                visit(child);
            } else if (child.getBoundingClientRect().height >= 50 && child.getBoundingClientRect().width >= Math.min(200, innerWidth / 2)) {
                empties.push(child);
            }
        }
    };
    visit(body);
    add(empties.length + " empty blocks");
    empties.forEach((node, index) => describe(node, "#" + (index + 1)));
    const named = [];
    for (const node of body.querySelectorAll("[id],[class]")) {
        if (named.length < 12 && adWord(node) && !named.some((outer) => outer.contains(node)) && node.getBoundingClientRect().top + scrollY <= reach) {
            named.push(node);
        }
    }
    add(named.length + " blocks named for ads");
    named.forEach((node, index) => {
        describe(node, "ad" + (index + 1) + ' ("' + adWord(node) + '")');
        const folded = node.style.getPropertyValue("display") === "none" && node.style.getPropertyPriority("display") === "important";
        const keeps = !shown(node) ? "hidden already" : seenText(node) > 3 ? "shows text" : pictures(node) ? "shows a picture" :
            roomOf(node) < 30 && node.getBoundingClientRect().height >= 30 ? "height made of padding" : "";
        add("  engine: " + (folded ? "folded" : keeps ? "kept, " + keeps : "would fold"));
    });

    // Frames.
    const frames = Array.from(document.querySelectorAll("iframe"));
    add(frames.length + " frames");
    frames.slice(0, 8).forEach((frame) => {
        const box = frame.getBoundingClientRect();
        add("  " + Math.round(box.width) + "x" + Math.round(box.height) + (shown(frame) ? "" : " hidden") + " at " + Math.round(box.top + scrollY) +
            " src " + String(frame.getAttribute("src") || "none").replace(/^https?:\/\//, "").slice(0, 70));
    });
    return lines.join("\n");
})();
