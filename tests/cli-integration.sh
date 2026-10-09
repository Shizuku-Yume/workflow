#!/usr/bin/env bash
# Cross-command contracts, shell completions and 120-task performance checks.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 - "$KIT" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

KIT = Path(sys.argv[1])
COMMANDS = ('tasks', 'deps', 'decisions', 'effort', 'debt', 'hotfix-review', 'validate', 'next')
MAX_SECONDS = float(os.environ.get('WORKFLOW_PERF_MAX_SECONDS', '30'))

class IntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='workflow-cli-integration-')
        self.root = Path(self.temp.name)
        subprocess.run([str(KIT / 'tests/fixtures/large-project.sh'), str(self.root)], check=True)

    def tearDown(self):
        self.temp.cleanup()

    def cli(self, command, *flags, cwd=None, wrapper=False):
        args = [str(KIT / 'bin' / ('workflow' if wrapper else 'workflow-' + command))]
        if wrapper:
            args.append(command)
        return subprocess.run(args + list(flags), cwd=cwd or self.root,
                              text=True, capture_output=True, timeout=MAX_SECONDS)

    def test_shell_syntax_and_strict_mode(self):
        scripts = [KIT / 'bin' / ('workflow-' + command) for command in COMMANDS]
        scripts.append(KIT / 'completions/workflow.bash')
        for script in scripts:
            with self.subTest(script=script.name):
                result = subprocess.run(['bash', '-n', str(script)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                if script.parent.name == 'bin':
                    self.assertIn('set -euo pipefail', script.read_text())
        if shutil.which('zsh'):
            result = subprocess.run(['zsh', '-n', str(KIT / 'completions/_workflow')],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_help_examples_and_shared_plain_output(self):
        for command in COMMANDS:
            with self.subTest(command=command):
                result = self.cli(command, '--help', wrapper=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue('Examples:' in result.stdout or 'Lifecycle examples:' in result.stdout)
                marker = 'Examples:' if 'Examples:' in result.stdout else 'Lifecycle examples:'
                examples = result.stdout.split(marker, 1)[1]
                self.assertGreaterEqual(len(re.findall(r'^\s+workflow\s+', examples, re.M)), 2)
                self.assertIn('--no-color', result.stdout)
                self.assertNotIn('\x1b', result.stdout)

    def test_usage_errors_are_stderr_with_exit_two(self):
        for command in COMMANDS:
            with self.subTest(command=command):
                result = self.cli(command, '--invalid-cli-integration-option')
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn('Error:', result.stderr)
                self.assertNotIn('Traceback', result.stderr)

    def test_non_git_fallback_all_commands(self):
        for command in COMMANDS:
            with self.subTest(command=command):
                result = self.cli(command, '--no-color')
                self.assertIn(result.returncode, (0, 1) if command == 'validate' else (0,), result.stderr)
                self.assertNotIn('Traceback', result.stderr)
                self.assertNotIn('\x1b', result.stdout)
        result = self.cli('tasks', '--format', 'json')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)), 120)

    def test_git_subdirectory_root_discovery(self):
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        nested = self.root / 'src' / 'deep'
        nested.mkdir(parents=True)
        for command in COMMANDS:
            with self.subTest(command=command):
                root = self.cli(command, '--no-color')
                child = self.cli(command, '--no-color', cwd=nested, wrapper=True)
                self.assertEqual(child.returncode, root.returncode, child.stderr)
                self.assertEqual(child.stdout, root.stdout)

    def test_missing_workflow_is_controlled(self):
        empty = self.root / 'empty'
        empty.mkdir()
        for command in COMMANDS:
            with self.subTest(command=command):
                result = self.cli(command, '--no-color', cwd=empty)
                self.assertIn(result.returncode, (0, 1, 2))
                self.assertNotIn('Traceback', result.stderr)
                self.assertNotIn('unbound variable', result.stderr)
                self.assertNotIn('syntax error', result.stderr)
                if result.returncode:
                    self.assertIn('Error:', result.stderr)

    def test_large_project_performance_and_json(self):
        cases = [('tasks', ('--format', 'json')), ('deps', ('--format', 'text')),
                 ('decisions', ('--format', 'json')), ('hotfix-review', ('--format', 'json')),
                 ('next', ('--format', 'json')), ('effort', ('list', '--no-color')),
                 ('debt', ('list', '--format', 'json')), ('validate', ('--format', 'json'))]
        for command, flags in cases:
            with self.subTest(command=command):
                start = time.monotonic()
                result = self.cli(command, *flags)
                elapsed = time.monotonic() - start
                self.assertLess(elapsed, MAX_SECONDS)
                allowed = (0, 1) if command == 'validate' else (0,)
                self.assertIn(result.returncode, allowed, result.stderr)
                if 'json' in flags:
                    data = json.loads(result.stdout)
                    if command == 'tasks':
                        self.assertEqual(len(data), 120)
                    if command == 'decisions':
                        self.assertEqual(len(data), 120)
                print(f'performance: {command}: {elapsed:.3f}s (120 tasks, 120 decisions)', flush=True)

    def test_bash_completion_flags_and_formats(self):
        script = '''
set -euo pipefail
source "$1/completions/workflow.bash"
COMP_WORDS=(workflow tasks --); COMP_CWORD=2; _workflow_complete
[[ " ${COMPREPLY[*]} " == *" --help "* ]]
[[ " ${COMPREPLY[*]} " == *" --format "* ]]
COMP_WORDS=(workflow-tasks --format j); COMP_CWORD=2; _workflow_complete
[[ " ${COMPREPLY[*]} " == *" json "* ]]
COMP_WORDS=(workflow deps --format m); COMP_CWORD=3; _workflow_complete
[[ " ${COMPREPLY[*]} " == *" mermaid "* ]]
'''
        result = subprocess.run(['bash', '-c', script, 'completion-test', str(KIT)],
                                capture_output=True, text=True, cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_zsh_completion_loads(self):
        if not shutil.which('zsh'):
            self.skipTest('zsh is not installed; native completion check unavailable')
        script = '''
autoload -Uz compinit
compinit -D
source "$1/completions/_workflow"
(( $+functions[_workflow] )) || exit 1
[[ ${_comps[workflow]} == _workflow ]] || exit 1
[[ ${_comps[workflow-tasks]} == _workflow ]] || exit 1
'''
        result = subprocess.run(['zsh', '-f', '-c', script, 'completion-test', str(KIT)],
                                capture_output=True, text=True, cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)

unittest.main(argv=[sys.argv[0]], verbosity=2)
PY
