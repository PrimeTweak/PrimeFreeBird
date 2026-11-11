#!/usr/bin/env python3
"""Turns EasyList into the WebKit content-blocker lists of Block web ads.

Usage: easylist-webkit.py EASYLIST OUTPUT_DIR
EASYLIST is an EasyList checkout (its easylist.template is followed) or an easylist.txt.
OUTPUT_DIR receives web-ads.json (version and list names) and web-ads-N.json.

Rules WebKit cannot express (regular expressions, scriptlets, extended selectors, options
it has no trigger for) are left out. Each list carries every exception, since an exception
only reaches the rules of its own list, and ends by leaving X's own pages alone.
"""
import hashlib
import json
import os
import re
import sys

RULES_PER_LIST = 9000
SELECTORS_PER_RULE = 250
X_DOMAINS = ["*x.com", "*twitter.com", "*twimg.com", "*t.co"]

TYPES = {
    "script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font",
    "media": "media", "subdocument": "document", "xmlhttprequest": "raw", "websocket": "raw",
    "ping": "raw", "other": "raw", "popup": "popup",
}
ALL_TYPES = sorted(set(TYPES.values()))
IGNORED_OPTIONS = {"important"}
UNSUPPORTED_PSEUDO = re.compile(
    r":(-abp-|-ext-|has-text|xpath|upward|remove|style|matches-|contains|min-text-length|"
    r"watch-attr|others|nth-ancestor|if\(|if-not|spath|shadow|has\()")
DOMAIN = re.compile(r"^[a-z0-9.-]+$")
SPECIALS = set(".+?$()[]{}\\|")


def read_lines(source):
    if os.path.isdir(source):
        lines = []
        with open(os.path.join(source, "easylist.template"), encoding="utf-8") as template:
            for line in template:
                include = re.match(r"%include easylist:(.+)%", line.strip())
                if include:
                    with open(os.path.join(source, include.group(1)), encoding="utf-8") as part:
                        lines.extend(part.read().splitlines())
        return lines
    with open(source, encoding="utf-8") as whole:
        return whole.read().splitlines()


def domains_of(text, separator):
    positive, negative = [], []
    for item in filter(None, (part.strip().lower() for part in text.split(separator))):
        target = negative if item.startswith("~") else positive
        item = item.lstrip("~")
        if not DOMAIN.match(item) or "*" in item:
            return None
        target.append("*" + item)
    if positive and negative:
        return None
    return ("if-domain", positive) if positive else ("unless-domain", negative) if negative else ("", [])


def url_filter(pattern, case_sensitive):
    if pattern.startswith("/") and pattern.endswith("/") and len(pattern) > 2:
        return None
    if any(ord(ch) < 33 or ord(ch) > 126 for ch in pattern):
        return None
    separator = "[^-_.%a-zA-Z0-9]" if case_sensitive else "[^-_.%a-z0-9]"
    prefix = suffix = ""
    if pattern.startswith("||"):
        prefix, pattern = r"^[^:]+:(//)?([^/]+\.)?", pattern[2:]
    elif pattern.startswith("|"):
        prefix, pattern = "^", pattern[1:]
    if pattern.endswith("|"):
        suffix, pattern = "$", pattern[:-1]
    if not prefix:
        pattern = pattern.lstrip("*")
    if not suffix:
        pattern = pattern.rstrip("*")
    body = []
    for ch in pattern:
        if ch == "*":
            body.append(".*")
        elif ch == "^":
            body.append(separator)
        elif ch in SPECIALS:
            body.append("\\" + ch)
        else:
            body.append(ch)
    text = prefix + "".join(body) + suffix
    return text or ".*"


def network_rule(line):
    exception = line.startswith("@@")
    if exception:
        line = line[2:]
    pattern, options = line, []
    dollar = line.rfind("$")
    if dollar > 0 and re.match(r"^[a-z0-9~_=|.,*:-]+$", line[dollar + 1:], re.I):
        pattern, options = line[:dollar], line[dollar + 1:].split(",")
    trigger, types, negated, case_sensitive, whole_site = {}, set(), set(), False, False
    for option in options:
        name = option.strip().lower()
        if name in IGNORED_OPTIONS:
            continue
        if name in ("third-party", "3p"):
            trigger["load-type"] = ["third-party"]
        elif name in ("~third-party", "1p", "first-party"):
            trigger["load-type"] = ["first-party"]
        elif name == "match-case":
            case_sensitive = True
        elif name.startswith("domain="):
            found = domains_of(option.strip()[7:], "|")
            if found is None:
                return None
            if found[0]:
                trigger[found[0]] = found[1]
        elif name in TYPES:
            types.add(TYPES[name])
        elif name.startswith("~") and name[1:] in TYPES:
            negated.add(TYPES[name[1:]])
        elif exception and name == "document":
            whole_site = True
        else:
            return None
    if whole_site:
        site = re.match(r"^\|\|([a-z0-9.-]+)\^?$", pattern.lower())
        if not site or len(options) != 1:
            return None
        return [{"trigger": {"url-filter": ".*", "if-domain": ["*" + site.group(1)]},
                 "action": {"type": "ignore-previous-rules"}}], True
    if negated:
        types = (types or set(ALL_TYPES)) - negated
        if not types:
            return None
    regex = url_filter(pattern, case_sensitive)
    if regex is None:
        return None
    trigger = dict({"url-filter": regex}, **trigger)
    if case_sensitive:
        trigger["url-filter-is-case-sensitive"] = True
    if exception:
        if types:
            trigger["resource-type"] = sorted(types)
        return [{"trigger": trigger, "action": {"type": "ignore-previous-rules"}}], True
    # A page the user opens is never blocked by a pattern that only names a path: WebKit's
    # document type also covers the top frame, so documents are blocked in frames only.
    types = types or set(ALL_TYPES)
    rules = []
    if "document" in types and not pattern.startswith("||"):
        frames = dict(trigger, **{"resource-type": ["document"], "load-context": ["child-frame"]})
        rules.append({"trigger": frames, "action": {"type": "block"}})
        types = types - {"document"}
    if types:
        if types != set(ALL_TYPES):
            trigger["resource-type"] = sorted(types)
        rules.insert(0, {"trigger": trigger, "action": {"type": "block"}})
    return rules, False


