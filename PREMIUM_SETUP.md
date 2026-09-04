# Premium 订阅页接入状态

设置 → CleanFile Premium 打开独立订阅页。介绍现有媒体整理、授权文件清理、媒体压缩能力；使用现有主题、卡片与七种语言。App 启动时验证当前 StoreKit 权益：有效订阅进入主界面，无有效订阅则显示不可关闭的订阅页。

## 当前技术状态

`CleanMyIPhone/Features/Premium/PremiumConfiguration.swift` 已启用购买。页面使用原生 `SubscriptionStoreView`，由 StoreKit 加载本地化价格、周期、可用试用优惠，并提供购买和恢复入口。App 使用经过验证的当前权益和交易更新决定访问权限，不以安装日期计算试用。

已确认的 App Store Connect 标识：

- Bundle ID：`ZaneLiao.CleanPhone`
- Subscription Group ID：`22356442`
- 年度订阅 Product ID：`LZQ777`
- 月度订阅 Product ID：`LLL777`

## 提交与发布前必须完成

1. 在 App Store Connect 完成两个自动续期订阅的本地化、价格和审核信息，并为选定产品配置 3 天免费试用介绍优惠。
2. 提供公开可访问的 Privacy Policy URL 与 Terms of Service URL，并在 App Store Connect 和 App 元数据中完成法律信息。代码当前不以这两个 URL 阻止 StoreKit 技术流程。
3. 配置 StoreKit 测试及沙盒环境，验证首次订阅、试用资格、无试用资格、取消购买、购买失败、待批准、续订、过期、退款、撤销、恢复和跨设备权益。按项目规则，本地测试执行需用户另行授权。
4. 首个自动续期订阅必须随新的 App 版本一并提交审核；产品仍处于“准备提交”时不能视为生产环境可购买。

价格、试用时长和资格不写死到营销文案。免费试用不是所有用户都享有的优惠，不应仅凭本地标记判断。订阅页也不承诺尚未定义的“无限额度”。

## 验收

- 无有效订阅时，启动页显示不可关闭的订阅页；购买、恢复或重新验证为有效权益后进入主界面。
- 已有有效订阅时直接进入主界面；设置页入口仍可打开和关闭订阅管理页。
- 检查小屏、大字体、VoiceOver、浅色／深色／自定义主题与七种语言。
- 验证原生方案选择、真实本地化价格、3 天试用资格、恢复入口及法律链接。
- Build 只能证明编译，真机视觉效果和实际支付流程需要单独验收。
