# Credit Orb for macOS · 学分球（Mac版）

一个轻量的 macOS 桌面悬浮工具，显示 **Superfastcode 账户当前可用学分余额**。

**非官方开源项目，与 Superfastcode 无隶属或背书关系。仅限 Mac，暂不提供 Windows 版。**

## 功能

- **账户余额直读**：显示可用 Credits（学分），保留两位小数，不显示百分比。
- **桌面悬浮**：52pt 小球，置顶显示；按住左键拖动，松开后记住位置。
- **定时刷新**：默认30秒，可改为60秒，也可手动刷新。
- **菜单栏入口**：查看余额及更新时间、显示或隐藏小球、重置位置、退出。
- **独立登录**：使用官方网页登录自己的账号，无需填写 API Key。
- **状态可辨**：登录失效、连接失败或数据过期时不继续展示旧余额；历史值仅在菜单中明确标注。
- **浅色与深色**：跟随 macOS 系统外观。

## 系统要求

- 当前构建目标：**macOS 14及以上，Apple Silicon（M系列芯片）**。
- 已在 macOS 26.6.2 / Apple Silicon 本机验证编译、启动与账户余额读取；其他系统版本尚未完整验证。
- Intel Mac 与 Windows 暂不支持当前构建脚本。
- 自行构建需要 Apple Command Line Tools（包含 Swift 编译器）。

## 构建与使用

下载或克隆本仓库，在项目目录运行：

```sh
zsh test.sh
zsh build.sh
open dist/TokenOrb.app
```

1. 在独立窗口内登录自己的 Superfastcode 账号，优先使用邮箱验证码。
2. 等待自动刷新，小球显示账户余额。登录窗口可关闭，小球继续运行。
3. 按住小球拖动改变位置；单击或右击打开菜单。
4. 点击菜单栏入口可隐藏、重新显示小球或退出。

应用目前仅本地签名，**尚未经过 Apple Developer ID 签名及公证**；不保证下载后的二进制能在其他 Mac 上直接打开。推荐从审阅过的源码本机构建，无需关闭系统安全保护。

## 余额口径

当前读取官网控制台提供的 `account.credit_breakdown.available_cents`，除以100得到可用学分值。包含网站当前认定可用的套餐与充值额度，不包含尚未发放的套餐额度；并非剩余 Token 个数，也不是仅充值钱包余额。

读取接口：`GET https://api-direct.superfastcode.com/api/console/bootstrap`。这是网站目前使用的接口，不是本项目保证长期稳定的公开 API。字段或登录机制变化可能导致工具需要更新。

## 隐私

- 仅发布源码、测试与构建说明，不包含作者账号、Cookie、API Key、真实余额截图或本机配置。
- 登录会话保存在当前用户电脑的独立 WebKit 数据容器，由系统管理；不会附带在应用文件中。
- 监控逻辑只读取余额，不调用模型，不发送提示词，不读取 API Key 列表。
- 登录网页会按 Superfastcode 自身规则连接其服务；本项目不添加统计或上传余额的服务。
- 开源版使用独立的应用标识及数据容器，与作者自用版隔离。

## 源码导航与功能注释

| 文件 | 职责 |
|---|---|
| `Sources/App.swift` | 悬浮窗口、鼠标拖动、菜单、独立网页登录、刷新和错误状态 |
| `Sources/Quota.swift` | 官网数据校验和额度解析；保留额度计算结构，界面只展示可用余额 |
| `Tests/QuotaTests.swift` | 合成数据测试，不含真实账号数据 |
| `build.sh` | 编译 macOS ARM64 应用并本地签名 |
| `test.sh` | 运行额度解析测试 |

## 已知限制

- 无开机自启、后台系统服务或跨设备同步；退出应用后停止更新。
- 系统休眠和官网数据更新频率会影响刷新时效。
- 某些 OAuth 提供商可能限制内嵌网页登录，可尝试官网邮箱验证码。
- 拖动代码采用 macOS 原生窗口跟踪；多显示器及不同缩放比例需更多使用验证。
- 欢迎通过 Issues 报告问题；请不要提交验证码、Cookie、密钥或含私人信息的截图。

## 官网

- [Superfastcode 官网](https://superfastcode.com)
- [Superfastcode 账户余额](https://console.superfastcode.com/console/subscription-wallet)

## License

MIT License，见 [LICENSE](LICENSE)。Superfastcode 名称及商标属于相应权利人。
