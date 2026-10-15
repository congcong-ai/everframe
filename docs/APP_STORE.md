# 未来上架准备

当前只为 Xcode Personal Team 开发安装，不创建 App Store Connect 记录，不上传，不引入付费 entitlement。摄像头／麦克风／Speech／本地网络的用途均在 Info.plist 中明确说明，没有后台音频、定位或 VoIP 模式。

上线前仍需：付费开发者账号与分发签名、唯一产品身份和图标素材、隐私政策 URL、App Privacy 信息、第三方 AI 数据处理说明与同意流程复核、版本截图、审核备注、可重现真机稳定性证据。**未做过 App Store 审核，不承诺必然通过。**

Resources/PrivacyInfo.xcprivacy 声明本机文件 metadata 访问 C617.1、检查空间以决定写入／清理 E174.1，以及展示磁盘空间 85F4.1。电脑控制开关明确允许向同一局域网中本人的已配对设备展示状态与磁盘信息；无互联网发送该空间信息。上架前应再次核对 [Apple 所需原因 API 文档](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。该 manifest 不是完整 App Privacy 问卷的替代品。

审核备注应解释：闲置 iPhone 固定工作位置，持续前台明确录制；不提供隐蔽录像，不伪造后台能力，不使用 Screen Recording API 代替摄像头，不剪辑视频。系统打断摄像头时展示状态并要求用户手动恢复。

正式上架前需要明确 Apple Speech 在线路径、DeepSeek 处理方的数据政策、用户知情同意与删除语义。当前实现不代替法律或商店审核结论。
