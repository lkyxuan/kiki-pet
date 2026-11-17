# Kiki 桌宠

屏幕角落里的 Kiki：半身趴在右下角，衣服按时段换，有“要你的”时肩上出橙色数字、冒气泡，点她打开 Kiki 里那张卡。

这个库只有 Mac 外壳（`main.swift`）：透明、无边框、永远置顶、所有桌面都在的小窗，里面一个透明 WKWebView 加载 Kiki 后台的 `/pet.html`。画面、状态、“要你的”都在 Kiki 那边（Kiki 后台提供 `/pet.html`、`GET /api/pet`、`/api/events` 的 `pet` 事件），需要 Kiki 0.5.22 起。

## 打包

    ./build.sh          # → out/KikiPet.app（本机临时签名）
    open out/KikiPet.app

连哪台 Kiki：默认跟 Kiki.app 一样（读 `com.lkyxuan.kiki` 偏好里的 `server`，没选或本机就是 `http://localhost:4567`）。Kiki.app 连的是远程（比如 MacBook 经 Tailscale 连 Mac mini），桌宠也连那台，Kiki.app 改连别的电脑 15 秒内跟着换。试没发版的后台：`defaults write com.lkyxuan.kiki.pet server http://localhost:4612`，改回：`defaults delete com.lkyxuan.kiki.pet server`。

## 外壳管什么

- 透明处点穿：网页报立绘的 27×36 不透明格子 + 数字/小灯/气泡位置（`mask` 消息），外壳每秒 30 次看鼠标，在她身上才收鼠标，不用辅助功能权限。
- 单击（`kikiPet.click()` → 打开 `kiki://need` 或 `kiki://open`）、拖动（记住位置）、悬停冒气泡、右键菜单：打开 Kiki、换装、大小、免打扰、藏起来 1 小时、开机自动出来、退出。

## 真机记录

- 2026-11-17 Mac mini，macOS 27.2.1，Swift 6.4.2 arm64：编译无报错无警告，透明背景、立绘、数字、气泡都对。
