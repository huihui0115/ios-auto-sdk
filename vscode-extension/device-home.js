// Host-owned sidebar state. The webview sends action names, never URLs or commands.
const ACTIONS = new Set(['scan', 'cancelScan', 'connect', 'reconnect', 'pair', 'disconnect',
  'newScript', 'run', 'runSelection', 'stop', 'inspector', 'logs', 'help', 'manual', 'usb']);
const CONNECTION_ACTIONS = new Set(['connect', 'reconnect', 'pair', 'disconnect', 'manual', 'usb']);

function connectionHelp(error) {
  const message = String(error?.message || error || '');
  if (/新建示例脚本/.test(message)) return '请先打开脚本，或点击「新建示例脚本」。';
  if (/脚本正在运行/.test(message)) return '脚本正在运行，请先停止后再切换手机。';
  if (/工作区或连接目标已改变/.test(message)) return '工作区或连接目标已改变，请重新选择手机。';
  if (/token|auth|unauthor|forbidden|1008/i.test(message)) return '配对未通过。请点「重新配对」，使用手机当前显示的配对码。';
  if (/trust/i.test(message)) return '请先信任此工作区，再运行脚本。';
  if (/timed? ?out|timeout|ECONN|ENET|EHOST|closed|socket/i.test(message)) return '手机暂时无法连接。请保持 App 打开、开启 Wi-Fi 调试，并确认电脑和手机在同一 Wi-Fi；地址变化时重新搜索。';
  return '操作未完成。请确认手机已开启 Wi-Fi 调试；可重试或打开运行日志查看详情。';
}

class DeviceHome {
  constructor(options) {
    this.options = options;
    this.devices = [];
    this.revision = 0;
    this.epoch = 0;
    this.connection = 'disconnected';
    this.message = '手机打开 AutoSDK，开启 Wi-Fi 调试，然后点击搜索。';
    this.busy = false;
    this.running = false;
    this.disposed = false;
  }

  snapshot() {
    return { ...this.options.context(), connection: this.connection, message: this.message,
      busy: this.busy, running: this.running, scanning: Boolean(this.scanController),
      revision: this.revision, devices: this.devices.map((device, index) => ({
        key: `${this.revision}:${index}`, name: device.name, address: `${device.address}:${device.port}`
      })) };
  }

  publish() {
    if (!this.disposed) this.options.publish(this.snapshot());
  }

  setConnection(state) {
    if (state === 'disconnected' && this.connection === 'ready') this.message = '连接已断开。请保持手机 App 打开，点击「连接」重试；地址变化时重新搜索。';
    this.connection = state;
    this.publish();
  }

  setRunning(running) {
    this.running = running;
    this.publish();
  }

  reset() {
    this.epoch++;
    this.scanController?.abort();
    this.scanController = undefined;
    this.devices = [];
    this.revision++;
    this.connection = 'disconnected';
    this.message = '工作区已切换，请搜索并连接此工作区的手机。';
    this.publish();
  }

  async scan() {
    if (this.disposed || this.scanController || this.busy || this.running) return;
    const controller = new AbortController();
    const epoch = this.epoch;
    this.scanController = controller;
    this.devices = [];
    this.revision++;
    this.message = '正在搜索同一局域网的手机…';
    this.publish();
    try {
      const devices = await this.options.discover({ signal: controller.signal });
      if (this.disposed || controller.signal.aborted || epoch !== this.epoch) return;
      this.devices = devices.slice(0, 64);
      this.message = devices.length ? `找到 ${this.devices.length} 台手机，点击「添加并连接」。` :
        '未找到手机：确认 App 在前台、Wi-Fi 调试已开启、已允许“本地网络”权限。访客 Wi-Fi / 路由器隔离可能阻止发现。';
    } catch (error) {
      if (this.disposed || epoch !== this.epoch) return;
      this.message = controller.signal.aborted ? '已取消搜索。' : connectionHelp(error);
      if (!controller.signal.aborted) this.options.log(error);
    } finally {
      if (!this.disposed && controller.signal.aborted && epoch === this.epoch) this.message = '已取消搜索。';
      if (this.scanController === controller) this.scanController = undefined;
      this.publish();
    }
  }

  async receive(message) {
    if (this.disposed || !message || typeof message !== 'object') return;
    if (message.action === 'ready') return this.publish();
    const action = message.action;
    if (!ACTIONS.has(action)) return;
    if (action === 'cancelScan') { this.scanController?.abort(); return; }
    if (action === 'scan') return this.scan();
    // Stop and read-only help remain available during a long-running script.
    if (['stop', 'logs', 'help'].includes(action)) {
      try { await this.options.perform(action); }
      catch (error) { this.options.log(error); this.message = connectionHelp(error); this.publish(); }
      return;
    }
    if (this.busy || this.scanController || (this.running && (CONNECTION_ACTIONS.has(action) || ['run', 'runSelection', 'inspector'].includes(action)))) return;
    let device;
    if (action === 'connect') {
      device = this.devices.find((_, index) => message.key === `${this.revision}:${index}`);
      if (!device) return; // Reject stale scan results and forged URLs.
    }
    const epoch = this.epoch;
    this.busy = true;
    this.publish();
    try {
      const result = await this.options.perform(action, device);
      if (epoch !== this.epoch || this.disposed) return;
      if (CONNECTION_ACTIONS.has(action) && result === true) this.message = '手机已连接，可以运行脚本或打开截图与节点。';
      else if (action === 'disconnect') this.message = '连接已断开；配对信息保留，下次点击「连接」即可。';
      else if (result === false) this.message = '操作已取消，或未连接成功。可点击「重新配对」或再次搜索。';
    } catch (error) {
      if (epoch !== this.epoch || this.disposed) return;
      this.options.log(error);
      this.message = connectionHelp(error);
    } finally {
      this.busy = false;
      this.publish();
    }
  }

  dispose() { this.disposed = true; this.epoch++; this.scanController?.abort(); }
}

module.exports = { DeviceHome, connectionHelp };
