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

#机型专属覆盖：Config/<机型>-OVERRIDE.txt
#GENERAL.txt 是共用基座，但不同机型容量差异很大（例如亚瑟 64G eMMC 与 M2 128MB NAND
#不可能共用同一份插件清单）。覆盖文件在这里最后追加，优先级高于 GENERAL.txt，
#可以把共用基座里对当前机型来说多余的包显式关成 =n。
if [ -f "$GITHUB_WORKSPACE/Config/$WRT_CONFIG-OVERRIDE.txt" ]; then
	echo "Applying override from Config/$WRT_CONFIG-OVERRIDE.txt..."
	cat "$GITHUB_WORKSPACE/Config/$WRT_CONFIG-OVERRIDE.txt" >> ./.config
fi

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#无WIFI配置标志
#WRT-CORE 里 WRT_WIFI 的初值是 none，这里给一个确定值：
#配置名同时含 wifi 与 no（如 IPQ60XX-ZNM2-WIFI-NO）判为 wifi-no，其余一律 wifi-yes，
#否则固件文件名会带上错误的 WIFI 标记。
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
else
	echo "WRT_WIFI=wifi-yes" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
	# JDCloud RE-SS-01 硬改1G内存：ath11k切换完整内存模式（省内存模式仅适用于原厂512M）
	if [ -f "$DTS_PATH/ipq6000-re-ss-01.dts" ]; then
		sed -i 's/qcom,ath11k-fw-memory-mode = <1>/qcom,ath11k-fw-memory-mode = <0>/' "$DTS_PATH/ipq6000-re-ss-01.dts"
		echo "jdcloud re-ss-01 set ath11k fw memory-mode to 0 (1G RAM) done!"
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
