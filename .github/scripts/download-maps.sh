#!/usr/bin/env bash
# download-maps.sh — 从 GitHub Actions artifact 下载服务端地图文件
# 使用: bash download-maps.sh [run_id]
# 代理: 通过环境变量设置 HTTP_PROXY, HTTPS_PROXY
# 默认代理: http://192.168.100.3:7890

set -euo pipefail

RUN_ID="${1:-latest}"
PROXY="${HTTP_PROXY:-http://192.168.100.3:7890}"
OWNER="callmefree"
REPO="azerothcore-wotlk"
BRANCH="feature/acoremods"

echo "=== 地图文件下载脚本 ==="
echo "仓库: $OWNER/$REPO"
echo "分支: $BRANCH"
echo "代理: $PROXY"
echo ""

# 设置代理
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"

if [ "$RUN_ID" = "latest" ]; then
    echo "正在获取最新构建 ID..."
    API_URL="https://api.github.com/repos/$OWNER/$REPO/actions/runs?branch=$BRANCH&status=success&per_page=1"
    RUN_ID=$(curl -sS -H "Accept: application/vnd.github+json" "$API_URL" | python3 -c "import sys,json; print(json.load(sys.stdin)['workflow_runs'][0]['id'])" 2>/dev/null)
    echo "最新构建 ID: $RUN_ID"
fi

echo "正在获取 artifact 列表..."
ARTIFACTS_URL="https://api.github.com/repos/$OWNER/$REPO/actions/runs/$RUN_ID/artifacts"
ARTIFACTS=$(curl -sS -H "Accept: application/vnd.github+json" "$ARTIFACTS_URL")

echo "可用的 artifact:"
echo "$ARTIFACTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for a in data.get('artifacts', []):
    size_mb = a['size_in_bytes'] / 1024 / 1024
    print(f\"  {a['id']:>8}  {a['name']:<40} ({size_mb:.1f} MB)\")
"

# 只下载包含地图的 artifact — `azerothcore-acoremods-windows` 包含 server/data/
ARTIFACT_NAME="azerothcore-acoremods-windows"
ARTIFACT_ID=$(echo "$ARTIFACTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for a in data.get('artifacts', []):
    if a['name'] == '$ARTIFACT_NAME':
        print(a['id'])
        break
")

if [ -z "$ARTIFACT_ID" ]; then
    echo "[ERROR] 找不到 artifact: $ARTIFACT_NAME"
    exit 1
fi

echo "下载 $ARTIFACT_NAME (artifact ID: $ARTIFACT_ID)..."
DOWNLOAD_URL="https://api.github.com/repos/$OWNER/$REPO/actions/artifacts/$ARTIFACT_ID/zip"
curl -L -o "server-maps.zip" -H "Accept: application/vnd.github+json" "$DOWNLOAD_URL"

echo "解压中..."
mkdir -p server-data
cd server-data
unzip -q ../server-maps.zip
echo "解压完成:"
ls -la data/ 2>/dev/null || echo "(无 data/ 目录)"
echo ""
echo "如需安装到服务端，请将 data/ 目录复制到服务端安装目录下"