def selector_ok(selector):
    return (selector and all(32 <= ord(ch) <= 126 for ch in selector)
            and "{" not in selector and not selector.startswith("+js")
            and not UNSUPPORTED_PSEUDO.search(selector))


def hide_rules(selectors, condition):
    rules = []
    for start in range(0, len(selectors), SELECTORS_PER_RULE):
        trigger = {"url-filter": ".*"}
        if condition and condition[0]:
            trigger[condition[0]] = condition[1]
        rules.append({"trigger": trigger, "action": {
            "type": "css-display-none", "selector": ", ".join(selectors[start:start + SELECTORS_PER_RULE])}})
    return rules


def check(rule):
    """The url-filter keeps to what WebKit compiles: no alternation, braces or inner anchors."""
    text = rule["trigger"]["url-filter"]
    inner = text[1:] if text.startswith("^") else text
    inner = inner[:-1] if inner.endswith("$") and not inner.endswith("\\$") else inner
    if "^" in re.sub(r"\[\^", "", inner) or re.search(r"(?<!\\)[|{}]", inner):
        raise ValueError("url-filter WebKit refuses: " + text)


def main(source, output):
    blocks, exceptions, generic, generic_allowed, specific = [], [], [], set(), {}
    skipped = 0
    for raw in read_lines(source):
        line = raw.strip()
        if not line or line.startswith(("!", "[")):
            continue
        if "#@#" in line:
            domains, selector = line.split("#@#", 1)
            if not domains:
                generic_allowed.add(selector)
            continue
        if re.search(r"#[?$%@]+#|#\+js", line):
            skipped += 1
            continue
        if "##" in line:
            domains, selector = line.split("##", 1)
            if not selector_ok(selector):
                skipped += 1
                continue
            if not domains:
                generic.append(selector)
                continue
            found = domains_of(domains, ",")
            if found is None or not found[0]:
                skipped += 1
                continue
            specific.setdefault((found[0], tuple(sorted(found[1]))), []).append(selector)
            continue
        made = network_rule(line)
        if made is None:
            skipped += 1
            continue
        (exceptions if made[1] else blocks).extend(made[0])
    generic = [selector for selector in dict.fromkeys(generic) if selector not in generic_allowed]
    hides = hide_rules(generic, None)
    for (kind, domains), selectors in sorted(specific.items()):
        hides.extend(hide_rules(list(dict.fromkeys(selectors)), (kind, list(domains))))
    for rule in blocks + exceptions:
        check(rule)
    closing = {"trigger": {"url-filter": ".*", "if-domain": X_DOMAINS},
               "action": {"type": "ignore-previous-rules"}}
    body = blocks + hides
    per_list = RULES_PER_LIST
    chunks = [body[start:start + per_list] for start in range(0, len(body), per_list)]
    os.makedirs(output, exist_ok=True)
    for name in os.listdir(output):
        if re.match(r"^web-ads(-\d+)?\.json$", name):
            os.remove(os.path.join(output, name))
    names, digest = [], hashlib.sha256()
    for index, chunk in enumerate(chunks, 1):
        text = json.dumps(chunk + exceptions + [closing], separators=(",", ":"))
        digest.update(text.encode())
        name = "web-ads-%d.json" % index
        with open(os.path.join(output, name), "w", encoding="utf-8") as out:
            out.write(text)
        names.append(name)
    with open(os.path.join(output, "web-ads.json"), "w", encoding="utf-8") as out:
        json.dump({"version": digest.hexdigest()[:12], "lists": names}, out)
    print("block %d, exceptions %d, hiding rules %d (generic selectors %d), lists %d, skipped %d"
          % (len(blocks), len(exceptions), len(hides), len(generic), len(names), skipped))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
