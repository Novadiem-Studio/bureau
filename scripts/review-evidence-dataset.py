#!/usr/bin/env python3
"""review-evidence-dataset.py — build the first-party REVIEW-EVIDENCE dataset from Bureau run records.

Usage:
  review-evidence-dataset.py --roots "<glob of repo dirs>" --out <dir> [--patterns <architect-challenger-patterns.md>] [--as-of YYYY-MM-DD]

Reads every <repo>/.bureau/{runs,archive}/<slug>/ and takes ONLY aggregate, non-identifying facts:
  accounting.json        phases.critic_loops (per stage), tokens.rework_ratio, specialist spawns by role
  delegate-decisions.md  cold-review decisions (proceed | revise | escalate), one per record
  checkpoints/*-reviewer-verdict.json   cold-review verdicts: decision, whether Required-changes were named,
                                        whether the escalation cites signal 5 (public shipping) only
  proofread.md, verdicts/challenger-proofread-*.json   per-page proofreader verdicts on content runs
Optionally parses the Challenger pattern taxonomy doc (Pattern Frequency Table + Full Findings Table) into
counts by pattern, severity, action and artifact type. Finding TEXT is never copied.

Publication guard (docs/plan-content-taxonomy.md §7, sensitive-source guard): runs are identified by
repo, workflow family and date only — no slugs, no task names, no finding text from non-devweb repos.
The one exception is devweb's own proofreader hold concerns (they describe devweb's own pages).

Writes <out>/dataset.json, <out>/tables.md (the ONLY quotable surface), <out>/coverage.md.
"""
import argparse, glob, json, os, re, statistics
from collections import Counter, defaultdict
from datetime import date

def val(x): return x['value'] if isinstance(x, dict) and 'value' in x else x

CONTENT_WF = {'write-article', 'write-glossary', 'write-topic-overview', 'write-data-page', 'write-evidence-page'}
def family(wf):
    if not wf: return 'unknown'
    head = re.split(r'[\s(:→]', str(wf).strip())[0].lower()
    if head in CONTENT_WF: return 'content (' + head + ')'
    if head.startswith('feature'): return 'feature'
    if head.startswith('bug-fix'): return 'bug-fix'
    if head.startswith('execute-plan'): return 'execute-plan'
    if head.startswith('design-build'): return 'design-build'
    if head.startswith('build-review-cold'): return 'build-review-cold'
    if head.startswith('maintenance'): return 'maintenance-sweep'
    return head

def parse_ledger(path):
    c = Counter()
    if os.path.exists(path):
        for m in re.finditer(r'^decision:\s*(proceed|revise|escalate)\b', open(path, errors='ignore').read(), re.M):
            c[m.group(1)] += 1
    return c

def parse_verdicts(rd):
    out = []
    for vp in sorted(glob.glob(os.path.join(rd, 'checkpoints', '*-reviewer-verdict.json'))):
        try: v = json.load(open(vp))
        except Exception: continue
        dec = v.get('Decision'); rc = (v.get('Required-changes') or '').strip()
        esc = v.get('Escalation') or ''
        has_changes = bool(rc) and not rc.lower().startswith('none')
        sig5_only = ('5' in re.findall(r'[Ss]ignal\s*(\d)', esc)) and len(set(re.findall(r'[Ss]ignal\s*(\d)', esc))) == 1
        placeholder = (v.get('Artifact-hash') or '') == '0' * 64
        out.append({'decision': dec, 'required_changes': has_changes, 'signal5_only': sig5_only, 'placeholder_hash': placeholder})
    return out

