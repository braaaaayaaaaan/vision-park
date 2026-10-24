'use client';
import { useEffect, useId, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import styles from './confirmation-dialog.module.css';

export default function ConfirmationDialog({ id: providedId, title, description, children, variant = 'default', icon,
  confirmLabel = 'Confirm', cancelLabel = 'Cancel', pendingLabel = 'Please wait…', disabled = false,
  pending = false, error = '', onConfirm, onCancel, onConfirmed }) {
  const generatedId = useId(), id = providedId ?? generatedId;
  const dialog = useRef(null), cancel = useRef(null), inFlight = useRef(false), mounted = useRef(false);
  const [submitting, setSubmitting] = useState(false), [failure, setFailure] = useState('');
  const busy = pending || submitting;
  useEffect(() => {
    mounted.current = true;
    const element = dialog.current, origin = document.activeElement;
    element.showModal();
    cancel.current?.focus();
    return () => {
      mounted.current = false;
      element.close();
      if (origin?.isConnected) origin.focus({ preventScroll: true });
    };
  }, []);
  function dismiss() { if (!pending && !inFlight.current) onCancel(); }
  async function submit(event) {
    event.preventDefault(); event.stopPropagation();
    if (disabled || pending || inFlight.current) return;
    inFlight.current = true; setSubmitting(true); setFailure('');
    try {
      const result = await onConfirm(event);
      if (mounted.current && result !== false) onConfirmed?.();
    } catch (cause) {
      if (mounted.current) setFailure(cause instanceof Error ? cause.message : 'The action could not be confirmed. Please try again.');
    } finally {
      inFlight.current = false;
      if (mounted.current) setSubmitting(false);
    }
  }
  const content = <dialog ref={dialog} className={styles.dialog} data-variant={variant} aria-modal="true"
    aria-labelledby={`${id}-title`} aria-describedby={`${id}-description`} tabIndex={-1}
    onCancel={event => { event.preventDefault(); event.stopPropagation(); dismiss(); }}>
    <form onSubmit={submit} aria-busy={busy}>
      <header className={styles.header}>
        {icon !== false && <span className={styles.icon} aria-hidden="true">{icon ?? <svg width="23" height="23" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
          {variant === 'destructive' ? <path d="M3 6h18 M9 6V3h6v3 M5 6l1 15h12l1-15 M10 10v7 M14 10v7" /> : <><path d="M12 3 2 21h20L12 3Z M12 9v5 M12 17h.01" /></>}
        </svg>}</span>}
        <div><h2 id={`${id}-title`}>{title}</h2><p id={`${id}-description`}>{description}</p></div>
      </header>
      {children && <div className={styles.content}>{children}</div>}
      {(error || failure) && <p className={styles.error} role="alert">{error || failure}</p>}
      {busy && <p className={styles.pending} role="status">{pendingLabel}</p>}
      <footer className={styles.actions}>
        <button ref={cancel} type="button" className={styles.cancel} disabled={busy} onClick={dismiss}>{cancelLabel}</button>
        <button type="submit" className={styles.confirm} disabled={busy || disabled}>{busy ? pendingLabel : confirmLabel}</button>
      </footer>
    </form>
  </dialog>;
  // Escape native form nesting and keep dialogs visible in floor-plan fullscreen mode.
  return typeof document === 'undefined' ? content : createPortal(content, document.fullscreenElement ?? document.body);
}
