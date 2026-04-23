# Air724UG Local

Air724UG 短信转发、来电通知、语音信箱项目的干净源码仓库。

这个仓库当前主要包含两部分：

- `script/`
  Air724UG 设备端 Lua 脚本，支持从 `config.bin` 加载配置。
- `cloudflare-config-generator/`
  可部署到 Cloudflare Pages 的静态配置生成器，用于生成可直接下发到设备的 `config.bin`。

## 当前状态

- 设备端已支持 `CONFIG_BIN_KEY`
- 设备端优先解析 JSON 安全配置
- 设备端保留 Legacy Lua 密文回退能力
- Cloudflare 配置生成器已完成本地和实机联调
- 页面生成的 `config.bin` 已在 Air724UG 设备上验证可正常生效

## 目录说明

```text
script/
  audio/                 音频资源
  handler/               来电、短信、按键处理
  lib/                   LuatOS 依赖库
  utils/                 项目工具函数
  config.lua             默认配置
  main.lua               启动入口
  usbmsc.lua             U 盘挂载与写入逻辑

cloudflare-config-generator/
  index.html             页面结构
  styles.css             页面样式
  app.js                 生成器逻辑
  vendor/crypto-js.min.js
  deploy-pages.ps1       Wrangler 部署脚本
  smoke-test.js          本地导出兼容性自检
```

## 快速开始

### 设备端

把 `script/` 下脚本烧录到 Air724UG 设备。

如果需要通过 U 盘配置设备，把生成好的 `config.bin` 放到设备暴露出来的存储根目录即可。

### 配置生成器

本地直接打开：

```text
cloudflare-config-generator/index.html
```

或者部署到 Cloudflare Pages。

详细说明见：

- [cloudflare-config-generator/README.md](./cloudflare-config-generator/README.md)

## Cloudflare Pages 部署

### 手动上传

只上传 `cloudflare-config-generator/` 目录里的静态文件，不要上传整个仓库。

### Wrangler

```powershell
wrangler login
powershell -ExecutionPolicy Bypass -File .\cloudflare-config-generator\deploy-pages.ps1 -ProjectName <你的Pages项目名>
```

如果项目还没创建：

```powershell
powershell -ExecutionPolicy Bypass -File .\cloudflare-config-generator\deploy-pages.ps1 -ProjectName <你的Pages项目名> -CreateProject
```

## 本地自检

```bash
node cloudflare-config-generator/smoke-test.js
```

这个脚本会验证：

- JSON 模式 `config.bin` 生成与回读
- Legacy Lua 模式兼容性
- 关键字段是否正确进入导出载荷

## 鸣谢

感谢 [TheHot](https://github.com/TheHot/) 公开了相关思路和脚本，本仓库的整理、适配与扩展工作是在这些公开资料的基础上继续推进的。

## 说明

- 本仓库已移除本地 Luatools、大日志、临时构建目录等非源码内容
- `script/config.lua` 中的通知密钥默认为空，使用前请自行填写，或通过 `config.bin` 覆盖
