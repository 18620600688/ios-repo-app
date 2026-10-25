import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// 获取本机 Wi-Fi（en0）的局域网 IPv4 地址，供其他设备访问本机源服务。
func lanIPv4Address() -> String? {
    var addrList: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrList) == 0, let first = addrList else { return nil }
    defer { freeifaddrs(addrList) }

    var result: String?
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let p = ptr {
        let ifa = p.pointee
        let family = ifa.ifa_addr.pointee.sa_family
        if family == UInt8(AF_INET) {
            let name = String(cString: ifa.ifa_name)
            if name.hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let len = socklen_t(MemoryLayout<sockaddr_in>.size)
                if getnameinfo(ifa.ifa_addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if !ip.hasPrefix("127.") && !ip.isEmpty {
                        result = ip
                        break
                    }
                }
            }
        }
        ptr = ifa.ifa_next
    }
    return result
}
