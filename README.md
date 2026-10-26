<div align="center">
    <img width="160" height="160" src="assets/images/logo/logo.png" alt="PiliPlusC logo">
    <h1>PiliPlusC</h1>
    <p>A third-party Bilibili client built with Flutter, with a filter that learns what you don't want to see</p>

English | [中文](README.zh-CN.md)

<a href="https://github.com/XiaoNetwork-Astral/PiliPlusC/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/XiaoNetwork-Astral/PiliPlusC?style=flat-square"></a>
<a href="https://github.com/XiaoNetwork-Astral/PiliPlusC/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/XiaoNetwork-Astral/PiliPlusC/ci.yml?branch=main&style=flat-square&label=CI"></a>
<a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/XiaoNetwork-Astral/PiliPlusC?style=flat-square"></a>
</div>

<br/>

PiliPlusC builds on [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) and PiliPlusX. It is maintained by idk together with Claude, an AI assistant made by Anthropic. The C in the name stands for Claude.

*This is an unofficial client. It is not affiliated with, endorsed by, or connected to Bilibili.*

## Highlights

- a **cognitive filter** that keeps out what you don't want to read, with **rule blocking** and **AI blocking** in one place
- **rule blocking** with keyword, regex and user rules, scoped to danmaku, comments, dynamics, videos and live rooms
- **AI blocking** with your own key: it only hides what it is sure about and lets everything uncertain through
- a **calibration wizard** that nudges the blocking threshold with your own answers
- a **block history** that restores the original comment, video, dynamic or danmaku, with one-tap whitelisting
- **playback** with danmaku (advanced, merged and colored), subtitles, hardware decoding, picture in picture, DLNA casting and offline cache
- **dynamics, comments and direct messages**, multiple accounts, incognito and guest modes
- **backup and restore** through WebDAV, an archive or the clipboard, with optional password protection
- a **searchable settings** page that jumps to the exact option
- and the small things you would expect from a good client

## Platforms

- [Android](#android) (arm64-v8a, armeabi-v7a, x86_64)
- [iOS](#ios)
- [macOS](#macos)
- [Windows](#windows)
- [Linux](#linux)

> [!NOTE]
> Tablets and desktops get the wide layout. There is no web build.

## Looks

<div align="center">
<img src="assets/screenshots/home.png" width="23%" alt="Home" />
<img src="assets/screenshots/dynamic.png" width="23%" alt="Dynamics" />
<img src="assets/screenshots/bangumi_detail.png" width="23%" alt="Bangumi" />
<img src="assets/screenshots/set.png" width="23%" alt="Settings" />
<br/>
<img src="assets/screenshots/main_screen.png" width="96%" alt="Desktop" />
</div>

## Install

Every build is on the [releases page](https://github.com/XiaoNetwork-Astral/PiliPlusC/releases/latest). Pick the file for your system.

### Android

Download `PiliPlusC_android_<version>_<abi>.apk`. Most phones need `arm64-v8a`.

### iOS

Download `PiliPlusC_ios_<version>.ipa`. It is not signed, so install it with a sideloading tool such as AltStore or SideStore.

### macOS

Download `PiliPlusC_macos_<version>.dmg` and drag the app to Applications.

### Windows

Download `PiliPlusC_windows_<version>_x64_setup.exe` for an installer, or `PiliPlusC_windows_<version>_x64_portable.zip` to run it from a folder.

### Linux

Download the `tar.gz`, `deb`, `rpm` or `AppImage` file. For the AppImage:

```bash
chmod +x PiliPlus_linux_*.AppImage
./PiliPlus_linux_*.AppImage
```

### Build from source

Install the Flutter version named in [`pubspec.yaml`](pubspec.yaml), then:

```bash
flutter pub get
flutter run
```

## Hong Kong, Macau and Taiwan content

The app uses web endpoints, so public proxies built for other clients do not work. Reverse proxy `api.bilibili.com`, or add these routes to your own proxy:

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
> A proxy receives your cookies. Only use one you trust, or stay logged out.

## Disclaimer

PiliPlusC is a personal project for learning and testing. Please delete it within 24 hours of downloading. All APIs come from the official website, and the project provides no cracked content.

## License

Released under the GNU General Public License v3.0, see [LICENSE](LICENSE).

## Credits

Thanks to [guozhigq/pilipala](https://github.com/guozhigq/pilipala), [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) and [orz12/PiliPalaX](https://github.com/orz12/PiliPalaX) for the work this is built on, and to [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect), [media-kit](https://github.com/media-kit/media-kit) and [dio](https://pub.dev/packages/dio).
