(() => {
  const vscode = acquireVsCodeApi();
  const byId = id => document.getElementById(id);
  const send = (action, key) => vscode.postMessage({ action, key });
  for (const button of document.querySelectorAll('[data-action]')) {
    button.addEventListener('click', () => { if (!button.disabled) send(button.dataset.action); });
  }
  window.addEventListener('message', event => {
    if (event.data?.type !== 'state') return;
    const state = event.data.state;
    const ready = state.connection === 'ready';
    const locked = state.busy || state.scanning;
    byId('device-name').textContent = state.deviceName || '尚未添加手机';
    byId('device-address').textContent = state.address || '';
    byId('connection').textContent = ready ? '● 已连接' : state.connection === 'connecting' ? '正在连接…' : '○ 未连接';
    byId('connection').dataset.ready = String(ready);
    byId('message').textContent = state.message;
    byId('scan').textContent = state.scanning ? '正在搜索…' : '搜索 Wi-Fi 手机';
    byId('scan').disabled = locked || state.running;
    byId('cancelScan').hidden = !state.scanning;
    byId('reconnect').hidden = !state.configured || ready;
    byId('disconnect').hidden = !ready;
    byId('pair').hidden = !state.configured;
    for (const id of ['reconnect', 'disconnect', 'pair', 'manual', 'usb']) byId(id).disabled = locked || state.running;
    byId('newScript').disabled = locked;
    byId('script-name').textContent = state.scriptName || '还没有打开脚本，点击「新建示例脚本」开始。';
    byId('trust').hidden = state.trusted;
    byId('run').disabled = !ready || locked || state.running || !state.canRun || !state.trusted;
    byId('runSelection').disabled = byId('run').disabled || !state.canSelect;
    byId('stop').disabled = !ready;
    byId('inspector').disabled = !ready || locked || state.running;
    const devices = byId('devices');
    devices.replaceChildren();
    for (const device of state.devices) {
      const card = document.createElement('div'); card.className = 'device';
      const name = document.createElement('strong'); name.textContent = device.name;
      const address = document.createElement('small'); address.textContent = device.address;
      const button = document.createElement('button'); button.textContent = '添加并连接';
      button.disabled = locked || state.running;
      button.addEventListener('click', () => { if (!button.disabled) send('connect', device.key); });
      card.append(name, address, button); devices.append(card);
    }
  });
  send('ready');
})();
