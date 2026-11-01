// One read at a time, with the next interval measured from completion.
export function startVisiblePolling({ load, success, failure, interval = 15000,
  document: page = document, timers = globalThis, random = Math.random, shouldPoll = () => true }) {
  let stopped = false, current = null, timer = null;
  let failures = 0;
  function clear() { timers.clearTimeout(timer); timer = null; }
  async function run() {
    clear();
    if (stopped || current || page.visibilityState === 'hidden') return;
    const controller = new AbortController();
    current = controller;
    let timedOut = false;
    const timeout = timers.setTimeout(() => { timedOut = true; controller.abort(); }, 30000);
    try {
      const data = await load(controller.signal);
      if (!stopped && !controller.signal.aborted) {
        failures = 0;
        success(data);
        if (!shouldPoll(data)) stopped = true;
      }
    } catch (error) {
      if (!stopped && !controller.signal.aborted) {
        failure(error);
        failures++;
        if (error.sessionChanged) stopped = true;
      }
    } finally {
      if (timedOut && !stopped && page.visibilityState !== 'hidden') {
        failures++;
        failure(new Error('The request timed out. Please retry.'));
      }
      timers.clearTimeout(timeout);
      if (current === controller) current = null;
      if (!stopped && interval > 0 && page.visibilityState !== 'hidden') {
        const delay = failures ? Math.min(120000, interval * 2 ** Math.min(failures, 3) * (0.85 + random() * 0.3)) : interval;
        timer = timers.setTimeout(run, delay);
      }
    }
  }
  function visibility() {
    if (page.visibilityState === 'hidden') { clear(); current?.abort(); }
    else void run();
  }
  page.addEventListener('visibilitychange', visibility);
  void run();
  return () => {
    stopped = true;
    clear();
    current?.abort();
    page.removeEventListener('visibilitychange', visibility);
  };
}
