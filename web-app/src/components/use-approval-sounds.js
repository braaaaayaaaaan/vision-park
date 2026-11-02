'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import { createNotificationSound } from '../lib/notification-sound.mjs';

const preference = 'visionpark-approval-sounds';
function save(enabled) {
  try { window.localStorage.setItem(preference, enabled ? 'on' : 'off'); } catch { /* Sound still works without storage. */ }
}

export default function useApprovalSounds() {
  const [status, setStatus] = useState('off');
  const [error, setError] = useState('');
  const audio = useRef(null), wanted = useRef(false);
  useEffect(() => {
    const sound = createNotificationSound(window.AudioContext || window.webkitAudioContext);
    audio.current = sound;
    let mounted = true;
    try { wanted.current = window.localStorage.getItem(preference) === 'on'; } catch { /* Keep sounds off. */ }
    // Restore the preference after hydration; resume audio only on interaction.
    const timer = setTimeout(() => { if (wanted.current) setStatus('waiting'); }, 0);
    function unlock(event) {
      if (!wanted.current || event.target?.closest?.('[data-notification-sound-toggle]')) return;
      void sound.enable().then(ready => { if (mounted && ready) setStatus('on'); });
    }
    document.addEventListener('pointerdown', unlock);
    document.addEventListener('keydown', unlock);
    return () => {
      mounted = false; clearTimeout(timer);
      document.removeEventListener('pointerdown', unlock);
      document.removeEventListener('keydown', unlock);
      audio.current = null; sound.dispose();
    };
  }, []);
  const notify = useCallback(() => { audio.current?.play(); }, []);
  async function toggle() {
    const sound = audio.current;
    if (!sound) return;
    setError('');
    if (status === 'on') {
      wanted.current = false; save(false); sound.disable(); setStatus('off');
      return;
    }
    const ready = await sound.enable();
    if (audio.current !== sound) return;
    wanted.current = ready; save(ready);
    setStatus(ready ? 'on' : 'off');
    if (ready) sound.play();
    else setError('Sounds could not be enabled. Check your browser’s site sound settings and try again.');
  }
  return { enabled: status === 'on', error, toggle, notify };
}
