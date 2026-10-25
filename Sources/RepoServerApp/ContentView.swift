import SwiftUI
import UIKit

final class ServerModel: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 0
    @Published var servedCount = 0
    @Published var debCount = 0
    @Published var repoBytes: Int64 = 0
    @Published var hasIndex = false
    @Published var addresses: [NetAddress] = []

    private let server = RepoHTTPServer()

    var url: String { "http://127.0.0.1:\(port)" }
    /// 供其他设备访问的源地址（个人热点 / 同一 Wi-Fi 均可）
    var lanURLs: [(String, String, String)] {
        guard port > 0 else { return [] }
        return addresses.map { ($0.label, "http://\($0.ip):\(port)", $0.ifname) }
    }
    var lanURL: String? { lanURLs.first?.1 }

    init() {
        server.onChange = { [weak self] in self?.refresh() }
        server.start()
        refresh()
    }

    func restart() {
        server.start()
        refresh()
    }

    func refresh() {
        isRunning = server.isRunning
        port = server.port
        servedCount = server.requestCount

        let fm = FileManager.default
        var count = 0
        var bytes: Int64 = 0
        let debsDir = server.repoDir.appendingPathComponent("debs")
        if let en = fm.enumerator(at: debsDir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let f as URL in en {
                if f.pathExtension.lowercased() == "deb" {
                    count += 1
                    if let v = try? f.resourceValues(forKeys: [.fileSizeKey]), let s = v.fileSize {
                        bytes += Int64(s)
                    }
                }
            }
        }
        debCount = count
        repoBytes = bytes
        hasIndex = fm.fileExists(atPath: server.repoDir.appendingPathComponent("Packages").path)
            || fm.fileExists(atPath: server.repoDir.appendingPathComponent("dists/stable/Release").path)
        addresses = allIPv4Addresses()
    }

    func openInSileo() {
        let enc = url.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url
        if let u = URL(string: "sileo://source?url=\(enc)") {
            UIApplication.shared.open(u)
        }
    }
}

struct ContentView: View {
    @StateObject private var m = ServerModel()

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("服务状态")) {
                    HStack {
                        Circle()
                            .fill(m.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(m.isRunning ? "运行中 :\(m.port)" : "未启动")
                            .font(.headline)
                        Spacer()
                        Button("重启") { m.restart() }
                            .buttonStyle(.borderless)
                    }
                    HStack {
                        Text("本地源地址")
                        Spacer()
                        Text(m.url).font(.system(.footnote, design: .monospaced))
                        Button("复制") { UIPasteboard.general.string = m.url }
                            .buttonStyle(.borderless).font(.footnote)
                    }
                    if m.lanURLs.isEmpty {
                        HStack {
                            Text("对外地址")
                            Spacer()
                            Text("未连接网络")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(m.lanURLs, id: \.1) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.0).font(.footnote).foregroundColor(.secondary)
                                    Text(item.1).font(.system(.footnote, design: .monospaced))
                                }
                                Spacer()
                                Button("复制") { UIPasteboard.general.string = item.1 }
                                    .buttonStyle(.borderless).font(.footnote)
                            }
                        }
                    }
                    Button("在 Sileo 中打开此源") { m.openInSileo() }
                        .disabled(!m.isRunning)
                }

                Section(header: Text("仓库内容（Documents/Repo）")) {
                    HStack {
                        Text("deb 包数量"); Spacer()
                        Text("\(m.debCount)").font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("包总大小"); Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: m.repoBytes, countStyle: .file))
                    }
                    HStack {
                        Text("apt 索引"); Spacer()
                        Text(m.hasIndex ? "已就绪" : "缺失 — 请先在 PC 生成后导入")
                            .foregroundColor(m.hasIndex ? .green : .orange)
                            .font(.footnote)
                    }
                }

                Section(header: Text("使用步骤")) {
                    Text("1. 电脑端把仓库内容导入 Documents/Repo（爱思助手 → 应用 → 本地源 → 文件）")
                    Text("2. 保持本 App 在前台（iOS 会挂起后台网络）")
                    Text("3. 本机：Sileo 添加「本地源地址」127.0.0.1:8088")
                    Text("4. 其他手机：连同一 Wi-Fi，或连本机的个人热点，Sileo 添加上面的「个人热点 / Wi-Fi」地址即可")
                    Text("5. 连不上时：在对方手机 Safari 里先打开该地址，能列出目录就说明网络通，只是 Sileo 缓存问题（删源重加）")
                }
            }
            .navigationTitle("本地越狱源")
            .onAppear { m.refresh() }
        }
        .navigationViewStyle(.stack)
    }
}
