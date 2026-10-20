# Logos 开发约定

- 产品蓝图：`Logos-技术架构方案.md` v1.1；先阅读 `docs/功能对照与架构差距.md` 和 `docs/验收记录.md`，不要把开发版当作 Phase 1 已全部验收。
- Flutter Android 为主；Java 21 / Spring Boot 3 / GraphQL；PG16 为目标，本机验证 PG18 的差异见记录。
- 原 APK 仅用于研究。原代码、图标、字体、音频及受限制的文本不进入产品；经文只从校验过的公共领域来源导入。
- `.tools/bible-key.txt`、JWT 密钥、签名 keystore 不提交、不打印；APK 不内置正文解密主密钥。
- 游客业务数据只写客户端；未完成登录合并前，不把开发登录当作云同步。不要用 deviceId 充当用户身份。
- 阅读计划 Phase 1.5，AI/图谱 Phase 2；不引入社交、内容订阅平台或多 Agent 产品架构。
- 首选 `tools/dev.ps1` 启动，避免复用或修改机器上其他项目的数据库；本项目开发 PG 端口 55432。
- 有 `.codegraph/` 时先用 CodeGraph 理解/定位代码；没有则跳过，不自行建立索引。
- 验证依次为数据断言、后端集成测试、Flutter analyze/test、必要的 Android 交互验收。测试结果只记录实际运行过的项目。