def parse_proofread(rd):
    """Proofreader verdict EVENTS (one per page per pass) from the three formats the content runs used:
    table rows with a CLEAR/HOLD/DROP cell (bold or not), `Verdict: X` lines, and verdicts/*.json
    ({verdict: CLEAR|HOLD|BLOCKED|PASS}). Hold concerns are the row's last cell or a `### <id> — HOLD. <text>` heading."""
    c = Counter(); holds = []
    p = os.path.join(rd, 'proofread.md')
    if os.path.exists(p):
        for line in open(p, errors='ignore').read().splitlines():
            if line.startswith('|'):
                cells = [x.strip().strip('*').strip() for x in line.strip().strip('|').split('|')]
                hits = [x for x in cells if x in ('CLEAR', 'HOLD', 'DROP')]
                if hits:
                    c[hits[0]] += 1
                    if hits[0] in ('HOLD', 'DROP') and cells:
                        holds.append(re.sub(r'\s+', ' ', cells[-1])[:180])
                continue
            m = re.match(r'^\s*\**Verdict:?\**\s*\**(CLEAR|HOLD|DROP)\b', line)
            if m: c[m.group(1)] += 1; continue
            m = re.match(r'^#{2,4}\s*[A-Z]\d+\s*[—-]+\s*HOLD\.?\s*(.*)', line)
            if m: holds.append(re.sub(r'\s+', ' ', m.group(1))[:180])
    for jp in glob.glob(os.path.join(rd, 'verdicts', 'challenger-proofread-*.json')):
        try: j = json.load(open(jp))
        except Exception: continue
        dec = str(j.get('verdict') or j.get('Decision') or j.get('decision') or '').upper()
        dec = {'BLOCKED': 'HOLD', 'PASS': 'CLEAR'}.get(dec, dec)
        if dec in ('CLEAR', 'HOLD', 'DROP'): c[dec] += 1
    return c, holds

