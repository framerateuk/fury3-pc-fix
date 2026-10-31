# Fury3 (Terminal Reality / Microsoft, 1995; FURY3\FURY3.EXE v1.1.0.1 of the US retail disc, 645,120 bytes, linked 14 Aug
# 1995): new code for patch_exe.py. It goes into a section patch_exe.py adds to the exe, ".rdeck" at VA 0x57c000 (file
# offset 0x9d800, the end of the file, 0x2000 bytes, readable / writable / executable): this code from 0x57c000, its
# variables from 0x57d000 (zero when the exe loads). The exe always loads at its 0x400000 base (no dynamic-base flag;
# the patch also marks it "relocations stripped"), so absolute addresses are used throughout.
#
# Assembled with Apple clang (integrated assembler):
#   clang -target i386-pc-linux-gnu -c caves.s -o caves.o
# patch_exe.py carries the resulting bytes (CAVE) and checks them against this file when clang is around
# (patch_exe.py --check-caves). docs/TECHNICAL.md explains each routine.
#
# Rule kept from Speedster (23 Oct 2026): never keep a value in ecx / edx across an API call (Proton's timeGetTime
# and friends change them). Values live in ebx / esi / edi or memory across calls; ebp is never touched.
.intel_syntax noprefix
.set BASE, 0x57c000

# imports used (IAT slots of FURY3.EXE v1.1.0.1)
.set Sleep,                 0x545460
.set timeGetTime,           0x54558c
.set LoadLibraryA,          0x5453b0
.set GetProcAddress,        0x5453b4
.set GetPrivateProfileIntA, 0x545394
.set lstrcpyA,              0x545374
.set GetSystemMetrics,      0x54552c
.set SetCursor,             0x54548c
.set PostMessageA,          0x5454f8
.set CreateWindowExA,       0x54553c
.set GetClientRect,         0x5454a4
.set MoveWindow,            0x5454b8
.set PatBlt,                0x545348
.set StretchBlt,            0x545324
.set SetStretchBltMode,     0x545328
.set mciSendStringA,        0x545568

# game
.set HWND,      0x5329cc             # the main window
.set MEMDC,     0x53c0fc             # the memory DC holding the 8-bit DIB section the game draws into
.set CLIENTW,   0x5329d0             # the client size, as the WM_PAINT blit (0x409fc0) just measured it
.set CLIENTH,   0x532ae0
.set FRAMEW,    0x53e7d4             # the picture: 320 x 200
.set FRAMEH,    0x53e7d8
.set KEYS,      0x4eb940             # the keyboard: one byte per scan code, 1 = down (WM_KEYDOWN / WM_KEYUP 0x40af42)
.set KEYVK,     0x541f14             # the last WM_KEYDOWN's virtual key, 0 once read (kbhit 0x446e90, waitkey 0x446e60)
.set INGAME,    0x53e860             # 1 while the flight loop (0x424f.., 0x425084) runs
.set DEMO,      0x53e7c4             # 1 while the title's demo plays
.set TITLEREQ,  0x542464             # the title loop's request: 1 New Game, 2 Resume (0x44fead)
.set INIPATH,   0x53d4b0             # -> ".\system\fury3.ini"
.set JOYMODE,   0x53e728             # joystickActive: 0 keyboard, 1 gamepad (digital), 2 joystick, 3 with throttle
.set JOYX,      0x4eb620             # joyGetPosEx's X / Y / Z and buttons, as the joystick read (0x414c70) left them
.set JOYY,      0x4eb624
.set JOYZ,      0x4eb618
.set JOYBTN,    0x4ebcb0
.set HATUP,     0x514784             # the hat (dwPOV 0 / 9000 / 18000 / 27000): 1 = pushed that way
.set HATRIGHT,  0x51478c
.set HATDOWN,   0x514790
.set HATLEFT,   0x514788
.set WEAPON,    0x514760             # the weapon in use: 1 2 3 0x12 0x13 0x14 0x15 (keys 1-7), 0x16 turbo
.set WAVAIL,    0x50dfa0             # + 8 * weapon: nonzero = carried (0x419980)
.set MOVOPEN,   0x543048             # 1 while an MCI movie ("mov") is open
.set MOVPLAY,   0x543044             # 1 while it plays (cleared by MM_MCINOTIFY)
.set MOVHWND,   0x45fc7c             # its window (a child of the main window)
.set SAVENAME,  0x45ff60             # the current saved-game file ("" until saved / resumed)
.set ASPECT,    0x53e7a8             # aspectRatio: 1 = the windowed path's 320x200-as-4:3 maths, 0 = DISPDIB's
.set PUMP,      0x401b6d             # the message pump (0x409be0)
.set GAMETIME,  0x40127b             # the game clock (0x446e10, timeGetTime * 1179.648)
.set SPRINTF,   0x450ae7

