#!/usr/bin/env python3
"""workflow-core.py - `validate`, `next` and `pulse` for the workflow toolkit.

Called by bin/workflow as `python3 workflow-core.py validate|next|pulse ...`.
Python 3.8+, standard library only. Reads task files under .workflow/tasks/
and .workflow/done/, specs under .workflow/specs/, and .workflow/decisions.md.

Metadata grammar (CONVENTIONS §2): fields are `Name: value` lines, plain,
bulleted (`- Name: value`) or bolded (`**Name:** value`); fenced code blocks
and HTML comments are ignored; indented or bulleted lines continue the
previous field (`Blocked by` joins with ", ", other fields with a space);
blank lines, headings, checklists and new fields end a continuation.
`## Goal` and `## Check` headings start sections whose lines join the same
way. The first occurrence of a field wins; later ones are duplicates.
"""

import json
import os
import re
import subprocess
import sys

VERSION = "2.8.0"

KNOWN_FIELDS = {
    "task", "effort", "task type", "base commit", "base branch", "delivers", "blocked by",
    "files", "read first", "check", "covers", "done when", "priority", "status",
    "started", "finished", "question", "time box", "goal", "scope", "spec",
    "dependencies", "notes", "integration branch",
}
FIELD_ALIASES = {"base": "base commit", "type": "task type"}
TASK_TYPES = ("feature", "bugfix", "spike", "refactor")
PRIORITY_RANK = {"critical": 0, "urgent": 0, "high": 1, "normal": 2, "low": 3}
SPEC_STATUSES = ("proposed", "in progress", "done")
TASK_STATUSES = ("active", "paused", "blocked")
FINISHED_STATUSES = ("done", "completed", "archived")
DECISION_FIELDS = ("Decided", "Instead of", "Because", "Mine", "Revisit when")

SLUG_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TASK_FILE_RE = re.compile(r"^([0-9]+)-.+\.md$")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
TITLE_RE = re.compile(r"^#\s+([0-9]+):\s*(.*)$")
H2_RE = re.compile(r"^##\s+(.*)$")
CHECKLIST_RE = re.compile(r"^[-*]\s+\[[\sxX]\]")
BULLET_RE = re.compile(r"^[-*]\s+(.*)$")
BOLD_FIELD_RE = re.compile(r"^\*\*([^*]+)\*\*\s*:?\s*(.*)$")
PLAIN_FIELD_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_. -]*):\s*(.*)$")
NONE_RE = re.compile(r"^none(\s*,\s*can\s+start\s+now)?$")
QUALIFIED_REF_RE = re.compile(r"^([a-z0-9]+(-[a-z0-9]+)*)/([0-9]+)$")
BARE_REF_RE = re.compile(r"^([0-9]+)$")
SPEC_CHECK_RE = re.compile(r"^[-*]\s+\*\*([A-Za-z][A-Za-z0-9_-]*[0-9])\.\*\*")
UNTICKED_RE = re.compile(r"^[-*]\s+\[ \]\s*(.*)$")
ACCEPTED_RE = re.compile(r"^\s*(?:[-*]\s+)?(?:\*\*)?Accepted:(?:\*\*)?\s*\S")
REOPENED_RE = re.compile(r"^\s*##\s+Reopened\s*:?\s*$", re.IGNORECASE)


# ---------------------------------------------------------------- helpers

def project_root():
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             universal_newlines=True, check=False)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except OSError:
        pass
    return os.getcwd()


def read_lines(path):
    """Lines of a file with the newline and one trailing CR removed."""
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as fh:
        text = fh.read()
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return [line[:-1] if line.endswith("\r") else line for line in lines]


def norm_number(value):
    stripped = value.lstrip("0")
    return stripped if stripped else "0"


def task_ref(effort, number):
    return "%s/%02d" % (effort, int(number))


def task_files(directory):
    """Every Markdown file under a task directory, at any depth, sorted."""
    found = []
    if not os.path.isdir(directory):
        return found
    for base, dirs, files in os.walk(directory, followlinks=False):
        for name in files:
            if name.endswith(".md"):
                found.append(os.path.join(base, name))
        for name in dirs:
            full = os.path.join(base, name)
            if os.path.islink(full) and name.endswith(".md") and os.path.isfile(full):
                found.append(full)
    return sorted(found, key=lambda p: p.encode("utf-8", "surrogateescape"))


def dir_effort(base, path):
    rel = os.path.relpath(path, base).replace(os.sep, "/")
    return rel.split("/", 1)[0] if "/" in rel else ""


def strip_comments(line, in_comment):
    """Remove HTML comment text; returns (line, in_comment)."""
    while True:
        if in_comment:
            if "-->" in line:
                line = line.split("-->", 1)[1]
                in_comment = False
            else:
                return "", True
        elif "<!--" in line:
            before, after = line.split("<!--", 1)
            if "-->" in after:
                line = before + after.split("-->", 1)[1]
            else:
                return before, True
        else:
            return line, False


def split_text(text):
    """Lines of git output, split like read_lines (no trailing newline, no CR)."""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return [line[:-1] if line.endswith("\r") else line for line in lines]


def git_result(root, *args):
    """(ok, stdout) of a git command run in root."""
    try:
        proc = subprocess.run(["git", "-C", root] + list(args), stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, universal_newlines=True)
    except OSError:
        return False, ""
    return proc.returncode == 0, proc.stdout


def visible_lines(lines):
    """(lineno, line) outside fenced code blocks and HTML comments."""
    shown = []
    in_fence = in_comment = False
    for lineno, line in enumerate(lines, 1):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        line, in_comment = strip_comments(line, in_comment)
        shown.append((lineno, line))
    return shown


def section_has_content(shown, heading):
    """True when a `## heading` section has at least one non-heading text line."""
    inside = False
    for _, line in shown:
        text = line.strip()
        m = H2_RE.match(text)
        if m:
            inside = m.group(1).strip().rstrip(":").strip().lower() == heading
            continue
        if text.startswith("#"):
            continue
        if inside and text:
            return True
    return False


class Meta(object):
    """Fields of one task or spec file."""

    def __init__(self):
        self.field = {}
        self.line = {}
        self.dups = []          # (line, name)
        self.title = ""
        self.title_number = ""

    def get(self, name, default=""):
        return self.field.get(name, default)


def read_fields(path, lines=None):
    meta = Meta()
    if lines is None:
        lines = read_lines(path)
    in_fence = in_comment = False
    current = kind = None
    section_content = False
    title_seen = False
    sections = {}
    for lineno, line in enumerate(lines, 1):
        line, in_comment = strip_comments(line, in_comment)
        if FENCE_RE.match(line):
            in_fence = not in_fence
            current = kind = None
            continue
        if in_fence:
            continue
        rawline = line
        line = line.strip()
        if not line:
            if kind and (kind == "field" or section_content):
                current = kind = None
            continue
        m = TITLE_RE.match(line)
        if m:
            if not title_seen:
                title_seen = True
                meta.title = m.group(2).strip()
                meta.title_number = norm_number(m.group(1))
            current = kind = None
            continue
        m = H2_RE.match(line)
        if m:
            heading = m.group(1).lower()
            if heading.endswith(":"):
                heading = heading[:-1]
            heading = heading.strip()
            current = kind = None
            if heading in ("goal", "check"):
                current, kind, section_content = heading, "section", False
            continue
        if line.startswith("#") or CHECKLIST_RE.match(line):
            current = kind = None
            continue
        clean = line
        m = BULLET_RE.match(clean)
        if m:
            clean = m.group(1)
        m = BOLD_FIELD_RE.match(clean) or PLAIN_FIELD_RE.match(clean)
        if m:
            key = m.group(1).lower()
            if key.endswith(":"):
                key = key[:-1]
            key = FIELD_ALIASES.get(key.strip(), key.strip())
            if key in KNOWN_FIELDS:
                if key not in meta.line:
                    meta.field[key] = m.group(2).strip()
                    meta.line[key] = lineno
                    current, kind = key, "field"
                else:
                    meta.dups.append((lineno, key))
                    current, kind = None, "dup"
                continue
            current = kind = None
            continue
        if kind == "section":
            if current not in meta.line:
                old = meta.field.get(current, "")
                meta.field[current] = (old + " " + line) if old else line
            else:
                old = sections.get(current, "")
                sections[current] = (old + " " + line) if old else line
            section_content = True
            continue
        if kind in ("field", "dup") and (rawline[:1].isspace() or BULLET_RE.match(line)):
            if kind == "field":
                old = meta.field.get(current, "")
                sep = ", " if current == "blocked by" else " "
                meta.field[current] = (old + sep + clean) if old else clean
            continue
        current = kind = None
    if not meta.field.get("check") and sections.get("check"):
        meta.field["check"] = sections["check"]
    return meta


