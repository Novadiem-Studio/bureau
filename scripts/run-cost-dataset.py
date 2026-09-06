#!/usr/bin/env python3
"""run-cost-dataset.py — build the first-party run-cost dataset from Bureau accounting.json files.

Usage:
  run-cost-dataset.py --target-repo <repo> --pricing <model-pricing.json> --out <dir>
                      [--workflows write-article,write-glossary,...] [--as-of YYYY-MM-DD]

Reads every <repo>/.bureau/{runs,archive}/<slug>/accounting.json (schema v1 or v2) plus that run's
log.md ([EXTERNAL-ACTION] model-pass lines) and article.mdx / glossary/ / topics/ (what it produced).
Applies the dated pricing table and writes:
  <out>/dataset.json          every run, every leg, every number and the formula that produced it
  <out>/tables.md             the markdown tables a writer may quote — VERBATIM, nothing derived elsewhere
  <out>/coverage.md           which runs captured which legs; what is estimated; what is missing
  <out>/run-frontmatter/<essay-slug>.yaml   a `run:` block per fully-covered essay run (RunTable rows)

Rules (docs/plan-content-taxonomy.md §5A): nothing derived is stored in accounting.json; dollars are
derived HERE from published per-token prices with the arithmetic printed; the price basis is dated
and sourced; a leg with confidence "unavailable"/"partial" is reported as such, never filled in.
The dollar figures are API-list-price EQUIVALENTS: the Claude legs ran on a Claude Code subscription
(not metered per token) and only the Grok passes were metered (OpenRouter). Grok tokens are
ESTIMATED from the audit line's byte counts at the stated bytes-per-token ratio.
"""
import argparse, glob, json, os, re, statistics, sys
from datetime import date

def val(x):
    """accounting.json wraps most fields as {value, confidence}; unwrap either shape."""
    if isinstance(x, dict) and 'value' in x:
        return x['value']
    return x

def conf(x):
    return x.get('confidence') if isinstance(x, dict) else None

def leg_tokens(leg):
    t = (leg or {}).get('tokens') or {}
    out = {}
    for k in ('input', 'cache_creation', 'cache_read', 'output'):
        v = val(t.get(k))
        out[k] = int(v) if isinstance(v, (int, float)) else None
    return out

