# YOpenWRT-CI

自用 OpenWrt 云编译仓库，只维护两台 IPQ6000 设备。骨架 fork 自 VIKINGYFY/OpenWRT-CI。

## 设备与工作流

| 设备 | 硬件 | 配置 | 源码 |
|---|---|---|---|
| 京东云亚瑟 RE-SS-01 / AX1800 Pro | IPQ6000，硬改 1G RAM + 64G eMMC，带 WiFi | `Config/IPQ60XX.txt` | 两条线共用 |
| 兆能 ZN-M2 | IPQ6000，512MB RAM + 128MB NAND，无 WiFi | `Config/IPQ60XX-noWiFi.txt` | 两条线共用 |

四条工作流，都是薄壳，`uses: ./.github/workflows/WRT-CORE.yml`：

| 工作流 | 配置 | 源码 | 内核 |
|---|---|---|---|
| `IPQ60XX-ImmortalWrt.yml` | IPQ60XX | `VIKINGYFY/immortalwrt` @ `main` | 6.18 + 满血 NSS |
| `IPQ60XX-ImmortalWrt-noWiFi.yml` | IPQ60XX-noWiFi | 同上 | 同上 |
| `IPQ60XX-LibWRT.yml` | IPQ60XX | `LiBwrt/LibWrt` @ `25.12-nss` | 6.12 + 满血 NSS（含 WiFi 卸载） |
| `IPQ60XX-LibWRT-noWiFi.yml` | IPQ60XX-noWiFi | 同上 | 同上 |

辅助：`WRT-TEST.yml`（只出 `.config` 不编译）、`Auto-Clean.yml`、`Cache-Clean.yml`。

> 注意 VIKINGYFY/immortalwrt 的**默认分支是 `owrt`（无 NSS）**，必须显式写 `main` 才是满血 NSS 那条线。

## 配置的加载顺序

越靠后优先级越高，同 key 后者生效：

| 顺序 | 来源 | 说明 |
|---|---|---|
| 1 | `Config/<配置>.txt` | 设备 + 插件清单 |
| 2 | `Config/GENERAL.txt` | 共用基座，与上游保持一致不做本地增删 |
| 3 | `Config/<设备>-Override.txt` | 按设备关键词自动匹配，关掉用不到的包 |
| 4 | `Config/PRIVATE.txt` | 私有配置，文件不存在就整段跳过 |
| 5 | 工作流 `PACKAGE` 输入框 | 临时手动覆盖 |

### Override 按设备匹配，不按配置名

`IPQ60XX-JDCloud-Override.txt` / `IPQ60XX-ZNM2-Override.txt` 由 `Settings.sh` 从 `.config`
取出主设备名（`jdcloud_re-ss-01` / `zn_m2`），与文件名里的关键词比对，命中才追加。
所以**同一份覆盖在四条工作流里都生效**，不区分 WiFi、不绑定源码。

改插件的口诀：**想要的 `=y` 写机型配置或 GENERAL，不想要的 `=n` 只写 Override**。
某个包最终进不进固件由三处共同决定，拿不准就跑一次 WRT-TEST，看 Release 里
`Config-<配置>-*.txt`（那是 `make defconfig` 收敛后的真值）。

## 用法

1. fork → **Settings → Actions → General → Workflow permissions** 设为 **Read and write**。
2. 改完配置先跑 **Actions → WRT-TEST → Run workflow**，几分钟出结果，验证能不能过 `defconfig`。
3. 正式编译跑对应的 `IPQ60XX-*`，产物在 Releases。

## 两个要注意的坑

- **无 WiFi 的配置名必须同时含 `wifi` 和 `no`**（即写成 `noWiFi`）。`Settings.sh` 靠这个把
  `ipq6018.dtsi` 换成 `ipq6018-nowifi.dtsi`，给 NSS 少预留一大块内存 —— 512MB 的 M2 很吃这点。
  配置里 `CONFIG_PACKAGE_kmod-ath*=n` 几行也要带上，两者缺一不可。
- **源码已迁移 apk**，`.config` 里写了源中不存在的依赖时 `make defconfig` 不报错，
  要等一两个小时编完才在 `package/install` 炸掉。`Scripts/DepCheck.sh` 在 defconfig 后
  预检一遍，缺失项以 `::error::` 打到 Annotations，只告警不阻断。已知会命中的：
  `luci-app-passwall2` / `luci-app-mosdns`（依赖已改名 `v2ray-geodata`）、
  `luci-app-tailscale`（源里无主程序）、`luci-app-netspeedtest`（缺 python3-email），
  均已在 Override 里关掉。

## 目录

```
.github/workflows/  WRT-CORE.yml 是唯一干活的，其余全是薄壳
Config/             GENERAL.txt + 两份机型配置 + 两份 Override + TEST.txt
Scripts/            Packages.sh 拉包 / Handles.sh 修 feeds / Settings.sh 改系统设置
                    DepCheck.sh 依赖预检 / USB-WAN.sh 暂未启用（见 Handles.sh 注释）
USB-WAN.md          USB 网卡 WAN 玩法，需要时按它恢复
```

`third-party-sources.txt`、`Config/PRIVATE.txt`、`Scripts/PRIVATE.sh` 是本地产物，已忽略。
