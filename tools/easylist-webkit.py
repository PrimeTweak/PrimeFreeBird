#!/usr/bin/env python3
"""Turns EasyList, EasyPrivacy and Fanboy's Annoyance list into the WebKit content-blocker
lists of Block web ads.

Usage: easylist-webkit.py EASYLIST OUTPUT_DIR
EASYLIST is an EasyList checkout (its easylist, easyprivacy and fanboy-annoyance templates
are followed) or a single filter list. OUTPUT_DIR receives web-ads.json (version and list
names) and web-ads-N.json.

Rules WebKit cannot express (regular expressions, scriptlets, extended selectors, options
it has no trigger for) are left out. An exception only reaches the rules of its own list, so
each list carries the exceptions that can apply to it, and ends by leaving X's own pages alone.
Generic hiding has lists of its own, the only ones $generichide exceptions cancel, and :has()
selectors too, so a WebKit that refuses them leaves the other lists whole.
"""
import hashlib
import json
import os
import re
import sys

TEMPLATES = ("easylist.template", "easyprivacy.template", "fanboy-annoyance.template")
RULES_PER_LIST = 15000
SELECTORS_PER_RULE = 250
X_DOMAINS = ["*x.com", "*twitter.com", "*twimg.com", "*t.co"]

TYPES = {
    "script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font",
    "media": "media", "subdocument": "document", "xmlhttprequest": "raw", "websocket": "raw",
    "ping": "raw", "other": "raw", "popup": "popup",
}
ALL_TYPES = sorted(set(TYPES.values()))
PAGE_OPTIONS = {"generichide": "generichide", "ghide": "generichide", "elemhide": "elemhide", "ehide": "elemhide"}
IGNORED_OPTIONS = {"important"}
UNSUPPORTED_PSEUDO = re.compile(
    r":(-abp-|-ext-|has-text|xpath|upward|remove|style|matches-|contains|min-text-length|"
    r"watch-attr|others|nth-ancestor|if\(|if-not|spath|shadow)")
DOMAIN = re.compile(r"^[a-z0-9.-]+$")
SPECIALS = set(".+?$()[]{}\\|")
IGNORE = {"type": "ignore-previous-rules"}


def read_lines(source):
    if not os.path.isdir(source):
        with open(source, encoding="utf-8") as whole:
            return whole.read().splitlines()
    lines = []
    for name in TEMPLATES:
        with open(os.path.join(source, name), encoding="utf-8") as template:
            for line in template:
                include = re.match(r"%include easylist:(.+)%", line.strip())
                if include:
                    with open(os.path.join(source, include.group(1)), encoding="utf-8") as part:
                        lines.extend(part.read().splitlines())
    return list(dict.fromkeys(lines))


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
    """Returns the rules of a line and their kind: block, exception, generichide or elemhide."""
    exception = line.startswith("@@")
    if exception:
        line = line[2:]
    pattern, options = line, []
    dollar = line.rfind("$")
    if dollar >= 0 and re.match(r"^[a-z0-9~_=|.,*:-]+$", line[dollar + 1:], re.I):
        pattern, options = line[:dollar], line[dollar + 1:].split(",")
    trigger, types, negated, case_sensitive, whole_site, page = {}, set(), set(), False, False, None
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
        elif name in ("document", "doc"):
            whole_site = exception
            types.add("document")
        elif exception and name in PAGE_OPTIONS:
            page = PAGE_OPTIONS[name]
        else:
            return None
    if whole_site:
        site = re.match(r"^\|\|([a-z0-9.-]+)\^?$", pattern.lower())
        if not site or len(options) != 1:
            return None
        return [{"trigger": {"url-filter": ".*", "if-domain": ["*" + site.group(1)]}, "action": IGNORE}], "exception"
    if page and (types or negated):
        return None
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
    # Hiding is cancelled on the page itself, the load of its document.
    if page:
        trigger["resource-type"] = ["document"]
        return [{"trigger": trigger, "action": IGNORE}], page
    if exception:
        if types:
            trigger["resource-type"] = sorted(types)
        return [{"trigger": trigger, "action": IGNORE}], "exception"
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
    return rules, "block"


def nested_has(selector):
    """CSS refuses a :has() inside another one."""
    depth, opened = 0, []
    for index, ch in enumerate(selector):
        if selector.startswith(":has(", index):
            if opened:
                return True
            opened.append(depth)
        elif ch == ")" and opened and opened[-1] == depth - 1:
            opened.pop()
        depth += (ch == "(") - (ch == ")")
    return False


def selector_ok(selector):
    return (selector and all(32 <= ord(ch) <= 126 for ch in selector)
            and "{" not in selector and not selector.startswith("+js")
            and not UNSUPPORTED_PSEUDO.search(selector) and not nested_has(selector))


