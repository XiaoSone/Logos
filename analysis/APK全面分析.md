# 微读圣经 7.6.1 分析与 Logos 重实现依据

分析日期：2026-10-16。输入为工作区提供的单个 APK。原文件未修改。

本报告将**直接观察**、**静态推导**和**未验证**分开。它覆盖安装包、清单、签名、DEX、资源、业务接口、原生库、页面与功能结构、运行限制和重实现范围；不声称已经还原全部原生算法、服务端实现或联网业务。

## 1. 目标身份与可复现性

| 项目 | 直接观察 |
|---|---|
| 文件 | `wdbible_website_7_6_1.apk` |
| 字节数 | 107,989,063 |
| SHA-256 | `02e6c38b89b9ad3ff2c19fd826909f5ab73ccb9c81c29011dcad8c9c508f151d` |
| applicationId | `com.aquila.bible` |
| 应用标签 | `WeDevote` |
| versionName / versionCode | `7.6.1` / `255` |
| minSdk / targetSdk | 23 / 35 |
| 入口 | `com.wdbible.app.wedevotebible.base.LoadingActivity` |
| ZIP 条目 | 4,499 |
| DEX | 5 个 |
| 原始 DEX 类 | 37,988，含内部类及第三方代码 |
| 业务应用命名空间类 | 4,195 |
| `businesslayer` 接口命名空间类 | 168 |
| 解码布局 | 529 个 |
| Native ABI | `arm64-v8a`、`armeabi-v7a` |
| Native 库 | 每 ABI 8 个，共 16 个 |

证据：[`raw/package.json`](raw/package.json)、[`raw/archive.json`](raw/archive.json)、[`raw/classes.json`](raw/classes.json)、[`raw/summary.json`](raw/summary.json)。

### 签名

使用 Android SDK `apksigner verify --verbose --print-certs`，v1、v2、v3 校验通过；v3.1/v4 不存在。单签名证书 SHA-256：

`8e6906ea588a68ff1256d85d092fa4a6922348e95e785814928365d93e01fcfe`

证书使用 RSA 1024 位公钥；工具另报告部分 META-INF 条目未受签名保护。这些是工具输出事实，**不能据此证明 APK 来自官方分发渠道，也不等同于已验证的可利用漏洞**。

完整输出：[`raw/signature-verification.txt`](raw/signature-verification.txt)。

## 2. 对 REA 仓库的阅读与实际使用

来源：<https://github.com/morluto/rea>，本地研究快照提交：

`fe2a398dd9ab290ba6cb3411403d319cec8d07a2`

研究时 package 版本为 `rea-agents 6.5.0`，MIT。源码保留在 `tools/rea/`，作为独立工具目录忽略，不并入 Logos 产品源码。

重点阅读了 README、AGENTS.md、Android/JADX 分析指南、CLI 指南、安装指南、Apktool 指南、架构图及 Android CLI/配置边界代码。REA 的主要价值是将工具输出封装成带目标哈希、操作参数、引擎版本、来源和限制的 Evidence，CLI 与 MCP 共享工作流。它本身并不自动生成一个完整可用的竞品克隆。

与本任务直接相关的调用路径为：

```text
scripts/rea.mjs
  → CLI / src/cli/androidCommands.ts
  → AndroidAnalysisService
  → JADX provider / owned Java process
  → ReaJadxBridge.java
  → 固定版本 jadx-headless-mcp
  → normalized_result + raw_result + limitations
```

使用固定版本 `jadx-headless-mcp 0.7.1`，JAR SHA-256 已与 REA 发布元数据核对：

`6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75`

实际运行并保留：

| 操作 | 原始 Evidence |
|---|---|
| APK 清单与包信息 | [`raw/rea-package.json`](raw/rea-package.json) |
| 阅读 Activity 成员与字段 | [`raw/rea-reader-class.json`](raw/rea-reader-class.json) |
| 阅读页 `onCreate` 方法反编译 | [`raw/rea-reader-oncreate.json`](raw/rea-reader-oncreate.json) |
| `BibleBl` 业务接口 | [`raw/rea-biblebl.json`](raw/rea-biblebl.json) |

