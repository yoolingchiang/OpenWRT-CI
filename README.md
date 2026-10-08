# YOpenWRT-CI

自用 OpenWrt 云编译仓库，维护两台 IPQ6000 设备。骨架 fork 自 VIKINGYFY/OpenWRT-CI

## 产出矩阵

**3 种固件 × 2 条源码线 = 6 个产物**：

| 配置               | 设备                          | WiFi | 硬件                               |
| ---------------- | --------------------------- | ---- | -------------------------------- |
| `JDCloud-WiFi`   | 京东云亚瑟 RE-SS-01 / AX1800 Pro | 有    | IPQ6000，**硬改 1G RAM** + 64G eMMC |
| `JDCloud-noWiFi` | 京东云亚瑟 RE-SS-01 / AX1800 Pro | 无    | 同上（当纯有线路由 / 外接 AP 用）             |
| `ZNM2-noWiFi`    | 兆能 ZN-M2                    | 无    | IPQ6000，**硬改512MB RAM + 128MB NAND   |

**3 条工作流，一条工作流 = 一份设备配置**。源码线不写死在文件里，而是**运行时用  
`SOURCE` 下拉框手动选**，一次运行只出那一条线的固件。

| 工作流                  | 配置（写死）           | 运行时 `SOURCE` 可选项  |
| -------------------- | ---------------- | ----------------- |
| `JDCloud-WiFi.yml`   | `JDCloud-WiFi`   | `OWrt` / `LibWrt` |
| `JDCloud-noWiFi.yml` | `JDCloud-noWiFi` | `OWrt` / `LibWrt` |
| `ZNM2-noWiFi.yml`    | `ZNM2-noWiFi`    | `OWrt` / `LibWrt` |

选了 `SOURCE` 之后，**仓库 / 分支 / 主机名 / 管理 IP 全部自动带出**，不用再手填：

| `SOURCE` | 仓库 @ 分支                          | 主机名      | 管理 IP          | 内核                    |
| -------- | -------------------------------- | -------- | -------------- | --------------------- |
| `OWrt`   | `VIKINGYFY/immortalwrt` @ `main` | `OWrt`   | `192.168.10.1` | 6.18 满血 NSS           |
| `LibWrt` | `LiBwrt/LibWrt` @ `25.12-nss`    | `LibWrt` | `192.168.20.1` | 6.12 满血 NSS + WiFi 卸载 |

主机名按**源码线**区分（`OWrt` / `LibWrt`），IP 错开成 10.x / 20.x，  
这样两台路由插在同一张网里不撞 IP，进后台看主机名就知道刷的是哪条线。

辅助：`WRT-TEST.yml`（只出 `.config` 不编译）、`Auto-Clean.yml`、`Cache-Clean.yml`。

## 配置组织：一设备一配置，自包含清单

```
Config/
  GENERAL.txt        共用基座（上游 VIKINGYFY 原版，不做本地增删）
  JDCloud-WiFi.txt   亚瑟带 WiFi：完整清单
  JDCloud-noWiFi.txt 亚瑟无 WiFi：完整清单
  ZNM2-noWiFi.txt    M2 无 WiFi：完整清单
  TEST.txt           调试用，只出 .config
```

### 三份配置的差异对照

| 项目                                 | JDCloud-WiFi | JDCloud-noWiFi | ZNM2-noWiFi             |
| ---------------------------------- | ------------ | -------------- | ----------------------- |
| ath11k / 无线固件                      | 开（机型默认带）     | **显式 `=n` 关掉** | **显式 `=n` 关掉**          |
| Docker 全套                          | 开（1G + eMMC） | 开              | **关**（512MB + NAND 跑不动） |
| btrfs / NVMe / ATA / smartmontools | 开            | 开              | **关**                   |
| samba4 / diskman / partexp         | 开            | 开              | **关**                   |
| mwan3（多 WAN）                       | 无            | 无              | 开（当主路由，双拨用得上）           |
| zram-swap                          | 开            | 开              | 开（512MB 刚需）             |
| USB 全家桶                            | 开            | 开              | 开（两台都有 USB 口）           |
| coremark / 小工具                     | 开            | 开              | **关**（NAND 省空间）         |

## 用法

1. fork → **Settings → Actions → General → Workflow permissions** 设为 **Read and write**。
2. 改完配置先跑 **Actions → WRT-TEST → Run workflow**：选 `CONFIG` + 选 `SOURCE`，  
   几分钟出结果，验证能不能过 `defconfig`。
3. 正式编译跑对应的 `JDCloud-*` / `ZNM2-*`，**记得选 `SOURCE`**（默认 `OWrt`），产物在 Releases。

## 目录

```
.github/workflows/  WRT-CORE.yml 是唯一干活的，其余全是薄壳
Config/             GENERAL.txt + 三份设备配置 + TEST.txt
Scripts/            Packages.sh 拉包 / Handles.sh 修 feeds / Settings.sh 改系统设置
                    DepCheck.sh 依赖预检 / USB-WAN.sh 暂未启用（见 Handles.sh 注释）
USB-WAN.md          USB 网卡 WAN 玩法，需要时按它恢复
```