def hide_rules(selectors, condition):
    rules = []
    for start in range(0, len(selectors), SELECTORS_PER_RULE):
        trigger = {"url-filter": ".*"}
        if condition and condition[0]:
            trigger[condition[0]] = condition[1]
        rules.append({"trigger": trigger, "action": {
            "type": "css-display-none", "selector": ", ".join(selectors[start:start + SELECTORS_PER_RULE])}})
    return rules


def unique(rules):
    return list({json.dumps(rule, sort_keys=True): rule for rule in rules}.values())


def reaches_pages(rule):
    types = rule["trigger"].get("resource-type")
    return types is None or "document" in types


def check(rule):
    """The url-filter keeps to what WebKit compiles: no alternation, braces or inner anchors."""
    text = rule["trigger"]["url-filter"]
    inner = text[1:] if text.startswith("^") else text
    inner = inner[:-1] if inner.endswith("$") and not inner.endswith("\\$") else inner
    if "^" in re.sub(r"\[\^", "", inner) or re.search(r"(?<!\\)[|{}]", inner):
        raise ValueError("url-filter WebKit refuses: " + text)


def main(source, output):
    made_rules = {"block": [], "exception": [], "generichide": [], "elemhide": []}
    generic, generic_allowed, site_allowed, specific = [], set(), {}, {}
    skipped = 0
    for raw in read_lines(source):
        line = raw.strip()
        if not line or line.startswith(("!", "[")):
            continue
        if "#@#" in line:
            domains, selector = line.split("#@#", 1)
            found = domains_of(domains, ",")
            if not domains:
                generic_allowed.add(selector)
            elif found and found[0] == "if-domain":
                site_allowed.setdefault(selector, set()).update(found[1])
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
        made_rules[made[1]].extend(made[0])
    blocks, exceptions, generichide, elemhide = (unique(made_rules[kind]) for kind in
                                                  ("block", "exception", "generichide", "elemhide"))
    for rule in blocks + exceptions + generichide + elemhide:
        check(rule)

    # A generic selector some sites allow is kept apart, with those sites left out.
    generic = [selector for selector in dict.fromkeys(generic) if selector not in generic_allowed]
    groups = [([s for s in generic if s not in site_allowed], None, True)]
    by_sites = {}
    for selector in generic:
        if selector in site_allowed:
            by_sites.setdefault(tuple(sorted(site_allowed[selector])), []).append(selector)
    groups += [(selectors, ("unless-domain", list(sites)), True) for sites, selectors in sorted(by_sites.items())]
    groups += [(selectors, (kind, list(domains)), False) for (kind, domains), selectors in sorted(specific.items())]
    hides = {(is_generic, has): [] for is_generic in (True, False) for has in (False, True)}
    for selectors, condition, is_generic in groups:
        selectors = list(dict.fromkeys(selectors))
        for has in (False, True):
            chosen = [selector for selector in selectors if (":has(" in selector) == has]
            hides[(is_generic, has)].extend(hide_rules(chosen, condition))

    page_exceptions = [rule for rule in exceptions if reaches_pages(rule)]
    generic_tail = generichide + elemhide + page_exceptions
    layouts = [
        (hides[(True, False)], generic_tail),
        (hides[(True, True)], generic_tail),
        (hides[(False, True)], elemhide + page_exceptions),
        (blocks + hides[(False, False)], elemhide + exceptions),
    ]
    closing = {"trigger": {"url-filter": ".*", "if-domain": X_DOMAINS}, "action": IGNORE}
    os.makedirs(output, exist_ok=True)
    for name in os.listdir(output):
        if re.match(r"^web-ads(-\d+)?\.json$", name):
            os.remove(os.path.join(output, name))
    names, digest = [], hashlib.sha256()
    for body, tail in layouts:
        for start in range(0, len(body), RULES_PER_LIST):
            text = json.dumps(body[start:start + RULES_PER_LIST] + tail + [closing], separators=(",", ":"))
            digest.update(text.encode())
            name = "web-ads-%d.json" % (len(names) + 1)
            with open(os.path.join(output, name), "w", encoding="utf-8") as out:
                out.write(text)
            names.append(name)
    with open(os.path.join(output, "web-ads.json"), "w", encoding="utf-8") as out:
        json.dump({"version": digest.hexdigest()[:12], "lists": names}, out)
    print("block %d, exceptions %d, generichide %d, elemhide %d, generic selectors %d, "
          "hiding rules %d (:has %d), lists %d, skipped %d"
          % (len(blocks), len(exceptions), len(generichide), len(elemhide), len(generic),
             sum(len(rules) for rules in hides.values()), len(hides[(True, True)]) + len(hides[(False, True)]),
             len(names), skipped))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
