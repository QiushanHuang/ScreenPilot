# ScreenPilot identity · 品牌图形

Two overlapping displays represent one shared workspace. The navigation cursor represents choosing where that workspace appears. Mint (`#78e8c4`), muted teal (`#36756e`) and charcoal (`#121a21`) follow the application's existing palette.

双屏代表共享工作空间，指向标记代表主动选择输出位置；保留应用原有薄荷绿、青绿与深炭色。

- Editable vector: [logo.svg](images/logo.svg)
- README raster: [logo.png](images/logo.png)
- macOS icon generator: [make-icon.swift](../scripts/make-icon.swift)
- Theme-aware, transparent in-app mark: [BrandMark.swift](../Sources/ScreenPilot/BrandMark.swift)
- Windows multi-resolution icon: [ScreenPilot.ico](../WindowsBridge/ScreenPilot.ico)

The original geometry is drawn deterministically using SVG/AppKit, without an image-generation service. The icon is bundled in both desktop binaries. Copyright © 2026 QiushanHuang (Qiushan); see the project license.
