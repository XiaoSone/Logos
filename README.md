# Logos · 话语之间

以《Logos-技术架构方案》v1.1 为蓝图，从微读圣经 7.6.1 的静态结构独立实现的圣经学习 App 与项目底座。

当前可运行的核心：66 卷读经、卷章节目录、翻章与定位、引用/关键词搜索、每日经文、收藏/高亮、笔记与标签、我的分享、阅读历史、主题/字号/行距、设备加密离线下载，以及开发账号的独立缓存、游客合并与同步。客户端使用 Flutter / Riverpod / go_router / Drift；后端使用 Java 21 / Spring Boot 3 / GraphQL / PostgreSQL。

这是 Phase 1 **开发版**。已接通开发账号的登录合并、账号隔离、离线队列与云端缓存；正式短信、refreshToken/服务端会话撤销、Redis 治理、生产证书与签名尚未完成。计划按原方案留在 Phase 1.5，AI/图谱在 Phase 2。完整差距见下方清单。

本次已构建的 Android 安装包：[Logos 0.1.0 构建 2 debug](dist/logos-0.1.0-debug.apk)，支持 Android 8.0＋的 ARM64 真机和 x86_64 模拟器，约 138 MiB。初次使用需连接下述本地后端，下载离线经文后可离线阅读。此包为内测签名。

**验证状态：** 2026-10-20 已补充账号生命周期与分进程离线验收脚本，并修复云端快照落库后列表未刷新的问题；数据断言、19 项独立 PG18 后端集成测试、Flutter analyze、67 项常规 Flutter 测试及 3 项主机安全检查通过。此前账号包已在真机完成 v1→v2 迁移核对；构建 2 已覆盖安装真机，核对安装前后数据库/凭证文件一致及“关于”页构建号。五阶段断网冷启动仍待设备执行，不将安装或桌面测试当作完整真机签收。详细构建证据见 [验收记录](docs/验收记录.md)，账号数据归属见 [游客数据导入协议](docs/游客数据导入协议.md)。

游客模式不会上传个人数据。“我的 → 登录信息”打开“账号与同步”，阅读并同意说明后连接开发账号，游客收藏、笔记、阅读进度及分享会归入该账号并同步。断网或退出时，未上传数据保留在原账号的本地库中，重连原账号后续传；退出后使用空的游客业务数据，离线经文包和显示设置保留。账号页提供待上传数量、失败说明、立即同步和退出入口。切换到其他账号需先退出；开发 token 过期后需重新连接同一账号。

阅读页单击正文或空白处切换全屏；仅全屏模式下长按经文进入选中状态，普通模式长按不选中。选中后单击经文追加或取消选择，文字以下划短线标记，复制、收藏、笔记、分享和高亮工具悬浮在底部；点击关闭按钮或返回键取消选择。翻章使用左右滑动或目录。

主导航为首页、阅读计划、我的，手机底栏和宽屏侧栏均不再显示“记录”。分享历史从“我的 → 我的分享”进入，独立页面仅显示分享卡片，支持加载更多、查看引用范围和节数以及点击跳转阅读。既有分享直接保留，旧 `/records` 路由兼容跳转到新页。

浮动工具操作的成功提示约 1.3 秒（包含两段各 150 毫秒的动画）。高亮自动收藏经文，当前颜色用带间距的珊瑚红外圈标识，再点同色取消；无笔记时同时取消收藏，有笔记时保留收藏。多选颜色不一致时点击可统一设置，全部同色后再次点击取消。普通收藏显示珊瑚红实线；只有高亮时不叠加实线，工具栏主按钮改为“取消高亮”并同步取消收藏。有笔记的经文显示实线和下标圆圈数量，可与高亮共存，选中短虚线使用独立位置。全屏点击圆标可查看该节全部笔记，并可从列表进入编辑。

选中或复制经文不生成个人记录，旧的“选中”记录自动从数据库删除。取消高亮时同步删除对应高亮记录，换色或重复高亮时替换旧记录，旧版遗留的失效/重复高亮记录也会自动清理。“分享”记录按一次分享合并保存全部所选经文，卡片显示完整引用范围和节数：连续节合并为范围，不连续节用逗号分隔，例如“约翰福音 3:1-5,9,11 · 共 7 节”；已有记录同样生效。取消系统分享面板不记录。Android 以选择分享目标为记录时点，不表示已确认接收方应用发送成功。

全屏阅读时使用系统返回手势会直接离开阅读页，恢复系统状态栏；若没有上一页则回到首页。正在多选经文时，返回仍先取消选择。

