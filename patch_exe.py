#!/usr/bin/env python3
"""Patch Fury3 (FURY3\\FURY3.EXE on the US retail disc: v1.1.0.1, 645,120 bytes, MD5 9907b1b8f1550827ab0c47ddf1723038,
linked 14 Aug 1995, MSVC 2 / "CYBERUI MFC Application") into a copy.

  patch_exe.py <FURY3.EXE> <out.exe>   write the patched exe (refuses, writes nothing, on any unexpected byte)
  patch_exe.py --check-caves           re-assemble caves.s with clang and compare with CAVE below

New code (caves.s, assembled bytes in CAVE) goes into a section the patch adds: ".rdeck", VA 0x57c000, 0x2000 bytes
at file offset 0x9d800 (the end of the file, after .reloc), readable / writable / executable; its variables from
0x57d000. The section table had room for an eighth entry (it ended at 0x290, the first section starts at 0x400);
SizeOfImage 0x17c000 -> 0x17e000. The exe has no checksum and loads at its 0x400000 base; the header now also says
"relocations stripped", so no loader ever moves it.

The game (docs/TECHNICAL.md): a GDI program (no DirectDraw). It draws a 320x200 8-bit picture into a DIB
section and, in a window, BitBlts / StretchBlts it to the client area in WM_PAINT (0x409fc0); its "Full Screen" was
Win16 DISPDIB.DLL plus direct writes to the VGA memory at 0xA0000, on Windows 95 only (GetVersion 0x40b5a6: NT gets
"0x350" and the window, as Wine does). WinG only under Win32s. Movement is timed by timeGetTime (0x446e10), every loop
runs flat out. Sound: its own mixer thread on waveOut, MOD music from the POD files (the disc's 5 audio tracks are a
bonus soundtrack the game never plays). Movies: MCI "avivideo" (Cinepak) in a child window. Joystick: winmm, off on
NT. Keyboard: a scan-code table from WM_KEYDOWN / WM_KEYUP. Settings: SYSTEM\\FURY3.INI.

Patches (va: what was there -> what is there now):
  ram         0x40b6c4: "mov eax, [ebp-0x34]; mov [0x53e8ac], eax" (GlobalMemoryStatus' dwTotalPhys, compared
              signed with 9 MB at 0x42d210 / 0x42d2db / 0x433eea) -> call memclamp: every MEMORYSTATUS figure clamped
              to 2 GB - 1 first (Proton's forced large-address-aware flag reports up to 4 GB: negative, the low-memory
              texture cache).
  window      0x40b696: "call [CreateWindowExA]" (WS_OVERLAPPEDWINDOW 328x246, menu bar) -> call createwin: WS_POPUP |
              WS_CLIPCHILDREN covering the screen, no menu bar. 0x40b5e6: the class cursor (IDC_ARROW) -> none
              ("mov [ebp-0x4c], eax" -> "mov [ebp-0x4c], ebx", ebx = 0). 0x40bc40: the intro's
              ShowWindow(SW_MAXIMIZE) -> SW_SHOW (the window already has the screen's size; a maximised popup would
              stop at the taskbar on Windows).
  fullscreen  0x40a840: F4 / View > Full Screen (toggle 0x409d40: on NT it shrank the window back to 320x200 and
              centred it) -> ret.
  blit        0x40a0ba: the windowed blit (whole client area) -> jmp blit: 4:3 at the client area's height, centred,
              black bars ([Retrodeck] SquarePixels=1: whole multiples of 320x200).
  wndproc     0x40ab30: the window procedure's first instructions -> jmp wndfilter: no pointer (WM_SETCURSOR), Enter in
              flight = P (pause), Esc on the title = quit, F11 = Save Game (data\\QUICK.FFF when unnamed), F12 = Resume
              Saved Game.
  framecap    0x40bcc0: the frame display (InvalidateRect + pump, every loop's) -> jmp framecap: the pad read, then
              at most 60 frames a second (sleeping).
  kbhit       0x446e90: "key waiting?" -> jmp kbhitc: sleeps 1 ms when there is none (the spin loops).
  keywait     0x446e69: waitkey's "call pump" -> call keywait: pump, Sleep(5), pad A = Y, B = N.
  title       0x44fe5a: the title loop's "call kbhit" -> call titlekb: notes the title is up (Esc quits there),
              Enter = New Game.
  flighttime  0x425329: the flight loop's clock read -> call flighttime: notes the flight loop is running (Enter =
              pause there).
  moviewait   0x45049f: the movie loop's "call pump" -> call moviewait: pump, Sleep(5), the pad skips the movie.
  movie       0x450050: the movie window placement (1:1 or 2x, centred) -> jmp movieplace: 4:3 at full height, MCI
              "put destination".
  pumpidle    0x409cc6, 0x409cde: the pump's "jmp 0x409bff" while minimised / inactive (a spin) -> jmp pumpidle
              (Sleep(20) first).
  joyinit     0x414aa0: the joystick set-up (off on NT) -> jmp joyinit: mode 2 (joystick, throttle on buttons) with
              the calibration and buttons the pad code writes for; reads [Retrodeck] PadInvertY / SquarePixels.
  joyread     0x414c70, 0x414e80: the joystick reads (nothing on NT) -> jmp joyread (padupdate keeps the joystick
              figures current at every frame).
"""
import hashlib, os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE, MD5 = 645120, "9907b1b8f1550827ab0c47ddf1723038"
DELTA = 0x400c00                       # .text (VA 0x401000, file offset 0x400): file offset = VA - 0x400c00
def T(va):
    if 0x401000 <= va < 0x45ea00: return va - DELTA
    raise AssertionError(hex(va))

