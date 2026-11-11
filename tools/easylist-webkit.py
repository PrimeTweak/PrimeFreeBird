#!/usr/bin/env python3
"""Turns EasyList, EasyPrivacy and Fanboy's Annoyance list (uBlock Origin edition) into Block web
ads: WebKit content-blocker lists, and the rules of its page engine, web-ads-engine.js.

Usage: easylist-webkit.py EASYLIST OUTPUT_DIR
EASYLIST is an EasyList checkout (its easylist, easyprivacy and fanboy-annoyance-uBO templates are
followed) or a single filter list. OUTPUT_DIR receives web-ads.json, web-ads-N.json and web-ads-page.json.

Each list carries the exceptions that can apply to it and ends by leaving X's own pages alone;
generic hiding and :has() selectors have lists of their own. The page engine takes what WebKit
cannot express; redirections to stand-in resources are left out.
"""
import hashlib
import json
import os
import re
import sys

TEMPLATES = ("easylist.template", "easyprivacy.template", "fanboy-annoyance-uBO.template")
RULES_PER_LIST = 15000
SELECTORS_PER_RULE = 250
X_DOMAINS = ["*x.com", "*twitter.com", "*twimg.com", "*t.co"]
# A site written name.* stands for these endings in a network rule, which WebKit only takes whole.
ENTITY_ENDINGS = (
    "com", "net", "org", "info", "biz", "io", "co", "me", "tv", "eu", "us", "uk", "co.uk", "ca", "de",
    "fr", "it", "es", "nl", "be", "ch", "at", "se", "no", "dk", "fi", "pl", "pt", "ie", "cz", "sk", "hu",
    "ro", "gr", "tr", "ru", "ua", "jp", "co.jp", "kr", "co.kr", "cn", "com.cn", "tw", "com.tw", "hk",
    "com.hk", "sg", "com.sg", "in", "co.in", "au", "com.au", "nz", "co.nz", "br", "com.br", "mx",
    "com.mx", "ar", "com.ar", "cl", "za", "co.za")

TYPES = {
    "script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font",
    "media": "media", "subdocument": "document", "xmlhttprequest": "raw", "websocket": "raw",
    "ping": "raw", "other": "raw", "popup": "popup",
}
ALL_TYPES = sorted(set(TYPES.values()))
PAGE_OPTIONS = {"generichide": "generichide", "ghide": "generichide", "elemhide": "elemhide", "ehide": "elemhide"}
IGNORED_OPTIONS = {"important"}
UNSUPPORTED_PSEUDO = re.compile(
    r"(?<!\\):(-abp-|-ext-|abp-|has-text|xpath|upward|remove|style|matches-|contains|min-text-length|"
    r"watch-attr|others|nth-ancestor|if\(|if-not|spath|shadow)")
DOMAIN = re.compile(r"^[a-z0-9.-]+$")
SPECIALS = set(".+?$()[]{}\\|")
IGNORE = {"type": "ignore-previous-rules"}

# Page engine: the operators and scripts web-ads-engine.js knows.
NATIVE_FUNCTIONS = {"not", "is", "where", "has", "nth-child", "nth-last-child", "nth-of-type",
                    "nth-last-of-type", "lang", "dir"}
PROCEDURAL = {"has-text", "xpath", "upward", "matches-path"}
ACTIONS = {"style", "remove", "remove-class"}
SCRIPTLETS = {
    "set-constant", "set", "abort-on-property-read", "aopr", "abort-on-property-write", "aopw",
    "abort-current-script", "acs", "acis", "abort-on-stack-trace", "aost",
    "addEventListener-defuser", "aeld", "prevent-addEventListener", "no-setTimeout-if", "nostif",
    "prevent-setTimeout", "no-setInterval-if", "nosiif", "no-requestAnimationFrame-if", "norafif",
    "no-xhr-if", "no-fetch-if", "remove-node-text", "rmnt", "remove-class", "rc", "remove-attr", "ra",
    "json-prune", "json-edit", "set-cookie", "set-cookie-reload", "remove-cookie", "cookie-remover",
    "set-local-storage-item", "set-session-storage-item", "prevent-dialog",
}


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


