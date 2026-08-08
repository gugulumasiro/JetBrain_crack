# JetBrains IDE离线激活（本地）

基于 ja-netfilter / power.jar 原理的 JetBrains 许可证离线激活。
许可证由本地 RSA 私钥 + 自签名证书真正签名生成，激活时 IDE 的证书信任链由 power.conf 拦截。

> 仅供学习研究使用，请勿用于商业或侵权用途。

## 项目依赖

- **Python 3.8+**：生成密钥与离线许可证时需要；Windows 安装时建议勾选 “Add python.exe to PATH”
- **Python 依赖**：`pip install -r requirements.txt`（实际仅需要 `cryptography`，一键脚本会自动安装）
- **Windows**：PowerShell 5.1+ 或 CMD，二者均可一键激活（脚本会自动申请管理员权限）
- **Linux / macOS**：bash
- 首次使用前先生成 `keys/`（见「手动方式 · 生成密钥」；一键激活脚本会自动完成这一步）

## 支持的 IDE

本项目支持激活以下 JetBrains IDE（“标识”为脚本内使用的名称，“产品代码”为签发许可证时使用的产品代码）：

| IDE | 标识 | 产品代码 |
| --- | --- | --- |
| IntelliJ IDEA | `idea` | `II,PCWMP,PSI` |
| CLion | `clion` | `CL,PSI,PCWMP` |
| PhpStorm | `phpstorm` | `PS,PCWMP,PSI` |
| GoLand | `goland` | `GO,PSI,PCWMP` |
| PyCharm | `pycharm` | `PC,PSI,PCWMP` |
| WebStorm | `webstorm` | `WS,PCWMP,PSI` |
| Rider | `rider` | `RD,PDB,PSI,PCWMP` |
| DataGrip | `datagrip` | `DB,PSI,PDB` |
| RubyMine | `rubymine` | `RM,PCWMP,PSI` |
| AppCode | `appcode` | `AC,PCWMP,PSI` |
| DataSpell | `dataspell` | `DS,PSI,PDB,PCWMP` |
| RustRover | `rustrover` | `RR,PSI,PCWP` |

## 快速开始（一键激活）

一条命令完成「生成密钥 → 激活 IDE」全流程，**全程不启动服务器**，脚本幂等，可重复运行。

**在哪运行**：在仓库根目录（`JetBrain_crack/`）打开终端运行。脚本会自动定位到仓库根目录，
因此从任一位置运行也能工作，但推荐在仓库根目录执行。

**Windows · PowerShell 终端**

先打开 **PowerShell 终端**（开始菜单搜索 “PowerShell” 打开即可），然后复制执行：

```powershell
.\scripts\Windows\one-click-activate.ps1
```

> 若提示执行策略限制，先在终端执行 `Set-ExecutionPolicy -Scope Process Bypass`，再运行上面的命令。

**Windows · CMD 终端**

先打开 **CMD 终端**（开始菜单搜索 “命令提示符” / “CMD” 打开即可），然后复制执行：

```cmd
.\scripts\Windows\one-click-activate.cmd
```

> 两种终端对应同一个激活流程，脚本会自动弹出 UAC 请求获取管理员权限，任选其一即可。

**Linux / macOS**

在 **终端** 中复制执行（普通用户即可，无需管理员权限）：

```bash
bash scripts/Linux-macOS/one-click-activate.sh
```

脚本会按顺序执行：

1. **生成/补齐密钥**：运行 `scripts/generate_keys.py`，生成 RSA 私钥、证书并校准 `power.conf`
   （幂等，已有密钥则跳过，不影响之前激活过的 IDE）；
2. **激活 IDE**：以离线方式执行 `activate.ps1` / `activate.sh`——ja-netfilter 及插件从仓库
   本地 `ja-netfilter/` 复制，许可证由本地密钥经 `server/generate_license.py` 离线生成，
   全程不启动本地服务器。按提示选择产品并填写许可证信息即可。

> **提示：部分 IDE 激活失败时**
>
> 1. 可改用**服务器模式**重新激活：启动本地服务器（`python server/local_server.py`），
>    再在管理员终端执行 `irm http://localhost:10768 | iex`（Windows）/
>    `curl -Ls http://localhost:10768 | bash`（Linux/macOS）；
> 2. 若执行后仍有个别 IDE 未激活成功，打开服务器操作面板 `http://localhost:10768`，
>    为对应产品生成**激活码**并复制，在 IDE 的「激活许可证」界面手动粘贴激活。

## 目录结构