def rel32(src, dst, op):               # e8 / e9 at src (5 bytes) -> dst
    return bytes([op]) + (dst - (src + 5)).to_bytes(4, "little", signed=True)
NOP = b"\x90"

SECT_VA, SECT_RVA, SECT_OFF, SECT_SIZE = 0x57c000, 0x17c000, 0x9d800, 0x2000
CAVE_VA, VARS = SECT_VA, 0x1000        # code from 0x57c000, variables from 0x57d000
CAVE = bytes.fromhex(
    "6a01ff152c555400894424206a00ff152c5554008944241cc744241400000000c744241800000000c744241000000082c744242800000000"
    "ff253c55540051528d4dccba060000008139ffffff7f7606c701ffffff7f83c1044a75ec5a598b45cca3ace85300c38b44240883f820751c"
    "66837c2410010f85e50000006a00ff158c545400b801000000c210003d00010000740b3d010100000f85c3000000837c240c0d7541817c24"
    "0801010000750ec6055cb94e0000c60559b94e0000e8a900000085c00f8497000000c744240c500000008b44241025ffff00ff0d00001900"
    "89442410eb7b817c2408000100007571837c240c1b751fe89b00000085c074618b4424046a006a006a1050ff15f854540031c0c21000837c"
    "240c7a7520803d60ff450000751068b8ca57006860ff4500ff1574535400b812800000eb0c837c240c7b751db8118000008b4c24046a0050"
    "681101000051ff15f854540031c0c2100083ec405356e9cae9e8ff833d60e85300017520833dc4e75300007517ff158c5554002b0540d057"
    "0083f8647306b801000000c331c0c3ff158c5554002b0544d057003dc80000007306b801000000c331c0c3ff158c555400a340d05700e9b8"
    "50e8ffff158c555400a344d05700e8e201000085c0741c833d141f54000d7513833d6424540000750ac7056424540001000000c38b442430"
    "a350d057008b35d02953008b3de02a5300833d4cd057000075208d04bd0000000031d2b903000000f7f189fb39f0763d8d1c76c1eb0289f0"
    "eb3389f031d2b940010000f7f189c389f831d2b9c8000000f7f139d8760289d885c07505b80100000069d8c800000069c040010000a35cd0"
    "5700891d60d0570089f129c1d1f9890d54d0570089f929d9d1f9890d58d05700a154d0570085c07e366a4257506a006a00ff3550d05700ff"
    "1548535400a154d0570003055cd0570089f129c16a4257516a0050ff3550d05700ff1548535400a158d0570085c07e366a4250566a006a00"
    "ff3550d05700ff1548535400a158d05700030560d0570089f929c16a425156506a00ff3550d05700ff15485354006a03ff3550d05700ff15"
    "28535400682000cc00ff35d8e75300ff35d4e753006a006a00ff35fcc05300ff3560d05700ff355cd05700ff3558d05700ff3554d05700ff"
    "3550d05700ff1524535400e924dee8ff60e89e020000ff158c5554008d0440833d38d05700007511c70538d0570001000000a33cd05700eb"
    "2189c12b0d3cd05700790a6a01ff1560545400ebc981f9960000007c05a33cd0570083053cd05700326156a164245300e911f9e8ff833d14"
    "1f540000750f51526a01ff15605454005a5931c0c3b801000000c3e89557e8ff606a05ff1560545400e816020000833d141f540000752ef7"
    "0528d0570000100000740cc705141f540059000000eb16f70528d0570000200000740ac705141f54004e00000061c3e84957e8ff606a05ff"
    "1560545400e8ca010000f70528d0570010f00000740ac705443054000000000061c36a14ff1560545400e9a8d7e8ff833d48305400000f84"
    "8b00000053565783ec1089e050ff742424ff15a45454008b7424088b7c240c8d04bd0000000031d2b903000000f7f189fb39f076088d1c76"
    "c1eb0289f0890424895c240429c6d1fe29dfd1ff6a0153505756ff357cfc4500ff15b8545400ff742404ff74240468c7ca57006800d15700"
    "e81246edff83c4106a006a006a006800d15700ff156855540083c4105f5e5bc360c70528e7530002000000c7054ccb530000000000c70550"
    "cb530000000000c70548cb530000000000c7052cb64e00ff7f0000c705b8bb4e0000000000c705a4bb4e00ffff0000c705d8b94e00ff7f00"
    "00c70514b64e0000000000c70510b64e00ffff0000c7052ce75300ff3f0000c70520e8530001000000c70524e8530002000000c70528e853"
    "0008000000c7052ce8530004000000c705a8e7530001000000c70520b64e00ff7f0000c70524b64e00ff7f0000c70518b64e00ff7f0000ff"
    "35b0d453006a0068a0ca57006896ca5700ff1594535400a348d05700ff35b0d453006a0068abca57006896ca5700ff1594535400a34cd057"
    "0061c3833d04d0570000750760e80200000061c360e87903000085c00f843a0200008b3508d05700a10cd05700e8ca0200008d81ff7f0000"
    "a320b64e00a110d05700e8b5020000833d48d05700007502f7d98d81ff7f0000a324b64e00c70518b64e00ff7f000031dbf7c60010000075"
    "09833d20d0570028720383cb01833d1cd0570028720383cb02a118d057003d803e00007c0383cb083d80c1ffff7f0383cb04891db0bc4e00"
    "89f083e001a38447510089f0d1e883e001a39047510089f0c1e80283e001a38847510089f0c1e80383e001a38c475100a114d057003d80c1"
    "ffff7f10c60587b94e0001830d30d0570001eb1af70530d0570001000000740ec60587b94e0000832530d05700fe3d803e00007c10c60589"
    "b94e0001830d30d0570002eb1af70530d0570002000000740ec60589b94e0000832530d05700fd8b3d24d05700893524d0570089f8f7d021"
    "f0a328d0570089f0f7d021f8a32cd05700bb68ca57000fb70385c074270fb64b02850528d057007407c68140b94e000185052cd057007407"
    "c68140b94e000083c304ebd2a12cd05700a900030000741b8b0d34d0570085c97411c68140b94e0000c70534d0570000000000ba01000000"
    "f70528d05700000200007511ba06000000f70528d05700000100007405e853010000f70528d057001000000074306801001c006a0d680001"
    "0000ff35cc295300ff15f85454006801001cc06a0d6801010000ff35cc295300ff15f8545400f70528d0570020000000743068010001006a"
    "1b6800010000ff35cc295300ff15f854540068010001c06a1b6801010000ff35cc295300ff15f854540061c3c70520b64e00ff7f0000c705"
    "24b64e00ff7f0000c70518b64e00ff7f0000c705b0bc4e0000000000c7058447510000000000c7059047510000000000c705884751000000"
    "0000c7058c47510000000000f70530d05700010000007407c60587b94e0000f70530d05700020000007407c60589b94e0000c70530d05700"
    "00000000c70524d0570000000000c70528d0570000000000c7052cd057000000000061c389c1c1f91f31c829c82d581b00007f0331c9c351"
    "69c0ff7f000031d253bba8640000f7f35b3dff7f00007605b8ff7f00005931c829c889c1c3a16047510031c9bf80ca57000fb61c0f39c374"
    "084183f90772f231c9bb0700000001d183f907720383e9070fb6040f833cc5a0df50000075044b75e5c3a134d0570085c07407c68040b94e"
    "000083c102c68140b94e0001890d34d05700c360833d04d0570000753cc70504d0570001000000bef0ca5700bb0300000056ff15b0535400"
    "85c074176887ca570050ff15b453540085c07407a300d05700eb0683c6104b75d8833d00d0570000747531db6880d0570053ff1500d05700"
    "85c074084383fb0472eaeb5b0fb70584d05700a308d057000fb60586d05700a31cd057000fb60587d05700a320d057000fbf0588d05700a3"
    "0cd057000fbf058ad05700a310d057000fbf058cd05700a314d057000fbf058ed05700a318d0570061b801000000c331c0a308d05700a30c"
    "d05700a310d05700a314d05700a318d05700a31cd05700a320d057006131c0c300802f0000402e0000200e0080000f0040002d0000000000"
    "0102031213141558496e707574476574537461746500526574726f6465636b00506164496e766572745900537175617265506978656c7300"
    "646174615c515549434b2e46464600707574206d6f762064657374696e6174696f6e20617420302030202564202564000f1f840000000000"
    "78696e707574315f342e646c6c00669078696e707574315f332e646c6c00669078696e707574395f315f302e646c6c00")
