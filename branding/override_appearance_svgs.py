#!/usr/bin/env python3
"""Usage: override_appearance_svgs.py <app_dir> <svg_dir>. Invoked from ipa_branding.py.
Each svg replaces the same-named glyph in VectorImages/main of every TwitterAppearance
bundle (app and extensions); an svg matching no glyph is ignored.
"""

import os
import shutil
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: override_appearance_svgs.py <app_dir> <svg_dir>\n")
        return 2
    app_dir, svg_dir = sys.argv[1], sys.argv[2]

    # VectorImages/main glyphs of every TwitterAppearance bundle, by basename, with
    # the bundle root so its stale seal can be dropped later. Emoji stay untouched.
    index = {}  # basename -> [(path, bundle_root)]
    for root, dirs, _files in os.walk(app_dir):
        dirs[:] = [d for d in dirs if d != "__MACOSX"]
        for d in dirs:
            if "TwitterAppearance" in d and d.endswith(".bundle"):
                broot = os.path.join(root, d)
                maindir = os.path.join(broot, "VectorImages", "main")
                if not os.path.isdir(maindir):
                    continue
                for f in os.listdir(maindir):
                    if f.lower().endswith(".svg"):
                        index.setdefault(f, []).append((os.path.join(maindir, f), broot))

    # Apply each provided svg to all matching targets.
    modified_bundles = set()
    for sroot, sdirs, sfiles in os.walk(svg_dir):
        sdirs[:] = [d for d in sdirs if d != "__MACOSX"]
        for f in sfiles:
            if f.startswith("._") or not f.lower().endswith(".svg"):
                continue
            for path, broot in index.get(f, []):
                shutil.copyfile(os.path.join(sroot, f), path)
                modified_bundles.add(broot)

    # A replaced glyph breaks the bundle's own seal; dropping it lets the app's
    # re-seal (cyan and the installer) cover the bundle through CodeResources.
    for broot in sorted(modified_bundles):
        shutil.rmtree(os.path.join(broot, "_CodeSignature"), ignore_errors=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
