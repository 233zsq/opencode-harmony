import { image } from '@kit.ImageKit';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct ZoomableAttachment {
  @Prop @Watch('resetView') url: string = '';
  private resetView(): void { this.resize(1); }
  @Prop pixels: image.PixelMap | undefined = undefined;
  @State zoom: number = 1;
  @State x: number = 0;
  @State y: number = 0;
  private baseZoom: number = 1;
  private baseX: number = 0;
  private baseY: number = 0;
  private frameWidth: number = 320;
  private resize(value: number): void { this.zoom = Math.max(1, Math.min(4, value)); this.x = Math.max(-this.frameWidth * (this.zoom - 1) / 2, Math.min(this.frameWidth * (this.zoom - 1) / 2, this.x)); this.y = Math.max(-190 * (this.zoom - 1), Math.min(190 * (this.zoom - 1), this.y)); }
  build() {
    Column({ space: 8 }) {
      Stack() {
        Image(this.pixels || this.url).id(this.pixels ? 'attachment-pdf-image' : 'attachment-preview-image').width('100%').height('100%').objectFit(ImageFit.Contain)
          .scale({ x: this.zoom, y: this.zoom }).translate({ x: this.x, y: this.y }).accessibilityText('附件图片预览')
      }.id('attachment-zoom-viewport').width('100%').height(380).clip(true).backgroundColor(C.field).borderRadius(14)
        .onAreaChange((oldArea: Area, newArea: Area): void => { this.frameWidth = Number(newArea.width); })
        .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent): GestureJudgeResult => { return !info.isSystemGesture && info.type === GestureControl.GestureType.PAN_GESTURE && this.zoom <= 1 ? GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE; })
        .gesture(GestureGroup(GestureMode.Parallel,
          PinchGesture().onActionStart(() => { this.baseZoom = this.zoom; }).onActionUpdate((event: GestureEvent) => { this.resize(this.baseZoom * event.scale); }),
          PanGesture().onActionStart(() => { this.baseX = this.x; this.baseY = this.y; }).onActionUpdate((event: GestureEvent) => { if (this.zoom > 1) { this.x = this.baseX + event.offsetX; this.y = this.baseY + event.offsetY; this.resize(this.zoom); } }),
          TapGesture({ count: 2 }).onAction(() => { this.resize(1); })
        ))
      Row({ space: 10 }) {
        Button('缩小').id('attachment-zoom-out').height(40).fontSize(14).backgroundColor(C.field).fontColor(C.text).enabled(this.zoom > 1).onClick(() => { this.resize(this.zoom - 0.5); })
        Button('适应').id('attachment-zoom-reset').height(40).fontSize(14).backgroundColor(C.field).fontColor(C.text).onClick(() => { this.resize(1); })
        Button('放大').id('attachment-zoom-in').height(40).fontSize(14).backgroundColor(C.field).fontColor(C.text).enabled(this.zoom < 4).onClick(() => { this.resize(this.zoom + 0.5); })
        Text(Math.round(this.zoom * 100) + '%').id('attachment-zoom-level').fontSize(12).fontColor(C.secondary)
      }.width('100%')
      Text('双指缩放，放大后拖动；双击复位').fontSize(12).fontColor(C.secondary).width('100%')
    }.width('100%')
  }
}
