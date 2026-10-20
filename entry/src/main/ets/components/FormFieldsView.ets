import { HarmonyColors as C } from '../presentation/HarmonyColors';
import { FormField, Choice, visibleFormFields } from '../domain/Core';

@Component
export struct FormFieldsView {
  @Prop fields: FormField[] = [];
  onChange: (key: string, value: string, multiple: boolean) => void = (): void => {};
  onOpenLink: (url: string) => void = (): void => {};
  build() {
    Column({ space: 12 }) {
      ForEach(visibleFormFields(this.fields), (field: FormField) => {
        Column({ space: 8 }) {
          Text(field.label + (field.required ? ' *' : '')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
          if (field.type === 'external') {
            Button('打开授权页面', { type: ButtonType.Normal }).fontSize(12).height(34).padding({ left: 14, right: 14 }).backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8).fontColor(C.text)
              .onClick(() => { this.onOpenLink(field.constraints?.url || ''); })
            Row({ space: 6 }) {
              Checkbox().select(field.text === 'true').selectedColor(C.accent).unselectedColor(C.muted).onChange((value: boolean) => { this.onChange(field.key, String(value), false); })
              Text('我已完成外部步骤').fontSize(12).fontColor(C.secondary)
            }
          } else if (field.type === 'boolean') {
            Toggle({ type: ToggleType.Switch, isOn: field.text === 'true' }).selectedColor(C.accent)
              .onChange((value: boolean) => { this.onChange(field.key, String(value), false); })
          } else {
            ForEach(field.options, (choice: Choice) => {
              Row({ space: 8 }) {
                if (field.type === 'multiselect') {
                  Checkbox().id('choice-' + field.key + '-' + choice.value).select(field.values.indexOf(choice.value) >= 0)
                    .selectedColor(C.accent).unselectedColor(C.muted)
                    .onChange(() => { this.onChange(field.key, choice.value, true); })
                } else {
                  Radio({ value: choice.value, group: field.key }).id('choice-' + field.key + '-' + choice.value)
                    .checked(field.text === choice.value).radioStyle({ checkedBackgroundColor: C.accent, uncheckedBorderColor: C.muted })
                    .onChange((checked: boolean) => { if (checked) { this.onChange(field.key, choice.value, false); } })
                }
                Column({ space: 3 }) {
                  Text(choice.label).fontSize(12.5).fontColor(C.text)
                  if (choice.description) { Text(choice.description).fontSize(10.5).fontColor(C.muted) }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  .onClick(() => { this.onChange(field.key, choice.value, field.type === 'multiselect'); })
              }.width('100%')
            }, (choice: Choice) => choice.value)
            if (field.type !== 'multiselect' && (!field.options.length || field.constraints?.custom)) {
              TextInput({ placeholder: field.options.length ? '或输入自定义回答' : '请输入', text: field.text }).id('field-' + field.key)
                .type(/key|token|password|secret/i.test(field.key) ? InputType.Password : field.type === 'number' ? InputType.Number : InputType.Normal)
                .fontSize(12.5).fontColor(C.text).placeholderColor(C.muted).height(34).padding({ left: 10, right: 10 })
                .backgroundColor(C.field).borderRadius(8).onChange((value: string) => { this.onChange(field.key, value, false); })
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (field: FormField) => field.key)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