# our variables (.rdeck from 0x57d000, zero at load)
.set XGS,     0x57d000               # XInputGetState (0 = no XInput DLL)
.set XINIT,   0x57d004               # 1 once readpad has looked for XInput
.set PB,      0x57d008               # the pad as readpad last read it: XInput wButtons
.set PLX,     0x57d00c               #   left stick X / Y (signed, up +)
.set PLY,     0x57d010
.set PRX,     0x57d014               #   right stick X / Y
.set PRY,     0x57d018
.set PLT,     0x57d01c               #   left / right trigger 0..255
.set PRT,     0x57d020
.set PPREV,   0x57d024               # wButtons at the previous padupdate
.set NEWP,    0x57d028               # buttons newly down at the last padupdate
.set RELP,    0x57d02c               # buttons released at the last padupdate
.set HELD,    0x57d030               # roll keys padupdate holds down: 1 Home, 2 PgUp
.set WKEY,    0x57d034               # the weapon key (scan code 2..8) padupdate holds down, 0 = none
.set FINIT,   0x57d038               # framecap: 1 once started
.set FDUE3,   0x57d03c               #   the next frame's time in thirds of a millisecond
.set FLIGHTT, 0x57d040               # timeGetTime at the flight loop's last frame (flighttime)
.set TITLET,  0x57d044               # timeGetTime at the title loop's last pass (titlekb)
.set INVY,    0x57d048               # FURY3.INI [Retrodeck] PadInvertY
.set SQPIX,   0x57d04c               # FURY3.INI [Retrodeck] SquarePixels
.set HDC,     0x57d050               # blit: the paint DC
.set PICX,    0x57d054               #   the picture's place in the client area
.set PICY,    0x57d058
.set PICW,    0x57d05c
.set PICH,    0x57d060
.set XS,      0x57d080               # an XINPUT_STATE (16 bytes)
.set MCIBUF,  0x57d100               # movieplace: an MCI command string (64 bytes)

.set DZ,      7000                   # left stick dead zone (of 32768): 21 %
.set RDZ,     16000                  # right stick: a direction counts from half way out
.set TDZ,     40                     # a trigger counts from 16 % of the way in

.macro PUSHI v                       # push imm32
  .byte 0x68
  .long \v
.endm
.macro JMPA t                        # jmp to an absolute address in the exe
  .byte 0xe9
  .long \t - (BASE + (. + 4 - start))
.endm
.macro CALLA t                       # call an absolute address in the exe
  .byte 0xe8
  .long \t - (BASE + (. + 4 - start))
.endm
.macro ADDR sym                      # the absolute address of a label of ours
  .long BASE + (\sym - start)
.endm

.text
start:

# ---------------------------------------------------------------------------------------------------------------
# createwin (patch window): WinMain's CreateWindowExA of the main window (0x40b696: WS_OVERLAPPEDWINDOW, 328 x 246 at
# CW_USEDEFAULT, the menu bar Game / View / Options / Help) comes here instead: WS_POPUP | WS_CLIPCHILDREN at 0, 0 the
# size of the screen (a full-screen window under Wine; the movie window is a child, which the blit must not paint
# over), no menu bar. Same arguments otherwise; a tail jump, so CreateWindowExA returns to WinMain.
createwin:
  push 1                             # SM_CYSCREEN
  call dword ptr [GetSystemMetrics]
  mov dword ptr [esp + 0x20], eax    # nHeight
  push 0                             # SM_CXSCREEN
  call dword ptr [GetSystemMetrics]
  mov dword ptr [esp + 0x1c], eax    # nWidth
  mov dword ptr [esp + 0x14], 0      # x
  mov dword ptr [esp + 0x18], 0      # y
  mov dword ptr [esp + 0x10], 0x82000000   # WS_POPUP | WS_CLIPCHILDREN
  mov dword ptr [esp + 0x28], 0      # hMenu
  jmp dword ptr [CreateWindowExA]

# ---------------------------------------------------------------------------------------------------------------
# memclamp (patch ram): WinMain read GlobalMemoryStatus into [ebp - 0x3c] and kept dwTotalPhys (0x53e8ac); three
# places compare it signed with 9 MB (0x42d210 texture cache 320 / 512 KB, 0x42d2db, 0x433eea). Proton marks every exe
# large-address-aware, so Wine reports up to 4 GB here: read as negative, the game takes its low-memory path. Every
# figure of the MEMORYSTATUS is clamped to 2 GB - 1 (what Windows gives an exe without the flag), then the two
# instructions the call replaced.
memclamp:
  push ecx
  push edx
  lea ecx, [ebp - 0x34]              # dwTotalPhys .. dwAvailVirtual: 6 dwords
  mov edx, 6
1:
  cmp dword ptr [ecx], 0x7fffffff
  jbe 2f
  mov dword ptr [ecx], 0x7fffffff
2:
  add ecx, 4
  dec edx
  jnz 1b
  pop edx
  pop ecx
  mov eax, dword ptr [ebp - 0x34]
  mov dword ptr [0x53e8ac], eax
  ret

