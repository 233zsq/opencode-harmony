import { HarmonyColors as C } from '../presentation/HarmonyColors';
import { SegmentButton, SegmentButtonOptions } from '@ohos.arkui.advanced.SegmentButton';

@Component
export struct NativeSegments {
  @Prop first: string = '';
  @Prop second: string = '';
  @Prop third: string = '';
  @Prop @Watch('syncSelection') selected: number = 0;
  @State selection: number[] = [0];
  @State options: SegmentButtonOptions = SegmentButtonOptions.tab({ buttons: [{ text: '' }, { text: '' }, { text: '' }] });
  onSelect: (index: number) => void = (): void => {};
  aboutToAppear(): void {
    this.options = SegmentButtonOptions.tab({ buttons: [{ text: this.first }, { text: this.second }, { text: this.third }],
      fontColor: C.secondary, selectedFontColor: C.text, fontSize: 12, selectedFontSize: 12,
      fontWeight: FontWeight.Normal, selectedFontWeight: FontWeight.Medium,
      backgroundColor: C.field, selectedBackgroundColor: C.bubble });
    this.syncSelection();
  }
  private syncSelection(): void { this.selection = [this.selected]; }
  build() {
    SegmentButton({ options: this.options, selectedIndexes: $selection,
      onItemClicked: (index: number): void => { this.onSelect(index); } }).width('100%')
  }
}
