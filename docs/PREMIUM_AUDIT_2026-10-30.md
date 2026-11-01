# Premium 订阅机制审查（2026-10-30）

## 结论和验证边界

本次按“完整检查”进行代码审查，没有修改订阅逻辑或商业权限边界。

没有发现清理文件、清除转换记录、重置界面偏好会主动删除 StoreKit 购买记录的代码。商品 ID 和订阅组在代码与仓库 StoreKit 配置中一致；不能据此证明 App Store Connect 的线上配置、真实订单、退款和跨设备恢复均正常。

发现两处可以从代码明确推导的异常状态处理问题，以及两处状态更新/恢复风险。它们会影响“已购买是否正确解锁”和“已失效是否正确收回”，不能把当前机制评价为无 Bug。

App 与测试 target 编译通过：`/tmp/CleanFile-PremiumAudit-testcompile.log`，末尾为 `TEST BUILD SUCCEEDED`。本轮未运行本地测试，未启动模拟器、Docker、购买、恢复或退款操作，也未执行真实 App Store 验证。GitHub Actions 未触发。

## 发现

### P1：已确认失效仍可能因状态查询错误保留 Premium

位置：`CleanMyIPhone/Features/Premium/PremiumEntitlementStore.swift`，`listenForTransactionUpdates()` 与 `refreshEntitlements(revisionAtStart:)`。

条件：已有 `.entitled`；收到已验证的撤销/失效交易；刷新时没有任何有效 currentEntitlements 或 latest 交易；订阅状态查询抛错。

当前路径：监听器的无效交易分支仅增加 revision 并刷新；最终 `subscriptionStatus == nil`，而刷新明确保留已有 `.entitled`。已经收到的负面证据没有参与最终决策。因此退款、撤销或失效可能直到一次成功刷新才收回权限。`restore()` 也可能因沿用该状态而返回成功。

修复方向：区分“没有收到撤销证据的临时离线”与“已验证的权益撤销”，按具体商品/交易处理负面证据。仍有另一份有效订阅或终身购买时不能一并锁定。

### P1：未通过验证被折叠为“确认未订阅”

位置：同文件 `hasActiveSubscriptionStatus()` 和刷新末尾。

条件：没有可用的已验证 currentEntitlements/latest，状态请求本身返回成功，但相关状态的 transaction 为 `.unverified`。

当前路径：`statuses.contains` 对未验证状态返回 false，随后设置 `.notEntitled` 并清除 verificationUnavailable。界面将其当作确认没有权益，解锁入口可能重新显示购买按钮，而不是提示验证失败/重试。

修复方向：状态证据至少保留“有效 / 确认无效 / 无法验证”三类；任何有效商品可以授予访问；无法验证不能伪装成确认过期，也不能用于授予新权限。

### P2：前台持续使用时缺少订阅状态变更监听

位置：同文件 `start()`、`listenForTransactionUpdates()`；`PremiumAccessRootView.swift` 的 scenePhase task。

当前监听 Transaction.updates，并在重新激活场景时刷新；没有监听 Product.SubscriptionInfo.Status.updates，也没有到期复查调度。若只有订阅状态/宽限期变化而没有可处理的新交易事件，App 一直处于前台时不会主动重查。实际延迟需要 StoreKit 集成测试验证，不能仅凭代码声称每次过期必然漏掉。

修复方向：补充订阅状态更新监听，沿用现有合并刷新及 revision 防旧结果覆盖机制；取消自动续费不能立即锁定，宽限期必须保留访问。

### P2：启动核验超时仅改变提示，不解除挂起查询

位置：同文件 `markStartupVerificationDelayed()`、`refresh()`。

三秒超时只设置 verificationUnavailable；原 refreshTask 继续占用。若底层 StoreKit 查询长期不返回，重试及再次进入前台仍等待同一任务，付费功能可长期停留 checking，购买也被有意禁止。并非证明 StoreKit 必然挂起，而是当前应用没有有限的恢复边界。

修复方向：为查询恢复建立明确的超时/代次策略，防止晚到结果覆盖较新的购买结果；不能用超时直接判为未订阅。

## 已核对的正常设计

