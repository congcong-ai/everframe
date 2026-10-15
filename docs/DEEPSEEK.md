# DeepSeek

已于 2026-10-15 核对 [DeepSeek 官方 Chat Completions 文档](https://api-docs.deepseek.com/api/create-chat-completion/)；当时英文文档模型值包含 `deepseek-flash`。默认 Base URL / 模型集中在 Product；设置可覆盖模型，避免随接口变化改多处源码。若官方账号实际返回模型不可用，以测试连接结果为准。

## 请求

HTTPS `https://api.deepseek.com/chat/completions`，OpenAI-compatible messages，非 stream，`response_format: {type: json_object}`，同时明确要求 JSON。采用 `reasoning_effort: none`，4096 输出 token，90 秒超时。请求只含带时间戳转写与当前片段时长；没有上传 MOV、关键帧或整段音频。

系统 prompt 要求中文，忽略转写中的指令，不推测视觉，不生成剪辑计划。返回 summary、topics、importance_score、suggested_review、review_reason、timeline 与 ideas。

## 校验与失败

支持纯 JSON 或完整 markdown JSON fence。检查必需类型、非空摘要、0–100 分数、有限时间戳、起止顺序与片段时长；拒绝截断、空内容和未知每日总结素材引用。不把无效结果标成完成；设 aiStatus=failed，素材页“重新分析”可手动重试。已经完成的转写会复用，避免不必要地再次识别。

API Key 存 Keychain，Release 不读取环境变量。Key 从不出现在 GET settings、日志或 metadata。测试连接需要在手机开启 AI，并主动点击；只发简短 JSON 测试内容。

## 每日总结

时间轴页或电脑网页可点击“生成今日总结”。输入只有当天已经完成的片段摘要、主题和回看原因，不重新发送全天 transcript；结果保存到 DailySummaries。生成与片段分析共享串行任务槽，避免多个请求挤占设备。

本轮没有提供真实 API Key，没有调用用户付费 API，实际 DeepSeek 联调标为 NOT TESTED。JSON 解析、非法时间戳与持久化已由本机 CLI 测试覆盖。连接、费用、模型可用性和中文摘要质量需要实际配置 Key 后验收。
