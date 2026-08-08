# ckey.run 离线复现（本地激活服务）

基于 ja-netfilter / power.jar 原理的 JetBrains 许可证离线激活服务。
许可证由本地 RSA 私钥 + 自签名证书真正签名生成，激活时 IDE 的证书信任链由 power.conf 拦截。

## 目录结构

```
ckey/
├── server/
│   └── local_server.py           # 本地 HTTP 服务器（模拟 ckey.run 端点）
├── web/
│   └── dashboard.html            # 浏览器访问 / 时显示的操作面板
├── scripts/
│   ├── activate.sh               # Linux/Mac 激活脚本（GET / 快捷运行，/export/ 导出）
│   ├── activate.ps1              # Windows 激活脚本（GET / 快捷运行，/export/ 导出）
│   ├── offline_activate.ps1      # Windows 免交互激活脚本（GET /activate /export/）
│   ├── offline_activate.sh       # Linux/Mac 免交互激活脚本（GET /activate /export/）
│   ├── debug.sh                  # Debug 模式脚本（GET /debug /export/）
│   └── uninstall.sh              # 卸载脚本（GET /uninstall /export/）
├── ja-netfilter/                 # ja-netfilter 部署资源（GET /ja-netfilter/*）
│   ├── ja-netfilter.jar
│   ├── config/                   # dns.conf env.conf native.conf power.conf url.conf
│   └── plugins/                  # dns.jar env.jar hideme.jar native.jar power.jar privacy.jar url.jar
├── keys/                         # 本地 RSA 密钥与证书（签名来源）
│   ├── private.pem
│   ├── public.pem
│   └── cert.der
└── README.md
```

## 启动服务器

```bash
python server/local_server.py               # 默认监听 0.0.0.0:10768
python server/local_server.py --port 8080   # 自定义端口
```

端口冲突处理：启动前会先探测端口占用情况，若已被残留实例占用会明确报错并提示
占用进程 PID 及释放命令（`taskkill /F /PID <pid>` / `kill <pid>`）；正常 `Ctrl+C`
停止后端口会立即释放，可马上重启。Windows 下服务以独占端口方式监听，避免残留
旧实例与新实例"双绑"导致请求被旧实例抢走（表现为 404）。

## 一键激活（跨平台）

启动服务器后，浏览器访问 `http://<服务器IP>:10768` 会看到操作面板。
各平台终端也有两种用法：**快捷运行**（不落地脚本，管道直接执行）与
**导出为本地脚本**（先保存文件再运行，适合审阅留档）。

**Windows PowerShell（右键管理员运行）：**

快捷运行（不保存文件）：

```powershell
irm http://localhost:10768 | iex
```

导出为本地脚本（保存后运行）：

```powershell
irm http://localhost:10768/export/activate.ps1 -OutFile activate.ps1; .\activate.ps1
```

**Linux / macOS 终端：**

快捷运行（不保存文件）：

```bash
curl -Ls http://localhost:10768 | bash
```

导出为本地脚本（保存后运行）：

```bash
curl -Ls http://localhost:10768/export/activate.sh -o activate.sh && bash activate.sh
```

> 快捷运行适合临时使用；导出脚本便于先审阅内容再运行。
> `/export/` 导出的 `.ps1` 保留 UTF-8 BOM，Windows PowerShell 5.1 可直接解析。

**免交互批量激活（自动处理本机所有已安装的 JetBrains IDE，无需逐台操作）：**

```powershell
# Windows PowerShell（管理员）
irm http://localhost:10768/export/offline_activate.ps1 -OutFile offline_activate.ps1; .\offline_activate.ps1
```

```bash
# Linux / macOS
curl -Ls http://localhost:10768/export/offline_activate.sh -o offline_activate.sh && bash offline_activate.sh
# 可带参数: [服务器地址] [许可证名称] [过期日期]
#   bash offline_activate.sh http://192.168.1.5:10768 MyName 2099-12-31
```

**一次性导出各平台全部脚本：**

浏览器打开 `http://localhost:10768/scripts.zip`，或：

```bash
curl -Ls http://localhost:10768/scripts.zip -o ckey-scripts.zip
```

zip 内含 Windows 与 Linux/macOS 两端共 6 个脚本（activate / offline_activate /
debug / uninstall）及使用说明，均已改写为本机服务器地址，`.ps1` 保留 UTF-8 BOM。
也可单独下载：`/export/activate.ps1`、`/export/offline_activate.ps1`、
`/export/activate.sh`、`/export/offline_activate.sh`、`/export/debug.sh`、
`/export/uninstall.sh`。

脚本会：下载 ja-netfilter 及插件 → 修改各 IDE 的 .vmoptions 注入 `-javaagent` →
向服务器请求并写入许可证。Linux/macOS 用户级配置目录在
`~/.config/JetBrains`（Linux）/ `~/Library/Application Support/JetBrains`（macOS），
安装目录由 `~/.cache/JetBrains/<IDE>/.home`（Linux）/
`~/Library/Caches/JetBrains/<IDE>/.home`（macOS）定位。

## 激活原理（power.conf）

IDE 校验许可证时计算 `证书签名 ^ 65537 mod JetBrainsCA模数` 以建立证书信任链，
power.jar 把该 `modPow` 替换为 EMSA-PKCS1v15(SHA256(本地证书TBS)) 的结果。
因此 `power.conf` 中：

- 参数1 = 本地证书签名（`int(cert.signature)`）
- 参数2 = 65537
- 参数3 = JetBrains CA 模数（IDE 内置，**不可改动**）
- 参数4 = 替换后的正确结果（`int(EMSA-PKCS1v15(SHA256(cert TBS), k=512))`）

JSON 签名另由 IDE 用证书内嵌公钥按 **RSA-SHA1 + PKCS1v15** 独立校验，
与 power.conf 互不干扰，由本地私钥在生成时完成。

## 依赖

- Python 3.8+，`cryptography` 库（`pip install cryptography`）
- 若本地密钥丢失，可重新生成：`openssl req -x509 -newkey rsa:4096 ...` 放入
  `keys/`（证书 CN 任意，power.conf 参数 1/4 需按上述方式重算）
