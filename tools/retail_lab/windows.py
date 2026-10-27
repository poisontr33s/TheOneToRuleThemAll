"""Small Windows bridge to one explicitly selected WoW installation.

Uses the real client window. It does not implement WoW APIs or load addon Lua.
The caller must serialize requests and authenticate access to this module.
"""

import contextlib
import ctypes as C
import os
from pathlib import Path
import struct
import time
import zlib


_COMMANDS = {"tor": "/tor", "guide": "/tor guide", "test": "/tortest", "reload": "/reload"}
_backend = None

DWORD, LONG, WORD = C.c_uint32, C.c_int32, C.c_uint16
HANDLE, BOOL = C.c_void_p, C.c_int32


class _Point(C.Structure):
    _fields_ = [("x", LONG), ("y", LONG)]


class _Rect(C.Structure):
    _fields_ = [("left", LONG), ("top", LONG), ("right", LONG), ("bottom", LONG)]


class _MouseInput(C.Structure):
    _fields_ = [("dx", LONG), ("dy", LONG), ("mouseData", DWORD),
                ("dwFlags", DWORD), ("time", DWORD), ("dwExtraInfo", C.c_size_t)]


class _KeyboardInput(C.Structure):
    _fields_ = [("wVk", WORD), ("wScan", WORD), ("dwFlags", DWORD),
                ("time", DWORD), ("dwExtraInfo", C.c_size_t)]


class _InputData(C.Union):
    _fields_ = [("mi", _MouseInput), ("ki", _KeyboardInput)]


class _Input(C.Structure):
    _fields_ = [("type", DWORD), ("data", _InputData)]


class _BitmapHeader(C.Structure):
    _fields_ = [("size", DWORD), ("width", LONG), ("height", LONG),
                ("planes", WORD), ("bits", WORD), ("compression", DWORD),
                ("image_size", DWORD), ("x_pixels", LONG), ("y_pixels", LONG),
                ("colors_used", DWORD), ("colors_important", DWORD)]


def _png(width, height, bgra):
    """Encode top-down, four-byte GDI pixels as a standard RGB PNG."""
    rgb = bytearray(width * height * 3)
    rgb[0::3], rgb[1::3], rgb[2::3] = bgra[2::4], bgra[1::4], bgra[0::4]
    if not any(rgb):
        raise RuntimeError("WoW returned a black image. Try windowed or borderless mode.")
    stride = width * 3
    scanlines = b"".join(b"\0" + rgb[row:row + stride] for row in range(0, len(rgb), stride))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines, 3)) + chunk(b"IEND", b""))


def _key(vk=0, char=0, up=False):
    event = _Input()
    event.type = 1
    event.data.ki = _KeyboardInput(vk, char, (4 if char else 0) | (2 if up else 0), 0, 0)
    return event


def _key_press(vk):
    return [_key(vk), _key(vk, up=True)]


