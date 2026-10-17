"""Stopped native-game access for deterministic acceptance fixtures.

Only use against a private test disk/session. Calls execute real 65816 routines;
this module does not emulate or substitute the game logic.
"""
from __future__ import annotations
import json
from pathlib import Path
import time
from probe import client_class, read, registers

SIGNATURE = b'FORCEIIGS'


class Runtime:
    def __init__(self, socket, symbols, source):
        self.client = client_class(source)()
        self.client.connect(str(socket))
        self.client.hello()
        self.manifest = json.loads(Path(symbols).read_text())
        self.symbols = self.manifest['symbols']
        self.mailbox = None
        self.base = None
        self.dp = None
        self.initial_pause = None

    def locate(self, timeout=120):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for bank in range(2, 128):
                hits = self.client.find_mem(4, bank << 16, 65536, SIGNATURE, max_hits=8)
                for address in hits:
                    raw = read(self.client, address, 28, domain=4)
                    base = int.from_bytes(raw[10:14], 'little')
                    if raw[9] == 1 and raw[16] == 1 and base and base < 0x800000:
                        self.mailbox = address
                        self.base = base
                        self.dp = int.from_bytes(raw[14:16], 'little')
                        return self
                if time.monotonic() >= deadline:
                    break
            time.sleep(.5)
        raise TimeoutError('FORCE debugger mailbox never became ready')

    def freeze(self):
        self.initial_pause = read(self.client, self.mailbox + 17, 1)[0]
        self.client.write_mem(0, self.mailbox + 17, b'\1')
        if self.client.get_status().execution_mode == 0:
            self.client.pause()
            self.client.wait_stopped(timeout=5)
        # Stop between frames, so restoring CPU registers after a probe never
        # resumes an interrupted renderer whose shared scratch has changed.
        from gs2debug import BP_KIND_EXEC
        boundary = self.address('main_loop')
        bp = self.client.bp_set(kind=BP_KIND_EXEC, address=boundary)
        try:
            self.client.continue_()
            event = self.client.wait_stopped(timeout=20)
            if event.bp_id != bp:
                raise AssertionError('Unexpected breakpoint while finding frame boundary')
        finally:
            self.client.bp_clear(bp)
        return self

    def address(self, name):
        offset = self.symbols[name]
        if name.startswith('z') and offset < 256:
            return self.dp + offset
        return self.base + offset

    def mem(self, name, count=1):
        return read(self.client, self.address(name), count)

    def set(self, name, data):
        if isinstance(data, int):
            data = bytes([data])
        self.client.write_mem(0, self.address(name), bytes(data))

    def call(self, name, a=0, x=0, y=0, timeout=20, count=1):
        """Run a bank-local simulation routine with its documented 8-bit ABI."""
        from gs2debug import (BP_KIND_EXEC, REG_PC, REG_PB, REG_DB, REG_A,
                              REG_X, REG_Y, REG_D, REG_P, REG_E, REG_SP)
        before = registers(self.client.get_regs())
        target = (self.base + self.symbols[name]) & 65535
        trampoline = self.symbols['debug_call']
        address = self.base + trampoline
        if not 1 <= count <= 255:
            raise ValueError('Native call batch count must be 1..255')
        if count == 1:
            program = bytes((0x20, target & 255, target >> 8, 0xea))
            stop = address + 3
        else:
            counter = (address + 15) & 65535
            program = bytes((0xa9, count, 0x8d, counter & 255, counter >> 8,
                             0x20, target & 255, target >> 8,
                             0xce, counter & 255, counter >> 8, 0xd0, 0xf8, 0xea, 0, 0))
            stop = address + 13
        old = read(self.client, address, len(program))
        self.client.write_mem(0, address, program)
        bp = self.client.bp_set(kind=BP_KIND_EXEC, address=stop)
        try:
            self.client.set_regs(REG_PC | REG_PB | REG_DB | REG_A | REG_X | REG_Y | REG_D | REG_P | REG_E,
                                 pc=address & 65535, pb=address >> 16, db=self.base >> 16,
                                 a=a, x=x, y=y, d=self.dp, p=0x34, e=0)
            self.client.continue_()
            event = self.client.wait_stopped(timeout=timeout)
            if event.bp_id != bp or event.pc != stop:
                raise AssertionError(f'{name} stopped at unexpected address {event.pc:06x}')
            after = registers(self.client.get_regs())
            if after['sp'] != before['sp']:
                raise AssertionError(f'{name} leaked stack: {before["sp"]:04x} -> {after["sp"]:04x}')
            return after
        except (OSError, RuntimeError, TimeoutError) as exc:
            if self.client.get_status().execution_mode == 0:
                self.client.pause()
                self.client.wait_stopped(timeout=5)
            failed = registers(self.client.get_regs())
            raise RuntimeError(f'{name} failed at {failed}: {exc}') from exc
        finally:
            self.client.bp_clear(bp)
            self.client.write_mem(0, address, old)
            self.client.set_regs(REG_PC | REG_PB | REG_DB | REG_A | REG_X | REG_Y | REG_SP | REG_D | REG_P | REG_E,
                                 pc=before['pc'], pb=before['pb'], db=before['db'],
                                 a=before['a'], x=before['x'], y=before['y'], sp=before['sp'],
                                 d=before['d'], p=before['p'], e=0)

    def close(self, resume=False):
        if resume and self.initial_pause is not None:
            self.client.write_mem(0, self.mailbox + 17, bytes([self.initial_pause]))
            self.client.continue_()
        self.client.close()
