# OpenWRT-CI（自用云编译）

自用 OpenWrt 云编译仓库。当前主力维护两台设备，但**四条产品线的通用配置全部保留**，
随时可以扩展其他机型。

| 线 | 工作流 | 覆盖 | 源码分支 |
|---|---|---|---|
| QCA | `QCA-ALL.yml` | IPQ60XX（**亚瑟 + 兆能 M2**） | `VIKINGYFY/immortalwrt` @ `main` |
| QCB | `QCB-ALL.yml` | IPQ53XX-WIFI-NO / IPQ95XX-WIFI-YES | 同 @ `owrt` |
| MTK | `MTK-ALL.yml` | MEDIATEK-WIFI-YES / WIFI-NO | 同 @ `owrt` |
| OWRT | `OWRT-ALL.yml` | AIROHA-WIFI-NO / ROCKCHIP / X86 | 同 @ `owrt` |

现有两台设备（IPQ6 系里单独拉出来精修的两个配置）：

| 机型 | 配置 | 硬件 | 形态 |
|---|---|---|---|
| 京东云亚瑟 AX1800 Pro / RE-SS-01 | `Config/IPQ60XX-JDCLOUD.txt` | IPQ6000，硬改 1G RAM + 64G eMMC | 带 WiFi |
| 兆能 ZN-M2 | `Config/IPQ60XX-ZNM2-WIFI-NO.txt` | IPQ6000，512MB RAM + 128MB NAND | 无 WiFi，纯路由 / USB 网卡 WAN |

---

## 血统与组合方式

骨架 fork 自 **krisxu23/OpenWRT-CI**（VIKINGYFY/OpenWRT-CI 的亚瑟精简版），再整合另外两家：

1. **骨架：krisxu23** —— 薄壳矩阵 + 公用编译核心 `WRT-CORE.yml`，脚本拆成
   `Packages.sh`（拉包）/ `Handles.sh`（修 feeds、注入 files）/ `Settings.sh`（改系统设置）。
   选它的理由是自带 **`Scripts/USB-WAN.sh` + `files/` 注入机制**，
   兆能 M2 无 WiFi，正好当 USB 网卡 WAN 的小主机（详见 `USB-WAN.md`）。
2. **通用配置：darkrain88** —— 保留它全套通用设备配置（IPQ53XX / IPQ95XX / IPQ807X /
   MEDIATEK / ROCKCHIP / X86），以及新增无 WiFi 机型时的设备清单写法。
3. **按需拉包 + 克隆重试 + 源码溯源 + IPQ 调参：laipeng668** —— 移植自
   `Roc-script.sh`，见下两节。

---

## 三个关键机制

### 按需拉包（`Scripts/Packages.sh`）

原来每个 `UPDATE_PACKAGE` 都无条件 clone 一次 GitHub 仓库，30 个包 30 次网络请求，
任何一个上游挂掉整构建就失败。现在改成：

```
Config/<机型>.txt → Config/GENERAL.txt → Config/<机型>-OVERRIDE.txt
                          ↓ 一次 awk 扫描，建"已启用包名"索引
              UPDATE_PACKAGE_OPT 逐个对照，没选中的直接跳过
```

- 实测：亚瑟拉 **16** 个包，兆能 M2 只拉 **7** 个包。
- 读不到任何配置文件时**退化为全量拉包**，不会因解析失败漏包。
- 主题（`WRT_THEME`）与 `viking` 仓库例外，始终拉取：主题由 `Settings.sh` 后期才写进
  `.config`，`viking` 则同时提供 homeproxy / gecoosac / wolultra / sing-box，按它自己的
  名字匹配不到。
- 想让某个包被拉下来，在机型配置里写一行 `CONFIG_PACKAGE_luci-app-xxx=y` 即可。

### 机型覆盖文件（`Config/<机型>-OVERRIDE.txt`）

`GENERAL.txt` 是两台机器共用的基座，但 64G eMMC 和 128MB NAND 不可能用同一份插件清单。
覆盖文件在 `.config` **末尾**追加，优先级高于 `GENERAL.txt`，可以把用不到的包关成 `=n`。
它同时参与按需拉包的判断 —— 关掉的包连 clone 都省了。

### IPQ 专属调参（`Scripts/Settings.sh`）

