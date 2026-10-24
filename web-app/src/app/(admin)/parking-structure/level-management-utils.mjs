export const MIN_LEVEL_NUMBER = -2147483648;
export const MAX_LEVEL_NUMBER = 2147483647;
export const MAX_LEVEL_BATCH = 50;
const timestamp = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
const number = value => Number.isInteger(value) && value >= MIN_LEVEL_NUMBER && value <= MAX_LEVEL_NUMBER;
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const keys = (value, fields) => object(value) && Object.keys(value).length === fields.length && fields.every(field => Object.hasOwn(value, field));
export function levelInputError(value) {
  if (!object(value) || !number(value.level_number)) return 'Use a whole level number between −2147483648 and 2147483647.';
  if (typeof value.name !== 'string' || !value.name.trim() || Array.from(value.name.trim()).length > 100 || /[\u0000-\u001f\u007f-\u009f]/u.test(value.name)) return 'Use a nonempty level name of at most 100 characters.';
  return '';
}
export function validLevelSnapshot(value) {
  return object(value) && number(value.level_number) && typeof value.name === 'string' && Boolean(value.name.length) && typeof value.is_active === 'boolean' && timestamp(value.updated_at) && number(value.metadata_revision) && value.metadata_revision > 0;
}
export function levelRequestError(value, mode) {
  if (mode === 'delete') return keys(value, ['expected_metadata_revision']) && number(value.expected_metadata_revision) && value.expected_metadata_revision > 0 ? '' : 'Refresh to load the current level revision.';
  if (mode === 'bulk') {
    if (!keys(value, ['levels']) || !Array.isArray(value.levels) || value.levels.length < 1 || value.levels.length > MAX_LEVEL_BATCH) return 'Preview between 1 and 50 levels.';
    return value.levels.some(item => !keys(item, ['level_number', 'name']) || levelInputError(item)) ? 'Check every level number and name.' : '';
  }
  if (!keys(value, mode === 'edit' ? ['level_number', 'name', 'expected'] : ['level_number', 'name'])) return 'Use only level number, level name and the required edit snapshot.';
  return levelInputError(value) || (mode === 'edit' && (!keys(value.expected, ['level_number', 'name', 'is_active', 'updated_at', 'metadata_revision']) || !validLevelSnapshot(value.expected)) ? 'Refresh to load the exact current level snapshot.' : '');
}
export const duplicateLevelNumbers = rows => new Set(rows.map(row => row.level_number)).size !== rows.length;
export function levelSnapshot(level) {
  return { level_number: level.level_number, name: level.name, is_active: level.is_active, updated_at: level.updated_at, metadata_revision: level.metadata_revision };
}
export function previewLevels(count, levels) {
  if (!Number.isInteger(count) || count < 1 || count > MAX_LEVEL_BATCH) throw new Error('Choose between 1 and 50 levels.');
  const start = levels.reduce((maximum, level) => Math.max(maximum, level.level_number), 0) + 1;
  if (start + count - 1 > MAX_LEVEL_NUMBER) throw new Error('Generated numbers exceed the integer limit. Add individual levels with available numbers.');
  return Array.from({ length: count }, (_, index) => ({ level_number: String(start + index), name: `Level ${start + index}` }));
}
export function levelRowsError(rows, levels, editingId = null) {
  const parsed = rows.map(row => ({ level_number: row.level_number === '' ? NaN : Number(row.level_number), name: row.name }));
  for (const row of parsed) { const error = levelInputError(row); if (error) return error; }
  if (duplicateLevelNumbers(parsed)) return 'Each preview row must have a different level number.';
  if (parsed.some(row => levels.some(level => level.id !== editingId && level.level_number === row.level_number))) return 'A level number is already in use. Choose another number.';
  return '';
}
export function validateLevelResponse(data, input, mode, id) {
  if (mode === 'delete') {
    if (data?.deleted_level_id !== id) throw new Error('Level deletion could not be confirmed.');
    return data;
  }
  const rows = mode === 'bulk' ? data?.levels : [data?.level];
  const wanted = mode === 'bulk' ? input.levels : [input];
  if (!Array.isArray(rows) || rows.length !== wanted.length || new Set(rows.map(row => row?.id)).size !== rows.length || rows.some(row =>
    !validLevelSnapshot(row) || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(row.id) ||
    !wanted.some(item => item.level_number === row.level_number && item.name.trim() === row.name) ||
    (mode === 'edit' ? row.id !== id || row.is_active !== input.expected.is_active ||
      row.metadata_revision !== input.expected.metadata_revision + Number(input.level_number !== input.expected.level_number || input.name.trim() !== input.expected.name) :
      row.is_active !== false || row.metadata_revision !== 1))) throw new Error('Level save could not be confirmed.');
  if (new Set(rows.map(row => row.level_number)).size !== rows.length) throw new Error('Incomplete level batch.');
  return data;
}
