import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

// App-local appearance; never changes the device's system-wide theme.
export class Appearance {
  static restore(context: common.Context): void {
    let mode = 'system';
    try {
      const prefs = preferences.getPreferencesSync(context, { name: 'opencode_appearance' });
      const value = prefs.getSync('mode', 'system');
      if (value === 'light' || value === 'dark') { mode = value as string; }
    } catch (_) { mode = 'system'; }
    try { Appearance.apply(context, mode); } catch (_) { AppStorage.setOrCreate('appearanceMode', 'system'); }
    Appearance.syncSystem(context);
  }
  static async save(context: common.Context, mode: string): Promise<void> {
    if (['system', 'light', 'dark'].indexOf(mode) < 0) { return; }
    try {
      const prefs = await preferences.getPreferences(context, { name: 'opencode_appearance' });
      await prefs.put('mode', mode); await prefs.flush();
      Appearance.apply(context, mode); Appearance.syncSystem(context);
    } catch (_) { throw new Error('外观设置未保存'); }
  }

  private static apply(context: common.Context, mode: string): void {
    try {
      context.getApplicationContext().setColorMode(mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
        mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      AppStorage.setOrCreate('appearanceMode', mode);
    } catch (_) { throw new Error('暂时无法切换外观'); }
  }

  static syncSystem(context: common.Context): void {
    try { AppStorage.setOrCreate('appearanceDark', context.resourceManager.getConfigurationSync().colorMode === 0); }
    catch (_) { AppStorage.setOrCreate('appearanceDark', false); }
  }
}