来自 laipeng668 的两个"手动旋钮"，原仓库里是注释掉的，这里改成**由机型配置里的标记驱动**，
调参跟着机型走，不用改脚本。标记以行首 `# @` 开头：

```ini
# @WRT_Q6_REGION=0x02000000   # NSS 预留内存 → 32MB
# @WRT_CPU_UV=950000          # 1.5GHz 档电压 → 0.95V
```

| 标记 | 作用 | 默认值 | 可选值 |
|---|---|---|---|
| `@WRT_Q6_REGION` | NSS 的 q6_region 内存预留 | `ipq6018.dtsi` 85MB / `ipq6018-512m.dtsi` 55MB | `0x01000000`=16MB、`0x02000000`=32MB、`0x04000000`=64MB、`0x06000000`=96MB |
| `@WRT_CPU_UV` | 1.5GHz 频率档电压 | 937500（0.9375V） | 一般提到 950000（0.95V） |

- **带 WiFi 至少留 54MB**，无 WiFi 机型才适合调小。
- 兆能 M2 已启用 `0x02000000`（55MB → 32MB，多留 ~23MB 给系统）。
- 两个标记默认不写 = 不生效；找不到对应文件/匹配行也只是跳过，不会让构建失败。

### 克隆重试与源码溯源

- `clone_with_retry`：单个仓库失败最多重试 3 次（退避 2s / 4s）。
- `record_git_revision`：第三方包的 `仓库 / 分支 / commit` 写进 `third-party-sources.txt`，
  随固件上传 Release，便于回溯"这版到底编了哪个提交"。

---

## 目录结构

```
.github/workflows/
  WRT-CORE.yml    公用编译核心（唯一真正干活的工作流，其余全是薄壳）
  QCA-ALL.yml     薄壳：IPQ60XX-JDCLOUD + IPQ60XX-ZNM2-WIFI-NO   ← 当前主力
  QCB-ALL.yml     薄壳：IPQ53XX-WIFI-NO + IPQ95XX-WIFI-YES       （保留待扩展）
  MTK-ALL.yml     薄壳：MEDIATEK-WIFI-YES + WIFI-NO              （保留待扩展）
  OWRT-ALL.yml    薄壳：AIROHA-WIFI-NO + ROCKCHIP + X86           （保留待扩展）
  WRT-TEST.yml    只出 .config 不编译，改完配置先跑它验证
  Auto-Clean.yml  自动清理旧 Release / 旧 workflow 记录
  Cache-Clean.yml 清理 Actions 缓存
Config/
  GENERAL.txt                       两台机器共用的基座（也是所有机型的基座）
  ── 当前主力 ──
  IPQ60XX-JDCLOUD.txt               亚瑟（含插件清单）
  IPQ60XX-ZNM2-WIFI-NO.txt          兆能 M2（含插件清单 + IPQ 调参标记）
  IPQ60XX-ZNM2-WIFI-NO-OVERRIDE.txt 兆能 M2 专属裁剪
  ── 通用（保留待扩展，已按 VIKINGYFY 上游原版校准）──
  IPQ60XX-WIFI-YES.txt / IPQ60XX-WIFI-NO.txt
  IPQ807X-WIFI-YES.txt / IPQ807X-WIFI-NO.txt
  IPQ53XX-WIFI-NO.txt / IPQ95XX-WIFI-YES.txt
  MEDIATEK-WIFI-YES.txt / MEDIATEK-WIFI-NO.txt
  AIROHA-WIFI-NO.txt / ROCKCHIP.txt / X86.txt
  TEST.txt                          WRT-TEST 用
Scripts/
  Packages.sh     拉第三方包（含按需判断 / 重试 / 溯源）
  Handles.sh      修 feeds、改 tailscale/rust、调用 USB-WAN.sh 注入 files/
  Settings.sh     改 IP、主机名、主题、SSID；无 WiFi 切 nowifi.dtsi；IPQ 调参
  USB-WAN.sh      USB 网卡自动 WAN（CPE）
  DepCheck.sh     依赖预检（defconfig 之后跑，见下）
USB-WAN.md        USB-WAN 用法与排障
```

---

## 依赖预检（`Scripts/DepCheck.sh`）

在 `make defconfig` 之后自动跑一次，**几秒钟**，用来提前发现这类问题：

```
ERROR: unable to select packages: v2ray-geoip (no such package): required by: luci-app-passwall2
```