class BlockerError(Exception):
    def __init__(self, token, trailing=False):
        Exception.__init__(self, token)
        self.token = token
        self.trailing = trailing


def parse_blockers(raw):
    """[(normalized ref, raw token)] for a Blocked by value; raises BlockerError."""
    raw = raw.strip()
    if NONE_RE.match(raw.lower()):
        return []
    if not raw:
        raise BlockerError("")
    if raw.endswith(","):
        raise BlockerError("", trailing=True)
    refs = []
    for token in raw.split(","):
        token = token.strip()
        m = QUALIFIED_REF_RE.match(token)
        if m:
            refs.append((m.group(1) + "/" + norm_number(m.group(3)), token))
            continue
        m = BARE_REF_RE.match(token)
        if m:
            refs.append((norm_number(m.group(1)), token))
            continue
        raise BlockerError(token)
    return refs


def resolve_ref(ref, effort):
    if "/" in ref:
        ref_effort, number = ref.split("/", 1)
        return task_ref(ref_effort, number)
    return task_ref(effort, ref)


def colors_enabled(no_color_flag):
    return (not no_color_flag and not os.environ.get("NO_COLOR")
            and sys.stdout.isatty())


def usage_error(message, usage):
    sys.stderr.write("Error: %s\n" % message)
    if usage:
        sys.stderr.write(usage)
    return 2


# Options dropped in 2.5, answered like the removed commands in bin/workflow.
REMOVED_FLAGS = {
    "--fix": "validate --fix was removed in 2.5: CRLF line endings are read like LF, so there is nothing to repair",
    "--interactive": "next --interactive was removed in 2.5: run 'workflow next' and start a task with flow-implement <effort>/<NN>",
}


def parse_common(args, usage, allowed):
    """Parse shared CLI flags; returns (options, exit code or None)."""
    opts = {"format": "text", "no_color": False, "strict": False,
            "all": False, "quiet_idle": False, "effort": None}
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in ("-h", "--help"):
            sys.stdout.write(usage)
            return opts, 0
        if arg == "--no-color":
            opts["no_color"] = True
        elif arg == "--strict" and "strict" in allowed:
            opts["strict"] = True
        elif arg == "--all" and "all" in allowed:
            opts["all"] = True
        elif arg == "--quiet-idle" and "quiet_idle" in allowed:
            opts["quiet_idle"] = True
        elif arg == "--effort" and "effort" in allowed:
            if i + 1 >= len(args) or not args[i + 1]:
                return opts, usage_error("--effort requires an effort slug", "")
            opts["effort"] = args[i + 1]
            i += 1
        elif arg.startswith("--effort=") and "effort" in allowed:
            opts["effort"] = arg[len("--effort="):]
            if not opts["effort"]:
                return opts, usage_error("--effort requires an effort slug", "")
        elif arg == "--format":
            if i + 1 >= len(args):
                return opts, usage_error("--format requires text or json", "")
            opts["format"] = args[i + 1]
            i += 1
        elif arg.startswith("--format="):
            opts["format"] = arg[len("--format="):]
        elif arg in REMOVED_FLAGS:
            return opts, usage_error(REMOVED_FLAGS[arg], "")
        else:
            return opts, usage_error("unknown option: %s" % arg, usage)
        i += 1
    if opts["effort"] is not None and not SLUG_RE.match(opts["effort"]):
        return opts, usage_error("invalid effort slug: %s" % opts["effort"], "")
    if opts["format"] not in ("text", "json"):
        return opts, usage_error("invalid format: %s (use text or json)" % opts["format"], "")
    return opts, None


# --------------------------------------------------------------- validate

VALIDATE_USAGE = """workflow validate - validate task files and the decision log

Usage: workflow validate [--strict] [--format text|json] [--no-color]
Checks required Task, Effort, Check and Blocked by fields; effort slugs;
that a task in tasks/<effort>/ says the same Effort; that the heading number
matches the filename; Status and Priority values; blockers; Base commit refs;
task-number collisions within efforts; dependency cycles; Covers IDs no spec
check defines; and decision format. Checks active and completed task files;
problems in completed files warn instead of failing.

  --strict     Treat warnings as errors
  --format F   Output text (default) or JSON
  --no-color   Disable color output
  --help       Show help

Exit: 0 = valid, 1 = warnings, 2 = errors (including usage errors).
"""


