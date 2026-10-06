# ClipHarbor · 视频下载器

SwiftUI 视频下载工具，支持选择保存目录、查看下载日志、取消任务和提取 MP3。

## 功能

- yt-dlp 下载视频和播放列表
- FFmpeg 合并视频及音频转码
- 可选 CCTVVideoDownloader 处理央视页面

## 从源码构建

要求 macOS 14 或更新版本，以及 Xcode Command Line Tools。

```bash
./build.sh --compile-only
```

这会编译 Swift 程序到 `build/`。运行完整应用还需要以下依赖：

将 yt-dlp 的 macOS 可执行文件命名为 `yt-dlp_macos` 放在 `Resources/`，同时提供 `ffmpeg` 和 `deno`。可选央视下载器位于 `Resources/cctv-dl/bin/cctv-dl`，缺少时走 yt-dlp。

`Sources/` 存放原生界面源码，`Resources/` 存放应用资源和后端脚本。准备好依赖后运行 `./build.sh` 生成应用包。构建脚本执行本地 ad-hoc 签名；正式发布需另行签名和公证。

如已有对应应用的完整依赖，可以指定其资源目录重新打包：

```bash
APP_RESOURCES="/path/to/Application.app/Contents/Resources" ./build.sh
```

此方式复用第三方运行时，重新编译本仓库的原生程序；构建结果在 `build/`，不提交到源码仓库。脚本不会打包已有的文件索引或用户转换结果。

## 许可证与第三方组件

本项目原创界面、脚本和构建文件使用 [MIT License](LICENSE)。第三方源码、图标和运行时遵循其原有许可，根目录许可不覆盖第三方材料。

[yt-dlp](https://github.com/yt-dlp/yt-dlp)、[FFmpeg](https://github.com/FFmpeg/FFmpeg)、[Deno](https://github.com/denoland/deno)。第三方组件按各自许可证分发，见 `licenses/`。