SYM = {"createwin": 0x0, "memclamp": 0x3e, "wndfilter": 0x67, "flighttime": 0x1b3, "titlekb": 0x1c3, "blit": 0x1f4, "framecap": 0x358, "kbhitc": 0x3b5, "keywait": 0x3d3, "moviewait": 0x41f, "pumpidle": 0x44a, "movieplace": 0x457, "joyinit": 0x4f0, "joyread": 0x5eb}   # labels of caves.s
def C(name): return CAVE_VA + SYM[name]

def build():
    """(va, old bytes, new bytes) for every patch site."""
    e = []
    # ram: "mov eax, [ebp-0x34]; mov [0x53e8ac], eax" -> call memclamp
    e.append((0x40b6c4, bytes.fromhex("8b45cca3ace85300"), rel32(0x40b6c4, C("memclamp"), 0xe8) + NOP * 3))
    # window: "call [CreateWindowExA]" -> call createwin; class cursor -> NULL; SW_MAXIMIZE -> SW_SHOW
    e.append((0x40b696, bytes.fromhex("ff153c555400"), rel32(0x40b696, C("createwin"), 0xe8) + NOP))
    e.append((0x40b5e6, bytes.fromhex("8945b4"), bytes.fromhex("895db4")))
    e.append((0x40bc40, bytes.fromhex("6a03"), bytes.fromhex("6a05")))
    # fullscreen: "push esi" (0x40a840, the toggle's first instruction) -> ret
    e.append((0x40a840, bytes.fromhex("56"), bytes.fromhex("c3")))
    # blit: "cmp dword [0x532468], 0x300" (WinG or GDI?) -> jmp blit
    e.append((0x40a0ba, bytes.fromhex("813d6824530000030000"), rel32(0x40a0ba, C("blit"), 0xe9) + NOP * 5))
    # wndproc: "sub esp, 0x40; push ebx; push esi" -> jmp wndfilter
    e.append((0x40ab30, bytes.fromhex("83ec405356"), rel32(0x40ab30, C("wndfilter"), 0xe9)))
    # framecap: "push esi; mov eax, [0x532464]" -> jmp framecap
    e.append((0x40bcc0, bytes.fromhex("56a164245300"), rel32(0x40bcc0, C("framecap"), 0xe9) + NOP))
    # kbhit: "cmp dword [0x541f14], 1; sbb eax, eax; inc eax; ret" -> jmp kbhitc
    e.append((0x446e90, bytes.fromhex("833d141f5400011bc040c3"), rel32(0x446e90, C("kbhitc"), 0xe9) + NOP * 6))
    # keywait, title, flighttime, moviewait: calls redirected
    e.append((0x446e69, rel32(0x446e69, 0x401b6d, 0xe8), rel32(0x446e69, C("keywait"), 0xe8)))
    e.append((0x44fe5a, rel32(0x44fe5a, 0x40171c, 0xe8), rel32(0x44fe5a, C("titlekb"), 0xe8)))
    e.append((0x425329, rel32(0x425329, 0x40127b, 0xe8), rel32(0x425329, C("flighttime"), 0xe8)))
    e.append((0x45049f, rel32(0x45049f, 0x401b6d, 0xe8), rel32(0x45049f, C("moviewait"), 0xe8)))
    # movie: "sub esp, 0xa0" (0x450050's first instruction) -> jmp movieplace
    e.append((0x450050, bytes.fromhex("81eca0000000"), rel32(0x450050, C("movieplace"), 0xe9) + NOP))
    # pumpidle: the two "jmp 0x409bff" -> jmp pumpidle
    for va in (0x409cc6, 0x409cde):
        e.append((va, rel32(va, 0x409bff, 0xe9), rel32(va, C("pumpidle"), 0xe9)))
    # joyinit: "sub esp, 0x194" -> jmp joyinit; joyread: the two reads' first bytes -> jmp joyread
    e.append((0x414aa0, bytes.fromhex("81ec94010000"), rel32(0x414aa0, C("joyinit"), 0xe9) + NOP))
    e.append((0x414c70, bytes.fromhex("83ec44813d"), rel32(0x414c70, C("joyread"), 0xe9)))
    e.append((0x414e80, bytes.fromhex("813d682453"), rel32(0x414e80, C("joyread"), 0xe9)))
    return e

