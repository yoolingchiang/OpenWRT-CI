#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#设备专属覆盖：本仓库已不使用 —— 配置改为「一台设备/一种形态一份自包含清单」
#（Config/JDCloud-WiFi.txt、JDCloud-noWiFi.txt、ZNM2-noWiFi.txt）。
#原先是 Config/*-Override.txt 按设备关键词（JDCloud / ZNM2）自动匹配、追加到 .config 末尾。
#取消的原因：亚瑟要出 WiFi 与 noWiFi 两份，而 Override 只认设备名（两台都命中 JDCloud），
#没法区分形态；自包含清单天然没有这个问题，也不必再维护「通用层 + 减法」两层。
#如果以后又想回到覆盖机制：把下面那段恢复即可（Packages.sh 里有对应的按需拉包逻辑）。
#if [ -n "$(sed -n 's/^CONFIG_TARGET_DEVICE_.*_DEVICE_\([A-Za-z0-9_-]\{1,\}\)=y[[:space:]]*$/\1/p' ./.config 2>/dev/null)" ]; then
#	...（原 Override 遍历逻辑，见 git 历史）
#fi

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#高通平台参数统一裁定（ath11k 内存档位 + NSS 固件版本）
#
#为什么这些项不写在 Config/*.txt：这两个都是 Kconfig 的 choice，同一时刻只能有一个 =y。
#放在这里按「配置名是否 noWiFi」裁定，好处是：
#  1) 新增配置不用记得同时改档位，跟着命名走就行；
#  2) 两份配置互不干扰 —— 各自独立 .config，天然不会出现 choice 多选。
#（早期版本一份配置编多台设备、靠 Override 区分，那时两份 Override 会各写一个 =y 造成
#  choice 多选，才必须集中到这个脚本里收口。现在一配置一设备，这个坑已经不存在，
#  集中裁定保留下来只是为了让档位跟配置名挂钩、少一处要改的地方。）
#
#两条源码线的实现差异（本次踩坑点）：
#  LibWrt(6.12)：ath.mk 里是真正的 choice —— ATH11K_MEM_PROFILE_1G/512M/256M 三选一；
#                NSS 固件版本在 nss-packages feed 的 firmware/nss-firmware/Makefile 里，
#                也是 choice —— 11_4/12_1/12_2/12_5 四选一。
#  VIKINGYFY/immortalwrt(6.18)：两个 choice 都不存在。ath11k 只在 ATH11K_NSS_SUPPORT=y 时
#                由 ath.mk 硬写 ATH11K_MEM_PROFILE_512M；固件版本符号干脆没有。
#                也就是说 6.18 线上这两项用户改不了，写进 .config 会被静默忽略（不报错）。
#判据：用 ath.mk 里有没有 ATH11K_MEM_PROFILE_1G 来识别「这是 LibWrt 那条有 choice 的线」。
if [ -f "./package/kernel/mac80211/ath.mk" ] && grep -q "ATH11K_MEM_PROFILE_1G" ./package/kernel/mac80211/ath.mk; then
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		ATH11K_MEM_KEEP="512M"
		NSS_FW_KEEP="11_4"
	else
		ATH11K_MEM_KEEP="1G"
		NSS_FW_KEEP="12_5"
	fi

	#ath11k 内存档位：带 WiFi 用 1G（亚瑟硬改），无 WiFi 用 512M（ath11k 不工作，不该占内存）
	sed -i '/^CONFIG_ATH11K_MEM_PROFILE_/d; /^# CONFIG_ATH11K_MEM_PROFILE_.* is not set$/d' ./.config
	for ATH_MEM in 1G 512M 256M; do
		if [ "$ATH_MEM" = "$ATH11K_MEM_KEEP" ]; then
			echo "CONFIG_ATH11K_MEM_PROFILE_$ATH_MEM=y" >> ./.config
		else
			echo "# CONFIG_ATH11K_MEM_PROFILE_$ATH_MEM is not set" >> ./.config
		fi
	done

	#NSS 固件版本：带 WiFi 用 12.5（新），无 WiFi 用 11.4（保留 mesh，且是上游默认值）
	sed -i '/^CONFIG_NSS_FIRMWARE_VERSION_/d; /^# CONFIG_NSS_FIRMWARE_VERSION_.* is not set$/d' ./.config
	for NSS_FW in 11_4 12_1 12_2 12_5; do
		if [ "$NSS_FW" = "$NSS_FW_KEEP" ]; then
			echo "CONFIG_NSS_FIRMWARE_VERSION_$NSS_FW=y" >> ./.config
		else
			echo "# CONFIG_NSS_FIRMWARE_VERSION_$NSS_FW is not set" >> ./.config
		fi
	done

	echo "qualcommax params resolved: ath11k mem=$ATH11K_MEM_KEEP, nss firmware=$NSS_FW_KEEP"
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#======================= 命名规则（固定写法，别自创）=======================
#带 WiFi 的配置一律以 -WiFi 结尾，无 WiFi 的一律以 -noWiFi 结尾：
#    JDCloud-WiFi / JDCloud-noWiFi / ZNM2-noWiFi
#▲WiFi 的大小写要统一写 WiFi（i 小写），不要写 WIFI / Wifi / wiFi —— 一是和 noWiFi
#  保持一致的驼峰观感，二是 Linux 大小写敏感，配置名/工作流名/WRT_CONFIG 三处必须
#  完全一致，写歪一个字母就是「找不到配置文件」。
#为什么必须固定：下面判断「是否有 WiFi」靠的是配置名小写后同时含 wifi 与 no，
#写成 WIFI-NO / wifi / NoWifi / -nowifi 都可能让判定悄悄失效 —— 判错的后果是
#固件文件名带上错误的 WIFI 标记，而且 dtsi 不会切成 nowifi 版（NSS 白占一大块内存），
#不报错、只是产物不对，最难查。所以这里主动校验一次。
#TEST 是只输出 .config 的调试配置，不参与这条规则。
case "$WRT_CONFIG" in
	TEST) ;;
	*-WiFi|*-noWiFi) ;;
	*)
		echo "::warning::配置名 '$WRT_CONFIG' 不符合命名规则：带 WiFi 用 -WiFi 结尾、无 WiFi 用 -noWiFi 结尾（如 JDCloud-WiFi / JDCloud-noWiFi）。注意是 WiFi 不是 WIFI。当前会按「带 WiFi」处理，若实际是无 WiFi 配置，dtsi 不会切换、固件文件名标记也会错。"
		;;
