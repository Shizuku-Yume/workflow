#!/usr/bin/env bash
# Lint prose contracts and round-trip the examples through the real CLI.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for dependency in python3 git; do
  command -v "$dependency" >/dev/null || {
    printf 'FAIL: tests/skills-lint.sh:1: missing test dependency: %s\n' "$dependency" >&2
    exit 1
  }
done
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
export GIT_CEILING_DIRECTORIES="$TMP"
python3 - "$ROOT" "$TMP" <<'PY'
import itertools
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1])
repo = Path(sys.argv[2]) / 'project'
workflow = root / 'bin/workflow'
passed = failed = 0


def label(path, line):
    return f'{path.relative_to(root)}:{line}'


def fail(path, line, issue, result=None):
    global failed
    failed += 1
    print(f'FAIL: {label(path, line)}: {issue}', file=sys.stderr)
    if result is not None:
        print(f'  exit status: {result.returncode}\n--- stdout ---', file=sys.stderr)
        print(result.stdout, end='' if result.stdout.endswith('\n') else '\n', file=sys.stderr)
        print('--- stderr ---', file=sys.stderr)
        print(result.stderr, end='' if result.stderr.endswith('\n') else '\n', file=sys.stderr)
        print('--- end ---', file=sys.stderr)


def ok(issue):
    global passed
    passed += 1
    print(f'PASS: {issue}')


def lines(path):
    return path.read_text(encoding='utf-8').splitlines()


# Only real Markdown headings count: examples inside fences are not sections.
def headings(source):
    fence = None
    comment = False
    for number, text in enumerate(source, 1):
        if fence:
            if re.fullmatch(r' {0,3}' + re.escape(fence[0]) + '{' + str(fence[1]) + r',}\s*', text):
                fence = None
            continue
        if comment:
            if '-->' not in text:
                continue
            text = text.split('-->', 1)[1]
            comment = False
        while '<!--' in text:
            before, after = text.split('<!--', 1)
            if '-->' not in after:
                text = before
                comment = True
                break
            text = before + after.split('-->', 1)[1]
        opening = re.match(r' {0,3}(`{3,}|~{3,})', text)
        if opening:
            fence = (opening[1][0], len(opening[1]))
            continue
        heading = re.match(r' {0,3}(#{1,6})\s+(.+?)\s*#*\s*$', text)
        if heading:
            yield number, len(heading[1]), heading[2]


conventions = root / 'CONVENTIONS.md'
sections = set()
for number, level, title in headings(lines(conventions)):
    pattern = r'(\d+)\.\s+\S' if level == 2 else r'(\d+\.\d+)\s+\S' if level == 3 else None
    match = re.match(pattern, title) if pattern else None
    if match:
        sections.add(match[1])

prose = sorted(set((root / 'skills').rglob('*.md')) | set((root / 'templates').rglob('*.md')))
prose += [conventions, root / 'README.md']
initial_failures = failed
for path in prose:
    for number, text in enumerate(lines(path), 1):
        for match in re.finditer(r'§(\d+(?:\.\d+)*)', text):
            if match[1] not in sections:
                fail(path, number, f'unresolved section reference {match[0]} in CONVENTIONS.md')
if failed == initial_failures:
    ok('all prose section references resolve to CONVENTIONS.md headings')

for path in sorted((root / 'skills').glob('*/SKILL.md')):
    initial_failures = failed
    source = lines(path)
    found = list(headings(source))
    by_line = {number: (level, title) for number, level, title in found}
    expected = 1
    for number, level, title in found:
        step = re.match(r'(\d+)\.\s+', title) if level == 2 else None
        if step:
            if int(step[1]) != expected:
                fail(path, number, f'numbered step must be {expected}, found {step[1]}')
            expected += 1
        following = number + 1
        while following <= len(source) and not source[following - 1].strip():
            following += 1
        if following in by_line and by_line[following][0] <= level:
            fail(path, number, f'empty section {title!r}: next content is same/higher heading at line {following}')
    if failed == initial_failures:
        ok(f'{path.relative_to(root)} sequential steps and nonempty sections')


# Extract the live fenced blocks, retaining original line numbers for diagnostics.
def example(path, start):
    blocks = []
    current = None
    fence = None
    for number, text in enumerate(lines(path), 1):
        if fence:
            if re.fullmatch(r' {0,3}' + re.escape(fence[0]) + '{' + str(fence[1]) + r',}\s*', text):
                if current and start.match(current[0][1]):
                    blocks.append(current)
                current = None
                fence = None
            elif current is not None:
                current.append((number, text))
            continue
        opening = re.fullmatch(r' {0,3}(`{3,}|~{3,})\s*([^\s]*)\s*', text)
        if opening:
            fence = (opening[1][0], len(opening[1]))
            current = [] if opening[2] == 'markdown' else None
    if len(blocks) != 1:
        fail(path, 1, f'expected exactly one fenced markdown example beginning {start.pattern!r}, found {len(blocks)}')
        return None
    return blocks[0]


flow_path = root / 'skills/flow-break/SKILL.md'
spike_path = root / 'templates/project/.workflow/spike-tasks.md'
decision_path = root / 'templates/project/.workflow/decisions.md'
flow = example(flow_path, re.compile(r'^# <NN>:'))
spike = example(spike_path, re.compile(r'^#\s*03:'))
decision = example(decision_path, re.compile(r'^## \d{4}-\d{2}-\d{2} - '))