# ---------------------------------------------------------------------------------------------------------------
# wndfilter (patch wndproc): the window procedure (0x40ab30) starts here; [esp + 4] hwnd, [esp + 8] message,
# [esp + 0xc] wParam, [esp + 0x10] lParam.
#   WM_SETCURSOR over the client area: no pointer (SetCursor(NULL); the class has none either, patch cursor).
#   Enter (WM_KEYDOWN / WM_KEYUP) while the flight loop runs and it is no demo: the P key instead (pause / resume;
#     Enter did nothing in flight), so Start (Steam Input: Enter) pauses. Elsewhere Enter stays Enter.
#   Esc (WM_KEYDOWN) on the title screen: quit (WM_CLOSE; Esc did nothing there). In a game Esc stays "End Game?".
#   F11: Game > Save Game (WM_COMMAND 0x8012), with "data\QUICK.FFF" as the file when the game has none yet (no Save
#     As box); F12: Game > Resume Saved Game (0x8011, its file box). Steam Input puts them on L4 / R4. The menu bar is
#     gone (patch window), Ctrl+S / Ctrl+R still work.
wndfilter:
  mov eax, dword ptr [esp + 8]
  cmp eax, 0x20                      # WM_SETCURSOR
  jne 1f
  cmp word ptr [esp + 0x10], 1       # HTCLIENT
  jne 9f
  push 0
  call dword ptr [SetCursor]
  mov eax, 1
  ret 0x10
1:
  cmp eax, 0x100                     # WM_KEYDOWN
  je 2f
  cmp eax, 0x101                     # WM_KEYUP
  jne 9f
2:
  cmp dword ptr [esp + 0xc], 0x0d    # VK_RETURN
  jne 3f
  cmp dword ptr [esp + 8], 0x101     # Enter up: both keys up in the key table, whichever the down became
  jne 21f
  mov byte ptr [KEYS + 0x1c], 0
  mov byte ptr [KEYS + 0x19], 0
21:
  call inflight
  test eax, eax
  jz 9f
  mov dword ptr [esp + 0xc], 0x50    # 'P'
  mov eax, dword ptr [esp + 0x10]
  and eax, 0xff00ffff
  or eax, 0x00190000                 # scan code 0x19 (P)
  mov dword ptr [esp + 0x10], eax
  jmp 9f
3:
  cmp dword ptr [esp + 8], 0x100     # the rest: key down only
  jne 9f
  cmp dword ptr [esp + 0xc], 0x1b    # VK_ESCAPE
  jne 4f
  call intitle
  test eax, eax
  jz 9f
  mov eax, dword ptr [esp + 4]
  push 0
  push 0
  push 0x10                          # WM_CLOSE (no "Exit Fury3?" box outside a game)
  push eax
  call dword ptr [PostMessageA]
  xor eax, eax
  ret 0x10
4:
  cmp dword ptr [esp + 0xc], 0x7a    # VK_F11: save
  jne 5f
  cmp byte ptr [SAVENAME], 0
  jne 41f
  PUSHI BASE + (s_quick - start)
  PUSHI SAVENAME
  call dword ptr [lstrcpyA]
41:
  mov eax, 0x8012                    # Save Game
  jmp 6f
5:
  cmp dword ptr [esp + 0xc], 0x7b    # VK_F12: resume
  jne 9f
  mov eax, 0x8011                    # Resume Saved Game
6:
  mov ecx, dword ptr [esp + 4]
  push 0
  push eax
  push 0x111                         # WM_COMMAND
  push ecx
  call dword ptr [PostMessageA]
  xor eax, eax
  ret 0x10
9:
  sub esp, 0x40                      # the instructions the jump replaced
  push ebx
  push esi
  JMPA 0x40ab35

# inflight: eax = 1 when the flight loop ran a frame in the last 100 ms (flighttime) and it is no demo
inflight:
  cmp dword ptr [INGAME], 1
  jne 8f
  cmp dword ptr [DEMO], 0
  jne 8f
  call dword ptr [timeGetTime]
  sub eax, dword ptr [FLIGHTT]
  cmp eax, 100
  jae 8f
  mov eax, 1
  ret
8:
  xor eax, eax
  ret

# intitle: eax = 1 when the title loop passed in the last 200 ms (titlekb): the title screen, not its demo
intitle:
  call dword ptr [timeGetTime]
  sub eax, dword ptr [TITLET]
  cmp eax, 200
  jae 8f
  mov eax, 1
  ret
8:
  xor eax, eax
  ret

# flighttime (patch flighttime): the flight loop's clock read at the end of each frame (0x425329) notes the time first
flighttime:
  call dword ptr [timeGetTime]
  mov dword ptr [FLIGHTT], eax
  JMPA GAMETIME

# titlekb (patch title): the title loop's "key pressed?" (0x44fe5a) notes the time (intitle) and makes Enter (Start)
# Game > New Game, as F2 is, when nothing else is asked for.
titlekb:
  call dword ptr [timeGetTime]
  mov dword ptr [TITLET], eax
  call kbhitc
  test eax, eax
  jz 1f
  cmp dword ptr [KEYVK], 0x0d        # VK_RETURN
  jne 1f
  cmp dword ptr [TITLEREQ], 0
  jne 1f
  mov dword ptr [TITLEREQ], 1        # New Game (the title loop's 0x44fead)
