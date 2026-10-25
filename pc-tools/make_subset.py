# -*- coding: utf-8 -*-
"""从 F:\\越狱源 挑一批 deb 生成「手机仓库」，索引/签名一并备好，供爱思导入 iOS App 的 Documents/Repo。

用法（在 F:\\越狱源\\tools 下运行）：
  python make_subset.py <输出目录> [包含关键词1 关键词2 ...] [--max 20M] [--limit 500]

示例：
  python make_subset.py D:\\phone-repo --max 20M --limit 300        # 最小的 300 个包
  python make_subset.py D:\\phone-repo --max 50M 破解 主题 工具     # 按关键词挑选
不传关键词/limit 则打包全部 <=max 的包（注意手机存储！）
"""
import sys, os, json, shutil

TOOLS = r"F:\越狱源\tools"
sys.path.insert(0, TOOLS)
import launcher  # noqa: E402


def parse_args(argv):
    out_dir = None
    kws = []
    max_bytes = None
    limit = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--max":
            i += 1
            v = argv[i].upper()
            mult = 1
            if v.endswith("M"):
                mult = 1024 * 1024; v = v[:-1]
            elif v.endswith("G"):
                mult = 1024 * 1024 * 1024; v = v[:-1]
            max_bytes = float(v) * mult
        elif a == "--limit":
            i += 1
            limit = int(argv[i])
        elif out_dir is None:
            out_dir = a
        else:
            kws.append(a)
        i += 1
    return out_dir, kws, max_bytes, limit


def main():
    out_dir, kws, max_bytes, limit = parse_args(sys.argv[1:])
    if not out_dir:
        print(__doc__)
        return
    src_debs = os.path.join(launcher.__dict__.get("DEFAULT_ROOT", r"F:\越狱源"), "debs")
    out_debs = os.path.join(out_dir, "debs")
    os.makedirs(out_debs, exist_ok=True)

    cand = []
    for f in os.listdir(src_debs):
        p = os.path.join(src_debs, f)
        if not os.path.isfile(p) or not f.lower().endswith(".deb"):
            continue
        size = os.path.getsize(p)
        if max_bytes and size > max_bytes:
            continue
        if kws and not any(k.lower() in f.lower() for k in kws):
            continue
        cand.append((size, p))
    cand.sort()
    if limit:
        cand = cand[:limit]

    total = sum(s for s, _ in cand)
    print("待导出 %d 个包，共 %.2f GB -> %s" % (len(cand), total / 1e9, out_dir))
    for i, (_, p) in enumerate(cand):
        dst = os.path.join(out_debs, os.path.basename(p))
        if not os.path.exists(dst):
            shutil.copy2(p, dst)
        if (i + 1) % 200 == 0:
            print("  复制 %d/%d" % (i + 1, len(cand)))
    print("复制完成，开始建索引...")
    ok, skipped, archs = launcher.build_index(out_dir, log=lambda *_: None)
    print("INDEX: ok=%d skipped=%d archs=%s" % (ok, skipped, archs))

    # 公钥/签名文件带齐
    root = launcher.__dict__.get("DEFAULT_ROOT", r"F:\越狱源")
    for f in ("tunan.gpg", "repo.pubkey", "Release.gpg", "InRelease"):
        src = os.path.join(root, f)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(out_dir, f))
    print("完成。把 %s 整个目录内容导入 iOS App 的 Documents/Repo 即可。" % out_dir)


if __name__ == "__main__":
    main()
