#!/bin/bash
# fuckCrowd —— macOS 端 CrowdStrike 伪装壳
# 让飞连/CorpLink 的"已装App"枚举把目标 bundle id 当作已安装，清除 SoftwareRisk，使 /vpn/conn 放行。
# 用法: ./falcon-shell.sh {check|install|reindex|uninstall|status}
# 重要: 生效依赖【本机】Spotlight 把 bundle id 索引出来。必须在目标机器上跑 install，
#       把 Falcon.app 拷过去而不 mdimport 是不生效的。
set -e

# ==== 按目标机器改这里 ====
BUNDLE_ID="com.crowdstrike.falcon.App"   # 策略要求的 software_id (用 check 查看实际值)
APP_NAME="Falcon"                         # 显示名/可执行名
B=/Applications/Falcon.app                # 壳路径(与真实安装路径一致)
NODE="AUTO"                               # 试连用的 VPN 节点名(没有就忽略试连报错)
# ==========================

LS="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
CLI=/usr/local/corplink/corplink-cli
LOG=/usr/local/corplink/logs/corplink.log

check() {
  echo "[1] CorpLink CLI: $([ -x "$CLI" ] && echo OK || echo '未找到 —— 该机可能没装 CorpLink/SealSuite，本壳不适用')"
  echo "[2] Spotlight: $(mdutil -s / 2>/dev/null | tail -1)"
  if [ -r "$LOG" ]; then
    echo "[3] 策略要求的 software_id(最近):"
    grep -a -o -E "software_id:[a-zA-Z0-9._]+" "$LOG" 2>/dev/null | sort -u | sed 's/^/    /' | tail -10
    if grep -aq "software_id:$BUNDLE_ID" "$LOG" 2>/dev/null; then
      echo "    -> 命中 $BUNDLE_ID：本壳适用"
    else
      echo "    -> 未命中 $BUNDLE_ID：把脚本顶部 BUNDLE_ID 改成上面实际要求的 id"
    fi
  else
    echo "[3] 日志不可读(sudo 看 $LOG)，跳过策略核对"
  fi
}

install() {
  mkdir -p "$B/Contents/MacOS" "$B/Contents/Resources"
  printf '#!/bin/sh\nexit 0\n' > "$B/Contents/MacOS/$APP_NAME"; chmod 755 "$B/Contents/MacOS/$APP_NAME"
  printf 'APPL????' > "$B/Contents/PkgInfo"
  cat > "$B/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>7.11.0</string>
  <key>CFBundleVersion</key><string>81121409</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHumanReadableCopyright</key><string>Copyright (c) 2024 CrowdStrike, Inc.</string>
</dict>
</plist>
PLIST
  codesign --force --sign - "$B" 2>/dev/null || true
  "$LS" -f "$B" 2>/dev/null || true
  mdimport "$B" 2>/dev/null || true
  echo "已安装，验证中……"
  sleep 1
  echo "  mdfind: $(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | head -1 || echo '未索引(再跑 reindex)')"
  [ -x "$CLI" ] && echo "  试连: $($CLI vpn connect --name "$NODE" --mode split 2>&1 | tr -d '\n' | head -c 220)"
}

reindex() {
  "$LS" -f "$B" 2>/dev/null || true
  mdimport "$B" 2>/dev/null || true
  echo "reindexed."
}

uninstall() {
  "$LS" -u "$B" 2>/dev/null || true
  /bin/rm -rf "$B"
  echo "removed. 注意: 移除后 VPN 会重新被 3015 拦截。"
}

status() {
  echo "bundle id: $(plutil -extract CFBundleIdentifier raw "$B/Contents/Info.plist" 2>/dev/null || echo MISSING)"
  echo "spotlight: $(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | head -1 || echo none)"
  [ -x "$CLI" ] && "$CLI" vpn status 2>/dev/null | head -8
}

case "$1" in
  check) check;; install) install;; reindex) reindex;; uninstall) uninstall;; status) status;;
  *) echo "用法: $0 {check|install|reindex|uninstall|status}";;
esac
