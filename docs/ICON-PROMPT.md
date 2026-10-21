# 图标生成记录

工具：内置 `image_gen`；全新生成，透明背景，不使用 CLI 或 API Key。输出为真实 Alpha 的 PNG，原图保存到项目的 AppScope 与 entry 资源目录，两个副本字节一致。

资源：

- `AppScope/resources/base/media/opencode_mark_v1.png`
- `entry/src/main/resources/base/media/opencode_mark_v1.png`

完整提示词：

> Use case: logo-brand. Asset type: an original production app icon foreground for a native HarmonyOS coding assistant called OpenCode Harmony. Generate exactly one isolated icon, square composition, genuinely transparent background. Subject: one calm, luminous, gently rounded-square glass tile in clean azure blue with a precise white terminal prompt chevron and short underscore embedded in the front face. A single softly folded glass edge gives modest optical depth and a small cool cyan refraction; nearly front facing, no dramatic isometric tilt. Refined modern native mobile software aesthetic, restrained like a first-party productivity app, light on ornament. Strong legible silhouette at 24px. Tile centered, occupying about 64 percent of the canvas width and height with generous completely transparent outer safe area. Keep all visible parts and any subtle soft shadow inside the central 74 percent. Soft studio illumination from upper left, realistic frosted translucent glass with a crisp terminal mark. Only the icon, no words, no letters, no extra badges, no sparkle stars, no particles, no background glow cloud, no device mockup, no surrounding UI. Do not include Huawei logos or copy any existing app logo. Deliver a polished high resolution PNG with true alpha transparency.

分层图标的背景是独立的简单 SVG，不对 PNG 像素进行二次处理。原模板图标文件保留。
