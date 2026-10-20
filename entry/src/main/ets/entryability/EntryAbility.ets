import { Appearance } from '../presentation/Appearance';
import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { NOTIFICATION_LAUNCH_KEY, notificationLaunchValue, notificationTargetFromParameters } from '../domain/Notifications';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Appearance.restore(this.context);
    this.rememberNotificationLaunch(want);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  // A tap on a notification while the ability is alive arrives here. Parameters
  // are application-internal want data, never visible notification text.
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.rememberNotificationLaunch(want);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
  }

  private rememberNotificationLaunch(want: Want): void {
    try {
      const target = notificationTargetFromParameters(want.parameters);
      if (!target) { return; }
      // The Index page watches this AppStorage entry and uses the existing safe
      // navigation flow; the timestamp makes repeated taps on the same
      // notification produce distinct values.
      AppStorage.setOrCreate(NOTIFICATION_LAUNCH_KEY, notificationLaunchValue(target, Date.now()));
    } catch (_) { /* a reminder deep link must never block launching the app */ }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
        if (err.code) { hilog.error(DOMAIN, 'OpenCodeUI', 'Failed to load the main page.'); return; }
      Appearance.syncSystem(this.context);
    });
  }

  onConfigurationUpdate(configuration: Configuration): void { Appearance.syncSystem(this.context); }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    AppStorage.setOrCreate('appForeground', true);
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    AppStorage.setOrCreate('appForeground', false);
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