def ascii_domain(item):
    """A site written in its own alphabet, as WebKit and the page see it."""
    excluded = "~" if item.startswith("~") else ""
    name = item[len(excluded):]
    ending = ".*" if name.endswith(".*") else ""
    name = name[:len(name) - len(ending)]
    try:
        name = name if name.isascii() else name.encode("idna").decode("ascii")
    except UnicodeError:
        pass
    return excluded + name + ending


def domains_of(text, separator, entities=False):
    positive, negative = [], []
    for item in filter(None, (ascii_domain(part.strip().lower()) for part in text.split(separator))):
        target = negative if item.startswith("~") else positive
        item = item.lstrip("~")
        if item.endswith(".*") and DOMAIN.match(item[:-2]):
            if not entities:
                return None
            target.extend("*%s.%s" % (item[:-2], ending) for ending in ENTITY_ENDINGS)
            continue
        if not DOMAIN.match(item) or "*" in item:
            return None
        target.append("*" + item)
    if positive and negative:
        return None
    return ("if-domain", positive) if positive else ("unless-domain", negative) if negative else ("", [])


def engine_domains(text):
    """Sites for the page engine: names, or name.* for any ending, each possibly excluded."""
    included, excluded = [], []
    for item in filter(None, (ascii_domain(part.strip().lower()) for part in text.split(","))):
        target = excluded if item.startswith("~") else included
        item = item.lstrip("~")
        name = item[:-2] if item.endswith(".*") else item
        if not DOMAIN.match(name) or not name.strip("."):
            return None
        target.append(item)
    return included, excluded


