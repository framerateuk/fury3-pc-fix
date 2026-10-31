# How it works

Notes on Fury3 (Terminal Reality / Microsoft, 1995), the US / English CD (volume `MSFURY3`, 18 August
1995), `FURY3\FURY3.EXE` version 1.1.0.1 (645,120 bytes, linked 14 August 1995, MD5
`9907b1b8f1550827ab0c47ddf1723038`). Addresses are virtual addresses in that exe.

## The disc and Setup

Track 1 is the data track; tracks 2-6 are five pieces of music for a CD player, which the game never
plays (its only MCI device is `avivideo`; its music is 18 MOD files inside `FURY3.POD`). No copy
protection and no CD check: the game opens its data through paths in `SYSTEM\FURY3.INI` and only
says "The Fury3 CD is not correctly inserted" when a POD file is missing.

`SETUP.EXE` is a 16-bit stub for Microsoft ACME Setup. A Typical install copied `FURY3.EXE`,
`FURY3.HLP` / `.CNT` and `README.TXT` into the install folder, and `SYSTEM\FURY3.INI`, `FURY3.INF`,
`STARTUP.POD`, `FURY3PID.DLL` (the About box's product ID) and `FURY3.POD` into `SYSTEM\`;
optionally the movies into `SYSTEM\STORY\`. It also wrote three path entries into the INI (relative
paths work, since the exe makes its own folder the current one), an uninstall entry, a `.fff` file
type and shortcuts. The game reads no registry. `build.py` copies the same files, with the movies.
Left out: Setup, the Windows 3.1 help, the Multimedia Catalog (`MMCAT\`), `DRIVERS\` (1995 joystick
and ATI programs) and the disc root's `SYSTEM\` (WinG, Video for Windows, Win32s, DISPDIB: Windows
3.1 runtime).

## How the game works

- **One exe for Windows 3.1 (Win32s), Windows 95 and NT 3.51**, chosen by `GetVersion` (0x40b5a6).
  Modern Windows and Wine are NT. No 16-bit code runs.
- **Graphics: GDI.** A 320x200 8-bit picture in a DIB section (`CreateDIBSection`, 0x40a582), copied
  to the window in WM_PAINT (0x409fc0) with `BitBlt` or `StretchBlt`. The window had a frame and a
  menu bar. Full Screen (F4) was Windows 95 only: Win16 `DISPDIB.DLL` plus `rep movsd` straight to
  the VGA memory at 0xA0000. There's no DirectDraw anywhere, so dgVoodoo and cnc-ddraw don't apply.
- **Timing:** the clock is `timeGetTime` (0x446e10); every loop moves things by the time since its
  last frame and draws again at once: no frame limit, no sleep. Waits for a key spin on the message
  pump, and the pump spins while the game is minimised.
- **Input:** the keyboard as a scan-code table (0x40af42); the joystick through winmm `joyGetPosEx`
  (0x414c70): X / Y, throttle, 4 buttons, the hat. On NT the set-up (0x414aa0) switched it off
  ("Joysticks are not supported under NT").
- **Sound:** its own mixer thread on `waveOut`, 11 kHz. **Movies:** MCI `avivideo`, Cinepak 320x240
  in a child window. Cinepak still decodes on Windows 10/11 and in Wine.
- **Memory check:** `GlobalMemoryStatus` (0x40b6be), `dwTotalPhys` compared *signed* with 9 MB for
  the texture cache size and a detail level.

## The patches

`patch_exe.py` adds a section `.rdeck` (VA 0x57c000, 8 KB, at the end of the file) holding the new
code from `caves.s`, and redirects these sites into it. Its header lists each site's old and new
bytes.

| Patch | Was | Now |
|---|---|---|
| `ram` | `dwTotalPhys` read signed; Proton's large-address-aware flag reports up to 4 GB, which reads as negative: the low-memory texture cache, silently | Every `GlobalMemoryStatus` figure clamped to 2 GB - 1 |
| `window` | 328x246 framed window with a menu bar, arrow pointer, maximised by the intro | A `WS_POPUP` window covering the screen, no menu bar, no pointer |
| `fullscreen` | F4: on NT, back to a 320x200 window | Nothing |
| `blit` | The picture stretched to the whole window | 4:3 at full height, centred, black bars painted each frame (`SquarePixels=1`: whole multiples of 320x200) |
| `wndproc` | (window procedure) | No pointer; Enter in flight = P (pause); Esc on the title = quit; F11 = Save Game (`data\QUICK.FFF` when the game has no file yet, so no Save As box); F12 = Resume Saved Game |
| `framecap` | Every loop drew as fast as the CPU allowed | At most 60 frames a second, sleeping 1 ms at a time; the pad read here each frame |
| `kbhit`, `keywait`, `moviewait`, `pumpidle` | Spin loops | Short sleeps; in the waits the pad's A / B answer Y / N and A, B, X, Y or Start skip a movie |
| `title`, `flighttime` | | Note where the game is, for Enter (new game on the title, pause in flight) and Esc |
| `movie` | Movie window 1:1 or doubled, centred | 4:3 at full height, centred, and MCI `put destination` so the video fills it |
| `joyinit`, `joyread` | Joystick off on NT | Analogue joystick mode with fixed calibration, fed from XInput every frame by `padupdate`; reads the `[Retrodeck]` switches |

`padupdate` (in `caves.s`) reads the first XInput pad (`xinput1_4`, then `1_3`, then `9_1_0`). The
left stick becomes the joystick (21% dead zone), triggers and buttons become joystick buttons or
keys put straight into the game's key table, and Start / Back are posted to the window as Enter /
Esc.

The game's INI section for the two switches is called `[Retrodeck]` because the name is a string
inside the patched exe.

## Picture

The 320x200 picture is scaled with `COLORONCOLOR` (nearest pixel, the game's own mode) to 4:3 at the
screen's height: 1066x800 on the Steam Deck, 107-pixel bars each side. 4:3 is how Fury3 looked full
screen on a 1995 monitor, and its art is drawn for it (round planets, round HUD dials).

No widescreen: the engine has one 320x200 frame buffer, with 320 and 200 built into the HUD, the
cockpit art and the 3D view set-up. Its "Panoramic format" (`[` / `]`) only letterboxes the 3D view
inside the frame.

## Frame rate

The game times everything by the clock, so the frame rate isn't its speed: 60 is the cap to stop
the CPU running flat out and frame times shrinking below the clock's 1 ms step. Its 1995 machines
drew 15-30 frames a second.
