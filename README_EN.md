<p align="center">
  <a href="README.md">中文</a> | <strong>English</strong>
</p>

# JetBrains IDE Offline Activation (Local)

Local JetBrains license activation built on the ja-netfilter / power.jar mechanism — **no internet, no online license server needed**.

- **Truly signed licenses**: every license is genuinely signed by a local RSA-4096 private key + self-signed certificate (RSA-SHA1 + PKCS1v15),
  in a format identical to the official one; the IDE's certificate trust chain is intercepted by `power.conf` at activation time, and the `keys/` private key is never committed.
- **Covers 12 IDEs**: IntelliJ IDEA, PyCharm, PhpStorm, GoLand, CLion, WebStorm, Rider,
  DataGrip, RubyMine, AppCode, DataSpell, RustRover — all supported.
- **Three activation methods**: one-click scripts (embedded pre-generated licenses, no Python on the target machine) · interactive scripts (offline / server dual mode) ·
  single-file self-contained offline exports (all resources and licenses embedded, copy to any machine and run).
- **Web dashboard**: the local server serves a browser panel to pick products, generate activation codes / `.key` files, and download offline export scripts.

> For learning and research purposes only. Do not use for commercial or infringing purposes.

## Project Dependencies

Python is only needed on the **machine hosting this repository** (to generate keys, re-embed licenses, and for server mode). The built-in **one-click activation scripts already embed pre-generated licenses, so the target machine needs no Python and no online server**.

- **Python 3.8+** (local machine only): needed to generate keys, re-embed licenses, and run server mode; on Windows it is recommended to check "Add python.exe to PATH" during installation
- **Python dependencies**: `pip install -r requirements.txt` (only `cryptography` is actually required, used only when running `scripts/generate_keys.py` / `scripts/embed_licenses.py` locally; the one-click scripts do not depend on Python)
- **Windows**: PowerShell 5.1+ or CMD, either can activate with one click (the script requests administrator privileges automatically)
- **Linux / macOS**: bash
- The three one-click scripts in this repo embed pre-generated licenses for 12 products (fixed identity: license name `JetBrain`, licensee empty, valid until `2099-12-31`), ready to use out of the box; only after rotating the `keys/` private key do you need to refresh them via "Manual · Re-embed Licenses"

## Supported IDEs

This project supports activating the following JetBrains IDEs ("ID" is the name used by the scripts, "Product Code" is the product code used when issuing licenses):

| IDE | ID | Product Code |
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

## Quick Start (One-Click Activation)

A single command completes the entire flow of "extract embedded licenses → activate IDE", **without starting any server**. The script is idempotent and can be run repeatedly.

**Where to run**: open a terminal in the repository root (`JetBrain_crack/`). The script locates the repository root automatically, so it also works from any location, but running it in the repository root is recommended.

**Windows · PowerShell terminal**

First open a **PowerShell terminal** (search for "PowerShell" in the Start menu), then copy and run:

```powershell
.\scripts\Windows\one-click-activate.ps1
```

> If you get a policy restriction prompt, first run `Set-ExecutionPolicy -Scope Process Bypass` in the terminal, then run the command above.

**Windows · CMD terminal**

First open a **CMD terminal** (search for "Command Prompt" / "CMD" in the Start menu), then copy and run:

```cmd
.\scripts\Windows\one-click-activate.cmd
```

> Both terminals map to the same activation flow; the script automatically triggers a UAC prompt to request administrator privileges. Pick either one.

**Linux / macOS**

Copy and run in a **terminal** (a regular user is fine, no administrator privileges needed):

```bash
bash scripts/Linux-macOS/one-click-activate.sh
```

The script executes in order:

1. **Extract embedded licenses**: extract the pre-generated 12-product `.key` licenses embedded in the script to a temp directory
   (the target machine needs no Python and generates no keys — licenses are pre-issued with a fixed identity);
2. **Activate the IDE**: run `activate.ps1` / `activate.sh` in offline mode — ja-netfilter and its plugins are copied from the local `ja-netfilter/` directory, and the licenses are taken directly from the embedded licenses extracted in step 1, without starting any local server. Select the product as prompted.

> **Tip: when some IDE fails to activate**
>
> 1. You can re-activate using **server mode**: start the local server (`python server/local_server.py`),
>    then run `irm http://localhost:10768 | iex` in an administrator terminal (Windows) /
>    `curl -Ls http://localhost:10768 | bash` (Linux/macOS);
> 2. If some IDE still fails to activate, open the server dashboard at `http://localhost:10768`,
>    generate an **activation code** for the product and paste it manually in the IDE's "Activate License" dialog.