def command(path, line, description, *args):
    result = subprocess.run(args, cwd=repo, stdin=subprocess.DEVNULL,
                            capture_output=True, text=True)
    if result.returncode:
        fail(path, line, description, result)
        return None
    return result


def roundtrips():
    if flow is None or spike is None or decision is None:
        return
    repo.mkdir()
    location = flow[0][0]
    for args in [('git', 'init', '-q'), ('git', 'config', 'user.name', 'Skills lint'),
                 ('git', 'config', 'user.email', 'skills-lint@example.com')]:
        if command(flow_path, location, 'cannot initialize example repository', *args) is None:
            return
    (repo / 'README.md').write_text('Example repository for prose roundtrips.\n', encoding='utf-8')
    for args in [('git', 'add', 'README.md'), ('git', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Initial commit'),
                 (str(workflow), 'init')]:
        if command(flow_path, location, 'cannot initialize workflow example', *args) is None:
            return
    base = command(flow_path, location, 'cannot resolve example base commit', 'git', 'rev-parse', 'HEAD')
    if base is None:
        return
    replacements = {
        'NN': '01', 'Title': 'Deliver observable behavior', 'effort': 'demo',
        'commit-sha': base.stdout.strip(), 'observable behavior': 'README documents the demonstrated behavior',
        'where work happens': 'README.md', 'spec sections, glossary terms, files': 'README.md',
        'command': 'git status --short', 'result that means it works': 'working tree status is displayed',
        'acceptance point': 'The demonstrated behavior is documented',
        'Filled in after spike': 'Spike findings have been recorded below.',
    }
    field = re.compile(r'^((?:-\s+)?(?:\*\*)?[A-Za-z][A-Za-z ]*:(?:\*\*)?\s*)(.*)$')

    def variants(path, block):
        choices = []
        for number, text in block:
            prefix = ''
            value = text
            metadata = field.match(text)
            if metadata:
                prefix, value = metadata.groups()
            concrete = []
            for alternative in value.split(' | '):
                valid = True
                context = replacements.copy()
                if metadata and 'Blocked by:' in prefix:
                    context.update(NN='02', effort='demo2')

                def replace(match):
                    nonlocal valid
                    token = match[1]
                    if (metadata and 'Blocked by:' in prefix and token == 'NN'
                            and alternative[:match.start()].endswith('<effort>/')):
                        return '01'
                    if token not in context:
                        fail(path, number, f'unsupported example placeholder {match[0]}')
                        valid = False
                        return match[0]
                    return context[token]

                expanded = re.sub(r'<([^<>\n]+)>', replace, alternative)
                if not valid:
                    return
                concrete.append((number, prefix + expanded))
            choices.append(concrete)
        yield from itertools.product(*choices)

    efforts = set()

    def effort(path, line, slug):
        if slug in efforts:
            return True
        if command(path, line, f'cannot create example effort {slug!r}', str(workflow), 'effort', 'create', slug) is None:
            return False
        efforts.add(slug)
        return True

    for slug, number in [('demo', '02'), ('demo2', '01')]:
        if not effort(flow_path, location, slug):
            return
        (repo / f'.workflow/tasks/{number}-{slug}-reference.md').write_text(
            f'# {number}: Reference target\n\n**Effort:** {slug}\n**Blocked by:** None\n'
            '**Check:** Reference target exists.\n', encoding='utf-8')

    # The example is real entry content, not an ignored fence in the installed log.
    concrete_decisions = list(variants(decision_path, decision))
    if not concrete_decisions:
        return
    for index, variant in enumerate(concrete_decisions, 1):
        (repo / '.workflow/decisions.md').write_text(
            '# Decisions\n\n## Entries\n\n' + '\n'.join(text for _, text in variant) + '\n', encoding='utf-8')
        result = command(decision_path, decision[0][0], f'decision example variant {index} roundtrip failed',
                         str(workflow), 'decisions', 'validate', '--format', 'json')
        if result is None:
            continue
        try:
            report = json.loads(result.stdout)
            if report.get('valid') is not True or report.get('errors') != 0 or report.get('decisions') != 1:
                raise ValueError(f'expected one decision and zero malformed entries, received {report!r}')
        except (ValueError, AttributeError) as error:
            fail(decision_path, decision[0][0], f'decision example variant {index}: {error}', result)
        else:
            ok(f'{label(decision_path, decision[0][0])} decision example variant {index}: zero malformed entries')

    for path, block, number in [(flow_path, flow, '01'), (spike_path, spike, '03')]:
        for index, variant in enumerate(variants(path, block), 1):
            for line, text in variant:
                metadata = field.match(text)
                if metadata and 'Effort:' in metadata[1]:
                    if not effort(path, line, metadata[2].strip()):
                        return
            candidate = repo / f'.workflow/tasks/{number}-template-example.md'
            candidate.write_text('\n'.join(text for _, text in variant) + '\n', encoding='utf-8')
            try:
                result = command(path, block[0][0], f'task example variant {index} roundtrip failed',
                                 str(workflow), 'validate')
                if result is not None:
                    ok(f'{label(path, block[0][0])} task example variant {index} validates')
            finally:
                candidate.unlink()


roundtrips()
print(f'\n{passed} passed; {failed} failed')
sys.exit(1 if failed else 0)
PY