正文按源段落连续排版，章号放大并环绕开头两行，节号嵌入正文。全屏在正文开头保留书卷/章/译本行；常规模式顶部为返回、目录、译本、历史，底部为播放、搜索、对照、研读、设置、更多。目录提供卷/章/节切换、四列书卷网格或列表、目录到节开关和新旧约跳转。播放与其他译本尚未接入，入口显示实际功能说明。

章、节页采用独立的五列数字网格：顶部显示当前书卷与章，选中标签用珊瑚红文字和短横线标示；白色单元格配浅灰细分隔线，余下区域为浅灰底。卷页的视图开关、新旧约底栏不显示在章、节页。

笔记编辑页的“添加”通过卷→章→节目录关联经文：书卷支持四列网格/列表与新旧约跳转，章使用五列数字，节页展示正文与多选框。已有引用预先勾选，可跨章跨卷选择；点“确定”更新引用，直接返回放弃本次选择，笔记草稿保留。合节正文只展示一次，选择和移除会覆盖该合节的全部节地址；最多关联 100 个节地址，超限时提示且保留已有选择。

安装包和 SDK 缓存留在本机，默认不提交 Git；分发 APK 时使用私有制品或 Release 附件。

## 从这里阅读

- [APK 全面分析与 REA 研究](analysis/APK全面分析.md)
- [功能对照与架构差距](docs/功能对照与架构差距.md)
- [实际构建和验收记录](docs/验收记录.md)
- [游客数据存储与导入协议](docs/游客数据导入协议.md)
- [Android 自动验收](docs/Android自动验收.md)
- [Git 基线与独立备份](docs/基线与备份.md)
- [原技术架构方案](Logos-技术架构方案.md)
- [数据源与第三方许可](THIRD_PARTY_NOTICES.md)

## 目录

```text
apps/logos/       Flutter Android App，附 Web 预览
backend/          Java 21 / Spring Boot 3 / GraphQL 单服务
data/             公有领域 CUVs 导入数据、密文、明文结构索引与报告
tools/import-bible/  固定哈希 USFM 导入器、66 卷码本
tools/            分析、数据断言、本地开发脚本
analysis/         研究报告、原始证据与截图（raw 提取物不入产品包）
docs/             实施决策、差距与验收
sql/init/         PG 扩展初始化
compose.yml       PG16+pgvector、Redis7.2，仅绑定本机
.tools/           本次准备的 SDK/JDK/本地工具与密钥，禁止提交
```

## 本工作区启动

准备好的 Flutter SDK 在 `.tools/flutter/`，Java 21 在 `.tools/jdk21/`，Android SDK 在 `.tools/android-sdk/`。构建缓存位于 D 盘工作区。

本次验证使用一个独立的本地 PostgreSQL 集群：`.tools/pgdata`，`127.0.0.1:55432`，开发用户/库 `logos`。这是仅绑定回环的 trust 开发实例，不用于对外部署。

如果实例已停止，可在本机用已安装的 PG18 工具启动：

```powershell
& D:/PostgreSQL/18/bin/pg_ctl.exe -D .tools/pgdata -l analysis/postgres.log -o '-p 55432 -h 127.0.0.1' start
```

启动后端（另一个终端）：

```powershell
powershell -ExecutionPolicy Bypass -File tools/dev.ps1 backend
```

后端监听 `127.0.0.1:8080/graphql`。首次启动自动建表并导入固定公共领域经文，个人数据不会被覆盖。开发 profile 支持测试验证码 `246810`、邀请码 `LOGOS-LOCAL`，仅为联调入口；正式 profile 不接受此通道，且要求配置 JWT_SECRET。

启动 Web 辅助预览（若已构建）：

```powershell
powershell -ExecutionPolicy Bypass -File tools/dev.ps1 serve
```

打开 <http://127.0.0.1:7357>。端口与 CORS 已配套。首次阅读需要后端提供解密密钥；设置中下载后可离线使用。

Android 模拟器默认连接 `http://10.0.2.2:8080/graphql`。真机通过 USB 联调时：

```powershell
.tools/android-sdk/platform-tools/adb.exe reverse tcp:8080 tcp:8080
```

然后在 App「设置 → 经文服务连接」中填 `http://127.0.0.1:8080/graphql`。真实远程地址必须是 HTTPS。主密钥不会写进 APK；初次无网络、无密钥时只能浏览结构，这是方案定义的状态。

