'use strict';
const { catalog, snippet, completions, callHelp, hoverEntry } = require('./api-language');

function languageProviders(vscode) {
  const languages = [{ language: 'javascript' }, { language: 'typescript' }];
  return [vscode.languages.registerCompletionItemProvider(languages, {
    provideCompletionItems(document, position) {
      return completions(document.getText(), document.offsetAt(position)).map(candidate => {
        const item = new vscode.CompletionItem(candidate.name, vscode.CompletionItemKind.Method);
        item.detail = candidate.signature;
        item.documentation = new vscode.MarkdownString(candidate.documentation);
        item.insertText = new vscode.SnippetString(candidate.insertText);
        item.filterText = candidate.filterText;
        item.range = new vscode.Range(position.translate(0, -candidate.replaceLength), position.translate(0, candidate.replaceAfterLength));
        item.command = { command: 'editor.action.triggerParameterHints', title: '参数提示' };
        return item;
      });
    }
  }, '.'), vscode.languages.registerSignatureHelpProvider(languages, {
    provideSignatureHelp(document, position) {
      const help = callHelp(document.getText(), document.offsetAt(position));
      if (!help) return undefined;
      const result = new vscode.SignatureHelp();
      result.signatures = help.entries.map(entry => {
        const info = new vscode.SignatureInformation(entry.signature, new vscode.MarkdownString(entry.documentation));
        info.parameters = entry.parameters.map(p => new vscode.ParameterInformation(`${p.rest ? '...' : ''}${p.name}${p.optional ? '?' : ''}: ${p.type}`));
        return info;
      });
      const matching = help.entries.findIndex(entry => entry.parameters.length > help.parameter || entry.parameters.some(p => p.rest));
      result.activeSignature = Math.max(0, matching);
      result.activeParameter = Math.max(0, Math.min(help.parameter, help.entries[result.activeSignature].parameters.length - 1));
      return result;
    }
  }, '(', ','), vscode.languages.registerHoverProvider(languages, {
    provideHover(document, position) {
      const entry = hoverEntry(document.getText(), document.offsetAt(position));
      if (!entry) return undefined;
      const markdown = new vscode.MarkdownString();
      markdown.appendCodeblock(entry.signature, 'typescript');
      markdown.appendText(entry.documentation);
      return new vscode.Hover(markdown);
    }
  })];
}

function apiItems() {
  const presets = [
    ['打开系统小白点 / 辅助触控', 'device.setAssistiveTouchEnabled(true)', '需私有接口与签名权限；与 App 内 floatBall 不同。'],
    ['关闭系统小白点 / 辅助触控', 'device.setAssistiveTouchEnabled(false)', '蓝牙鼠标方案可能依赖它；仅插入，运行前确认。'],
    ['查询系统小白点状态', 'device.isAssistiveTouchEnabled()', '返回 null 表示无法可靠读取，不是已关闭。'],
    ...Object.entries({ assistiveTouch: '小白点 / 辅助触控', touch: '触控', voiceOver: '旁白', zoom: '缩放', switchControl: '切换控制', reduceMotion: '减弱动态效果', textSize: '字体大小', autoLock: '自动锁屏', sounds: '声音', keyboard: '键盘', wifi: 'Wi-Fi', bluetooth: '蓝牙', vpn: 'VPN', battery: '低电量模式', location: '定位', accessibility: '辅助功能' })
      .map(([panel, name]) => [`打开${name}设置`, `system.openSettings("${panel}")`, '仅请求打开设置，不能代替切换开关；iOS 可能回退设置首页。'])
  ].map(([label, code, detail]) => ({ label, description: code, detail, insertion: code }));
  return [...presets, ...catalog.map(entry => ({ label: entry.title, description: entry.signature,
    detail: entry.documentation, insertion: snippet(entry) }))];
}

async function insertAPI(currentEditor, vscode) {
  const original = currentEditor();
  const version = original?.document.version;
  const selection = original?.selection;
  const selected = await vscode.window.showQuickPick(apiItems(), {
    title: 'AutoSDK 函数库', placeHolder: '搜索中文或函数名，例如：小白点、VPN、剪贴板。选择后仅插入代码，不自动运行。',
    matchOnDescription: true, matchOnDetail: true
  });
  if (!selected) return;
  if (original && (original.document.isClosed || original.document.version !== version ||
      !original.selection.isEqual(selection) || currentEditor() !== original)) {
    return vscode.window.showWarningMessage('编辑器内容或光标已改变，请重新选择函数，避免插入到错误位置。');
  }
  const editor = original || await vscode.window.showTextDocument(await vscode.workspace.openTextDocument({ language: 'javascript', content: '' }));
  await editor.insertSnippet(new vscode.SnippetString(selected.insertion));
}

module.exports = { languageProviders, apiItems, insertAPI };
