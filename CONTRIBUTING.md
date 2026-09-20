# Development · 开发

See README for dependencies and builds. Original project materials are all rights reserved; discuss licensing and contributions with [QiushanHuang](https://github.com/QiushanHuang) before submitting code.

## Checks / 检查

```sh
swift test -c release
./scripts/build-helper.sh
dotnet build WindowsBridge/ScreenPilotBridge.csproj -c Release
DOTNET_HOST_PATH="$(command -v dotnet)" python3 scripts/test-windows-core.py
python3 scripts/package-windows-ready.py
python3 -m unittest discover -s Tests -p 'test_*.py'
./scripts/build-app.sh
```

Swift checks cover mapping, brightness policy, recovery, output presets, USB arrivals, layout readiness and protocol rules. Native C tests cover DDC packets and control safety. Windows core tests exercise production protocol/arrival logic without Win32 hardware. Integration tests that require a local fixture are skipped unless that fixture is running.

Do not run `--ui-smoke`, `--connection-smoke` or `--connection-group-smoke` as routine CI checks: they manipulate physical displays. Explicit test targets are required through `SCREENPILOT_SMOKE_TARGET` or three comma-separated UUIDs in `SCREENPILOT_SMOKE_TARGETS`. Hardware results need a human observer and a working physical recovery path.

公共提交不要包含本机配置、配对码、设备清单、诊断报告、构建缓存或用户数据。`Config/VerifiedInputs.json` 被 Git 忽略；发布使用空示例映射。硬件测试必须单独明确范围，不得将 API 返回成功写成真实屏幕成功。

Report OS version, application version, monitor model and cabling when filing an issue. Redact addresses and device identifiers as appropriate; never attach pairing secrets.
