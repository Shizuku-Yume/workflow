#!/usr/bin/env python3
"""Lint the prose contracts and round-trip their examples through the real CLI.

Run from anywhere: python3 tests/skills_lint.py. Exit 1 when any check fails.
"""
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / 'bin/workflow'
CONVENTIONS = ROOT / 'CONVENTIONS.md'
FLOW_PATH = ROOT / 'skills/flow-break/SKILL.md'
SPIKE_PATH = ROOT / 'templates/project/.workflow/spike-tasks.md'
DECISION_PATH = ROOT / 'templates/project/.workflow/decisions.md'

# Things removed in 2.5 that the shipped prose must not mention (CHANGELOG is exempt).
REMOVED = ['workflow tasks', 'workflow deps', 'workflow decisions', 'workflow effort',
           'workflow debt', 'hotfix-review', 'mark-resolved', 'effort create',
           'effort complete', '.workflow/efforts', 'thinking.md', 'workflow-process']

passed = failed = 0


def label(path, line):
    try:
        return f'{path.relative_to(ROOT)}:{line}'
    except ValueError:
        return f'{path}:{line}'


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


def closes(fence, text):
    return re.fullmatch(r' {0,3}' + re.escape(fence[0]) + '{' + str(fence[1]) + r',}\s*', text)


# Only real Markdown headings count: examples inside fences and comments are not sections.
def headings(source):
    fence = None
    comment = False
    for number, text in enumerate(source, 1):
        if fence:
            if closes(fence, text):
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


def section_numbers():
    sections = set()
    for _, level, title in headings(lines(CONVENTIONS)):
        pattern = r'(\d+)\.\s+\S' if level == 2 else r'(\d+\.\d+)\s+\S' if level == 3 else None
        match = re.match(pattern, title) if pattern else None
        if match:
            sections.add(match[1])
    return sections


def section_text(path, number):
    """Body of the level-2 section `## <number>. ...`, or None when it is missing."""
    source = lines(path)
    found = list(headings(source))
    for index, (line, level, title) in enumerate(found):
        if level == 2 and re.match(re.escape(number) + r'\.\s', title):
            end = len(source)
            for later, later_level, _ in found[index + 1:]:
                if later_level <= 2:
                    end = later - 1
                    break
            return '\n'.join(source[line - 1:end])
    return None


def check_section_references():
    sections = section_numbers()
    prose = sorted(set((ROOT / 'skills').rglob('*.md')) | set((ROOT / 'templates').rglob('*.md')))
    prose += [CONVENTIONS, ROOT / 'README.md']
    initial = failed
    for path in prose:
        for number, text in enumerate(lines(path), 1):
            for match in re.finditer(r'§(\d+(?:\.\d+)*)', text):
                if match[1] not in sections:
                    fail(path, number, f'unresolved section reference {match[0]} in CONVENTIONS.md')
    if failed == initial:
        ok('all prose section references resolve to CONVENTIONS.md headings')


def check_skill_structure():
    for path in sorted((ROOT / 'skills').glob('*/SKILL.md')):
        initial = failed
        source = lines(path)
        found = list(headings(source))
        by_line = {number: (level, title) for number, level, title in found}
        # Numbered steps count per heading level; a higher-level heading restarts the count.
        expected = {}
        for number, level, title in found:
            for deeper in [key for key in expected if key > level]:
                del expected[deeper]
            step = re.match(r'(\d+)\.\s+', title) if level >= 2 else None
            if step:
                want = expected.get(level, 1)
                if int(step[1]) != want:
                    fail(path, number, f'numbered step must be {want}, found {step[1]}')
                expected[level] = int(step[1]) + 1
            following = number + 1
            while following <= len(source) and not source[following - 1].strip():
                following += 1
            if following > len(source) or (following in by_line and by_line[following][0] <= level):
                fail(path, number, f'empty section {title!r}: no content before the next same/higher heading')
        if failed == initial:
            ok(f'{path.relative_to(ROOT)} sequential steps and nonempty sections')


def removed_targets():
    targets = [CONVENTIONS, ROOT / 'STYLE.md', ROOT / 'README.md']
    targets += sorted((ROOT / 'skills').glob('*/SKILL.md'))
    targets += sorted(path for path in (ROOT / 'templates').rglob('*') if path.is_file())
    return [path for path in targets if path.is_file()]


def check_removed_mentions():
    initial = failed
    for path in removed_targets():
        try:
            source = lines(path)
        except UnicodeDecodeError:
            continue
        for number, text in enumerate(source, 1):
            for pattern in REMOVED:
                if pattern in text:
                    fail(path, number, f'mentions removed {pattern!r}')
    if failed == initial:
        ok('docs, skills and templates never mention removed commands or files')


def tree_entries(body):
    """Path tokens named in the CONVENTIONS §2 install tree, in order."""
    entries = []
    fence = False
    for text in body.splitlines():
        stripped = text.strip()
        if stripped.startswith('```'):
            fence = not fence
            continue
        if fence and stripped:
            entries.append(stripped.split()[0].rstrip('/'))
    return entries