源码已迁移到 **apk** 包管理器，`.config` 里写了源中不存在（或已被改名）的依赖时，
`make defconfig` **不会报任何错** —— 要等 1.5~3 小时把几百个包全部编完之后，
在 `package/install` 阶段才炸，整次编译白跑，而且失败还会导致编译缓存不保存。

预检会读出 `tmp/.packageinfo`（`scripts/package-metadata.pl` 生成，含 `LUCI_DEPENDS`），
逐个比对选中包的依赖是否存在，缺失项以 `::error::` 注解输出，直接显示在运行的
**Annotations** 区和 job 摘要里，不用翻长日志。

- **只告警，永远 `exit 0`**，不会因为预检失败而中断编译。
- **WRT-TEST 也会跑它**，所以想验证新插件能不能编，跑一次 WRT-TEST 就够，不用等完整编译。
- 已知会被它抓到的典型情况：`luci-app-tailscale`（源里无 `tailscale`）、
  `luci-app-passwall2` / `luci-app-mosdns`（`v2ray-geoip`、`v2ray-geosite`
  已被生态改名合并为 `v2ray-geodata`）。

---

## 配置的加载顺序（谁覆盖谁）

一次构建里，配置分五批写进 `.config`，**越靠后优先级越高**：

| 顺序 | 来源 | 位置 | 说明 |
|---|---|---|---|
| 1 | `Config/<机型>.txt` | `WRT-CORE.yml` 的 Custom Settings 步骤 | 设备 + 机型插件清单 |
| 2 | `Config/GENERAL.txt` | 同上，紧跟其后 `cat` | 共用基座 |
| 3 | `Config/<机型>-OVERRIDE.txt` | `Scripts/Settings.sh` 末尾追加 | 关掉基座里用不到的包 |
| 4 | `Config/PRIVATE.txt` | `Scripts/Settings.sh` | 私有配置（不入库） |
| 5 | 工作流 `PACKAGE` 输入框 | `Scripts/Settings.sh` | 临时手动覆盖，优先级最高 |

覆盖文件就是在第 3 步由 `Settings.sh` 的这段加载的（找不到文件就跳过，不会报错）：

```bash
if [ -f "$GITHUB_WORKSPACE/Config/$WRT_CONFIG-OVERRIDE.txt" ]; then
	echo "Applying override from Config/$WRT_CONFIG-OVERRIDE.txt..."
	cat "$GITHUB_WORKSPACE/Config/$WRT_CONFIG-OVERRIDE.txt" >> ./.config
fi
```

它同时被 `Scripts/Packages.sh` 读进 `WRT_CONFIG_FILES`（排在最后），
所以 awk 顺序扫描时同名的 `=n` 能盖掉 `GENERAL.txt` 里的 `=y`，按需拉包跟着一起生效。

---

## 怎么用

1. fork 本仓库 → **Settings → Actions → General → Workflow permissions**
   设为 **Read and write permissions**。
2. **Actions → WRT-TEST → Run workflow**：只生成 `.config` 不编译，几分钟出结果，
   用来验证配置能不能过 `make defconfig`。改完配置先跑它。
3. **Actions → QCA-ALL → Run workflow**：正式编译，两条线并行出亚瑟和 M2 两个固件。
4. 产物在 Releases，tag 形如 `IPQ60XX-ZNM2-WIFI-NO-VIKINGYFY-main-26.10.06-08.30.00`。

---

## 加一台新设备

1. 复制一份最接近的机型配置，改设备名与插件清单。
   设备 key 去 `target/linux/<target>/<subtarget>/` 下找，
   兆能 M2 是 `zn_m2`、亚瑟是 `jdcloud_re-ss-01`。
2. 容量小的机器再配一个 `Config/<机型>-OVERRIDE.txt` 做裁剪。
3. 在对应 `*-ALL.yml` 的 `matrix.CONFIG` 里加一项。

全程不用碰 `WRT-CORE.yml` —— 上游编译步骤有变动时只同步这一个文件。

---

## 与上游 VIKINGYFY 的校准记录

骨架取自 krisxu23（它只跑亚瑟一台，其余文件未必验证过），
所以全部通用配置都拿 VIKINGYFY/OpenWRT-CI 原版逐行对过一遍。修正如下：