1:
  ret

# ---------------------------------------------------------------------------------------------------------------
# blit (patch blit): the windowed WM_PAINT blit (0x40a0ba) BitBlt the 320x200 picture at 320x200 or StretchBlt it to
# the whole client area (16:10 on the Deck, any shape on Windows). Now: 4:3 (320x200 as on a 1995 monitor, the
# windowed path's own maths, ASPECT 1), as tall as the client area and centred (1066x800 on the Deck), or as wide when
# the client area is narrower than 4:3; with FURY3.INI [Retrodeck] SquarePixels=1 the largest whole multiple of
# 320x200 instead (1280x800 on the Deck: 16:10, the window's 1:1 pixels). The rest painted black each frame (the game
# erases nothing, WM_ERASEBKGND). Nearest-pixel scaling (COLORONCOLOR, the game's own). Then 0x40a17c (return 1).
blit:
  mov eax, dword ptr [esp + 0x30]    # the paint DC (0x409fc0's second argument)
  mov dword ptr [HDC], eax
  mov esi, dword ptr [CLIENTW]
  mov edi, dword ptr [CLIENTH]
  cmp dword ptr [SQPIX], 0
  jne 20f
  lea eax, [edi * 4]                 # w = h * 4 / 3
  xor edx, edx
  mov ecx, 3
  div ecx
  mov ebx, edi                       # h
  cmp eax, esi
  jbe 30f
  lea ebx, [esi + esi * 2]           # too wide: w = client width, h = w * 3 / 4
  shr ebx, 2
  mov eax, esi
  jmp 30f
20:
  mov eax, esi                       # square pixels: k = min(w / 320, h / 200), at least 1
  xor edx, edx
  mov ecx, 320
  div ecx
  mov ebx, eax
  mov eax, edi
  xor edx, edx
  mov ecx, 200
  div ecx
  cmp eax, ebx
  jbe 21f
  mov eax, ebx
21:
  test eax, eax
  jnz 22f
  mov eax, 1
22:
  imul ebx, eax, 200
  imul eax, eax, 320
30:
  mov dword ptr [PICW], eax
  mov dword ptr [PICH], ebx
  mov ecx, esi
  sub ecx, eax
  sar ecx, 1
  mov dword ptr [PICX], ecx
  mov ecx, edi
  sub ecx, ebx
  sar ecx, 1
  mov dword ptr [PICY], ecx
  # black bars (BLACKNESS): left, right (full height), top, bottom (picture width)
  mov eax, dword ptr [PICX]
  test eax, eax
  jle 31f
  push 0x42
  push edi
  push eax
  push 0
  push 0
  push dword ptr [HDC]
  call dword ptr [PatBlt]
  mov eax, dword ptr [PICX]
  add eax, dword ptr [PICW]
  mov ecx, esi
  sub ecx, eax
  push 0x42
  push edi
  push ecx
  push 0
  push eax
  push dword ptr [HDC]
  call dword ptr [PatBlt]
31:
  mov eax, dword ptr [PICY]
  test eax, eax
  jle 32f
  push 0x42
  push eax
  push esi
  push 0
  push 0
  push dword ptr [HDC]
  call dword ptr [PatBlt]
  mov eax, dword ptr [PICY]
  add eax, dword ptr [PICH]
  mov ecx, edi
  sub ecx, eax
  push 0x42
  push ecx
  push esi
  push eax
  push 0
  push dword ptr [HDC]
  call dword ptr [PatBlt]
32:
  push 3                             # COLORONCOLOR
  push dword ptr [HDC]
  call dword ptr [SetStretchBltMode]
  PUSHI 0xcc0020                     # SRCCOPY
  push dword ptr [FRAMEH]
  push dword ptr [FRAMEW]
  push 0
  push 0
  push dword ptr [MEMDC]
  push dword ptr [PICH]
  push dword ptr [PICW]
  push dword ptr [PICY]
  push dword ptr [PICX]
  push dword ptr [HDC]
  call dword ptr [StretchBlt]
  JMPA 0x40a17c

# ---------------------------------------------------------------------------------------------------------------
# framecap (patch framecap): every loop of the game (logos, title, flight, tunnels, briefings) shows a frame through
# 0x40bcc0 (InvalidateRect + the message pump, which paints) and none waited: the game times its movement by the
# clock, so it drew as many frames as the CPU allowed, one core at 100 % (and on a fast CPU frames less than a
# millisecond apart, the clock's step). Now at most 60 frames a second: frame n is shown at t0 + n * 50/3 ms (kept in
# thirds of a millisecond, timeGetTime * 3, wrap-safe), sleeping 1 ms at a time until then (the game's own
# timeBeginPeriod(1), 0x41b0d0); more than 50 ms behind (a load), start again from now. The pad is read first
# (padupdate). Then the two instructions the jump replaced and on into 0x40bcc6.
framecap:
  pushad
  call padupdate
