<div align="center">
    <img width="160" height="160" src="assets/images/logo/logo.png" alt="PiliPlusC logo">
    <h1>PiliPlusC</h1>
    <p>使用 Flutter 开发的哔哩哔哩第三方客户端，自带一套能按你的喜好屏蔽内容的认知滤网</p>

[English](README.md) | 中文

<a href="https://github.com/XiaoNetwork-Astral/PiliPlusC/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/XiaoNetwork-Astral/PiliPlusC?style=flat-square"></a>
<a href="https://github.com/XiaoNetwork-Astral/PiliPlusC/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/XiaoNetwork-Astral/PiliPlusC/ci.yml?branch=main&style=flat-square&label=CI"></a>
<a href="LICENSE"><img alt="许可证" src="https://img.shields.io/github/license/XiaoNetwork-Astral/PiliPlusC?style=flat-square"></a>
</div>

<br/>

PiliPlusC 基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 和 PiliPlusX 继续开发，由 idk 与 Claude（Anthropic 的 AI 助手）共同维护。名字里的 C 代表 Claude。

*这是非官方客户端，与哔哩哔哩没有任何关联。*

## 亮点

- **认知滤网**：把不想看的内容挡在外面，**规则屏蔽**和 **AI 屏蔽**在同一个入口
- **规则屏蔽**：关键词、正则、用户三类规则，可分别作用于弹幕、评论、动态、视频和直播
- **AI 屏蔽**：用你自己的密钥接入，只屏蔽有十足把握的内容，拿不准一律放行
- **校准向导**：根据你自己的判断微调屏蔽门槛
- **屏蔽历史**：还原被屏蔽的评论、视频、动态和弹幕原貌，一键加入白名单
- **播放**：弹幕（高级、合并、彩色）、字幕、硬件解码、画中画、DLNA 投屏、离线缓存
- **动态、评论、私信**，多账号，无痕与游客模式
- **备份与恢复**：WebDAV、压缩包、剪贴板三种方式，可用密码加密
- **设置可搜索**，点击结果直接跳到对应选项
- 还有许多一个好客户端该有的小细节

## 适配平台

- [Android](#android)（arm64-v8a、armeabi-v7a、x86_64）
- [iOS](#ios)
- [macOS](#macos)
- [Windows](#windows)
- [Linux](#linux)

> [!NOTE]
> 平板和桌面端使用宽屏布局，没有网页版。

## 截图

<div align="center">
<img src="assets/screenshots/home.png" width="23%" alt="首页" />
<img src="assets/screenshots/dynamic.png" width="23%" alt="动态" />
<img src="assets/screenshots/bangumi_detail.png" width="23%" alt="番剧" />
<img src="assets/screenshots/set.png" width="23%" alt="设置" />
<br/>
<img src="assets/screenshots/main_screen.png" width="96%" alt="桌面端" />
</div>

## 安装

所有构建都在 [Releases 页面](https://github.com/XiaoNetwork-Astral/PiliPlusC/releases/latest)，按系统选择对应文件。

### Android

下载 `PiliPlusC_android_<版本>_<abi>.apk`，大多数手机选 `arm64-v8a`。

### iOS

下载 `PiliPlusC_ios_<版本>.ipa`。安装包没有签名，需要用 AltStore、SideStore 之类的工具自行侧载。

### macOS

下载 `PiliPlusC_macos_<版本>.dmg`，把应用拖进「应用程序」。

### Windows

下载 `PiliPlusC_windows_<版本>_x64_setup.exe` 安装，或下载 `PiliPlusC_windows_<版本>_x64_portable.zip` 解压即用。

### Linux

下载 `tar.gz`、`deb`、`rpm` 或 `AppImage`。AppImage 的用法：

```bash
chmod +x PiliPlus_linux_*.AppImage
./PiliPlus_linux_*.AppImage
```

### 从源码构建

安装 [`pubspec.yaml`](pubspec.yaml) 里指定的 Flutter 版本，然后：

```bash
flutter pub get
flutter run
```

## 港澳台内容

由于使用了 web 接口，不能直接用哔哩漫游的公共服务器。直接反向代理 `api.bilibili.com`，或在自己的代理里加上这些路由：

```text
/x/web-interface/view
/x/web-interface/wbi/search/type
/x/player/wbi/playurl
/pgc/season/index/result
/pgc/web/timeline
/pgc/season/index/condition
/pgc/player/web/v2/playurl
/pgc/view/web/season
```

> [!WARNING]
> 代理服务器会收到你的 cookie，请只用可信任的代理，或不登录账号使用。

## 声明

PiliPlusC 是个人为了兴趣而开发的项目，仅用于学习和测试，请于下载后 24 小时内删除。所用 API 皆从官方网站收集，不提供任何破解内容。

## 许可证

基于 GNU 通用公共许可证第 3 版，见 [LICENSE](LICENSE)。

## 致谢

感谢 [guozhigq/pilipala](https://github.com/guozhigq/pilipala)、[bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)、[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX) 提供的基础，以及 [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)、[media-kit](https://github.com/media-kit/media-kit)、[dio](https://pub.dev/packages/dio)。
