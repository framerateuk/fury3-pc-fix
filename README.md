# Fury3 (PC, 1995) on modern PCs and the Steam Deck

## Why this exists

I was a big fan of Terminal Velocity, and Fury3 is basically more of that, and pretty much
forgotten about. The Windows 95 version doesn't run properly on anything newer: no full screen, no
joystick, and a 16-bit installer. This kit sorts that out,
so it can be played again.

## What this does

Turns **your own** Fury3 CD into a folder that runs on the Steam Deck (Proton) or on Windows 10/11,
with no installer, no registry entries and no extra downloads:

- **Copied straight from the CD**: what the 1995 Setup installed, without running Setup (a 16-bit
  Microsoft installer modern Windows can't start).
- **Full screen**: the game's own full screen worked only on Windows 95 (it wrote straight to the
  VGA card). Now it fills the screen, 4:3 with black bars, as on a 1995 monitor. No window frame, no
  menu bar, no mouse pointer.
- **Gamepad**: the game switched its joystick off on Windows NT, which modern Windows and Proton
  are. The exe now reads an Xbox-style pad (the Steam Deck's included) directly, as an analogue
  flight stick with throttle, weapons, views and the hat.
- **At most 60 frames a second, no busy waits**: it no longer runs one CPU core flat out.
- **Smaller fixes**: a memory check that misread modern amounts of RAM (and silently picked the
  low-detail texture cache), the movies at full height, quick save / resume keys, Enter pauses.

Fury3 had no CD check and no CD music (the disc's audio tracks are a bonus soundtrack the game never
plays), so there's nothing to rip and no wrappers to download.

**No game files are in this repository.** Everything from the game comes from your disc when you
run `build.py`.

## What you need

| | |
|---|---|
| The game | The **Fury3 CD** (Microsoft / Terminal Reality, 1995, the US / English release, volume label `MSFURY3`, `FURY3\FURY3.EXE` version 1.1.0.1) as `.cue` + `.bin` or CloneCD `.ccd` + `.img`. `build.py` checks the exe and the game data and stops on another version. |
| Python | 3.8 or newer (python.org on Windows; already on macOS/Linux). |

## Build

```
python3 build.py Fury3.ccd
```

creates `Fury3/` with `game/` and `fury3_launch.sh` (for the Steam Deck) in a few seconds. The same
`game/` folder runs on Windows; `--windows` leaves out the launch script. `--out DIR` puts the result
somewhere else. The disc's original exe and settings file are kept in `game/_spare/`.

## Play on the Steam Deck

1. Copy `Fury3/` to the Deck, for example to `/home/deck/Games/Fury3/`.
2. Desktop Mode: Steam > Add a Non-Steam Game > Browse > `.../Fury3/game/FURY3.EXE`.
   Rename the shortcut "Fury3".
3. Properties > Compatibility: force **Proton 9.0**. Pin it rather than floating on Experimental.
4. Properties > Launch Options:
   ```
   /home/deck/Games/Fury3/fury3_launch.sh %command%
   ```
5. Controller layout: the standard **Gamepad** layout works, since the game reads the pad itself
   (Start and View send Enter and Esc). Two extras are worth adding in Steam's controller settings:
   **L4 = F11** (save) and **R4 = F12** (resume a saved game), and the **right trackpad as a mouse**
   for the few Windows dialog boxes (choosing a saved game). The "Gamepad with Mouse Trackpad"
   template has the trackpad already.

## Play on Windows

Run `game/FURY3.EXE`. An Xbox-style pad works as on the Deck; save and resume are F11 / F12 on
the keyboard.

## Controls

| Pad | Does | Keyboard |
|---|---|---|
| Left stick | fly (analogue; pushed up = nose down, like a 1995 flight stick) | arrows |
| RT or A | fire | Space |
| LT | Turbo Thrust (when you carry turbo fuel) | F |
| Right stick up / down | throttle up / down | A / Z |
| Right stick left / right | roll | Home / Page Up |
| RB / LB | next / previous weapon | 1-7 |
| D-pad | look out of the cockpit / pan the outside view | Ins, Del, keypad |
| Y | next pilot view (cockpit, chase, outside) | V |
| X | next instrument display | C |
| B | mission status | Backspace |
| R3 / L3 | satellite map / crosshairs on and off | Tab / X |
| Start | title: new game; boxes: OK; briefings: next page; movies: skip; in flight: pause | Enter |
| View / Back | in flight: "End Game? (Y/N)" (A yes, B no); on the title: quit | Esc |
| L4 / R4 (Deck, see above) | save / resume a saved game | F11 / F12 |

The game's own keys still work too: P or F3 pause, F2 new game, Ctrl+S / Ctrl+R save / resume,
Ctrl+M mute, F1 help (needs WinHelp, which Windows 10/11 no longer have). New Game asks for a call
sign and a difficulty in a small box; Start takes the defaults.

## Settings

The game's Options boxes were on the menu bar, which is gone with the full-screen window, so
settings live in `game/SYSTEM/FURY3.INI` (the game writes it back when it quits). The kit's copy
differs from the disc's: the pad on (`joystickActive=2`), stereo sound, debris "Overkill", no Quick
Help or "256 colours" box at start, and a `[Retrodeck]` section with two switches the patched exe
reads:

- `PadInvertY=1`: pushing the stick up climbs instead.
- `SquarePixels=1`: the picture at whole multiples of 320x200 (on the Deck exactly 4x, 1280x800,
  filling the screen but 20% wider) instead of 4:3 with bars.

Saved games and high scores go in `game/data/`.

## Troubleshooting

- *A small window with a menu bar*: you're running the unpatched exe from `_spare/`.
- *The pad does nothing*: on Windows, the pad must be an XInput (Xbox-style) one; on the Deck, the
  shortcut's controller layout must pass the gamepad through (the Gamepad templates do).
- *Judder on a G-Sync / FreeSync monitor*: turn variable refresh off for this game.

## What's in this repository

| File | What |
|---|---|
| `build.py` | Builds the folder: copies the CD's game files, patches the exe, adds the settings. Python standard library only. |
| `patch_exe.py` | The exe patches, each explained; adds a code section to the exe. Also runs on its own. |
| `caves.s` | The new code's source (x86 assembly). `python3 patch_exe.py --check-caves` re-assembles it with clang and checks it against the bytes in `patch_exe.py`. |
| `disc.py` | Reads the CD image: `.cue`/`.bin` or `.ccd`/`.img`, ISO 9660. |
| `config/SYSTEM/FURY3.INI` | The game's settings, set up for the pad. |
| `steamdeck/fury3_launch.sh` | Proton launch wrapper: logging only. |
| `docs/TECHNICAL.md` | How the game works and what each patch does. |

## Credits

- **Terminal Reality** made Fury3 on its Terminal Velocity engine; **Microsoft** published it.
  Please own the game: this kit needs your disc.

## License

The scripts and docs in this repository: MIT (see `LICENSE`). The license covers only this
repository's own files, not the game.

Not affiliated with or endorsed by the game's rights holders.