def add_section(data):
    lfanew = struct.unpack_from("<I", data, 0x3c)[0]
    nsec = struct.unpack_from("<H", data, lfanew + 6)[0]
    optsize = struct.unpack_from("<H", data, lfanew + 20)[0]
    sh = lfanew + 24 + optsize + 40 * nsec
    if nsec != 7 or sh != 0x290 or any(data[sh:sh + 40]) or len(data) != SECT_OFF:
        sys.exit("unexpected PE header; nothing written")
    struct.pack_into("<8sIIIIIIHHI", data, sh, b".rdeck", SECT_SIZE, SECT_RVA, SECT_SIZE, SECT_OFF, 0, 0, 0, 0,
                     0xE0000060)       # code | initialised data | execute | read | write
    struct.pack_into("<H", data, lfanew + 6, nsec + 1)
    chars = struct.unpack_from("<H", data, lfanew + 22)[0]
    struct.pack_into("<H", data, lfanew + 22, chars | 1)     # IMAGE_FILE_RELOCS_STRIPPED
    if struct.unpack_from("<I", data, lfanew + 24 + 56)[0] != SECT_RVA: sys.exit("unexpected SizeOfImage")
    struct.pack_into("<I", data, lfanew + 24 + 56, SECT_RVA + SECT_SIZE)
    data += CAVE + bytes(SECT_SIZE - len(CAVE))

