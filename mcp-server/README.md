# AutoSDK 本地文档 MCP

让支持本地 MCP（stdio）的 AI 查到 AutoSDK 的真实接口，再静态检查它写出的脚本。
不绑定 AI 品牌，不需要 API Key，不开网络端口、不连接手机、不执行提交的代码。
AI 客户端仍可能把工具结果和提交的脚本发送给其模型服务；“本地 MCP”不等于 AI 全程离线。

## 接入一次，以后让 AI 自己查

1. 电脑安装 Node.js 22 或更高版本。在本目录运行一次 `npm ci --ignore-scripts`。
2. 运行 `node server.mjs --config`，复制输出的接入配置。
3. 在你的 AI 工具的 MCP 设置中添加本地 / stdio 服务，并重新加载服务。

仓库根目录可运行 `npm run mcp:config`。当前工作目录无要求；服务自己定位资料。
客户端负责启动进程，不要另外常驻开一个终端，也不要用会往 stdout 打印 npm 标题的
`npm run mcp` 作为客户端命令。使用配置中的 Node **绝对路径**和脚本路径，保留中文与空格。

通用 JSON 模板如下；以 `--config` 自动生成的本机路径为准：

```json
{
  "mcpServers": {
    "autosdk-docs": {
      "command": "C:/Program Files/nodejs/node.exe",
      "args": ["E:/ios脚本框架开发/mcp-server/server.mjs"]
    }
  }
}
```

不同客户端的配置外层可能叫 `mcpServers`、`servers`，或使用可视化表单。
需要填写的核心字段相同：名称 `autosdk-docs`、传输 `stdio`、命令 `command`、参数 `args`。
只支持远程 HTTP MCP 的客户端不能直接用此服务；不要为此把它暴露到公网。
本项目不会修改任何 AI 客户端配置，不会自动接管聊天或保证 AI 必定使用工具。

接入后对 AI 说：

> 写 AutoSDK 脚本前，先用 autosdk-docs 的 search_api 搜索，get_api 核对准确签名、
> 参数、返回值和权限限制，写完调用 validate_script。查不到就明确说明，不要猜函数名。
> 我用的手机端 SDK 版本是……；不要把静态检查通过说成已在手机运行成功。

试用：让 AI 搜索“小白点”，应能查到 `device.setAssistiveTouchEnabled(enabled: boolean)`，
文档会说明私有权限、未知状态和回读限制。让 AI 检查 `device.madeUp();`，应报告不存在该成员。

## 工具与资料

| 工具 | 输入 | 输出 |
| --- | --- | --- |
| `search_api` | `query`；可选 `limit`（1–20）、`offset` | 中文/英文匹配的函数、类型和文档组，返回版本和下一页 |
| `get_api` | 精确 `name`，来自搜索结果 | 重载、参数、返回类型、原始文档/示例、限制、关联类型 |
| `validate_script` | `code`；可选 `language: javascript / typescript` | 错误位置、类型/语法诊断、警告；始终 `executed: false` |

资源 `autosdk://guide` 提供写作流程和运行时边界。`AutoSelectorBuilder.findOne` 等
`instance` 结果是类型实例成员，不能把类型名作为全局变量使用。类型名（如
`AutoNodeObject`）可用 `get_api` 查询属性结构。`doc:N` 是文档组，**不是可调用函数**。
同组示例可能演示不同函数，以精确签名为准；缺少示例时不会自动编造。

数据直接来自 `types/autosdk.d.ts` 与 `tools/generate-api-reference.mjs`，包含所有声明的
全局/模块可调用签名、接口实例成员、类型结构与中文文档，保留别名/重载。
每个结果都带 SDK 版本；不猜测首次引入版本，也不把资料版本当成手机已安装版本。

## 静态检查边界

- 脚本只作为内存中的文本交给 TypeScript 检查；不会 `eval`、运行、访问手机或写文件。
- 编译器只读取随包附带的可信 AutoSDK/ES2017 声明，不读工作区、tsconfig、第三方包或输入指定的文件。
- 不允许 import/export、triple-slash 引用或 `@ts-ignore / @ts-nocheck / @ts-expect-error`。
- 单次最多 65,536 个 UTF-16 码元，单个检查线程、8 秒超时和 192 MiB 旧生代堆限制。
  取消、超时、忙碌、线程异常都不报告检查通过。协议输入缓冲封顶 1 MiB。
- `valid` 只表示没有检测到静态错误；必须同时查看 `status` 和 `warnings`。
  `any`、动态属性和类型断言可能绕过检查；会对可检测的绕过点告警，但不承诺穷尽。
- TS 检查通过后仍要经 VS Code 插件转译成 JavaScript，不能直接把 TS 交给手机 JavaScriptCore。
- 不验证运行逻辑、图片存在性、坐标正确性、签名/权限、低端机保活或真机可用性。

## 更新、测试和分发

仓库开发者：修改权威声明/元数据后，在根目录运行 `npm run mcp:generate`，
再运行 `npm run mcp:check`、`npm run mcp:test` 和项目全量验证。
`npm run verify` 检查源文件与生成数据的 SHA-256，防止旧资料混入新版本。
`tools/bump-version.mjs` 会同步 MCP 包及锁文件版本，之后仍需重新生成资料。

Release 附件 `autosdk-docs-mcp-版本.tgz` 是独立服务包（不含 Node 和 node_modules）。
解压到固定位置（内容在 `package` 子目录），进入该目录执行
`npm install --omit=dev --ignore-scripts`，再运行 `node server.mjs --config` 注册。
安装依赖需要联网；安装完成后查询、检查不访问网络。SDK 声明随包携带，无需整个项目。

开发仓库和分发包共用 `npm-shrinkwrap.json` 锁定依赖，可用 `npm ci --ignore-scripts` 复现。分发包只提供运行所需文件；
官方 MCP SDK 2.0.0 固定主依赖版本，支持传统 initialize 和 2026-07-28 的协商协议，测试覆盖二者。

协议依据：[MCP 服务开发文档](https://modelcontextprotocol.io/docs/develop/build-server)、
[官方 TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)。
