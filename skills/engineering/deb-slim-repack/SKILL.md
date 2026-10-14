---
name: deb-slim-repack
description: 对一个 .deb 软件包做瘦身重打包——下载指定版本的 deb、对照本机已安装版本、用 ldd/strings/apt 实测移除不必要的 Depends/Recommends 与非本平台载荷（多余 locale、win32/darwin 二进制）、重新 dpkg-deb 打包并安装到本机。Use when the user says "下载XX的deb", "对照本机移除不必要的依赖", "重新pack", "瘦身重打包 deb", "repack slim deb", or wants to trim/repack/install a .deb package locally.
---

# Deb Slim Repack

把一个官方（或第三方）.deb 拆开，实测哪些依赖和载荷用不上，裁剪后重打包安装。

## Instructions

### Step 1: 定位并下载 .deb

- 已安装包信息：`dpkg -s <pkg>`（Version / Depends / Recommends / Installed-Size），`dpkg -L <pkg>` 看文件清单。
- 用户给了 URL 就直接 `curl -L -o pkg.deb <url>`。
- 若用户只说"下载某软件最新版"且它是 Electron/腾讯系应用，先试更新接口，例如 WorkBuddy：
  `curl -s "https://copilot.tencent.com/v2/update?platform=workbuddy-linux-x64-deb"` → 取 `.url` 字段。
- 记录官方包的 `dpkg-deb -I pkg.deb` 输出作为对照基线。

### Step 2: 解包并对照本机版本

```bash
dpkg-deb -x pkg.deb extracted/          # 数据
dpkg-deb -e pkg.deb extracted/DEBIAN    # control + 维护脚本
du -sk extracted/opt | cut -f1          # 新版 Installed-Size 基准
```

对照本机：`du -sh` 同级目录、文件数（`find ... | wc -l`）、locale 数、`.node` 清单。本机若有历史 slim 版（control Description 里带 "slim" 字样），它就是载荷裁剪的参照物。

### Step 3: 实测依赖（决定 Depends/Recommends 怎么改）

用 `scripts/analyze-deps.sh <ELF文件...>` 或手动三查：

1. **链接依赖**：`ldd bin | awk '{print $1}' | grep '^lib'` — NEEDED 的必留。
   反例：`libasound2` 常被官方包漏写（ldd 有、Depends 无）→ 应补上。
2. **dlopen 依赖**：`strings bin | grep -oE 'lib[a-zA-Z0-9_.-]+\.so(\.[0-9]+)*'` —
   运行时加载的也要留（Electron 典型：`libnotify.so.4`、`libsecret-1.so.0`）。
   无任何字符串引用的 `libxss1`/`libxtst6`/`libuuid1` 可移除。
3. **传递冗余**：`apt-cache depends <pkg>` / `apt-cache rdepends --installed <pkg>` —
   会被 gtk3 等已声明依赖链带入的（如 `libatspi2.0-0`、`libuuid1`）可从 Depends 移除。
4. **Recommends 里的大块头**（如 `imagemagick`）：先 `grep -aoiE '<关键词>' resources/app.asar` 找真实调用证据，
   只匹配到无关文本（如内嵌 Emacs lisp）→ 移除。
5. 托盘类依赖写成提供者择一：`libayatana-appindicator3-1 | libappindicator3-1`（现代 Ubuntu/Mint 只有 ayatana）。

拿不准的依赖（疑似 X11 扩展类）宁可保留，运行期崩了代价更大。

### Step 4: 载荷裁剪（对照本机 slim 版）

在 `extracted/opt/<App>/` 下（模式已在 scripts/slim-payload.sh 中实现）：

- **locales**：只留 `en-GB en-US zh-CN zh-TW`（55→4，约 40MB）。
- **跨平台 `.node` 二进制**：只留本架构 linux-x64（`x64-linux`、`linux_x64`、`build/Release`）。
  删除：`*/prebuilds/{win32*,darwin*}`、`koffi/build/koffi/*` 非 linux_x64、`@lydell/node-pty-{win32*,darwin*}`、
  `fsevents`、`cli/bin/native/win32*`。
