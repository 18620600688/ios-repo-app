import Foundation
import Network

/// 手机本地源服务器：把 Documents/Repo 目录以 HTTP 形式暴露在 127.0.0.1:8088
/// 支持 GET/HEAD、Range 断点（大 deb 下载必需）、目录自动索引（apt 行为：目录下找 Packages）
final class RepoHTTPServer {
    private var listener: NWListener?
    private(set) var isRunning = false
    private(set) var port: UInt16 = 0
    private(set) var requestCount = 0
    var onChange: (() -> Void)?

    /// 仓库根目录：Documents/Repo —— 爱思助手文件共享可直接往里导入
    let repoDir: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Repo", isDirectory: true)

    func start() {
        stop()
        try? FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        tryStart(port: 8088)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = 0
        notify()
    }

    private func tryStart(port p: UInt16) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: p)!) else {
            if p < 8199 { tryStart(port: p + 1) } else { notify() }
            return
        }
        listener = l
        port = p
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.isRunning = true
            case .failed, .cancelled: self?.isRunning = false
            default: break
            }
            self?.notify()
        }
        l.start(queue: DispatchQueue(label: "repo.http.server", qos: .userInitiated))
    }

    private func notify() {
        DispatchQueue.main.async { self.onChange?() }
    }

    // MARK: - 连接处理

    private func accept(_ conn: NWConnection) {
        conn.start(queue: DispatchQueue(label: "repo.http.conn", qos: .userInitiated))
        readHeader(conn, Data())
    }

    private func readHeader(_ conn: NWConnection, _ buf: Data) {
        if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
            let header = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
            process(header, conn)
            return
        }
        if buf.count > 65536 { conn.cancel(); return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, _ in
            guard let self = self else { conn.cancel(); return }
            guard let d = data, !d.isEmpty, !complete else { conn.cancel(); return }
            var b = buf
            b.append(d)
            self.readHeader(conn, b)
        }
    }

    private func process(_ header: String, _ conn: NWConnection) {
        let lines = header.components(separatedBy: "\r\n")
        guard let first = lines.first else { conn.cancel(); return }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let method = String(parts[0]).uppercased()
        guard method == "GET" || method == "HEAD" else {
            respondError(conn, 405, "Method Not Allowed")
            return
        }
        var rawPath = String(parts[1])
        var headers: [String: String] = [:]
        for l in lines.dropFirst() {
            if let i = l.firstIndex(of: ":") {
                headers[String(l[..<i]).lowercased()] =
                    String(l[l.index(after: i)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if let q = rawPath.firstIndex(of: "?") { rawPath = String(rawPath[..<q]) }
        let path = rawPath.removingPercentEncoding ?? rawPath

        let comps = path.split(separator: "/").map(String.init)
        if comps.contains("..") {
            respondError(conn, 400, "Bad Request")
            return
        }

        var fileURL = repoDir
        for c in comps { fileURL.appendPathComponent(c) }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) else {
            respondError(conn, 404, "Not Found: \(path)")
            return
        }

        if isDir.boolValue {
            // apt 习惯：目录请求 → 找目录下的 Packages
            let pkg = fileURL.appendingPathComponent("Packages")
            if FileManager.default.fileExists(atPath: pkg.path) {
                serve(pkg, conn: conn, method: method, headers: headers)
            } else {
                serveDirectory(fileURL, path: path, conn: conn)
            }
            return
        }
        serve(fileURL, conn: conn, method: method, headers: headers)
    }

    // MARK: - 文件服务（含 Range）

    private func serve(_ url: URL, conn: NWConnection, method: String, headers: [String: String]) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value, size > 0 else {
            respondError(conn, 404, "Not Found")
            return
        }

        var offset: Int64 = 0
        var length = size
        var status = "200 OK"
        var extra = ""
        if let rangeHeader = headers["range"], let r = parseRange(rangeHeader, size) {
            offset = r.lowerBound
            length = r.upperBound - r.lowerBound + 1
            status = "206 Partial Content"
            extra += "Content-Range: bytes \(r.lowerBound)-\(r.upperBound)/\(size)\r\n"
        }

        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType(url.pathExtension.lowercased()))\r\n"
        head += "Content-Length: \(length)\r\n"
        head += "Accept-Ranges: bytes\r\n"
        head += extra
        head += "Connection: close\r\n\r\n"

        conn.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] err in
            guard err == nil else { conn.cancel(); return }
            guard method != "HEAD" else { conn.cancel(); return }
            guard length > 0, let fh = try? FileHandle(forReadingFrom: url) else {
                conn.cancel(); return
            }
            fh.seek(toFileOffset: UInt64(offset))
            self?.streamFile(fh, remaining: length, conn: conn)
        })
        requestCount += 1
        notify()
    }

    private func streamFile(_ fh: FileHandle, remaining: Int64, conn: NWConnection) {
        guard remaining > 0 else { try? fh.close(); conn.cancel(); return }
        let want = Int(min(262_144, remaining))
        guard let data = try? fh.read(upToCount: want), !data.isEmpty else {
            try? fh.close(); conn.cancel(); return
        }
        conn.send(content: data, completion: .contentProcessed { [weak self] err in
            guard err == nil else { try? fh.close(); conn.cancel(); return }
            self?.streamFile(fh, remaining: remaining - Int64(data.count), conn: conn)
        })
    }

    private func parseRange(_ header: String, _ size: Int64) -> ClosedRange<Int64>? {
        guard header.hasPrefix("bytes=") else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let s = parts[0].trimmingCharacters(in: .whitespaces)
        let e = parts[1].trimmingCharacters(in: .whitespaces)
        if s.isEmpty {
            guard let n = Int64(e), n > 0, size > 0 else { return nil }
            return max(0, size - n)...(size - 1)
        }
        guard let a = Int64(s), a < size else { return nil }
        let b = e.isEmpty ? size - 1 : min(Int64(e) ?? size - 1, size - 1)
        guard b >= a else { return nil }
        return a...b
    }

    // MARK: - 目录列表 / 错误页 / MIME

    private func serveDirectory(_ url: URL, path: String, conn: NWConnection) {
        let items = (try? FileManager.default.contentsOfDirectory(at: url)) ?? []
        let base = path.hasSuffix("/") ? path : path + "/"
        let rows = items
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { "<li><a href=\"\(base)\($0.lastPathComponent)\">\($0.lastPathComponent)</a></li>" }
            .joined()
        let body = "<html><head><meta charset=\"utf-8\"><title>Repo</title></head><body><h3>\(path)</h3><ul>\(rows)</ul></body></html>"
        respondHTML(conn, body)
    }

    private func respondError(_ conn: NWConnection, _ code: Int, _ msg: String) {
        respondHTML(conn, "<html><body><h3>\(code) \(msg)</h3></body></html>", status: "\(code) \(msg)")
    }

    private func respondHTML(_ conn: NWConnection, _ body: String, status: String = "200 OK") {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    private func contentType(_ ext: String) -> String {
        switch ext {
        case "deb": return "application/vnd.debian.binary-package"
        case "gpg": return "application/pgp-signature"
        case "pem": return "application/x-pem-file"
        case "gz": return "application/gzip"
        case "xz": return "application/x-xz"
        case "bz2": return "application/x-bzip2"
        case "html", "htm": return "text/html; charset=utf-8"
        case "txt": return "text/plain; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }
}
