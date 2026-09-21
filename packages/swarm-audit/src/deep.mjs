// deep.mjs — signals computed from what pull requests did, not what they said.
//
// The keyword codebook measures how often a failure was written about. These
// rules fire whether or not anyone narrated the problem, which matters because
// the corpus behind this tool is explicit that the largest failures were never
// narrated at all: its migration chain forked eleven times and not one fork was
// mentioned in a pull request, because forks happen between pushes and are
// repaired before review.
//
// Both signals need per-pull-request file lists, which cost one API request
// each. That is why they sit behind --deep.

const MIGRATION = /(?:^|\/)(?:migrations?|alembic|db\/migrate|prisma\/migrations)\//i;

const at = (v) => (v ? Date.parse(v) : null);

/**
 * Pull requests that touched migration files while another pull request had
 * migration files open too.
 *
 * Two lanes writing a migration against the same parent is the mechanism behind
 * the largest incident category in the case study. Each lane is internally
 * consistent, each lane's tests pass, and git reports no conflict because the
 * two lanes wrote different files. Overlapping open windows are the observable
 * part of that, and they are observable without anyone describing them.
 */
export function migrationOverlaps(prs, { pattern = MIGRATION } = {}) {
  const touching = prs
    .map((pr) => ({
      number: pr.number,
      opened: at(pr.created_at),
      closed: at(pr.merged_at) ?? at(pr.closed_at) ?? Date.now(),
      files: (pr.files ?? []).map((f) => (typeof f === 'string' ? f : f.path)).filter(Boolean),
    }))
    .filter((pr) => pr.opened && pr.files.some((f) => pattern.test(f)));

  const hits = new Map();
  for (let i = 0; i < touching.length; i += 1) {
    for (let j = i + 1; j < touching.length; j += 1) {
      const a = touching[i];
      const b = touching[j];
      if (!(a.opened < b.closed && b.opened < a.closed)) continue;
      for (const [self, other] of [[a, b], [b, a]]) {
        const evidence = `migration files open at the same time as #${other.number}`;
        const list = hits.get(self.number) ?? [];
        if (!list.some((h) => h.evidence === evidence)) {
          list.push({ id: 'shared_resources', confidence: 'high', evidence, kind: 'structural' });
        }
        hits.set(self.number, list);
      }
    }
  }
  return hits;
}

/**
 * Pull requests that reference an older pull request which was closed without
 * being merged.
 *
 * That is a supersede chain whether or not the word appears: someone opened
 * work, abandoned it, and a later pull request carries the same ground. The
 * keyword rule only finds the ones whose author said so.
 *
 * `states` maps a referenced number to { merged, closed, isPr }. Numbers that
 * are issues, or that cannot be resolved, are skipped rather than guessed —
 * a body reference is just an integer, and in this corpus three quarters of
 * them point at issues.
 */
export function supersedeChains(prs, states) {
  const hits = new Map();
  for (const pr of prs) {
    for (const ref of pr.referenced_prs ?? []) {
      if (ref >= pr.number) continue;
      const state = states.get(ref);
      if (!state?.isPr || state.merged || !state.closed) continue;
      const list = hits.get(pr.number) ?? [];
      list.push({
        id: 'rework_supersede',
        confidence: 'high',
        evidence: `references #${ref}, which was closed without merging`,
        kind: 'structural',
      });
      hits.set(pr.number, list);
    }
  }
  return hits;
}

/** Merge several signal maps into one. */
export function mergeSignals(...maps) {
  const out = new Map();
  for (const map of maps) {
    for (const [number, hits] of map) {
      out.set(number, [...(out.get(number) ?? []), ...hits]);
    }
  }
  return out;
}

export const MIGRATION_PATTERN = MIGRATION;
