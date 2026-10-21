import nativeTunnel from 'libusbtunnel.so';
import { common } from '@kit.AbilityKit';
import { BridgeConfig, BridgeStats } from '../bridge/Config';
import { TunnelBridge } from '../bridge/TunnelBridge';

@Entry
@Component
struct Index {
  @StorageLink('channelBackgroundActive') backgroundActive: boolean = false;
  @StorageLink('channelBackgroundStatus') backgroundStatus: string = '后台连接保护未启用';
  @State running: boolean = false;
  @State busy: boolean = false;
  @State statsText: string = '上行 0 包 / 下行 0 包 / 丢弃 0';
  @State hint: string = '先点「启动」，再去 Moonlight 添加主机 127.0.0.2';
  @State logs: string[] = [];

  private bridge: TunnelBridge = new TunnelBridge();
  private cfg: BridgeConfig = new BridgeConfig();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 打开页面后自动启动桥：省掉一次手动点击，也避免"忘了点启动"导致连不上
    setTimeout(() => {
      if (!this.running && !this.busy) {
        this.toggle();
      }
    }, 800);
    this.bridge.onLog = (line: string) => {
      const next: string[] = this.logs.slice();
      next.push(line);
      while (next.length > 300) {
        next.shift();
      }
      this.logs = next;
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Bottom);
      }, 30);
    };
    this.bridge.onStats = (s: BridgeStats) => {
      this.statsText = '上行 ' + s.upPkts + ' 包 / 下行 ' + s.downPkts + ' 包 / 丢弃 ' + s.dropped;
    };
    this.bridge.onState = (r: boolean) => {
      this.running = r;
    };
  }

  private async toggle(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      if (this.running) {
        nativeTunnel.stopProbe();
        await this.bridge.stop();
        this.hint = '已停止';
      } else {
        const ctx = AppStorage.get<common.UIAbilityContext>('abilityContext');
        if (ctx === undefined) {
          this.hint = '拿不到 AbilityContext，无法启动';
          return;
        }
        this.hint = '正在启动…';
        // Explicit diagnostic mode uses isolated HDC/PC ports. The production
        // relay and Sunshine service can stay running during latency A/B tests.
        const diagnostic: boolean = AppStorage.get<boolean>('usbProbe') === true;
        this.cfg.tunnelPort = diagnostic ? 57997 : 47997;
        this.cfg.controlTunnelPort = diagnostic ? 57996 : 47996;
        await this.bridge.start(this.cfg, ctx);
        if (AppStorage.get<boolean>('usbProbe') === true) {
          const rc: number = nativeTunnel.startProbe();
          if (rc !== 0) { throw new Error('诊断回环启动失败 errno=' + rc); }
        }
        this.hint = '运行中：Moonlight 添加主机 ' + this.cfg.listenHost;
      }
    } catch (e) {
      this.hint = '启动失败：' + JSON.stringify(e);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('Channel')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Text(this.hint)
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')

      Column({ space: 4 }) {
        Text('冒充服务器：' + this.cfg.listenHost)
          .fontSize(13)
        Text('转发目标：' + this.cfg.tunnelHost + ':' + this.cfg.tunnelPort + ' / ' + this.cfg.controlTunnelPort + '（视频 / 控制音频）')
          .fontSize(13)
        Text('UDP 上行口：' + this.cfg.serverUdpPorts.join(' / '))
          .fontSize(13)
        Text('TCP 转发口：' + this.cfg.proxyPorts.join(' / '))
          .fontSize(13)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .borderRadius(8)
      .backgroundColor('#F2F2F2')

      Text(this.backgroundStatus)
        .fontSize(13)
        .fontColor(this.backgroundActive ? '#17834A' : '#9A5C00')
        .width('100%')

      Text(this.statsText)
        .fontSize(13)
        .fontColor('#0070FF')
        .width('100%')

      Row({ space: 12 }) {
        Button(this.running ? '停止' : '启动')
          .width(140)
          .enabled(!this.busy)
          .onClick(() => {
            this.toggle();
          })
        Button('清空日志')
          .layoutWeight(1)
          .onClick(() => {
            this.logs = [];
          })
      }
      .width('100%')

      Scroll(this.scroller) {
        Column({ space: 4 }) {
          ForEach(this.logs, (line: string, idx: number) => {
            Text(line)
              .fontSize(12)
              .fontColor('#333333')
              .width('100%')
              .textAlign(TextAlign.Start)
          }, (line: string, idx: number) => idx.toString() + ':' + line)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .padding(8)
      .borderRadius(8)
      .backgroundColor('#FAFAFA')
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }
}