1:
  call dword ptr [timeGetTime]
  lea eax, [eax + eax * 2]
  cmp dword ptr [FINIT], 0
  jne 2f
  mov dword ptr [FINIT], 1
  mov dword ptr [FDUE3], eax
  jmp 5f
2:
  mov ecx, eax
  sub ecx, dword ptr [FDUE3]         # thirds of a ms since the frame was due (signed)
  jns 3f
  push 1
  call dword ptr [Sleep]
  jmp 1b
3:
  cmp ecx, 150
  jl 5f
  mov dword ptr [FDUE3], eax         # far behind: from now
5:
  add dword ptr [FDUE3], 50
  popad
  push esi
  mov eax, dword ptr [0x532464]
  JMPA 0x40bcc6

# ---------------------------------------------------------------------------------------------------------------
# kbhitc (patch kbhit): "is a key waiting?" (0x446e90) is what the logo, briefing and title loops spin on; with no key
# it now sleeps 1 ms first. eax = 1 / 0 as before; ecx / edx kept (the original changed only eax).
kbhitc:
  cmp dword ptr [KEYVK], 0
  jne 1f
  push ecx
  push edx
  push 1
  call dword ptr [Sleep]
  pop edx
  pop ecx
  xor eax, eax
  ret
1:
  mov eax, 1
  ret

# keywait (patch keywait): "wait for a key" (0x446e60: "End Game? (Y/N)", "Retry Mission (Y/N)", "Press any key")
# spun on the message pump; now the pump, then 5 ms asleep, then the pad: A = Y, B = N (Start = Enter comes from
# Steam Input, or from padupdate off Steam).
keywait:
  CALLA PUMP
  pushad
  push 5
  call dword ptr [Sleep]
  call padupdate
  cmp dword ptr [KEYVK], 0
  jne 9f
  test dword ptr [NEWP], 0x1000      # A
  jz 1f
  mov dword ptr [KEYVK], 0x59        # 'Y'
  jmp 9f
1:
  test dword ptr [NEWP], 0x2000      # B
  jz 9f
  mov dword ptr [KEYVK], 0x4e        # 'N'
9:
  popad
  ret

# moviewait (patch moviewait): the movie loop (0x45049f) spun on the message pump until the movie ended or Esc /
# Enter was down; now the pump, 5 ms asleep, and A, B, X, Y or Start on the pad end the movie (as its end would).
moviewait:
  CALLA PUMP
  pushad
  push 5
  call dword ptr [Sleep]
  call padupdate
  test dword ptr [NEWP], 0xf010      # A B X Y, Start
  jz 9f
  mov dword ptr [MOVPLAY], 0
9:
  popad
  ret

# pumpidle (patch pumpidle): the message pump (0x409be0) went straight back to PeekMessage while the game was
# minimised or not the active app (0x409cc6, 0x409cde): one core busy. Now 20 ms asleep first.
pumpidle:
  push 20
  call dword ptr [Sleep]
  JMPA 0x409bff

# ---------------------------------------------------------------------------------------------------------------
# movieplace (patch movie): the movie window's placement (0x450050, cdecl, the main window): the 320x240 movie at 1:1,
# or doubled when the client area was larger than 400x300, centred. Now 4:3 at the client area's full height (or
# width), centred (1066x800 on the Deck: the same box as the game's picture), and MCI told to fill the window
# ("put mov destination").
movieplace:
  cmp dword ptr [MOVOPEN], 0
  je 9f
  push ebx
  push esi
  push edi
  sub esp, 16                        # RECT
  mov eax, esp
  push eax
  push dword ptr [esp + 36]          # the main window
  call dword ptr [GetClientRect]
  mov esi, dword ptr [esp + 8]       # client width
  mov edi, dword ptr [esp + 12]      # client height
  lea eax, [edi * 4]
  xor edx, edx
  mov ecx, 3
  div ecx                            # w = h * 4 / 3
  mov ebx, edi
  cmp eax, esi
  jbe 1f
  lea ebx, [esi + esi * 2]
  shr ebx, 2
  mov eax, esi
1:
  mov dword ptr [esp], eax           # w
  mov dword ptr [esp + 4], ebx       # h
  sub esi, eax
  sar esi, 1                         # x
  sub edi, ebx
  sar edi, 1                         # y
  push 1
  push ebx
  push eax
  push edi
  push esi
  push dword ptr [MOVHWND]
  call dword ptr [MoveWindow]
  push dword ptr [esp + 4]           # h
  push dword ptr [esp + 4]           # w (esp moved by one push)
  PUSHI BASE + (s_put - start)
  PUSHI MCIBUF
  CALLA SPRINTF
  add esp, 16
  push 0
  push 0
  push 0
  PUSHI MCIBUF
  call dword ptr [mciSendStringA]
  add esp, 16
  pop edi
  pop esi
  pop ebx
9:
  ret