拔掉 USB 后可使用 Android 无线调试：手机与电脑连接同一 Wi-Fi，在开发者选项中开启无线调试，通过二维码或配对码与电脑配对，再连接无线调试主页显示的手机 IP 和连接端口。连接端口与配对端口不同，重新开启无线调试时可能变化。在项目目录执行（替换手机 IP 和连接端口）：

```powershell
.tools/android-sdk/platform-tools/adb.exe connect 手机IP:连接端口
.tools/android-sdk/platform-tools/adb.exe -s 手机IP:连接端口 reverse tcp:8080 tcp:8080
```

App 服务地址仍使用 `http://127.0.0.1:8080/graphql`，电脑和后端需保持运行；无线连接断开后应重新连接并恢复转发。此方式无需把开发后端开放到局域网，也不需要修改 APK 的 HTTP 地址限制。

## 在新环境准备

需要 Flutter stable（本次 3.47.7）、Java 21、Maven 3.9、Android SDK，Python 3.11＋`cryptography`；重新分析 APK 另需 `androguard`、`loguru`、`lxml`、`pyelftools`。

1. 启动 Docker Desktop，复制 `.env.example` 为 `.env` 并设置本地密码，`docker compose up -d`。
2. 导出 DATABASE_PASSWORD、JWT_SECRET 等环境变量（Compose 的 .env 不会自动成为 Maven 进程环境）。
3. 从 `https://ebible.org/Scriptures/cmn-cu89s_usfm.zip` 下载源文件到 `.tools/downloads/`。
4. 执行数据导入并复制产物：

```powershell
python tools/import-bible/import_bible.py .tools/downloads/cmn-cu89s_usfm.zip
Copy-Item data/bible.bin,data/bible_index.json apps/logos/assets/
```

导入器核对 `checksums.txt`，源快照变化时失败，必须先审阅再更新哈希。首次运行生成 `.tools/bible-key.txt`；该文件只给后端使用。需要跨环境统一加密包时，通过 `BIBLE_MASTER_KEY` 注入同一 32 字节 Base64 密钥；不要提交它。

现成 APK 的密文与当前工作区主密钥配套。跨环境部署须安全保留匹配密钥；重新生成密钥和密文时，应重新构建客户端。

5. `cd apps/logos`，`flutter pub get`；回根目录运行后端与客户端。

国内网络可在当前终端设置 `PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。本次还使用了校验后预下载 SQLite hook 二进制的辅助脚本，见 `tools/bootstrap_sqlite.py`；该脚本不修改依赖源码。

## 检查与构建

```powershell
python tools/verify_data.py
mvn -f backend/pom.xml test
cd apps/logos
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
flutter build apk --debug --target-platform android-arm64,android-x64
flutter build web --no-wasm-dry-run
```

默认 `flutter test` 会跳过需要外部服务的真实 HTTP 用例（其余 67 项可独立运行）。准备一个使用一次性数据库的开发后端后，可运行：

```powershell
flutter test --no-pub --concurrency=1 test/account_remote_http_test.dart --dart-define=LOGOS_ACCOUNT_TEST_URL=http://127.0.0.1:18080/graphql
```

该用例会在目标服务创建两个开发账号、上传并修改/删除测试数据，只指向独立测试数据库。本轮使用项目 PG 55432 上临时新建的数据库和 18080 服务完成测试，结束后均已清理。

Android 完整验收采用独立包名和一次性后端数据库，先编译、后按设备执行：

```powershell
# 在项目根目录执行。build-only 不安装、不写数据库。
.tools/venv/Scripts/python.exe tools/run_android_acceptance.py --build-only
# 替换为专用设备的实际标识；x86_64 模拟器加 --target-platform android-x64。
.tools/venv/Scripts/python.exe tools/run_android_acceptance.py --device 设备标识
```

脚本覆盖读经、A/B 账号、游客合并、两次离线进程启动及联网续传。仅重置 `app.logos.bible.integration` 的合成测试数据，不修改个人 App；测试包不覆盖 dist。原理、输出及执行限制见 [Android 自动验收](docs/Android自动验收.md)。

Android 构建产物在 `apps/logos/build/app/outputs/flutter-apk/`。当前为 debug 内测签名，不是生产发行包。发布前需要完成差距清单中的账号、同步、安全、签名、备份和真机验收。

原 APK 不作为依赖，不参与 Logos 构建；原资源、第三方付费文本、字体与商标不被复制。所有经文来自独立公共领域数据源。
