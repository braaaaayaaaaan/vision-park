'use client';
import { useEffect, useState } from 'react';

// A key mismatch hides previous data immediately, even before effect cleanup.
export default function useVehicleResource(key, load) {
  const [state, setState] = useState({ key: null, data: null, error: '' });
  useEffect(() => {
    const controller = new AbortController();
    load(controller.signal).then(data => {
      if (!controller.signal.aborted) setState({ key, data, error: '' });
    }).catch(error => {
      if (!controller.signal.aborted) setState(previous => ({ key, data: null, previous: previous.data ?? previous.previous,
        error: error.message || 'Unable to load vehicle information.' }));
    });
    return () => controller.abort();
  }, [key, load]);
  return state.key === key ? { ...state, loading: false, previous: state.data ?? state.previous }
    : { data: null, error: '', loading: true, previous: state.data ?? state.previous };
}
