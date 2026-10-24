'use client';
import { useRef, useState } from 'react';
import ConfirmationDialog from './confirmation-dialog';

// One local request per owner; no global provider, queue or native-popup fallback.
// disabled can be a live predicate of the request (for example, allow discard
// while a failed save is locked). An action can return false to keep its dialog open.
export default function useConfirmation({ disabled = false, error = '' } = {}) {
  const [request, setRequest] = useState(null), active = useRef(false);
  const isDisabled = options => typeof disabled === 'function' ? disabled(options) : disabled;
  function close() { active.current = false; setRequest(null); }
  function requestConfirmation(options, onConfirm) {
    if (active.current || isDisabled(options)) return;
    active.current = true;
    setRequest({ ...options, onConfirm });
  }
  return {
    requestConfirmation,
    confirmationDialog: request && <ConfirmationDialog {...request} disabled={isDisabled(request)} error={error}
      onCancel={close} onConfirmed={close} />,
  };
}