| 链路 | 代码结论 |
| --- | --- |
| 商品身份 | 年付 LZQ777、月付 LLL777、终身 filecleaner.lifetime；组 22356442 与仓库配置一致 |
| 试用 | 月付/年付配置为一周；展示前查询 StoreKit 资格，不自行推断免费试用 |
| 新购买 | 只接受 verified；检查商品、产品类型、撤销、升级、到期；先解锁再 finish |
| 取消/待批准 | 不凭 pending、userCancelled 授予 Premium；待批准文案存在 |
| 终身购买 | nonConsumable，不施加订阅到期时间判断 |
| 自动续费取消 | 不根据 willAutoRenew=false 立即收回已付费期间权益 |
| 重启恢复 | 查询 currentEntitlements，再查 latest 和订阅组状态，不依赖 UserDefaults 付费布尔值 |
| 宽限期 | currentEntitlements 路径不按过期时间简单拒绝；状态路径接受 inGracePeriod |
| 手动恢复 | 只有用户点击恢复调用 AppStore.sync；仍需改善上述负面证据/未知状态处理 |
| 购买并发 | 同一购买 ViewModel 的购买/恢复互斥；商品加载有代次检查和重试取消 |
| 刷新竞态 | refreshTask 合并查询，交易事件递增 revision，旧结果不能直接覆盖新购买 |
| 功能入口 | 快速清理与存储执行前再次检查权限；图片/音频转换通过 usagePolicy 预约批次检查权限；视频保持既有免费定义 |
| 外观 | 过期隐藏付费外观，但保留用户偏好，恢复订阅可恢复外观 |
| 入口 Premium | 开屏完成后、已确认免费才展示；同一进程不会因熄屏/亮屏反复弹出；可以关闭 |
| 正式版绕过 | UI 测试权益绕过包在 DEBUG 中；无看到 Release 用户偏好解锁后门 |

Apple 文档确认 currentEntitlements 包含 subscribed / inGracePeriod，不能仅因 transaction.expirationDate 已过就撤销宽限期访问：
https://developer.apple.com/documentation/storekit/transaction/currententitlements

状态与交易监听资料：
https://developer.apple.com/documentation/storekit/product/subscriptioninfo/status/updates
https://developer.apple.com/documentation/storekit/transaction/updates

## 测试覆盖与未验证范围

已阅读 PremiumStatusFailureTests、PremiumPurchaseViewModelTests、PremiumFeatureAccessTests 和 PremiumFreeTierUITests。现有测试源码覆盖试用、确认过期、宽限期离线、终身/订阅重建权益、区域/本地偏好变化、商品缺失、产品加载竞态、免费权限矩阵与部分执行检查。本轮只编译这些测试，未声称通过执行。

缺少针对上述发现的明确回归：撤销与查询异常同时发生、未验证状态结果、前台宽限期结束、长期挂起核验恢复；以及真实 Sandbox 的 Ask to Buy 延迟、AppStore.sync 恢复、跨设备、账户切换和退款验证。

要声称线上不会丢失/失效，仍需运行 StoreKit 集成测试并在 App Store Sandbox 验证。编译通过无法代替这些结果。

## 2026-10-31：P1 修复

- 记录实际授予访问的已验证交易。收到该交易或同商品更新交易的已验证失效证据时，先移除旧访问依据，再查询其他商品；状态查询失败不会继续沿用已撤销的 Premium。
- 已退款/升级交易按交易 ID 排除，防止旧快照再次授予权益；旧交易的退款不会直接撤销另一份有效购买。宽限期仍由 currentEntitlements / inGracePeriod 授权。
- currentEntitlements、latest 和订阅状态中的未验证结果保留为未知。如果没有其他有效证据，则进入 checking 并标记 verificationUnavailable，而不是判定未订阅或开放再次购买。
- 查询抛错与签名验证失败分别处理；普通查询错误本身不代表已购买权益失效。状态查询返回后继续检查 revision，避免旧结果覆盖新交易。
- 新增 Swift Testing 回归源码：未验证状态（含 expired/revoked）、终身退款与查询失败同时发生、退款后另一有效订阅保留、重复刷新不恢复已撤销购买。
- Build / 测试 target 编译：Passed（`/tmp/CleanFile-PremiumP1-build.log`，TEST BUILD SUCCEEDED）。Tests：未在本地执行；GitHub Actions：待验证。未进行真实购买或退款。
- P2 的前台订阅状态监听和长期挂起查询恢复仍未修改。

### 验证失败的含义

StoreKit 的 VerificationResult.unverified 表示不能确认签名数据可信，不等同于付款失败、未购买、订阅过期或退款。Apple 列出的错误包括：证书链无效、证书被撤销、签名不匹配、编码错误、缺少必需字段、当前设备校验不匹配。这里的“证书撤销”也不同于“订单退款”。

这些结果可能在购买回调、启动权益枚举、最新交易查询、恢复购买后的核验和交易/订阅状态更新中出现。具体原因必须以实际 VerificationError 为依据；本次审查没有证据证明线上用户已经遇到其中某一原因。断网/超时造成状态请求抛错是另一条失败路径，不能一概称为签名验证失败。

Apple 官方说明：https://developer.apple.com/documentation/storekit/verificationresult/verificationerror
