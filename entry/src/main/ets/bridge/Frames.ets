/**
 * 分帧编解码 —— 与 PC 端 relay.py / common.py 完全一致
 *
 *   +--------+--------+--------+---------------------+
 *   | ch(1B) | len(2B, 大端)  | payload (len 字节)   |
 *   +--------+--------+--------+---------------------+
 *
 * 隧道是 TCP 字节流，帧可能被任意切分，所以接收侧必须做流式重组。
 */

export const FRAME_HEADER: number = 3;

export function encodeFrame(channel: number, payload: ArrayBuffer): ArrayBuffer {
  const n = payload.byteLength;
  const out = new Uint8Array(FRAME_HEADER + n);
  out[0] = channel;
  out[1] = (n >> 8) & 0xff;
  out[2] = n & 0xff;
  out.set(new Uint8Array(payload), FRAME_HEADER);
  return out.buffer as ArrayBuffer;
}

/** 一条完整帧 */
export class Frame {
  channel: number = 0;
  payload: Uint8Array = new Uint8Array(0);
}

/** 流式重组器：喂字节，吐完整帧 */
export class FrameAssembler {
  private buf: Uint8Array;
  private len: number = 0;

  constructor(capacity: number = 1024 * 1024) {
    this.buf = new Uint8Array(capacity);
  }

  /** 返回本次能解析出的所有完整帧（可能为空） */
  feed(chunk: ArrayBuffer, onFrame: (f: Frame) => void): void {
    const src = new Uint8Array(chunk);
    if (this.len + src.byteLength > this.buf.byteLength) {
      // 缓冲区不够（理论上不该发生：单帧上限 64KB），压缩一次再判断
      this.compact(0);
      if (this.len + src.byteLength > this.buf.byteLength) {
        // 仍然放不下：丢弃这一块，避免把后续帧带偏
        return;
      }
    }
    this.buf.set(src, this.len);
    this.len += src.byteLength;

    let off = 0;
    while (this.len - off >= FRAME_HEADER) {
      const ch = this.buf[off];
      const n = (this.buf[off + 1] << 8) | this.buf[off + 2];
      if (ch > 2 || n === 0) {
        // 流对不上，整段丢弃（正常情况不会发生）
        off = this.len;
        break;
      }
      if (this.len - off < FRAME_HEADER + n) {
        break;
      }
      const frame = new Frame();
      frame.channel = ch;
      frame.payload = this.buf.slice(off + FRAME_HEADER, off + FRAME_HEADER + n);
      off += FRAME_HEADER + n;
      onFrame(frame);
    }
    this.compact(off);
  }

  private compact(consumed: number): void {
    if (consumed <= 0) {
      return;
    }
    const remain = this.len - consumed;
    if (remain > 0) {
      this.buf.copyWithin(0, consumed, this.len);
    }
    this.len = remain;
  }

  reset(): void {
    this.len = 0;
  }
}
