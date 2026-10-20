"""Moonlight USB 隧道中继（档位一，PC 端）

架构
----
    平板(改造版 Moonlight) <==TCP 隧道(hdc rport / USB)==> 本程序 <==UDP==> Sunshine

要点：
  * Sunshine 的 RTSP 握手经 hdc rport 到达时源地址是 127.0.0.1，因此 Sunshine
    会把视频/音频发到 127.0.0.1 的**标准客户端端口**（47998/47999/48000）。
    中继就监听这三个端口，把数据分帧后经 TCP 隧道发给平板。
  * 反向（平板 -> Sunshine）的包被还原成 UDP，发往 127.0.0.1:(标准端口 + 1000)，
    因为基地版 Sunshine 的端口整体偏移过，避开与本中继的冲突。
  * 中继在隧道拥塞时**主动丢弃视频帧**（channel 0），限制视频积压；--control-port 将控制流和音频隔离到独立 TCP——这是模拟 UDP 语义的关键设计。

用法
----
    python relay.py                       # 明文隧道，监听 127.0.0.1:47997
    python relay.py --tls-cert cert.pem --tls-key key.pem   # TLS 隧道

统计输出全部是 key=value，便于 bench/脚本解析。
"""

import argparse
import asyncio
import signal
import socket
import ssl
import sys
import time

from common import CHANNELS, CHANNEL_NAME, HDR, SUNSHINE_OFFSET, disable_udp_conn_reset

MAX_QUEUE_BYTES = 2 * 1024 * 1024   # TCP 写缓冲上限，超过则丢视频帧（回退到旧值）
RCVBUF_BYTES = 8 * 1024 * 1024      # UDP 接收缓冲

# Windows 特有：UDP socket 之前若向"没有监听者的端口"发过包，会收到 ICMP 端口不可达，
# 下一次 recv 直接抛 WSAECONNRESET(10054)，可能把接收循环打死。关掉这个行为。
# 具体实现放在 common.py（Python 的 sock.ioctl 不支持这个私有命令，得用 ctypes 调 WSAIoctl）。


class UDPSide(asyncio.DatagramProtocol):
    """收 Sunshine 发来的 UDP，分帧推进 TCP 隧道。"""

    def __init__(self, channel, relay):
        self.channel = channel
        self.relay = relay

    def datagram_received(self, data, addr):
        self.relay.to_tablet(self.channel, data)

    def error_received(self, exc):
        print(f"[relay] udp_error ch={self.channel} err={exc!r}", flush=True)


