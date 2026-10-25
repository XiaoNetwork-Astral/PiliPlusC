<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>

<div align="center">
    <h1>PiliPlusC</h1>
    <p>使用 Flutter 开发的哔哩哔哩第三方客户端</p>

中文 | [English](README.en.md)

<img src="assets/screenshots/510shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/174shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/850shots_so.png" width="32%" alt="home" />
<br/>
<img src="assets/screenshots/main_screen.png" width="96%" alt="home" />
<br/>
</div>

<br/>

PiliPlusC 基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 和 PiliPlusX 继续开发，由 idk 与 Claude（Anthropic 的 AI 助手）共同维护。名字里的 C 代表 Claude，表示这个项目是人和 AI 一起做的。

## 适配平台

Android / iOS / Pad / Windows / Linux

## 港澳台代理

由于本项目使用了 web 接口，所以不能直接使用哔哩漫游的公共服务器。

搭建方法：直接反向代理 `api.bilibili.com`，或添加下面几个路由的支持：

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

可用的公共服务器：

注意：由于请求代理服务器会携带 cookie，所以请使用可信任的代理服务器，或不登录账号进行使用。

|提供者|服务器|
|------|------|
|gucooing|https://blblapi.alsl.xyz|

## 下载

可以从 [Releases](https://github.com/XiaoNetwork-Astral/PiliPlusC/releases) 下载，或克隆仓库拉取代码后在本地编译。

## 功能

- **播放**：推荐、热门、番剧、直播；弹幕（含高级弹幕、合并弹幕、会员彩色弹幕）、字幕、倍速、手势调节亮度音量与进度、记忆播放；硬件加速、超分辨率、画中画、DLNA 投屏；离线缓存与播放；SponsorBlock、跳过番剧片头片尾
- **内容与互动**：动态（发布、编辑、转发、话题、分组）；评论（楼中楼、点赞点踩、带图、置顶）；私信；三连与投币动画；收藏夹与稍后再看的管理；搜索与筛选
- **账号**：多账号；Cookie 登录；Win/Mac 支持极验和短信登录；无痕模式与游客模式；黑名单
- **备份与恢复**：支持 WebDAV、压缩包和剪贴板三种方式，可选择备份的项目，压缩包可用密码加密；登录信息属于敏感信息，导出时有明确提示
- **设置**：设置项可搜索，点击结果会跳转到对应位置并闪烁高亮
- **本分支特色**：港澳台内容适配、弹幕字体、桌面端快捷键、剪贴板搜索、动态分组筛选

## 声明

此项目（PiliPlusC）是个人为了兴趣而开发，仅用于学习和测试，请于下载后 24 小时内删除。
所用 API 皆从官方网站收集，不提供任何破解内容。

由 idk 与 Claude（Anthropic）共同维护。

在此致敬：
- 原作者：[guozhigq/pilipala](https://github.com/guozhigq/pilipala)
- 上游作者：[bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)、[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)

本仓库做了更激进的修改，感谢各位作者的开源精神。

感谢使用。

## 致谢

- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- 等等