JADX 报告的加载类计数为 20,654；Androguard 的 37,988 是原始 DEX 类定义口径。两种工具对内部类/视图表示的口径不同，不应把差值解读为“漏掉了 17,334 个业务功能”。

补充工具链为 Androguard（清单、ARSC、DEX）、pyelftools（ELF 结构与动态符号）、Android SDK apksigner/ADB。没有注册全局 REA MCP，也没有改动用户现有代理配置。

## 3. 客户端架构还原

### 可直接观察的结构

- 主体为 Android View/XML 页面；搜索布局同时出现 `ComposeView`，属于 View 与局部 Compose 混合结构。
- 存在大量 Kotlin、协程、序列化、Ktor/HTTP 相关类型和字符串。
- Java/Kotlin UI 经 `com.wdbible.app.lib.businesslayer` 接口访问核心业务；存在 `CppProxy` 类。
- 原生库中包括 `libbusinesslayer_jni.so`、`librealmc.so`、`libsqlcipher.so`。
- 存在 Realm/KRDB 类型、Room 服务与 WorkManager 清单组件。
- 不存在 Flutter 的标准 `libflutter.so` / `libapp.so` 结构；本 APK 并非本次 Logos 所选的 Flutter 技术栈。

### 静态推导

可合理推导为“Android 页面层＋JNI 业务层＋本地内容/个人数据存储＋网络资源服务”的多层客户端。`BibleBl` 的抽象方法和 `CppProxy` 说明至少一部分关键读经/搜索逻辑进入 Native 边界。

Realm、SQLCipher 与 Room 共存，**不能仅凭打包库断定它们分别存哪一类用户数据**。没有原应用私有数据快照，也没有还原完整数据库 Schema。

业务模块类计数（包括内部生成类，不能当作代码行数）：

| 模块 | 类数 |
|---|---:|
| model | 3,092 |
| user | 190 |
| groups | 129 |
| devotion | 115 |
| tools | 98 |
| bible | 95 |
| network | 90 |
| plan | 77 |
| ui | 71 |
| audio | 52 |
| snparsing | 50 |
| analytics | 46 |

证据：[`raw/app-modules.json`](raw/app-modules.json)、[`raw/business-interfaces.json`](raw/business-interfaces.json)。

## 4. 页面导航与核心交互

清单共有 149 个 Activity、16 个 Service、13 个 Receiver、4 个 Provider。这包含第三方 SDK 的组件；不能声称 149 个 Activity 全是微读自有页面。

### 首页

`HomeMainActivity` 对应 `activity_home_main_layout.xml`，使用自定义 `HomeBottomNavigationLayout`、内容容器与底部四入口。

读经首页 `fragment_home_bible_layout.xml` 包含 RecyclerView、音频栏和版本更新提示。原生 XML 是静态骨架，实际卡片内容、排序和首屏状态依赖运行数据，**没有从布局中推断精确卡片文案与顺序**。

### 读经

关键证据文件：

- [`raw/layouts-resolved/res__layout__activity_bible_read.xml`](raw/layouts-resolved/res__layout__activity_bible_read.xml)
- [`raw/layouts-resolved/res__layout__tools_bible_read_tool_layout.xml`](raw/layouts-resolved/res__layout__tools_bible_read_tool_layout.xml)
- [`raw/rea-reader-oncreate.json`](raw/rea-reader-oncreate.json)

直接观察：

1. 使用 `BibleViewPager` 承载按章阅读。
2. 横向滚动工具栏含 7 个工具项；布局工具文字约 10sp，图标约 30dp，单项最小宽约 60dp。
3. 独立 `ToolBibleReadLayout` 承载工具层。
4. 初始化方法获取当前译本资源 ID，读取 `fromSearch`、`lockToolBar`、`planEntity` 等入口状态。
5. 初始化中设置工具栏译本显示、监听器、阅读来源，以及屏幕唤醒相关对象。

重实现由 Flutter `PageView`、按节列表、节号、长按多选、底部工具条、收藏/高亮/笔记菜单与可定位滚动组成。

### 圣经目录

原 `BibleCatalogActivity` 以及 `activity_bible_index_layout.xml`、`pager_adapter_bible_index_book_layout.xml` 支撑书卷导航。Logos 按架构方案实现“书卷—章—节”三级状态，66 卷维护清单独立来自公共领域文本导入工具。

