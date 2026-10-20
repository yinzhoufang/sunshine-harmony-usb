/**
 * 隧道伴侣核心 —— 在 127.0.0.2 上冒充一台 Moonlight 服务器
 *
 * 三条数据通路：
 *   1) RTSP / HTTP / HTTPS（TCP）：本机监听 127.0.0.2:48010/47989/47984，
 *      透明转发到 127.0.0.1:同端口（hdc rport 再把它送到 PC 上偏移 +1000 的 Sunshine）
 *   2) 上行媒体（UDP → TCP）：监听 127.0.0.2:48998/48999/49000，
 *      把 Moonlight 发来的包打上 3 字节帧头后写进隧道
 *   3) 下行媒体（TCP → UDP）：从隧道解帧，发回 Moonlight 自己绑定的 47998/47999/48000
 *
 * 注意：这些 socket 选项的字面量写法在不同 SDK 小版本间略有差异，
 * 统一收在下面三个 helper 里，编译报错时只改这里。
 */

import { socket } from '@kit.NetworkKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { BridgeConfig, BridgeStats } from './Config';
import nativeTunnel, { NativeStats } from 'libusbtunnel.so';

const TAG: string = 'UsbTunnel';

/** UDP 绑定选项（若编译报错，改成 { address: { address: host, port: port } }） */
function udpBindOptions(host: string, port: number): socket.NetAddress {
  return { address: host, port: port } as socket.NetAddress;
}

/** TCP 连接选项 */
function tcpConnectOptions(host: string, port: number, timeout: number): socket.TCPConnectOptions {
  return { address: { address: host, port: port, family: 1 }, timeout: timeout } as socket.TCPConnectOptions;
}

export class TunnelBridge {
  private cfg: BridgeConfig = new BridgeConfig();
  private stats: BridgeStats = new BridgeStats();

  private servers: Array<socket.TCPSocketServer> = [];
  private conns: Array<socket.TCPSocketConnection> = [];
  private upstreams: Array<socket.TCPSocket> = [];

  private running: boolean = false;
  private timerId: number = -1;
  private lastPkts: number = 0;
  private lastBytes: number = 0;

  onLog: (line: string) => void = () => {};
  onStats: (s: BridgeStats) => void = () => {};
  onState: (running: boolean) => void = () => {};

  isRunning(): boolean {
    return this.running;
  }

  getStats(): BridgeStats {
    return this.stats.clone();
  }

  private log(line: string): void {
    hilog.info(0x0001, TAG, '%{public}s', line);
    this.onLog(line);
  }

  // ---------------- 生命周期 ----------------

  async start(cfg: BridgeConfig, context: common.UIAbilityContext): Promise<void> {
    if (this.running) {
      return;
    }
    this.cfg = cfg;
    this.stats.reset();

    await this.requestKeepAlive(context);
    const result: number = nativeTunnel.start(cfg.tunnelHost, cfg.tunnelPort, cfg.controlTunnelPort,
      cfg.listenHost, cfg.serverUdpPorts, cfg.clientUdpPorts);
    if (result !== 0) {
        throw new Error('原生 UDP 监听失败 errno=' + result);
    }
    try {
    for (let i = 0; i < cfg.proxyPorts.length; i++) {
      await this.startProxy(cfg.listenHost, cfg.proxyPorts[i], cfg.proxyPorts[i]);
    }
    // Sunshine 偏移后的 RTSP 端口是 49010，启动响应里的会话地址会写成 rtsp://<host>:49010。
    // 客户端可能连 127.0.0.2 也可能连 127.0.0.1，两个地址都接上，统一转发到设备侧 48010
    // （那条 hdc rport 已经映射到 PC 上的 49010）。
    await this.startProxy(cfg.listenHost, 49010, 48010);
    await this.startProxy('127.0.0.1', 49010, 48010);
    } catch (e) {
      await this.stop();
      const err = e as BusinessError;
      throw new Error('TCP 代理启动失败 '+ err.code + ': ' + err.message);
    }

    this.running = true;
    this.onState(true);
    this.lastPkts = 0;
    this.lastBytes = 0;
    this.timerId = setInterval(() => {
      this.report();
    }, 2000);
    this.log('已启动：假装服务器 ' + cfg.listenHost + '，隧道 ' + cfg.tunnelHost + ':' + cfg.tunnelPort);
    this.log('原生双隧道：视频 ' + cfg.tunnelPort + '，控制/音频 ' + cfg.controlTunnelPort);
    this.log('现在去 Moonlight 里添加主机 ' + cfg.listenHost + '（不要用自动发现）');
    // 自检：直接问一遍 Sunshine，把原始响应打出来，避免依赖客户端手动操作
    setTimeout(() => {
      this.selfTest();
    }, 1500);
  }

