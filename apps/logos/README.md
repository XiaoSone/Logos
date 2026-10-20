# Logos Flutter 客户端

Android 为主要目标，Web 为辅助预览。完整启动、数据来源和密钥说明见 [根目录 README](../../README.md)，实际验证见 [验收记录](../../docs/验收记录.md)。

- `lib/main.dart`：Riverpod 容器、go_router 页面和经文深链。
- `lib/data/`：AES-GCM 经文解密、引用标准化、搜索、Drift 本地数据与设备缓存。
- `lib/state/app_controller.dart`：游客笔记、收藏、高亮、个人记录与阅读设置。
- `lib/ui/`：首页、卷章节目录、阅读器、搜索、笔记和设置。
- `test/`：引用、搜索与本地事务测试；`integration_test/`：Android 操作与离线恢复验证。

使用 Flutter stable 3.47.7 验证。首次联网从本地 GraphQL 服务解锁正文；APK 内不保存解密主密钥。游客记录保存在本机，开发账号入口尚不提供客户端云同步。

```powershell
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter run -d emulator-5554
```

Android 模拟器服务地址为 `http://10.0.2.2:8080/graphql`；Web 预览默认 `http://127.0.0.1:8080/graphql`。真机连接和离线下载步骤见根目录说明。
