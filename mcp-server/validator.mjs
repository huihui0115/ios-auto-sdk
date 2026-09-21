import { Worker } from 'node:worker_threads';

export const MAX_SCRIPT_LENGTH = 65536;
export function createValidator({ timeoutMs = 8000 } = {}) {
  let active = null, closed = false;
  async function validate(code, language = 'javascript', signal) {
    if (closed) throw new Error('Validator is closed');
    if (typeof code !== 'string' || code.length > MAX_SCRIPT_LENGTH || !code.trim()) throw new Error('脚本必须非空且不超过 65,536 个 UTF-16 码元');
    if (!['javascript', 'typescript'].includes(language)) throw new Error('Unsupported script language');
    if (signal?.aborted) throw new Error('Validation cancelled');
    if (active) throw new Error('正在检查另一份脚本，请稍后重试');
    return new Promise((resolve, reject) => {
      const worker = new Worker(new URL('./validation-worker.mjs', import.meta.url), {
        workerData: { code, language }, resourceLimits: { maxOldGenerationSizeMb: 192, stackSizeMb: 4 },
        stdout: true, stderr: true
      });
      // A faulty worker must not write anything to the MCP protocol stream.
      worker.stdout.resume(); worker.stderr.resume();
      let done = false;
      const finish = (error, result) => {
        if (done) return;
        done = true; clearTimeout(timer); signal?.removeEventListener('abort', cancel);
        // Keep the admission slot until termination, including timeout/error/cancel paths.
        worker.terminate().finally(() => { active = null; error ? reject(error) : resolve(result); });
      };
      const cancel = () => finish(new Error('Validation cancelled'));
      const timer = setTimeout(() => finish(new Error('静态检查超时，未得到有效结论；请缩小脚本后重试')), timeoutMs);
      active = { cancel, worker };
      signal?.addEventListener('abort', cancel, { once: true });
      if (signal?.aborted) cancel();
      worker.once('message', result => finish(null, result));
      worker.once('error', () => finish(new Error('静态检查线程失败，未得到有效结论；请简化脚本后重试')));
      worker.once('exit', () => { if (!done) finish(new Error('静态检查意外退出，未得到有效结论')); });
    });
  }
  return { validate, close() { closed = true; active?.cancel(); } };
}