## Directory Structure

```
JetBrain_crack/
├── server/
│   ├── local_server.py            # Local HTTP server (optional backend for manual mode, see "Manual Mode")
│   └── generate_license.py        # Offline license generator (called by activate scripts in offline mode)
├── web/
│   └── dashboard.html             # Dashboard shown when accessing / in server mode
├── scripts/
│   ├── generate_keys.py           # Generate keys/ keys and certificate and calibrate power.conf (offline, idempotent)
│   ├── embed_licenses.py          # Embed pre-generated licenses into the three one-click scripts (re-run after key rotation)
│   ├── Windows/
│   │   ├── one-click-activate.ps1   # Windows one-click activation (PowerShell, embedded pre-generated licenses, offline)
│   │   ├── one-click-activate.cmd   # Windows one-click activation (CMD, embedded pre-generated licenses, offline)
│   │   └── activate.ps1           # Windows interactive activation script (offline / server dual mode)
│   └── Linux-macOS/
│       ├── one-click-activate.sh    # Linux/macOS one-click activation (embedded pre-generated licenses, offline, no server)
│       └── activate.sh            # Linux/macOS interactive activation script (offline / server dual mode)
├── ja-netfilter/                  # ja-netfilter deployment resources (copied from here during offline activation)
│   ├── ja-netfilter.jar
│   ├── config/                    # dns.conf env.conf native.conf power.conf url.conf
│   └── plugins/                   # dns.jar env.jar hideme.jar native.jar power.jar privacy.jar url.jar
├── keys/                          # Local RSA key and certificate (signing source; not committed, see "Manual Mode · Generate Keys")
│   ├── private.pem                #   generated by python scripts/generate_keys.py
│   ├── public.pem
│   └── cert.der
├── requirements.txt               # Python dependency manifest
└── README.md
```

## Manual Mode

### 1. Generate Keys

The `keys/` directory (`private.pem` / `public.pem` / `cert.der`) is excluded by `.gitignore` and is not committed — the repository itself contains no private key. Run the generation script once before the first activation:

```bash
python scripts/generate_keys.py            # Create missing keys/certificate and calibrate power.conf
python scripts/generate_keys.py --force    # Ignore existing files and generate a completely new set
```

The script will:

1. Generate an RSA-4096 private key `keys/private.pem` and public key `keys/public.pem`;
2. Generate a self-signed certificate `keys/cert.der` from that private key. **The certificate issuer CN must be `JetProfile CA`**
   (the IDE uses it as the certificate trust anchor), with subject CN `Jetbrains-Help`; a plain
   `openssl req -x509` will fail certificate chain validation because issuer=subject, so please do not
   replace this script with command-line tools;
3. Recompute **parameter 1** (the certificate signature `int(cert.signature)`) and
   **parameter 4** (EMSA-PKCS1v15(SHA256(cert TBS), k=512)) of `power.conf` from the certificate; **parameter 3 (the JetBrains CA
   modulus, built into the IDE) stays unchanged**, and the original line endings and other content are preserved as-is.

If you activate before generating the keys, the issued licenses will never pass validation — be sure to run this script first before activating.

### 2. Activate the IDE (Offline, Without Starting a Server)

Running the activate script directly in the repository root automatically enters offline mode: the script locates the repository from its own path, copies resources from the local `ja-netfilter/`, and licenses are generated from the local key by `server/generate_license.py`, without starting any local server.

**Windows** (first open a PowerShell terminal, then copy and run):

```powershell
Set-ExecutionPolicy -Scope Process Bypass   # if restricted by execution policy
.\scripts\Windows\activate.ps1
```

**Linux / macOS**:

```bash
bash scripts/Linux-macOS/activate.sh
```

Offline mode detection priority: explicit `OFFLINE_*` environment variables > `-Offline` / `--offline` argument > auto-detection
(script located inside the repository). Generally you don't need to set it manually — the one-click scripts inject the environment variables automatically, and running the activate script directly also goes offline based on the repository location; the `-Offline` / `--offline` arguments are for forcing offline mode (errors if the repository is missing).
If you need to customize the resource directory or Python, you can still set `OFFLINE_*` environment variables manually to override auto-detection.

