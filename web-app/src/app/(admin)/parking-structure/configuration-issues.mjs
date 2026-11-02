// Group presentation only. Keep every underlying check for counts and details;
// validation readiness and publication eligibility still come from the server.
export function groupConfigurationIssues(issues) {
  const groups = new Map();
  for (const issue of issues) {
    const key = JSON.stringify([issue.severity ?? null, issue.level_id ?? null, issue.zone_id ?? null, issue.message]);
    if (!groups.has(key)) groups.set(key, {
      key, severity: issue.severity, level_id: issue.level_id ?? null,
      zone_id: issue.zone_id ?? null, message: issue.message, checks: [],
    });
    groups.get(key).checks.push(issue);
  }
  return [...groups.values()];
}