esac

#无WIFI配置标志
#WRT-CORE 里 WRT_WIFI 的初值是 none，这里给一个确定值：
#配置名以 -noWiFi 结尾 → wifi-no，其余一律 wifi-yes。
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
else
	echo "WRT_WIFI=wifi-yes" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#当前配置里实际要编的设备（可能不止一台），后面按设备名做定向调整
	WRT_DEVICES="$(sed -n 's/^CONFIG_TARGET_DEVICE_.*_DEVICE_\([A-Za-z0-9_-]\{1,\}\)=y[[:space:]]*$/\1/p' ./.config 2>/dev/null)"

	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
	# JDCloud RE-SS-01 硬改1G内存：ath11k切换完整内存模式（省内存模式仅适用于原厂512M）
	#★必须判断「本配置真的在编亚瑟」—— 只看文件存在的话，编 M2 时也会顺手改掉亚瑟的 dts，
	#  那是同一棵源码树里的文件，改了对本次产物无影响，但语义错误、且容易误导后来人。
	#  另外必须是「硬件真硬改过 1G」的设备才该改；两种形态（WiFi / noWiFi）都是同一块板子，
	#  所以只要配置里出了 jdcloud_re-ss-01 就改，不区分 WiFi。
	if printf '%s\n' "$WRT_DEVICES" | grep -qx 'jdcloud_re-ss-01'; then
		if [ -f "$DTS_PATH/ipq6000-re-ss-01.dts" ]; then
			sed -i 's/qcom,ath11k-fw-memory-mode = <1>/qcom,ath11k-fw-memory-mode = <0>/' "$DTS_PATH/ipq6000-re-ss-01.dts"
			echo "jdcloud re-ss-01 set ath11k fw memory-mode to 0 (1G RAM) done!"
		fi
		#noWiFi 形态下 ath11k 不工作，内存模式改了也不影响；保持统一处理，避免两种形态
		#出现「同一块板子、dts 却不同」的隐性差异。
	fi

	# ---- IPQ 专属调参（思路来自 laipeng668/openwrt-ci-roc 的 Roc-script.sh）----
	# 这两项在原仓库里都是注释掉的"手动旋钮"，这里改成由机型配置里的标记驱动，
	# 好处是调参跟着机型配置走，不用每次改脚本。标记写法（行首 # @ 开头）：
	#   # @WRT_Q6_REGION=0x02000000   —— NSS 预留内存改成 32MB
	#   # @WRT_CPU_UV=950000          —— 1.5GHz 档电压改成 0.95V
	# 两个标记都默认不写 = 不生效；找不到对应文件/匹配行也只是跳过，不会让构建失败。

	WRT_CFG_FILE="$GITHUB_WORKSPACE/Config/$WRT_CONFIG.txt"

	# NSS q6_region 内存预留：ipq6018.dtsi 默认 85MB，ipq6018-512m.dtsi 默认 55MB。
	# 带 WiFi 至少留 54MB；无 WiFi 机型可以调小，512MB 内存的小机器收益明显。
	# 可选值：0x01000000=16MB / 0x02000000=32MB / 0x04000000=64MB / 0x06000000=96MB
	if [ -f "$WRT_CFG_FILE" ]; then
		Q6_REGION="$(grep -m 1 -oP '^#\s*@WRT_Q6_REGION=\K0[xX][0-9a-fA-F]+' "$WRT_CFG_FILE" 2>/dev/null)"
	fi
	if [ -n "${Q6_REGION:-}" ]; then
		Q6_FILES="$(find ./target/linux/qualcommax -type f -name 'ipq6018*.dtsi' 2>/dev/null)"
		if [ -n "$Q6_FILES" ]; then
			echo "$Q6_FILES" | while read -r Q6_FILE; do
				if sed -i "s/reg = <0x0 0x4ab00000 0x0 0x[0-9a-fA-F]\+>/reg = <0x0 0x4ab00000 0x0 $Q6_REGION>/" "$Q6_FILE"; then
					echo "q6_region set to $Q6_REGION in $Q6_FILE"
				fi
			done
		else
			echo "q6_region: no ipq6018*.dtsi found, skipped!"
		fi
	fi

	# 1.5GHz 频率档电压：默认 0.9375V，过低可能不稳定，过高增加发热功耗。
	# 只处理 qualcommax 补丁里 opp-microvolt = <937500> 的那一行。
	if [ -f "$WRT_CFG_FILE" ]; then
		CPU_UV="$(grep -m 1 -oP '^#\s*@WRT_CPU_UV=\K[0-9]+' "$WRT_CFG_FILE" 2>/dev/null)"
	fi
	if [ -n "${CPU_UV:-}" ]; then
		UV_FILES="$(grep -rl 'opp-microvolt = <937500>' ./target/linux/qualcommax/patches-*/ 2>/dev/null)"
		if [ -n "$UV_FILES" ]; then
			echo "$UV_FILES" | while read -r UV_FILE; do
				if sed -i "s/opp-microvolt = <937500>;/opp-microvolt = <$CPU_UV>;/" "$UV_FILE"; then
					echo "cpu 1.5GHz microvolt set to $CPU_UV in $UV_FILE"
				fi
			done
		else
			echo "cpu microvolt: no patch with opp-microvolt 937500 found, skipped!"
		fi
	fi
fi
