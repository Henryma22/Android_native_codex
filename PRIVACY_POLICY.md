# Android Codex 隐私说明

Android Codex 的主要数据面在 Android 设备本地运行：workspace 路径、session 历史、草稿、
运行时配置和登录状态由应用本地保存，不需要连接 PC Bridge 或远程机器。

当用户使用 OpenAI 登录时，请求按照 Codex runtime 的登录协议发送到 OpenAI。用户显式配置并
启用第三方 OpenAI-compatible provider 时，请求会发送到用户填写的 provider 地址；该 provider
的隐私政策由用户自行确认。第三方 provider 模式与 OpenAI auth 模式互斥。

Root/PRoot 执行的命令、读取的文件和写入的配置默认发生在本机。应用不会因为执行 Root 命令
而自动把 workspace 上传到本项目维护的服务器；系统日志、截图和调试产物是否导出由用户控制。

使用本项目进行测试时，请勿把 API key、OAuth token、个人文件或 KernelSU 私密配置加入 issue、
构建日志、端口登记表或 Git 提交。
