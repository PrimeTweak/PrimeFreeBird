#!/usr/bin/env python3
"""Usage: scar_merge.py <app_Assets.car> <overlay_dir> <out.car> --workdir DIR [--scar BIN]
Rebuilds Assets.car with scar: an image named like an asset replaces all its renditions,
one named like a rendition replaces only it, any other becomes a new alternate icon.
"""

import argparse
import json
import os
import re
import subprocess
import sys

from PIL import Image

# Settings-picker thumbnails (<Icon>-settings) reuse their base icon's image.
SETTINGS_SPECIAL = {"icon-production-settings": "ProductionAppIcon"}


def run_scar(scar, *args):
    res = subprocess.run([scar, *args], capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write("scar %s failed:\n%s\n%s\n" % (args[0], res.stdout, res.stderr))
        raise SystemExit(1)
    return res


_resize_cache = {}


def pad_resize(master, w, h):
    """Aspect-preserving resize of `master` to exactly w x h, centered on a
    transparent canvas (a square master is never stretched into a non-square
    slot). Cached per (master, w, h)."""
    key = (master, w, h)
    if key not in _resize_cache:
        try:
            im = Image.open(master).convert("RGBA")
        except OSError as exc:
            sys.stderr.write("unreadable image %s: %s (Apple-optimized CgBI PNGs "
                             "must be converted to standard PNG)\n" % (master, exc))
            raise SystemExit(1)
        scale = min(w / im.width, h / im.height)
        nw, nh = max(1, round(im.width * scale)), max(1, round(im.height * scale))
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        canvas.paste(im.resize((nw, nh), Image.LANCZOS), ((w - nw) // 2, (h - nh) // 2))
        _resize_cache[key] = canvas
    return _resize_cache[key]


def install(catalog, rend, master):
    """Write `master` (pad-resized) as the edited pixels of one rendition.
    Returns False for renditions with no editable pixels (multisize stubs,
    data, undecodable codecs)."""
    c = rend["content"]
    if c["type"] == "image":
        target, w, h = c["file"], rend["width"], rend["height"]
    elif c["type"] == "raw-payload" and c.get("preview") and c.get("edit_hash"):
        target, w, h = c["preview"], rend["width"], rend["height"]
    elif c["type"] == "link" and c.get("preview") and c.get("edit_hash"):
        target, (w, h) = c["preview"], c["rect"][2:4]
    else:
        return False
    pad_resize(master, w, h).save(os.path.join(catalog, target))
    return True


def load_catalog(catalog):
    manifest = json.load(open(os.path.join(catalog, "manifest.json")))
    facets = {f["name"]: f["attributes"].get("identifier") for f in manifest["facets"]}
    by_ident = {}
    for r in manifest["renditions"]:
        by_ident.setdefault(r["key"].get("identifier"), []).append(r)
    return manifest, facets, by_ident


def settings_base(name):
    low = name.lower()
    if low in SETTINGS_SPECIAL:
        return SETTINGS_SPECIAL[low]
    if low.endswith("-settings"):
        return name[: -len("-settings")]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("car")
    ap.add_argument("overlay_dir")
    ap.add_argument("out_car")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--scar", default=os.environ.get("PFB_SCAR", "scar"))
    args = ap.parse_args()

    catalog = os.path.join(args.workdir, "catalog")
    run_scar(args.scar, "decompile", args.car, "--out", catalog)
    manifest, facets, by_ident = load_catalog(catalog)

    # Overlay files by exact name (single-rendition overrides) and by stem
    # ("master" images resized into every rendition of the matching asset).
    overlays, masters = {}, {}
    for root, dirs, files in os.walk(args.overlay_dir):
        dirs[:] = [d for d in dirs if d != "__MACOSX"]
        for f in files:
            if f.startswith("._") or not f.lower().endswith((".png", ".jpg", ".jpeg")):
                continue
            overlays.setdefault(f, os.path.join(root, f))
            masters.setdefault(os.path.splitext(f)[0].lower(), os.path.join(root, f))
    used = set()

    # App-icon assets are the facets that own multisize (MSIS) stubs.
    icon_names = {n for n, i in facets.items()
                  if any(r["content"]["type"] == "multisize" for r in by_ident.get(i, []))}
    primary = None
    for n in sorted(icon_names):
        if primary is None or "production" in n.lower():
            primary = n

    def master_for(name):
        m = masters.get(name.lower())
        if m:
            return m
        base = settings_base(name)
        if base:
            m = masters.get(base.lower())
            if m:
                return m
            if base in icon_names and "appicon" in masters:
                return masters["appicon"]
        if name in icon_names and "appicon" in masters:
            return masters["appicon"]
        return None

    # 1. Replace pixels of existing assets. Exact rendition-name overlays beat
    #    the asset master.
    themed = set()
    for name, ident in facets.items():
        m = master_for(name)
        count = 0
        for r in by_ident.get(ident, []):
            src = overlays.get(r["name"]) or m
            if src and install(catalog, r, src):
                used.add(src)
                count += 1
        if count:
            themed.add(name)
            print("replace: %s (%d renditions)" % (name, count))

    # 2. New alternate icons: unmatched masters cloned from a stock alternate built
    #    from its own images, before step 3 drops that template.
    def self_contained(n):
        return all(r["content"]["type"] != "link" for r in by_ident.get(facets[n], []))

    template = next((n for n in sorted(icon_names)
                     if n != primary and self_contained(n) and "%s-settings" % n in facets), None)
    new_icons = []
    for f, path in sorted(overlays.items()):
        stem = os.path.splitext(f)[0]
        if path in used or stem in facets:
            continue
        if "@" in stem or re.search(r"\d+x\d+", stem):  # a rendition file, not a master
            continue
        if not template:
            sys.stderr.write("no-template: %s (no self-contained alternate icon to clone)\n" % f)
            continue
        run_scar(args.scar, "clone-asset", catalog, "--from", template, "--to", stem)
        run_scar(args.scar, "clone-asset", catalog, "--from", "%s-settings" % template,
                 "--to", "%s-settings" % stem)
        new_icons.append((stem, path))
        used.add(path)

    if new_icons:
        # clone-asset rewrote the manifest: reload it, then size each clone to its
        # master's own resolution, since upscaled 1024 px art weighs megabytes
        # and iOS scales icons from whatever sizes the catalog offers.
        manifest, facets, by_ident = load_catalog(catalog)
        for stem, path in new_icons:
            native = min(Image.open(path).size)
            for r in by_ident.get(facets[stem], []):
                c = r["content"]
                if c["type"] == "image" and r["width"] > native:
                    r["width"] = r["height"] = native
                elif c["type"] == "multisize":
                    for e in c["sizes"]:
                        e["width"] = min(e["width"], native)
                        e["height"] = min(e["height"], native)
            for name in (stem, "%s-settings" % stem):
                for r in by_ident.get(facets[name], []):
                    install(catalog, r, path)
            print("new icon: %s" % stem)
        json.dump(manifest, open(os.path.join(catalog, "manifest.json"), "w"), indent=2)

    # 3. Drop stock alternates that got no replacement art, plus their
    #    -settings thumbnails, so the base app's icons don't linger in the
    #    picker alongside the pack's.
    drop = {n for n in icon_names if n != primary and n not in themed}
    drop |= {n for n in facets if settings_base(n) in drop and n not in themed}
    if drop:
        gone = {facets[n] for n in drop}
        manifest["facets"] = [f for f in manifest["facets"] if f["name"] not in drop]
        manifest["renditions"] = [r for r in manifest["renditions"]
                                  if r["key"].get("identifier") not in gone]
        json.dump(manifest, open(os.path.join(catalog, "manifest.json"), "w"), indent=2)
        print("dropped: %s" % ", ".join(sorted(drop)))

    run_scar(args.scar, "compile", catalog, "--out", args.out_car)

    for p in sorted(set(overlays.values()) - used):
        sys.stderr.write("overlay-unmatched: %s (no rendition or asset with that name)\n"
                         % os.path.basename(p))
    return 0


if __name__ == "__main__":
    sys.exit(main())
