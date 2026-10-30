name: risk tags retain old rename scopes and reject malformed name-status records
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
      (w / 'migrations').mkdir(); (w / 'archive').mkdir()
      old = w / 'migrations/x.sql'; new = w / 'archive/x.txt'
      old.write_text(''.join('-- unchanged row %d\n' % n for n in range(40)))
      git('add', '-A'); git('commit', '-qm', 'base'); base = git('rev-parse', 'HEAD')
      old.rename(new); new.write_text(new.read_text() + 'DROP TABLE users;\n')
      git('add', '-A'); git('commit', '-qm', 'rename')
      assert git('diff', '--name-status', '-M', base).startswith('R'), 'fixture must exercise a rename'
      cmd = [str(root / 'scripts/risk-tags.sh'), '--worktree', str(w), '--base', base]
      p = subprocess.run(cmd, capture_output=True, text=True)
      rec = json.loads(p.stdout)
      assert p.returncode == 3 and 'destructive-migration' in rec['escalate_tags'], rec
      # Intercept only the name-status query; every other Git operation stays real.
      real_git = subprocess.check_output(['sh', '-c', 'command -v git'], text=True).strip()
      bin_dir = tmp / 'bin'; bin_dir.mkdir()
      wrapper = bin_dir / 'git'
      wrapper.write_text('#!/usr/bin/env python3\nimport os,sys\n'
                         'if "--name-status" in sys.argv:\n'
                         '    sys.stdout.buffer.write(bytes.fromhex(os.environ["STATUS_HEX"]))\n'
                         '    sys.exit(0)\n'
                         'os.execv(os.environ["REAL_GIT"], [os.environ["REAL_GIT"], *sys.argv[1:]])\n')
      wrapper.chmod(0o755)
      env = dict(os.environ, REAL_GIT=real_git, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'])
      for status in (b'R090\0old\0', b'C100\0old\0', b'M\0path', b'\0M\0path\0', b'M\0\0', b'BOGUS\0path\0'):
          p = subprocess.run(cmd, env=dict(env, STATUS_HEX=status.hex()), capture_output=True, text=True)
          rec = json.loads(p.stdout)
          assert p.returncode == 2 and rec['result'] == 'error', (status, rec)
  print('PASS')
  PY
expected: exit 0; stdout PASS. Moving a migration outside its line scope still escalates an added DROP TABLE. Truncated R/C records, missing final NUL, empty status/path and invalid status all fail closed.
phase: bureau-lite · PR #101 review
owner: scripts/risk-tags.sh
