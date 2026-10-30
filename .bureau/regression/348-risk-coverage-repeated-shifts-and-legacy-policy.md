name: coverage retains earlier lite phases and legacy scans use the recorded policy ref
command: |
  set -eu
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  export ROOT
  python3 - <<'PY'
  import json, os, pathlib, subprocess, tempfile
  root = pathlib.Path(os.environ['ROOT'])
  with tempfile.TemporaryDirectory() as tmp:
      tmp = pathlib.Path(tmp); w = tmp / 'w'; w.mkdir(); run = tmp / 'run'; (run / 'risk-tags').mkdir(parents=True)
      def git(*args):
          return subprocess.check_output(['git', '-C', str(w), *args], text=True).strip()
      git('init', '-q', '-b', 'main'); git('config', 'user.email', 't@t'); git('config', 'user.name', 't')
      f = w / 'a.py'; f.write_text('a = 0\n'); git('add', '-A'); git('commit', '-qm', 'base'); a = git('rev-parse', 'HEAD')
      def commit(n):
          f.write_text('a = %d\n' % n); git('commit', '-qam', str(n)); return git('rev-parse', 'HEAD')
      b = commit(1); c = commit(2); d = commit(3)
      def scan(base, head, unit):
          subprocess.run([str(root / 'scripts/risk-tags.sh'), '--worktree', str(w), '--base', base,
                          '--head', head, '--policy-ref', a, '--out', str(run / 'risk-tags' / (unit + '.json'))], check=True, capture_output=True)
      scan(c, d, '03')
      state = {'workflow': 'bureau-lite', 'git': {'base_sha': a, 'worktree_path': str(w)}, 'workflow_shifts': [
          {'from': 'bureau-lite', 'to': 'execute-plan', 'head': b},
          {'from': 'execute-plan', 'to': 'bureau-lite', 'head': c, 'effective_from': '03'}]}
      def save():
          (run / 'state.json').write_text(json.dumps(state))
      def coverage():
          p = subprocess.run([str(root / 'scripts/risk-coverage.sh'), str(run)], capture_output=True, text=True)
          return p.returncode, json.loads(p.stdout)
      save(); (run / 'log.md').write_text('')
      rc, rec = coverage(); assert rc == 1 and any('gap:' in x for x in rec['problems']), rec
      scan(a, b, '01')
      rc, rec = coverage(); assert rc == 0 and set(rec['units']) == {'01', '03'}, rec
      # A legacy feature run has no git.base_sha, but each shift holds its frozen policy.
      state['workflow'] = 'feature'; del state['git']['base_sha']
      state['workflow_shifts'] = [{'from': 'feature', 'to': 'bureau-lite', 'effective_from': '03', 'policy_ref': a}]
      save()
      # Execute the actual documented selector, not a duplicate test-only expression.
      doc = (root / 'workflows/bureau-lite.md').read_text()
      selector = doc[doc.index('POLICY_REF=$(jq'):doc.index('      scripts/risk-tags.sh --worktree')]
      cmd = selector + '\nprintf "%s" "$POLICY_REF"\n'
      env = dict(os.environ, RUN_DIR=str(run))
      p = subprocess.run(['sh', '-c', cmd], env=env, capture_output=True, text=True)
      assert p.returncode == 0 and p.stdout == a, p
      rc, rec = coverage(); assert rc == 0, rec
      del state['workflow_shifts'][0]['policy_ref']; save()
      p = subprocess.run(['sh', '-c', cmd], env=env, capture_output=True, text=True)
      assert p.returncode == 2 and p.stdout == '', p
  print('PASS')
  PY
expected: exit 0; stdout PASS. A second downshift cannot hide an unscanned earlier lite phase; covering both phases passes. Legacy runs resolve their frozen policy ref from the shift, and absent policy refs stop before scanning.
phase: bureau-lite · PR #101 review
owner: scripts/risk-coverage.sh + workflows/bureau-lite.md
