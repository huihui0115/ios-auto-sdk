class CoalescingRunner {
  constructor(task) {
    if (typeof task !== 'function') throw new TypeError('CoalescingRunner requires a task function.');
    this.task = task;
    this.pending = false;
    this.running = undefined;
    this.disposed = false;
  }

  request() {
    if (this.disposed) return Promise.resolve(false);
    this.pending = true;
    if (!this.running) {
      const running = this.drain();
      const wrapped = running.finally(() => {
        if (this.running === wrapped) this.running = undefined;
      });
      this.running = wrapped;
    }
    return this.running;
  }

  async drain() {
    let completed = false;
    while (this.pending && !this.disposed) {
      this.pending = false;
      await this.task();
      completed = true;
    }
    return completed;
  }

  dispose() {
    this.disposed = true;
    this.pending = false;
  }

  cancelPending() {
    this.pending = false;
  }
}

module.exports = { CoalescingRunner };
