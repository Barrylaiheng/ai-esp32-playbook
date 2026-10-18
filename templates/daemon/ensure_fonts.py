# -*- coding: utf-8 -*-
"""ensure_fonts.py -- pre-build guard for generated LVGL font subsets.

Copy to <project>/tools/ and edit the CONFIG block below (font sets + the
fontTools-capable python candidates), then call it from build-quiet.cmd
BEFORE ninja runs (see the guard block in that template).

Why this exists:
  The natural wiring is a CMake add_custom_command whose OUTPUT is the
  generated font .c and which appears in SRCS. On ESP-IDF v6.0.1 that path
  is BLOCKED by an IDF reconfigure bug: the quoted IDF_VER value written
  into COMPILE_DEFINITIONS is not re-escaped when IDF serializes
  build_properties.temp.cmake, producing a malformed set() line. Any
  add_custom_command in a component CMakeLists triggers a reconfigure that
  hits it. (Verified by isolation testing: an inert add_custom_target
  reconfigure passes; add_custom_command with generated SRCS fails.)

  So guard at build time instead. If a generated font .c is missing or
  older than its generator/inputs, regenerate it BEFORE the firmware
  compiles. This catches the exact footgun: firmware built before the
  generated font .c existed -> symbol missing from the .map -> full clean
  rebuild "to fix it".

  A normal build with committed .c files already up to date is a no-op:
  a fast mtime check, no npx invocation, no measurable overhead.

  Honest boundary: like the CMake approach, this CANNOT detect "a new UI
  string was added without touching the script or the TTF" -- that still
  needs a manual regen. What it does cover: build-before-generate, and
  script/TTF changes.

Exit code: 0 = all fonts up to date (possibly after regen); 1 = a regen
failed. The build script should treat 1 as a hard stop (never compile a
firmware with stale/broken fonts).
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- CONFIG ----
# Candidate pythons for running the generators, in preference order.
# The generator needs fontTools (TTFont cmap filtering) so lv_font_conv
# never receives characters the TTF cannot render. The IDF python env
# typically does NOT have fontTools -> HAVE_FT=False -> the cmap filter is
# skipped -> lv_font_conv aborts on unsupported chars. So a fontTools
# capable python must be found; sys.executable is only the last resort.
PY_CANDIDATES = [
    r"C:\Program Files\Python312\python.exe",
    sys.executable,
]

# One entry per font set: (generator script, [output .c files], [input dirs]).
# Outputs newer than max(generator mtime, newest file in input dirs) = fresh.
# Input dirs hold TTFs (files only, walked recursively); pass [] to depend on
# the generator script alone.
FONT_SETS = [
    {
        "script": os.path.join(ROOT, "tools", "gen_fonts.py"),
        "outputs": [
            os.path.join(ROOT, "components", "ui", "fonts", "dada_body_16.c"),
            os.path.join(ROOT, "components", "ui", "fonts", "dada_label_20.c"),
            os.path.join(ROOT, "components", "ui", "fonts", "dada_title_24.c"),
        ],
        "input_dirs": [os.path.join(ROOT, "assets", "fonts")],
    },
    {
        "script": os.path.join(ROOT, "tools", "gen_clock_fonts.py"),
        "outputs": [
            os.path.join(ROOT, "components", "ui", "fonts", "dada_clock_dig52.c"),
            os.path.join(ROOT, "components", "ui", "fonts", "dada_clock_dig27.c"),
        ],
        "input_dirs": [os.path.join(ROOT, "assets", "fonts", "candidates")],
    },
]


def find_fonts_python():
    """Pick the first candidate that can `import fontTools`."""
    seen = set()
    for cand in PY_CANDIDATES:
        if not cand or cand in seen:
            continue
        seen.add(cand)
        if not os.path.isfile(cand):
            continue
        try:
            rc = subprocess.run(
                [cand, "-c", "import fontTools"],
                capture_output=True, cwd=ROOT,
            ).returncode
        except OSError:
            continue
        if rc == 0:
            return cand
    return sys.executable


PY = find_fonts_python()


def newest_mtime_in_dirs(dirs):
    best = 0.0
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for dp, _dirs, files in os.walk(d):
            for f in files:
                try:
                    m = os.path.getmtime(os.path.join(dp, f))
                except OSError:
                    continue
                if m > best:
                    best = m
    return best


def stale_reason(font_set):
    """Return '' when fresh, else a human reason string."""
    for out in font_set["outputs"]:
        if not os.path.isfile(out):
            return "missing " + os.path.basename(out)
    # Depend on the generator script + input TTFs, NOT on the scanned UI
    # source dirs: source mtime would regenerate on every source edit,
    # defeating the no-op goal.
    deps = [os.path.getmtime(font_set["script"])]
    deps.append(newest_mtime_in_dirs(font_set.get("input_dirs", [])))
    base = max(deps)
    for out in font_set["outputs"]:
        if os.path.getmtime(out) < base:
            return "stale " + os.path.basename(out)
    return ""


def regen(script, why):
    print("[ensure_fonts] %s -> regenerating via %s"
          % (why, os.path.basename(script)))
    r = subprocess.run([PY, script], cwd=ROOT)
    return r.returncode == 0


def main():
    rc = 0
    for font_set in FONT_SETS:
        why = stale_reason(font_set)
        if why and not regen(font_set["script"], why):
            rc = 1
    if rc == 0:
        print("[ensure_fonts] all fonts up to date")
    sys.exit(rc)


if __name__ == "__main__":
    main()
