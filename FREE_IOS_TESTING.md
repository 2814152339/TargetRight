# iPhone 免费验证方案（无 Mac）

本文档基于两步：

1. GitHub Actions 在云端构建 iOS `unsigned ipa`
2. Windows 用 Sideloadly 重签并安装到 iPhone

## 0. 前置准备

- 你有 GitHub 账号
- iPhone 一台 + 数据线
- Windows 电脑
- Apple ID（免费即可）
- 安装 iTunes（建议 Apple 官网版本，不建议 Microsoft Store 版本）
- 安装 Sideloadly：<https://sideloadly.io/>

## 1. 把工程推到 GitHub

当前工作流文件在仓库根目录：

- `.github/workflows/ios-unsigned-ipa.yml`

这个工作流默认 Flutter 项目目录是 `app/`。如果你把 Flutter 项目作为仓库根目录，请把 `working-directory: app` 改成 `working-directory: .`，并把上传路径改为 `build/ios/ipa/*.ipa`。

## 2. 触发云构建

1. 打开 GitHub 仓库的 `Actions`
2. 进入 `iOS Unsigned IPA`
3. 点击 `Run workflow`
4. 等待任务完成（大约 8-20 分钟）
5. 下载构建产物 `jinshi-checkin-ios-unsigned-ipa`
6. 解压后得到 `Runner.ipa`（或类似名称）

## 3. 用 Sideloadly 安装到 iPhone

1. iPhone 连接电脑并点“信任此电脑”
2. 打开 Sideloadly
3. 设备栏选择你的 iPhone
4. IPA 栏选择上一步下载的 `.ipa`
5. 输入你的 Apple ID（用于重签）
6. 点击 `Start` 开始安装

安装成功后，在 iPhone 执行：

1. 设置 -> 通用 -> VPN与设备管理（或“设备管理”）
2. 找到你的 Apple ID 证书并点“信任”
3. 返回桌面打开 App

如果系统提示开发者模式（iOS 16+）：

1. 设置 -> 隐私与安全性 -> 开发者模式
2. 开启后重启手机

## 4. 你要验证的功能清单

1. 新建循环任务（例如每 5 分钟）
2. 首页只显示循环任务，左右可滑
3. 出现待确认提醒点后，只能二选一：已完成 / 未完成
4. 日历页查看同一提醒点状态与首页一致
5. 在“我的”切换 VIP / Feature Flag，验证双人入口策略
6. 双人任务下，只有你和 TA 都“已完成”才增长进度
7. 退后台等待提醒，确认本地通知触达

## 5. 免费签名限制（必须知道）

- 免费 Apple ID 安装的应用一般 7 天有效
- 到期后需重新用 Sideloadly 安装一次
- 可同时自签的 App 数量有限（通常最多 3 个）

## 6. 常见问题

1. `No such module` / Pod 相关失败  
   重新触发一次 workflow，通常可恢复；若持续失败我再帮你加 CocoaPods 清理步骤。

2. 手机上打不开或闪退  
   先确认已“信任证书”和开启开发者模式，再重装一次。

3. 通知不触发  
   检查 iOS 设置中 App 通知权限是否允许，且低电量模式下可能延迟。
