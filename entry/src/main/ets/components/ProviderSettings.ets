import { ProviderStore, Integration, AuthMethod, Account, CustomProvider } from '../presentation/ProviderStore';
import { FormFieldsView } from './FormFieldsView';

@Component
export struct ProviderSettings {
  @ObjectLink store: ProviderStore;
  onOpenLink: (url: string) => void = (): void => {};
  @Builder
  cardTitle(title: string) { Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#274A35').width('100%') }
  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Text('模型与接入').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#274A35').layoutWeight(1)
          Button('刷新', { type: ButtonType.Normal }).id('providers-refresh').fontSize(12).backgroundColor('#E1EBDE').fontColor('#385E3B')
            .enabled(!this.store.busy).onClick(() => { this.store.load(); })
        }.width('100%')
        Text('凭据保存在当前服务器。账号与渠道设置作用于本实例全部项目，任务和待办处理完后再修改。')
          .fontSize(12).fontColor('#7A8B70').width('100%')
        if (this.store.error) { Text(this.store.error).fontSize(12).fontColor('#A35C49').width('100%') }
        if (this.store.notice) { Text(this.store.notice).fontSize(12).fontColor('#3B774C').width('100%') }
        TextInput({ placeholder: '搜索 DeepSeek、MiMo、OpenAI 或其他提供商', text: this.store.search }).id('provider-search')
          .fontSize(13).backgroundColor(Color.White).onChange((value: string) => { this.store.search = value; })
        Text('已发现 ' + this.store.entries.length + ' 个接入入口；输入名称搜索全部。').fontSize(11).fontColor('#899880').width('100%')
        ForEach(this.store.filtered(), (entry: Integration) => {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text(entry.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#33553B')
              Text(entry.id).fontSize(10).fontColor('#87957E')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text(entry.accounts.length ? entry.accounts.length + ' 个连接' : '连接').fontSize(12).fontColor('#618459')
          }.id('provider-' + entry.id).width('100%').padding(15)
            .backgroundColor(this.store.selected === entry.id ? '#E0ECDD' : Color.White).borderRadius(12)
            .onClick(() => { if (!this.store.busy) { this.store.select(entry); } })
        }, (entry: Integration) => entry.id + entry.name + entry.accounts.length)
        if (this.store.current()) {
          Column({ space: 12 }) {
            this.cardTitle(this.store.current()?.name || '提供商')
            ForEach(this.store.current()?.accounts || [], (account: Account) => {
              Column({ space: 6 }) {
                Text(account.label + (account.active ? ' · 当前使用' : '')).fontSize(14).fontColor('#325D3B').width('100%')
                if (account.type === 'credential') {
                  Row({ space: 8 }) {
                    Button('启用', { type: ButtonType.Normal }).fontSize(11).enabled(!this.store.busy && !account.active)
                      .onClick(() => { this.store.account(account, 'activate'); })
                    Button('按下方名称改名', { type: ButtonType.Normal }).fontSize(11).enabled(!this.store.busy)
                      .onClick(() => { this.store.account(account, 'rename'); })
                    Button('删除', { type: ButtonType.Normal }).fontSize(11).enabled(!this.store.busy)
                      .onClick(() => { this.getUIContext().showAlertDialog({ title: '删除此账号？', message: '仅删除服务器上这个账号的凭据。',
                        primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '删除', action: (): void => { this.store.account(account, 'delete'); } } }); })
                  }
                } else { Text('环境变量由服务器管理').fontSize(11).fontColor('#899680') }
              }.padding(10).backgroundColor('#F0F5EB').borderRadius(8).width('100%')
            }, (account: Account) => account.id + account.label + account.type + account.method + String(account.active))
            TextInput({ placeholder: '账号名称（可选，也用于改名）', text: this.store.label }).id('provider-label')
              .fontSize(13).backgroundColor('#F1F5EB').onChange((value: string) => { this.store.label = value; })
            ForEach(this.store.current()?.methods || [], (method: AuthMethod) => {
              Button(method.label + (method.supported ? '' : method.id === 'chatgpt-browser' ? '（请选择设备码授权）' : '（服务器配置）'), { type: ButtonType.Normal })
                .id('auth-method-' + method.id).fontSize(12).width('100%').backgroundColor(this.store.methodID === method.id ? '#DDEBDD' : '#EEF3E8')
                .fontColor('#476A46').enabled(method.supported && !this.store.busy && !this.store.attemptID)
                .onClick(() => { this.store.choose(method); })
            }, (method: AuthMethod) => method.id)
            if (this.store.methodType && !this.store.attemptID) {
              if (this.store.methodType === 'key') {
                TextInput({ placeholder: 'API Key（仅提交到当前服务器）', text: this.store.key }).id('provider-key').type(InputType.Password)
                  .fontSize(13).onChange((value: string) => { this.store.key = value; })
              }
              FormFieldsView({ fields: this.store.fields,
                onChange: (key: string, value: string, multiple: boolean): void => { this.store.field(key, value, multiple); },
                onOpenLink: (url: string): void => { this.onOpenLink(url); } })
              Button(this.store.busy ? '提交中…' : this.store.methodType === 'oauth' ? '开始授权' : '保存连接', { type: ButtonType.Normal })
                .id('provider-connect').width('100%').backgroundColor('#215D43').fontColor(Color.White).enabled(!this.store.busy)
                .onClick(() => { this.store.connect(); })
            }
            if (this.store.attemptID) {
              Text(this.store.instructions || '请在浏览器中完成授权，再返回此处。').fontSize(13).copyOption(CopyOptions.InApp).width('100%')
              Button('打开授权页面', { type: ButtonType.Normal }).id('oauth-open').fontSize(13)
                .onClick(() => { this.onOpenLink(this.store.authURL); })
              if (this.store.authMode === 'code') {
                TextInput({ placeholder: '粘贴授权码', text: this.store.code }).id('oauth-code').type(InputType.Password)
                  .onChange((value: string) => { this.store.code = value; })
                Button('提交授权码', { type: ButtonType.Normal }).enabled(!this.store.busy).onClick(() => { this.store.complete(); })
              }
              Row({ space: 10 }) {
                Button('检查状态', { type: ButtonType.Normal }).onClick(() => { this.store.poll(); })
                Button('取消授权', { type: ButtonType.Normal }).onClick(() => { this.store.cancel(); })
              }
            }
          }.padding(16).width('100%').backgroundColor(Color.White).borderRadius(14)
        }
        Column({ space: 12 }) {
          this.cardTitle('自定义兼容渠道')
          if (!this.store.customAvailable) {
            Text('此服务器未启用手机端自定义渠道设置接口；内置提供商仍可连接。').fontSize(12).fontColor('#8A937D').width('100%')
          } else {
            ForEach(this.store.custom, (provider: CustomProvider) => {
              Button(provider.name + (provider.hasKey ? ' · 已保存密钥' : ''), { type: ButtonType.Normal }).fontSize(13).width('100%')
                .onClick(() => { this.store.editCustom(provider); })
            }, (provider: CustomProvider) => provider.id + provider.name + provider.baseURL + provider.models.join(',') + String(provider.hasKey))
            TextInput({ placeholder: '渠道 ID，例如 mobile-my-api', text: this.store.customID }).id('custom-id').fontSize(13)
              .onChange((value: string) => { this.store.customID = value; })
            TextInput({ placeholder: '显示名称', text: this.store.customName }).id('custom-name').fontSize(13)
              .onChange((value: string) => { this.store.customName = value; })
            TextInput({ placeholder: 'https://api.example.com/v1', text: this.store.customURL }).id('custom-url').fontSize(13)
              .onChange((value: string) => { this.store.customURL = value; })
            TextArea({ placeholder: '模型 ID，每行一个，例如 deepseek-chat', text: this.store.customModels }).id('custom-models').height(100).fontSize(13)
              .onChange((value: string) => { this.store.customModels = value; })
            TextInput({ placeholder: 'API Key（编辑时留空保留）', text: this.store.customKey }).id('custom-key').type(InputType.Password).fontSize(13)
              .onChange((value: string) => { this.store.customKey = value; })
            Row({ space: 8 }) {
              Button('保存渠道', { type: ButtonType.Normal }).id('custom-save').layoutWeight(1).backgroundColor('#215D43').fontColor(Color.White)
                .enabled(!this.store.busy).onClick(() => { this.store.saveCustom(); })
              Button('删除此渠道', { type: ButtonType.Normal }).fontSize(12).enabled(!this.store.busy)
                .onClick(() => { this.getUIContext().showAlertDialog({ title: '删除自定义渠道？', message: '使用该渠道的会话需重新选择模型。',
                  primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '删除', action: (): void => { this.store.saveCustom(true); } } }); })
            }.width('100%')
          }
        }.padding(16).backgroundColor(Color.White).borderRadius(14).width('100%')
      }.padding(18).width('100%')
    }.layoutWeight(1).scrollBar(BarState.Off)
  }
}
