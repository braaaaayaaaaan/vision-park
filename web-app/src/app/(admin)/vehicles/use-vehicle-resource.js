'use client';
import { useEffect, useState } from 'react';
import { startVisiblePolling } from '../../../lib/visible-polling.mjs';

// A key mismatch hides previous data immediately, even before effect cleanup.
export default function useVehicleResource(key, load, interval = 0) {
  const [state, setState] = useState({ key: null, data: null, error: '' });
  useEffect(() => {
    if (!interval) {
      const controller = new AbortController();
      load(controller.signal).then(data => {
        if (!controller.signal.aborted) setState({ key, data, error: '' });
      }).catch(error => {
        if (!controller.signal.aborted) setState(previous => ({ key, data: null,
          previous: previous.data ?? previous.previous,
          error: error.message || 'Unable to load vehicle information.' }));
      });
      return () => controller.abort();
    }
    return startVisiblePolling({ load, interval,
      success: data => setState({ key, data, error: '' }),
      failure: error => setState(previous => {
        // Keep the current screen during transient background failures. Never
        // carry records across a filter/key change or an authentication change.
        const data = interval > 0 && previous.key === key && !error.sessionChanged ? previous.data : null;
        return { key, data, previous: previous.data ?? previous.previous,
          error: data ? '' : error.message || 'Unable to load vehicle information.' };
      }),
    });
  }, [key, load, interval]);
  return state.key === key ? { ...state, loading: false, previous: state.data ?? state.previous }
    : { data: null, error: '', loading: true, previous: state.data ?? state.previous };
}