# ---------------------------------------------------------------------------------------------------------------
# joyinit (patch joyinit): the joystick set-up (0x414aa0, after FURY3.INI is read) switched the joystick off on
# Windows NT ("Joysticks are not supported under NT", README.TXT), which Wine is. Now always "Joystick" (2: analogue
# stick, throttle on buttons), fed by the pad (padupdate), with the calibration and button numbers padupdate writes
# for: X / Y 0..65535 centred at 32767, fire = 1, Turbo Thrust = 2, throttle up = 8, down = 4. aspectRatio 1 (the
# windowed path's 4:3 maths; only DISPDIB full screen set 0). FURY3.INI [Retrodeck] PadInvertY / SquarePixels read.
joyinit:
  pushad
  mov dword ptr [JOYMODE], 2
  mov dword ptr [0x53cb4c], 0        # not the Win32s joystick path
  mov dword ptr [0x53cb50], 0        # no joyGetPosEx
  mov dword ptr [0x53cb48], 0
  mov dword ptr [0x4eb62c], 32767    # X centre / min / max
  mov dword ptr [0x4ebbb8], 0
  mov dword ptr [0x4ebba4], 65535
  mov dword ptr [0x4eb9d8], 32767    # Y centre / min / max
  mov dword ptr [0x4eb614], 0
  mov dword ptr [0x4eb610], 65535
  mov dword ptr [0x53e72c], 16383    # (gamepad mode's dead zone)
  mov dword ptr [0x53e820], 1        # buttonFire
  mov dword ptr [0x53e824], 2        # buttonWeapon (Turbo Thrust)
  mov dword ptr [0x53e828], 8        # buttonThrottleUp
  mov dword ptr [0x53e82c], 4        # buttonThrottleDown
  mov dword ptr [ASPECT], 1
  mov dword ptr [JOYX], 32767
  mov dword ptr [JOYY], 32767
  mov dword ptr [JOYZ], 32767
  push dword ptr [INIPATH]
  push 0
  PUSHI BASE + (s_invy - start)
  PUSHI BASE + (s_retrodeck - start)
  call dword ptr [GetPrivateProfileIntA]
  mov dword ptr [INVY], eax
  push dword ptr [INIPATH]
  push 0
  PUSHI BASE + (s_sqpix - start)
  PUSHI BASE + (s_retrodeck - start)
  call dword ptr [GetPrivateProfileIntA]
  mov dword ptr [SQPIX], eax
  popad
  ret

# joyread (patch joyread): the joystick read (0x414c70; 0x414e80 for the tunnels) returned at once on NT. padupdate
# keeps the joystick's figures current at every frame, so this only makes sure it has run once.
joyread:
  cmp dword ptr [XINIT], 0
  jne 1f
  pushad
  call padupdate
  popad
1:
  ret

# ---------------------------------------------------------------------------------------------------------------
# padupdate: the pad through XInput, as the game's joystick (mode 2) and keys. Called at every frame (framecap) and in
# the key / movie waits.
#   left stick       the joystick X / Y (analogue; 21 % dead zone, the rest scaled to the full range). Pushed up =
#                    the stick pushed forward = nose down, as on a 1995 joystick (PadInvertY=1: pulled back)
#   A, RT            button 1: fire                      LT        button 2: Turbo Thrust
#   right stick up   button 4: throttle up               down      button 3: throttle down
#   right stick L/R  Home / Page Up held: roll left / right
#   D-pad            the hat: look out of the cockpit windows / pan the outside view
#   Y                V: next pilot view (cockpit, chase, outside)
#   X                C: next instrument display
#   B                Backspace: mission status (weapon, objective)
#   RB / LB          the next / previous weapon carried (keys 1-7)
#   R3               Tab: satellite map           L3   X: crosshairs on / off
#   Start / Back     Enter / Esc posted to the window (on the Deck Steam Input types these two itself)
# Keys go into the game's key table (scan codes, 0x4eb940) when the button goes down and out when it comes up; the
# game clears the one-shot ones itself once used.
padupdate:
  pushad
  call readpad
  test eax, eax
  jz 50f
  mov esi, dword ptr [PB]
  # left stick -> joystick X / Y
  mov eax, dword ptr [PLX]
  call axis
  lea eax, [ecx + 32767]
  mov dword ptr [JOYX], eax
  mov eax, dword ptr [PLY]
  call axis
  cmp dword ptr [INVY], 0
  jne 1f
  neg ecx                            # up (+) = small Y = forward
1:
  lea eax, [ecx + 32767]
  mov dword ptr [JOYY], eax
  mov dword ptr [JOYZ], 32767
  # buttons
  xor ebx, ebx
  test esi, 0x1000                   # A
  jnz 2f
  cmp dword ptr [PRT], TDZ           # RT
  jb 3f
2:
  or ebx, 1
3:
  cmp dword ptr [PLT], TDZ           # LT
  jb 4f
  or ebx, 2
4:
  mov eax, dword ptr [PRY]
  cmp eax, RDZ
  jl 5f
  or ebx, 8                          # throttle up
5:
  cmp eax, -RDZ
  jg 6f
  or ebx, 4                          # throttle down
