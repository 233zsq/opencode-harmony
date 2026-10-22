import { ModelItem } from '../domain/Core';
import { ModelPreferences, emptyModelPreferences } from '../domain/ModelSelection';
import { QuickModelPicker } from './QuickModelPicker';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
import { loadImmersiveMaterials } from '../presentation/ImmersiveMaterials';
import deviceInfo from '@ohos.deviceInfo';

// Keep the native popup anchor independent of AppStore polling. Content props update
// their own nodes, so typing and expanded panels survive background synchronization.
@Component
export struct ModelMenuHost {
  @Link open: boolean;
  @Prop label: string = '选择模型';
  @Prop canOpen: boolean = true;
  @Prop triggerWidth: number = 160;
  @Prop popupWidth: number = 272;
  @Prop popupHeight: number = 560;
  @Prop models: ModelItem[] = [];
  @Prop preferences: ModelPreferences = emptyModelPreferences();
  @Prop current: string = '';
  @Prop variant: string = '';
  @Prop busy: boolean = false;
  @Prop uncertain: boolean = false;
  @Prop error: string = '';
  @State private material: SystemUiMaterial | undefined = undefined;
  private cachedOptions: CustomPopupOptions | undefined = undefined;
  onOpen: () => void = (): void => {};
  onSelect: (id: string) => void = (): void => {};
  onVariant: (id: string) => Promise<boolean> = (): Promise<boolean> => Promise.resolve(false);
  onRefresh: () => void = (): void => {};
  onManage: () => void = (): void => {};
  aboutToAppear(): void { loadImmersiveMaterials().then((surfaces): void => { this.material = surfaces.popup; this.cachedOptions = undefined; }); }
  @Builder
  content() {
    QuickModelPicker({ models: this.models, preferences: this.preferences, current: this.current, variant: this.variant,
      busy: this.busy, uncertain: this.uncertain, error: this.error, maxHeight: this.popupHeight,
      onSelect: (id: string): void => { this.onSelect(id); }, onVariant: (id: string): Promise<boolean> => this.onVariant(id),
      onRefresh: (): void => { this.onRefresh(); }, onManage: (): void => { this.onManage(); } })
  }
  private popupBuilder: CustomBuilder = (): void => { this.content(); };
  private options(): CustomPopupOptions {
    if (this.open && this.cachedOptions) { return this.cachedOptions; }
    const options: CustomPopupOptions = { builder: this.popupBuilder, placement: Placement.BottomLeft, enableArrow: false,
      width: this.popupWidth, targetSpace: 8, offset: { x: -40, y: 0 }, radius: 24,
      popupColor: C.glass_strong, backgroundBlurStyle: BlurStyle.COMPONENT_THICK, shadow: ShadowStyle.OUTER_DEFAULT_MD,
      mask: { color: '#0A000000' }, autoCancel: true, focusable: false,
      transition: TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
      onWillDismiss: (action): void => { action.dismiss(); this.open = false; },
      onStateChange: (event): void => { if (!event.isVisible) { this.open = false; } } };
    if (deviceInfo.sdkApiVersion >= 26) {
      if (deviceInfo.apiAvailable('26.0.0')) {
        if (this.material) { options.systemMaterial = this.material; options.focusable = true; }
      }
    }
    this.cachedOptions = options; return options;
  }
  build() {
    Button(this.label, { type: ButtonType.Normal }).id('model-select').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).height(36)
      .labelStyle({ maxLines: 1, overflow: TextOverflow.Ellipsis }).backgroundColor(Color.Transparent)
      .backgroundEffect({ radius: 20, saturation: 1.1, color: C.glass_fill }).border({ width: 0.5, color: C.glass_stroke }).borderRadius(999)
      .padding({ left: 13, right: 13 }).constraintSize({ maxWidth: 220 }).width(this.triggerWidth).enabled(this.canOpen)
      .accessibilityText('选择对话模型').onClick(() => { this.onOpen(); this.open = !this.open; }).bindPopup(this.open, this.options())
  }
}
