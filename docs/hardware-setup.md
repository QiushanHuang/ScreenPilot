# Verified shared-monitor setup · 共享显示器配置

The public app intentionally contains no developer-specific display identities. It offers general controls from detected capabilities, but the Mac/Windows host workflow needs an exact monitor mapping. There is currently no GUI mapping editor; use a local build for this advanced feature.

公开软件不包含开发者的显示器身份。常规操作按检测能力提供，跨主机工作流则需要精确映射。目前没有图形化映射编辑器，需要本地构建。

1. Connect Mac to HDMI 1 and Windows to HDMI 2. Enable DDC/CI. Use physical buttons to verify both inputs and the route back. / 按上述方式接线，开启 DDC/CI，用实体按键确认两端画面与恢复路径。
2. Build helpers and list identities (listing does not change display state): / 构建并只读查询身份：

   ```sh
   ./scripts/build-helper.sh
   .build/native/DisplayBridge list
   ```

3. Copy `Config/VerifiedInputs.example.json` to `Config/VerifiedInputs.json`. Use the exact `uuid` and `location` for the selected physical display. Only record an HDMI 2 route you have actually tested; do not copy another machine's identity. / 复制空示例，填入目标屏幕的精确身份，只登记自己实测过的 HDMI 2 路径。

   ```json
   [
     {
       "uuid": "REPLACE_WITH_YOUR_DISPLAY_UUID",
       "location": "REPLACE_WITH_YOUR_EXACT_IOREGISTRY_LOCATION",
       "value": 18,
       "label": "另一台主机"
     }
   ]
   ```

4. Restore screens and quit any running copy before rebuilding: / 恢复屏幕并退出正在运行的副本后构建：

   ```sh
   SCREENPILOT_VERIFIED_INPUTS=Config/VerifiedInputs.json ./scripts/build-app.sh
   ```

5. Open your local build, pair Windows, test manual switching before enabling USB automation. After changing ports/cables, identify the screen again and update the mapping only after revalidation. / 启动本地构建并配对，先测试手动切换，再开启 USB 自动。更换接线后重新识别、验证。

The mapping allows the tested target when input readback is unavailable; it does not certify brightness, power or reverse switching. Input `18` is HDMI 2; the companion's return target is HDMI 1. Never infer success merely from a sent command. If your monitor cannot reliably switch back, keep automation off.

白名单不代表该显示器的背光、电源或反向切换都可靠。无法可靠切回时不要开启自动切换。此文件只保存在本地，发布默认始终使用空映射。