def regex_parts(pattern):
    """Splits a regular expression into WebKit's subset: no alternation, braces or shorthand
    classes. Returns the url-filters it stands for, or None."""
    shorthand = {"d": "0-9", "w": "a-zA-Z0-9_"}
    position = [0]

    def atom_class():
        start = position[0]
        position[0] += 1
        body = "["
        if pattern[position[0]:position[0] + 1] == "^":
            body += "^"
            position[0] += 1
        while position[0] < len(pattern) and pattern[position[0]] != "]":
            ch = pattern[position[0]]
            if ch == "\\":
                following = pattern[position[0] + 1:position[0] + 2]
                body += shorthand.get(following, "\\" + following if following in "]\\^-" else following)
                position[0] += 2
                continue
            body += ch
            position[0] += 1
        if position[0] >= len(pattern) or position[0] == start + 1:
            raise ValueError("class")
        position[0] += 1
        return [body + "]"]

    def sequence():
        variants = [""]
        while position[0] < len(pattern) and pattern[position[0]] not in "|)":
            ch = pattern[position[0]]
            if ch == "(":
                position[0] += 1
                if pattern.startswith("?:", position[0]):
                    position[0] += 2
                elif pattern.startswith("?", position[0]):
                    raise ValueError("lookaround")
                inner = alternation()
                if pattern[position[0]:position[0] + 1] != ")":
                    raise ValueError("group")
                position[0] += 1
                repeated = pattern[position[0]:position[0] + 1] in ("*", "+", "?", "{")
                atoms = ["(%s)" % part if repeated and len(part) > 1 else part for part in inner]
            elif ch == "[":
                atoms = atom_class()
            elif ch == "\\":
                following = pattern[position[0] + 1:position[0] + 2]
                if following in shorthand:
                    atoms = ["[%s]" % shorthand[following]]
                elif following and not following.isalnum():
                    atoms = ["\\" + following if following in ".+?*()[]$^\\/{}|" else following]
                else:
                    raise ValueError("escape")
                position[0] += 2
            elif ch in "^$":
                atoms = [ch]
                position[0] += 1
            elif ch in "{}*+?":
                raise ValueError("quantifier")
            else:
                atoms = ["\\" + ch if ch in "/" else ch]
                position[0] += 1
            atoms = [quantified(atom) for atom in atoms]
            variants = [variant + atom for variant in variants for atom in atoms]
            if len(variants) > 64:
                raise ValueError("too many")
        return variants

    def quantified(atom):
        rest = pattern[position[0]:]
        braces = re.match(r"\{(\d+)(,(\d*))?\}\??", rest)
        if braces:
            position[0] += len(braces.group(0))
            low = int(braces.group(1))
            high = low if not braces.group(2) else (int(braces.group(3)) if braces.group(3) else None)
            if low > 120 or (high is not None and (high < low or high > 120)):
                raise ValueError("repeat")
            text = atom * low
            return text + (atom + "*" if high is None else (atom + "?") * (high - low))
        simple = re.match(r"[*+?]\??", rest)
        if simple:
            position[0] += len(simple.group(0))
            return atom + simple.group(0)[0]
        return atom

    def alternation():
        variants = sequence()
        while pattern[position[0]:position[0] + 1] == "|":
            position[0] += 1
            variants += sequence()
        return variants

    try:
        variants = alternation()
        if position[0] != len(pattern):
            return None
    except (ValueError, IndexError):
        return None
    filters = []
    for variant in variants:
        inner = variant[1:] if variant.startswith("^") else variant
        inner = inner[:-1] if inner.endswith("$") and not inner.endswith("\\$") else inner
        if re.search(r"(?<!\\)[$^](?![^\[]*\])", inner) or not variant:
            return None
        filters.append(variant)
    return filters


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
    plugins_only = False
    for option in options:
        name = option.strip().lower()
        if name in IGNORED_OPTIONS or name == "~object":
            continue
        if name in ("third-party", "3p"):
            trigger["load-type"] = ["third-party"]
        elif name in ("~third-party", "1p", "first-party"):
            trigger["load-type"] = ["first-party"]
        elif name == "match-case":
            case_sensitive = True
        elif name.startswith("domain="):
            found = domains_of(option.strip()[7:], "|", entities=True)
            if found is None:
                return None
            if found[0]:
                trigger[found[0]] = found[1]
        elif name in TYPES:
            types.add(TYPES[name])
        elif name.startswith("~") and name[1:] in TYPES:
            negated.add(TYPES[name[1:]])
        elif name in ("~document", "~doc"):
            negated.add("document")
        elif name == "object":
            plugins_only = True
        elif name in ("document", "doc"):
            whole_site = exception and len(options) == 1
            types.add("document")
        elif exception and name in PAGE_OPTIONS:
            page = PAGE_OPTIONS[name]
        else:
            return None
    # WebKit loads no plugins, so a rule only about them has nothing to act on.
    if plugins_only and not types:
        return [], "block"
    if whole_site:
        site = re.match(r"^\|\|([a-z0-9.-]+)\^?$", pattern.lower())
        if not site:
            return None
        return [{"trigger": {"url-filter": ".*", "if-domain": ["*" + site.group(1)]}, "action": IGNORE}], "exception"
    if page and (types or negated):
        return None
    if negated:
        types = (types or set(ALL_TYPES)) - negated
        if not types:
            return None
    if pattern.startswith("/") and pattern.endswith("/") and len(pattern) > 2:
        regexes = regex_parts(pattern[1:-1])
    else:
        regexes = [url_filter(pattern, case_sensitive)]
    if not regexes or None in regexes:
        return None
    rules = []
    for regex in regexes:
        made = made_rules(dict({"url-filter": regex}, **trigger), types, case_sensitive, page, exception,
                          pattern.startswith("||"))
        rules.extend(made)
    return rules, page or ("exception" if exception else "block")


def made_rules(trigger, types, case_sensitive, page, exception, names_site):
    if case_sensitive:
        trigger["url-filter-is-case-sensitive"] = True
    # Hiding is cancelled on the page itself, the load of its document.
    if page:
        trigger["resource-type"] = ["document"]
        return [{"trigger": trigger, "action": IGNORE}]
    if exception:
        if types:
            trigger["resource-type"] = sorted(types)
        return [{"trigger": trigger, "action": IGNORE}]
    # A page the user opens is never blocked by a pattern that only names a path: WebKit's
    # document type also covers the top frame, so documents are blocked in frames only.
    types = types or set(ALL_TYPES)
    rules = []
    if "document" in types and not names_site:
        frames = dict(trigger, **{"resource-type": ["document"], "load-context": ["child-frame"]})
        rules.append({"trigger": frames, "action": {"type": "block"}})
        types = types - {"document"}
    if types:
        if types != set(ALL_TYPES):
            trigger["resource-type"] = sorted(types)
        rules.insert(0, {"trigger": trigger, "action": {"type": "block"}})
    return rules


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


