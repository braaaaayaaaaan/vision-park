import styles from './metric-icon.module.css';

// Matches the lightweight, outlined SVG icons already used in the navigation.
const paths = {
  occupancy: 'M12 3a9 9 0 1 0 9 9h-9z M15 3.5V9h5.5',
  parking: 'M6 21V3h7a6 6 0 0 1 0 12H6 M6 7h7a2 2 0 0 1 0 4H6',
  entry: 'M14 3h6v18h-6 M3 12h12 M10 7l5 5-5 5',
  exit: 'M10 3H4v18h6 M10 12h11 M16 7l5 5-5 5',
  sessions: 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M12 7v5l3 2',
  payments: 'M3 5h18v14H3z M3 9h18 M7 15h4',
  wallet: 'M20 8V5H5a2 2 0 0 0 0 4h16v11H5a2 2 0 0 1-2-2V7 M16 12h5v5h-5z',
  companies: 'M3 21V7h10v14 M13 3h8v18 M1 21h22 M6 11h4 M6 15h4 M16 7h2 M16 11h2 M16 15h2',
  vehicles: 'M5 10l2-6h10l2 6 M3 10h18v8H3z M5 18v3 M19 18v3 M6 14h2 M16 14h2',
  drivers: 'M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0 M4 21v-2a8 8 0 0 1 16 0v2',
  approved: 'M12 3l8 3v6c0 5-8 9-8 9s-8-4-8-9V6z M8 12l3 3 5-6',
  pending: 'M9 3h6v4H9z M9 4H5v17h14V4h-4 M8 13h8 M8 17h5',
  allocated: 'M4 4h16v16H4z M9 17V7h4a3 3 0 0 1 0 6H9',
  completed: 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M8 12l3 3 5-6',
  cancelled: 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M8 8l8 8 M16 8l-8 8',
};

const solidPaths = {
  occupancy: 'M11 2.05A10 10 0 1 0 21.95 13H11V2.05ZM13 2.05V11h8.95A10 10 0 0 0 13 2.05Z',
  parking: 'M6 2h7a7 7 0 0 1 0 14h-3v6H6V2Zm4 4v6h3a3 3 0 0 0 0-6h-3Z',
  entry: 'M13 2h7a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2h-7v-3h6V5h-6V2ZM9 6l6 6-6 6v-4H2v-4h7V6Z',
  exit: 'M11 2H4a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h7v-3H5V5h6V2ZM17 6l6 6-6 6v-4h-7v-4h7V6Z',
  sessions: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20ZM11 6h2v5.4l4 2.4-1 1.7-5-3V6Z',
  vehicles: 'M6 3h12l3 7v10h-3v-2H6v2H3V10L6 3ZM7.3 6l-1.7 4h12.8l-1.7-4H7.3ZM9 13.5a1.5 1.5 0 1 0-3 0 1.5 1.5 0 0 0 3 0ZM18 13.5a1.5 1.5 0 1 0-3 0 1.5 1.5 0 0 0 3 0Z',
  payments: 'M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2ZM4 8v3h16V8H4ZM6 15v2h6v-2H6Z',
  wallet: 'M5 3h14v3h1a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a3 3 0 0 1 3-3ZM5 5a1 1 0 0 0 0 2h12V5H5ZM16 11v5h6v-5h-6ZM20 13.5a1 1 0 1 0-2 0 1 1 0 0 0 2 0Z',
  pending: 'M8 2h8v2h3a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h3V2ZM9 5v2h6V5H9ZM7 11v2h10v-2H7ZM7 16v2h7v-2H7Z',
  receipt: 'M4 2l2 1 2-1 2 1 2-1 2 1 2-1 2 1 2-1v20l-2-1-2 1-2-1-2 1-2-1-2 1-2-1-2 1V2ZM8 7v2h8V7H8ZM8 11v2h8v-2H8ZM8 15v2h5v-2H8Z',
};

export default function MetricIcon({ name, large = false, solid = false }) {
  const className = [styles.badge, large && styles.large].filter(Boolean).join(' ');
  const size = large ? 30 : 20;
  const filled = solid && Boolean(solidPaths[name]);
  return <span className={className} aria-hidden="true"><svg width={size} height={size} viewBox="0 0 24 24" fill={filled ? 'currentColor' : 'none'} fillRule="evenodd" stroke={filled ? 'none' : 'currentColor'} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" focusable="false"><path d={filled ? solidPaths[name] : paths[name] || paths.sessions} /></svg></span>;
}
