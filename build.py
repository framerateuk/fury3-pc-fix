#!/usr/bin/env python3
"""Build a ready-to-run Fury3 folder for modern PCs from your own CD.

Usage:
  python3 build.py DISC.cue|DISC.ccd [--out DIR] [--windows]

  DISC          your Fury3 CD (Microsoft, 1995, v1.1.0.1, volume label MSFURY3) as .cue + .bin or .ccd + .img
  --out         where to create Fury3/ (default: this folder)
  --windows     a folder for Windows only: the same game/ folder, without the Steam Deck launch script

Needs Python 3.8+ and nothing else: no wrapper DLLs, no downloads.
Nothing from the game is in this repository: every game file comes from your disc.
"""
import argparse, hashlib, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import disc, patch_exe

POD_MD5 = "095d4bf9561e15fb17b6dcfd9ce6ec60"           # FURY3\SYSTEM\FURY3.POD, the game data
PATCHED_MD5 = "961813b1d254649ed12a5ad7dcea5a05"


def md5(data): return hashlib.md5(data).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("disc"); ap.add_argument("--out", default=HERE); ap.add_argument("--windows", action="store_true")
    a = ap.parse_args()

    tracks = disc.tracks(a.disc)
    data = [t for t in tracks if t.kind != "AUDIO"]
    if not data: sys.exit("no data track in " + a.disc)
    dt = disc.DataTrack(data[0])
    if dt.label() != "MSFURY3": print(f"warning: volume label is {dt.label()!r}, this kit was made for MSFURY3")
    entries = {p.upper(): (p, is_dir, l, s) for p, is_dir, l, s in dt.walk()}
    for key, want in [("FURY3/FURY3.EXE", patch_exe.MD5), ("FURY3/SYSTEM/FURY3.POD", POD_MD5)]:
        if key not in entries: sys.exit(f"no {key} on this CD: it isn't the Fury3 disc the kit was made for")
        got = md5(dt.read_file(*entries[key][2:]))
        if got != want:
            sys.exit(f"this CD's {key} is not the v1.1.0.1 one the kit was made for (MD5 {got}); nothing else is supported yet")

    pkg = os.path.join(os.path.abspath(a.out), "Fury3"); game = os.path.join(pkg, "game")
    if os.path.exists(pkg): sys.exit(f"{pkg} already exists: move or delete it first")

    print("1/3 game files from the CD")   # what Setup's Typical install copies, plus the movies
    def copy(key, dst): dt.copy_file(*entries[key][2:], os.path.join(game, *dst.split("/")))
    for key, dst in [("FURY3/FURY3.HLP", "FURY3.HLP"), ("FURY3/FURY3.CNT", "FURY3.CNT"), ("README.TXT", "README.TXT"),
                     ("FURY3/FURY3.EXE", "_spare/FURY3.EXE"), ("FURY3/SYSTEM/FURY3.INI", "_spare/FURY3.INI")]:
        copy(key, dst)
    movies = 0
    for key, (p, is_dir, l, s) in entries.items():
        if is_dir or not key.startswith("FURY3/SYSTEM/") or key == "FURY3/SYSTEM/FURY3.INI": continue
        copy(key, p[len("FURY3/"):]); movies += key.startswith("FURY3/SYSTEM/STORY/")
    if movies != 19: sys.exit(f"expected 19 movies in FURY3\\SYSTEM\\STORY, found {movies}")
    shutil.copyfile(os.path.join(HERE, "config", "SYSTEM", "FURY3.INI"), os.path.join(game, "SYSTEM", "FURY3.INI"))

    print("2/3 exe patches")
    out = patch_exe.patch(dt.read_file(*entries["FURY3/FURY3.EXE"][2:]))
    if md5(out) != PATCHED_MD5: sys.exit("patching gave an unexpected FURY3.EXE")
    open(os.path.join(game, "FURY3.EXE"), "wb").write(out)

    print("3/3 Steam Deck launch script" if not a.windows else "3/3 done")
    if not a.windows:
        launch = os.path.join(pkg, "fury3_launch.sh")
        shutil.copyfile(os.path.join(HERE, "steamdeck", "fury3_launch.sh"), launch); os.chmod(launch, 0o755)
    print(f"\ndone: {pkg}  (see README.md)")


if __name__ == "__main__":
    main()
