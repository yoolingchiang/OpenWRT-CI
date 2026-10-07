#!/bin/bash
#依赖预检：在 make defconfig 之后跑，提前找出 apk 阶段才会暴露的"依赖包不存在"。
#
#为什么需要它：
#	源码（VIKINGYFY/immortalwrt）已迁移到 apk 包管理器。.config 里 =y 的包，
#	如果它的运行时依赖在源码树里根本没有对应的包，make defconfig 不会报任何错 ——
#	要等 1.5~3 小时把几百个包全部编完之后，在 package/install 阶段才报：
#		ERROR: unable to select packages: xxx (no such package): required by: yyy
#	然后 make world 直接中断，整次编译白跑，而且编译失败还会导致缓存不保存。
#	本脚本在 defconfig 之后花几秒钟把这类问题一次全列出来。
#
#	已经踩过的实例：
#		luci-app-tailscale    -> tailscale / python3-email / python3-pkg-resources 不存在
#		luci-app-passwall2    -> v2ray-geoip / v2ray-geosite 已被生态改名成 v2ray-geodata
#		luci-app-mosdns       -> 同上
#
#运行位置：源码根目录（WRT-CORE 里是 cd ./wrt/ 之后调用）
#退出码：永远 0 —— 预检只告警，绝不阻断编译（误报毁掉一次完整编译的代价远高于漏报）
#依赖数据来源：tmp/.packageinfo（scripts/package-metadata.pl 生成，make defconfig 会产出）
#	luci.mk 里有 DEPENDS:=$(LUCI_DEPENDS)，所以 luci 包的 LUCI_DEPENDS 也在里面，不用另外解析 Makefile

set +e

PKGINFO="tmp/.packageinfo"
CONFIG=".config"

if [ ! -f "$CONFIG" ]; then
	echo "::warning::DepCheck: 当前目录没有 .config，跳过依赖预检"
	exit 0
fi

#临时目录必须用【相对路径】：Windows 的 Git Bash 下 mktemp -d 返回的是
#	C:\Users\ADMINI~1\AppData\Local\Temp\tmp.XXXX
#这种反斜杠路径传给 awk 会被当成转义序列（\U \A \L \T 直接被吃掉）导致文件打不开，
#结果就是"检查了但一条都没报"。用相对路径在 Windows / Linux CI 上都安全。
WORK=".depcheck.$$"
rm -rf "$WORK"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

#---------- 1. .config 里被选中的包 ----------
#形如 CONFIG_PACKAGE_luci-app-nikki=y / =m
#排除带下划线的项：那些是包自带的配置子项（如 ..._Basic_Core_All），不是包名
grep -oE '^CONFIG_PACKAGE_[^=_]+=[ym]' "$CONFIG" | sed -e 's/^CONFIG_PACKAGE_//' -e 's/=[ym]$//' | sort -u > "$WORK/selected"
SELECTED=$(wc -l < "$WORK/selected")

#---------- 2. "可用包"集合 ----------
#权威来源：tmp/.packageinfo 的 Package: 字段（枚举树里所有包，含一个 Makefile 定义多个包的
#情形，比如 kmod-* 全在 package/kernel/linux/modules/Makefile 里，按目录名找会漏）。
#Provides: 是虚拟提供名 —— apk 允许"别的包提供这个名字"，也算可用。
#只有 packageinfo 不存在时才退回"含 Makefile 的目录名"，那种方式准确度较差（会误报 kmod-*）。
if [ -f "$PKGINFO" ]; then
	awk '
		/^Package: /  { print $2 }
		/^Provides: / { for (i=2; i<=NF; i++) { gsub(/,/, "", $i); if ($i != "") print $i } }
	' "$PKGINFO" | sort -u > "$WORK/avail"
	AVAIL_SRC="$PKGINFO"
else
	find package feeds -mindepth 2 -maxdepth 6 -name Makefile -printf '%h\n' 2>/dev/null | sed 's|.*/||' | sort -u > "$WORK/avail"
	AVAIL_SRC="Makefile 目录名（未找到 $PKGINFO，准确度较低，kmod-* 之类可能误报）"
fi
AVAIL=$(wc -l < "$WORK/avail")

#---------- 3. 依赖列表 ----------
#格式统一为 "包名<TAB>依赖token"，后面再统一清洗
: > "$WORK/deps_raw"

if [ -f "$PKGINFO" ]; then
	awk -v OFS='\t' '
		/^Package: / { pkg=$2; next }
		/^(Depends|Extra-Depends): / {
			sub(/^(Depends|Extra-Depends): /, "")
			n=split($0, arr, ",")
			for (i=1; i<=n; i++) print pkg, arr[i]
		}
	' "$PKGINFO" >> "$WORK/deps_raw"