- **纯 win/mac 的 prebuilds 目录**（如 weixinpay 的 darwin/win32 dll）：整个删。
- **构建中间产物**：`better-sqlite3/build/Release/obj.target`。
- 源码/头文件（*.h、*.c、xcframework 源码）体积小且本机 slim 也保留 → 不动。
- 校验：`find <root> -name '*.node' | grep -viE 'linux[-_]?x64|x64-linux|build/Release'` 应为空。

### Step 5: 改 control 并重建元数据

编辑 `extracted/DEBIAN/control`：

- `Version: <上游版本>+slim1`（与本机旧 slim 版同风格）。
- `Depends` 用 Step 3 结论；`Recommends` 按需精简。
- Description 追加一行注明做了哪些裁剪。

重建元数据（**必须做**，否则 md5sums 全错）：

```bash
cd extracted && find opt -type f -print0 | xargs -0 md5sum > DEBIAN/md5sums   # 相对路径!
size=$(du -sk opt | cut -f1) && sed -i "s/^Installed-Size:.*/Installed-Size: $size/" DEBIAN/control
chmod 755 DEBIAN/postinst DEBIAN/prerm DEBIAN/preinst DEBIAN/postrm 2>/dev/null
```

维护脚本（杀进程、apparmor、setuid sandbox）直接沿用官方的，不要改。

### Step 6: 打包

```bash
dpkg-deb -Zxz --root-owner-group -b extracted <pkg>_<ver>+slim1_amd64.deb
dpkg-deb -I <新deb> | head -25     # 核对 Depends/Installed-Size/md5sums 行数
dpkg-deb -c <新deb> | head -30     # 抽查内容
```

### Step 7: 安装（先征得用户确认）

- `pgrep -af '/opt/<App>'` 检查是否在运行；安装会触发官方 preinst 杀进程 → **必须先问用户**。
- `sudo dpkg -i <新deb>`（需要时用 interactive 模式让用户输密码）。
- 安装后验证：`dpkg -s <pkg> | grep -E 'Version|Depends'`、抽查裁剪项（locale 数等）、`dpkg -V <pkg>`。

### Step 8: 补注册 CLI 入口

官方新版 postinst 常不再注册 `update-alternatives`，升级后 `/usr/bin/<cmd>` 可能消失：

```bash
command -v <cmd> || sudo update-alternatives --install /usr/bin/<cmd> <cmd> /opt/<App>/<cmd> 200
```

## Examples

- 用户："下载 deepin 版 workbuddy，对照本机移除不必要的依赖，重新 pack 安装" →
  Step 1 取官方 update 接口 URL → Step 2 解包对照 → Step 3 砍掉 libxss1/libxtst6/libuuid1/libatspi2.0-0 与 imagemagick、
  补 libasound → Step 4 只留 4 个 locale + linux-x64 .node → Step 5-6 打出 `5.6.2+slim1` →
  确认后 Step 7 安装 → Step 8 恢复 alternatives。
- 任意其它 .deb 的瘦身：同一套流程，Step 1 换成用户给的 URL。

## Troubleshooting

- `xargs: invalid option -- 'f'` → GNU xargs 没有 `-f`，批量删除写 `for d in *; do rm -rf "$d"; done` 或 `xargs -r rm -rf`。
- md5sums 里出现绝对路径 → 生成时没先 `cd extracted`，必须用相对路径 `find opt ...`。
- 安装后 `command -v <cmd>` 找不到 → 见 Step 8，旧包用 alternatives 建的链接在升级时可能被清掉。
- 装完缺库崩溃 → 用 `ldd` 复查被砍掉的依赖，把误砍的加回 control 重新走 Step 5-7（版本号 +slim2）。
- 官方 update 接口返回 invalid platform → 换平台值（linux-x64-deb / linux-arm64-deb / linux-x64-rpm），或让用户提供直接 URL。
