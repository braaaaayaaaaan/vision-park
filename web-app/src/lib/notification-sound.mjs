// Short, locally generated chime: no audio downloads or third-party services.
export function createNotificationSound(AudioContext) {
  let context = null, enabled = false, disposed = false, revision = 0, lastPlayed = -Infinity;
  function play() {
    if (!enabled || disposed || context?.state !== 'running' || context.currentTime - lastPlayed < 1.5) return false;
    try {
      const start = context.currentTime;
      for (const [frequency, offset] of [[740, 0], [988, 0.17]]) {
        const tone = context.createOscillator(), volume = context.createGain();
        tone.type = 'sine'; tone.frequency.value = frequency;
        volume.gain.setValueAtTime(0.0001, start + offset);
        volume.gain.exponentialRampToValueAtTime(0.09, start + offset + 0.015);
        volume.gain.exponentialRampToValueAtTime(0.0001, start + offset + 0.22);
        tone.connect(volume); volume.connect(context.destination);
        tone.onended = () => { tone.disconnect(); volume.disconnect(); };
        tone.start(start + offset); tone.stop(start + offset + 0.24);
      }
      lastPlayed = start;
      return true;
    } catch { return false; }
  }
  return {
    async enable() {
      const attempt = ++revision;
      if (disposed || !AudioContext) return false;
      try {
        context ??= new AudioContext();
        if (context.state !== 'running') await context.resume();
        if (disposed || attempt !== revision) return false;
        enabled = context.state === 'running';
        return enabled;
      } catch { enabled = false; return false; }
    },
    play,
    disable() {
      revision++; enabled = false;
      if (context?.state === 'running') void context.suspend().catch(() => {});
    },
    dispose() {
      revision++; enabled = false; disposed = true;
      if (context && context.state !== 'closed') void context.close().catch(() => {});
    },
  };
}