The script will: copy ja-netfilter and plugins from `ja-netfilter/` → modify each IDE's `.vmoptions` to inject
`-javaagent` → generate a local license and write it. On Linux/macOS the user-level config directory is
`~/.config/JetBrains` (Linux) / `~/Library/Application Support/JetBrains` (macOS),
and the installation directory is located via `~/.cache/JetBrains/<IDE>/.home` (Linux) /
`~/Library/Caches/JetBrains/<IDE>/.home` (macOS).

### 3. (Optional) Server Mode

Start the local server only when you need the browser dashboard:

```bash
python server/local_server.py               # listens on 0.0.0.0:10768 by default
python server/local_server.py --port 8080   # custom port
```

After startup, visit `http://localhost:10768` in a browser to see the dashboard, or pipe it directly to activate:

```powershell
irm http://localhost:10768 | iex          # Windows PowerShell terminal (administrator)
curl -Ls http://localhost:10768 | bash    # Linux / macOS
```

You can also export **self-contained single-file offline scripts** from the server: each exported file embeds the "activation script + ja-netfilter resources +
pre-generated licenses for the 12 products". After downloading it's a standalone file — run it and it automatically extracts and activates offline,
**not dependent on the server being online, not dependent on companion repo files, and the target machine needs no Python**, suitable for copying to other machines. Three formats are supported:

```powershell
irm  http://localhost:10768/export/activate.ps1 -OutFile activate.ps1                  # Windows PowerShell
curl -Ls http://localhost:10768/export/one-click-activate.cmd -o one-click-activate.cmd # Windows CMD
curl -Ls http://localhost:10768/export/activate.sh -o activate.sh                       # Linux / macOS
```

Using Windows CMD as an example (the other two are similar):

```bash
curl -Ls http://localhost:10768/export/one-click-activate.cmd -o one-click-activate.cmd
one-click-activate.cmd
```

When the exported script runs, it first extracts the embedded offline package to a temp directory, sets the offline environment variables, runs the activation, and cleans up the temp files at the end.
The licenses are pre-issued at export time with a fixed identity (license name `JetBrain`, licensee empty, valid until `2099-12-31`),
so during activation the script writes them directly into the IDE config directory — no key generation or license details are needed on the target machine. Target machine requirements:
Windows only needs PowerShell 5.1+ or CMD; Linux / macOS only needs bash (self-extraction also needs the system-provided `base64` and `unzip`).
The `keys/` keys must have been generated on the server machine before exporting, otherwise the endpoint returns 400 asking you to generate the keys first.

Port conflict handling: before startup the port is probed for conflicts; if the occupier is a leftover instance of this service (command line contains
`local_server.py`) it is terminated automatically and the service restarts on the original port; if it's another program, a random available port is used instead and you are informed.

### 4. Re-embed Licenses (After Key Rotation)

The licenses embedded in the one-click scripts are pre-issued with the local `keys/` private key. If you regenerate `keys/`
(`python scripts/generate_keys.py --force`), the previously embedded licenses become invalid and you need to refresh the three one-click scripts:

```bash
python scripts/embed_licenses.py        # embed (default)
python scripts/embed_licenses.py verify # verify that the embedded payload can extract the 12 .key files
```

`embed_licenses.py` re-issues licenses for the 12 products with the current `keys/` (fixed identity: license name `JetBrain`,
licensee empty, valid until `2099-12-31`), packages them as base64 and embeds them into
`scripts/Windows/one-click-activate.ps1`, `one-click-activate.cmd` and
`scripts/Linux-macOS/one-click-activate.sh` — the target machine needs no Python.

## How Activation Works (power.conf)

When the IDE validates a license it computes `certificate signature ^ 65537 mod JetBrainsCAmodel` to establish the certificate trust chain;
power.jar replaces that `modPow` with the result of EMSA-PKCS1v15(SHA256(local certificate TBS)). Therefore in `power.conf`:

- Parameter 1 = local certificate signature (`int(cert.signature)`)
- Parameter 2 = 65537
- Parameter 3 = JetBrains CA modulus (built into the IDE, **must not be changed**)
- Parameter 4 = the correct replaced result (`int(EMSA-PKCS1v15(SHA256(cert TBS), k=512))`)

The JSON signature is separately verified by the IDE with the embedded public key in the certificate using **RSA-SHA1 + PKCS1v15**,
independent of power.conf, and is done by the local private key at generation time.
