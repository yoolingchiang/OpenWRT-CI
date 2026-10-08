# YOpenWRT-CI

自用 OpenWrt 云编译仓库，维护两台 IPQ6000 设备。骨架 fork 自 VIKINGYFY/OpenWRT-CI，
配置组织方式参考 uiYzzi 的 openwrt_jdcloud_re-ss-01_ci（一设备一配置、自包含清单）。

## 产出矩阵

**3 种固件 × 2 条源码线 = 6 个产物**：

| 配置 | 设备 | WiFi | 硬件 |
|---|---|---|---|
| `JDCloud-WiFi` | 京东云亚瑟 RE-SS-01 / AX1800 Pro | 有 | IPQ6000，**硬改 1G RAM** + 64G eMMC |
| `JDCloud-noWiFi` | 京东云亚瑟 RE-SS-01 / AX1800 Pro | 无 | 同上（当纯有线路由 / 外接 AP 用） |
| `ZNM2-noWiFi` | 兆能 ZN-M2 | 无 | IPQ6000，512MB RAM + 128MB NAND |

**3 条工作流，一条工作流 = 一份设备配置**。源码线不写死在文件里，而是**运行时用
`SOURCE` 下拉框手动选**，一次运行只出那一条线的固件 —— 不搞矩阵展开，
所以不会「跑一次自动带出两份」。两条线都要，就手动再触发一次。

| 工作流 | 配置（写死） | 运行时 `SOURCE` 可选项 |
|---|---|---|
| `JDCloud-WiFi.yml` | `JDCloud-WiFi` | `OWrt` / `LibWrt` |
| `JDCloud-noWiFi.yml` | `JDCloud-noWiFi` | `OWrt` / `LibWrt` |
| `ZNM2-noWiFi.yml` | `ZNM2-noWiFi` | `OWrt` / `LibWrt` |

选了 `SOURCE` 之后，**仓库 / 分支 / 主机名 / 管理 IP 全部自动带出**，不用再手填：

| `SOURCE` | 仓库 @ 分支 | 主机名 | 管理 IP | 内核 |
|---|---|---|---|---|
| `OWrt` | `VIKINGYFY/immortalwrt` @ `main` | `OWrt` | `192.168.10.1` | 6.18 满血 NSS |
| `LibWrt` | `LiBwrt/LibWrt` @ `25.12-nss` | `LibWrt` | `192.168.20.1` | 6.12 满血 NSS + WiFi 卸载 |

主机名按**源码线**区分（`OWrt` / `LibWrt`），IP 错开成 10.x / 20.x，
这样两台路由插在同一张网里不撞 IP，进后台看主机名就知道刷的是哪条线。

> 自动带出靠的是 `${{inputs.SOURCE == 'LibWrt' && ... || ...}}` 这种表达式。
> 如果以后要加第三条源码线，改法是把这四处的三元判断换成「先算再传」——
> 或者干脆拆成独立工作流文件（代价是 3×N 个文件，目前 3×2 拆成 6 个没必要）。

辅助：`WRT-TEST.yml`（只出 `.config` 不编译）、`Auto-Clean.yml`、`Cache-Clean.yml`。

> VIKINGYFY/immortalwrt 的**默认分支是 `owrt`（无 NSS）**，必须显式写 `main` 才是满血 NSS 那条线。

## 配置组织：一设备一配置，自包含清单

```
Config/
  GENERAL.txt        共用基座（上游 VIKINGYFY 原版，不做本地增删）
  JDCloud-WiFi.txt   亚瑟带 WiFi：完整清单
  JDCloud-noWiFi.txt 亚瑟无 WiFi：完整清单
  ZNM2-noWiFi.txt    M2 无 WiFi：完整清单
  TEST.txt           调试用，只出 .config
```

**每份配置写完自己要什么、不要什么**，不搞「通用层 + 覆盖层」那套。
早期版本用过 `Config/*-Override.txt` 按设备关键词自动追加，现已取消。

### 为什么不用 Override 了

Override 是按**设备名**匹配的（`JDCloud` 命中 `jdcloud_re-ss-01`）。
亚瑟要同时出 WiFi 和无 WiFi 两份，而**两份配置都会命中同一个 `JDCloud-Override`** ——
它分不清形态，`kmod-ath11k` 该开还是该关没法表达。自包含清单天然没这个问题。

而且同一个 `.config` 里 `CONFIG_PACKAGE_*` 是**全局共享**的：
`PER_DEVICE_ROOTFS` 只把各机型的镜像/rootfs 分开，**包集合是共用的**。
所以一份配置里编多台设备时，两台固件拿到的是同一套包，M2 的 `docker=n`
会把亚瑟的 docker 一起关掉 —— 「按机型差异化」整个失效。
**一配置一设备（或一形态），是这套架构能成立的前提。**

### 三份配置的差异对照

