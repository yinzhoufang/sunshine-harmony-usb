import { AbilityConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { backgroundSession } from '../bridge/BackgroundSession';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'UsbTunnel';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate<boolean>('usbProbe', want.parameters !== undefined && want.parameters['usbProbe'] === true);
    // 页面里要拿 UIAbilityContext 去申请长时任务
    AppStorage.setOrCreate<common.UIAbilityContext>('abilityContext', this.context);
    hilog.info(DOMAIN, TAG, 'ability onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent ok');
    });
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'ability onForeground');
    backgroundSession.onForeground(this.context);
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'ability onBackground');
    backgroundSession.onBackground();
  }

  onDestroy(): void {
    backgroundSession.stop().catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'background destroy cleanup failed: %{public}d', e.code);
    });
    hilog.info(DOMAIN, TAG, 'ability onDestroy');
  }
}
