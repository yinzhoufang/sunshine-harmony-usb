import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { notificationManager } from '@kit.NotificationKit';

// Own the single UIAbility continuous task for the lifetime of a bridge session.
// Local experiment: a real continuous transfer with byte-count status updates.
// No finite download percentage or synthetic media activity is reported.
class BackgroundSession {
  private context: common.UIAbilityContext | undefined = undefined;
  private pending: Promise<void> | undefined = undefined;
  private wanted: boolean = false;
  private foreground: boolean = true;
  private active: boolean = false;
  private suspended: boolean = false;
  private listening: boolean = false;
  private taskId: number = -1;
  private generation: number = 0;
  private stoppingTaskIds: number[] = [];
  private notificationId: number = -1;
  private lastPublishedBytes: number = 0;
  private lastNotificationAt: number = 0;
  private notificationUpdate: Promise<void> | undefined = undefined;

  updateTransfer(upBytes: number, downBytes: number, connected: boolean): void {
    // Only update a real, currently active transfer. Idle time must not generate
    // fabricated progress or keep re-requesting a cancelled task.
    const total = upBytes + downBytes;
    const now = Date.now();
    if (!this.wanted || !this.active || this.suspended || !connected || this.notificationId < 0 ||
      total <= this.lastPublishedBytes || this.notificationUpdate !== undefined ||
      (this.lastNotificationAt > 0 && now >= this.lastNotificationAt && now - this.lastNotificationAt < 15000)) {
      return;
    }
    this.lastNotificationAt = now;
    const context = this.context;
    if (context === undefined) { return; }
    const generation = this.generation;
    const id = this.notificationId;
    this.notificationUpdate = this.publishTransfer(id, upBytes, downBytes, context, generation);
    this.notificationUpdate.finally(() => { this.notificationUpdate = undefined; });
  }