6:
  mov dword ptr [JOYBTN], ebx
  # hat from the D-pad (XInput 1 up, 2 down, 4 left, 8 right)
  mov eax, esi
  and eax, 1
  mov dword ptr [HATUP], eax
  mov eax, esi
  shr eax, 1
  and eax, 1
  mov dword ptr [HATDOWN], eax
  mov eax, esi
  shr eax, 2
  and eax, 1
  mov dword ptr [HATLEFT], eax
  mov eax, esi
  shr eax, 3
  and eax, 1
  mov dword ptr [HATRIGHT], eax
  # roll: right stick X holds Home (0x47) / Page Up (0x49)
  mov eax, dword ptr [PRX]
  cmp eax, -RDZ
  jg 7f
  mov byte ptr [KEYS + 0x47], 1
  or dword ptr [HELD], 1
  jmp 8f
7:
  test dword ptr [HELD], 1
  jz 8f
  mov byte ptr [KEYS + 0x47], 0
  and dword ptr [HELD], 0xfffffffe
8:
  cmp eax, RDZ
  jl 9f
  mov byte ptr [KEYS + 0x49], 1
  or dword ptr [HELD], 2
  jmp 10f
9:
  test dword ptr [HELD], 2
  jz 10f
  mov byte ptr [KEYS + 0x49], 0
  and dword ptr [HELD], 0xfffffffd
10:
  # edges
  mov edi, dword ptr [PPREV]
  mov dword ptr [PPREV], esi
  mov eax, edi
  not eax
  and eax, esi
  mov dword ptr [NEWP], eax          # newly down
  mov eax, esi
  not eax
  and eax, edi
  mov dword ptr [RELP], eax          # newly up
  # button -> key: (XInput bit, scan code) pairs from keymap
  .byte 0xbb                         # mov ebx, keymap
  ADDR keymap
11:
  movzx eax, word ptr [ebx]
  test eax, eax
  jz 15f
  movzx ecx, byte ptr [ebx + 2]
  test dword ptr [NEWP], eax
  jz 12f
  mov byte ptr [KEYS + ecx], 1
12:
  test dword ptr [RELP], eax
  jz 13f
  mov byte ptr [KEYS + ecx], 0
13:
  add ebx, 4
  jmp 11b
15:
  # weapons: RB next, LB previous; the key is held while the bumper is
  mov eax, dword ptr [RELP]
  test eax, 0x300
  jz 16f
  mov ecx, dword ptr [WKEY]
  test ecx, ecx
  jz 16f
  mov byte ptr [KEYS + ecx], 0
  mov dword ptr [WKEY], 0
16:
  mov edx, 1
  test dword ptr [NEWP], 0x200       # RB
  jnz 17f
  mov edx, 6                         # (= -1, modulo 7)
  test dword ptr [NEWP], 0x100       # LB
  jz 20f
17:
  call nextweapon
20:
  # Start / Back: Enter / Esc to the window (down and up)
  test dword ptr [NEWP], 0x10
  jz 21f
  push 0x001c0001
  push 0x0d
  push 0x100
  push dword ptr [HWND]
  call dword ptr [PostMessageA]
  push 0xc01c0001
  push 0x0d
  push 0x101
  push dword ptr [HWND]
  call dword ptr [PostMessageA]
21:
  test dword ptr [NEWP], 0x20
  jz 22f
  push 0x00010001
  push 0x1b
  push 0x100
  push dword ptr [HWND]
  call dword ptr [PostMessageA]
  push 0xc0010001
  push 0x1b
  push 0x101
  push dword ptr [HWND]
  call dword ptr [PostMessageA]
22:
  popad
  ret
50:
  # no pad: the joystick centred, no buttons, nothing held
  mov dword ptr [JOYX], 32767
  mov dword ptr [JOYY], 32767
  mov dword ptr [JOYZ], 32767
  mov dword ptr [JOYBTN], 0
  mov dword ptr [HATUP], 0
  mov dword ptr [HATDOWN], 0
  mov dword ptr [HATLEFT], 0
  mov dword ptr [HATRIGHT], 0
  test dword ptr [HELD], 1
  jz 51f
  mov byte ptr [KEYS + 0x47], 0
51:
  test dword ptr [HELD], 2
  jz 52f
  mov byte ptr [KEYS + 0x49], 0
52:
  mov dword ptr [HELD], 0
  mov dword ptr [PPREV], 0
  mov dword ptr [NEWP], 0
  mov dword ptr [RELP], 0
  popad
  ret

# axis: eax = a stick axis (-32768..32767) -> ecx = -32767..32767 with the dead zone DZ cut out and the rest scaled
# to the full range. Uses eax, ecx, edx.
axis:
  mov ecx, eax
  sar ecx, 31                        # -1 if negative
  xor eax, ecx
  sub eax, ecx                       # |v|
  sub eax, DZ
  jg 1f
  xor ecx, ecx
  ret
1:
  push ecx
  imul eax, eax, 32767
  xor edx, edx
  push ebx
  mov ebx, 32768 - DZ
  div ebx
  pop ebx
  cmp eax, 32767
  jbe 2f
  mov eax, 32767