class Relay:
    def __init__(self, tunnel_port, offset, bind, tls_ctx, stats_every, csv_path, control_port=0):
        self.tunnel_port = tunnel_port
        self.offset = offset
        self.bind = bind
        self.tls_ctx = tls_ctx
        self.stats_every = stats_every
        self.csv_path = csv_path
        self.control_port = control_port
        self.writers = {}
        self.sessions = {}
        self.udp = {}
        self.session_no = 0

    # ---------- 启动 ----------
    async def start(self):
        loop = asyncio.get_running_loop()

        for ch, port in CHANNELS.items():
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            disable_udp_conn_reset(sock)
            try:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, RCVBUF_BYTES)
            except OSError as exc:
                print(f"[relay] warn rcvbuf_failed ch={ch} err={exc!r}", flush=True)
            sock.bind((self.bind, port))
            transport, _ = await loop.create_datagram_endpoint(
                lambda ch=ch: UDPSide(ch, self), sock=sock
            )
            self.udp[ch] = transport
            print(f"[relay] udp_listen ch={ch} port={port} sock={CHANNEL_NAME[ch]}", flush=True)

        server = await asyncio.start_server(
            lambda r, w: self.on_tunnel_conn(r, w, "media"), self.bind, self.tunnel_port, ssl=self.tls_ctx
        )
        control_server = None
        if self.control_port:
            control_server = await asyncio.start_server(
                lambda r, w: self.on_tunnel_conn(r, w, "control"),
                self.bind, self.control_port, ssl=self.tls_ctx)
        print(
            f"[relay] ready tunnel_port={self.tunnel_port} "
            f"control_port={self.control_port} tls={'yes' if self.tls_ctx else 'no'} offset={self.offset} "
            f"rcvbuf={RCVBUF_BYTES}",
            flush=True,
        )

        stop = asyncio.Event()
        try:
            # Windows 的 Proactor 事件循环只支持 SIGINT，部分版本直接抛
            # NotImplementedError，这里降级为"不处理信号，靠外部终止"。
            loop.add_signal_handler(
                signal.SIGINT, lambda: (print("[relay] sigint", flush=True), stop.set())
            )
        except (NotImplementedError, RuntimeError, ValueError):
            pass
        async with server:
            try:
                await stop.wait()
            finally:
                if control_server:
                    control_server.close()
                    await control_server.wait_closed()

    # ---------- 隧道 ----------
    async def on_tunnel_conn(self, reader, writer, lane="media"):
        peer = writer.get_extra_info("peername")
        if lane in self.writers:
            print(f"[relay] reject_extra_peer peer={peer} lane={lane}", flush=True)
            writer.close()
            await writer.wait_closed()
            return

        self.writers[lane] = writer
        tcp_sock = writer.get_extra_info("socket")
        if tcp_sock:
            tcp_sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.session_no += 1
        now = time.perf_counter()
        sess = {
            "no": self.session_no,
            "lane": lane,
            "writer": writer,
            "peak_buf": 0,
            "uplink": 0,
            "peer": peer,
            "t0": now,
            "last": now,
            "in": {0: 0, 1: 0, 2: 0},
            "last_in": {0: 0, 1: 0, 2: 0},
            "tcp_bytes": 0,
            "last_bytes": 0,
            "drop_no_tunnel": 0,
            "drop_queue": 0,
        }
        self.sessions[lane] = sess
        print(f"[relay] tunnel_connected session={sess['no']} peer={peer} lane={lane}", flush=True)

        stats_task = (
            asyncio.create_task(self._stats_loop(sess)) if self.stats_every > 0 else None
        )
        err = None
        try:
            while True:
                header = await reader.readexactly(HDR)
                ch = header[0]
                length = int.from_bytes(header[1:3], "big")
                if ch not in CHANNELS or length > 65507:
                    raise ValueError("invalid frame header")
                if self.control_port and ((lane == "media") != (ch == 0)):
                    raise ValueError("frame on wrong tunnel lane")
                payload = await reader.readexactly(length)
                self.to_sunshine(sess, ch, payload)
        except (asyncio.IncompleteReadError, ConnectionResetError, ssl.SSLError, OSError, ValueError) as exc:
            err = repr(exc)
        finally:
            if stats_task is not None:
                stats_task.cancel()
            self.writers.pop(lane, None)
            self.sessions.pop(lane, None)
            writer.close()
            secs = time.perf_counter() - sess["t0"]
            print(
                "[relay] tunnel_closed session={no} secs={secs:.3f} "
                "ch0_in={c0} ch1_in={c1} ch2_in={c2} tcp_bytes={tb} "
                "drop_no_tunnel={dn} drop_queue={dq} err={err} lane={lane}".format(
                    no=sess["no"], secs=secs,
                    c0=sess["in"][0], c1=sess["in"][1], c2=sess["in"][2],
                    tb=sess["tcp_bytes"],
                    dn=sess["drop_no_tunnel"], dq=sess["drop_queue"],
                    err=err, lane=lane,
                ),
                flush=True,
            )

    async def _stats_loop(self, sess):
        while True:
            await asyncio.sleep(self.stats_every)
            now = time.perf_counter()
            dt = now - sess["last"]
            delta = {ch: sess["in"][ch] - sess["last_in"][ch] for ch in (0, 1, 2)}
            dbytes = sess["tcp_bytes"] - sess["last_bytes"]
            buf = sess["writer"].transport.get_write_buffer_size()
            print(
                f"[relay] stats t={now - sess['t0']:.1f} "
                f"ch0={delta[0]} ch1={delta[1]} ch2={delta[2]} "
                f"tcp_MBps={dbytes / dt / 1048576:.2f} buf={buf} "
                f"ch0_total={sess['in'][0]} tcp_bytes_total={sess['tcp_bytes']} "
                f"lane={sess['lane']} peak_buf={sess['peak_buf']} "
                f"drop_queue={sess['drop_queue']} drop_no_tunnel={sess['drop_no_tunnel']} "
                f"uplink_total={sess['uplink']}",
                flush=True,
            )
            if self.csv_path:
                with open(self.csv_path, "a", encoding="utf-8") as fh:
                    fh.write(
                        f"{sess['no']},{now - sess['t0']:.2f},"
                        f"{delta[0]},{delta[1]},{delta[2]},{dbytes},{buf}\n"
                    )
            sess["last"] = now
            sess["last_in"] = dict(sess["in"])
            sess["last_bytes"] = sess["tcp_bytes"]

    # ---------- 数据面 ----------
    def to_tablet(self, channel, data):
        """Sunshine -> 平板：UDP 收包，分帧写入 TCP。"""
        lane = "control" if self.control_port and channel != 0 else "media"
        sess = self.sessions.get(lane)
        w = self.writers.get(lane)
        if sess is None or w is None:
            self._drop_no_tunnel(lane)
            return
        if channel == 0 and w.transport.get_write_buffer_size() > MAX_QUEUE_BYTES:
            sess["drop_queue"] += 1
            return
        w.write(bytes([channel]) + len(data).to_bytes(2, "big") + data)
        sess["peak_buf"] = max(sess["peak_buf"], w.transport.get_write_buffer_size())
        sess["in"][channel] += 1
        sess["tcp_bytes"] += HDR + len(data)

    def _drop_no_tunnel(self, lane):
        # 隧道尚未建立（或已断开）时的包直接丢弃：没有对端可发
        sess = self.sessions.get(lane)
        if sess is not None:
            sess["drop_no_tunnel"] += 1

    def to_sunshine(self, sess, channel, payload):
        """平板 -> Sunshine：TCP 收帧，还原成 UDP 发往偏移后的端口。"""
        transport = self.udp.get(channel)
        if transport is None or channel not in CHANNELS:
            return
        sess["uplink"] += 1
        transport.sendto(payload, (self.bind, CHANNELS[channel] + self.offset))