### 搜索

原 `SearchActivity` / `activity_search_layout.xml` 包含搜索输入、类型/范围控制、列表结果、历史容器与局部 ComposeView。

`BibleBl` 提供：

```text
buildBibleFtsDb(...)
buildBibleLikeSearchDb(...)
createSearchDb(...)
initSearchEngine(...)
needCreateSearchDb(...)
getSearchCount(..., SearchType)
getSearchResult(..., SearchType, int)
```

可直接确认本地搜索数据库构建和搜索类型接口存在。**原版排序、模糊算法、FTS 分词、召回口径未通过 Native 反编译或运行抓取确认**。

Logos 按方案明确采用连续子串匹配；服务端 `ILIKE`＋pg_trgm，客户端同口径本地匹配；经文引用先解析。不会将关键词搜索伪装成语义检索。

### 笔记与收藏

原 `NoteActivity`、`NoteEditActivity`、`NoteSearchActivity`、`NoteAddVersesActivity`、`HighlightActivity`、`HighlightSearchActivity`、`FavoriteActivity` 等页面完整存在。

`activity_note_write_layout.xml` 显示标题、引用列表和正文三段结构，标题输入限制 60，正文 50,000；Logos 按自身方案采用标题最多 200 字，正文 50,000 字，多节引用与标签分组。

### 计划、音频、灵修与社交

Activity 清单显示个人/自定义/群组计划、日历、统计、补读；音频播放器、专辑和下载；每日经文/灵粮、文章/音视频；群组创建、成员、邀请、动态、反思、转让/删除。

这些功能均进入分析矩阵。实现范围以 Logos 文档为准：计划 Phase 1.5，AI 与知识图谱 Phase 2；群组社交、内容订阅平台和付费运营功能不进入 Logos 当前产品。

## 5. 数据与资源层

APK assets 包含 CSS、若干第三方 JSON/证书、原文/拉丁字体、语言识别模型和公钥。**未发现以普通 SQLite/JSON/USFM 形式明文内置的整本圣经**。不能把“未发现明文库”推导为“没有任何嵌入内容”，也未尝试绕过原 App 的内容授权或加密。

因此 Logos 从 eBible 独立获取公有领域 CUVs，不从 APK 提取正文、付费译本、注释、图片、字体或录音。

### Native 结构

| ARM64 库 | 导出动态符号数 | 解释边界 |
|---|---:|---|
| libbusinesslayer_jni.so | 414 | JNI/业务边界；并未还原全部实现 |
| librealmc.so | 902 | Realm 核心组件 |
| libsqlcipher.so | 485 | SQLCipher 组件存在，不等于已取得数据库或密钥 |
| libjnidispatch.so | 153 | JNA 调用支持 |
| libnative_ffi.so | 66 | 原生 FFI 支持，具体业务用途未验证 |
| liblanguage_id_l2c_jni.so | 5 | 与语言识别组件一致 |
| libandroidx.graphics.path.so | 1 | AndroidX 图形支持 |
| libfox.so | 8 | 名称与符号不足以断定用途，保留未知 |

ELF 依赖和完整导出列表：[`raw/native-analysis.json`](raw/native-analysis.json)。本次未安装 Ghidra/IDA/Hopper，因此 Native 只做结构与符号层分析，不声称完成原生算法反编译。

## 6. 网络与外部依赖

DEX 静态字符串出现 `api.wedevote.us`、`auth.wedevote.us`、测试 API 域、CDN/资源域、Firebase、Stripe、Braintree、PayPal 等地址。字符串存在只说明安装包包含该值，不证明每次启动都会请求，也不证明当前仍可用。

GraphQL 配置/客户端相关字符串存在，但本次没有恢复完整 operation 集、服务端 Schema、认证协议或实时响应。Logos 的 GraphQL Schema 按《技术架构方案》独立定义，**不连接微读的私有接口**。

第三方组件证据包括 Firebase Messaging/Auth/Analytics/Crashlytics、媒体播放、Stripe/Braintree/PayPal、ML Kit、WorkManager、Room、Realm/KRDB。存在库不等于证明其运行采集行为。Logos 当前未引入这些分析、广告或支付 SDK。

