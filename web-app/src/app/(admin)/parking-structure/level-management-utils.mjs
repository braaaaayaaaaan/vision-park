export const MIN_LEVEL_NUMBER = -2147483648;
export const MAX_LEVEL_NUMBER = 2147483647;
export const MAX_LEVEL_BATCH = 50;
const timestamp = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
const number = value => Number.isInteger(value) && value >= MIN_LEVEL_NUMBER && value <= MAX_LEVEL_NUMBER;
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const keys = (value, fields) => object(value) && Object.keys(value).length === fields.length && fields.every(field => Object.hasOwn(value, field));
export function levelInputError(value) {
  if (!object(value) || !number(value.level_number)) return 'Use A Whole Level Number Between −2147483648 And 2147483647.';
  if (typeof value.name !== 'string' || !value.name.trim() || Array.from(value.name.trim()).length > 100 || /[\u0000-\u001f\u007f-\u009f]/u.test(value.name)) return 'Use A Nonempty Level Name Of At Most 100 Characters.';
  return '';
}
export function validLevelSnapshot(value) {
  return object(value) && number(value.level_number) && typeof value.name === 'string' && Boolean(value.name.length) && typeof value.is_active === 'boolean' && timestamp(value.updated_at) && number(value.metadata_revision) && value.metadata_revision > 0;
}
export function levelRequestError(value, mode) {
  if (mode === 'delete') return keys(value, ['expected_metadata_revision']) && number(value.expected_metadata_revision) && value.expected_metadata_revision > 0 ? '' : 'Refresh To Load The Current Level Revision.';
  if (mode === 'bulk') {
    if (!keys(value, ['levels']) || !Array.isArray(value.levels) || value.levels.length < 1 || value.levels.length > MAX_LEVEL_BATCH) return 'Preview Between 1 And 50 Levels.';
    return value.levels.some(item => !keys(item, ['level_number', 'name']) || levelInputError(item)) ? 'Check Every Level Number And Name.' : '';
  }
  if (!keys(value, mode === 'edit' ? ['level_number', 'name', 'expected'] : ['level_number', 'name'])) return 'Use Only Level Number, Level Name And The Required Edit Snapshot.';
  return levelInputError(value) || (mode === 'edit' && (!keys(value.expected, ['level_number', 'name', 'is_active', 'updated_at', 'metadata_revision']) || !validLevelSnapshot(value.expected)) ? 'Refresh To Load The Exact Current Level Snapshot.' : '');
}
export const duplicateLevelNumbers = rows => new Set(rows.map(row => row.level_number)).size !== rows.length;
export function levelSnapshot(level) {
  return { level_number: level.level_number, name: level.name, is_active: level.is_active, updated_at: level.updated_at, metadata_revision: level.metadata_revision };
}
export function previewLevels(count, levels) {
  if (!Number.isInteger(count) || count < 1 || count > MAX_LEVEL_BATCH) throw new Error('Choose Between 1 And 50 Levels.');
  const start = levels.reduce((maximum, level) => Math.max(maximum, level.level_number), 0) + 1;
  if (start + count - 1 > MAX_LEVEL_NUMBER) throw new Error('Generated Numbers Exceed The Integer Limit. Add Individual Levels With Available Numbers.');
  return Array.from({ length: count }, (_, index) => ({ level_number: String(start + index), name: `Level ${start + index}` }));
}
export function levelRowsError(rows, levels, editingId = null) {
  const parsed = rows.map(row => ({ level_number: row.level_number === '' ? NaN : Number(row.level_number), name: row.name }));
  for (const row of parsed) { const error = levelInputError(row); if (error) return error; }
  if (duplicateLevelNumbers(parsed)) return 'Each Preview Row Must Have A Different Level Number.';
  if (parsed.some(row => levels.some(level => level.id !== editingId && level.level_number === row.level_number))) return 'A Level Number Is Already In Use. Choose Another Number.';
  return '';
}
export function validateLevelResponse(data, input, mode, id) {
  if (mode === 'delete') {
    if (data?.deleted_level_id !== id) throw new Error('Level Deletion Could Not Be Confirmed.');
    return data;
  }
  const rows = mode === 'bulk' ? data?.levels : [data?.level];
  const wanted = mode === 'bulk' ? input.levels : [input];
  if (!Array.isArray(rows) || rows.length !== wanted.length || new Set(rows.map(row => row?.id)).size !== rows.length || rows.some(row =>
    !validLevelSnapshot(row) || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(row.id) ||
    !wanted.some(item => item.level_number === row.level_number && item.name.trim() === row.name) ||
    (mode === 'edit' ? row.id !== id || row.is_active !== input.expected.is_active ||
      row.metadata_revision !== input.expected.metadata_revision + Number(input.level_number !== input.expected.level_number || input.name.trim() !== input.expected.name) :
      row.is_active !== false || row.metadata_revision !== 1))) throw new Error('Level Save Could Not Be Confirmed.');
  if (new Set(rows.map(row => row.level_number)).size !== rows.length) throw new Error('Incomplete Level Batch.');
  return data;
}