2:
  pop ecx
  xor eax, ecx                       # the sign back
  sub eax, ecx
  mov ecx, eax
  ret

# nextweapon: edx = 1 (next) or 6 (previous): the next weapon carried after the one in use, in key order 1-7
# (ServoKinetic laser ... ), its key put down (WKEY). Uses eax, ebx, ecx, edi.
nextweapon:
  mov eax, dword ptr [WEAPON]
  xor ecx, ecx
  .byte 0xbf                         # mov edi, wtab
  ADDR wtab
1:
  movzx ebx, byte ptr [edi + ecx]
  cmp ebx, eax
  je 2f
  inc ecx
  cmp ecx, 7
  jb 1b
  xor ecx, ecx                       # not a keyed weapon (turbo): from the laser
2:
  mov ebx, 7                         # tries
3:
  add ecx, edx
  cmp ecx, 7
  jb 4f
  sub ecx, 7
4:
  movzx eax, byte ptr [edi + ecx]
  cmp dword ptr [WAVAIL + eax * 8], 0
  jne 5f
  dec ebx
  jnz 3b
  ret
5:
  mov eax, dword ptr [WKEY]          # a weapon key still down: up first
  test eax, eax
  jz 6f
  mov byte ptr [KEYS + eax], 0
6:
  add ecx, 2                         # scan codes 2..8 = keys 1..7
  mov byte ptr [KEYS + ecx], 1
  mov dword ptr [WKEY], ecx
  ret

# readpad: XInputGetState of the first connected pad (xinput1_4, 1_3 or 9_1_0, whichever loads) -> PB, PLX, PLY,
# PRX, PRY, PLT, PRT; eax = 1, or 0 with them zeroed when there is no pad (or no XInput).
readpad:
  pushad
  cmp dword ptr [XINIT], 0
  jne 10f
  mov dword ptr [XINIT], 1
  .byte 0xbe                         # mov esi, the three names (16 bytes each)
  ADDR s_xinput
  mov ebx, 3
2:
  push esi
  call dword ptr [LoadLibraryA]
  test eax, eax
  jz 3f
  PUSHI BASE + (s_xgs - start)
  push eax
  call dword ptr [GetProcAddress]
  test eax, eax
  jz 3f
  mov dword ptr [XGS], eax
  jmp 10f
3:
  add esi, 16
  dec ebx
  jnz 2b
10:
  cmp dword ptr [XGS], 0
  je 99f
  xor ebx, ebx                       # pad index
11:
  PUSHI XS
  push ebx
  call dword ptr [XGS]
  test eax, eax
  jz 12f
  inc ebx
  cmp ebx, 4
  jb 11b
  jmp 99f
12:
  movzx eax, word ptr [XS + 4]
  mov dword ptr [PB], eax
  movzx eax, byte ptr [XS + 6]
  mov dword ptr [PLT], eax
  movzx eax, byte ptr [XS + 7]
  mov dword ptr [PRT], eax
  movsx eax, word ptr [XS + 8]
  mov dword ptr [PLX], eax
  movsx eax, word ptr [XS + 10]
  mov dword ptr [PLY], eax
  movsx eax, word ptr [XS + 12]
  mov dword ptr [PRX], eax
  movsx eax, word ptr [XS + 14]
  mov dword ptr [PRY], eax
  popad
  mov eax, 1
  ret
99:
  xor eax, eax
  mov dword ptr [PB], eax
  mov dword ptr [PLX], eax
  mov dword ptr [PLY], eax
  mov dword ptr [PRX], eax
  mov dword ptr [PRY], eax
  mov dword ptr [PLT], eax
  mov dword ptr [PRT], eax
  popad
  xor eax, eax
  ret

# ---------------------------------------------------------------------------------------------------------------
  .p2align 2
keymap:                              # XInput button (word), scan code (byte), pad
  .word 0x8000                       # Y: V, next pilot view
  .byte 0x2f, 0
  .word 0x4000                       # X: C, next instrument display
  .byte 0x2e, 0
  .word 0x2000                       # B: Backspace, mission status
  .byte 0x0e, 0
  .word 0x0080                       # R3: Tab, satellite map
  .byte 0x0f, 0
  .word 0x0040                       # L3: X, crosshairs
  .byte 0x2d, 0
  .word 0
  .byte 0, 0
wtab:      .byte 0x01, 0x02, 0x03, 0x12, 0x13, 0x14, 0x15   # the weapons of keys 1-7
s_xgs:     .asciz "XInputGetState"
s_retrodeck: .asciz "Retrodeck"
s_invy:    .asciz "PadInvertY"
s_sqpix:   .asciz "SquarePixels"
s_quick:   .asciz "data\\QUICK.FFF"
s_put:     .asciz "put mov destination at 0 0 %d %d"
  .p2align 4
s_xinput:  .asciz "xinput1_4.dll"
  .p2align 4
           .asciz "xinput1_3.dll"
  .p2align 4
           .asciz "xinput9_1_0.dll"