def build_argparser():
    ap = argparse.ArgumentParser(description="Moonlight USB 隧道中继（PC 端）")
    ap.add_argument("--tunnel-port", type=int, default=47997)
    ap.add_argument("--control-port", type=int, default=0,
                    help="双隧道控制/音频 TCP 端口；0 保留单隧道测试兼容模式")
    ap.add_argument("--offset", type=int, default=SUNSHINE_OFFSET,
                    help="Sunshine 端口偏移量（标准端口 + offset）")
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--tls-cert")
    ap.add_argument("--tls-key")
    ap.add_argument("--hi-res-timer", action="store_true",
                    help="把系统定时器精度提到 1ms（Windows 默认 15.6ms，"
                         "会在大码率下引入 ~15ms 的尾部抖动）")
    ap.add_argument("--stats-every", type=float, default=0.0,
                    help="每 N 秒打印一次统计；0 表示关闭")
    ap.add_argument("--csv", help="把逐秒统计追加写入该 CSV")
    return ap


def main():
    args = build_argparser().parse_args()
    if args.control_port == args.tunnel_port:
        raise SystemExit("control-port must differ from tunnel-port")
    if args.hi_res_timer:
        try:
            import ctypes
            ctypes.windll.winmm.timeBeginPeriod(1)
            print("[relay] timer_resolution=1ms", flush=True)
        except Exception as exc:  # 非 Windows 或调用失败都无所谓
            print(f"[relay] warn hi_res_timer_failed {exc!r}", flush=True)
    tls_ctx = None
    if args.tls_cert and args.tls_key:
        tls_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls_ctx.load_cert_chain(args.tls_cert, args.tls_key)
    elif args.tls_cert or args.tls_key:
        print("[relay] --tls-cert 与 --tls-key 必须同时提供", file=sys.stderr)
        sys.exit(2)

    if args.csv:
        with open(args.csv, "w", encoding="utf-8") as fh:
            fh.write("session,t_s,ch0,ch1,ch2,tcp_bytes,buf\n")

    relay = Relay(args.tunnel_port, args.offset, args.bind, tls_ctx,
                  args.stats_every, args.csv, args.control_port)
    try:
        asyncio.run(relay.start())
    except KeyboardInterrupt:
        pass
    print("[relay] exit", flush=True)


if __name__ == "__main__":
    main()
