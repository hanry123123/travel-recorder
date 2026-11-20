# 旅迹 · TravelRecorder

原生旅行路线记录器：**iOS 14+ / Android 8.0+**。路线、导入照片和日记保存在手机本地，两个平台暂不提供数据同步。

## 下载与安装

- **iPhone**（iOS 14+）：用 TrollStore 覆盖安装 [旅迹 1.7.6 IPA](https://github.com/hanry123123/travel-recorder/releases/download/v1.7.6/TravelRecorder-1.7.6.ipa)。
- **Android**（8.0+）：下载 [旅迹 1.4.1 APK](https://github.com/hanry123123/travel-recorder/releases/download/v1.4.1/TravelRecorder-1.4.1.apk)。

**旧版 iPhone 用户升级前请检查相册。** 新版会清理旅迹内的旧照片副本，包括仅存在于旅迹中的副本。请先另存重要照片，再覆盖安装以保留路线和日记。详见 [1.7.6 版本说明](docs/RELEASE-1.7.6.md)。

## 功能

- 开始记录位置并连接路线，支持暂停、继续和后台记录；暂停或定位中断保留缺口。
- 自动关联旅程照片，也可手动添加旧照片；无GPS照片可在地图上放置，iOS 版从系统相册按需读取原图和缩略图。
- 点击照片或地图地点写日记，补充整段旅程的特点与感受。
- 回忆卡片显示路线形状、最多三张照片及起终点；支持编辑、收藏理由、收藏筛选和删除。
- 路途重现按时间顺序播放红点与火星；时间滑块可拖动，记录中新位置继续加入。镜头平滑跟随，手动拖图停止跟随。
- iOS 版可将路线、照片和文字生成为地图海报，从预览页右上角分享到微信等应用，或选择「存储图像」。

没有网络仍可记录GPS、写日记、看已保存照片。iOS使用MapKit；Android使用带署名的OpenStreetMap底图，能否加载取决于网络及缓存。原始坐标保持WGS84，大陆坐标转换只用于iOS地图显示。iOS 分享图片使用系统地图快照。

## 构建

### iOS

Swift 5、SwiftUI、MapKit、Core Location、PhotoKit、Core Data；最低系统iOS14。使用Xcode16.2/iOS18.2 SDK完成本次构建。

```sh
python3 scripts/generate_project.py
python3 scripts/build_ipa.py
python3 scripts/audit_ipa.py
```

也可打开 `TravelRecorder.xcodeproj`。构建脚本默认使用 `/Applications/Xcode.app`。核心夹具为 `sh scripts/run_fixtures.sh`；`python3 scripts/run_share_fixture.py` 在Mac Catalyst环境检查地图海报绘制、图片导出和交互逻辑。

### Android

原生Java，无第三方运行时SDK；最低API26，目标API35。构建需要JDK17、Android SDK平台35、Build Tools35。当前脚本使用macOS工具布局，根目录由 `TRAVEL_ANDROID_TOOLS` 指定，默认 `~/.local/share/travel-android-tools`：

- `jdk-17.0.16+8/Contents/Home/`：JDK
- `android-35/android.jar`：平台SDK
- `android-15/`：Build Tools35解压目录（含aapt2、d8、zipalign、apksigner）

```sh
python3 android/build.py
```

APK生成到 `android/build/`。首次构建会在用户目录的独立签名目录生成更新密钥；后续更新必须沿用，勿提交到仓库。`android/build_tests.py` 为隔离的Android测试环境生成测试APK。

## 验证与声明

验证范围见 [iOS 1.7.6](docs/RELEASE-1.7.6.md) 和 [iOS／Android 1.4.1](docs/RELEASE-1.4.1.md)。

第三方声明见 [THIRD-PARTY.md](docs/THIRD-PARTY.md) 和 [Android地图声明](android/assets/ThirdPartyNotices.txt)。