class _WindowsBackend:
    def __init__(self, executable):
        if os.name != "nt":
            raise RuntimeError("The WoW window bridge requires Windows with the real WoW client running.")
        try:
            path = Path(executable).resolve(strict=True)
        except (OSError, TypeError, ValueError) as exc:
            raise RuntimeError("Select an existing _retail_/Wow.exe or _ptr_/WowT.exe.") from exc
        expected = {"_retail_": "wow.exe", "_ptr_": "wowt.exe"}
        if not path.is_file() or expected.get(path.parent.name.lower()) != path.name.lower():
            raise RuntimeError("Only _retail_/Wow.exe and _ptr_/WowT.exe are supported.")
        self.executable = os.path.normcase(str(path))
        self.target = None
        self.user = C.WinDLL("user32", use_last_error=True)
        self.kernel = C.WinDLL("kernel32", use_last_error=True)
        self.gdi = C.WinDLL("gdi32", use_last_error=True)
        self.dwm = C.WinDLL("dwmapi", use_last_error=True)
        self.enum_callback = C.WINFUNCTYPE(BOOL, HANDLE, C.c_ssize_t)
        self._bind_functions()

    def _bind_functions(self):
        def bind(dll, name, result, *args):
            function = getattr(dll, name)
            function.restype, function.argtypes = result, args

        bind(self.user, "EnumWindows", BOOL, self.enum_callback, C.c_ssize_t)
        for name in ("IsWindow", "IsWindowVisible", "IsIconic", "SetForegroundWindow"):
            bind(self.user, name, BOOL, HANDLE)
        bind(self.user, "GetForegroundWindow", HANDLE)
        bind(self.user, "GetWindowThreadProcessId", DWORD, HANDLE, C.POINTER(DWORD))
        bind(self.user, "GetWindowTextW", C.c_int, HANDLE, C.c_wchar_p, C.c_int)
        bind(self.user, "GetClientRect", BOOL, HANDLE, C.POINTER(_Rect))
        bind(self.user, "GetWindowRect", BOOL, HANDLE, C.POINTER(_Rect))
        bind(self.user, "ClientToScreen", BOOL, HANDLE, C.POINTER(_Point))
        bind(self.user, "GetWindow", HANDLE, HANDLE, C.c_uint)
        bind(self.user, "GetAncestor", HANDLE, HANDLE, C.c_uint)
        bind(self.user, "WindowFromPoint", HANDLE, _Point)
        bind(self.user, "GetSystemMetrics", C.c_int, C.c_int)
        bind(self.user, "GetAsyncKeyState", C.c_int16, C.c_int)
        bind(self.user, "SendInput", C.c_uint, C.c_uint, C.POINTER(_Input), C.c_int)
        bind(self.user, "SetThreadDpiAwarenessContext", HANDLE, HANDLE)
        bind(self.user, "GetDC", HANDLE, HANDLE)
        bind(self.user, "ReleaseDC", C.c_int, HANDLE, HANDLE)
        bind(self.kernel, "OpenProcess", HANDLE, DWORD, BOOL, DWORD)
        bind(self.kernel, "CloseHandle", BOOL, HANDLE)
        bind(self.kernel, "QueryFullProcessImageNameW", BOOL, HANDLE, DWORD, C.c_wchar_p, C.POINTER(DWORD))
        bind(self.gdi, "CreateCompatibleDC", HANDLE, HANDLE)
        bind(self.gdi, "CreateDIBSection", HANDLE, HANDLE, C.POINTER(_BitmapHeader), C.c_uint,
             C.POINTER(HANDLE), HANDLE, DWORD)
        bind(self.gdi, "SelectObject", HANDLE, HANDLE, HANDLE)
        bind(self.gdi, "BitBlt", BOOL, HANDLE, C.c_int, C.c_int, C.c_int, C.c_int,
             HANDLE, C.c_int, C.c_int, DWORD)
        bind(self.gdi, "GdiFlush", BOOL)
        bind(self.gdi, "DeleteObject", BOOL, HANDLE)
        bind(self.gdi, "DeleteDC", BOOL, HANDLE)
        bind(self.dwm, "DwmGetWindowAttribute", LONG, HANDLE, DWORD, HANDLE, DWORD)

    @contextlib.contextmanager
    def physical_pixels(self):
        # HTTP requests can run on different threads; set awareness on each one.
        previous = self.user.SetThreadDpiAwarenessContext(HANDLE(-4))
        if not previous:
            raise RuntimeError("Windows could not enable physical-pixel coordinates.")
        try:
            yield
        finally:
            self.user.SetThreadDpiAwarenessContext(previous)

    def _identity(self, hwnd):
        pid = DWORD()
        if not self.user.IsWindow(hwnd) or not self.user.GetWindowThreadProcessId(hwnd, C.byref(pid)):
            return None
        process = self.kernel.OpenProcess(0x1000, False, pid.value)
        if not process:
            return None
        try:
            size = DWORD(32768)
            path = C.create_unicode_buffer(size.value)
            if not self.kernel.QueryFullProcessImageNameW(process, 0, path, C.byref(size)):
                return None
            try:
                return pid.value, os.path.normcase(os.path.realpath(path.value))
            except OSError:
                return None
        finally:
            self.kernel.CloseHandle(process)

    def _find(self):
        if self.target is not None:
            hwnd, pid = self.target
            if self._identity(hwnd) != (pid, self.executable):
                raise RuntimeError("The selected WoW process closed or changed. Restart the bridge to select it again.")
            return hwnd
        matches = []

        @self.enum_callback
        def visit(hwnd, unused):
            if self.user.IsWindowVisible(hwnd):
                identity = self._identity(hwnd)
                if identity and identity[1] == self.executable:
                    matches.append((hwnd, identity[0]))
            return True

        if not self.user.EnumWindows(visit, 0):
            raise RuntimeError("Windows could not enumerate application windows.")
        if len(matches) != 1:
            raise RuntimeError("Keep exactly one visible WoW window from the selected installation open.")
        self.target = matches[0]
        return self.target[0]

    def describe(self):
        hwnd = self._find()
        if not self.user.IsWindowVisible(hwnd) or self.user.IsIconic(hwnd):
            raise RuntimeError("Restore the selected WoW window before using the bridge.")
        rect, origin = _Rect(), _Point()
        if not self.user.GetClientRect(hwnd, C.byref(rect)) or not self.user.ClientToScreen(hwnd, C.byref(origin)):
            raise RuntimeError("Windows could not read the WoW client area.")
        width, height = rect.right - rect.left, rect.bottom - rect.top
        if width <= 0 or height <= 0 or width * height > 33_177_600:
            raise RuntimeError("The WoW client area is empty or exceeds the capture limit.")
        title = C.create_unicode_buffer(512)
        self.user.GetWindowTextW(hwnd, title, len(title))
        return {"hwnd": hwnd, "pid": self.target[1], "executable": self.executable,
                "title": title.value, "width": width, "height": height,
                "client_x": origin.x, "client_y": origin.y,
                "foreground": self.user.GetForegroundWindow() == hwnd}

    def _check_target(self, info):
        current = self.describe()
        if current != info or not current["foreground"]:
            raise RuntimeError("WoW lost focus or its window changed. No further input was sent.")

    def _focus(self):
        info = self.describe()
        if not info["foreground"]:
            self.user.SetForegroundWindow(info["hwnd"])
            time.sleep(0.1)
            info = self.describe()
        if not info["foreground"]:
            raise RuntimeError("Windows refused focus. Bring WoW to the foreground and try again.")
        return info

    def _uncovered(self, info):
        """Refuse to capture pixels covered by another top-level window."""
        left, top = info["client_x"], info["client_y"]
        right, bottom = left + info["width"], top + info["height"]
        sx, sy = self.user.GetSystemMetrics(76), self.user.GetSystemMetrics(77)
        sw, sh = self.user.GetSystemMetrics(78), self.user.GetSystemMetrics(79)
        if left < sx or top < sy or right > sx + sw or bottom > sy + sh:
            raise RuntimeError("Move the entire WoW client area onto the desktop before capturing it.")
        other = self.user.GetWindow(info["hwnd"], 3)  # GW_HWNDPREV: above WoW in Z order
        seen = set()
        while other:
            if other in seen:
                raise RuntimeError("Window order changed during capture. Try again.")
            seen.add(other)
            if self.user.IsWindowVisible(other) and not self.user.IsIconic(other):
                cloaked, rect = DWORD(), _Rect()
                result = self.dwm.DwmGetWindowAttribute(other, 14, C.byref(cloaked), C.sizeof(cloaked))
                if result != 0 or not cloaked.value:
                    if not self.user.GetWindowRect(other, C.byref(rect)):
                        raise RuntimeError("Could not check an overlapping window.")
                    if rect.left < right and rect.right > left and rect.top < bottom and rect.bottom > top:
                        raise RuntimeError("Another window overlaps WoW. Move it away before capturing or clicking.")
            other = self.user.GetWindow(other, 3)

    def capture(self):
        info = self._focus()
        self._uncovered(info)
        width, height = info["width"], info["height"]
        source = self.user.GetDC(info["hwnd"])
        memory = bitmap = old = None
        try:
            if not source:
                raise RuntimeError("Windows could not access the WoW drawing surface.")
            memory = self.gdi.CreateCompatibleDC(source)
            pixels = HANDLE()
            header = _BitmapHeader(C.sizeof(_BitmapHeader), width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
            bitmap = self.gdi.CreateDIBSection(source, C.byref(header), 0, C.byref(pixels), None, 0)
            if not memory or not bitmap or not pixels:
                raise RuntimeError("Windows could not allocate the screenshot.")
            old = self.gdi.SelectObject(memory, bitmap)
            if not old or old == HANDLE(-1).value:
                raise RuntimeError("Windows could not select the screenshot bitmap.")
            self._check_target(info)
            if not self.gdi.BitBlt(memory, 0, 0, width, height, source, 0, 0, 0x00CC0020):
                raise RuntimeError("Windows could not capture WoW. Try windowed or borderless mode.")
            if not self.gdi.GdiFlush():
                raise RuntimeError("Windows could not finish drawing the screenshot.")
            data = C.string_at(pixels, width * height * 4)
            self._check_target(info)
            self._uncovered(info)
            return _png(width, height, data)
        finally:
            if old and old != HANDLE(-1).value:
                self.gdi.SelectObject(memory, old)
            if bitmap:
                self.gdi.DeleteObject(bitmap)
            if memory:
                self.gdi.DeleteDC(memory)
            if source:
                self.user.ReleaseDC(info["hwnd"], source)

    def _send(self, info, events):
        self._check_target(info)
        if any(self.user.GetAsyncKeyState(key) & 0x8000 for key in (1, 2, 4, 16, 17, 18, 91, 92)):
            raise RuntimeError("Release mouse buttons and modifier keys before sending an action.")
        inputs = (_Input * len(events))(*events)
        self._check_target(info)
        sent = self.user.SendInput(len(inputs), inputs, C.sizeof(_Input))
        if sent != len(inputs):
            self._release_partial(info, events[:sent])
            raise RuntimeError("Windows did not accept all input. Check WoW manually before retrying.")

    def _release_partial(self, info, accepted):
        # Release only our accepted downs whose paired ups were not inserted.
        # This bridge generates keyboard pairs and the left mouse button only.
        pending = {}
        for event in accepted:
            if event.type == 1:
                key = event.data.ki
                identity = (key.wVk, key.wScan, key.dwFlags & ~2)
                if key.dwFlags & 2:
                    pending.pop(identity, None)
                else:
                    release = _Input.from_buffer_copy(event)
                    release.data.ki.dwFlags |= 2
                    pending[identity] = release
            elif event.type == 0:
                flags = event.data.mi.dwFlags
                if flags & 2:
                    release = _Input()
                    release.data.mi.dwFlags = 4
                    pending["left"] = release
                if flags & 4:
                    pending.pop("left", None)
        if not pending:
            return
        try:
            self._uncovered(info)
            self._check_target(info)
        except RuntimeError:
            return
        releases = (_Input * len(pending))(*pending.values())
        # One bounded attempt, with no new downs and no automatic retry.
        self.user.SendInput(len(releases), releases, C.sizeof(_Input))

    def click(self, x, y):
        if type(x) is not int or type(y) is not int:
            raise RuntimeError("Click coordinates must be integer client pixels.")
        info = self._focus()
        if not 0 <= x < info["width"] or not 0 <= y < info["height"]:
            raise RuntimeError("The click is outside the WoW client area.")
        self._uncovered(info)
        point = _Point(info["client_x"] + x, info["client_y"] + y)
        hit = self.user.WindowFromPoint(point)
        if not hit or self.user.GetAncestor(hit, 2) != info["hwnd"]:
            raise RuntimeError("The requested pixel does not belong to the WoW window.")
        sx, sy = self.user.GetSystemMetrics(76), self.user.GetSystemMetrics(77)
        sw, sh = self.user.GetSystemMetrics(78), self.user.GetSystemMetrics(79)
        if sw < 2 or sh < 2:
            raise RuntimeError("Windows could not read the desktop size.")
        # Aim at the centre of the pixel in SendInput's 16-bit desktop space.
        dx = min(65535, ((2 * (point.x - sx) + 1) * 65536) // (2 * sw))
        dy = min(65535, ((2 * (point.y - sy) + 1) * 65536) // (2 * sh))
        events = []
        for flags in (0xC001, 0x0002, 0x0004):  # absolute virtual-desktop move, left down, left up
            event = _Input()
            event.type = 0
            event.data.mi = _MouseInput(dx, dy, 0, flags, 0, 0)
            events.append(event)
        self._send(info, events)
        return {"sent": "click", "x": x, "y": y}

    def command(self, name):
        if not isinstance(name, str) or name not in _COMMANDS:
            raise RuntimeError("Allowed commands are tor, guide, test, and reload.")
        info = self._focus()
        self._send(info, _key_press(0x1B))  # discard an existing chat entry
        time.sleep(0.05)
        self._send(info, _key_press(0x0D))
        time.sleep(0.05)
        events = []
        for char in _COMMANDS[name]:
            events.extend((_key(char=ord(char)), _key(char=ord(char), up=True)))
        self._send(info, events + _key_press(0x0D))
        return {"sent": "command", "command": _COMMANDS[name]}

    def escape(self):
        self._send(self._focus(), _key_press(0x1B))
        return {"sent": "escape"}


def configure(executable: str) -> None:
    """Select the exact installed Retail/PTR executable before serving requests."""
    global _backend
    _backend = _WindowsBackend(executable)


def _call(method, *args):
    if os.name != "nt":
        raise RuntimeError("The WoW window bridge requires Windows with the real WoW client running.")
    if _backend is None:
        raise RuntimeError("Configure the exact WoW executable before using the bridge.")
    with _backend.physical_pixels():
        return getattr(_backend, method)(*args)


def describe() -> dict:
    return _call("describe")


def capture() -> bytes:
    return _call("capture")


def click(x: int, y: int) -> dict:
    return _call("click", x, y)


def command(name: str) -> dict:
    return _call("command", name)


def escape() -> dict:
    return _call("escape")
