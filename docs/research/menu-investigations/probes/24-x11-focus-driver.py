#!/usr/bin/env python3
"""Investigation 24 driver for 24-x11-focus-probe.gd: moves the X11 keyboard focus away from the Godot window and back
while holding the Up arrow through XTEST. Only ctypes + libX11 + libXtst (no xdotool, no window manager).
Usage: see the header of 24-x11-focus-probe.gd. Argument: the file where the probe writes its X11 window id; optional --no-autorepeat turns the X server's key
autorepeat off first (to see whether a held key comes back after the focus returns)."""
import ctypes
import os
import sys
import time

x11 = ctypes.CDLL("libX11.so.6")
xtst = ctypes.CDLL("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XDefaultRootWindow.restype = ctypes.c_ulong
x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x11.XCreateSimpleWindow.restype = ctypes.c_ulong
x11.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint,
                                    ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_ulong]
x11.XMapRaised.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XSetInputFocus.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
x11.XFlush.argtypes = [ctypes.c_void_p]
x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
x11.XKeysymToKeycode.restype = ctypes.c_ubyte
x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
ERR = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)
_keep = ERR(lambda d, e: 0)  # ignore BadMatch while the Godot window is not yet viewable
x11.XSetErrorHandler(_keep)

REVERT_TO_PARENT = 2
XK_UP = 0xFF52


def now():
    return "%05d" % (int(time.time() * 1000) % 100000)


def log(msg):
    print(now(), "driver:", msg, flush=True)


wid_file = sys.argv[1]
for _ in range(200):
    if os.path.exists(wid_file) and open(wid_file).read().strip():
        break
    time.sleep(0.05)
godot = int(open(wid_file).read().strip())
dpy = x11.XOpenDisplay(None)
other = x11.XCreateSimpleWindow(dpy, x11.XDefaultRootWindow(dpy), 0, 0, 50, 50, 0, 0, 0)
x11.XMapRaised(dpy, other)
x11.XSync(dpy, 0)
up = x11.XKeysymToKeycode(dpy, XK_UP)
if "--no-autorepeat" in sys.argv:
    x11.XAutoRepeatOff.argtypes = [ctypes.c_void_p]
    x11.XAutoRepeatOff(dpy)
    log("server key autorepeat OFF")


def focus(w, name):
    x11.XSetInputFocus(dpy, w, REVERT_TO_PARENT, 0)
    x11.XSync(dpy, 0)
    log("XSetInputFocus -> " + name)


def key(down):
    xtst.XTestFakeKeyEvent(dpy, up, 1 if down else 0, 0)
    x11.XSync(dpy, 0)
    log("XTEST Up " + ("down" if down else "up"))


time.sleep(1.5)
focus(godot, "godot")
time.sleep(0.5)
key(True)
time.sleep(0.3)
focus(other, "other client (Alt+Tab equivalent; Up still held)")
time.sleep(1.0)
focus(godot, "godot (Up still held)")
time.sleep(1.5)
key(False)
time.sleep(0.3)
key(True)
time.sleep(0.3)
key(False)
log("done")
