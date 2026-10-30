name: project policy read errors fail closed while absent optional policy stays clean
command: |
  set -eu
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  export ROOT
  python3 - <<'PY'
  import json, os, pathlib, subprocess, tempfile
  root = pathlib.Path(os.environ['ROOT'])
  with tempfile.TemporaryDirectory() as tmp:
      tmp = pathlib.Path(tmp); w = tmp / 'w'; w.mkdir()
      def git(*args):
          return subprocess.check_output(['git', '-C', str(w), *args], text=True).strip()
      git('init', '-q'); git('config', 'user.email', 't@t'); git('config', 'user.name', 't')
      f = w / 'a.py'; f.write_text('a = 0\n'); git('add', '-A'); git('commit', '-qm', 'base'); base = git('rev-parse', 'HEAD')
      f.write_text('a = 1\n'); git('commit', '-qam', 'clean')
      cmd = [str(root / 'scripts/risk-tags.sh'), '--worktree', str(w), '--base', base]
      p = subprocess.run(cmd, capture_output=True, text=True)
      assert p.returncode == 0 and json.loads(p.stdout)['result'] == 'clean', p
      policy = {'tags': [{'id': 'project-only', 'class': 'review', 'lines': ['SPECIAL_MARKER']}]}
      (w / 'project-context.md').write_text('```json risk_tags\n' + json.dumps(policy) + '\n```\n')
      git('add', '-A'); git('commit', '-qm', 'policy'); base = git('rev-parse', 'HEAD')
      f.write_text('a = "SPECIAL_MARKER"\n'); git('commit', '-qam', 'project-sensitive')
      cmd[-1] = base
      p = subprocess.run(cmd, capture_output=True, text=True)
      assert p.returncode == 1 and json.loads(p.stdout)['review_tags'] == ['project-only'], p
      real_git = subprocess.check_output(['sh', '-c', 'command -v git'], text=True).strip()
      bin_dir = tmp / 'bin'; bin_dir.mkdir(); wrapper = bin_dir / 'git'
      wrapper.write_text('#!/usr/bin/env python3\nimport os,sys\n'
                         'if os.environ.get("FAIL_OP") in sys.argv:\n'
                         '    print("injected policy read failure", file=sys.stderr); sys.exit(128)\n'
                         'os.execv(os.environ["REAL_GIT"], [os.environ["REAL_GIT"], *sys.argv[1:]])\n')
      wrapper.chmod(0o755)
      env = dict(os.environ, REAL_GIT=real_git, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'])
      for op, expected in [('ls-tree', 'cannot list project policy'), ('show', 'cannot read')]:
          p = subprocess.run(cmd, env=dict(env, FAIL_OP=op), capture_output=True, text=True)
          rec = json.loads(p.stdout)
          assert p.returncode == 2 and rec['result'] == 'error' and expected in rec['error'], rec
  print('PASS')
  PY
expected: exit 0; stdout PASS. Missing project-context.md is optional, an existing project-only trigger requires review, and injected ls-tree/show failures produce error records instead of silently dropping that trigger.
phase: bureau-lite · PR #101 review
owner: scripts/risk-tags.sh