| 项目 | JDCloud-WiFi | JDCloud-noWiFi | ZNM2-noWiFi |
|---|---|---|---|
| ath11k / 无线固件 | 开（机型默认带） | **显式 `=n` 关掉** | **显式 `=n` 关掉** |
| Docker 全套 | 开（1G + eMMC） | 开 | **关**（512MB + NAND 跑不动） |
| btrfs / NVMe / ATA / smartmontools | 开 | 开 | **关** |
| samba4 / diskman / partexp | 开 | 开 | **关** |
| mwan3（多 WAN） | 无 | 无 | 开（当主路由，双拨用得上） |
| zram-swap | 开 | 开 | 开（512MB 刚需） |
| USB 全家桶 | 开 | 开 | 开（两台都有 USB 口） |
| coremark / 小工具 | 开 | 开 | **关**（NAND 省空间） |

## 加载顺序

越靠后优先级越高，同 key 后者生效：

| 顺序 | 来源 | 说明 |
|---|---|---|
| 1 | `Config/<配置>.txt` | 自包含清单 |
| 2 | `Config/GENERAL.txt` | 共用基座 |
| 3 | `Config/PRIVATE.txt` | 私有配置，文件不存在就整段跳过 |
| 4 | `Settings.sh` 的高通参数裁定 | ath11k 内存档位 / NSS 固件版本 |
| 5 | 工作流 `PACKAGE` 输入框 | 临时手动覆盖 |

最后 `make defconfig`：它是求解器不是配置层，会补齐依赖、仲裁互斥 ——
「把 X 关成 `=n` 但另一个开着的包依赖 X」时，X 会被悄悄拉回 `=y`。

## 命名规则（固定写法，别自创）

**带 WiFi 用 `-WiFi` 结尾，无 WiFi 用 `-noWiFi` 结尾**，注意是 `WiFi`（i 小写），
不要写成 `WIFI` / `Wifi` / `wiFi`。配置文件名、工作流名、`WRT_CONFIG` 三处必须完全一致
（Linux 大小写敏感，写歪一个字母就是「找不到配置文件」）。

`Settings.sh` 会校验这条规则，不合规时打 `::warning::` 到 Annotations。
写错不会报错、只会让产物悄悄不对 —— `dtsi` 不切成 nowifi 版（NSS 白占一大块内存），
固件文件名带上错误的 WIFI 标记，最难查。

## 两个要注意的坑

- **无 WiFi 不只是改个名**：`Settings.sh` 靠 `-noWiFi` 把 `ipq6018.dtsi` 换成
  `ipq6018-nowifi.dtsi`（给 NSS 少预留一大块内存，512MB 的 M2 很吃这点），
  配置里 `kmod-ath11k*` / `ath11k-firmware-*` 的 `=n` 也要带上 ——
  这些驱动来自机型 DEFAULT_PACKAGES，不显式写 `=n` 会被 defconfig 拉回来。
- **源码已迁移 apk**：`.config` 里写了源中不存在的依赖时 `make defconfig` 不报错，
  要等一两个小时编完才在 `package/install` 炸掉。`Scripts/DepCheck.sh` 在 defconfig 后
  预检一遍，缺失项以 `::error::` 打到 Annotations，只告警不阻断。已知会命中的：
  `luci-app-passwall2` / `luci-app-mosdns`（依赖已改名 `v2ray-geodata`）、
  `luci-app-tailscale`（源里无主程序）、`luci-app-netspeedtest`（缺 python3-email），
  均已在配置里关掉。
- **ath11k 内存档位 / NSS 固件版本不要在配置里写**。两者是 Kconfig `choice`，
  同一份 `.config` 只能有一个 `=y`，统一交给 `Settings.sh` 裁定：
  带 WiFi → 1G 档 + NSS 12.5；无 WiFi → 512M 档 + NSS 11.4。
  这两组符号只在 LibWrt(6.12) 线真实存在，immortalwrt(6.18) 线没有这个 choice，
  脚本检测到符号缺失会整段跳过。

## 用法

1. fork → **Settings → Actions → General → Workflow permissions** 设为 **Read and write**。
2. 改完配置先跑 **Actions → WRT-TEST → Run workflow**（选配置 + 选源码线），
   几分钟出结果，验证能不能过 `defconfig`。`BRANCH` 留空即跟随源码线默认分支。
3. 正式编译跑对应的 `JDCloud-*` / `ZNM2-*`，**记得选 `SOURCE`**（默认 `OWrt`），产物在 Releases。

## 目录

```
.github/workflows/  WRT-CORE.yml 是唯一干活的，其余全是薄壳
Config/             GENERAL.txt + 三份设备配置 + TEST.txt
Scripts/            Packages.sh 拉包 / Handles.sh 修 feeds / Settings.sh 改系统设置
                    DepCheck.sh 依赖预检 / USB-WAN.sh 暂未启用（见 Handles.sh 注释）
USB-WAN.md          USB 网卡 WAN 玩法，需要时按它恢复
```

`third-party-sources.txt`、`Config/PRIVATE.txt`、`Scripts/PRIVATE.sh` 是本地产物，已忽略。
`.trash-old/` 是本次重构归档的旧配置与旧工作流，确认无误后可删。
