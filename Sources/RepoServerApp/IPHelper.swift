import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// 一个可被其他设备访问的 IPv4 地址
struct NetAddress: Identifiable {
    let ip: String
    let ifname: String
    var id: String { ifname + ip }

    /// 网络类型说明（个人热点 / Wi-Fi / 有线 / 蜂窝）
    var label: String {
        if ifname.hasPrefix("bridge") { return "个人热点" }
        if ifname.hasPrefix("en") { return "Wi-Fi" }
        if ifname.hasPrefix("pdp_ip") || ifname.hasPrefix("pdp") { return "蜂窝（一般连不上）" }
        return "其他网卡"
    }

    /// 排序权重：热点 > Wi-Fi > 其他有线 > 蜂窝
    var weight: Int {
        if ifname.hasPrefix("bridge") { return 0 }
        if ifname.hasPrefix("en") { return 1 }
        if ifname.hasPrefix("pdp") { return 9 }
        return 5
    }
}

/// 枚举本机所有可用的 IPv4 地址（含个人热点的 bridge100，即 172.20.10.1）
func allIPv4Addresses() -> [NetAddress] {
    var addrList: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrList) == 0, let first = addrList else { return [] }
    defer { freeifaddrs(addrList) }

    var out: [NetAddress] = []
    var seen = Set<String>()
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let p = ptr {
        let ifa = p.pointee
        if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
            let name = String(cString: ifa.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(MemoryLayout<sockaddr_in>.size)
            if getnameinfo(sa, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.isEmpty && !ip.hasPrefix("127.") && !seen.contains(ip) {
                    seen.insert(ip)
                    out.append(NetAddress(ip: ip, ifname: name))
                }
            }
        }
        ptr = ifa.ifa_next
    }
    return out.sorted { ($0.weight, $0.ip) < ($1.weight, $1.ip) }
}

/// 取一个最适合给其他设备用的地址（热点优先，其次 Wi-Fi）
func preferredLANAddress() -> NetAddress? {
    allIPv4Addresses().first
}

/// 兼容旧调用：返回首选 IPv4 字符串
func lanIPv4Address() -> String? {
    preferredLANAddress()?.ip
}