```
JetBrain_crack/
├── server/
│   ├── local_server.py            # 本地 HTTP 服务器（手动方式的可选后端，见「手动方式」）
│   └── generate_license.py        # 离线许可证生成器（activate 脚本离线模式调用）
├── web/
│   └── dashboard.html             # 服务器模式浏览器访问 / 时显示的操作面板
├── scripts/
│   ├── generate_keys.py           # 生成 keys/ 密钥与证书并校准 power.conf（离线，幂等）
│   ├── Windows/
│   │   ├── one-click-activate.ps1   # Windows 一键激活（PowerShell，含密钥生成，离线）
│   │   ├── one-click-activate.cmd   # Windows 一键激活（CMD，含密钥生成，离线）
│   │   └── activate.ps1           # Windows 交互式激活脚本（离线 / 服务器双模式）
│   └── Linux-macOS/
│       ├── one-click-activate.sh    # Linux/macOS 一键激活（含密钥生成，离线，不启动服务器）
│       └── activate.sh            # Linux/macOS 交互式激活脚本（离线 / 服务器双模式）
├── ja-netfilter/                  # ja-netfilter 部署资源（离线激活时从此目录复制）
│   ├── ja-netfilter.jar
│   ├── config/                    # dns.conf env.conf native.conf power.conf url.conf
│   └── plugins/                   # dns.jar env.jar hideme.jar native.jar power.jar privacy.jar url.jar
├── keys/                          # 本地 RSA 密钥与证书（签名来源；不入库，见「手动方式 · 生成密钥」）
│   ├── private.pem                #   由 python scripts/generate_keys.py 生成
│   ├── public.pem
│   └── cert.der
├── requirements.txt               # Python 依赖清单
└── README.md
```

## 手动方式

### 1. 生成密钥

`keys/` 目录（`private.pem` / `public.pem` / `cert.der`）已在 `.gitignore` 中排除、不入库，
仓库本身不包含任何私钥。首次激活前运行一次生成脚本：

```bash
python scripts/generate_keys.py            # 缺失时补齐密钥/证书，并校准 power.conf
python scripts/generate_keys.py --force    # 忽略已有文件，全新生成一套
```

脚本会：

1. 生成 RSA-4096 私钥 `keys/private.pem` 与公钥 `keys/public.pem`；
2. 用该私钥生成自签名证书 `keys/cert.der`。**证书 issuer CN 必须为 `JetProfile CA`**
   （IDE 以此作为证书信任锚点），subject CN 为 `Jetbrains-Help`；用普通
   `openssl req -x509` 生成会因 issuer=subject 而无法通过证书链校验，请不要用
   命令行工具替代本脚本；
3. 依据证书重算 `power.conf` 的**参数1**（证书签名 `int(cert.signature)`）与
   **参数4**（EMSA-PKCS1v15(SHA256(cert TBS), k=512)）；**参数3（JetBrains CA
   模数，IDE 内置）保持不变**，原文件行尾与其它内容原样保留。

若在生成密钥之前激活，签发的许可证将永远无法通过校验，请务必先跑一遍本脚本再激活。

### 2. 激活 IDE（离线，不启动服务器）

在仓库根目录直接运行 activate 脚本即自动进入离线模式：脚本按自身路径定位仓库，
从本地 `ja-netfilter/` 复制资源，许可证由本地密钥经 `server/generate_license.py` 生成，
全程不启动本地服务器。

**Windows**（先打开 PowerShell 终端，再复制执行）：

```powershell
Set-ExecutionPolicy -Scope Process Bypass   # 若受执行策略限制
.\scripts\Windows\activate.ps1
```

**Linux / macOS**：

```bash
bash scripts/Linux-macOS/activate.sh
```

离线模式判定优先级：显式 `OFFLINE_*` 环境变量 > `-Offline` / `--offline` 参数 > 自动检测
（脚本位于仓库内）。一般无需手动设置——一键脚本会自动注入环境变量，直接运行 activate 脚本
也会按仓库位置自动离线；`-Offline` / `--offline` 参数用于强制离线（仓库缺失时报错）。
如需自定义资源目录或 Python，仍可手动设置 `OFFLINE_*` 环境变量覆盖自动检测。

脚本会：从 `ja-netfilter/` 复制 ja-netfilter 及插件 → 修改各 IDE 的 .vmoptions 注入
`-javaagent` → 生成本地许可证并写入。Linux/macOS 用户级配置目录在
`~/.config/JetBrains`（Linux）/ `~/Library/Application Support/JetBrains`（macOS），
安装目录由 `~/.cache/JetBrains/<IDE>/.home`（Linux）/
`~/Library/Caches/JetBrains/<IDE>/.home`（macOS）定位。

### 3.（可选）服务器模式

需要浏览器操作面板时再启动本地服务器：

```bash
python server/local_server.py               # 默认监听 0.0.0.0:10768
python server/local_server.py --port 8080   # 自定义端口
```

启动后浏览器访问 `http://localhost:10768` 可看到操作面板，也可用管道直接执行激活：

```powershell
irm http://localhost:10768 | iex          # Windows PowerShell 终端（管理员）
curl -Ls http://localhost:10768 | bash    # Linux / macOS
```

也可以从服务器导出脚本到本地再运行（服务器支持导出 `one-click-activate.cmd`）：

```bash
curl -Ls http://localhost:10768/export/one-click-activate.cmd -o one-click-activate.cmd
one-click-activate.cmd
```

端口冲突处理：启动前会先探测端口占用情况，若占用者是本服务残留实例（命令行含
`local_server.py`）会自动结束并用原端口重启；若是其它程序则改用随机可用端口启动并告知。

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
