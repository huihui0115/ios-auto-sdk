// Read-only diagnostics: whitelist fields, never copy credentials, names or script/error text.
const object = value => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const version = value => typeof value === 'string' && value.length <= 32 && /^\d+(?:\.\d+){1,3}$/.test(value) ? value : '未提供';
const REASONS = { completed: '正常完成', userCancelled: '用户停止', cancelled: '已取消',
  memoryPressure: '内存压力保护停止', thermalPressure: '严重发热保护停止',
  backgroundExpired: 'iOS 后台时间到期', scriptTimeout: '脚本超时', failed: '脚本出错（请查看运行日志）' };
const ownLabel = (labels, value, fallback) => typeof value === 'string' && Object.hasOwn(labels, value) ? labels[value] : fallback;

function buildDeviceHealth(deviceInfo, capabilities, checkedAtMs = Date.now()) {
  const info = object(deviceInfo), caps = object(capabilities), automation = object(caps.automation);
  const candidate = object(info.runtimeHealth);
  const health = candidate.schemaVersion === 1 ? candidate : {};
  const rows = [], warnings = [];
  const add = (label, value) => rows.push({ label, value });
  add('版本', `iOS ${version(info.systemVersion)} · SDK ${version(info.sdkVersion)}`);
  if (health.schemaVersion !== 1) warnings.push('手机端未提供可识别的运行健康信息；更新 App 后重试。');
  add('内存保护', health.lowMemoryProfile === true ? '低内存机型保护已启用' : health.lowMemoryProfile === false ? '标准资源预算' : '未知');
  if (typeof health.decodedImageBudgetMiB === 'number' && Number.isInteger(health.decodedImageBudgetMiB) && health.decodedImageBudgetMiB > 0 && health.decodedImageBudgetMiB <= 128) {
    add('图像预算', `${health.decodedImageBudgetMiB} MiB（解码预算，不是进程总内存上限）`);
  }
  add('温度', ownLabel({ nominal: '正常', fair: '略热', serious: '严重发热', critical: '过热' }, health.thermalState, '未知'));
  if (['serious', 'critical'].includes(health.thermalState)) warnings.push('手机发热明显，请停止高频采集并冷却后再试。');
  add('省电模式', health.lowPowerMode === true ? '开启' : health.lowPowerMode === false ? '关闭' : '未知');
  add('App 状态', ownLabel({ active: '前台', inactive: '暂不活跃', background: '后台' }, health.appState, '未知'));
  add('脚本状态', health.stopRequested === true ? '已请求停止，等待安全退出' : health.running === true ? '运行中' : health.running === false ? '空闲' : '未知');
  add('后台保障', health.backgroundPolicy === 'finite' ? (health.backgroundLeaseActive === true ? '有限后台时间已申请，不保证永久保活' : '当前无有效后台时间申请') : '未知，不保证永久保活');
  if (health.appState === 'background' && health.backgroundLeaseActive !== true) warnings.push('App 在后台且未报告有效后台时间；请返回 App 后重新检查。');
  const reason = object(health.lastRun).reasonCode;
  add('上次运行', ownLabel(REASONS, reason, '暂无记录（仅本次 App 进程）'));
  if (reason === 'backgroundExpired') warnings.push('上次因后台时间到期退出；返回 App 检查进度，再手动运行，避免重复操作。');
  if (reason === 'memoryPressure') warnings.push('上次触发内存保护；缩小截图/找图范围，降低采集频率后重试。');
  if (reason === 'thermalPressure') warnings.push('上次触发发热保护；冷却手机、降低采集频率后重试。');
  for (const [key, label] of [['screenshot', '截图'], ['nodes', '节点'], ['click', '点击'], ['crossApp', '跨 App']]) {
    add(`${label}能力`, automation[key] === true ? '声明支持，未实机验证' : automation[key] === false ? '当前适配器未支持' : '未提供');
    if (automation[key] === false) warnings.push(`${label}当前不可用；请核对手机端适配器、签名权限与运行日志。`);
  }
  if (caps.interruptibleScripts === false || caps.cooperativeCancellation === true) {
    add('停止方式', '协作式停止；不含安全检查的纯 JS 死循环无法保证立即退出');
  }
  return { checkedAtMs: Number.isFinite(checkedAtMs) && checkedAtMs >= 0 && checkedAtMs <= 8640000000000000 ? checkedAtMs : 0,
    summary: warnings.length ? '检查完成，有需要处理的提示' : '状态读取完成，能力仍需实机验证', rows, warnings };
}

async function readDeviceHealth(request, { signal } = {}) {
  const read = async type => {
    if (signal?.aborted) throw new Error('Device health check cancelled.');
    const response = await request({ type }, { signal });
    if (signal?.aborted) throw new Error('Device health check cancelled.');
    const value = response?.[type];
    if (response?.ok !== true || !value || typeof value !== 'object' || Array.isArray(value)) throw new Error('无法读取手机状态，请检查连接后重试。');
    return value;
  };
  return buildDeviceHealth(await read('deviceInfo'), await read('capabilities'));
}

function healthReportText(report) {
  return ['AutoSDK 手机状态摘要（只读快照；非实机验收）', `电脑检查时间：${new Date(report.checkedAtMs).toISOString()}`,
    report.summary, ...report.rows.map(row => `${row.label}：${row.value}`), ...report.warnings.map(value => `提示：${value}`)].join('\n');
}

module.exports = { buildDeviceHealth, readDeviceHealth, healthReportText };