else
	#兜底：直接解析选中包目录下的 Makefile。
	#必须自己拼 \ 续行 —— LUCI_DEPENDS 通常写成多行，只 grep 单行会把
	#第二行之后的依赖（本例里的 v2ray-geoip）整个漏掉。
	find package feeds -mindepth 2 -maxdepth 6 -name Makefile 2>/dev/null > "$WORK/mkfiles"
	awk -v sel="$WORK/selected" '
		BEGIN { while ((getline l < sel) > 0) want[l]=1 }
		{
			n=$0; sub(/\/Makefile$/, "", n); sub(/.*\//, "", n)
			if (n in want) print
		}
	' "$WORK/mkfiles" > "$WORK/mk_sel"
	if [ -s "$WORK/mk_sel" ]; then
		xargs awk -v sel="$WORK/selected" '
			BEGIN { while ((getline l < sel) > 0) want[l]=1 }
			FNR==1 {
				n=FILENAME; sub(/\/Makefile$/, "", n); sub(/.*\//, "", n)
				active=(n in want); buf=""; cont=0
			}
			!active { next }
			{
				line=$0
				sub(/[ \t]+$/, "", line)
				if (line ~ /\\$/) { sub(/\\$/, "", line); buf = buf " " line; cont=1; next }
				if (cont) { line = buf " " line; buf=""; cont=0 }
				if (line !~ /^[[:space:]]*(LUCI_)?DEPENDS[[:space:]]*[:+]?=/) next
				sub(/^[^=]*=[+]?/, "", line)     #去掉 "  LUCI_DEPENDS:=" / "  DEPENDS+="
				c=split(line, tok, /[ \t]+/)
				for (i=1; i<=c; i++) if (tok[i] != "") print n "\t" tok[i]
			}
		' < "$WORK/mk_sel" >> "$WORK/deps_raw" 2>/dev/null
	fi
fi

#---------- 4. 清洗依赖名并比对 ----------
#依赖 token 的几种常见形态：
#	+tcping           -> tcping
#	+libfoo (>=1.2)   -> libfoo（紧跟的括号项丢弃）
#	+libfoo(<1)       -> libfoo
#	@TARGET_xxx       -> 丢弃（Kconfig 条件，不是包名）
#	+PACKAGE_x:foo    -> foo（条件依赖，取冒号后面）
#	+kmod-xxx         -> kmod-xxx
awk -F'\t' -v avail="$WORK/avail" -v sel="$WORK/selected" '
	BEGIN {
		while ((getline l < avail) > 0) have[l]=1
		while ((getline l < sel) > 0) want[l]=1
		#基础库 / 工具链提供、树里没有同名包目录的（packageinfo 里一般都有，这里是兜底防误报）
		split("libc libgcc libm librt libpthread libdl libstdcpp libatomic libxcrypt", b, " ")
		for (i in b) have[b[i]]=1
	}
	{
		pkg=$1
		if (!(pkg in want)) next
		dep=$2
		sub(/^[ \t]+/, "", dep)              #去前导空格（packageinfo 里逗号后带空格）
		sub(/^\+/, "", dep)                  #去 + 前缀
		sub(/[ \t].*$/, "", dep)             #只留第一个词：+libfoo (>=1.2) -> +libfoo
		sub(/\(.*$/, "", dep)                #紧贴写法：+libfoo(<1) -> libfoo
		if (dep ~ /:/) sub(/^.*:/, "", dep)  #条件依赖：+PACKAGE_x:foo -> foo
		if (dep == "" || dep == pkg) next
		if (dep ~ /^@/) next                 #Kconfig 条件，不是包名
		if (dep ~ /^PACKAGE_/) next          #条件依赖前缀
		if (dep in have) next
		print pkg "\t" dep
	}
' "$WORK/deps_raw" | sort -u > "$WORK/missing"

MISSING=$(wc -l < "$WORK/missing")

#---------- 5. 输出 ----------
#说明：只告警不失败。缺失项会同时以 ::error:: 注解输出，GitHub 会把它们收集到
#      Annotations 区和 job 摘要里，不用翻日志也能看到。
echo "==================== 依赖预检（DepCheck） ===================="
echo "选中包 $SELECTED 个 / 可用包 $AVAIL 个（来源：$AVAIL_SRC）"
echo "--------------------------------------------------------------"

if [ "$MISSING" -eq 0 ]; then
	echo "✅ 未发现缺失依赖"
else
	echo "❌ 发现 $MISSING 条缺失依赖（这些包在源码树里不存在）："
	echo "   后果：编完所有包之后，package/install 阶段会报"
	echo "   ERROR: unable to select packages: xxx (no such package)"
	echo "   然后 make world 中断 —— 前面 1.5~3 小时白跑。"
	echo "--------------------------------------------------------------"
	#按包名归拢输出，方便照着改 Config
	awk -F'\t' '{ a[$1] = a[$1] " " $2 } END { for (p in a) printf "  %-32s ->%s\n", p, a[p] }' "$WORK/missing" | sort
	echo "--------------------------------------------------------------"
	echo "处理：在 Config/*.txt 里把这些包设成 =n，或换成源里确实存在的替代包。"
	head -50 "$WORK/missing" | while IFS=$'\t' read -r p d; do
		echo "::error::DepCheck: $p 依赖的 $d 在源码树中不存在，将在 package/install 阶段中断编译"
	done
fi
echo "==============================================================="

if [ -n "$GITHUB_STEP_SUMMARY" ]; then
	{
		echo "### 依赖预检（DepCheck）"
		echo ""
		echo "- 选中包：**$SELECTED** 个；可用包：**$AVAIL** 个（来源：$AVAIL_SRC）"
		if [ "$MISSING" -eq 0 ]; then
			echo "- 结果：✅ 未发现缺失依赖"
		else
			echo "- 结果：❌ **$MISSING** 条缺失依赖"
			echo ""
			echo "| 包 | 缺失的依赖 |"
			echo "|---|---|"
			awk -F'\t' '{ a[$1] = a[$1] " `" $2 "`" } END { for (p in a) printf "| %s |%s |\n", p, a[p] }' "$WORK/missing" | sort
		fi
	} >> "$GITHUB_STEP_SUMMARY"
fi

exit 0