def closing_paren(text, start):
    """Index of the parenthesis closing the one at start, past quotes and escapes."""
    depth, quote, index = 0, None, start
    while index < len(text):
        ch = text[index]
        if ch == "\\":
            index += 2
            continue
        if quote:
            quote = None if ch == quote else quote
        elif ch in "\"'":
            quote = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return -1


def pseudo_functions(selector):
    """The functional pseudo-classes written at the top level of a selector: (name, argument, end)."""
    found, index, bracket, quote = [], 0, 0, None
    while index < len(selector):
        ch = selector[index]
        if ch == "\\":
            index += 2
            continue
        if quote:
            quote = None if ch == quote else quote
        elif ch in "\"'":
            quote = ch
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket -= 1
        elif ch == ":" and not bracket:
            named = re.match(r":(-?[a-zA-Z][\w-]*)\(", selector[index:])
            if named:
                open_at = index + len(named.group(0)) - 1
                close = closing_paren(selector, open_at)
                if close < 0:
                    return None
                found.append((named.group(1).lower(), selector[open_at + 1:close], close + 1))
                index = close + 1
                continue
        index += 1
    return found


def selector_kind(selector):
    """plain, procedural, or None for a selector the page engine cannot read."""
    functions = pseudo_functions(selector)
    if functions is None:
        return None
    kind = "plain"
    for name, argument, _ in functions:
        if name in PROCEDURAL:
            kind = "procedural"
        elif name in ("has", "not"):
            inner = selector_kind(argument.lstrip(" >+~"))
            if inner is None:
                return None
            if inner == "procedural" or (name == "has" and ":has(" in argument):
                kind = "procedural"
        elif name not in NATIVE_FUNCTIONS:
            return None
    return kind


def cosmetic(selector):
    """Splits a cosmetic rule into what applies it: ("css", sel), ("style", sel, declarations) or
    ("proc", text); None for what neither the content blockers nor the page engine can express."""
    injected = re.match(r"^(.*?[^\\\s])\s*\{\s*(.*?)\s*\}\s*$", selector)
    if injected and "{" not in injected.group(1):
        selector, declarations = injected.group(1), injected.group(2)
        return ("style", selector, declarations) if selector_kind(selector) == "plain" else None
    functions = pseudo_functions(selector)
    if functions is None:
        return None
    last = functions[-1] if functions else None
    action = last if last and last[0] in ACTIONS and last[2] == len(selector.rstrip()) else None
    base = selector[:selector.rfind(":" + action[0] + "(")] if action else selector
    if not base.strip() or any(name in ACTIONS for name, _, _ in pseudo_functions(base) or []):
        return None
    kind = selector_kind(base)
    if kind is None:
        return None
    if action and action[0] == "style" and kind == "plain":
        return ("style", base, action[1])
    if action or kind == "procedural":
        return ("proc", selector)
    return ("css", base)


def scriptlet_args(text):
    """uBlock Origin's argument list: commas split, a quoted argument keeps them, \\, escapes one."""
    args, index = [], 0
    while index <= len(text):
        while index < len(text) and text[index] == " ":
            index += 1
        quote = text[index] if index < len(text) and text[index] in "'\"`" else None
        if quote:
            end = index + 1
            while end < len(text) and (text[end] != quote or text[end - 1] == "\\"):
                end += 1
            after = text[end + 1:].lstrip(" ")
            if end < len(text) and (not after or after.startswith(",")):
                args.append(text[index + 1:end])
                index = len(text) - len(after) + 1
                continue
        end = index
        while end < len(text) and not (text[end] == "," and text[end - 1] != "\\"):
            end += 1
        args.append(text[index:end].strip().replace("\\,", ","))
        index = end + 1
    return args


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


class Engine:
    """The page engine's rules, each kept once with every site it applies to."""

    def __init__(self):
        self.rules, self.sites = {}, {}

    def add(self, payload, included, excluded):
        key = json.dumps([payload, sorted(excluded)])
        self.rules.setdefault(key, [payload, sorted(set(excluded))])
        self.sites.setdefault(key, set()).update(included)

    def data(self, trusted, generichide):
        rules, hosts, generic = [], {}, []
        for key, (payload, excluded) in self.rules.items():
            index = len(rules)
            rules.append(payload + [excluded] if excluded else payload)
            if self.sites[key]:
                for site in sorted(self.sites[key]):
                    hosts.setdefault(site, []).append(index)
            else:
                generic.append(index)
        return {"rules": rules, "hosts": hosts, "generic": generic, "trusted": sorted(trusted),
                "generichide": sorted(generichide), "x": [domain[1:] for domain in X_DOMAINS]}


