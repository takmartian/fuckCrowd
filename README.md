# fuckCrowd

> 让 SealSuite / CorpLink（飞连）的「必须安装 CrowdStrike」准入策略闭嘴 —— 把「没装」伪装成「已装」，VPN 照常连。

公司零信任 VPN（火山引擎飞连 / SealSuite / CorpLink）在连接时会检查终端是否安装了 CrowdStrike Falcon。没装就弹「请安装 CrowdStrike」，点击连接被服务端拒绝：

        VPN连接请求被阻断，请联系企业管理员 (3015 / 10210002)

本仓库提供 Windows 与 macOS 两端的伪装方案，无需真正安装 EDR，让客户端的「已安装软件」检查认为 CrowdStrike 已安装，从而放行 /vpn/conn。

## 原理

拦截发生在网关 /vpn/conn，放行与否取决于客户端上报的 SoftwareRisk 是否清空。关键发现：**客户端只做「已安装软件清单」的枚举比对，不校验进程、服务或文件是否真实存在。**

| 平台 | 客户端如何判定 CrowdStrike 已安装 | 本项目的伪装点 |
|------|-----------------------------------|----------------|
| Windows | corplink-service.exe 读注册表 ...\\CurrentVersion\\Uninstall 下的 DisplayName / Publisher，与服务端 baseline 策略比对（software_name "Crowdstrike" / software_id "CrowdStrike Windows Sensor" / publisher "CrowdStrike, Inc."） | 往注册表 HKEY_CURRENT_USER 写几条卸载项 |
| macOS | corplink-service 用 Spotlight 元数据 kMDItemCFBundleIdentifier 枚举已装 App，比对策略里的 software_id（com.crowdstrike.falcon.App） | 造一个 /Applications/Falcon.app 空壳并让 Spotlight 索引到它 |

两端都不检查服务 / 进程 / 文件，所以「清单里出现它」就够了。

## 用法

### Windows

1. 双击 Install-CrowdStrike-Spoof.reg（写入 HKEY_CURRENT_USER，无需管理员权限）。
2. 等下一轮策略刷新（约 15 分钟），或直接在客户端重新点击连接。
3. 撤销：双击 Remove-CrowdStrike-Spoof.reg。

### macOS

    ./falcon-shell.sh check      # 核对：是否装了 CorpLink、策略要求的 software_id、Spotlight 是否开启
    ./falcon-shell.sh install    # 造壳 + 签名 + 注册 + mdimport，并自动试连一次
    ./falcon-shell.sh status     # 复查 bundle id / Spotlight 索引 / VPN 状态
    ./falcon-shell.sh reindex    # 重启或 Spotlight 重建后若又被拦，跑这个
    ./falcon-shell.sh uninstall  # 移除伪装（之后 VPN 会恢复被拦）

注意：必须在目标机器本机运行 install —— macOS 的生效依赖 Spotlight 在本机把壳的 bundle id 索引出来，把 Falcon.app 直接拷过去而不 mdimport 不会生效。若 VPN 节点不叫 AUTO，改脚本顶部 NODE 变量。

## 适用前提与注意

- 同租户、同策略：目标机器需被同一条应用管控策略要求 CrowdStrike。macOS 的 check 会打印策略实际要求的 software_id，若不是 com.crowdstrike.falcon.App，改脚本顶部 BUNDLE_ID。
- 客户端版本：本项目在 CorpLink / SealSuite 3.3.22 实测有效；不同版本检测机制可能不同（有的会校验版本、进程存活或 CrowdStrike 云侧心跳，那种情况清单欺骗可能不够）。
- 性质：这是主动改写上报给公司的合规遥测（把未安装报成已安装），请自行判断在所在环境是否可接受。
- 不是绕过认证：飞连的账号登录、设备绑定等照常，只针对「CrowdStrike 已安装」这一项准入条件。

## 文件

    Install-CrowdStrike-Spoof.reg     Windows 伪装（双击导入）
    Remove-CrowdStrike-Spoof.reg      Windows 撤销
    macos/falcon-shell.sh             macOS 伪装脚本（check/install/reindex/uninstall/status）