def usd(tokens, price):
    """tokens dict + price dict -> (cost, formula). None tokens count as 0 but are flagged by caller."""
    parts, total = [], 0.0
    for k, pk in (('input', 'input'), ('cache_creation', 'cache_write'), ('cache_read', 'cache_read'), ('output', 'output')):
        n = tokens.get(k) or 0
        p = price[pk]
        c = n / 1e6 * p
        total += c
        parts.append(f"{n/1e6:.3f}M x ${p}")
    return round(total, 2), " + ".join(parts) + f" = ${total:.2f}"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--target-repo', required=True)
    ap.add_argument('--pricing', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--workflows', default='write-article,write-glossary,write-topic-overview')
    ap.add_argument('--as-of', default=date.today().isoformat())
    a = ap.parse_args()

    pricing = json.load(open(a.pricing))
    prices = pricing['models']          # alias -> {model, input, cache_write, cache_read, output}
    grok = pricing['openrouter']['x-ai/grok-4.3']
    bpt = pricing['grok_bytes_per_token_estimate']
    want = set(a.workflows.split(','))

    runs = []
    for acc in sorted(glob.glob(os.path.join(a.target_repo, '.bureau', '*', '*', 'accounting.json'))):
        rd = os.path.dirname(acc)
        slug = os.path.basename(rd)
        d = json.load(open(acc))
        wf = val((d.get('run') or {}).get('workflow'))
        if wf not in want:
            continue
        run_date = val((d.get('run') or {}).get('run_date')) or slug[:8]
        run_date = re.sub(r'^(\d{4})(\d{2})(\d{2}).*', r'\1-\2-\3', str(run_date))[:10]

        # what it produced
        produced = {}
        art = os.path.join(rd, 'article.mdx')
        if os.path.exists(art):
            m = re.search(r'^slug:\s*"?([a-z0-9-]+)"?', open(art, errors='ignore').read(), re.M)
            if m: produced = {'kind': 'essay', 'slug': m.group(1)}
        for sub, kind in (('glossary', 'glossary-terms'), ('topics', 'topic-overviews')):
            p = os.path.join(rd, sub)
            if os.path.isdir(p):
                n = len([f for f in os.listdir(p) if f.endswith('.mdx')])
                if n: produced = {'kind': kind, 'count': n}

        legs = []
        def add_leg(name, leg, model_alias):
            if not leg: return
            t = leg_tokens(leg)
            c = leg.get('confidence') or conf(leg.get('tokens')) or 'unknown'
            captured = c == 'exact' and all(v is not None for v in t.values())
            price = prices.get(model_alias)
            cost, formula = usd(t, price) if (captured and price) else (None, None)
            legs.append({'leg': name, 'agent': name, 'model': model_alias, 'tokens': t, 'turns': leg.get('turns'),
                         'confidence': c, 'captured': captured, 'usd_equiv': cost, 'formula': formula})
        # Conductor / Delegate / reviewer legs: model comes from model-routing / delegate roles
        routing = {}
        mr = os.path.join(rd, 'model-routing.json')
        if os.path.exists(mr):
            try: routing = {k: v.get('model') for k, v in (json.load(open(mr)).get('roles') or {}).items()}
            except Exception: routing = {}
        add_leg('The Conductor', d.get('conductor_tokens'), routing.get('conductor', 'opus'))
        add_leg('The Delegate (manager)', d.get('delegate_tokens'), routing.get('delegate', 'opus'))
        add_leg('Cold reviewer', d.get('reviewer_tokens'), routing.get('delegate', 'opus'))
        for sp in d.get('specialist_spawns') or []:
            t = leg_tokens(sp)
            model = val(sp.get('actual_model')) or val(sp.get('configured_model')) or 'sonnet'
            agent = val(sp.get('agent')) or val(sp.get('role')) or 'specialist'
            captured = all(v is not None for v in t.values())
            price = prices.get(model)
            cost, formula = usd(t, price) if (captured and price) else (None, None)
            legs.append({'leg': 'specialist', 'agent': agent, 'model': model, 'tokens': t, 'turns': val(sp.get('turns')),
                         'confidence': 'exact' if captured else 'unavailable', 'captured': captured,
                         'usd_equiv': cost, 'formula': formula})

        # Grok passes from the audit lines
        grok_calls = []
        logp = os.path.join(rd, 'log.md')
        if os.path.exists(logp):
            for line in open(logp, errors='ignore'):
                if line.startswith('[EXTERNAL-ACTION] model-pass') and 'status=ok' in line:
                    bi = int(re.search(r'bytes_in=(\d+)', line).group(1)); bo = int(re.search(r'bytes_out=(\d+)', line).group(1))
                    ti, to = bi / bpt, bo / bpt
                    cost = round(ti / 1e6 * grok['input'] + to / 1e6 * grok['output'], 4)
                    grok_calls.append({'bytes_in': bi, 'bytes_out': bo, 'tokens_in_est': round(ti), 'tokens_out_est': round(to),
                                       'usd': cost, 'formula': f"({bi}/{bpt})/1e6 x ${grok['input']} + ({bo}/{bpt})/1e6 x ${grok['output']} = ${cost:.4f}"})
        grok_usd = round(sum(g['usd'] for g in grok_calls), 4)

        captured_legs = [l for l in legs if l['captured']]
        claude_usd = round(sum(l['usd_equiv'] for l in captured_legs), 2) if captured_legs else None
        tok_total = sum(sum(v for v in l['tokens'].values() if v) for l in captured_legs)
        out_total = sum((l['tokens'].get('output') or 0) for l in captured_legs)
        cache_read = sum((l['tokens'].get('cache_read') or 0) for l in captured_legs)
        has_specialists = any(l['leg'] == 'specialist' and l['captured'] for l in legs)
        has_conductor = any(l['agent'] == 'The Conductor' and l['captured'] for l in legs)
        coverage = 'complete' if (has_specialists and has_conductor) else ('partial' if captured_legs else 'none')
        runs.append({'run': slug, 'date': run_date, 'workflow': wf, 'produced': produced, 'schema_version': d.get('schema_version'),
                     'legs': legs, 'grok_calls': grok_calls, 'coverage': coverage,
                     'totals': {'tokens_processed_captured': tok_total, 'output_tokens_captured': out_total,
                                'cache_read_tokens_captured': cache_read, 'legs_captured': len(captured_legs), 'legs_total': len(legs),
                                'claude_usd_equiv': claude_usd, 'grok_usd': grok_usd,
                                'total_usd_equiv': (round(claude_usd + grok_usd, 2) if claude_usd is not None else None)}})

    os.makedirs(a.out, exist_ok=True)
    complete_essays = [r for r in runs if r['coverage'] == 'complete' and r['produced'].get('kind') == 'essay']
    rollup = {}
    if complete_essays:
        costs = [r['totals']['total_usd_equiv'] for r in complete_essays]
        rollup = {'complete_essay_runs': len(complete_essays), 'median_usd_equiv_per_essay': round(statistics.median(costs), 2),
                  'min_usd_equiv': min(costs), 'max_usd_equiv': max(costs),
                  'median_tokens_processed': int(statistics.median([r['totals']['tokens_processed_captured'] for r in complete_essays])),
                  'cache_read_share': round(sum(r['totals']['cache_read_tokens_captured'] for r in complete_essays) /
                                            max(1, sum(r['totals']['tokens_processed_captured'] for r in complete_essays)), 3)}
        by_role = {}
        for r in complete_essays:
            for l in r['legs']:
                if l['captured']:
                    by_role[l['agent']] = round(by_role.get(l['agent'], 0) + l['usd_equiv'], 2)
        rollup['usd_equiv_by_agent_across_complete_essay_runs'] = dict(sorted(by_role.items(), key=lambda kv: -kv[1]))
    dataset = {'as_of': a.as_of, 'target_repo': a.target_repo, 'pricing_basis': pricing, 'runs': runs, 'rollup': rollup,
               'notes': ['USD figures are API list-price equivalents: Claude legs ran on a Claude Code subscription, not metered per token.',
                         f'Grok tokens are estimated from audit-line byte counts at {bpt} bytes per token; Grok was the only metered spend.',
                         'A leg whose tokens were not captured (confidence unavailable/partial, or schema v1) is excluded from totals and shown as such.',
                         'Model aliases (sonnet/opus/haiku) are priced at the model the alias resolves to on the as-of date; earlier runs may have executed on earlier models.']}
    json.dump(dataset, open(os.path.join(a.out, 'dataset.json'), 'w'), indent=1)

    # tables.md — the quotable surface
    L = []
    L.append(f"# Run-cost dataset — tables (as of {a.as_of})\n")
    L.append("## Price basis\n")
    L.append("| Alias | Priced as | Input $/M | Cache write $/M | Cache read $/M | Output $/M | Source | Fetched |")
    L.append("|---|---|---|---|---|---|---|---|")
    for alias, p in prices.items():
        L.append(f"| {alias} | {p['model']} | {p['input']} | {p['cache_write']} | {p['cache_read']} | {p['output']} | {p['source']} | {p['fetched']} |")
    L.append(f"| grok (OpenRouter) | x-ai/grok-4.3 | {grok['input']} | n/a | {grok.get('cache_read','n/a')} | {grok['output']} | {grok['source']} | {grok['fetched']} |")
    L.append(f"\nGrok token estimate: bytes / {bpt}. Claude legs ran on a subscription; USD is the API list-price equivalent.\n")
    L.append("## Runs\n")
    L.append("| Run | Date | Workflow | Produced | Coverage | Legs captured | Tokens processed (captured) | Output tokens | Cache-read share | Grok calls | Grok USD | Claude USD equiv | Total USD equiv |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in runs:
        t = r['totals']; pr = r['produced']
        prod = pr.get('slug') or (f"{pr.get('count')} {pr.get('kind')}" if pr else '?')
        share = f"{t['cache_read_tokens_captured']/t['tokens_processed_captured']:.0%}" if t['tokens_processed_captured'] else 'n/a'
        L.append(f"| {r['run']} | {r['date']} | {r['workflow']} | {prod} | {r['coverage']} | {t['legs_captured']}/{t['legs_total']} | {t['tokens_processed_captured']:,} | {t['output_tokens_captured']:,} | {share} | {len(r['grok_calls'])} | {t['grok_usd']:.4f} | {t['claude_usd_equiv'] if t['claude_usd_equiv'] is not None else 'n/a'} | {t['total_usd_equiv'] if t['total_usd_equiv'] is not None else 'n/a'} |")
    L.append("\n## Leg breakdown (complete-coverage essay runs)\n")
    for r in complete_essays:
        L.append(f"### {r['run']} → /articles/{r['produced']['slug']} ({r['date']})\n")
        L.append("| Agent | Model | Input | Cache write | Cache read | Output | USD equiv | Arithmetic |")
        L.append("|---|---|---|---|---|---|---|---|")
        for l in r['legs']:
            if l['captured']:
                t = l['tokens']
                L.append(f"| {l['agent']} | {l['model']} | {t['input']:,} | {t['cache_creation']:,} | {t['cache_read']:,} | {t['output']:,} | {l['usd_equiv']:.2f} | {l['formula']} |")
        for i, g in enumerate(r['grok_calls'], 1):
            L.append(f"| Grok pass {i} | grok-4.3 | ~{g['tokens_in_est']:,} (est) | n/a | n/a | ~{g['tokens_out_est']:,} (est) | {g['usd']:.4f} | {g['formula']} |")
        L.append(f"| **Total** | | | | | | **{r['totals']['total_usd_equiv']:.2f}** | Claude {r['totals']['claude_usd_equiv']:.2f} + Grok {r['totals']['grok_usd']:.4f} |\n")
    L.append("## Rollup (complete-coverage essay runs only)\n")
    for k, v in rollup.items():
        L.append(f"- {k}: {json.dumps(v)}")
    open(os.path.join(a.out, 'tables.md'), 'w').write("\n".join(L) + "\n")

    # coverage.md
    C = ["# Coverage\n", "| Run | Schema | Coverage | Conductor | Delegate | Reviewer | Specialists captured / recorded | Grok calls |", "|---|---|---|---|---|---|---|---|"]
    for r in runs:
        def st(name):
            for l in r['legs']:
                if l['agent'] == name: return l['confidence']
            return 'absent'
        sp_all = [l for l in r['legs'] if l['leg'] == 'specialist']; sp_cap = [l for l in sp_all if l['captured']]
        C.append(f"| {r['run']} | v{r['schema_version']} | {r['coverage']} | {st('The Conductor')} | {st('The Delegate (manager)')} | {st('Cold reviewer')} | {len(sp_cap)}/{len(sp_all)} | {len(r['grok_calls'])} |")
    open(os.path.join(a.out, 'coverage.md'), 'w').write("\n".join(C) + "\n")

    # run frontmatter blocks for RunTable (complete essay runs): one row per captured leg + Grok, tokens = all tokens processed
    fmdir = os.path.join(a.out, 'run-frontmatter'); os.makedirs(fmdir, exist_ok=True)
    for r in complete_essays:
        rows = []
        for l in r['legs']:
            if l['captured']:
                rows.append({'stage': l['agent'], 'model': l['model'], 'tokens': sum(v for v in l['tokens'].values() if v), 'cost': l['usd_equiv']})
        for i, g in enumerate(r['grok_calls'], 1):
            rows.append({'stage': f'Grok improve pass {i}', 'model': 'grok-4.3 (OpenRouter)', 'tokens': g['tokens_in_est'] + g['tokens_out_est'], 'cost': g['usd']})
        y = ["run:", "  rows:"]
        for row in rows:
            y.append(f'    - {{ stage: "{row["stage"]}", model: "{row["model"]}", tokens: {row["tokens"]}, cost: {row["cost"]} }}')
        open(os.path.join(fmdir, f"{r['produced']['slug']}.yaml"), 'w').write("\n".join(y) + "\n")
    print(f"runs: {len(runs)}  complete essay runs: {len(complete_essays)}  -> {a.out}")

if __name__ == '__main__':
    main()