def shipped_files():
    """Files `init` copies from the toolkit checkout."""
    project = ROOT / 'templates' / 'project'
    files = [path for path in sorted(project.rglob('*'))
             if path.is_file()
             and path.relative_to(project).parts[0] != '.agents'   # generic in the tree
             and path.name != 'CLAUDE.md']                         # the --claude adapter
    files += [path for path in sorted((ROOT / 'bin').glob('*')) if path.is_file()]
    return files


def check_file_tree():
    """Every file init installs is named in the §2 tree, and nothing else is."""
    body = section_text(CONVENTIONS, '2')
    initial = failed
    if body is None:
        fail(CONVENTIONS, 1, 'missing section "## 2." (file structure)')
        return
    entries = tree_entries(body)
    names = {entry.rsplit('/', 1)[-1] for entry in entries if '<' not in entry}
    for path in shipped_files():
        if path.parent.name != 'bin' and path.suffix not in ('.md', '.py'):
            continue
        if path.name not in names:
            fail(CONVENTIONS, 1,
                 f'CONVENTIONS section 2 tree does not list {path.name}, which init installs')
    shipped = {path.name for path in shipped_files()}
    shipped |= {'AGENTS.md', 'README.md', 'CHANGELOG.md', 'CONVENTIONS.md', 'STYLE.md'}
    for entry in entries:
        if '<' in entry or not entry.endswith(('.md', '.py')):
            continue
        if entry.rsplit('/', 1)[-1] not in shipped:
            fail(CONVENTIONS, 1,
                 f'CONVENTIONS section 2 tree lists {entry}, which the toolkit does not ship')
    if failed == initial:
        ok('CONVENTIONS section 2 file tree matches what init installs')


def check_skill_listing():
    skills = sorted(path.name for path in (ROOT / 'skills').iterdir() if path.is_dir())
    readme = (ROOT / 'README.md').read_text(encoding='utf-8')
    routing = section_text(CONVENTIONS, '5')
    initial = failed
    if routing is None:
        fail(CONVENTIONS, 1, 'missing section "## 5." (skill routing)')
        routing = ''
    for name in skills:
        pattern = re.compile(r'(?<![\w-])' + re.escape(name) + r'(?![\w-])')
        if not pattern.search(readme):
            fail(ROOT / 'README.md', 1, f'skill {name!r} is not mentioned')
        if routing and not pattern.search(routing):
            fail(CONVENTIONS, 1, f'skill {name!r} is not mentioned in §5')
    if failed == initial:
        ok(f'all {len(skills)} skills appear in README.md and CONVENTIONS.md §5')


# Extract the live fenced blocks, retaining original line numbers for diagnostics.
def example(path, start):
    blocks = []
    current = None
    fence = None
    for number, text in enumerate(lines(path), 1):
        if fence:
            if closes(fence, text):
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


FIELD = re.compile(r'^((?:-\s+)?(?:\*\*)?[A-Za-z][A-Za-z ]*:(?:\*\*)?\s*)(.*)$')


def variants(path, block, replacements):
    """Every concrete file the example allows: placeholders filled, `a | b` alternatives expanded."""
    choices = []
    for number, text in block:
        prefix = ''
        value = text
        metadata = FIELD.match(text)
        if metadata:
            prefix, value = metadata.groups()
        blocker = bool(metadata) and 'Blocked by:' in prefix
        concrete = []
        for alternative in value.split(' | '):
            valid = True
            context = replacements.copy()
            if blocker:
                context.update(NN='02', effort='demo2')

            def replace(match):
                nonlocal valid
                token = match[1]
                if blocker and token == 'NN' and alternative[:match.start()].endswith('<effort>/'):
                    return '01'
                if token not in context:
                    fail(path, number, f'unsupported example placeholder {match[0]}')
                    valid = False
                    return match[0]
                return context[token]

            expanded = re.sub(r'<([^<>\n]+)>', replace, alternative)
            if not valid:
                return []
            concrete.append((number, prefix + expanded))
        choices.append(concrete)
    return list(itertools.product(*choices))


def run(repo, env, *args):
    return subprocess.run(args, cwd=repo, env=env, stdin=subprocess.DEVNULL,
                          capture_output=True, text=True)


def command(repo, env, path, line, description, *args):
    result = run(repo, env, *args)
    if result.returncode:
        fail(path, line, description, result)
        return None
    return result


REFERENCE_TASK = '''# {number}: Reference target

**Effort:** {effort}
**Task type:** feature
**Base commit:** {base}

**Delivers:** Reference target exists.

**Blocked by:** None
**Files:** README.md

**Read first:** README.md

**Check:** `git status --short` → working tree status is displayed

- [ ] Reference target exists
'''


