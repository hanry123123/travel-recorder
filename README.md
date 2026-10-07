# 旅迹 · TravelRecorder

兼容 iOS 14 的原生 iPhone 旅行记录器，用路线、照片和日记保存旅途回忆。

**[下载最新版 IPA](https://github.com/hanry123123/travel-recorder/releases/latest)** · [1.2.0 更新说明](docs/RELEASE-1.2.0.md)

## 功能

- 开始、暂停、继续和结束路线记录；支持后台定位，未记录区间保留缺口。
- 自动关联旅途中照片，手动导入以前的照片；无定位照片可手动放到地图上。
- 地图显示细白框照片缩略图，可给照片和地点写日记，也可记录整段旅程的特点与感受。
- 回忆卡片左侧路线、右侧最多三张照片、顶部起终点，支持编辑及删除已结束回忆。
- 红色光点与飞散火星重现路程顺序；拖动进度条同步查看记录时间与地图位置。
- 手动移动地图停止跟随；定位按钮恢复跟随，双箭头按钮查看全程。

数据保存在手机应用容器中，照片保存独立JPEG副本和缩略图。删除系统相册原图不影响已导入副本。没有账号或云端同步；无网仍可记录、写日记及看已保存照片，地图底图和首次地点名查询依赖网络或已有缓存。

## 安装与更新

在 [Releases](https://github.com/hanry123123/travel-recorder/releases) 下载 `TravelRecorder-1.2.0.ipa`，在支持TrollStore的设备上导入。部署目标iOS14.0，包含ARM64真机程序。点击“开始记录”，按需授予位置和相册权限。

更新时直接覆盖安装，**不要先卸载**，以免丢失本机回忆。强制关闭App或重启手机会中断定位，之后可继续记录，不补画遗漏路程。

## 构建与测试

Swift 5模式，SwiftUI、MapKit、Core Location、PhotoKit和Core Data，无第三方Swift包。

- Xcode打开 `TravelRecorder.xcodeproj`，共享scheme为 `TravelRecorder`，部署目标14.0。个人开发签名需设置自己的Team。
- 当前IPA用Xcode16.2/iPhoneOS18.2 SDK构建，脚本默认Xcode位于 `/Applications/Xcode.app`。
- `python3 scripts/generate_project.py` 重新生成项目与几何App图标。

```sh
shasum -a 256 -c source.SHA256SUMS
sh scripts/run_fixtures.sh
python3 scripts/build_ipa.py
python3 scripts/audit_ipa.py
```

输出位于 `artifacts/`；构建脚本采用ad hoc签名供TrollStore导入，不包含开发者证书。公开仓库的应用代码、资源、测试及构建脚本与交付版一致，发布整理仅调整说明文件、忽略规则和源码清单。

## 验证状态

1.2.0通过200项核心/SQLite/ImageIO检查、142项包检查、Apple严格验签及宿主机ldid签名回归，真实Mach-O最低系统版本为iOS14.0。

**首次标签切换、正常全屏黑线与新增视觉效果仍待iOS14真机确认。** 编译和自动测试通过不代表所有手机行为已验证。精简检查见[更新说明](docs/RELEASE-1.2.0.md)，完整检查见[设备检查清单](docs/DEVICE-CHECKLIST.md)。

## 地图与第三方资料

原始GPS以WGS-84保存，大陆地图只在显示时转换；沿海和边境可在设置手动切换对齐模式。转换公式及地理范围来源与许可见[第三方声明](docs/THIRD-PARTY.md)。
