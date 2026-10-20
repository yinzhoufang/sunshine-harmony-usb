/**
 * 隧道伴侣 —— 配置与数据结构
 *
 * 它冒充一台"服务器"存在于 127.0.0.2 上，Moonlight 只要添加这个地址当主机即可。
 * 所有真实流量经 USB（hdc rport）转发到 PC 上的 relay.py。
 */

export class BridgeConfig {
  /** PC 侧中继的隧道端口（经 hdc rport 映射到本机 127.0.0.1 的同号端口） */
  tunnelHost: string = '127.0.0.1';
  tunnelPort: number = 47997;
  /** 控制和音频单独走 TCP，隔离视频排队。需要新增同号 hdc rport。 */
  controlTunnelPort: number = 47996;

  /** 冒充服务器用的地址（127.0.0.0/8 全是 lo，和 127.0.0.1 互不干扰） */
  listenHost: string = '127.0.0.2';

  /** 服务器侧 UDP 端口：Sunshine 端口整体 +1000 后的值，Moonlight 从 RTSP SETUP 响应里读到 */
  serverUdpPorts: number[] = [48998, 48999, 49000];

  /** 客户端侧 UDP 端口：Moonlight 自己绑定的端口，下行要发到这里 */
  clientUdpPorts: number[] = [47998, 47999, 48000];

  /** 需要本机透明转发的 TCP 端口（RTSP / HTTP / HTTPS 配对） */
  proxyPorts: number[] = [48010, 47989, 47984, 48984, 48989];

  /** TCP 写缓冲上限（帧数），超过后只丢视频帧，模拟 UDP 语义 */
  maxPendingFrames: number = 512;
}

export class BridgeStats {
  upPkts: number = 0;
  upBytes: number = 0;
  downPkts: number = 0;
  downBytes: number = 0;
  dropped: number = 0;

  reset(): void {
    this.upPkts = 0;
    this.upBytes = 0;
    this.downPkts = 0;
    this.downBytes = 0;
    this.dropped = 0;
  }

  clone(): BridgeStats {
    const s = new BridgeStats();
    s.upPkts = this.upPkts;
    s.upBytes = this.upBytes;
    s.downPkts = this.downPkts;
    s.downBytes = this.downBytes;
    s.dropped = this.dropped;
    return s;
  }
}

export enum Channel {
  VIDEO = 0,
  CONTROL = 1,
  AUDIO = 2
}