def roundtrips(tmp):
    flow = example(FLOW_PATH, re.compile(r'^# <NN>:'))
    spike = example(SPIKE_PATH, re.compile(r'^#\s*03:'))
    decision = example(DECISION_PATH, re.compile(r'^## \d{4}-\d{2}-\d{2} - '))
    if flow is None or spike is None or decision is None:
        return
    repo = tmp / 'project'
    repo.mkdir()
    env = {key: value for key, value in os.environ.items()
           if key not in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE')}
    env['GIT_CEILING_DIRECTORIES'] = str(tmp)
    env['NO_COLOR'] = '1'
    location = flow[0][0]
    for args in [('git', 'init', '-q'), ('git', 'config', 'user.name', 'Skills lint'),
                 ('git', 'config', 'user.email', 'skills-lint@example.com')]:
        if command(repo, env, FLOW_PATH, location, 'cannot initialize example repository', *args) is None:
            return
    (repo / 'README.md').write_text('Example repository for prose roundtrips.\n', encoding='utf-8')
    for args in [('git', 'add', 'README.md'),
                 ('git', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Initial commit'),
                 (str(WORKFLOW), 'init')]:
        if command(repo, env, FLOW_PATH, location, 'cannot initialize workflow example', *args) is None:
            return
    base = command(repo, env, FLOW_PATH, location, 'cannot resolve example base commit', 'git', 'rev-parse', 'HEAD')
    if base is None:
        return
    base = base.stdout.strip()
    replacements = {
        'NN': '01', 'Title': 'Deliver observable behavior', 'effort': 'demo',
        'commit-sha': base, 'observable behavior': 'README documents the demonstrated behavior',
        'where work happens': 'README.md', 'spec sections, glossary terms, files': 'README.md',
        'command': 'git status --short', 'result that means it works': 'working tree status is displayed',
        'acceptance point': 'The demonstrated behavior is documented', 'check IDs': 'W1',
        'Filled in after spike': 'Spike findings have been recorded below.',
    }
    tasks = repo / '.workflow/tasks'
    # Blocker targets for the `Blocked by:` alternatives: demo/02 and demo2/01.
    for effort, number in [('demo', '02'), ('demo2', '01')]:
        (tasks / effort).mkdir(parents=True, exist_ok=True)
        (tasks / effort / f'{number}-reference.md').write_text(
            REFERENCE_TASK.format(number=number, effort=effort, base=base), encoding='utf-8')

    # The decision example is real entry content: validate must find nothing wrong in the log.
    concrete = variants(DECISION_PATH, decision, replacements)
    for index, variant in enumerate(concrete, 1):
        (repo / '.workflow/decisions.md').write_text(
            '# Decisions\n\n## Entries\n\n' + '\n'.join(text for _, text in variant) + '\n', encoding='utf-8')
        where = f'{label(DECISION_PATH, decision[0][0])} decision example variant {index}'
        result = run(repo, env, str(WORKFLOW), 'validate', '--format', 'json')
        try:
            report = json.loads(result.stdout)
            if not isinstance(report, dict):
                raise ValueError(f'expected a JSON object, received {report!r}')
            problems = [issue for issue in report.get('issues', [])
                        if str(issue.get('file', '')).endswith('decisions.md')]
            if result.returncode not in (0, 1) or report.get('errors') != 0 or problems:
                raise ValueError(f'expected zero errors and no decisions.md issues, received {report!r}')
        except ValueError as error:
            fail(DECISION_PATH, decision[0][0], f'decision example variant {index}: {error}', result)
        else:
            ok(f'{where}: no validate issues')

    for path, block, number in [(FLOW_PATH, flow, '01'), (SPIKE_PATH, spike, '03')]:
        for index, variant in enumerate(variants(path, block, replacements), 1):
            effort = 'demo'
            for _, text in variant:
                metadata = FIELD.match(text)
                if metadata and 'Effort:' in metadata[1]:
                    effort = metadata[2].strip()
            directory = tasks / effort
            created = not directory.exists()
            directory.mkdir(parents=True, exist_ok=True)
            candidate = directory / f'{number}-template-example.md'
            candidate.write_text('\n'.join(text for _, text in variant) + '\n', encoding='utf-8')
            try:
                result = command(repo, env, path, block[0][0], f'task example variant {index} roundtrip failed',
                                 str(WORKFLOW), 'validate')
                if result is not None:
                    ok(f'{label(path, block[0][0])} task example variant {index} validates')
            finally:
                candidate.unlink()
                if created:
                    shutil.rmtree(directory, ignore_errors=True)


def main():
    for dependency in ('git',):
        if shutil.which(dependency) is None:
            fail(Path(__file__).resolve(), 1, f'missing test dependency: {dependency}')
            return 1
    check_section_references()
    check_skill_structure()
    check_removed_mentions()
    check_file_tree()
    with tempfile.TemporaryDirectory() as tmp:
        roundtrips(Path(tmp).resolve())
    print(f'\n{passed} passed; {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