| 问题 | 处理 |
|---|---|
| `IPQ60XX-WIFI-YES/NO.txt` 被 krisxu23 改成亚瑟单设备版（162 行，其余设备全写 `=n`） | 还原为上游全设备列表版（22 / 32 行） |
| `GENERAL.txt` 缺 `luci-app-natmapt`、`kmod-nf-nat`、`kmod-usb-ehci`、`stuntman-client`、`CONFIG_FEED_pon_*=n` | 全部补回（pon feed 不关会多拉一批驱动） |
| `IPQ807X-WIFI-YES` 缺 `verizon_cr1000a` | 整份按上游还原 |
| `MEDIATEK-WIFI-YES` 缺 `airpi_ap3000m` | 补回 |
| `IPQ53XX-WIFI-NO` 缺 `xiaomi_be6500` | 补回 |
| `X86.txt` 有 `luci-app-dockerman=y`，但该包根本没被拉（WRT-CORE 里已 `rm` 掉） | 删除，避免"看起来装上了其实没有" |
| `AIROHA` 整条线丢失（OWRT 矩阵和 Config 都没有） | 补 `Config/AIROHA-WIFI-NO.txt`，加回 OWRT-ALL 矩阵 |
| `WRT-CORE` 里 `WRT_WIFI` 初值被 krisxu23 写死成 `wifi-yes`，且删掉了上游的重算逻辑 | 初值还原 `none`，由 `Settings.sh` 按机型名给出确定值 |
| `WRT_TEST` 传参缺 `|| false` 兜底（`workflow_run` 触发时 inputs 为空） | 五条调用工作流统一改回 `${{inputs.TEST \|\| false}}` |

| `IPQ60XX-ZNM2-WIFI-NO` 里给 M2 加了 `# @WRT_Q6_REGION=0x02000000`（想把 NSS 预留砍到 32MB） | **删除**。核对源码后发现 `ipq6018-nowifi.dtsi` 里 `q6_region` 本身就是 `0x1000000`（16MB），再设 32MB 是反向优化，白扔 16MB 内存 |

另外，**上游自己有两处不一致**：`QCB-ALL` / `OWRT-ALL` 的矩阵引用
`IPQ53XX-WIFI-NO`、`IPQ95XX-WIFI-YES`、`AIROHA-WIFI-NO`，
但上游 Config 目录里叫 `IPQ53XX.txt`、`IPQ95XX.txt`、`AIROHA.txt`
—— 也就是说上游这三条线其实是跑不起来的。本仓库统一用矩阵里的名字命名文件，已对齐。

---

## 注意

- **无 WiFi 机型的配置名必须同时含 `WIFI` 和 `NO`**（如 `IPQ60XX-ZNM2-WIFI-NO`）。
  `Settings.sh` 靠这个判断把 `ipq6018.dtsi` 换成 `ipq6018-nowifi.dtsi`，
  给 NSS 少预留一大块内存 —— 512MB 的 M2 很吃这一点。
  除了改名字，机型配置里 `CONFIG_PACKAGE_kmod-ath*=n` 几行也要带上，两者缺一不可。
- **nowifi 链路已对源码核过**（`VIKINGYFY/immortalwrt` @ main）：
  - `ipq6018-nowifi.dtsi` / `ipq8074-nowifi.dtsi` 不在 `target/linux/qualcommax/dts/` 下，
    而在 `target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/`，会被拷进内核 dts 目录 —— 所以替换后能正常 `#include`。
  - M2 的链路是 `ipq6000-m2.dts` → `ipq6000-cmiot.dtsi` → `ipq6018.dtsi`，
    `Settings.sh` 改的是中间的 `ipq6000-cmiot.dtsi`，命中。
  - nowifi 变体把 `q6_region` 设为 16MB（base 是 85MB），**不要再手动调大**。
  - 亚瑟的 `ipq6000-re-ss-01.dts` 第 181 行确实是 `qcom,ath11k-fw-memory-mode = <1>`，
    `Settings.sh` 改 `<1>` → `<0>`（完整内存模式，适配硬改 1G）能命中。
- `third-party-sources.txt` 是构建产物，已在 `.gitignore` 里，不要提交。
- 私有配置放 `Config/PRIVATE.txt` 或 `Scripts/PRIVATE.sh`，会被自动加载且已忽略。