  private async publishTransfer(id: number, upBytes: number, downBytes: number,
    context: common.UIAbilityContext, generation: number): Promise<void> {
    const text = '已接收 ' + (downBytes / 1048576).toFixed(1) + ' MB · 已发送 ' +
      (upBytes / 1048576).toFixed(1) + ' MB';
    // Some device builds return the internal content enum (8) rather than
    // the public JS enum. Build the documented dataTransfer notification
    // with public constants; never reinterpret that value as a text type.
    const content: notificationManager.NotificationContent = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
      systemLiveView: { typeCode: 8, title: 'Channel USB 串流', text: text }
    };
    const request: notificationManager.NotificationRequest = {
      id: id,
      notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
      content: content,
      // The owner may update a continuous-task notification only with a template.
      // A stream has no finite completion percentage: omit optional progressValue.
      template: {
        name: 'downloadTemplate',
        data: { title: text, fileName: 'Channel USB 实时数据流' }
      },
      isOngoing: true,
      tapDismissed: false
    };
    try {
      this.log('notification_request=' + JSON.stringify(request));
      await notificationManager.publish(request);
      if (!this.isCurrent(context, generation) || this.notificationId !== id) { return; }
      this.lastPublishedBytes = upBytes + downBytes;
      this.log('transfer_notification id=' + id + ' up_bytes=' + upBytes + ' down_bytes=' + downBytes);
    } catch (e) {
      if (!this.isCurrent(context, generation)) { return; }
      const error = e as BusinessError;
      this.log('notification_failed code=' + error.code + ' message=' + error.message);
      AppStorage.setOrCreate<string>('channelBackgroundStatus', '传输通知更新失败，请保持 Channel 可见');
    }
  }

  private log(message: string): void {
    hilog.info(0x0001, 'UsbTunnel', '%{public}s', 'background ' + message);
  }

  private status(active: boolean, text: string): void {
    this.active = active;
    AppStorage.setOrCreate<boolean>('channelBackgroundActive', active);
    AppStorage.setOrCreate<string>('channelBackgroundStatus', text);
  }

  private onCancel = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (deviceInfo.sdkApiVersion < 15) { return; }
    const stoppingIndex = this.stoppingTaskIds.indexOf(info.id);
    if (stoppingIndex >= 0) {
      this.stoppingTaskIds.splice(stoppingIndex, 1);
      this.log('stop_confirmed id=' + info.id);
      return;
    }
    if (this.taskId >= 0 && info.id !== this.taskId) { return; }
    if (!this.wanted && this.taskId < 0) { return; }
    this.log('cancel id=' + info.id + ' reason=' + info.reason);
    // Invalidate both a pending query and a not-yet-resolved start request.
    this.generation++;
    this.taskId = -1;
    this.notificationId = -1;
    this.suspended = false;
    this.status(false, '后台连接保护已结束，请回到 Channel 查看');
    // Respect explicit user cancellation; never loop to reclaim a cancelled task.
    if (info.reason === backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL ||
      info.reason === backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL_REMOVE_NOTIFICATION) {
      this.wanted = false;
    }
  };

  private onSuspend = (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
    if (deviceInfo.sdkApiVersion < 20) { return; }
    if (!this.wanted || this.taskId < 0 || info.continuousTaskId !== this.taskId) { return; }
    this.suspended = info.suspendState;
    this.log('suspend id=' + info.continuousTaskId + ' reason=' + info.suspendReason);
    this.status(false, '后台连接保护已暂停，请保持 Channel 可见');
  };

  private onActive = (info: backgroundTaskManager.ContinuousTaskActiveInfo): void => {
    if (deviceInfo.sdkApiVersion < 20) { return; }
    if (!this.wanted || this.taskId < 0 || info.id !== this.taskId) { return; }
    this.suspended = false;
    this.log('active id=' + info.id);
    this.status(true, '后台传输已启动（本机测试版）');
  };

  private subscribe(): void {
    if (this.listening) { return; }
    if (deviceInfo.sdkApiVersion >= 15) {
      backgroundTaskManager.on('continuousTaskCancel', this.onCancel);
    }
    if (deviceInfo.sdkApiVersion >= 20) {
      backgroundTaskManager.on('continuousTaskSuspend', this.onSuspend);
      backgroundTaskManager.on('continuousTaskActive', this.onActive);
    }
    this.listening = true;
  }

  async start(context: common.UIAbilityContext): Promise<void> {
    if (!this.wanted || this.context !== context) { this.generation++; }
    this.context = context;
    this.wanted = true;
    await this.reconcile();
  }

  private isCurrent(context: common.UIAbilityContext, generation: number): boolean {
    return this.wanted && this.context === context && this.generation === generation;
  }

  private canRequest(context: common.UIAbilityContext, generation: number): boolean {
    return this.foreground && this.isCurrent(context, generation);
  }

  // Serialize the complete query/request/stop transaction, not just the final
  // startBackgroundRunning call. A stale query must never replace a newer task.
  private async serialize(operation: () => Promise<void>): Promise<void> {
    const previous = this.pending;
    const current = (async (): Promise<void> => {
      if (previous !== undefined) {
        try { await previous; } catch (e) { /* Allow cleanup after a failed operation. */ }
      }
      await operation();
    })();
    this.pending = current;
    try { await current; } finally {
      if (this.pending === current) { this.pending = undefined; }
    }
  }

  private async reconcile(): Promise<void> {
    if (!this.wanted || !this.foreground) { return; }
    const context = this.context;
    if (context === undefined) { return; }
    const generation = this.generation;
    await this.serialize(async (): Promise<void> => {
      if (!this.canRequest(context, generation)) { return; }
      if (deviceInfo.sdkApiVersion >= 20) {
        try {
          const tasks = await backgroundTaskManager.getAllContinuousTasks(context, true);
          if (!this.canRequest(context, generation)) { return; }
          const existing = tasks.find((task: backgroundTaskManager.ContinuousTaskInfo) =>
            task.abilityName === context.abilityInfo.name && task.backgroundModes.includes('dataTransfer'));
          if (existing !== undefined) {
            this.taskId = existing.continuousTaskId;
            this.notificationId = existing.notificationId;
            this.suspended = existing.suspendState;
            this.status(!this.suspended, this.suspended ?
              '后台连接保护已暂停，请保持 Channel 可见' : '后台传输已启动（本机测试版）');
            this.log('verified id=' + this.taskId + ' suspended=' + this.suspended);
            this.subscribe();
          } else {
            this.active = false;
            this.suspended = false;
            this.taskId = -1;
          }
        } catch (e) {
          if (!this.canRequest(context, generation)) { return; }
          const error = e as BusinessError;
          this.log('query_failed code=' + error.code + ' message=' + error.message);
        }
      }
      if (!this.canRequest(context, generation) || this.active || this.suspended) { return; }
      await this.request(context, generation);
    });
  }

  private async request(context: common.UIAbilityContext, generation: number): Promise<void> {
    try {
      this.subscribe();
      this.status(false, '正在启用后台连接保护');
      const agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      if (!this.canRequest(context, generation)) { return; }
      // Use the UIAbility overload (string[]), which returns the real task ID.
      const result = await backgroundTaskManager.startBackgroundRunning(
        context, ['dataTransfer'], agent);
      if (!this.isCurrent(context, generation)) {
        // stop() or user cancellation won the race. Do not publish a late
        // success; release a task which the system created after that decision.
        await this.releaseTask(context, result.continuousTaskId === undefined ? -1 : result.continuousTaskId);
        return;
      }
      // The request was issued in foreground. Its successful response remains
      // valid if onBackground happened while that system call was in flight.
      this.taskId = result.continuousTaskId === undefined ? -1 : result.continuousTaskId;
      this.notificationId = result.notificationId;
      this.log('task_result=' + JSON.stringify(result));


      this.lastPublishedBytes = 0;
      this.lastNotificationAt = 0;
      this.suspended = false;
      this.status(true, '后台传输已启动（本机测试版）');
      this.log('started mode=dataTransfer id=' + this.taskId +
        ' notification=' + result.notificationId);
    } catch (e) {
      if (!this.isCurrent(context, generation)) { return; }
      const error = e as BusinessError;
      this.status(false, '后台连接保护未启用，请保持 Channel 可见');
      this.log('start_failed code=' + error.code + ' message=' + error.message);
    }
  }

  private async releaseTask(context: common.UIAbilityContext, id: number): Promise<void> {
    if (id >= 0) {
      this.stoppingTaskIds.push(id);
      while (this.stoppingTaskIds.length > 16) { this.stoppingTaskIds.shift(); }
    }
    if (this.notificationUpdate !== undefined) { await this.notificationUpdate; }
    try {
      if (deviceInfo.sdkApiVersion >= 21 && id >= 0) {
        await backgroundTaskManager.stopBackgroundRunning(context, id);
      } else {
        await backgroundTaskManager.stopBackgroundRunning(context);
      }
      this.log('stopped id=' + id);
    } catch (e) {
      const error = e as BusinessError;
      this.log('stop_failed id=' + id + ' code=' + error.code + ' message=' + error.message);
    }
  }

  onForeground(context: common.UIAbilityContext): void {
    this.foreground = true;
    this.context = context;
    this.log('foreground wanted=' + this.wanted + ' active=' + this.active + ' id=' + this.taskId);
    // A missing task may be requested again only after the user returns.
    this.reconcile().catch((e: BusinessError) => this.log('resume_failed code=' + e.code));
  }

  onBackground(): void {
    this.foreground = false;
    this.log('background active=' + this.active + ' suspended=' + this.suspended + ' id=' + this.taskId);
  }

  async stop(): Promise<void> {
    this.wanted = false;
    const generation = ++this.generation;
    const context = this.context;
    await this.serialize(async (): Promise<void> => {
      let id = this.taskId;
      let hasTask = this.active || this.suspended || id >= 0;
      // A stop may invalidate an in-flight query before it adopts an existing
      // task. Locate that task here so it is still released.
      if (context !== undefined && id < 0 && deviceInfo.sdkApiVersion >= 20) {
        try {
          const tasks = await backgroundTaskManager.getAllContinuousTasks(context, true);
          const existing = tasks.find((task: backgroundTaskManager.ContinuousTaskInfo) =>
            task.abilityName === context.abilityInfo.name && task.backgroundModes.includes('dataTransfer'));
          if (existing !== undefined) {
            id = existing.continuousTaskId;
            hasTask = true;
          }
        } catch (e) {
          const error = e as BusinessError;
          this.log('stop_query_failed code=' + error.code + ' message=' + error.message);
        }
      }
      if (context !== undefined && hasTask) { await this.releaseTask(context, id); }
      this.taskId = -1;
      this.notificationId = -1;
      this.suspended = false;
      this.status(false, '后台连接保护未启用');
      if (this.generation === generation && !this.wanted) { this.context = undefined; }
    });
  }
}

export const backgroundSession: BackgroundSession = new BackgroundSession();