def elf_text(path):                    # .text bytes and label offsets of an i386 ELF object (no relocations)
    d = open(path, "rb").read()
    shoff = struct.unpack_from("<I", d, 0x20)[0]; shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x2e)
    secs = [struct.unpack_from("<10I", d, shoff + i * shentsize) for i in range(shnum)]
    names = [d[secs[shstrndx][4] + x[0]:].split(b"\0")[0].decode() for x in secs]
    if any(n.startswith(".rel") and x[5] for n, x in zip(names, secs)): sys.exit("caves.o has relocations")
    ti = names.index(".text"); text = d[secs[ti][4]:secs[ti][4] + secs[ti][5]]; syms = {}
    for x in secs:
        if x[1] != 2: continue                                   # SHT_SYMTAB
        strs = secs[x[6]]
        for i in range(x[5] // 16):
            nm, val, size, info, oth, shn = struct.unpack_from("<IIIBBH", d, x[4] + 16 * i)
            if shn == ti: syms[d[strs[4] + nm:].split(b"\0")[0].decode()] = val
    return text, syms

ENTRIES = ("createwin", "memclamp", "wndfilter", "flighttime", "titlekb", "blit", "framecap", "kbhitc", "keywait",
           "moviewait", "pumpidle", "movieplace", "joyinit", "joyread")
def check_caves():
    with tempfile.TemporaryDirectory() as t:
        o = os.path.join(t, "caves.o")
        subprocess.run(["clang", "-target", "i386-pc-linux-gnu", "-c", os.path.join(HERE, "caves.s"), "-o", o], check=True)
        text, syms = elf_text(o)
    ok = text == CAVE and all(syms.get(k) == SYM.get(k) for k in ENTRIES)
    print("caves.s matches CAVE" if ok else "caves.s differs from CAVE / SYM: update patch_exe.py")
    if not ok:
        print("CAVE =", text.hex()); print("SYM =", {k: hex(syms[k]) for k in ENTRIES})
    return ok

def patch(data, label="FURY3.EXE"):
    """Returns the patched exe; exits on any unexpected byte."""
    data = bytearray(data)
    if len(data) != SIZE or hashlib.md5(data).hexdigest() != MD5:
        sys.exit(f"{label}: not Fury3's FURY3.EXE v1.1.0.1 (size {SIZE}, MD5 {MD5}); nothing written")
    assert 0 < len(CAVE) < VARS, "CAVE empty or running into the variables at 0x57d000"
    edits = build()
    for va, old, new in edits:
        off = T(va)
        if bytes(data[off:off + len(old)]) != old or len(old) != len(new):
            sys.exit(f"unexpected bytes at VA {va:#x}; nothing written")
    for va, old, new in edits:
        data[T(va):T(va) + len(new)] = new
    add_section(data)
    print(f"  rdeck ram window fullscreen blit wndproc framecap kbhit keywait title flighttime moviewait movie "
          f"pumpidle joyinit joyread ({len(edits)} edits)")
    return bytes(data)

def main(src, dst):
    data = patch(open(src, "rb").read(), src)
    tmp = dst + ".tmp"
    open(tmp, "wb").write(data)
    os.replace(tmp, dst)
    print(f"{dst}: MD5 {hashlib.md5(data).hexdigest()}")

if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--check-caves": sys.exit(0 if check_caves() else 1)
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
