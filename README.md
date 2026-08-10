# NBA 2K20 iOS Mod Menu

生涯模式修改菜单 —— 海鸥出品

## 功能

- **全属性拉满**（抢断/盖帽/速度/控球/灌篮/意识/篮板/力量/敏捷/体力… 共18项 → 可调 50~99）
- **锁比赛时间**（冻结在 11:00）
- **锁进攻时间**（冻结在 24 秒）

## 原理

2K 自研引擎把全部球员能力值存在 `__bss` 段的一个 float 数组里，通过 `TuneData_GetPlayer*` 系列 getter 读取（地址已通过符号表+反汇编逆向确认）。本插件不 hook 代码（非越狱设备上 W^X 保护会拦截），而是**直接向该数组写 float 值**，并由一个后台线程每 50ms 刷新，防止游戏逻辑把值覆盖回去。因此**不需要越狱，TrollStore 直接装**。

逆向确认的地址（主程序 vmaddr）：

```
能力数组结构  0x10227A2C8   (struct { count@+4, data@+8 })
玩家 slot 指针 0x10270C034   (int)
比赛时间      0x102703060   (float)
进攻时间      0x102703090   (float)
能力偏移      0x04 抢断 ~ 0x8c 持球防守 (每项 float, 间隔 0x8)
```

## 编译（GitHub Actions 云编译）

1. 把本项目推到你的 GitHub 仓库（main 分支）
2. Actions 自动在 macOS runner 上用 Theos 编译
3. 从 Actions 的 artifacts 下载 `nba2k20mod.dylib`

> 本地编译需要 macOS + Theos + iOS SDK，Windows 上无法直接编译，所以走 GitHub Actions。

## 注入安装（TrollStore）

拿到 `nba2k20mod.dylib` 后：

1. 解压解密后的 IPA 到 `Payload/NBA 2K20.app/`
2. 用 `insert_dylib` 把 dylib 注入主程序（arm64 版）
3. 复制 dylib 到 `Payload/NBA 2K20.app/nba2k20mod.dylib`
4. 去掉主程序旧签名（jtool2 `--sign --inplace` 或直接无签名）
5. 重新打包成 IPA，TrollStore 安装

详细步骤见对话记录中的逐步操作。
