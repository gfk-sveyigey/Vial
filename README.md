# Vial

iOS 应用，Bundle Identifier：`com.aholic.vial`。最低支持 iOS 26.0，版本号由根目录 `VERSION` 管理。

## 导航

基础标签栏依次为 **主页、新发现、广播、资料库、搜索**。搜索默认与其他页面共用标签栏；开启“独立搜索页面”后，搜索页使用系统搜索标签角色。标签栏收缩与各页面显示状态在 iOS「设置」App 的 Vial 设置项中配置。搜索始终显示，不能隐藏。

导航 Header 使用自定义 SwiftUI 视图，滚动时可收缩。临时调试入口位于资料库页面，调试内容以 Sheet 呈现。

## GitHub Actions

- `.github/workflows/build-dev.yml`：向 `dev` 推送应用、工程、设置 bundle 或 `VERSION` 更改时构建 Debug unsigned IPA，也支持手动触发。
- `.github/workflows/build-and-release.yml`：PR 合并到 `main` 后，以 `VERSION` 创建 GitHub Release，并附带 unsigned IPA 和 SHA256。

构建需 Xcode 27 / Swift 6.3，最低部署版本为 iOS 26.0。
