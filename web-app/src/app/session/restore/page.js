import SessionRestore from './session-restore';

export default async function RestorePage({ searchParams }) {
  const { next } = await searchParams;
  const allowed = /^\/(overview|analytics|approvals|vehicles|tenants|sessions|parking-structure)(\/|\?|$)/;
  const destination = typeof next === 'string' && allowed.test(next) && !next.includes('\\') ? next : '/overview';
  return <SessionRestore destination={destination} />;
}
