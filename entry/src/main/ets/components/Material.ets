import { HarmonyColors as C } from '../presentation/HarmonyColors';

// Universal liquid-glass surface.
// Uses a portable blur + saturation + specular sheen composed from API24-safe
// attributes so the same component renders on API24 and API26 devices.
@Component
export struct GlassPanel {
  @Prop radius: number = 14;
  @Prop strong: boolean = false;
  @Prop paddingValue: number = 0;
  @Prop interactive: boolean = false;
  @State private pressed: boolean = false;
  @Builder
  emptyContent() {
  }
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  private sheen() {
    Column()
      .width('100%')
      .height('100%')
      .borderRadius(this.radius)
      .linearGradient({ angle: 135, colors: [[C.glass_highlight, 0], ['#00FFFFFF', 0.4], ['#00FFFFFF', 1]] })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.paddingValue)
    .backgroundEffect({ radius: this.strong ? 34 : 24, saturation: 1.6, brightness: 1.0,
      color: this.strong ? C.glass_strong : C.glass_fill })
    .borderRadius(this.radius)
    .border({ width: 1, color: C.glass_stroke })
    .clip(true)
    .shadow({ radius: this.strong ? 40 : 22, color: C.glass_shadow, offsetX: 0, offsetY: this.strong ? 16 : 8 })
    .overlay(this.sheen, { align: Alignment.Center })
    .scale({ x: this.interactive && this.pressed ? 0.985 : 1, y: this.interactive && this.pressed ? 0.985 : 1 })
    .animation({ duration: 180, curve: Curve.Friction })
    .onTouch((event: TouchEvent): void => {
      if (this.interactive) {
        this.pressed = event.type === TouchType.Down || event.type === TouchType.Move;
      }
    })
  }
}

// Small square status LED used for live/running/approval states.
@Component
export struct StatusLed {
  @Prop color: ResourceColor = C.success;
  @Prop pulse: boolean = false;
  @Prop ledSize: number = 5;
  @State private wave: number = 0;

  aboutToAppear(): void {
    if (!this.pulse) {
      return;
    }
    this.getUIContext().animateTo({ duration: 1500, iterations: -1, curve: Curve.EaseOut }, (): void => {
      this.wave = 1;
    });
  }

  build() {
    Stack() {
      if (this.pulse) {
        Circle()
          .width(this.ledSize)
          .height(this.ledSize)
          .fill(this.color)
          .opacity(0.34 * (1 - this.wave))
          .scale({ x: 1 + this.wave * 2.2, y: 1 + this.wave * 2.2 })
      }
      Rect().width(this.ledSize).height(this.ledSize).radius(1).fill(this.color)
    }
    .width(this.ledSize * 3)
    .height(this.ledSize * 3)
  }
}

