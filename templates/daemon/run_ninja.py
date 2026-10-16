"""run_ninja.py - launch ninja for the build with a detached stdin.

Why this wrapper exists
-----------------------
When ninja is started *directly by cmd.exe* inside the build daemon, ninja
inherits the daemon's hidden console as its stdin. In that configuration the
`ldgen` step (Generating esp-idf/esp_system/ld/sections.ld) deterministically
dies with exit code -1 ("Batch file failed at line 3 with errorcode -1"),
although the very same command succeeds when stdin is not that console.

Verified on a real project:
    ninja launched directly by cmd from the daemon  -> ldgen rc = -1 (build fails)
    ninja launched via python with stdin=DEVNULL    -> ldgen rc =  0 (build OK)

So the build daemon always goes through this wrapper. stdout/stderr are
left inherited, so the caller's `>> build.log 2>&1` redirection still works.

Usage: python run_ninja.py -C <build_dir> [-j N]
"""

import subprocess
import sys

args = ["ninja"] + sys.argv[1:]
rc = subprocess.run(args, stdin=subprocess.DEVNULL).returncode
sys.exit(rc)
