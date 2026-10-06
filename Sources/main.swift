import SwiftUI
import AppKit

@MainActor
final class DownloadModel: ObservableObject {
    @Published var url = ""
    @Published var destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
    @Published var audioOnly = false
    @Published var isRunning = false
    @Published var status = "就绪"
    @Published var log = "粘贴视频链接，然后点击“开始下载”。\n"

    private var process: Process?
    private var outputPipe: Pipe?

    var ffmpegPath: String? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("ffmpeg").path
        return ([bundled].compactMap { $0 } + ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"])
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func paste() {
        if let value = NSPasteboard.general.string(forType: .string) {
            url = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if panel.runModal() == .OK, let selected = panel.url {
            destination = selected.path
        }
    }

    func openDestination() {
        NSWorkspace.shared.open(URL(fileURLWithPath: destination, isDirectory: true))
    }

    func start() {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host != nil else {
            status = "请输入有效的 http 或 https 链接"
            return
        }
        guard FileManager.default.fileExists(atPath: destination) else {
            status = "下载文件夹不存在"
            return
        }
        guard !audioOnly || ffmpegPath != nil else {
            status = "提取 MP3 需要安装 ffmpeg"
            return
        }
        guard let ytDlpExecutable = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) else {
            status = "应用包内缺少 yt-dlp"
            return
        }

        let cctvExecutable = Bundle.main.resourceURL?.appendingPathComponent("cctv-dl/bin/cctv-dl")
        let isCCTVVideo = (parsed.host?.lowercased() == "tv.cctv.com")
            && parsed.path.contains("VIDE") && parsed.path.hasSuffix(".shtml")
        let useCCTVDownloader = isCCTVVideo && !audioOnly
            && (cctvExecutable.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false)
        let executable = useCCTVDownloader ? cctvExecutable! : ytDlpExecutable

        let task = Process()
        let pipe = Pipe()
        task.executableURL = executable
        var arguments: [String]
        if useCCTVDownloader {
            arguments = ["download", trimmed, "--output", destination, "--quality", "0", "--threads", "8", "--mp4"]
        } else {
            arguments = ["--newline", "--progress", "--no-mtime", "-P", destination]
            if let ffmpegPath {
                arguments += ["--ffmpeg-location", ffmpegPath]
            }
            if audioOnly {
                arguments += ["-x", "--audio-format", "mp3"]
            }
            arguments.append(trimmed)
        }
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = pipe
        task.environment = ProcessInfo.processInfo.environment.merging([
            "PATH": "\(Bundle.main.resourcePath ?? ""):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        ]) { _, new in new }

        log = "正在下载：\(trimmed)\n保存到：\(destination)\n"
            + (useCCTVDownloader ? "央视视频：优先获取最高可用原始清晰度。\n\n" : "\n")
        status = useCCTVDownloader ? "央视高清下载中…" : "下载中…"
        isRunning = true
        process = task
        outputPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let message = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.log += message
            }
        }
        task.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            DispatchQueue.main.async {
                self?.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self?.process = nil
                self?.outputPipe = nil
                self?.isRunning = false
                self?.status = code == 0 ? "下载完成" : (finished.terminationReason == .uncaughtSignal ? "已取消" : "下载失败（退出码 \(code)）")
            }
        }
        do {
            try task.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            process = nil
            outputPipe = nil
            isRunning = false
            status = "无法启动 yt-dlp：\(error.localizedDescription)"
        }
    }

    func cancel() {
        process?.terminate()
    }
}

struct ContentView: View {
    @StateObject private var model = DownloadModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("yt-dlp 下载器")
                .font(.system(size: 24, weight: .bold))
            Text("粘贴支持的网站链接，选择保存位置即可下载。")
                .foregroundStyle(.secondary)

            HStack {
                TextField("视频或播放列表链接", text: $model.url)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if !model.isRunning { model.start() } }
                Button("粘贴") { model.paste() }
            }

            HStack {
                Text("保存到")
                Text(model.destination)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("选择文件夹") { model.chooseDestination() }
                Button("打开文件夹") { model.openDestination() }
            }

            HStack(spacing: 18) {
                Toggle("仅音频（MP3）", isOn: $model.audioOnly)
                    .toggleStyle(.checkbox)
                    .disabled(model.isRunning)
                Spacer()
                Text(model.status)
                    .foregroundStyle(model.status.contains("失败") || model.status.contains("需要") ? .red : .secondary)
                if model.isRunning {
                    Button("取消") { model.cancel() }
                } else {
                    Button("开始下载") { model.start() }
                        .keyboardShortcut(.defaultAction)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.log)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .onChange(of: model.log) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            HStack {
                Spacer()
                Text("© 2026 YCCCC")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary.opacity(0.55))
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 460)
    }
}

@main
struct YTDLPApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
