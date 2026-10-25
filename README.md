# 旅迹 · TravelRecorder

原生旅行路线记录器：**iOS 14+ / Android 8.0+**。路线、导入照片和日记保存在手机本地，两个平台暂不提供数据同步。

## 下载与安装

前往 [最新版本下载页](https://github.com/hanry123123/travel-recorder/releases/latest)：

- **iPhone**：下载 `TravelRecorder-1.4.1.ipa`，使用 TrollStore 安装。
- **Android**：下载 `TravelRecorder-1.4.1.apk` 安装。
- 更新请直接覆盖安装，**不要卸载旧版**，避免删除本机旅程。校验值见 Release 的 `SHA256SUMS`。

## 功能

- 开始记录位置并连接路线，支持暂停、继续和后台记录；暂停或定位中断保留缺口。
- 自动关联旅程照片，也可手动添加旧照片；无GPS照片可在地图上放置，保存独立照片副本和缩略图。
- 点击照片或地图地点写日记，补充整段旅程的特点与感受。
- 回忆卡片显示路线形状、最多三张照片及起终点；支持编辑、收藏理由、收藏筛选和删除。
- 路途重现按时间顺序播放红点与火星；时间滑块可拖动，记录中新位置继续加入。镜头平滑跟随，手动拖图停止跟随。
- 生成路线、照片和文字组成的图片或视频，通过系统分享发送到微信等应用，也可保存相册。

没有网络仍可记录GPS、写日记、看已保存照片。iOS使用MapKit；Android使用带署名的OpenStreetMap底图，能否加载取决于网络及缓存。原始坐标保持WGS84，大陆坐标转换只用于iOS地图显示。分享作品使用自绘路线，不包含第三方地图底图。

## 1.4.1 更新

- 调整iOS圆形地图按钮和地图接缝的绘制，移除额外栅格化、重复裁剪及底边遮盖条。
- 记录页、回忆卡片和详情的分享入口改为纯图标，保留点击范围及读屏名称。
- 本次公开版同时包含1.3/1.4新增的实时重现、平滑镜头、收藏、图文/视频分享，以及Android原生版本。

手机上特定状态下出现的黑圈/细线仍需实际确认，电脑预览不能证明已消失。验证范围见 [版本说明](docs/RELEASE-1.4.1.md)，手机短测见 [检查步骤](docs/DEVICE-CHECKLIST.md)。

## 构建

### iOS

Swift 5、SwiftUI、MapKit、Core Location、PhotoKit、Core Data；最低系统iOS14。使用Xcode16.2/iOS18.2 SDK完成本次构建。

```sh
python3 scripts/generate_project.py
python3 scripts/build_ipa.py
python3 scripts/audit_ipa.py
```

也可打开 `TravelRecorder.xcodeproj`。构建脚本默认使用 `/Applications/Xcode.app`。核心夹具为 `sh scripts/run_fixtures.sh`；`python3 scripts/run_share_fixture.py` 在Mac Catalyst环境检查生产绘制和视频导出。

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

1.4.1通过iOS构建、146项安装包审计、宿主签名回归和23项现有Mac Catalyst检查；Android通过构建、签名与模拟器覆盖升级、分享图标操作检查。实体手机的锁屏记录、相机时序、地图网络、屏幕细线和微信接收效果仍需实际验证。

第三方声明见 [THIRD-PARTY.md](docs/THIRD-PARTY.md) 和 [Android地图声明](android/assets/ThirdPartyNotices.txt)。
