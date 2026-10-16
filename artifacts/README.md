# 本地安装包

从项目根目录运行：

```sh
./scripts/package.sh
```

- `ios/`：iOS 开发签名 IPA，仅可安装到签名描述文件授权的设备；开发签名有有效期。使用 Xcode 的 Devices and Simulators → 选择手机 → Installed Apps 下方的 `+` 安装，保留相同签名覆盖安装，避免卸载丢失素材。
- `android/`：Android 开发签名 APK，可直接侧载体验。沿用本机原有开发签名，版本号递增；不是商店发行签名。
- `SHA256SUMS`：这两份安装包的 SHA-256 校验值，可在本目录运行 `shasum -a 256 -c SHA256SUMS` 检查。

二进制、签名描述文件及校验输出不提交 Git。此目录仅提交本说明。公开分发 Android APK 使用 GitHub Release 附件；iOS 开发 IPA 包含设备授权信息，不上传公开 Release。

脚本只使用本机缓存的 iOS 开发证书和描述文件，不自动申请或更新签名。若签名已过期，需要先在 Xcode 为自己的设备完成签名配置，再重新运行。Android 工具链要求见 `android/README.md`。

构建通过不代表真机录制已验收；锁屏音画连续性、双摄、自动亮度及实际耗电仍须实测。