def page_rule(line, engine):
    """Takes a cosmetic or script rule into the page engine; False when it cannot."""
    separator = re.search(r"#(\?|\$)?#", line)
    domains, body = line[:separator.start()], line[separator.end():]
    sites = engine_domains(domains)
    if sites is None or body.startswith("^"):
        return False
    if body.startswith("+js(") and body.endswith(")"):
        args = scriptlet_args(body[4:-1])
        name = re.sub(r"\.js$", "", args[0])
        if name not in SCRIPTLETS or not sites[0]:
            return False
        engine.add(["js", name] + args[1:], *sites)
        return True
    made = cosmetic(body)
    if made is None:
        return False
    engine.add(list(made), *sites)
    return True


def csp_rule(line, engine):
    """$csp=policy rules go to the page engine, which writes the policy into the page."""
    found = re.match(r"^(\|\|([a-z0-9.-]+)\^)?\$csp=([^,]+)(,.*)?$", line)
    if not found:
        return False
    included = [found.group(2)] if found.group(2) else []
    excluded = []
    for option in (found.group(4) or "").split(",")[1:]:
        if option.startswith("domain="):
            for site in option[7:].split("|"):
                (excluded if site.startswith("~") else included).append(site.lstrip("~"))
        elif option not in ("~third-party", "1p"):
            return False
    if not included:
        return False
    engine.add(["csp", found.group(3)], included, excluded)
    return True


def main(source, output):
    made_rules_of = {"block": [], "exception": [], "generichide": [], "elemhide": []}
    generic, generic_allowed, site_allowed, specific = [], set(), {}, {}
    engine, trusted, generichide_sites = Engine(), set(), set()
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
        if re.search(r"#[?$%@]+#|#\+js", line) or "##+js(" in line:
            skipped += 0 if page_rule(line, engine) else 1
            continue
        if "##" in line:
            domains, selector = line.split("##", 1)
            found = domains_of(domains, ",")
            if selector_ok(selector) and found is not None and (found[0] or not domains):
                if not domains:
                    generic.append(selector)
                else:
                    specific.setdefault((found[0], tuple(sorted(found[1]))), []).append(selector)
                continue
            skipped += 0 if page_rule(line, engine) else 1
            continue
        if "$csp=" in line:
            skipped += 0 if csp_rule(line, engine) else 1
            continue
        made = network_rule(line)
        if made is None:
            skipped += 1
            continue
        made_rules_of[made[1]].extend(made[0])
        site = re.match(r"^@@\|\|([a-z0-9.-]+)\^?\$(document|generichide)$", line)
        site_list = re.match(r"^@@\$generichide,domain=([a-z0-9.|-]+)$", line)
        if site:
            (trusted if site.group(2) == "document" else generichide_sites).add(site.group(1))
        elif site_list:
            generichide_sites.update(site_list.group(1).split("|"))
    blocks, exceptions, generichide, elemhide = (unique(made_rules_of[kind]) for kind in
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
        if re.match(r"^web-ads(-\d+|-page)?\.json$", name):
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
    page = engine.data(trusted, generichide_sites)
    with open(os.path.join(output, "web-ads-page.json"), "w", encoding="utf-8") as out:
        json.dump(page, out, separators=(",", ":"), ensure_ascii=False)
    kinds = {}
    for rule in page["rules"]:
        kinds[rule[0]] = kinds.get(rule[0], 0) + 1
    print("block %d, exceptions %d, generichide %d, elemhide %d, generic selectors %d, "
          "hiding rules %d (:has %d), lists %d, page rules %s, skipped %d"
          % (len(blocks), len(exceptions), len(generichide), len(elemhide), len(generic),
             sum(len(rules) for rules in hides.values()), len(hides[(True, True)]) + len(hides[(False, True)]),
             len(names), kinds, skipped))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
