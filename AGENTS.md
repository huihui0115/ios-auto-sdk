# AGENTS.md — AutoSDK 开发守则（新 AI 必读）

嵌入式 iOS JavaScript 自动化 SDK（JS 脚本运行在宿主 App 的 JavaScriptCore 中，
通过 bridge 调原生能力）。对标 EasyClick / AScript / TrollAutoScript / kuaijs。
仓库根：当前目录。分支：`main`，提交信息格式 `Feat: round N - ... (vX.Y.Z)`。

## 每次改动后必须跑

```
npm run verify          # 全量一致性检查（必须通过）
npm test                # Node 端测试（bootstrap 行为测试）
npx -y -p typescript@5.6.3 tsc -p jsconfig.json --noEmit   # d.ts 类型检查
npm run docs            # 重新生成 docs/api-reference.html
```

## 铁律

1. **bootstrap 单一权威源**：bootstrap 的 JS 代码只在
   `tools/bootstrap-source.js` 里改，改完跑 `npm run regenerate:bootstrap`。
   **绝不直接手改** `Sources/AutoSDK/AutoBootstrapScript.m`。
   `npm run verify` 会校验两者完全一致（不一致直接失败）。
2. **60KB 预算**：bootstrap 解码后 `script.length <= 61440`（UTF-16 码元，与
   verify 口径一致）。加功能必须先压缩别处。当前用量见 commit 信息。
3. **版本四件套同步**：`package.json` / `package-lock.json` /
   `AutoSDK.podspec` / `Sources/AutoSDK/AutoSDKVersion.m` 版本号必须一致，
   用 `node tools/bump-version.mjs X.Y.Z` 统一改，再手工修 CHANGELOG 的
   占位块（bump 会插入损坏的 "(fill in)" 块）。
4. **d.ts ↔ 文档 ↔ verify 闭环**：在 `types/autosdk.d.ts` 新增的每个
   `declare function` 和 interface 方法，都必须出现在
   `tools/generate-api-reference.mjs` 的某个 `sig:` 或示例里，
   否则 `npm run verify` 报 "API reference must document every declared function"。
5. **行尾陷阱**：仓库文件 CRLF/LF 混用。用 Node 脚本读文件时模板字符串里的
   换行要先按目标文件行尾转换（`.replace(/\n/g, '\r\n')`），替换前必须验证
   `split(old).length-1 === 1` 唯一性。不要用 PowerShell 单引号 here-string
   写含真实换行的 JS 字符串（会把换行写进文件）。
6. **PowerShell**：不支持 `&&`，用 `;`。中文/多行逻辑写 Node `.mjs` 到
   `$env:TEMP` 再 `node` 执行（注意 `.cjs` 不支持 ESM `import`）。
   临时脚本与正式脚本统一用 ESM（`import fs from 'node:fs'`）。
7. **提交即发布**：每轮完成跑通后 `git add -A`、commit、`git tag vX.Y.Z`、
   `git push origin main vX.Y.Z`（PowerShell 会把 git 的 stderr 显示为红字，
   看到 `main -> main` 和 `[new tag]` 即成功）。

## 关键文件

- `tools/bootstrap-source.js` — bootstrap JS 权威源（改这里）
- `tools/regenerate-bootstrap.mjs` — 重新编码进 `.m`（npm run regenerate:bootstrap）
- `Sources/AutoSDK/AutoBootstrapScript.m` — 生成的 Objective-C 字符串（勿手改）
- `Sources/AutoSDK/AutoEngine.m` — 原生 JS 桥接/调度（CRLF，改时注意行尾）
- `Sources/AutoSDK/AutoScriptSupport.m` — 原生文件/HTTP/安全实现
- `types/autosdk.d.ts` — 类型声明（与文档闭环）
- `tools/verify.mjs` — 一致性断言（bootstrap 内容、d.ts、文档、版本、原生锚点）
- `tools/bootstrap.test.mjs` — bootstrap 行为测试（mock bridge 在 Node 里跑）
- `tools/generate-api-reference.mjs` — 手写 APIS 列表生成交互式文档
- `docs/EASYCLICK_COMPARISON.md` — 与 EasyClick 的能力差距审计（每轮更新）
- `docs/AI_HANDOFF.md` — 完整交接手册（架构/历史/缺口/工作流，新 AI 先读）

## 每轮迭代套路

1. 读 `docs/AI_HANDOFF.md` 的“待办/缺口”和 `docs/EASYCLICK_COMPARISON.md`。
2. 定本轮主题（补 API / 修 bug / 压缩 / 文档），给出 2-4 步计划。
3. 改 `bootstrap-source.js` 或原生 `.m` → `npm run regenerate:bootstrap` →
   同步 d.ts / verify / 测试 / 文档 → 跑铁律第 1 条四件套。
4. bump 版本 + CHANGELOG + MARKET_RELEASE tag 行 → commit → tag → push。
