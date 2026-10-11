#!/usr/bin/env python3
"""Writes src/Support/Generated/PFBHookManifest.m: every hooked class and method and every class
resolved by name, checked against the running app by the debugger. Run from the repo root;
the Makefile calls it before each build. PrimeFreeBird's own classes are skipped.
"""

import os
import re
import sys

SRC = "src"
OUT = "src/Support/Generated/PFBHookManifest.m"

# A %hook line names the class; everything up to the matching %end is its body.
HOOK_RE = re.compile(r'^\s*%hook\s+([A-Za-z_][A-Za-z0-9_$]*)\s*$')
END_RE = re.compile(r'^\s*%end\s*$')
# A method inside a hook body: - (ret)name...  or  + (ret)name...
# The whole selector is read, across lines when needed, so the on-device check
# looks up the exact method rather than its first keyword.
METHOD_RE = re.compile(r'^\s*[-+]\s*\([^)]*\)\s*([A-Za-z_][A-Za-z0-9_]*)')


def full_selector(signature):
    # Every parenthesised type goes, innermost first so block types unwind too.
    body = re.sub(r'^\s*[-+]\s*', '', signature)
    while True:
        stripped = re.sub(r'\([^()]*\)', ' ', body)
        if stripped == body:
            break
        body = stripped
    pieces = re.findall(r'([A-Za-z_][A-Za-z0-9_]*)\s*:', body)
    if pieces:
        return ''.join(piece + ':' for piece in pieces)
    match = re.match(r'\s*([A-Za-z_][A-Za-z0-9_]*)', body)
    return match.group(1) if match else None
# Runtime class resolution, in all three spellings the sources use.
BYNAME_RE = re.compile(
    r'%c\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'
    r'|objc_getClass\(\s*"([A-Za-z_][A-Za-z0-9_.]*)"\s*\)'
    r'|NSClassFromString\(\s*@"([A-Za-z_][A-Za-z0-9_.]*)"\s*\)'
)


def source_files():
    for root, _dirs, files in os.walk(SRC):
        if "Generated" in root:
            continue
        for name in sorted(files):
            if name.endswith(".x") or name.endswith(".m"):
                yield os.path.join(root, name)


def parse():
    # class -> set of hooked methods (a class hooked with no method still counts)
    hooks = {}
    byname = set()
    # Classes implemented in src/, and FLEX, Cephei and Preferences ones by prefix, ship with
    # PrimeFreeBird rather than Twitter, so they are not checked against the app. An
    # @interface alone only redeclares a class of the app; categories never count.
    own_classes = set()
    own_prefixes = ("FLEX", "HBForce", "Cephei", "PS")
    implementation_re = re.compile(r'^@implementation\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\{.*)?$')

    for path in source_files():
        with open(path, encoding="utf-8") as handle:
            lines = handle.readlines()
        for line in lines:
            match = implementation_re.match(line)
            if match:
                own_classes.add(match.group(1))

    for path in source_files():
        rel = os.path.relpath(path, SRC)
        with open(path, encoding="utf-8") as handle:
            lines = handle.readlines()
        current = None
        pending_new = False  # the next method line is a %new, added here
        signature = None  # a method declaration still being read, up to its "{"
        signature_is_new = False
        for line in lines:
            stripped = line.split("//", 1)[0]  # ignore line comments
            if signature is not None and not HOOK_RE.match(stripped) and not END_RE.match(stripped):
                signature += " " + stripped
                if "{" in stripped:
                    selector = full_selector(signature.split("{", 1)[0])
                    if selector and current and not signature_is_new:
                        hooks[current]["methods"].setdefault(selector, rel)
                    signature = None
                continue
            hook = HOOK_RE.match(stripped)
            if hook:
                current = hook.group(1)
                hooks.setdefault(current, {"methods": {}, "file": rel})
                pending_new = False
                signature = None
                continue
            if END_RE.match(stripped):
                current = None
                pending_new = False
                signature = None
                continue
            # A %new anywhere on the line means the method that follows is added here, not a
            # Twitter dependency, so it is never a missing hook.
            if "%new" in stripped:
                pending_new = True
                continue
            if current:
                method = METHOD_RE.match(stripped)
                if method:
                    is_new = pending_new
                    pending_new = False  # consumed by this method
                    if "{" in stripped:
                        selector = full_selector(stripped.split("{", 1)[0])
                        if selector and not is_new:
                            hooks[current]["methods"].setdefault(selector, rel)
                    else:
                        signature = stripped
                        signature_is_new = is_new
            for match in BYNAME_RE.finditer(stripped):
                name = match.group(1) or match.group(2) or match.group(3)
                if name:
                    byname.add(name)

    def is_own(name):
        return name in own_classes or name.startswith(own_prefixes)

    hooks = {cls: info for cls, info in hooks.items() if not is_own(cls)}
    byname = {name for name in byname if not is_own(name)}
    return hooks, byname


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def emit(hooks, byname):
    lines = []
    lines.append("// GENERATED by tools/gen-hook-manifest.py on every build. Do not edit.")
    lines.append("")
    lines.append('#import "Support/Generated/PFBHookManifest.h"')
    lines.append("")

    # Flattened method table: one row per (class, method), plus one row per
    # class with a NULL method so a class hooked with no method is still checked.
    lines.append("const PFBHookRecord PFBHookRecords[] = {")
    for cls in sorted(hooks):
        info = hooks[cls]
        file_literal = escape(info["file"])
        methods = sorted(info["methods"].items())
        if not methods:
            lines.append(
                '    {"%s", NULL, "%s"},' % (escape(cls), file_literal))
        else:
            # Each method names the file that hooks it, not the class's first file.
            for method, method_file in methods:
                lines.append(
                    '    {"%s", "%s", "%s"},'
                    % (escape(cls), escape(method), escape(method_file)))
    lines.append("};")
    lines.append(
        "const size_t PFBHookRecordCount = "
        "sizeof(PFBHookRecords) / sizeof(PFBHookRecords[0]);")
    lines.append("")

    lines.append("const char* const PFBRuntimeClasses[] = {")
    for name in sorted(byname):
        lines.append('    "%s",' % escape(name))
    lines.append("};")
    lines.append(
        "const size_t PFBRuntimeClassCount = "
        "sizeof(PFBRuntimeClasses) / sizeof(PFBRuntimeClasses[0]);")
    lines.append("")
    return "\n".join(lines)


def emit_header():
    return """// GENERATED by tools/gen-hook-manifest.py on every build. Do not edit.
#import <stddef.h>

typedef struct {
    const char* className;
    const char* methodName;  // NULL when the class is hooked with no method
    const char* file;
} PFBHookRecord;

extern const PFBHookRecord PFBHookRecords[];
extern const size_t PFBHookRecordCount;

extern const char* const PFBRuntimeClasses[];
extern const size_t PFBRuntimeClassCount;
"""


def main():
    if not os.path.isdir(SRC):
        sys.stderr.write("gen-hook-manifest: run from the repo root (no src/)\n")
        return 1
    hooks, byname = parse()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write(emit(hooks, byname))
    header = os.path.join(os.path.dirname(OUT), "PFBHookManifest.h")
    with open(header, "w", encoding="utf-8") as handle:
        handle.write(emit_header())

    method_rows = sum(
        len(info["methods"]) or 1 for info in hooks.values())
    sys.stderr.write(
        "gen-hook-manifest: %d classes, %d method rows, %d runtime classes\n"
        % (len(hooks), method_rows, len(byname)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
