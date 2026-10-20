"""USB 隧道中继 —— 共享协议常量（PC 端与鸿蒙端必须保持一致）

分帧格式（隧道内一个 UDP 数据报 = 一帧）：

    +--------+--------+--------+---------------------+
    | ch(1B) | len(2B, 大端)  | payload (len 字节)   |
    +--------+--------+--------+---------------------+

ch: 0 = 视频(47998)  1 = 控制(47999)  2 = 音频(48000)

设计约束（为什么是这三个字节）：
  * 单个 UDP 报文最大 65507 字节，2 字节长度字段足够；
  * 头部固定 3 字节，不引入对齐/可变长解析，鸿蒙端 C 实现 10 行内可完成；
  * 不携带时间戳：时间戳已经在 RTP 头部里，中继不复用也不改写（保持对 Sunshine
    与 moonlight-common-c 双向透明）。
"""

import struct

# 平板（客户端）视角的标准 Moonlight 端口
CHANNELS = {0: 47998, 1: 47999, 2: 48000}
CHANNEL_NAME = {0: "video", 1: "control", 2: "audio"}

HDR = 3                      # 帧头长度
MAX_PAYLOAD = 65535          # 2 字节长度字段上限

# 基地版 Sunshine 端口整体偏移量：Sunshine 实际端口 = 标准端口 + 1000
# （避开与中继占用的 47998/47999/48000 冲突，见 PROTOCOL.md）
SUNSHINE_OFFSET = 1000

DEFAULT_PKT = 1400           # 模拟 RTP 负载大小（以太网 MSS 附近）

# 测试用报文头：seq(u32) + 发送时刻 perf_counter_ns(u64)，紧跟填充字节
# 注意：这是**测试脚手架专用**，不属于隧道协议本身。
PROBE = struct.Struct("<IQ")


def pack_frame(channel: int, payload: bytes) -> bytes:
    if len(payload) > MAX_PAYLOAD:
        raise ValueError(f"payload too large: {len(payload)}")
    return bytes([channel]) + len(payload).to_bytes(2, "big") + payload


def unpack_header(buf: bytes):
    """从缓冲区前 3 字节解析帧头，返回 (channel, length)。"""
    return buf[0], int.from_bytes(buf[1:3], "big")


# Windows 特有：UDP socket 若向"没人监听的端口"发过包，会收到 ICMP 端口不可达，
# 下一次 recv 直接抛 WSAECONNRESET(10054)，可能把接收循环打死。
# Python 的 socket.ioctl 不接受这个私有命令，只能用 ctypes 直接调 WSAIoctl。
SIO_UDP_CONNRESET = 0x9800000C


def disable_udp_conn_reset(sock):
    """关掉 Windows 上 UDP 的 ICMP 重置行为；非 Windows 直接返回 False。"""
    try:
        import ctypes
        from ctypes import wintypes

        inbuf = wintypes.BOOL(False)      # FALSE = 不把 ICMP 错误投递给用户态
        returned = wintypes.DWORD(0)
        rc = ctypes.windll.ws2_32.WSAIoctl(
            sock.fileno(),
            SIO_UDP_CONNRESET,
            ctypes.byref(inbuf), ctypes.sizeof(inbuf),
            None, 0,
            ctypes.byref(returned),
            None, None,
        )
        return rc == 0
    except Exception:
        return False
