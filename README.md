# 本地越狱源 · iOS App（最低 iOS 14）

手机自带一个源服务器：电脑上把仓库内容用**爱思助手**直接推进 App 的 Documents/Repo，
App 内嵌 HTTP 服务（127.0.0.1:8088），同机 Sileo 加这个地址即可离线装包——
**不依赖电脑、不依赖家里 Wi-Fi。**

---

## 一、出 IPA 包（Windows 上无法编译 iOS，用 GitHub 云端 Mac，5 分钟）

1. 仓库页 → **Actions** 标签 → 等 "Build iOS IPA" 跑完（约 2~3 分钟）
2. 进该次运行 → **Artifacts** → 下载 `RepoServer-ipa` → 解压得 `RepoServer.ipa`

> 构建方式：纯 SwiftPM 交叉编译（`swift build --destination` 指向 iphoneos SDK + `-static-stdlib`），无 Xcode 工程文件，产出二进制后手工拼 `Payload/RepoServer.app` 打成未签名 IPA。

## 二、安装

| 设备 | 方式 |
|---|---|
| iPhone 7 · iOS 14.7.1（有 TrollStore） | **TrollStore 直接装未签名 ipa**，无需证书、永不过期 |
| iOS 18 设备（无 TrollStore） | 爱思助手自签安装（免费证书 7 天一续）；或者干脆不装 App，直接 Sileo 加电脑源 `http://192.168.5.168:8088` |

## 三、导入仓库内容（爱思助手）

App 已开启文件共享，爱思里能看到它的文档目录：

1. 爱思助手 → 我的应用 → 找到「本地源」→ 文件管理 → `Documents/`
2. 新建 `Repo` 文件夹，把 PC 上准备好的仓库内容整个拖进去，应长这样：
   ```
   Documents/Repo/
   ├─ debs/            ← deb 包
   ├─ dists/           ← 新式索引
   ├─ Packages(.gz/.xz/.bz2)
   ├─ Release / Release.gpg / InRelease
   └─ tunan.gpg
   ```
3. 回到 App，界面会显示 deb 数量和"apt 索引：已就绪"

**只导一部分包？** 用 PC 脚本先做子集仓库（自动建索引）：
```
cd F:\越狱源\tools
python "D:\workbuddy\2026-10-23-23-07-38\ios-repo-app\pc-tools\make_subset.py" D:\phone-repo --max 20M --limit 300
```
然后把 `D:\phone-repo` 里的内容拖进 Documents/Repo。（手机存储有限，建议 ≤ 10 GB）

## 四、Sileo 使用

1. 手机上打开本 App，保持**前台**（iOS 会挂起后台 App 的网络，锁屏前先去 Sileo 操作）
2. Sileo → 软件源 → 添加 → `http://127.0.0.1:8088`（也可点 App 里的"在 Sileo 中打开此源"）
3. 刷新即可安装，和远程源体验一致

> 注意：未越狱设备装不了 Sileo，此 App 主要面向越狱机 / TrollStore 机的 Sileo 使用场景。

## 五、常见问题

- **刷新源报 hash 不匹配**：导入内容后索引是旧的 → 重跑 `make_subset.py` 或在 PC 全量重建索引后重新导入 `dists/`、`Packages*`、`Release*`
- **App 里显示"apt 索引缺失"**：说明只导了 deb 没导索引文件，按上一条处理
- **8088 被占**：App 会自动尝试 8088→8199，以界面显示的端口为准
- **换手机/重装 App**：Documents 会被清空，需重新导入

## 目录说明

```
├─ Package.swift                # SwiftPM 包定义（最低 iOS 14.0，纯 SwiftPM 无 Xcode 工程）
├─ AppInfo/Info.plist           # .app 打包用清单
├─ Sources/RepoServerApp/
│  ├─ RepoServerApp.swift       # 入口（@main SwiftUI App）
│  ├─ ContentView.swift         # 界面：状态/包数/一键进 Sileo
│  └─ Server.swift              # 内嵌 HTTP 服务器（Range 断点、目录索引、MIME）
├─ .github/workflows/build.yml  # GitHub Actions 云端打包（SwiftPM → 未签名 IPA）
└─ pc-tools/make_subset.py      # PC 端子集仓库生成器
```
