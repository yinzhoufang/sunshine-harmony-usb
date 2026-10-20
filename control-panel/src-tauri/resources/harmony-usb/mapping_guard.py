"""Repair missing USB mappings outside the relay's media/event-loop thread."""
import contextlib
import ctypes
import json
import os
from pathlib import Path
import re
import subprocess
import threading

MAPS = ((48010, 49010), (47989, 48989), (47984, 48984),
        (47997, 47997), (47996, 47996), (48984, 48984), (48989, 48989))


@contextlib.contextmanager
def mode_lock():
    # The exact same mutex as transport_mode.ps1: no repair during switch/rollback.
    if os.name != 'nt':
        raise RuntimeError('USB mapping recovery requires Windows')
    from ctypes import wintypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateMutexW.argtypes = (ctypes.c_void_p, wintypes.BOOL, wintypes.LPCWSTR)
    kernel.CreateMutexW.restype = wintypes.HANDLE
    kernel.WaitForSingleObject.argtypes = (wintypes.HANDLE, wintypes.DWORD)
    kernel.WaitForSingleObject.restype = wintypes.DWORD
    kernel.ReleaseMutex.argtypes = (wintypes.HANDLE,)
    kernel.CloseHandle.argtypes = (wintypes.HANDLE,)
    handle = kernel.CreateMutexW(None, False, 'Global\\SunshineHarmonyUsbMode')
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    held = False
    try:
        held = kernel.WaitForSingleObject(handle, 0) in (0, 0x80)
        yield held
    finally:
        if held:
            kernel.ReleaseMutex(handle)
        kernel.CloseHandle(handle)


class MappingGuard:
    def __init__(self, hdc, state_path, runner=None, lock=mode_lock, log=print):
        self.hdc = hdc
        self.state_path = Path(state_path)
        self.runner = runner or self._run
        self.lock = lock
        self.log = log
        self.stop_event = threading.Event()
        self.thread = None
        self.last_status = None

    def _run(self, args):
        result = subprocess.run([self.hdc, *args], capture_output=True,
                                encoding='utf-8', errors='replace', timeout=3,
                                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if result.returncode:
            raise RuntimeError('hdc command failed')
        text = result.stdout
        if re.search(r'\b(fail(?:ed)?|error|unauthorized)\b', text, re.I):
            raise RuntimeError('hdc command rejected')
        return text

    def status(self, value):
        if value != self.last_status:
            self.log('[relay] usb_recovery=' + value, flush=True)
            self.last_status = value

    def check(self):
        with self.lock() as held:
            if not held:
                return
            state = json.loads(self.state_path.read_text(encoding='utf-8-sig'))
            if not isinstance(state, dict):
                raise ValueError('invalid transport state')
            if state.get('mode') != 'usb':
                self.status('disabled')
                return
            target = state.get('device_id', '')
            if not isinstance(target, str) or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.:-]{0,127}', target):
                self.status('invalid_device')
                return
            targets = self.runner(['list', 'targets']).splitlines()
            if target not in [line.strip() for line in targets]:
                self.status('waiting_device')
                return
            args = ['-t', target]
            rules = self.runner(args + ['fport', 'ls'])
            missing = []
            for local, remote in MAPS:
                pattern = rf'(?<!\S)tcp:{local}\s+tcp:{remote}\s+\[Reverse\]'
                if re.search(pattern, rules):
                    continue
                # A different rule already owns this device port. Never delete it.
                if re.search(rf'(?<!\S)tcp:{local}\s+tcp:\d+\s+\[Reverse\]', rules):
                    self.status('mapping_conflict')
                    return
                missing.append((local, remote))
            if missing:
                self.status('repairing')
                for local, remote in missing:
                    if self.stop_event.is_set():
                        return
                    self.runner(args + ['rport', f'tcp:{local}', f'tcp:{remote}'])
                rules = self.runner(args + ['fport', 'ls'])
                if any(not re.search(rf'(?<!\S)tcp:{a}\s+tcp:{b}\s+\[Reverse\]', rules)
                       for a, b in MAPS):
                    raise RuntimeError('mapping verification failed')
                self.log(f'[relay] usb_repaired mappings={len(missing)}', flush=True)
            self.status('ready')

    def _loop(self):
        while not self.stop_event.is_set():
            try:
                self.check()
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                self.status('retrying')
            self.stop_event.wait(2)

    def start(self):
        self.thread = threading.Thread(target=self._loop, name='usb-mapping-recovery', daemon=True)
        self.thread.start()

    def stop(self):
        self.stop_event.set()