class Validator(object):
    def __init__(self, root):
        self.root = root
        self.wf = os.path.join(root, ".workflow")
        self.issues = []
        self.errors = self.warnings = 0
        self.files = []
        self.meta = {}
        self.number = {}
        self.effort = {}
        self.dir_effort = {}
        self.index = {}
        self.active = set()
        self.tasks_dir = os.path.join(self.wf, "tasks") + os.sep
        self.done_dir = os.path.join(self.wf, "done") + os.sep
        self.lines_cache = {}

    def rel(self, path):
        rel = os.path.relpath(path, self.root)
        return rel.replace(os.sep, "/")

    def issue(self, severity, path, line, message, suggestion):
        if severity == "ERROR":
            self.errors += 1
        else:
            self.warnings += 1
        self.issues.append({"severity": severity, "file": self.rel(path),
                            "line": int(line or 1), "message": message,
                            "suggestion": suggestion})

    def sev(self, path):
        return "WARNING" if path.startswith(self.done_dir) else "ERROR"

    def line_of(self, path, key):
        return self.meta[path].line.get(key, 1)

    def run(self):
        if not os.path.isdir(self.wf):
            self.issue("ERROR", self.wf, 1, "missing .workflow directory", "Run: workflow init")
            return
        if not os.path.isdir(os.path.join(self.wf, "tasks")):
            self.issue("WARNING", os.path.join(self.wf, "tasks"), 1,
                       "tasks directory is missing", "Run: workflow init")
        self.collect()
        self.check_required()
        self.check_types_and_slugs()
        self.check_layout()
        self.check_collisions()
        edges = self.check_blockers()
        self.check_status()
        self.check_priorities()
        self.check_covers()
        self.check_bases()
        self.check_cycles(edges)
        self.check_new_archives()
        self.check_spec_done_with_open_tasks()
        self.check_spec_acceptance()
        self.check_decisions()

    def collect(self):
        for sub in ("tasks", "done"):
            directory = os.path.join(self.wf, sub)
            for path in task_files(directory):
                m = TASK_FILE_RE.match(os.path.basename(path))
                if not m:
                    continue
                self.files.append(path)
                self.number[path] = norm_number(m.group(1))
                self.dir_effort[path] = dir_effort(directory, path)
                meta = read_fields(path)
                self.meta[path] = meta
                for line, name in meta.dups:
                    self.issue(self.sev(path), path, line, "duplicate %s field" % name,
                               "Keep one %s field." % name)
                self.effort[path] = meta.get("effort")
                key = task_ref(self.effort[path], self.number[path])
                self.index.setdefault(key, path)
                if sub == "tasks":
                    self.active.add(key)

    def check_required(self):
        for path in self.files:
            meta = self.meta[path]
            for name in ("Task", "Effort", "Check", "Blocked by"):
                if name == "Task":
                    value = meta.title or meta.get("task")
                    line = 1 if meta.title else meta.line.get("task", 1)
                else:
                    key = name.lower()
                    value = meta.get(key)
                    line = meta.line.get(key, 1)
                if not value:
                    self.issue(self.sev(path), path, line,
                               "missing or empty required %s field" % name,
                               "Add a nonempty %s field (Task may be '# NN: title'; "
                               "Check may be a section)." % name)

    def check_types_and_slugs(self):
        for path in self.files:
            value = self.meta[path].get("task type")
            if value and value not in TASK_TYPES:
                self.issue(self.sev(path), path, self.line_of(path, "task type"),
                           "invalid Task type '%s'" % value,
                           "Use feature, bugfix, spike, or refactor.")
            effort = self.effort[path]
            if effort and not SLUG_RE.match(effort):
                self.issue(self.sev(path), path, self.line_of(path, "effort"),
                           "invalid effort slug '%s'" % effort,
                           "Use lowercase letters, digits and hyphens.")

    def check_layout(self):
        for path in self.files:
            directory, effort = self.dir_effort[path], self.effort[path]
            if directory and effort and directory != effort:
                self.issue(self.sev(path), path, self.line_of(path, "effort"),
                           "task is under %s/ but its Effort is '%s'" % (directory, effort),
                           "Move it to the %s/ directory or correct the Effort field." % effort)
            title_number = self.meta[path].title_number
            if title_number and title_number != self.number[path]:
                self.issue(self.sev(path), path, 1,
                           "heading number %s does not match filename number %s"
                           % (title_number, self.number[path]),
                           "Make the '# NN:' heading and the filename use the same number.")

    def check_collisions(self):
        seen = {}
        for path in self.files:
            key = task_ref(self.effort[path], self.number[path])
            if key in seen:
                self.issue("ERROR", path, 1,
                           "task-number collision: %s also occurs in %s" % (key, self.rel(seen[key])),
                           "Renumber one task and update its blocker references.")
            else:
                seen[key] = path

    def check_blockers(self):
        edges = {}
        suggestion = "Use NN or effort/NN, comma-separated, or None."
        for path in self.files:
            blocked = self.meta[path].get("blocked by")
            if not blocked:
                continue
            line = self.line_of(path, "blocked by")
            key = task_ref(self.effort[path], self.number[path])
            try:
                refs = parse_blockers(blocked)
            except BlockerError as exc:
                if exc.trailing:
                    self.issue(self.sev(path), path, line, "malformed blocker: trailing comma", suggestion)
                else:
                    self.issue(self.sev(path), path, line, "malformed blocker '%s'" % exc.token, suggestion)
                continue
            for ref, raw in refs:
                target = resolve_ref(ref, self.effort[path])
                if target not in self.index:
                    self.issue(self.sev(path), path, line, "orphaned blocker '%s'" % raw,
                               "Create task %s or correct the Blocked by reference." % target)
                elif key in self.active and target in self.active:
                    edges.setdefault(key, []).append(target)
        return edges

    def check_covers(self):
        """Covers must name check IDs the effort's spec defines.

        Silent when the effort has no spec or the spec lists no IDs, so a project
        that writes its checks differently is never nagged.
        """
        cache = {}
        for path in self.files:
            covers = self.meta[path].get("covers")
            effort = self.effort[path]
            if not covers or not effort:
                continue
            if effort not in cache:
                cache[effort] = spec_check_ids(self.wf, effort)
            known = cache[effort]
            if not known:
                continue
            line = self.line_of(path, "covers")
            for token in covers.split(","):
                token = token.strip().strip(".")
                if token and token not in known:
                    self.issue(self.sev(path), path, line,
                               "Covers names '%s', which specs/%s.md does not define"
                               % (token, effort),
                               "Use one of: %s, or add the check to the spec."
                               % ", ".join(sorted(known)))


    def check_status(self):
        """A Status value decides whether `next` offers a task as ready.

        An unrecognized one is worse than a missing field: the task is silently
        treated as not started, so a half-finished task gets handed out again.
        """
        for path in self.files:
            value = self.meta[path].get("status").lower()
            if not value:
                continue
            line = self.line_of(path, "status")
            if value in TASK_STATUSES:
                continue
            if value in FINISHED_STATUSES:
                self.issue(self.sev(path), path, line,
                           "Status '%s' on a task file; only flow-implement archives a task"
                           % value,
                           "Move it to done/<effort>/ and drop the Status field.")
            else:
                self.issue(self.sev(path), path, line,
                           "invalid Status '%s'" % value,
                           "Use one of: %s (or drop the field for a drafted task)."
                           % ", ".join(TASK_STATUSES))

    def check_priorities(self):
        """The spec header's Priority is what `next` ranks by, and Status tracks lifecycle.

        A typo in Priority silently falls back to normal, so the effort loses its place
        in the queue without a word. A task-level Priority does nothing at all.
        """
        specs = {}
        for path in self.files:
            value = self.meta[path].get("priority")
            if value:
                self.issue(self.sev(path), path, self.line_of(path, "priority"),
                           "Priority on a task file, which nothing ranks by",
                           "Set Priority in specs/%s.md instead."
                           % (self.effort[path] or "<effort>"))
            effort = self.effort[path]
            if effort and effort not in specs:
                specs[effort] = True
        specs_dir = os.path.join(self.wf, "specs")
        if os.path.isdir(specs_dir):
            for name in sorted(os.listdir(specs_dir)):
                if name.endswith(".md"):
                    specs[name[:-3]] = True
        for effort in sorted(specs):
            path = os.path.join(self.wf, "specs", effort + ".md")
            if not os.path.isfile(path):
                continue
            meta = read_fields(path)
            value = meta.get("priority", "").lower()
            if value and value not in PRIORITY_RANK:
                self.issue("WARNING", path, meta.line.get("priority", 1),
                           "invalid Priority '%s'" % value,
                           "Use one of: %s. An unknown value ranks as normal."
                           % ", ".join(sorted(PRIORITY_RANK)))
            status = meta.get("status", "").lower()
            if status and status not in SPEC_STATUSES:
                self.issue("WARNING", path, meta.line.get("status", 1),
                           "invalid spec Status '%s'" % status,
                           "Use one of: %s." % ", ".join(SPEC_STATUSES))

    def check_bases(self):
        commits, branches = {}, {}
        for path in self.files:
            value = self.meta[path].get("base commit").strip()
            if value and value not in ("<commit-sha>", "not-started"):
                commits.setdefault(value, []).append(path)
            branch = self.meta[path].get("base branch").strip()
            if branch and not (branch.startswith("<") and branch.endswith(">")):
                branches.setdefault(branch, []).append(path)
        if not commits and not branches:
            return
        is_git = subprocess.run(["git", "-C", self.root, "rev-parse", "--git-dir"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        for value in sorted(commits):
            ok = False
            if is_git:
                ok = subprocess.run(["git", "-C", self.root, "rev-parse", "--verify", "--quiet",
                                     "--end-of-options", value + "^{commit}"],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
            if not ok:
                for path in commits[value]:
                    self.issue(self.sev(path), path, self.line_of(path, "base commit"),
                               "invalid Base commit '%s'" % value,
                               "Use an existing git commit ref, or <commit-sha> for drafts.")
        for branch in sorted(branches):
            ok = False
            if is_git:
                for candidate in (branch, "origin/" + branch):
                    if subprocess.run(["git", "-C", self.root, "rev-parse", "--verify", "--quiet",
                                       "--end-of-options", candidate + "^{commit}"],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                        ok = True
                        break
            if not ok:
                for path in branches[branch]:
                    self.issue(self.sev(path), path, self.line_of(path, "base branch"),
                               "invalid Base branch '%s'" % branch,
                               "Use an existing blocker branch name, or drop Base branch once rebased.")
    def check_cycles(self, edges):
        state = {}

        def visit(node, path):
            state[node] = 1
            for target in edges.get(node, ()):
                status = state.get(target, 0)
                if status == 1:
                    task = self.index[node]
                    self.issue("ERROR", task, self.line_of(task, "blocked by"),
                               "circular dependency: %s -> %s" % (" -> ".join(path), target),
                               "Remove or change one blocker in the cycle.")
                elif status == 0:
                    visit(target, path + [target])
            state[node] = 2

        sys.setrecursionlimit(max(1000, len(self.active) * 4 + 100))
        for node in sorted(self.active):
            if state.get(node, 0) == 0:
                visit(node, [node])

    def lines(self, path):
        if path not in self.lines_cache:
            self.lines_cache[path] = read_lines(path)
        return self.lines_cache[path]

    def head_exists(self):
        ready, _ = git_result(self.root, "rev-parse", "--verify", "--quiet", "HEAD^{commit}")
        return ready

    def check_new_archives(self):
        """Judge archives made in this change; committed history is never re-judged.

        A task moves to done/ with its checkboxes ticked and a record of the Check
        run. Only paths absent from HEAD's tree are checked, so an old archive that
        predates the rule (or a checkout of one) stays quiet.
        """
        if not self.head_exists():
            return
        ready, listing = git_result(self.root, "ls-tree", "-r", "--name-only", "HEAD", "--",
                                    ".workflow/done")
        if not ready:
            return
        committed = set(listing.splitlines())
        unticked_suggestion = ("Tick it if it is done; otherwise finish it, or delete it "
                               "and say in ## Progress why it no longer applies.")
        for path in self.files:
            rel = self.rel(path)
            if not rel.startswith(".workflow/done/") or rel in committed:
                continue
            shown = visible_lines(self.lines(path))
            for lineno, line in shown:
                m = UNTICKED_RE.match(line.strip())
                if m:
                    item = m.group(1).strip()
                    if len(item) > 60:
                        item = item[:57] + "..."
                    self.issue("ERROR", path, lineno,
                               "archived with an unticked item: %s" % item, unticked_suggestion)
            if self.meta[path].get("task type").strip().lower() == "spike":
                if not section_has_content(shown, "findings"):
                    self.issue("ERROR", path, 1, "spike archived without ## Findings",
                               "Record what the spike found under ## Findings.")
            elif not any("check after" in line.lower() for _, line in shown):
                self.issue("ERROR", path, 1, "archived without a Check after record",
                           "Run the Check on the final code and record `Check after:` in ## Progress.")

    def specs(self):
        """(effort, path, meta) for every spec file, sorted by effort."""
        specs_dir = os.path.join(self.wf, "specs")
        found = []
        if not os.path.isdir(specs_dir):
            return found
        for name in sorted(os.listdir(specs_dir)):
            path = os.path.join(specs_dir, name)
            if name.endswith(".md") and os.path.isfile(path):
                found.append((name[:-3], path, read_fields(path)))
        return found

    def check_spec_done_with_open_tasks(self):
        """A done spec whose effort still has a task under tasks/ was closed too early."""
        for effort, path, meta in self.specs():
            if meta.get("status").strip().lower() != "done":
                continue
            open_paths = sorted(p for p in self.files
                                if p.startswith(self.tasks_dir) and self.effort.get(p) == effort)
            if not open_paths:
                continue
            number = self.number[open_paths[0]]
            self.issue("ERROR", path, meta.line.get("status", 1),
                       "specs/%s.md says done but %s is still open"
                       % (effort, task_ref(effort, number)),
                       "Set the spec back to in progress (CONVENTIONS §6), or archive the task.")

    def check_spec_acceptance(self):
        """A spec that turns done in this change needs the user's acceptance on record.

        flow-close writes one `**Accepted:**` line per acceptance, and a reopening
        needs a fresh one, so the count must cover 1 + the number of ## Reopened
        headings. A spec already done in HEAD is history and stays quiet.
        """
        if not self.head_exists():
            return
        for effort, path, meta in self.specs():
            if meta.get("status").strip().lower() != "done":
                continue
            ready, text = git_result(self.root, "show", "HEAD:.workflow/specs/%s.md" % effort)
            if ready and read_fields(path, split_text(text)).get("status").strip().lower() == "done":
                continue
            required, accepted = 1, 0
            retro = os.path.join(self.done_dir, effort, "retrospective.md")
            if os.path.isfile(retro):
                lines = read_lines(retro)
                required += sum(1 for line in lines if REOPENED_RE.match(line))
                accepted = sum(1 for line in lines if ACCEPTED_RE.match(line))
            if accepted < required:
                self.issue("ERROR", path, meta.line.get("status", 1),
                           "specs/%s.md is marked done without a recorded acceptance" % effort,
                           "flow-close records `**Accepted:** <date> by <name>` in "
                           "done/%s/retrospective.md once the user accepts." % effort)

    def check_decisions(self):
        path = os.path.join(self.wf, "decisions.md")
        if not os.path.isfile(path):
            self.issue("WARNING", path, 1, "decision log is missing",
                       "Create .workflow/decisions.md with ## Entries.")
            return
        for line, message, suggestion in decision_problems(read_lines(path)):
            self.issue("ERROR", path, line, message, suggestion)



ISO_TIME_RE = re.compile(r"^[0-9-]+T[0-9][0-9]:[0-9][0-9](:[0-9][0-9](\.[0-9]+)?)?"
                         r"(Z|[+-][0-9][0-9]:[0-9][0-9])?$")
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
DECISION_HEADING_RE = re.compile(r"^[^ \t]+[ \t]+-[ \t]+[^ \t]")
DECISION_OUTSIDE_RE = re.compile(r"^[ \t]*-[ \t]+\*\*(Decided|Instead of|Because|Mine|Revisit when):")
MINE_RE = re.compile(r"^(yes|no)([ \t.(]|$)")


def valid_iso(value):
    base = value.split("T", 1)[0]
    if not DATE_RE.match(base):
        return False
    year, month, day = int(base[:4]), int(base[5:7]), int(base[8:10])
    if month < 1 or month > 12:
        return False
    if month == 2:
        days = 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28
    elif month in (4, 6, 9, 11):
        days = 30
    else:
        days = 31
    if day < 1 or day > days:
        return False
    if value == base:
        return True
    if not ISO_TIME_RE.match(value):
        return False
    rest = value[11:]
    hour, minute = int(rest[0:2]), int(rest[3:5])
    second = int(rest[6:8]) if rest[5:6] == ":" else 0
    if hour > 23 or minute > 59 or second > 59:
        return False
    m = re.search(r"[+-]", rest)
    if m:
        offset = rest[m.start() + 1:]
        if int(offset[0:2]) > 23 or int(offset[3:5]) > 59:
            return False
    return True


def decision_problems(lines):
    """[(line, message, suggestion)] for decisions.md content."""
    problems = []
    state = {"entry": False, "start": 0, "values": {}}

    def finish():
        if not state["entry"]:
            return
        for name in DECISION_FIELDS:
            if not state["values"].get(name):
                problems.append((state["start"], "missing or empty decision field %s" % name,
                                 "Add - **%s:** meaningful content." % name))

    in_comment = in_fence = entries = False
    seen = {}
    pending = ""
    for number, s in enumerate(lines, 1):
        if in_comment:
            if "-->" in s:
                in_comment = False
            continue
        if "<!--" in s:
            if "-->" not in s:
                in_comment = True
            continue
        if FENCE_RE.match(s):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if re.match(r"^##[ \t]+Entries[ \t]*$", s):
            finish()
            entries, state["entry"] = True, False
            continue
        if not entries:
            continue
        if re.match(r"^##[ \t]+[^#]", s):
            finish()
            state.update(entry=True, start=number, values={})
            seen, pending = {}, ""
            title = re.sub(r"^##[ \t]+", "", s)
            date = re.split(r"[ \t]", title, maxsplit=1)[0]
            if not valid_iso(date) or not DECISION_HEADING_RE.match(title):
                problems.append((number, "malformed decision heading",
                                 "Use ## ISO-date - title with a valid ISO8601 date or timestamp."))
            continue
        if not state["entry"]:
            if DECISION_OUTSIDE_RE.match(s):
                problems.append((number, "decision field outside an entry",
                                 "Add ## ISO-date - title above it."))
            continue
        v = re.sub(r"^[ \t]*-[ \t]+", "", s.replace("**", ""), count=1)
        key = v.split(":", 1)[0]
        if key in DECISION_FIELDS:
            seen[key] = seen.get(key, 0) + 1
            if seen[key] > 1:
                problems.append((number, "duplicate decision field %s" % key,
                                 "Keep one %s field per entry." % key))
            v = v.split(":", 1)[1].strip(" \t\r") if ":" in v else ""
            state["values"][key] = bool(v)
            pending = key
            if key == "Mine" and not MINE_RE.match(v):
                problems.append((number, "invalid Mine field",
                                 "Use yes for agent decisions, no for user decisions."))
        elif pending and re.match(r"^[ \t]+[^ \t]", s):
            state["values"][pending] = True
        elif s.strip(" \t\r"):
            pending = ""
    finish()
    if not entries:
        problems.append((1, "missing ## Entries section", "Add ## Entries before the decision log."))
    return problems


def cmd_validate(args):
    opts, code = parse_common(args, VALIDATE_USAGE, ("strict",))
    if code is not None:
        return code
    validator = Validator(project_root())
    validator.run()
    errors, warnings = validator.errors, validator.warnings
    if errors or (opts["strict"] and warnings):
        status = 2
    elif warnings:
        status = 1
    else:
        status = 0
    if opts["format"] == "json":
        out = {"valid": status == 0 and errors == 0 and warnings == 0, "errors": errors,
               "warnings": warnings, "tasks": len(validator.files), "issues": validator.issues}
        sys.stdout.write(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
        return status
    color = colors_enabled(opts["no_color"])
    red, yellow, blue, off = ("\033[31m", "\033[33m", "\033[34m", "\033[0m") if color else ("",) * 4
    out = []
    for item in validator.issues:
        warn = item["severity"] == "WARNING"
        out.append("%s%s:%s %s:%d: %s\n  Fix: %s\n" % (
            yellow if warn else red, "Warning" if warn else "Error", off,
            item["file"], item["line"], item["message"], item["suggestion"]))
    if status == 0:
        out.append("%sWorkflow is valid (%d task files).%s\n" % (blue, len(validator.files), off))
    else:
        out.append("%d error(s), %d warning(s).\n" % (errors, warnings))
    sys.stdout.write("".join(out))
    return status


# ------------------------------------------------------------------- next

NEXT_USAGE = """workflow next - suggest what to work on next

Usage: workflow next [--effort SLUG] [--all] [--format text|json] [--no-color]

Shows the top five ready tasks (or all with --all): not started, and every blocker archived under
.workflow/done/ ("Blocked by: None" also accepts "None, can start now"), with
their effort goal and Check preview. Efforts rank by the **Priority:** of
.workflow/specs/<effort>.md: critical, high, normal (default), low; ties sort
by task number.

On a branch, the first line names the tree and how far behind main it is. A
task archived on main but still present here is listed as landed: merge main.
An effort whose spec declares **Integration branch:** B lands on B instead:
on B or its task branches, B's archives count as landed; on any other branch
the effort is reported under "Integrating on another branch" and its tasks
are neither ready nor counted.

Started tasks are listed above the ready ones, never as ready: paused, needing
replanning (Status: blocked), in progress, landed, or finished on a branch but
not landed. A task counts as started when its file in this tree has a Status,
or when a task branch <effort>/<NN>-<slug> exists locally or on a remote
(under pr, git fetch first); the branch's copy of the task file gives its
Status. Branches that all claim one task are named last.

Options:
  --effort SLUG  Scope output to a single effort slug
  --all          Return all ready tasks instead of capping at five
  --format TYPE  Output text (default) or JSON
  --no-color     Disable terminal colors
  -h, --help     Show this help
"""


def spec_info(wf, effort, cache):
    """(priority, rank, goal) for an effort from specs/<effort>.md."""
    if effort in cache:
        return cache[effort]
    priority, goal = "normal", "(not specified)"
    path = os.path.join(wf, "specs", effort + ".md")
    if effort != "none" and os.path.isfile(path):
        lines = read_lines(path)
        priority = read_fields(path, lines).get("priority", "normal").lower() or "normal"
        goal = spec_goal(lines) or goal
    if priority not in PRIORITY_RANK:
        sys.stderr.write("Warning: unknown priority '%s' for effort %s; using normal\n" % (priority, effort))
        priority = "normal"
    cache[effort] = (priority, PRIORITY_RANK[priority], goal)
    return cache[effort]


def spec_goal(lines):
    """First non-empty line under `## What this is for`."""
    in_fence = in_comment = inside = False
    for line in lines:
        line, in_comment = strip_comments(line, in_comment)
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        text = line.strip()
        if text.startswith("#"):
            if inside:
                return ""
            m = H2_RE.match(text)
            if m and m.group(1).strip().rstrip(":").strip().lower() == "what this is for":
                inside = True
            continue
        if inside and text:
            return text
    return ""


def spec_check_ids(wf, effort):
    """Check IDs ({'W1', ...}) the effort's spec defines, or an empty set.

    IDs are the bolded labels of the bullets under `## How we will know it
    works`: `- **W1.** <what command, what result>`. A spec without that section,
    or one that lists no IDs, yields an empty set and disables the check.
    """
    path = os.path.join(wf, "specs", effort + ".md")
    if effort == "none" or not os.path.isfile(path):
        return set()
    found = set()
    in_fence = in_comment = inside = False
    for line in read_lines(path):
        line, in_comment = strip_comments(line, in_comment)
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        text = line.strip()
        if text.startswith("#"):
            m = H2_RE.match(text)
            if m:
                title = m.group(1).strip().rstrip(":").strip().lower()
                inside = title == "how we will know it works"
            continue
        if inside:
            m = SPEC_CHECK_RE.match(text)
            if m:
                found.add(m.group(1))
    return found


# A started task's file lives on its branch until it lands (merge-strategy.md), so
# `next` reads task branches to tell claimed, paused and blocked tasks from ready ones.
TASK_BRANCH_RE = re.compile(r"^([a-z0-9]+(?:-[a-z0-9]+)*)/([0-9]+)-([^/]+)$")
STARTED_ORDER = {"paused": 0, "blocked": 1, "active": 2, "landed": 3, "finished": 4}


def git_out(root, *args):
    """stdout of a git command run in root, or None when it fails."""
    try:
        proc = subprocess.run(["git", "-C", root] + list(args), stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, universal_newlines=True)
    except OSError:
        return None
    return proc.stdout if proc.returncode == 0 else None


def strip_remote_prefix(rest, remotes):
    """Strip the remote prefix from refs/remotes/<rest>, supporting multi-slash remotes."""
    for remote in remotes:
        prefix = remote + "/"
        if rest.startswith(prefix):
            return rest[len(prefix):]
    parts = rest.split("/")
    if len(parts) >= 3:
        return "/".join(parts[-2:])
    return parts[1] if len(parts) == 2 else ""


def task_branches(root):
    """{task ref: [(refname, branch), ...]} for <effort>/<NN>-<slug> branches.

    Local branches win over remote ones; among remotes, newer commits win.
    The checked-out branch is skipped because the working tree already shows its task file."""
    listing = git_out(root, "for-each-ref", "--sort=-committerdate",
                      "--format=%(refname)", "refs/heads", "refs/remotes")
    if not listing:
        return {}
    current = (git_out(root, "symbolic-ref", "-q", "--short", "HEAD") or "").strip()
    raw_remotes = (git_out(root, "remote") or "").splitlines()
    remotes = sorted((r.strip() for r in raw_remotes if r.strip()), key=len, reverse=True)
    heads, remote_refs = [], []
    for refname in listing.split():
        if refname.startswith("refs/heads/"):
            heads.append((refname, refname[len("refs/heads/"):]))
        elif refname.startswith("refs/remotes/"):
            name = strip_remote_prefix(refname[len("refs/remotes/"):], remotes)
            if name and name != "HEAD" and not name.endswith("/HEAD"):
                remote_refs.append((refname, name))
    found = {}
    for refname, name in heads + remote_refs:
        m = TASK_BRANCH_RE.match(name)
        if not m or name == current:
            continue
        ref = task_ref(m.group(1), norm_number(m.group(2)))
        found.setdefault(ref, []).append((refname, name))
    return found


def all_branch_names(root):
    """Every local and remote branch name, newest first."""
    listing = git_out(root, "for-each-ref", "--sort=-committerdate", "--format=%(refname)",
                      "refs/heads", "refs/remotes")
    if not listing:
        return []
    raw_remotes = (git_out(root, "remote") or "").splitlines()
    remotes = sorted((r.strip() for r in raw_remotes if r.strip()), key=len, reverse=True)
    names = []
    for refname in listing.split():
        if refname.startswith("refs/heads/"):
            names.append(refname[len("refs/heads/"):])
        elif refname.startswith("refs/remotes/"):
            name = strip_remote_prefix(refname[len("refs/remotes/"):], remotes)
            if name and name != "HEAD" and not name.endswith("/HEAD"):
                names.append(name)
    return names


def branch_task_status(root, refname, branch):
    """active | paused | blocked | finished, read from the task file on a branch."""
    effort, rest = branch.split("/", 1)
    for rel in (".workflow/tasks/%s/%s.md" % (effort, rest), ".workflow/tasks/%s.md" % rest):
        text = git_out(root, "show", "%s:%s" % (refname, rel))
        if text is not None:
            lines = [line[:-1] if line.endswith("\r") else line for line in text.split("\n")]
            status = read_fields(rel, lines).get("status").lower()
            return status if status in ("paused", "blocked") else "active"
    if git_out(root, "cat-file", "-e", "%s:.workflow/done/%s/%s.md" % (refname, effort, rest)) is not None:
        return "finished"
    return "active"


def branch_archived_tasks(root, branch, cache):
    """Set of task refs archived under .workflow/done/ on `branch` (for stacked tasks)."""
    if branch in cache:
        return cache[branch]
    found = set()
    target_ref = None
    for candidate in (branch, "origin/" + branch):
        if git_out(root, "rev-parse", "--verify", "--quiet", "--end-of-options", candidate + "^{commit}") is not None:
            target_ref = candidate
            break
    if target_ref:
        tree = git_out(root, "ls-tree", "-r", "--name-only", target_ref, ".workflow/done")
        if tree:
            for rel in tree.splitlines():
                parts = rel.split("/")
                if len(parts) >= 4 and parts[0] == ".workflow" and parts[1] == "done":
                    m = TASK_FILE_RE.match(parts[-1])
                    if m:
                        found.add(task_ref(parts[2], norm_number(m.group(1))))
    cache[branch] = found
    return found


def current_branch(root):
    """The checked-out branch, or None on a detached HEAD."""
    name = (git_out(root, "symbolic-ref", "-q", "--short", "HEAD") or "").strip()
    return name or None


def main_branch(root):
    """`main` if it exists, else `master`, else None."""
    for name in ("main", "master"):
        if git_out(root, "rev-parse", "--verify", "--quiet", "--end-of-options",
                   "refs/heads/" + name) is not None:
            return name
    return None


def resolve_branch(root, name):
    """The refname that resolves `name` locally or as origin/`name`, or None."""
    for candidate in (name, "origin/" + name):
        if git_out(root, "rev-parse", "--verify", "--quiet", "--end-of-options",
                   candidate + "^{commit}") is not None:
            return candidate
    return None


def tree_info(root):
    """Where this working tree sits relative to the main branch."""
    branch = current_branch(root)
    head = (git_out(root, "rev-parse", "--short", "HEAD") or "").strip() or None
    main = main_branch(root)
    behind = 0
    if main and branch != main and head:
        count = (git_out(root, "rev-list", "--count", "HEAD.." + main) or "").strip()
        if count.isdigit():
            behind = int(count)
    return {"branch": branch, "head": head, "main": main, "behind_main": behind}


def tree_header(tree):
    """The first `next` line: which tree is being read and how stale it is."""
    main = tree["main"]
    if not main or tree["branch"] == main or not tree["head"]:
        return ""
    label = tree["branch"] or "detached HEAD"
    if tree["behind_main"]:
        return "Reading %s (%s); %s is %d commit(s) ahead.\n" % (
            label, tree["head"], main, tree["behind_main"])
    return "Reading %s (%s).\n" % (label, tree["head"])


def branch_effort_counts(root, ref, effort):
    """(archived, open) task-file counts for one effort in a branch's tree."""
    counts = []
    for area in ("done", "tasks"):
        total = 0
        tree = git_out(root, "ls-tree", "-r", "--name-only", ref, "--",
                       ".workflow/%s/%s" % (area, effort))
        for rel in (tree or "").splitlines():
            parts = rel.split("/")
            if (len(parts) >= 4 and parts[0] == ".workflow" and parts[1] == area
                    and parts[2] == effort and TASK_FILE_RE.match(parts[-1])):
                total += 1
        counts.append(total)
    return counts[0], counts[1]


def _clean_path_token(root, token):
    token = token.strip().strip("`'\"").strip()
    if not token or token.lower() == "none" or (token.startswith("<") and token.endswith(">")):
        return ""
    if " " in token or "\t" in token or "|" in token:
        return ""
    while token.startswith("./"):
        token = token[2:]
    if "*" in token:
        prefix = token.split("*", 1)[0].rstrip("/")
        token = prefix if prefix else token
    token = token.rstrip("/")
    if not token or token == ".":
        return ""
    if "/" in token or "." in token or os.path.exists(os.path.join(root, token)):
        return token
    return ""


def parse_task_files_field(root, raw):
    """Normalized path list extracted from a task's `Files:` field."""
    if not raw or not raw.strip():
        return []
    cleaned = re.sub(r"\([^)]*\)", " ", raw)
    if "`" in cleaned:
        candidates = re.findall(r"`([^`]+)`", cleaned)
    elif "," in cleaned:
        candidates = cleaned.split(",")
    else:
        parts = cleaned.split()
        resolved = [_clean_path_token(root, p) for p in parts]
        return list(dict.fromkeys(p for p in resolved if p)) if parts and all(resolved) else []
    out = []
    for item in candidates:
        norm = _clean_path_token(root, item)
        if norm and norm not in out:
            out.append(norm)
    return out


def compute_file_overlaps(ready_tasks):
    """Shared paths across ready tasks (exact match or parent/child directory)."""
    overlaps = {}
    for i in range(len(ready_tasks)):
        t1 = ready_tasks[i]
        for j in range(i + 1, len(ready_tasks)):
            t2 = ready_tasks[j]
            for p1 in t1["files"]:
                for p2 in t2["files"]:
                    shared = None
                    if p1 == p2 or p2.startswith(p1 + "/"):
                        shared = p1
                    elif p1.startswith(p2 + "/"):
                        shared = p2
                    if shared:
                        overlaps.setdefault(shared, set()).update((t1["task"], t2["task"]))
    return [{"path": path, "tasks": sorted(refs)}
            for path, refs in sorted(overlaps.items(), key=lambda kv: (-len(kv[1]), kv[0]))]


def collect_queue(root, wf, target_effort=None):
    """Gather queue state across the working tree and git branches."""
    tasks_dir, done_dir = os.path.join(wf, "tasks"), os.path.join(wf, "done")
    tree = tree_info(root)
    if not os.path.isdir(tasks_dir):
        return {"missing_tasks_dir": True, "tree": tree, "ready": [], "started": [],
                "stackable": [], "block_tasks": {}, "block_numbers": {}, "blockers": [],
                "task_count": 0, "blocked_count": 0, "waiting": 0, "integrating": [],
                "duplicates": [], "overlaps": []}

    # Blockers archived under done/ are finished and never block.
    archived = set()
    for path in task_files(done_dir):
        m = TASK_FILE_RE.match(os.path.basename(path))
        if not m:
            continue
        effort = read_fields(path).get("effort") or dir_effort(done_dir, path)
        if not effort:
            continue
        archived.add(task_ref(effort, norm_number(m.group(1))))

    current = tree["branch"]
    main = tree["main"]
    landed_main = set()
    if main and current != main:
        landed_main = branch_archived_tasks(root, main, {})
        archived |= landed_main

    hidden_efforts = set()
    integrating = []
    integration_landed = {}
    skip_branches = set()
    integration_cache = {}
    specs_dir = os.path.join(wf, "specs")
    if os.path.isdir(specs_dir):
        for name in sorted(os.listdir(specs_dir)):
            path = os.path.join(specs_dir, name)
            if not name.endswith(".md") or not os.path.isfile(path):
                continue
            effort = name[:-3]
            if target_effort and effort != target_effort:
                continue
            integration = read_fields(path).get("integration branch").strip()
            if not integration or (integration.startswith("<") and integration.endswith(">")):
                continue
            ref = resolve_branch(root, integration)
            if ref is None:
                continue
            match = TASK_BRANCH_RE.match(current) if current else None
            if current == integration or (match is not None and match.group(1) == effort):
                for carried in branch_archived_tasks(root, ref, integration_cache):
                    if carried.split("/", 1)[0] == effort:
                        archived.add(carried)
                        integration_landed.setdefault(carried, integration)
                skip_branches.update((integration, ref))
            else:
                done_count, open_count = branch_effort_counts(root, ref, effort)
                integrating.append({"effort": effort, "branch": integration,
                                    "archived": done_count, "open": open_count})
                hidden_efforts.add(effort)

    branches = task_branches(root)
    branch_status_cache = {}
    finished_branches = {}
    for b_ref, candidates in branches.items():
        for b_refname, b_name in candidates:
            b_status = branch_task_status(root, b_refname, b_name)
            branch_status_cache[(b_ref, b_name)] = b_status
            if b_status == "finished" and b_ref not in finished_branches and b_name not in skip_branches:
                finished_branches[b_ref] = b_name

    union_cache = {}
    archived_branch = {}
    branch_names = all_branch_names(root)
    for b_name in branch_names:
        if b_name in skip_branches:
            continue
        for carried in branch_archived_tasks(root, b_name, union_cache):
            archived_branch.setdefault(carried, b_name)

    ready, started, stackable = [], [], []
    block_tasks, block_numbers = {}, {}
    task_count = blocked_count = waiting = 0
    specs = {}
    base_archived_cache = {}
    open_refs = set()

    def record(blocker, ref, number):
        block_tasks.setdefault(blocker, []).append(ref)
        block_numbers.setdefault(blocker, []).append(int(number))

    for path in task_files(tasks_dir):
        name = os.path.basename(path)
        m = TASK_FILE_RE.match(name)
        if not m:
            sys.stderr.write("Warning: ignoring task with invalid filename: %s\n" % name)
            continue
        number = norm_number(m.group(1))
        meta = read_fields(path)
        effort = meta.get("effort") or dir_effort(tasks_dir, path) or "none"
        if not SLUG_RE.match(effort):
            sys.stderr.write("Warning: %s has an invalid effort reference; using default priority\n" % name)
            effort = "none"
        if target_effort and effort != target_effort:
            continue
        if effort in hidden_efforts:
            continue
        status = meta.get("status").lower()
        if status in ("done", "completed", "archived"):
            continue
        task_count += 1
        ref = task_ref(effort, number)
        open_refs.add(ref)
        title = meta.title or meta.get("task") or "Untitled"

        if ref in landed_main:
            started.append((STARTED_ORDER["landed"], int(number), ref, title, "landed", main, effort))
            continue
        if ref in integration_landed:
            started.append((STARTED_ORDER["landed"], int(number), ref, title, "landed",
                            integration_landed[ref], effort))
            continue

        branch = None
        if status not in ("active", "paused", "blocked"):
            if ref in finished_branches:
                status, branch = "finished", finished_branches[ref]
            elif ref in archived_branch:
                status, branch = "finished", archived_branch[ref]
            elif ref in branches:
                branch = branches[ref][0][1]
                status = branch_status_cache[(ref, branch)]
        if status in STARTED_ORDER:
            started.append((STARTED_ORDER[status], int(number), ref, title, status, branch, effort))
            if status == "blocked":
                blocked_count += 1
            continue

        base_branch = meta.get("base branch").strip()
        stacked_done = set()
        if base_branch and not (base_branch.startswith("<") and base_branch.endswith(">")):
            stacked_done = branch_archived_tasks(root, base_branch, base_archived_cache)

        blocked = False
        raw = meta.get("blocked by")
        if not raw:
            blocked = True
            record("(missing Blocked by field)", ref, number)
        else:
            try:
                open_refs_needed = []
                for token, _ in parse_blockers(raw):
                    target = resolve_ref(token, effort)
                    if target not in archived and target not in stacked_done and target not in open_refs_needed:
                        open_refs_needed.append(target)
                for target in open_refs_needed:
                    record(target, ref, number)
                blocked = bool(open_refs_needed)
                if open_refs_needed and all(t in finished_branches for t in open_refs_needed):
                    stackable.append((ref, [finished_branches[t] for t in open_refs_needed]))
            except BlockerError:
                blocked = True
                sys.stderr.write("Warning: %s has malformed Blocked by: %s\n" % (name, raw))
                record("(malformed Blocked by field)", ref, number)
        if blocked:
            blocked_count += 1
            waiting += 1
            continue
        priority, rank, goal = spec_info(wf, effort, specs)
        rel_path = os.path.relpath(path, root).replace(os.sep, "/")
        branch_name = "%s/%s" % (effort, name[:-3])
        files_list = parse_task_files_field(root, meta.get("files"))
        task = {"task": ref, "number": int(number), "title": title, "effort": effort,
                "priority": priority, "goal": goal, "check": meta.get("check") or "(not specified)",
                "path": rel_path, "branch": branch_name, "files": files_list,
                "start_command": "flow-implement " + ref}
        ready.append((rank, int(number), len(ready), ref, task))
    ready.sort(key=lambda item: item[:3])
    started.sort(key=lambda item: (item[0], item[6], item[1]))
    blockers = sorted(block_tasks, key=lambda b: (-len(block_tasks[b]), b.encode("utf-8")))

    claims = {}
    for branch_name in set(branch_names):
        m = TASK_BRANCH_RE.match(branch_name)
        if not m:
            continue
        ref = task_ref(m.group(1), norm_number(m.group(2)))
        if target_effort and m.group(1) != target_effort:
            continue
        claims.setdefault(ref, set()).add(branch_name)
    duplicates = [(ref, sorted(names)) for ref, names in claims.items()
                  if len(names) >= 2 and ref in open_refs]
    duplicates.sort(key=lambda item: (-len(item[1]), item[0]))
    overlaps = compute_file_overlaps([item[4] for item in ready])
    return {"missing_tasks_dir": False, "tree": tree, "ready": ready, "started": started,
            "stackable": stackable, "block_tasks": block_tasks, "block_numbers": block_numbers,
            "blockers": blockers, "task_count": task_count, "blocked_count": blocked_count,
            "waiting": waiting, "integrating": integrating, "duplicates": duplicates,
            "overlaps": overlaps}


def cmd_next(args):
    opts, code = parse_common(args, NEXT_USAGE, ("all", "effort"))
    if code is not None:
        return code
    root = project_root()
    wf = os.path.join(root, ".workflow")
    if not os.path.isdir(wf):
        sys.stderr.write("Error: no .workflow directory at %s; run 'workflow init' first\n" % root)
        return 1
    as_json = opts["format"] == "json"
    state = collect_queue(root, wf, opts["effort"])
    tree = state["tree"]
    header = tree_header(tree)
    if state["missing_tasks_dir"]:
        if as_json:
            out = {"ready_count": 0, "task_count": 0, "blocked_count": 0, "ready_tasks": [],
                   "file_overlaps": [], "blockers": [], "in_progress": [], "tree": tree,
                   "integrating": [], "duplicate_claims": []}
            sys.stdout.write(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
        else:
            sys.stdout.write(header + "No tasks found (tasks directory is missing).\n")
        return 0

    ready = state["ready"]
    started = state["started"]
    stackable = state["stackable"]
    block_tasks = state["block_tasks"]
    block_numbers = state["block_numbers"]
    shown_ready = ready if opts["all"] else ready[:5]
    shown_blockers = state["blockers"] if opts["all"] else state["blockers"][:5]
    shown_duplicates = state["duplicates"] if opts["all"] else state["duplicates"][:5]
    overlaps = state["overlaps"]
    integrating = state["integrating"]
    task_count = state["task_count"]
    blocked_count = state["blocked_count"]
    waiting = state["waiting"]

    if as_json:
        out = {"ready_count": len(ready), "task_count": task_count, "blocked_count": blocked_count,
               "ready_tasks": [item[4] for item in shown_ready],
               "file_overlaps": overlaps,
               "blockers": [{"dependency": b, "count": len(block_tasks[b]), "tasks": block_numbers[b]}
                            for b in shown_blockers],
               "in_progress": [{"task": item[2], "number": item[1], "effort": item[6], "title": item[3],
                                "status": item[4], "branch": item[5]} for item in started],
               "tree": tree, "integrating": integrating,
               "duplicate_claims": [{"task": ref, "branches": names} for ref, names in shown_duplicates]}
        sys.stdout.write(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
        return 0

    color = colors_enabled(opts["no_color"])
    bold, dim, off = ("\033[1m", "\033[2m", "\033[0m") if color else ("", "", "")
    out = [header]
    if task_count == 0 and not integrating:
        sys.stdout.write(header + "No tasks found.\n")
        return 0
    headings = (("paused", "Paused (resume before starting new work):"),
                ("blocked", "Needs replanning (Status: blocked; flow-break amend):"),
                ("active", "In progress:"))
    for st_name, heading in headings:
        rows = [item for item in started if item[4] == st_name]
        if rows:
            out.append("%s\n" % heading)
            for item in rows:
                where = "branch %s" % item[5] if item[5] else "this working tree"
                out.append("  %s%s%s %s (%s)\n" % (bold, item[2], off, item[3], where))
    landed_branches = []
    for item in started:
        if item[4] == "landed" and item[5] not in landed_branches:
            landed_branches.append(item[5])
    for landed_branch in landed_branches:
        out.append("Landed on %s, still open in this tree (merge %s into this branch):\n"
                   % (landed_branch, landed_branch))
        for item in started:
            if item[4] == "landed" and item[5] == landed_branch:
                out.append("  %s%s%s %s (branch %s)\n" % (bold, item[2], off, item[3], landed_branch))
    finished_rows = [item for item in started if item[4] == "finished"]
    if finished_rows:
        out.append("Finished on a branch, not landed yet:\n")
        for item in finished_rows:
            out.append("  %s%s%s %s (branch %s)\n" % (bold, item[2], off, item[3], item[5]))
    if task_count:
        if ready:
            if opts["all"]:
                out.append("%sReady tasks%s (%d):\n" % (bold, off, len(ready)))
            else:
                out.append("%sReady tasks%s (%d total; showing up to 5):\n" % (bold, off, len(ready)))
            for i, item in enumerate(shown_ready, 1):
                ref, task = item[3], item[4]
                out.append("%d) %s%s%s %s (priority: %s)\n" % (i, bold, ref, off, task["title"], task["priority"]))
                if task["goal"] != "(not specified)":
                    out.append("   %sGoal:%s %s\n" % (dim, off, task["goal"]))
                out.append("   %sCheck:%s %s\n" % (dim, off, task["check"]))
                out.append("   Start: flow-implement %s\n" % ref)
            if overlaps:
                shown_overlaps = overlaps if opts["all"] else overlaps[:5]
                out.append("Shared files across ready tasks (serialize or coordinate): %s\n" % (
                    ", ".join("%s (%s)" % (o["path"], ", ".join(o["tasks"])) for o in shown_overlaps)))
        else:
            out.append("No ready tasks.\n")
    if waiting:
        out.append("Waiting on dependencies: %d task(s); top blockers: %s\n" % (
            waiting, ", ".join("%s (%d)" % (b, len(block_tasks[b])) for b in shown_blockers)))
        if stackable:
            out.append("Stackable under pr (blockers finished on branch): %s\n" % (
                ", ".join("%s (on %s)" % (r, ", ".join(bs)) for r, bs in stackable)))
    if integrating:
        out.append("Integrating on another branch (run next there):\n")
        for item in integrating:
            out.append("  %s on %s: %d archived, %d open\n" % (
                item["effort"], item["branch"], item["archived"], item["open"]))
    if shown_duplicates:
        out.append("Several branches claim one task (keep one; rename retries to "
                   "attempt/<effort>-<NN>): %s\n" % ", ".join(
                       "%s (%d)" % (ref, len(names)) for ref, names in shown_duplicates))
    sys.stdout.write("".join(out))
    return 0


# ------------------------------------------------------------------ pulse

PULSE_USAGE = """workflow pulse - anti-drift queue snapshot for long autonomous runs

Usage: workflow pulse [--effort SLUG] [--quiet-idle] [--format text|json] [--no-color]

Prints a compact snapshot of active, paused, blocked and ready tasks alongside
anti-drift execution directives (CONVENTIONS §7, §9, §10) so multi-hour sessions
keep momentum after compaction or heavy tool output.

Options:
  --effort SLUG  Scope snapshot to a single effort slug
  --quiet-idle   Print nothing when no open tasks or .workflow/HANDOFF.md exist
  --format TYPE  Output text (default) or JSON
  --no-color     Disable terminal colors
  -h, --help     Show this help
"""

PULSE_DIRECTIVES = [
    "Act on the bottleneck directly; do not spend a turn acknowledging this pulse.",
    "Harvest completed subagent work immediately (Check + real path + land) and launch newly ready tasks.",
    "If the same blocker survived two rounds without progress, take over the gap or run flow-break amend.",
    "Reuse valid checks on unchanged code; skip speculative edge cases, unpaid hashes and unrequested wrappers.",
]


def cmd_pulse(args):
    opts, code = parse_common(args, PULSE_USAGE, ("effort", "quiet_idle"))
    if code is not None:
        return code
    root = project_root()
    wf = os.path.join(root, ".workflow")
    if not os.path.isdir(wf):
        sys.stderr.write("Error: no .workflow directory at %s; run 'workflow init' first\n" % root)
        return 1
    state = collect_queue(root, wf, opts["effort"])
    handoff = os.path.isfile(os.path.join(wf, "HANDOFF.md"))
    active_work = bool(handoff or state["started"] or state["ready"]
                       or state["waiting"] or state["integrating"])
    if opts["quiet_idle"] and not active_work:
        return 0

    ready_refs = [item[3] for item in state["ready"]]
    started_summary = [{"task": item[2], "status": item[4], "branch": item[5]}
                       for item in state["started"]]
    if opts["format"] == "json":
        out = {"active": active_work, "handoff": handoff, "tree": state["tree"],
               "in_progress": started_summary, "ready": ready_refs,
               "file_overlaps": state["overlaps"], "waiting_count": state["waiting"],
               "integrating": state["integrating"], "directives": PULSE_DIRECTIVES}
        sys.stdout.write(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
        return 0

    lines = [tree_header(state["tree"])]
    if handoff:
        lines.append("Handoff: .workflow/HANDOFF.md present — read it and delete once absorbed.\n")
    if started_summary:
        lines.append("Started: %s\n" % ", ".join(
            "%s [%s%s]" % (s["task"], s["status"], " @" + s["branch"] if s["branch"] else "")
            for s in started_summary))
    if ready_refs:
        lines.append("Ready wave (%d): %s\n" % (len(ready_refs), ", ".join(ready_refs)))
    if state["overlaps"]:
        lines.append("Overlaps: %s\n" % ", ".join(
            "%s (%s)" % (o["path"], "+".join(o["tasks"])) for o in state["overlaps"]))
    if state["waiting"]:
        lines.append("Waiting on dependencies: %d task(s)\n" % state["waiting"])
    if not active_work:
        lines.append("Queue idle.\n")
    else:
        lines.append("Pulse:\n" + "".join("- %s\n" % d for d in PULSE_DIRECTIVES))
    sys.stdout.write("".join(lines))
    return 0


# ------------------------------------------------------------------- main

MAIN_USAGE = """workflow-core.py %s - validate, next and pulse for the workflow toolkit

Usage: workflow-core.py validate [--strict] [--format text|json] [--no-color]
       workflow-core.py next [--effort SLUG] [--all] [--format text|json] [--no-color]
       workflow-core.py pulse [--effort SLUG] [--quiet-idle] [--format text|json] [--no-color]
       workflow-core.py <command> --help
""" % VERSION


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        (sys.stdout if argv else sys.stderr).write(MAIN_USAGE)
        return 0 if argv else 2
    command, args = argv[0], argv[1:]
    if command == "validate":
        return cmd_validate(args)
    if command == "next":
        return cmd_next(args)
    if command == "pulse":
        return cmd_pulse(args)
    sys.stderr.write("Error: unknown command: %s\n" % command)
    sys.stderr.write(MAIN_USAGE)
    return 2

if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