  async stop(): Promise<void> {
    nativeTunnel.stop();
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    for (let i = 0; i < this.servers.length; i++) {
      try {
        this.servers[i].off('connect');
        await this.servers[i].close();
      } catch (e) {
        // 忽略
      }
    }
    this.servers = [];
    for (let i = 0; i < this.conns.length; i++) {
      try {
        await this.conns[i].close();
      } catch (e) {
        // 忽略
      }
    }
    this.conns = [];
    for (let i = 0; i < this.upstreams.length; i++) {
      try {
        await this.upstreams[i].close();
      } catch (e) {
        // 忽略
      }
    }
    this.upstreams = [];
    this.running = false;
    this.onState(false);
    this.log('已停止');
  }

  /**
   * 申请长时任务（dataTransfer）。Moonlight 全屏后本 App 进后台，
   * 没有这一句约 10 秒后会被系统冻结、隧道就断了。
   */
  private async requestKeepAlive(context: common.UIAbilityContext): Promise<void> {
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: 'com.chenfang.usbtunnel', abilityName: 'EntryAbility' }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(
        context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      this.log('已申请后台常驻（dataTransfer）');
    } catch (e) {
      const err = e as BusinessError;
      this.log('后台常驻申请失败(' + err.code + ')，切到后台可能会被冻结');
    }
  }

  // UDP 与双向隧道由原生工作线程持有，不向 ArkTS 逐包派发。

  // ---------------- TCP 透明转发（RTSP / 配对） ----------------

  private async startProxy(listenHost: string, listenPort: number, upstreamPort: number): Promise<void> {
    const server = socket.constructTCPSocketServerInstance();
    server.on('connect', (client: socket.TCPSocketConnection) => {
      this.pipeConnection(client, upstreamPort);
    });
    await server.listen(udpBindOptions(listenHost, listenPort));
    this.servers.push(server);
    this.log('TCP 转发 ' + listenHost + ':' + listenPort + ' -> 127.0.0.1:' + upstreamPort);
  }

  private pipeConnection(client: socket.TCPSocketConnection, port: number): void {
    const upstream = socket.constructTCPSocketInstance();
    this.conns.push(client);
    this.upstreams.push(upstream);

    // 关键：upstream.connect() 是异步的，而客户端（Moonlight）会立刻发第一个请求
    // （HTTP GET / RTSP OPTIONS）。连上之前到达的字节必须先缓存，连上后补发，
    // 否则第一个请求会丢，对端只会看到一个"连上就断"的空连接。
    const backlog: ArrayBuffer[] = [];
    let ready: boolean = false;
    let loggedReq: boolean = false;
    let loggedResp: boolean = false;
    // RTSP 通道全程留档，用来确认 SETUP 响应里到底给了哪个 server_port
    const isRtsp: boolean = (port === 48010 || port === 49010);
    let upText: string = '';
    let downText: string = '';

    upstream.on('message', (info: socket.SocketMessageInfo) => {
      if (isRtsp) {
        const one = this.preview(info.message);
        this.log('RTSP↓片段 :' + port + ' ' + one);
      }
      if (!loggedResp) {
        loggedResp = true;
        this.log('响应 :' + port + ' ' + this.preview(info.message));
      }
      client.send({ data: info.message }).catch(() => {});
    });
    upstream.on('close', () => {
      if (isRtsp) {
        this.log('RTSP↑ :' + port + ' ' + upText);
        this.log('RTSP↓ :' + port + ' ' + downText);
      }
      // Sunshine 是"发完就关"的 HTTP/1.0 风格。立刻 close 会把最后一段响应截断：
      // serverinfo 小、挤得进一个包，所以看着正常；applist 大一点就会解析失败、
      // 应用列表变空白。延迟一点再关，让尾巴先落到客户端。
      setTimeout(() => {
        client.close().catch(() => {});
      }, 300);
    });
    upstream.on('error', () => {
      client.close().catch(() => {});
    });

    client.on('message', (info: socket.SocketMessageInfo) => {
      if (isRtsp && upText.length < 4000) {
        upText += this.preview(info.message) + ' || ';
      }
      if (!loggedReq) {
        loggedReq = true;
        this.log('请求 :' + port + ' ' + this.preview(info.message));
      }
      if (!ready) {
        backlog.push(info.message);
        return;
      }
      upstream.send({ data: info.message }).catch((err: BusinessError) => {
        this.log('TCP 上行失败 :' + port + ' (' + err.code + ')');
      });
    });
    client.on('close', () => {
      setTimeout(() => {
        upstream.close().catch(() => {});
      }, 300);
    });

    upstream.connect(tcpConnectOptions('127.0.0.1', port, 5000))
      .then(() => {
        ready = true;
        const n = backlog.length;
        for (let i = 0; i < n; i++) {
          upstream.send({ data: backlog[i] }).catch(() => {});
        }
        backlog.length = 0;
        this.log('TCP 通道建立 :' + port + '（补发 ' + n + ' 帧）');
      })
      .catch((err: BusinessError) => {
        this.log('TCP 通道连接失败 :' + port + ' (' + err.code + ')');
        client.close().catch(() => {});
      });
  }

  /** 自检：直接向自己的 47989 代理发 HTTP 请求，打印 Sunshine 的原始响应 */
  private async selfTest(): Promise<void> {
    const paths: string[] = ['/serverinfo', '/applist'];
    for (let i = 0; i < paths.length; i++) {
      const route = paths[i];
      const t = socket.constructTCPSocketInstance();
      let got: string = '';
      try {
        await t.connect(tcpConnectOptions('127.0.0.2', 47989, 3000));
        t.on('message', (info: socket.SocketMessageInfo) => {
          if (got.length === 0) {
            got = this.preview(info.message);
            this.log('自检' + route + ' -> ' + got);
          }
        });
        const req = 'GET ' + route + ' HTTP/1.0\r\nHost: 127.0.0.2:47989\r\n\r\n';
        await t.send({ data: req });
        await new Promise<void>((resolve: () => void) => {
          setTimeout(() => {
            resolve();
          }, 1500);
        });
        if (got.length === 0) {
          this.log('自检' + route + ' -> 无响应');
        }
      } catch (e) {
        const err = e as BusinessError;
        this.log('自检' + route + ' 连接失败 ' + err.code);
      }
      await t.close().catch(() => {});
    }
  }

  /** 把首包内容转成可读文本，用于诊断 HTTP 请求/响应 */
  private preview(buf: ArrayBuffer): string {
    const n = Math.min(buf.byteLength, 200);
    const arr = new Uint8Array(buf).slice(0, n);
    const dec = new util.TextDecoder('utf-8');
    let text = dec.decodeToString(arr);
    text = text.split('\r\n').join(' | ');
    text = text.split('\n').join(' | ');
    return text;
  }

  // ---------------- 统计 ----------------

  private report(): void {
    const native: NativeStats = nativeTunnel.getStats();
    this.stats.upPkts = native.upPkts;
    this.stats.upBytes = native.upBytes;
    this.stats.downPkts = native.downPkts;
    this.stats.downBytes = native.downBytes;
    this.stats.dropped = native.dropped;
    const pkts = this.stats.upPkts + this.stats.downPkts;
    const bytes = this.stats.upBytes + this.stats.downBytes;
    const dPkts = pkts - this.lastPkts;
    const dBytes = bytes - this.lastBytes;
    this.lastPkts = pkts;
    this.lastBytes = bytes;
    const mbps = dBytes * 8 / 2 / 1e6; // 2 秒采样
    this.log('统计 ' + mbps.toFixed(1) + ' Mbps，' + (dPkts / 2).toFixed(0) + ' 包/秒，丢弃 ' +
      this.stats.dropped + '，客户端 native' +
      ' video=' + native.videoConnected + ' control=' + native.controlConnected +
      ' send_errors=' + native.sendErrors + ' protocol_errors=' + native.protocolErrors +
      ' reconnects=' + native.reconnects + ' video_buf=' + native.videoQueue +
      ' control_buf=' + native.controlQueue + ' dispatch_p99_us=' + native.dispatchP99Us);
    this.onStats(this.stats.clone());
  }
}
