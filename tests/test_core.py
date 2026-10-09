#!/usr/bin/env python3
"""Tests for bin/workflow-core.py (validate and next).

Run from the repo root: python3 tests/test_core.py
Each test builds its project in a temporary git repository.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "workflow-core.py")

VALID_DECISIONS = """# Decisions

## Entries

## 2026-01-02 - Use Python for the core

- **Decided:** Port validate and next to Python.
- **Instead of:** Keeping Bash 4.
- **Because:** macOS ships Bash 3.2.
- **Mine:** yes
- **Revisit when:** Python is unavailable.
"""


def task(number, title, effort, blocked="None", check="Run the tests.", extra=""):
    return ("# %s: %s\n\n**Effort:** %s\n**Blocked by:** %s\n**Check:** %s\n%s"
            % (number, title, effort, blocked, check, extra))


class Project(object):
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="wf-core-")
        subprocess.run(["git", "init", "-q", self.root], check=True)
        self.write(".workflow/decisions.md", VALID_DECISIONS)
        os.makedirs(os.path.join(self.root, ".workflow", "tasks"), exist_ok=True)

    def write(self, rel, content):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", newline="") as fh:
            fh.write(content)
        return path

    def run(self, *args):
        proc = subprocess.run([sys.executable, CORE] + list(args), cwd=self.root,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True, env=dict(os.environ, NO_COLOR="1"))
        return proc

    def validate(self, *args):
        proc = self.run("validate", "--format", "json", *args)
        return proc.returncode, json.loads(proc.stdout)

    def next(self):
        proc = self.run("next", "--format", "json")
        self.last = proc
        return json.loads(proc.stdout)

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


class Base(unittest.TestCase):
    def setUp(self):
        self.p = Project()

    def tearDown(self):
        self.p.close()

    def messages(self, data, severity=None):
        return [i["message"] for i in data["issues"] if severity in (None, i["severity"])]

    def assertIssue(self, data, fragment, severity="ERROR"):
        found = [m for m in self.messages(data, severity) if fragment in m]
        self.assertTrue(found, "no %s containing %r in %s" % (severity, fragment, data["issues"]))


class ValidateTests(Base):
    def test_valid_project(self):
        self.p.write(".workflow/tasks/core/01-start.md", task("01", "Start", "core"))
        self.p.write(".workflow/tasks/core/02-next.md", task("02", "Next", "core", blocked="01"))
        code, data = self.p.validate()
        self.assertEqual((code, data["valid"], data["errors"], data["warnings"], data["tasks"]),
                         (0, True, 0, 0, 2))
        self.assertEqual(data["issues"], [])
        text = self.p.run("validate")
        self.assertEqual(text.returncode, 0)
        self.assertIn("Workflow is valid (2 task files).", text.stdout)

    def test_required_fields(self):
        self.p.write(".workflow/tasks/core/01-bare.md", "Some prose without fields.\n")
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        for name in ("Task", "Effort", "Check", "Blocked by"):
            self.assertIssue(data, "missing or empty required %s field" % name)

    def test_variants_bullets_sections_and_bold(self):
        content = textwrap.dedent("""\
            - Task: Bulleted title
            - Effort: core
            - Blocked by:
              - None

            ## Check

            Run make test.

            ```
            Effort: wrong
            ```
            <!-- Blocked by: 99 -->
            """)
        self.p.write(".workflow/tasks/core/01-variants.md", content)
        code, data = self.p.validate()
        self.assertEqual(code, 0, data)

    def test_malformed_blockers(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core", blocked="soon"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", blocked="01,"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "malformed blocker 'soon'")
        self.assertIssue(data, "malformed blocker: trailing comma")

    def test_missing_blocker_and_references(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", blocked="1"))
        self.p.write(".workflow/tasks/ui/01-c.md", task("01", "C", "ui", blocked="core/02, core/1"))
        self.p.write(".workflow/tasks/ui/02-d.md", task("02", "D", "ui", blocked="core/07"))
        self.p.write(".workflow/tasks/ui/03-e.md", task("03", "E", "ui", blocked="05"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "orphaned blocker 'core/07'")
        self.assertIssue(data, "orphaned blocker '05'")
        orphans = [m for m in self.messages(data) if "orphaned" in m]
        self.assertEqual(len(orphans), 2, data["issues"])
        self.assertEqual(data["errors"], 2)

    def test_duplicate_numbers(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.p.write(".workflow/tasks/core/1-b.md", task("1", "B", "core"))
        self.p.write(".workflow/tasks/ui/01-c.md", task("01", "C", "ui"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        collisions = [m for m in self.messages(data) if "collision" in m]
        self.assertEqual(len(collisions), 1, data["issues"])
        self.assertIn("core/01", collisions[0])

    def test_heading_number_and_directory_mismatch(self):
        self.p.write(".workflow/tasks/core/03-a.md", task("04", "A", "core"))
        self.p.write(".workflow/tasks/core/05-b.md", task("05", "B", "ui"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "heading number 4 does not match filename number 3")
        self.assertIssue(data, "task is under core/ but its Effort is 'ui'")

    def test_done_problems_are_warnings(self):
        self.p.write(".workflow/done/core/01-old.md", "# 01: Old\n\n**Effort:** core\n")
        self.p.write(".workflow/done/core/retrospective.md", "# Retrospective\n")
        code, data = self.p.validate()
        self.assertEqual(code, 1)
        self.assertEqual((data["errors"], data["valid"], data["tasks"]), (0, False, 1))
        self.assertIssue(data, "missing or empty required Check field", "WARNING")
        strict, _ = self.p.validate("--strict")
        self.assertEqual(strict, 2)

    def test_cycles(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core", blocked="03"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", blocked="01"))
        self.p.write(".workflow/tasks/core/03-c.md", task("03", "C", "core", blocked="02"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "circular dependency: core/01 -> core/03 -> core/02 -> core/01")

    def test_invalid_type_slug_base_and_duplicate_field(self):
        extra = "**Task type:** chore\n**Base commit:** deadbeefcafe\n**Check:** again\n"
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core", extra=extra))
        self.p.write(".workflow/tasks/02-b.md", task("02", "B", "Bad_Slug"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "invalid Task type 'chore'")
        self.assertIssue(data, "invalid Base commit 'deadbeefcafe'")
        self.assertIssue(data, "duplicate check field")
        self.assertIssue(data, "invalid effort slug 'Bad_Slug'")

    def test_decisions_errors(self):
        self.p.write(".workflow/decisions.md", textwrap.dedent("""\
            # Decisions

            - **Decided:** too early

            ## Entries

            ## 2026-02-30 - Bad date

            - **Decided:** x
            - **Decided:** y
            - **Instead of:** z
            - **Because:** w
            - **Mine:** maybe
            - **Revisit when:** v

            ## 2026-03-01 - Missing fields

            - **Decided:** x
            - **Because:**

            ```
            ## not a heading
            ```
            """))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        msgs = self.messages(data)
        self.assertIn("malformed decision heading", msgs)
        self.assertIn("duplicate decision field Decided", msgs)
        self.assertIn("invalid Mine field", msgs)
        self.assertIn("missing or empty decision field Because", msgs)
        self.assertIn("missing or empty decision field Instead of", msgs)
        self.assertNotIn("decision field outside an entry", msgs)  # before ## Entries is ignored
        self.assertEqual(len([m for m in msgs if "decision" in m or "Mine" in m]), 7, msgs)

    def test_decisions_missing_entries_and_outside_field(self):
        self.p.write(".workflow/decisions.md", "# Decisions\n")
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "missing ## Entries section")
        self.p.write(".workflow/decisions.md", "## Entries\n\n- **Mine:** yes\n")
        _, data = self.p.validate()
        self.assertIssue(data, "decision field outside an entry")
        os.remove(os.path.join(self.p.root, ".workflow/decisions.md"))
        code, data = self.p.validate()
        self.assertEqual(code, 1)
        self.assertIssue(data, "decision log is missing", "WARNING")

    def test_decision_with_supersedes_is_valid(self):
        self.p.write(".workflow/decisions.md", VALID_DECISIONS + textwrap.dedent("""\
            - **Superseded by:** 2026-05-01T10:00:00+08:00 - Use Go

            ## 2026-05-01T10:00:00+08:00 - Use Go

            - **Effort:** core
            - **Decided:** Port to Go.
            - **Instead of:** Python,
              which needs an interpreter.
            - **Because:** One static binary.
            - **Mine:** no (user call)
            - **Revisit when:** Never.
            - **Supersedes:** 2026-01-02 - Use Python for the core
            <!-- a note -->
            """))
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

    def test_crlf_warning_and_json_shape(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core").replace("\n", "\r\n"))
        code, data = self.p.validate()
        self.assertEqual(code, 1)
        self.assertEqual(sorted(data), ["errors", "issues", "tasks", "valid", "warnings"])
        issue = data["issues"][0]
        self.assertEqual(sorted(issue), ["file", "line", "message", "severity", "suggestion"])
        self.assertEqual(issue["file"], ".workflow/tasks/core/01-a.md")
        self.assertIsInstance(issue["line"], int)
        self.assertEqual(issue["message"], "CRLF line endings")

    def test_missing_workflow_and_usage_errors(self):
        shutil.rmtree(os.path.join(self.p.root, ".workflow"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "missing .workflow directory")
        for args in (["validate", "--fix"], ["validate", "--format"], ["validate", "--format", "xml"],
                     ["next", "--interactive"], ["bogus"], []):
            self.assertEqual(self.p.run(*args).returncode, 2, args)
        for cmd in ("validate", "next"):
            proc = self.p.run(cmd, "--help")
            self.assertEqual(proc.returncode, 0)
            self.assertIn("Usage: workflow " + cmd, proc.stdout)

    def test_text_output_without_color(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core", blocked="9"))
        proc = self.p.run("validate", "--no-color")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("Error: .workflow/tasks/core/01-a.md:4: orphaned blocker '9'", proc.stdout)
        self.assertIn("  Fix: Create task core/09", proc.stdout)
        self.assertIn("1 error(s), 0 warning(s).", proc.stdout)
        self.assertNotIn("\033[", proc.stdout)


class NextTests(Base):
    def spec(self, effort, priority, goal):
        self.p.write(".workflow/specs/%s.md" % effort, textwrap.dedent("""\
            # Spec: %s

            **Status:** in progress
            **Priority:** %s

            ## What this is for

            %s
            Second line is not the goal.

            ## Scope

            Scope must not leak.
            """) % (effort, priority, goal))

    def test_ranking_by_spec_priority(self):
        self.spec("crit", "critical", "Fix the outage.")
        self.spec("hi", "High", "Ship high priority work.")
        self.spec("lo", "low", "Someday.")
        self.p.write(".workflow/tasks/lo/01-a.md", task("01", "Low", "lo"))
        self.p.write(".workflow/tasks/plain/05-b.md", task("05", "Plain", "plain"))
        self.p.write(".workflow/tasks/hi/10-c.md", task("10", "High ten", "hi"))
        self.p.write(".workflow/tasks/hi/02-d.md", task("02", "High two", "hi", check="Check task two."))
        self.p.write(".workflow/tasks/crit/09-e.md", task("09", "Crit", "crit"))
        data = self.p.next()
        self.assertEqual(self.p.last.returncode, 0)
        self.assertEqual([(t["effort"], t["number"]) for t in data["ready_tasks"]],
                         [("crit", 9), ("hi", 2), ("hi", 10), ("plain", 5), ("lo", 1)])
        two = data["ready_tasks"][1]
        self.assertEqual((two["priority"], two["goal"], two["check"], two["start_command"]),
                         ("high", "Ship high priority work.", "Check task two.", "flow-implement hi/02"))
        self.assertEqual(data["ready_tasks"][3]["goal"], "(not specified)")
        self.assertEqual(data["ready_tasks"][3]["priority"], "normal")
        self.assertEqual(self.p.last.stderr, "")
        self.assertEqual((data["ready_count"], data["task_count"], data["blocked_count"]), (5, 5, 0))
        text = self.p.run("next").stdout
        self.assertIn("1) crit/09 Crit (priority: critical)", text)
        self.assertIn("Goal: Fix the outage.", text)
        self.assertNotIn("Scope must not", text)
        self.assertNotIn("Second line", text)

    def test_archived_blockers_satisfied_and_blocked_status(self):
        self.p.write(".workflow/done/core/01-done.md", task("01", "Done", "core"))
        self.p.write(".workflow/tasks/core/02-a.md", task("02", "A", "core", blocked="01"))
        self.p.write(".workflow/tasks/core/03-b.md", task("03", "B", "core", blocked="01, 02"))
        self.p.write(".workflow/tasks/core/04-c.md",
                     task("04", "C", "core", extra="**Status:** blocked\n"))
        self.p.write(".workflow/tasks/core/05-d.md", task("05", "D", "core", blocked="later"))
        data = self.p.next()
        self.assertEqual([t["number"] for t in data["ready_tasks"]], [2])
        self.assertEqual((data["ready_count"], data["task_count"], data["blocked_count"]), (1, 4, 3))
        deps = {b["dependency"]: b for b in data["blockers"]}
        self.assertEqual(deps["core/02"]["tasks"], [3])
        self.assertEqual(deps["(Status: blocked, needs replanning)"]["count"], 1)
        self.assertIn("(malformed Blocked by field)", deps)

    def test_no_ready_tasks_and_no_tasks(self):
        text = self.p.run("next").stdout
        self.assertIn("No tasks found.", text)
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core", blocked="02"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", blocked="01"))
        text = self.p.run("next").stdout
        self.assertIn("No ready tasks. 2 task(s) blocked.", text)
        self.assertIn("core/01: 1 task(s) (tasks: core/02)", text)
        data = self.p.next()
        self.assertEqual(sorted(data), ["blocked_count", "blockers", "ready_count", "ready_tasks", "task_count"])

    def test_missing_workflow(self):
        shutil.rmtree(os.path.join(self.p.root, ".workflow"))
        self.assertEqual(self.p.run("next").returncode, 1)


class PerformanceTests(Base):
    def test_large_project_is_fast(self):
        for effort_index in range(4):
            effort = "effort-%d" % effort_index
            self.spec_written = self.p.write(".workflow/specs/%s.md" % effort,
                                             "**Priority:** high\n\n## What this is for\n\nGoal.\n")
            for n in range(1, 31):
                blocked = "None" if n == 1 else "%02d" % (n - 1)
                extra = "**Base commit:** <commit-sha>\n- **Files:** src/a.py\n  src/b.py\n"
                self.p.write(".workflow/tasks/%s/%02d-task.md" % (effort, n),
                             task("%02d" % n, "Task %d" % n, effort, blocked=blocked, extra=extra))
        for cmd in ("validate", "next"):
            start = time.time()
            proc = self.p.run(cmd, "--format", "json")
            elapsed = time.time() - start
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertLess(elapsed, 5.0, "%s took %.2fs" % (cmd, elapsed))
        self.assertEqual(json.loads(self.p.run("validate", "--format", "json").stdout)["tasks"], 120)
        self.assertEqual(json.loads(self.p.run("next", "--format", "json").stdout)["ready_count"], 4)


if __name__ == "__main__":
    unittest.main()