证据：[`raw/urls.json`](raw/urls.json)、[`raw/dex-strings.json`](raw/dex-strings.json)、[`raw/manifest-components.json`](raw/manifest-components.json)。没有主动探测原 App 服务端。

## 7. 权限与平台能力

共 24 项权限声明，主要包括网络状态、INTERNET、通知、媒体前台服务、唤醒、相机、READ_PHONE_STATE、安装/删除包请求和广播、广告相关权限等。

- 音频前台服务和耳机接收器与音频模块相符。
- 相机权限与 CaptureActivity/扫码组件相符。
- 安装相关权限与站外 APK 更新能力相符。
- 广告/归因权限可由第三方 SDK 合并；**本次未证明原应用展示广告或读取某项个人数据**。
- exported、permission 与 intent-filter 的逐项表保留在组件证据文件，未把清单声明当作实际可达漏洞。

Logos 实际合并后的 APK 声明 INTERNET、ACCESS_NETWORK_STATE，以及 AndroidX 使用的应用内动态接收器签名权限；不需要相机、电话、位置、通讯录或存储权限。应用私有数据关闭 Android 自动备份。远程服务使用 HTTPS；开发明文例外仅限 localhost、127.0.0.1、10.0.2.2。

## 8. 动态分析的实际结果

环境：Windows x64 Android Emulator，Google APIs Android 11 / API 30 x86_64，支持 ARM 翻译，WHPX 可用。

1. 原 APK 安装成功。
2. 默认 ARM64 路径在 `libbusinesslayer_jni.so` 的 `JNI_OnLoad` 失败，抛出 `UnsatisfiedLinkError`。
3. 强制 ARM32 安装后，启动时 `libndk_translation.so` 中发生 SIGSEGV。
4. 未进入原 App 首页，未建立已登录会话，没有成功的原版阅读、搜索或计划运行截图。

保存证据：[`raw/original-crash.log`](raw/original-crash.log)。`screenshots/wedev-initial.png` 仅是失败后的模拟器桌面，不作为原 App 截图使用。

这不能证明原 App 在 ARM 真机有同样问题，也不能判断其是否主动检测模拟器。原版实际文案、动画、首屏网络、弱网行为、账号同步与支付流程仍需 ARM 真机补测。

## 9. Logos 的复刻结果与取舍

本次结果是**独立实现的核心体验版本和 Logos 第一阶段项目底座**，不是原 APK 的重打包，也不是所有 149 个 Activity 的等价替代。

已实现的交互：四 Tab（首页/计划占位/个人记录/我的）、每日经文、继续阅读、三级目录、章节翻页、指定节定位、正文/节号/小标题、脚注查看、字号/行距/夜间模式、关键词与引用搜索、范围筛选、结果跳转、历史搜索、多选复制、系统文本分享、收藏、高亮、笔记 CRUD、多节引用、标签、个人 Feed 筛选与跳转、阅读历史、加密离线下载、清缓存、关于和开发账号入口。

产品资源独立制作；品牌为 Logos，视觉采用自己的纸色/森林绿，交互骨架参考原布局。由于原 App 动态启动失败，**不称为像素级复刻**。

逐项状态与尚未完成项见 [`../docs/功能对照与架构差距.md`](../docs/功能对照与架构差距.md)。实际构建与验证见 [`../docs/验收记录.md`](../docs/验收记录.md)。

## 10. 重跑分析

```powershell
.tools/venv/Scripts/python tools/analyze_apk.py
.tools/venv/Scripts/python tools/summarize_apk.py
$env:JAVA_HOME = (Resolve-Path .tools/jdk21/jdk21.0.12_12).Path
$env:REA_JADX_MCP_JAR = (Resolve-Path .tools/downloads/jadx-headless.jar).Path
npm exec --yes --package rea-agents@6.5.0 -- rea inspect-android-package (Resolve-Path wdbible_website_7_6_1.apk).Path --format json
```

重新分析前保留输入哈希，固定工具版本。原始证据量较大，默认不进入版本控制；报告与重跑脚本进入项目。
