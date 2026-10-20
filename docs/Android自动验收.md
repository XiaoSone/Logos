# Android 自动验收

本轮扩充 `apps/logos/integration_test/core_flow_test.dart`。普通读经场景继续覆盖搜索定位、多选高亮、笔记保存、原生 SQLite 和加密缓存读取；账号验收通过同一测试入口分阶段运行。

## 环境隔离

- 主机运行入口：`tools/run_android_acceptance.py`。必须明确选择设备，建议使用专用模拟器或测试手机。
- 测试包名为 `app.logos.bible.integration`，与个人 App `app.logos.bible` 分开安装。脚本在安装前核对 APK 包名，仅清理上次的独立测试 App；不清理个人 App 数据。
- 脚本在本项目 PG18 `127.0.0.1:55432` 创建 `logos_android_<随机编号>` 一次性数据库，启动独立 Java 后端，结束时停止自己创建的进程并删除该临时库。不使用现有 `logos` 库，不停止 8080 服务。
- 仅创建/移除本次拥有的设备端 `tcp:18081` ADB reverse。该端口已有转发时直接停止，不覆盖；其他转发保持原状。不会切换手机 Wi-Fi、移动网络或飞行模式。
- 测试内创建合成分享记录，不打开系统分享面板或发送外部消息。测试号码随机生成，仅使用开发验证码，不发送真实短信。

## 编译与运行

项目本地工具、Flutter 依赖和数据应按 README 准备好。仅编译验收包、不连接设备、不写数据库：

```powershell
cd D:\Project\pre\Logos
.tools/venv/Scripts/python.exe tools/run_android_acceptance.py --build-only
```

查看设备列表，然后用实际设备标识运行：

```powershell
.tools/android-sdk/platform-tools/adb.exe devices -l
.tools/venv/Scripts/python.exe tools/run_android_acceptance.py --device 设备标识
```

x86_64 模拟器加 `--target-platform android-x64`。本机 PostgreSQL 须已启动；PG 工具路径不同可指定 `--pg-bin`。脚本会构建测试 APK 和后端 JAR，运行期间使用项目 `.tools/tmp` 和 `.tools/gradle` 缓存。

## 五阶段断言

| 阶段 | 后端通道 | 核对内容 |
| --- | --- | --- |
| core | 在线 | 经文解锁、搜索定位、高亮、笔记及引用、设备加密离线下载和重新读取 |
| seed | 在线 | 未同意不能登录；游客合并 A；真实安全存储；退出后空游客；经文包/主题/字号保留；B 看不到 A；B 写入不进入 A；重连 A |
| offline-write | 切断 | 新进程在启动前探测后端不可达；恢复 A 凭证、经文密文及笔记；离线新增、编辑、删除；同步失败但队列持久化 |
| offline-reopen | 仍切断 | 再次强停后新进程启动；离线新内容、删除状态及队列 UUID 版本完整保留；退出 A 后游客为空、安全凭证移除，重新打开 A 数据库仍保留未上传任务 |
| reconnect | 恢复 | 先登录 B 确认未接管 A 的离线修改，再回 A 续传；用另一组全新原生 SQLite 文件从云端拉取，验证编辑/新增/删除及多节分享；重复同步不重复 |

每阶段执行前强停独立测试 App，并检查进程确实退出；每阶段返回 PID，主机要求 PID 不同。离线阶段在启动 AppController 前通过真实 socket 断言 `127.0.0.1:18081` 不可连接，使用与在线阶段相同的服务地址、真实安全存储及 SQLite。Flutter VM 服务通过另外的控制通道保持可用。因此不把同一进程重新实例化 Repository、修改测试假网络或热重启称为断网冷启动。

## 结果与限制

输出到 `analysis/android-acceptance/<时间-编号>/`：测试 APK、构建和各阶段日志、阶段 JSON、截图及 `summary.json`。主机检查 runId、phase 和 PID；任何阶段失败、证据缺失或资源清理失败，都不能标记为通过。`--build-only` 的摘要始终不标记完整验收通过。

失败时保留独立测试 App 数据和本地日志供排查；临时后端/数据库仍会清理。下次运行会重置独立测试 App。离线测试证明配置的业务后端不可达，并不要求设备所有网卡断开；真实飞行模式/系统断网提示仍可按人工清单补测。

正式短信、令牌刷新/撤销、跨设备 Android Keystore 恢复、PG16/Redis、生产签名不是此脚本已经覆盖的能力。未实际运行五阶段流程时，验收记录必须保留“待设备执行”。
