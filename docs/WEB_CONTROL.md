# 局域网电脑控制

采用系统 Network.framework / NWListener，无第三方 HTTP 依赖。只在用户开启且 App 前台、温度非 critical 时监听 Wi-Fi 的 8080 端口。没有互联网远程控制、端口映射或后台常驻。iPhone 不能杀其它 App 的端口；如果端口不可用，明确显示启动失败。

## 使用

手机和电脑连接相同可信 Wi-Fi，手机允许本地网络权限。设置页开启后显示 Wi-Fi IPv4 URL 与二维码；二维码只包含 URL。电脑输入六位配对码获得会话。更新配对码／关闭再开启电脑控制／重启 App 会撤销会话。会话只在内存保存，最长 12 小时；浏览器 LocalStorage 保存令牌，退出配对清理本浏览器。

配对五次失败后全局冷却一分钟。令牌使用 SecRandomCopyBytes 生成 256 位随机数，最多保留八个会话。读取接口也要求认证，避免同一 Wi-Fi 的未配对设备读取摘要。

使用明文 HTTP，不防御恶意网络内窃听或主动中间人。不要在公共／不可信 Wi-Fi 开启。允许同一人的电脑显示磁盘信息由设置开关明确告知。没有使用 cookie 进行隐式认证；修改请求要求 JSON 和 Bearer Token；有 Origin 时要求与当前 Host 一致。无 CORS 授权。网页内容用 textContent 渲染，避免转写／模型文本进入 HTML。

## 接口

| 方法与路径 | 说明 |
| --- | --- |
| POST /api/pair | `{ "code": "六位数字" }`，无需旧令牌 |
| GET /api/status | 记录状态、连续／今日秒数、占用／剩余字节、AI 状态 |
| POST /api/start | 手机必须前台；失败返回 409 和具体提示 |
| POST /api/stop | 请求停止；实际封装可能稍后完成 |
| POST /api/keep | `{ "minutes": 10或30或60 }` |
| GET /api/clips | 最近最多 500 段 metadata，不传原始视频 |
| POST /api/clips/{UUID}/lock | 保留；当前段转 pendingLock |
| POST /api/clips/{UUID}/unlock | 取消保留 |
| GET /api/timeline | 当日事件；时间为 ISO 8601 |
| GET /api/daily-summary | 本地当日总结或 null |
| POST /api/daily-summary | 异步请求生成当日总结 |
| GET /api/settings | 非秘密配置，不含 API Key |
| POST /api/settings | JSON 字段 segmentMinutes、maxStorageGB、retentionDays、minimumFreeGB，须一起传入 |

除配对外，以上均需 `Authorization: Bearer <token>`。POST 使用 `Content-Type: application/json`；无参数传 `{}`。隐私同意、Key、AI 开关和网络启停只在手机修改。无删除 API。快照为可选项，本版未提供。

## HTTP 边界

仅支持 GET／POST 的 HTTP/1.1 Content-Length，不支持 chunked、流水线或长连接。头部最多 8 KB，body 最多 32 KB，最多八个连接，十秒后关闭未完成连接。重复头、非法长度和超限请求拒绝。响应包含 no-store、nosniff 和 CSP，不加载 CDN。浏览器五秒轮询，轮询不重叠。

CLI 传输测试在 Mac 的 18080 使用真实 NWListener、URLSession、PairingStore，业务返回值为夹具；不能替代 iPhone WebAPI 的真机测试。测试脚本先清理端口，退出自动关闭 listener。
