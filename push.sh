#!/bin/bash
# 首次推送脚本：把本地 OpenWRT-CI 仓库推到 GitHub
# 用法：bash push.sh
# 前提：GitHub 上已创建空仓库 yoolingchiang/OpenWRT-CI
#       （不要勾选 添加自述文件 / .gitignore / 许可证）

set -e

GH_USER="yoolingchiang"
GH_REPO="OpenWRT-CI"

cd "$(dirname "$0")"

# 1) 确认本地状态干净
if [ -n "$(git status --porcelain)" ]; then
	echo "!! 工作区有未提交改动，请先提交："
	git status --short
	exit 1
fi

# 2) 配置 remote（已存在则更新）
if git remote get-url origin >/dev/null 2>&1; then
	git remote set-url origin "https://github.com/$GH_USER/$GH_REPO.git"
else
	git remote add origin "https://github.com/$GH_USER/$GH_REPO.git"
fi
echo "remote: $(git remote get-url origin)"

# 3) 推送
# 首次推送时 GitHub 会弹窗要求登录：
#   用户名填 GitHub 用户名，密码栏粘贴 PAT（细粒度令牌，需 Contents: Read and write）
echo
echo ">>> 开始推送，若提示输入凭据："
echo ">>>   Username: $GH_USER"
echo ">>>   Password: 粘贴你的 PAT（不是账号密码）"
echo
git push -u origin main

echo
echo "推送完成：https://github.com/$GH_USER/$GH_REPO"