def parse_patterns(path):
    if not path or not os.path.exists(path): return None
    t = open(path, errors='ignore').read()
    freq = []
    sec = t.split('## Pattern Frequency Table', 1)[1].split('\n## ', 1)[0]
    for line in sec.splitlines():
        m = re.match(r'^\|\s*([a-z][a-z0-9/-]+)\s*\|\s*([0-9]+)(?:–([0-9]+))?', line)
        if m:
            lo = int(m.group(2)); hi = int(m.group(3)) if m.group(3) else lo
            freq.append({'pattern': m.group(1), 'count_low': lo, 'count_high': hi})
    findings = t.split('## Full Findings Table', 1)[1].split('\n## ', 1)[0] if '## Full Findings Table' in t else ''
    sev = Counter(); act = Counter(); art = Counter(); runs = set(); n = 0
    for line in findings.splitlines():
        cells = [x.strip() for x in line.strip().strip('|').split('|')]
        if len(cells) >= 6 and cells[1] in ('BLOCKER', 'WARNING', 'NOTE', 'INFO'):
            n += 1; sev[cells[1]] += 1; act[cells[3]] += 1; art[cells[4]] += 1; runs.add(cells[0])
    refresh = re.search(r'## Refresh — (\d{4}-\d{2}-\d{2})', t)
    return {'source_doc': os.path.basename(path), 'refresh_date': refresh.group(1) if refresh else None,
            'frequency': freq, 'findings_total': n, 'runs_coded': len(runs), 'by_severity': dict(sev),
            'by_action': dict(act), 'by_artifact': dict(art)}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--roots', required=True, help='glob of repo dirs, e.g. "/Users/robin/Code/novadiem/*"')
    ap.add_argument('--out', required=True)
    ap.add_argument('--patterns', default=None)
    ap.add_argument('--as-of', default=date.today().isoformat())
    a = ap.parse_args()

    runs = []
    for acc in sorted(glob.glob(os.path.join(a.roots, '.bureau', '*', '*', 'accounting.json'))):
        rd = os.path.dirname(acc); slug = os.path.basename(rd)
        repo = rd.split('/.bureau/')[0].rstrip('/').split('/')[-1]
        try: d = json.load(open(acc))
        except Exception: continue
        wf = val((d.get('run') or {}).get('workflow'))
        rdate = re.sub(r'^(\d{4})(\d{2})(\d{2}).*', r'\1-\2-\3', slug)[:10] if re.match(r'^\d{8}', slug) else None
        cl = val((d.get('phases') or {}).get('critic_loops')) or {}
        cl = {k: int(v) for k, v in cl.items() if isinstance(v, (int, float))} if isinstance(cl, dict) else {}
        rr = val((d.get('tokens') or {}).get('rework_ratio'))
        rr = float(rr) if isinstance(rr, (int, float)) else None
        sp = d.get('specialist_spawns') or []
        roles = Counter((val(s.get('role')) or '?') for s in sp)
        ledger = parse_ledger(os.path.join(rd, 'delegate-decisions.md'))
        verdicts = parse_verdicts(rd)
        proof, holds = parse_proofread(rd)
        fam = family(wf)
        runs.append({'repo': repo, 'workflow_family': fam, 'date': rdate, 'schema_version': d.get('schema_version'),
                     'critic_loops': cl, 'critic_loops_total': sum(cl.values()) if cl else None,
                     'rework_ratio': rr, 'challenger_spawns_recorded': roles.get('challenger', 0),
                     'specialist_spawns_recorded': len(sp), 'cold_review_decisions': dict(ledger),
                     'cold_review_verdicts': verdicts, 'proofread': dict(proof),
                     'proofread_holds': holds if repo == 'devweb' else []})

    critic_stage = [r for r in runs if not r['workflow_family'].startswith('content')]
    with_loops = [r for r in critic_stage if r['critic_loops_total'] is not None]
    loop_dist = Counter(min(r['critic_loops_total'], 4) for r in with_loops)
    by_stage = defaultdict(list)
    for r in with_loops:
        for k in ('analyst', 'architect', 'prompts'): by_stage[k].append(r['critic_loops'].get(k, 0))
    rr_vals = [r['rework_ratio'] for r in runs if r['rework_ratio'] is not None]
    rr_pos = [x for x in rr_vals if x > 0]
    decisions = Counter()
    for r in runs: decisions.update(r['cold_review_decisions'])
    verdicts = [v for r in runs for v in r['cold_review_verdicts']]
    proof_total = Counter()
    for r in runs: proof_total.update(r['proofread'])
    def q(vals, p):
        if not vals: return None
        s = sorted(vals); i = (len(s) - 1) * p; lo = int(i); hi = min(lo + 1, len(s) - 1)
        return round(s[lo] + (s[hi] - s[lo]) * (i - lo), 3)
    rollup = {
        'runs_total': len(runs), 'repos': len({r['repo'] for r in runs}),
        'runs_with_critic_stage': len(critic_stage), 'runs_with_critic_loop_record': len(with_loops),
        'runs_with_at_least_one_critic_loop': sum(1 for r in with_loops if r['critic_loops_total'] > 0),
        'critic_loop_distribution': {('4+' if k == 4 else str(k)): v for k, v in sorted(loop_dist.items())},
        'mean_loops_by_stage': {k: round(statistics.mean(v), 2) for k, v in by_stage.items() if v},
        'rework_ratio_runs_recorded': len(rr_vals), 'rework_ratio_runs_positive': len(rr_pos),
        'rework_ratio_median_all': q(rr_vals, 0.5), 'rework_ratio_p75_all': q(rr_vals, 0.75), 'rework_ratio_max': max(rr_vals) if rr_vals else None,
        'rework_ratio_median_positive': q(rr_pos, 0.5),
        'cold_review_decisions_total': dict(decisions), 'cold_review_runs_with_ledger': sum(1 for r in runs if r['cold_review_decisions']),
        'cold_review_verdict_files': len(verdicts),
        'cold_review_verdicts_with_required_changes': sum(1 for v in verdicts if v['required_changes']),
        'cold_review_escalations_signal5_only': sum(1 for v in verdicts if v['decision'] == 'escalate' and v['signal5_only']),
        'cold_review_placeholder_hash_verdicts': sum(1 for v in verdicts if v['placeholder_hash']),
        'proofread_pages_total': dict(proof_total),
        'challenger_spawns_recorded_total': sum(r['challenger_spawns_recorded'] for r in runs),
    }
    patterns = parse_patterns(a.patterns)
    dataset = {'as_of': a.as_of, 'roots': a.roots, 'runs': runs, 'rollup': rollup, 'challenger_findings_taxonomy': patterns,
               'notes': ['The corpus is every run directory with an accounting.json under the scanned roots; runs without one are not counted.',
                         'Runs are identified by repo, workflow family and date only; no task names or finding text from non-devweb repos.',
                         'critic_loops counts revise cycles the Challenger forced at the analyst/architect/prompts stages (recorded in accounting.json); content workflows have no critic stage and are excluded from loop rates.',
                         'rework_ratio is the accounting\'s share of tokens spent on rework; None where the run did not record it.',
                         'Cold-review decisions come from each run\'s delegate-decisions.md ledger; verdict files add whether Required-changes were named and whether an escalation cited signal 5 (public shipping) alone.',
                         'The Challenger findings taxonomy is parsed from the framework\'s own pattern doc (counts only; the doc\'s refresh date is the as-of for those counts).']}
    os.makedirs(a.out, exist_ok=True)
    json.dump(dataset, open(os.path.join(a.out, 'dataset.json'), 'w'), indent=1)

    L = [f"# Review-evidence dataset — tables (as of {a.as_of})\n"]
    L.append("## Corpus\n")
    L.append(f"| Runs | Repos | Runs with a critic stage | Runs with a critic-loop record | Runs with a cold-review ledger | Cold-review verdict files | Challenger spawns recorded |")
    L.append("|---|---|---|---|---|---|---|")
    L.append(f"| {rollup['runs_total']} | {rollup['repos']} | {rollup['runs_with_critic_stage']} | {rollup['runs_with_critic_loop_record']} | {rollup['cold_review_runs_with_ledger']} | {rollup['cold_review_verdict_files']} | {rollup['challenger_spawns_recorded_total']} |\n")
    L.append("## Critic loops (non-content workflows with a record)\n")
    L.append("| Runs with a record | Runs with at least one loop | Share | Loops = 0 | 1 | 2 | 3 | 4+ | Mean analyst loops | Mean architect loops | Mean prompts loops |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|")
    ld = rollup['critic_loop_distribution']; n = rollup['runs_with_critic_loop_record']; k = rollup['runs_with_at_least_one_critic_loop']
    ms = rollup['mean_loops_by_stage']
    L.append(f"| {n} | {k} | {k/n:.0%} | {ld.get('0',0)} | {ld.get('1',0)} | {ld.get('2',0)} | {ld.get('3',0)} | {ld.get('4+',0)} | {ms.get('analyst')} | {ms.get('architect')} | {ms.get('prompts')} |\n")
    L.append("## Rework ratio (share of tokens spent on rework, where recorded)\n")
    L.append("| Runs recorded | Runs with ratio > 0 | Median (all) | 75th percentile (all) | Max | Median (ratio > 0 only) |")
    L.append("|---|---|---|---|---|---|")
    L.append(f"| {rollup['rework_ratio_runs_recorded']} | {rollup['rework_ratio_runs_positive']} | {rollup['rework_ratio_median_all']} | {rollup['rework_ratio_p75_all']} | {round(rollup['rework_ratio_max'],3) if rollup['rework_ratio_max'] is not None else 'n/a'} | {rollup['rework_ratio_median_positive']} |\n")
    L.append("## Cold-review decisions (Delegate ledgers)\n")
    dec = rollup['cold_review_decisions_total']
    L.append("| proceed | revise | escalate | Verdict files inspected | With required changes named | Escalations citing signal 5 (public shipping) only | Placeholder-hash verdicts (discarded) |")
    L.append("|---|---|---|---|---|---|---|")
    L.append(f"| {dec.get('proceed',0)} | {dec.get('revise',0)} | {dec.get('escalate',0)} | {rollup['cold_review_verdict_files']} | {rollup['cold_review_verdicts_with_required_changes']} | {rollup['cold_review_escalations_signal5_only']} | {rollup['cold_review_placeholder_hash_verdicts']} |\n")
    L.append("## Proofreader verdict events on content pages (devweb runs; one event per page per pass)\n")
    pt = rollup['proofread_pages_total']
    L.append("| CLEAR | HOLD | DROP |"); L.append("|---|---|---|"); L.append(f"| {pt.get('CLEAR',0)} | {pt.get('HOLD',0)} | {pt.get('DROP',0)} |\n")
    holds = [(r['date'], h) for r in runs for h in r['proofread_holds'] if h]
    if holds:
        L.append("## Proofreader hold concerns (devweb pages, one line each)\n"); L.append("| Run date | Concern |"); L.append("|---|---|")
        for d_, h in holds: L.append(f"| {d_} | {h.replace('|','/')} |")
        L.append("")
    if patterns:
        L.append(f"## Challenger findings taxonomy ({patterns['source_doc']}, refreshed {patterns['refresh_date']})\n")
        L.append(f"Two views of one taxonomy: the frequency table's counts are cumulative through the doc's {patterns['refresh_date']} refresh (the 8 originally coded runs plus 2 re-coded later); the severity/action/artifact counts below come from the doc's full findings table, which codes the original 8 runs only. Finding text is not reproduced.\n")
        L.append(f"Coded findings: {patterns['findings_total']} across {patterns['runs_coded']} runs. By severity: " + ", ".join(f"{k} {v}" for k, v in sorted(patterns['by_severity'].items())) + ". By action: " + ", ".join(f"{k} {v}" for k, v in sorted(patterns['by_action'].items(), key=lambda kv: -kv[1])) + ".\n")
        L.append("| Pattern | Count |"); L.append("|---|---|")
        for f_ in patterns['frequency']:
            L.append(f"| {f_['pattern']} | {f_['count_low']}" + (f"–{f_['count_high']}" if f_['count_high'] != f_['count_low'] else "") + " |")
        L.append("")
        L.append("| Artifact type | Findings |"); L.append("|---|---|")
        for k, v in sorted(patterns['by_artifact'].items(), key=lambda kv: -kv[1]): L.append(f"| {k} | {v} |")
        L.append("")
    L.append("## Runs (identified by repo, workflow family, date)\n")
    L.append("| Repo | Workflow | Date | Critic loops | Rework ratio | Challenger spawns | Cold-review decisions | Proofreader |")
    L.append("|---|---|---|---|---|---|---|---|")
    for r in sorted(runs, key=lambda r: (r['date'] or '', r['repo'])):
        cd = ", ".join(f"{k} {v}" for k, v in sorted(r['cold_review_decisions'].items())) or "none"
        pf = ", ".join(f"{k} {v}" for k, v in sorted(r['proofread'].items())) or "n/a"
        L.append(f"| {r['repo']} | {r['workflow_family']} | {r['date']} | {r['critic_loops_total'] if r['critic_loops_total'] is not None else 'n/a'} | {round(r['rework_ratio'],3) if r['rework_ratio'] is not None else 'n/a'} | {r['challenger_spawns_recorded']} | {cd} | {pf} |")
    open(os.path.join(a.out, 'tables.md'), 'w').write("\n".join(L) + "\n")
    C = ["# Coverage\n", "| Record | Runs with it | Runs without |", "|---|---|---|"]
    for name, pred in (('critic_loops', lambda r: r['critic_loops_total'] is not None), ('rework_ratio', lambda r: r['rework_ratio'] is not None),
                       ('cold-review ledger', lambda r: bool(r['cold_review_decisions'])), ('reviewer verdict files', lambda r: bool(r['cold_review_verdicts'])),
                       ('proofread verdicts', lambda r: bool(r['proofread'])), ('specialist spawns recorded', lambda r: r['specialist_spawns_recorded'] > 0)):
        k = sum(1 for r in runs if pred(r)); C.append(f"| {name} | {k} | {len(runs) - k} |")
    open(os.path.join(a.out, 'coverage.md'), 'w').write("\n".join(C) + "\n")
    print(f"runs: {len(runs)} repos: {rollup['repos']} critic-loop records: {n} ledgers: {rollup['cold_review_runs_with_ledger']} verdict files: {rollup['cold_review_verdict_files']} -> {a.out}")

if __name__ == '__main__':
    main()
