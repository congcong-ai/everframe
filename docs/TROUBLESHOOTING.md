# 常见问题

## 编译有 SDK 但找不到 Scheme destination

本机 Xcode 26.5 的 Scheme 目标枚举报 “iOS 26.5 is not installed”，没有连接真机，也没有 simulator runtime。`./scripts/build.sh` 直接构建 target，可验证 arm64 编译链接，但不证明能安装。先连接解锁的真实 iPhone，在顶部运行目标选择该手机；如不可选，按 Devices and Simulators 的具体提示处理。没有模拟器 runtime 时也可能显示 Get，不能据此断定缺少真机支持。Components 内标为 iOS 16.x Simulator 的下载不是运行 iOS 16 真机的前提。不要把 Deployment Target 改成 17／18，也不要直接忽略签名后声称安装成功。

说明依据：[Apple 的 Xcode 组件说明](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。

## Signing 错误

确认 Accounts 已登录、Personal Team 已选择、Bundle Identifier 全局唯一。免费 profile 周期性过期，重新 ⌘R。不要打开自动上传或 Archive 分发。更新尽量保持原 Bundle Identifier／Team，先备份再做可能导致数据丢失的操作。

## 没有画面或无声音

模拟器不支持真实摄像头验收。手机系统设置允许摄像头和麦克风；检查是否有来电、其它 App 或系统占用摄像头。开始后仍失败，先关闭 AI，用最小录像复现，查看诊断事件。不能只看 Preview 就认定文件有声音。

## 不能打开电脑网页

手机 App 保持前台；设置开关已开，本地网络权限允许；两台设备同一 Wi-Fi，没有访客网络隔离、VPN 或路由器客户端隔离。确认显示真实 IPv4 地址和开启状态，端口 8080 未被占用。iPhone IP 改变时使用新地址。后台或温度 critical 会主动关闭网页服务。

## 配对后仍 401

Token 随 App 重启／配对码重置失效，浏览器点击退出再配对。五次错误后等一分钟，不要关闭鉴权排错。Safari 隐私模式可能清除 LocalStorage。

## Speech 不可用

先点授权，检查系统 Speech 权限和 zh-CN 可用性。A11 未必支持本地中文识别；在充分知情后可以单独同意在线识别。Apple 服务可能限流，稍后从素材页重试；失败不自动无限重试。10 分钟片段会拆 55 秒块，不能指望单个请求处理完整十分钟。

## AI 一直等待

默认需要 AI 开启、可用 Key、Speech 授权、Wi-Fi 和充电，温度不能 serious／critical，App 保持前台。当前片段必须先录完。关闭自动分析时，素材页可手动“重新分析”。Debug 强制 AI 不绕过温度和隐私开关。

## 空间不降、录制停止

保护素材与当前片段不会被循环删除，已保护内容超限时需主动导出后确认删除。剩余空间低于 1 GB 会停止。Debug 模拟低磁盘开关也会停止；关闭再开始。不要真实填满手机磁盘来测试。

## 文件损坏或启动读配置失败

先用 Finder 文件共享／Xcode 容器导出备份，保留原 MOV／JSON。恢复扫描保守锁定无 metadata 的录像；损坏 MOV 留在素材列表并提示。配置文件损坏时启动显示错误而不是静默覆盖资料，备份后再检查 settings.json。不要先卸载。无法保证修复强杀时尚未封装的 MOV。

## 日志与隐私

设置可查看／导出滚动诊断日志，最大约 1 MB 后重新开始。只记录事件。Debug AI JSON 页面含个人内容，分享截图前自行检查。排错不应把 Key、全量转写或原视频粘贴到公共 issue。
