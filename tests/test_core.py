#!/usr/bin/env python3
"""Tests for bin/workflow-core.py (validate and next).

Run from the repo root: python3 tests/test_core.py
Each test builds its project in a temporary git repository.
"""

import json
import os
import re
import shutil
import stat
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
- **Decided by:** agent
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
                              universal_newlines=True,
                              env=dict(os.environ, NO_COLOR="1", PYTHONWARNINGS="error::DeprecationWarning"))
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

    def git(self, *args):
        subprocess.run(["git", "-C", self.p.root, "-c", "user.email=t@t", "-c", "user.name=t"] + list(args),
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def commit_all(self, message):
        self.git("add", "-A")
        self.git("commit", "-qm", message)

    def head_short(self, rev="HEAD"):
        return subprocess.run(["git", "-C", self.p.root, "rev-parse", "--short", rev],
                              stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()

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
        self.p.write(".workflow/done/core/closeout.md", "# Closeout\n")
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

    def test_standalone_spec_and_base_branch_validation(self):
        self.p.write(".workflow/specs/orphan.md", "**Status:** Bogus\n**Priority:** ultra\n")
        code, data = self.p.validate()
        self.assertEqual(code, 1)
        self.assertIssue(data, "invalid Priority 'ultra'", "WARNING")
        self.assertIssue(data, "invalid spec Status 'bogus'", "WARNING")
        self.p.write(".workflow/specs/orphan.md", "**Status:** proposed\n**Priority:** high\n")
        self.p.write(".workflow/tasks/orphan/01-a.md",
                     task("01", "A", "orphan", extra="**Base branch:** no-such-branch\n"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "invalid Base branch 'no-such-branch'")
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
            - **Decided by:** maybe
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
        self.assertIn("invalid Decided by field", msgs)
        self.assertIn("missing or empty decision field Because", msgs)
        self.assertIn("missing or empty decision field Instead of", msgs)
        self.assertNotIn("decision field outside an entry", msgs)  # before ## Entries is ignored
        self.assertEqual(len([m for m in msgs if "decision" in m or "Decided by" in m]), 5, msgs)

    def test_decision_effort_field(self):
        self.p.write(".workflow/decisions.md", VALID_DECISIONS + textwrap.dedent("""\
            ## 2026-04-01 - Tie a decision to an effort

            - **Effort:** core
            - **Decided:** Keep the queue in Python.
            - **Instead of:** Rewriting in Bash.
            - **Because:** Bash 3.2 cannot parse JSON.
            """))
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        # Present but empty is an error; absent is fine.
        self.p.write(".workflow/decisions.md", textwrap.dedent("""\
            # Decisions

            ## Entries

            - **Effort:**

            ## 2026-04-02 - Empty effort

            - **Effort:**
            - **Decided:** x
            - **Instead of:** y
            - **Because:** z
            """))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "decision field outside an entry")
        self.assertIssue(data, "missing or empty decision field Effort")

    def test_decisions_missing_entries_and_outside_field(self):
        self.p.write(".workflow/decisions.md", "# Decisions\n")
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "missing ## Entries section")
        self.p.write(".workflow/decisions.md", "## Entries\n\n- **Decided by:** agent\n")
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
            - **Decided by:** user (user call)
            - **Revisit when:** Never.
            - **Supersedes:** 2026-01-02 - Use Python for the core
            <!-- a note -->

            ## 2026-06-01 - Append-only Supersedes without mutating older entry

            - **Decided:** Keep SQLite for local queue state.
            - **Instead of:** Adding Redis.
            - **Because:** Single-host CLI needs zero daemon setup.
            - **Supersedes:** 2026-05-01T10:00:00+08:00 - Use Go
            - **Mine:** yes
            """))
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

        # Empty, duplicate, or outside-entry Supersedes fields are rejected.
        self.p.write(".workflow/decisions.md", textwrap.dedent("""\
            # Decisions

            ## Entries

            - **Supersedes:** orphan

            ## 2026-07-01 - Broken Supersedes

            - **Decided:** x
            - **Instead of:** y
            - **Because:** z
            - **Supersedes:** a
            - **Supersedes:**
            """))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "decision field outside an entry")
        self.assertIssue(data, "duplicate decision field Supersedes")
        self.assertIssue(data, "missing or empty decision field Supersedes")

    def test_nested_and_tilde_code_fences(self):
        self.p.write(".workflow/specs/core.md", textwrap.dedent("""\
            # Spec: core

            **Status:** in progress
            **Priority:** high

            ## What this is for

            ````markdown
            ```
            Fake goal inside nested fence.
            ```
            ````
            Real goal after nested fence.

            ## How we will know it works

            - **W1.** Real check.
            ~~~~markdown
            ```
            - **W99.** Fake check inside tilde fence.
            ```
            ~~~~
            """))
        self.p.write(".workflow/decisions.md", VALID_DECISIONS + textwrap.dedent("""\
            ````markdown
            ```
            ## 2026-02-30 - Fake malformed decision inside 4-backtick fence
            ```
            ````
            """))
        self.p.write(".workflow/tasks/core/01-fenced.md", textwrap.dedent("""\
            # 01: Fenced examples

            **Effort:** core
            **Blocked by:** None
            **Covers:** W1
            **Check:** Run ```` ```inline``` ```` check.

            ````markdown
            ```sh
            **Effort:** wrong_slug
            **Blocked by:** 99
            <!-- unclosed HTML comment inside code fence
            - [ ] Unticked example item inside nested fence
            ```
            ````

            - [x] Real checklist item

            ## Progress

            Check after: passed
            Review: pass (base abcdef)
            """))
        self.commit_all("plan")
        os.makedirs(os.path.join(self.p.root, ".workflow/done/core"), exist_ok=True)
        self.git("mv", ".workflow/tasks/core/01-fenced.md", ".workflow/done/core/01-fenced.md")
        self.p.write(".workflow/tasks/core/02-open.md",
                     task("02", "Open", "core", extra="**Covers:** W99\n"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertEqual(len(data["issues"]), 1, data["issues"])
        self.assertIssue(data, "Covers names 'W99', which specs/core.md does not define")
        self.p.write(".workflow/tasks/core/02-open.md",
                     task("02", "Open", "core", extra="**Covers:** W1\n"))
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        nxt = self.p.next()
        self.assertEqual(nxt["ready_tasks"][0]["goal"], "Real goal after nested fence.")

    def test_files_field_warning_in_validate(self):
        self.p.write(".workflow/tasks/core/01-bad.md",
                     task("01", "Prose files", "core", extra="**Files:** touch whatever needs changing.\n"))
        self.p.write(".workflow/tasks/core/02-spike.md",
                     task("02", "Spike prose", "core",
                          extra="**Task type:** spike\n**Files:** throwaway prototype branch\n"))
        self.p.write(".workflow/tasks/core/03-none.md",
                     task("03", "Explicit none", "core", extra="**Files:** None\n"))
        self.p.write(".workflow/tasks/core/04-placeholder.md",
                     task("04", "Draft", "core", extra="**Files:** <where work happens>\n"))
        self.p.write(".workflow/done/core/00-old.md",
                     task("00", "Archived prose", "core",
                          extra="**Files:** legacy prose\n\n## Progress\n\nCheck after: ok\n"
                                "Review: pass (base abcdef)\n"))
        code, data = self.p.validate()
        self.assertEqual((code, data["errors"], data["warnings"]), (1, 0, 1), data["issues"])
        self.assertIssue(data, "Files field lists no recognizable paths", "WARNING")
        self.assertEqual(data["issues"][0]["file"], ".workflow/tasks/core/01-bad.md")
    def test_crlf_files_are_accepted(self):
        # Windows checkouts may use CRLF; the reader strips CR, so nothing is reported.
        crlf = lambda text: text.replace("\n", "\r\n")
        self.p.write(".workflow/tasks/core/01-a.md", crlf(task("01", "A", "core")))
        self.p.write(".workflow/tasks/core/02-b.md", crlf(task("02", "B", "core", blocked="01")))
        self.p.write(".workflow/decisions.md", crlf(VALID_DECISIONS))
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        proc = self.p.run("next", "--format", "json")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual([t["number"] for t in json.loads(proc.stdout)["ready_tasks"]], [1])

    def test_json_issue_shape(self):
        self.p.write(".workflow/done/core/01-old.md", "# 01: Old\n\n**Effort:** core\n")
        code, data = self.p.validate()
        self.assertEqual(code, 1)
        self.assertEqual(sorted(data), ["errors", "issues", "tasks", "valid", "warnings"])
        issue = data["issues"][0]
        self.assertEqual(sorted(issue), ["file", "line", "message", "severity", "suggestion"])
        self.assertEqual(issue["file"], ".workflow/done/core/01-old.md")
        self.assertEqual(issue["severity"], "WARNING")
        self.assertIsInstance(issue["line"], int)

    def test_missing_workflow_and_usage_errors(self):
        shutil.rmtree(os.path.join(self.p.root, ".workflow"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "missing .workflow directory")
        for args in (["validate", "--fix"], ["validate", "--format"], ["validate", "--format", "xml"],
                     ["next", "--interactive"], ["next", "--quiet-idle"], ["pulse"], ["bogus"], []):
            self.assertEqual(self.p.run(*args).returncode, 2, args)
        for args, hint in ((["validate", "--fix"], "validate --fix was removed in 2.5"),
                           (["next", "--interactive"], "next --interactive was removed in 2.5"),
                           (["next", "--quiet-idle"], "workflow next --brief"),
                           (["pulse"], "workflow pulse was removed: run 'workflow next --brief'")):
            proc = self.p.run(*args)
            self.assertIn(hint, proc.stderr)
            self.assertEqual(proc.stdout, "")
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


    def test_new_archive_unticked_item(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        self.p.write(".workflow/done/core/01-a.md", textwrap.dedent("""\
            # 01: A

            **Effort:** core
            **Check:** Run the tests.
            **Blocked by:** None

            ## Progress

            - [x] Wrote it
            - [ ] Ship it
            Check after: ran on the final code
            Review: pass (base abcdef)
            """))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "archived with an unticked item: Ship it")
        self.assertIn("Tick it if it is done", data["issues"][0]["suggestion"])

    def test_new_archive_needs_check_after(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        body = "# 01: A\n\n**Effort:** core\n**Check:** Run.\n**Blocked by:** None\n"
        self.p.write(".workflow/done/core/01-a.md", body)
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "archived without a Check after or Check waived record")
        self.assertIssue(data, "archived without a Review record")
        self.p.write(".workflow/done/core/01-a.md",
                     body + "\n## Progress\n\nCheck after: ran it on the final code\n"
                            "Review: pass (base abcdef)\n")
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        # A user waiver of the Check replaces Check after.
        self.p.write(".workflow/done/core/01-a.md",
                     body + "\n## Progress\n\nCheck waived: user; Ada; 2026-11-11\n"
                            "Review: waived — finding B2; user, 2026-11-11\n")
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

    def test_new_archive_check_after_must_record_a_result(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        body = ("# 01: A\n\n**Effort:** core\n**Check:** Run.\n**Blocked by:** None\n"
                "\n## Progress\n\nReview: pass (base abcdef)\nCheck after: %s\n")
        for value in ("n/a", "TODO", "`*not run*", "pending", "deferred", "未运行", "跳过"):
            self.p.write(".workflow/done/core/01-a.md", body % value)
            code, data = self.p.validate()
            self.assertEqual(code, 2, value)
            self.assertIssue(data, "Check after records no result")
            self.assertIn("Run the Check and record its result",
                          data["issues"][0]["suggestion"])
        # Values that merely contain a no-result word later in the text pass.
        for value in ("120 passed", "tests skipped nothing", "boot log clean"):
            self.p.write(".workflow/done/core/01-a.md", body % value)
            code, data = self.p.validate()
            self.assertEqual((code, data["issues"]), (0, []), value)
        # The rule is literal: a leading no-result word decides, even with a suffix.
        for value in ("pending-free", "Not Run: build only"):
            self.p.write(".workflow/done/core/01-a.md", body % value)
            code, data = self.p.validate()
            self.assertEqual(code, 2, value)
            self.assertIssue(data, "Check after records no result")
        # The continuation lines are part of the value: an empty first line followed
        # by a no-result word records no result.
        self.p.write(".workflow/done/core/01-a.md", (body % "") + "  pending\n")
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "Check after records no result")

    def test_new_archive_check_after_cites_no_temp_path(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        body = ("# 01: A\n\n**Effort:** core\n**Check:** Run.\n**Blocked by:** None\n"
                "\n## Progress\n\nCheck after: %s\nReview: pass (base abcdef)\n")
        for value in ("/tmp/run.log shows PASS", "see /var/tmp/log",
                      "log at /tmp/x.log — 120 passed"):
            self.p.write(".workflow/done/core/01-a.md", body % value)
            code, data = self.p.validate()
            self.assertEqual(code, 2, value)
            self.assertIssue(data, "Check after cites a temporary path")
            self.assertIn("Evidence directory", data["issues"][0]["suggestion"])
        # A repository path that merely contains "tmp-notes" is not a temporary path.
        for value in ("evidence/tmp-notes/a.log shows PASS", "/repo/tmp/a.log",
                      "./tmp.log — 120 passed", "~/tmp/a.log"):
            self.p.write(".workflow/done/core/01-a.md", body % value)
            code, data = self.p.validate()
            self.assertEqual((code, data["issues"]), (0, []), value)

    def test_new_archive_review_outcomes(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        body = ("# 01: A\n\n**Effort:** core\n**Check:** Run.\n**Blocked by:** None\n"
                "\n## Progress\n\nCheck after: passed\n%s\n")
        cases = (("", "archived without a Review record"),
                 ("Review: blocked (base abcdef)", "archived with Review: blocked"),
                 ("Review: skipped", "Review: skipped needs a reason"),
                 ("Review: waived", "Review: waived needs a reason"),
                 ("Review: maybe (base abcdef)", "invalid Review outcome 'maybe'"))
        for review, message in cases:
            self.p.write(".workflow/done/core/01-a.md", body % review)
            code, data = self.p.validate()
            self.assertEqual(code, 2, review)
            self.assertIssue(data, message)
        # The last Review line wins; an earlier blocked record stops mattering.
        self.p.write(".workflow/done/core/01-a.md",
                     body % "Review: blocked (base abcdef)\nReview: PASS (base abcdef)")
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        # skipped with a reason is accepted.
        self.p.write(".workflow/done/core/01-a.md",
                     body % "Review: skipped — reviewer subagent unavailable")
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

    def test_new_archive_base_commit_and_status(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        body = ("# 01: A\n\n**Effort:** core\n**Blocked by:** None\n**Check:** Run.\n"
                "%s\n## Progress\n\nCheck after: passed\nReview: pass (base abcdef)\n")
        self.p.write(".workflow/done/core/01-a.md", body % "**Base commit:** <commit-sha>\n")
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "archived with a placeholder Base commit")
        self.p.write(".workflow/done/core/01-a.md", body % "**Status:** active\n")
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "archived task still has a Status")
        # A real Base commit and no Status pass; a missing one is not a placeholder.
        self.p.write(".workflow/done/core/01-a.md",
                     body % ("**Base commit:** " + self.head_short() + "\n"))
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        self.p.write(".workflow/done/core/01-a.md", body % "")
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

    def test_new_spike_archive_needs_findings(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        body = ("# 01: A\n\n**Effort:** core\n**Task type:** spike\n"
                "**Check:** Run.\n**Blocked by:** None\n")
        self.p.write(".workflow/done/core/01-a.md", body)
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "spike archived without ## Findings")
        # A spike needs findings instead of a Check after record.
        self.p.write(".workflow/done/core/01-a.md", body + "\n## Findings\n\nThe idea holds.\n")
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

    def test_committed_archive_is_not_rejudged(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.p.write(".workflow/done/core/00-old.md",
                     "# 00: Old\n\n**Effort:** core\n**Check:** Run.\n"
                     "**Blocked by:** None\n\n- [ ] never finished\n")
        self.commit_all("history")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

    def test_spec_done_with_an_open_task(self):
        self.p.write(".workflow/specs/core.md", "# Spec: core\n\n**Status:** done\n")
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "specs/core.md says done but core/01 is still open")
        issue = [i for i in data["issues"] if "still open" in i["message"]][0]
        self.assertEqual((issue["file"], issue["line"]), (".workflow/specs/core.md", 3))
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        self.p.write(".workflow/done/core/01-a.md",
                     "# 01: A\n\n**Effort:** core\n**Check:** Run.\n**Blocked by:** None\n"
                     "\n## Progress\n\nCheck after: ran on the final code\n"
                     "Review: pass (base abcdef)\n")
        code, data = self.p.validate()
        self.assertNotIn("still open", " ".join(self.messages(data)))
        self.assertEqual(code, 0)

    def test_spec_done_needs_acceptance(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write("README.md", "root\n")
        self.commit_all("base")
        self.p.write(".workflow/specs/core.md", "# Spec: core\n\n**Status:** done\n")
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "specs/core.md is marked done without a recorded acceptance")
        closeout = ".workflow/done/core/closeout.md"
        self.p.write(closeout, "# Closeout\n\n- **Accepted:** 2026-10-01 by Ada\n")
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        # Every reopening needs a fresh acceptance.
        self.p.write(closeout, "# Closeout\n\n- **Accepted:** 2026-10-01 by Ada\n\n"
                               "## Reopened\n\nA bug surfaced.\n")
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "without a recorded acceptance")
        self.p.write(closeout, "# Closeout\n\n- **Accepted:** 2026-10-01 by Ada\n\n"
                               "## Reopened\n\nA bug surfaced.\n\n"
                               "**Accepted:** 2026-10-05 by Ada\n")
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        self.p.write(closeout, "# Closeout\n\n- **Accepted:** 2026-10-01 by Ada\n\n"
                               "## Reopened 2026-10-05\n\nAnother fix.\n")
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.p.write(closeout, "# Closeout\n\n- **Accepted:** 2026-10-01 by Ada\n\n"
                               "## Reopened 2026-10-05\n\nAnother fix.\n\n"
                               "**Accepted:** 2026-10-06 by Ada\n")
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        # A spec already done in HEAD is history, not this change's claim.
        self.commit_all("close")
        os.remove(os.path.join(self.p.root, closeout))
        code, data = self.p.validate()
        self.assertNotIn("without a recorded acceptance", " ".join(self.messages(data)))

    def test_check_after_real_field_vs_misleading(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))

        base_body = "# 01: A\n\n**Effort:** core\n**Check:** Run.\n**Blocked by:** None\n"
        review = "\nReview: pass (base abcdef)\n"
        missing = "archived without a Check after or Check waived record"

        # Misleading: substring in prose
        self.p.write(".workflow/done/core/01-a.md",
                     base_body + "\n## Progress\n\nWe will check after deployment." + review)
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, missing)

        # Misleading: substring in another field
        self.p.write(".workflow/done/core/01-a.md",
                     base_body + "\n## Progress\n\nNotes: check after deploy" + review)
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, missing)

        # Misleading: Check after outside ## Progress
        self.p.write(".workflow/done/core/01-a.md",
                     base_body + "\n## Notes\n\nCheck after: ran tests" + review)
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, missing)

        # Misleading: empty Check after without continuation
        self.p.write(".workflow/done/core/01-a.md",
                     base_body + "\n## Progress\n\nCheck after:\n\nOther: field" + review)
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, missing)

        # Misleading: a Check after inside a code fence does not count.
        self.p.write(".workflow/done/core/01-a.md",
                     base_body + "\n## Progress\n\n```\nCheck after: ran tests\n```" + review)
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, missing)

        # Valid: plain field
        self.p.write(".workflow/done/core/01-a.md",
                     base_body + "\n## Progress\n\nCheck after: `true` passes" + review)
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

        # Valid: bold field
        self.p.write(".workflow/done/core/01-a.md",
                     base_body + "\n## Progress\n\n**Check after:** ran tests" + review)
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

        # Valid: bulleted bold field
        self.p.write(".workflow/done/core/01-a.md",
                     base_body + "\n## Progress\n\n- **Check after:** ran tests" + review)
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

        # Valid: multiline continuation
        self.p.write(".workflow/done/core/01-a.md",
                     base_body + "\n## Progress\n\nCheck after:\n  ran test suite on final code"
                     + review)
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

    def test_historical_audit_mode(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/specs/core.md", "# Spec: core\n\n**Status:** done\n")
        self.p.write(".workflow/done/core/00-old.md",
                     "# 00: Old\n\n**Effort:** core\n**Check:** Run.\n"
                     "**Blocked by:** None\n\n## Progress\n\n- [ ] unfinished\nCheck after: ok\n")
        self.commit_all("legacy-history")

        # Normal validate ignores committed historical archives and already-done specs
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

        # Strict validate alone does not break old repositories
        strict_code, strict_data = self.p.validate("--strict")
        self.assertEqual((strict_code, strict_data["issues"]), (0, []))

        # Audit mode catches historical archive unticked items and missing spec acceptance
        audit_code, audit_data = self.p.validate("--audit")
        self.assertEqual(audit_code, 2)
        self.assertIssue(audit_data, "archived with an unticked item: unfinished")
        self.assertIssue(audit_data, "specs/core.md is marked done without a recorded acceptance")

    def test_partially_staged_metadata(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.git("add", ".workflow/decisions.md")
        # Stage a valid task file
        valid_content = task("01", "Start", "core", check="pytest", blocked="None")
        self.p.write(".workflow/tasks/core/01-task.md", valid_content)
        self.git("add", ".workflow/tasks/core/01-task.md")

        # Dirty worktree: corrupt the task file without staging
        corrupt_content = "# 01: Start\n\n**Effort:** core\n**Blocked by:** None\n"
        with open(os.path.join(self.p.root, ".workflow/tasks/core/01-task.md"), "w") as fh:
            fh.write(corrupt_content)

        # Worktree validation catches the missing Check field
        wt_code, wt_data = self.p.validate()
        self.assertEqual(wt_code, 2)
        self.assertIssue(wt_data, "missing or empty required Check field")

        # Staged validation verifies index content and passes
        staged_code, staged_data = self.p.validate("--staged")
        self.assertEqual((staged_code, staged_data["issues"]), (0, []))

        # Now stage the corrupt file, but fix it in the dirty worktree
        self.git("add", ".workflow/tasks/core/01-task.md")
        with open(os.path.join(self.p.root, ".workflow/tasks/core/01-task.md"), "w") as fh:
            fh.write(valid_content)

        # Worktree sees the fix, but staged validation catches the staged error
        wt_code2, wt_data2 = self.p.validate()
        self.assertEqual((wt_code2, wt_data2["issues"]), (0, []))

        staged_code2, staged_data2 = self.p.validate("--staged")
        self.assertEqual(staged_code2, 2)
        self.assertIssue(staged_data2, "missing or empty required Check field")

    def test_standards_placeholder_warning(self):
        self.p.write(".workflow/standards.md",
                     "# Standards\n\n<TODO: install command>\n<direct | local-merge | pr>\n")
        code, data = self.p.validate()
        self.assertEqual(code, 1)
        self.assertIssue(data, "standards.md contains unfilled placeholder", "WARNING")

        strict_code, _ = self.p.validate("--strict")
        self.assertEqual(strict_code, 2)

        # After removing placeholders, no warning
        self.p.write(".workflow/standards.md",
                     "# Standards\n\nRun: npm test\nLanding: direct\n")
        clean_code, clean_data = self.p.validate()
        self.assertEqual((clean_code, clean_data["issues"]), (0, []))

    def test_oversized_standards_and_task_file_warn(self):
        self.p.write(".workflow/standards.md",
                     "\n".join("line %d" % n for n in range(1, 82)) + "\n")
        # Large ## Progress (>60 non-empty lines) and a >25-line fenced code block warn.
        self.p.write(".workflow/tasks/core/01-a.md",
                     task("01", "A", "core",
                          extra="## Progress\n\n" + "log line\n" * 61))
        self.p.write(".workflow/tasks/core/02-b.md",
                     task("02", "B", "core",
                          extra="## Progress\n\n```sh\n" + "echo line\n" * 26 + "```\n"))
        # Large (>20 KB) spec/checklist/CJK body above a concise ## Progress has zero warnings.
        big_spec = "## Context\n\n" + ("这是详细的任务需求说明与验收清单。\n" * 400)
        self.p.write(".workflow/tasks/core/03-c.md",
                     task("03", "C", "core", extra=big_spec + "\n## Progress\n\nCurrent state ok.\n"))
        code, data = self.p.validate()
        self.assertEqual((code, data["errors"]), (1, 0), data["issues"])
        self.assertIssue(data, "standards.md is 81 lines; keep it under one screen (80 lines)",
                         "WARNING")
        self.assertIssue(data, "## Progress is 61 non-empty lines", "WARNING")
        self.assertIssue(data, "## Progress contains a 26-line code block; move logs to the Evidence directory",
                         "WARNING")
        self.assertEqual(len(data["issues"]), 3, data["issues"])
        # A single >25-line fence alone does not double-warn as section length.
        self.p.write(".workflow/tasks/core/02-b.md",
                     task("02", "B", "core",
                          extra="## Progress\n\n```sh\n" + "echo line\n" * 70 + "```\n"))
        self.p.write(".workflow/standards.md",
                     "\n".join("line %d" % n for n in range(1, 81)) + "\n")
        self.p.write(".workflow/tasks/core/01-a.md",
                     task("01", "A", "core", extra="## Progress\n\n" + "log line\n" * 60))
        code, data = self.p.validate()
        self.assertEqual((code, data["errors"], len(data["issues"])), (1, 0, 1), data["issues"])
        self.assertIssue(data, "## Progress contains a 70-line code block", "WARNING")
        # At thresholds (80 lines standards, 60 lines Progress, 25-line fence) and on done/ files: 0 warnings.
        self.p.write(".workflow/tasks/core/02-b.md",
                     task("02", "B", "core",
                          extra="## Progress\n\n```sh\n" + "echo line\n" * 25 + "```\n"))
        self.p.write(".workflow/done/core/04-d.md",
                     task("04", "D", "core",
                          extra="## Progress\n\n```sh\n" + "echo line\n" * 40 + "```\n" + "log\n" * 80))
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))
        # Over 8000 chars in ## Progress also warns even if <= 60 lines.
        self.p.write(".workflow/tasks/core/01-a.md",
                     task("01", "A", "core", extra="## Progress\n\n" + ("x" * 8001) + "\n"))
        code, data = self.p.validate()
        self.assertEqual(code, 1)
        self.assertIssue(data, "non-empty lines (8001 chars); ## Progress holds current state, not a log",
                         "WARNING")
    def test_symlink_outside_root_ignored(self):
        outside_dir = tempfile.mkdtemp(prefix="wf-outside-")
        try:
            outside_task = os.path.join(outside_dir, "99-outside.md")
            with open(outside_task, "w") as fh:
                fh.write(task("99", "Outside", "core"))
            symlink_path = os.path.join(self.p.root, ".workflow", "tasks", "core", "99-outside.md")
            os.makedirs(os.path.dirname(symlink_path), exist_ok=True)
            os.symlink(outside_task, symlink_path)

            self.p.write(".workflow/tasks/core/01-inside.md", task("01", "Inside", "core"))

            code, data = self.p.validate()
            self.assertEqual(data["tasks"], 1)
            self.assertEqual([i["file"] for i in data["issues"]], [])
        finally:
            shutil.rmtree(outside_dir, ignore_errors=True)


    def test_review_pass_requires_detail_and_rejects_self_review(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        os.remove(os.path.join(self.p.root, ".workflow/tasks/core/01-a.md"))
        body = ("# 01: A\n\n**Effort:** core\n**Check:** Run.\n**Blocked by:** None\n"
                "\n## Progress\n\nCheck after: passed\n%s\n")
        for bad in ("Review: pass", "Review: pass —"):
            self.p.write(".workflow/done/core/01-a.md", body % bad)
            code, data = self.p.validate()
            self.assertEqual(code, 2, bad)
            self.assertIssue(data, "Review: pass needs a base commit or reviewer detail")
        for self_rev in (
            "Review: pass (self-review)",
            "Review: pass (Self-Reviewed by author)",
            "Review: pass (self reviewing)",
            "Review: pass (自审)",
            "Review: pass (自我审查)",
        ):
            self.p.write(".workflow/done/core/01-a.md", body % self_rev)
            code, data = self.p.validate()
            self.assertEqual(code, 2, self_rev)
            self.assertIssue(data, "self-review does not satisfy Review: pass")
        for good in ("Review: pass (base abcdef)", "Review: pass (base abcdef, reviewer r1)"):
            self.p.write(".workflow/done/core/01-a.md", body % good)
            code, data = self.p.validate()
            self.assertEqual((code, data["issues"]), (0, []), good)

    def test_check_temp_output_warning(self):
        self.p.write(".workflow/tasks/core/01-tee.md",
                     task("01", "Tee", "core", check="pytest | tee /tmp/out.log"))
        self.p.write(".workflow/tasks/core/02-redir.md",
                     task("02", "Redir", "core", check="pytest >/var/tmp/out.log 2>&1"))
        self.p.write(".workflow/tasks/core/03-env.md",
                     task("03", "Env", "core", check="HOME=/tmp/iso TMPDIR=$(mktemp -d /tmp/wf.XXXX) pytest"))
        self.p.write(".workflow/done/core/04-done.md",
                     task("04", "Done", "core", check="pytest > /tmp/old.log",
                          extra="## Progress\n\nCheck after: passed\nReview: pass (base abcdef)\n"))
        code, data = self.p.validate()
        self.assertEqual((code, data["errors"], data["warnings"]), (1, 0, 2), data["issues"])
        files = sorted(i["file"] for i in data["issues"])
        self.assertEqual(files, [".workflow/tasks/core/01-tee.md", ".workflow/tasks/core/02-redir.md"])
        for issue in data["issues"]:
            self.assertEqual(issue["message"], "Check writes output to a temporary path")

    def test_base_branch_not_checked_on_done_files(self):
        self.p.write(".workflow/tasks/core/01-open.md",
                     task("01", "Open", "core", extra="**Base branch:** deleted-branch\n"))
        self.p.write(".workflow/done/core/02-done.md",
                     task("02", "Done", "core",
                          extra="**Base branch:** deleted-branch\n\n## Progress\n\nCheck after: ok\nReview: pass (base abcdef)\n"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertEqual(len(data["issues"]), 1, data["issues"])
        self.assertEqual(data["issues"][0]["file"], ".workflow/tasks/core/01-open.md")
        self.assertIssue(data, "invalid Base branch 'deleted-branch'")

    def test_spec_and_task_effort_blockers_validation(self):
        self.p.write(".workflow/specs/upstream.md", "# Spec: upstream\n\n**Status:** in progress\n")
        self.p.write(".workflow/specs/core.md",
                     "# Spec: core\n\n**Status:** proposed\n**Blocked by:** upstream, upstream/01\n")
        self.p.write(".workflow/tasks/upstream/01-up.md", task("01", "Up", "upstream"))
        self.p.write(".workflow/tasks/core/01-a.md",
                     task("01", "A", "core", blocked="effort:upstream"))
        code, data = self.p.validate()
        self.assertEqual((code, data["issues"]), (0, []))

        # Malformed bare number on spec, self-dependency, orphaned effort, and cycle.
        self.p.write(".workflow/specs/a.md",
                     "# Spec: a\n\n**Status:** in progress\n**Blocked by:** b\n")
        self.p.write(".workflow/specs/b.md",
                     "# Spec: b\n\n**Status:** in progress\n**Blocked by:** a, b, missing-effort\n")
        self.p.write(".workflow/specs/malformed.md",
                     "# Spec: malformed\n\n**Status:** proposed\n**Blocked by:** 01\n")
        self.p.write(".workflow/tasks/core/02-self.md",
                     task("02", "Self", "core", blocked="effort:core, effort:ghost"))
        code, data = self.p.validate()
        self.assertEqual(code, 2)
        self.assertIssue(data, "malformed blocker '01'")
        self.assertIssue(data, "spec cannot be blocked by its own effort 'b'")
        self.assertIssue(data, "orphaned effort blocker 'missing-effort'")
        self.assertIssue(data, "circular spec dependency: a -> b -> a")
        self.assertIssue(data, "task cannot be blocked by its own effort 'core'")
        self.assertIssue(data, "orphaned effort blocker 'effort:ghost'")

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

    def test_flat_archived_blocker_uses_effort_field(self):
        self.p.write(".workflow/done/01-done.md", task("01", "Done", "core"))
        self.p.write(".workflow/tasks/core/02-a.md", task("02", "A", "core", blocked="01"))
        data = self.p.next()
        self.assertEqual([t["number"] for t in data["ready_tasks"]], [2])
        self.assertEqual((data["ready_count"], data["task_count"], data["blocked_count"]), (1, 1, 0))

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
        self.assertIn("(malformed Blocked by field)", deps)
        self.assertEqual([(t["task"], t["status"], t["branch"]) for t in data["in_progress"]],
                         [("core/04", "blocked", None)])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Needs replanning (Status: blocked; flow-break amend):\n  core/04 C (this working tree)", text)

    def test_started_tasks_are_not_ready(self):
        # Status in this tree: active, paused and blocked tasks are listed, never ready.
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core", extra="**Status:** active\n"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", extra="**Status:** paused\n"))
        self.p.write(".workflow/tasks/core/03-c.md", task("03", "C", "core"))
        data = self.p.next()
        self.assertEqual([t["number"] for t in data["ready_tasks"]], [3])
        self.assertEqual([(t["task"], t["status"]) for t in data["in_progress"]],
                         [("core/02", "paused"), ("core/01", "active")])
        text = self.p.run("next", "--no-color").stdout
        self.assertLess(text.index("Paused"), text.index("Ready tasks"))
        self.assertNotIn("Goal: (not specified)", text)

    def test_task_branches_show_claims_pauses_and_blocks(self):
        for number, slug in (("01", "a"), ("02", "b"), ("03", "c"), ("04", "d"), ("05", "e")):
            self.p.write(".workflow/tasks/core/%s-%s.md" % (number, slug), task(number, slug.upper(), "core"))
        self.commit_all("plan")
        main = subprocess.run(["git", "-C", self.p.root, "symbolic-ref", "--short", "HEAD"],
                              stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
        # 01 paused and 02 blocked on their branches; 03 claimed with no Status yet.
        for number, slug, extra in (("01", "a", "**Status:** paused\n"), ("02", "b", "**Status:** blocked\n"),
                                    ("03", "c", "")):
            self.git("checkout", "-q", "-b", "core/%s-%s" % (number, slug), main)
            if extra:
                self.p.write(".workflow/tasks/core/%s-%s.md" % (number, slug),
                             task(number, slug.upper(), "core", extra=extra))
                self.commit_all("state")
        # 04 finished on its branch (archived there) but not landed.
        self.git("checkout", "-q", "-b", "core/04-d", main)
        self.git("mv", ".workflow/tasks/core/04-d.md", ".workflow/tasks/core/04-moved.md")
        os.makedirs(os.path.join(self.p.root, ".workflow/done/core"), exist_ok=True)
        self.git("mv", ".workflow/tasks/core/04-moved.md", ".workflow/done/core/04-d.md")
        self.commit_all("archive")
        # A remote-only branch counts too (teammate's claim under pr).
        self.git("checkout", "-q", main)
        self.git("update-ref", "refs/remotes/origin/core/05-e", "HEAD")
        data = self.p.next()
        self.assertEqual(data["ready_tasks"], [])
        got = [(t["task"], t["status"], t["branch"]) for t in data["in_progress"]]
        self.assertEqual(got, [("core/01", "paused", "core/01-a"), ("core/02", "blocked", "core/02-b"),
                               ("core/03", "active", "core/03-c"), ("core/05", "active", "core/05-e"),
                               ("core/04", "finished", "core/04-d")])
        # On a task's own branch, the working tree is the source and the branch isn't listed twice.
        self.git("checkout", "-q", "core/03-c")
        data = self.p.next()
        self.assertEqual([t["number"] for t in data["ready_tasks"]], [3])
        self.assertNotIn("core/03", [t["task"] for t in data["in_progress"]])

    def test_archive_on_a_branch_not_named_for_the_task(self):
        # An integration branch carries the archive; the task is finished, not in progress.
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core"))
        self.commit_all("plan")
        main = subprocess.run(["git", "-C", self.p.root, "symbolic-ref", "--short", "HEAD"],
                              stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
        self.git("checkout", "-q", "-b", "core/09-integration", main)
        os.makedirs(os.path.join(self.p.root, ".workflow/done/core"), exist_ok=True)
        self.git("mv", ".workflow/tasks/core/01-a.md", ".workflow/done/core/01-a.md")
        self.commit_all("archive 01 on the integration branch")
        self.git("checkout", "-q", main)
        data = self.p.next()
        self.assertEqual([t["number"] for t in data["ready_tasks"]], [2])
        self.assertEqual([(t["task"], t["status"], t["branch"]) for t in data["in_progress"]],
                         [("core/01", "finished", "core/09-integration")])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Finished on a branch, not landed yet:\n"
                      "  core/01 A (branch core/09-integration)", text)

    def test_archive_wins_over_a_newer_branch_for_the_same_task(self):
        # Two branches name one task; the newer one has no archive and must not mask the other.
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        main = subprocess.run(["git", "-C", self.p.root, "symbolic-ref", "--short", "HEAD"],
                              stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
        self.git("checkout", "-q", "-b", "core/01-archive", main)
        os.makedirs(os.path.join(self.p.root, ".workflow/done/core"), exist_ok=True)
        self.git("mv", ".workflow/tasks/core/01-a.md", ".workflow/done/core/01-a.md")
        self.commit_all("archive 01")
        self.git("checkout", "-q", "-b", "core/01-stale", main)
        self.git("commit", "-q", "--allow-empty", "-m", "stale slice branch")
        self.git("checkout", "-q", main)
        data = self.p.next()
        self.assertEqual(data["ready_tasks"], [])
        self.assertEqual([(t["task"], t["status"], t["branch"]) for t in data["in_progress"]],
                         [("core/01", "finished", "core/01-archive")])

    def test_branch_of_a_landed_task_is_ignored(self):
        self.p.write(".workflow/done/core/01-a.md", task("01", "A", "core"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", blocked="01"))
        self.commit_all("landed")
        self.git("branch", "core/01-a")
        data = self.p.next()
        self.assertEqual(([t["number"] for t in data["ready_tasks"]], data["in_progress"]), ([2], []))

    def test_stacked_tasks_and_finished_blocker_branches(self):
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", blocked="01"))
        self.commit_all("plan")
        main = subprocess.run(["git", "-C", self.p.root, "symbolic-ref", "--short", "HEAD"],
                              stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
        self.git("checkout", "-q", "-b", "core/01-a", main)
        os.makedirs(os.path.join(self.p.root, ".workflow/done/core"), exist_ok=True)
        self.git("mv", ".workflow/tasks/core/01-a.md", ".workflow/done/core/01-a.md")
        self.commit_all("archive 01 on branch")
        self.git("checkout", "-q", main)
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Stackable under pr (blockers finished on branch): core/02 (on core/01-a)", text)
        # Once Base branch is recorded on task 02, next treats 01 as satisfied on that branch.
        self.p.write(".workflow/tasks/core/02-b.md",
                     task("02", "B", "core", blocked="01", extra="**Base branch:** core/01-a\n"))
        data = self.p.next()
        self.assertEqual([t["number"] for t in data["ready_tasks"]], [2])

    def test_tree_header_names_the_tree_and_main_distance(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core", extra="**Status:** active\n"))
        self.commit_all("plan")
        self.git("checkout", "-q", "-b", "core/01-a")
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core"))
        self.commit_all("branch work")
        branch_head = self.head_short()
        self.git("checkout", "-q", "main")
        self.p.write(".workflow/tasks/core/03-c.md", task("03", "C", "core"))
        self.commit_all("main work")
        self.git("checkout", "-q", "core/01-a")
        data = self.p.next()
        self.assertEqual(data["tree"], {"branch": "core/01-a", "head": branch_head,
                                        "main": "main", "behind_main": 1})
        text = self.p.run("next", "--no-color").stdout
        self.assertTrue(text.startswith(
            "Reading core/01-a (%s); main is 1 commit(s) ahead.\n" % branch_head), text)
        self.git("checkout", "-q", "--detach")
        text = self.p.run("next", "--no-color").stdout
        self.assertTrue(text.startswith(
            "Reading detached HEAD (%s); main is 1 commit(s) ahead.\n" % branch_head), text)
        self.git("checkout", "-q", "-b", "topic", "main")
        data = self.p.next()
        self.assertEqual(data["tree"]["behind_main"], 0)
        self.assertTrue(self.p.run("next").stdout.startswith(
            "Reading topic (%s).\n" % data["tree"]["head"]))
        self.git("checkout", "-q", "main")
        self.assertFalse(self.p.run("next").stdout.startswith("Reading "))
        self.assertEqual(self.p.next()["tree"],
                         {"branch": "main", "head": self.head_short(), "main": "main",
                          "behind_main": 0})

    def test_landed_on_main_is_reported_and_unblocks(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", blocked="01"))
        self.commit_all("plan")
        self.git("checkout", "-q", "-b", "work")
        self.git("checkout", "-q", "main")
        os.makedirs(os.path.join(self.p.root, ".workflow/done/core"), exist_ok=True)
        self.git("mv", ".workflow/tasks/core/01-a.md", ".workflow/done/core/01-a.md")
        self.commit_all("land 01")
        self.git("checkout", "-q", "work")
        data = self.p.next()
        self.assertEqual([t["number"] for t in data["ready_tasks"]], [2])
        self.assertEqual([(t["task"], t["status"], t["branch"]) for t in data["in_progress"]],
                         [("core/01", "landed", "main")])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Landed on main, still open in this tree (merge main into this branch):\n"
                      "  core/01 A (branch main)", text)
        self.assertNotIn("Finished on a branch", text)

    def test_integration_branch_scoping(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/specs/core.md", textwrap.dedent("""\
            # Spec: core

            **Status:** in progress
            **Integration branch:** core/integration
            """))
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", blocked="01"))
        self.commit_all("plan")
        self.git("checkout", "-q", "-b", "core/integration")
        os.makedirs(os.path.join(self.p.root, ".workflow/done/core"), exist_ok=True)
        self.git("mv", ".workflow/tasks/core/01-a.md", ".workflow/done/core/01-a.md")
        self.commit_all("archive 01 on the integration branch")

        # On main the effort is being worked elsewhere: hidden, with one summary line.
        self.git("checkout", "-q", "main")
        data = self.p.next()
        self.assertEqual(data["integrating"], [{"effort": "core", "branch": "core/integration",
                                                "worktree": None, "archived": 1, "open": 1}])
        self.assertEqual((data["ready_tasks"], data["task_count"], data["blocked_count"]), ([], 0, 0))
        self.assertEqual(data["in_progress"], [])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Integrating on another branch (run next there):\n"
                      "  core on core/integration: 1 archived, 1 open", text)
        self.git("checkout", "-q", "-b", "core/02-b", "main")
        data = self.p.next()
        self.assertEqual(data["integrating"], [])
        self.assertEqual([t["number"] for t in data["ready_tasks"]], [2])
        self.assertEqual([(t["task"], t["status"], t["branch"]) for t in data["in_progress"]],
                         [("core/01", "landed", "core/integration")])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Landed on core/integration, still open in this tree "
                      "(merge core/integration into this branch):", text)
        self.assertNotIn("Finished on a branch", text)

        # On the integration branch itself the effort is local work, not an integration elsewhere.
        self.git("checkout", "-q", "core/integration")
        data = self.p.next()
        self.assertEqual(data["integrating"], [])
        self.assertEqual(data["ready_tasks"], [])
        self.assertEqual([(t["task"], t["status"], t["branch"]) for t in data["in_progress"]],
                         [("core/02", "active", "core/02-b")])

    def test_duplicate_claims_are_named_last(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core"))
        self.commit_all("plan")
        self.git("branch", "core/01-first")
        self.git("branch", "core/01-second")
        self.git("update-ref", "refs/remotes/origin/core/01-first", "HEAD")
        data = self.p.next()
        self.assertEqual(data["duplicate_claims"],
                         [{"task": "core/01", "branches": ["core/01-first", "core/01-second"]}])
        text = self.p.run("next", "--no-color").stdout
        self.assertTrue(text.rstrip().endswith(
            "Several branches claim one task (keep one; rename retries to attempt/<effort>-<NN>): "
            "core/01 (2)"), text)
        # One claim plus a remote copy of the same name is not a duplicate.
        self.git("branch", "-D", "core/01-second")
        self.git("update-ref", "-d", "refs/remotes/origin/core/01-first")
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core"))
        self.commit_all("more")
        self.git("branch", "core/02-b")
        self.git("update-ref", "refs/remotes/origin/core/02-b", "HEAD")
        self.assertEqual(self.p.next()["duplicate_claims"], [])

    def test_no_ready_tasks_and_no_tasks(self):
        text = self.p.run("next").stdout
        self.assertIn("No tasks found.", text)
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "A", "core", blocked="02"))
        self.p.write(".workflow/tasks/core/02-b.md", task("02", "B", "core", blocked="01"))
        text = self.p.run("next").stdout
        self.assertIn("No ready tasks.", text)
        self.assertIn("Waiting on dependencies: 2 task(s); top blockers: core/01 (1), core/02 (1)", text)
        data = self.p.next()
        self.assertEqual(sorted(data), ["blocked_count", "blockers", "duplicate_claims",
                                        "file_overlaps", "in_progress", "integrating",
                                        "open_research", "ready_count", "ready_tasks",
                                        "ready_to_close", "resource_overlaps",
                                        "specs_without_tasks", "stale_worktrees",
                                        "task_count", "tree", "unarchived"])

    def test_missing_workflow(self):
        shutil.rmtree(os.path.join(self.p.root, ".workflow"))
        self.assertEqual(self.p.run("next").returncode, 1)


    def test_effort_filter_and_all_flag(self):
        self.p.write(".workflow/done/beta/01-done.md", task("01", "Beta base", "beta"))
        for n in range(1, 7):
            blocked = "beta/01" if n == 1 else "None"
            self.p.write(".workflow/tasks/alpha/%02d-t.md" % n,
                         task("%02d" % n, "Alpha %d" % n, "alpha", blocked=blocked))
        self.p.write(".workflow/tasks/beta/02-t.md", task("02", "Beta 2", "beta"))

        capped = json.loads(self.p.run("next", "--format", "json").stdout)
        self.assertEqual(capped["ready_count"], 7)
        self.assertEqual(len(capped["ready_tasks"]), 5)

        full = json.loads(self.p.run("next", "--all", "--format", "json").stdout)
        self.assertEqual(len(full["ready_tasks"]), 7)
        text_all = self.p.run("next", "--all", "--no-color").stdout
        self.assertIn("Ready tasks (7):", text_all)
        self.assertIn("7) alpha/06", text_all)

        scoped = json.loads(self.p.run("next", "--effort", "alpha", "--all", "--format", "json").stdout)
        self.assertEqual(scoped["task_count"], 6)
        self.assertEqual([t["task"] for t in scoped["ready_tasks"]],
                         ["alpha/%02d" % n for n in range(1, 7)])

        for bad in (["next", "--effort"], ["next", "--effort="], ["next", "--effort", "Bad_Slug"]):
            self.assertEqual(self.p.run(*bad).returncode, 2, bad)

    def test_ready_metadata_and_file_overlaps(self):
        self.p.write(".workflow/tasks/core/01-api-dir.md",
                     task("01", "API dir", "core", extra="**Files:** src/api, README.md\n"))
        self.p.write(".workflow/tasks/core/02-api-child.md",
                     task("02", "API child", "core", extra="**Files:** `src/api/users.py`, `src/db/*.sql`\n"))
        self.p.write(".workflow/tasks/core/03-db-file.md",
                     task("03", "DB file", "core", extra="- **Files:** src/db/schema.sql\n  README.md\n"))
        self.p.write(".workflow/tasks/core/04-prose.md",
                     task("04", "Spike prose", "core",
                          extra="**Files:** throwaway gateway on a spike branch.\n"))
        self.p.write(".workflow/tasks/core/05-mixed.md",
                     task("05", "Mixed formats", "core",
                          extra="**Files:** `src/api/auth.py`, src/db/pool.py and .gitignore\n"))
        self.p.write(".workflow/tasks/core/06-prose-backtick.md",
                     task("06", "Quoted in prose", "core",
                          extra="**Files:** Update `src/db/pool.py` plus `README.md` for pooling\n"))
        data = json.loads(self.p.run("next", "--all", "--format", "json").stdout)
        by_ref = {t["task"]: t for t in data["ready_tasks"]}
        self.assertEqual(by_ref["core/01"]["path"], ".workflow/tasks/core/01-api-dir.md")
        self.assertEqual(by_ref["core/01"]["branch"], "core/01-api-dir")
        self.assertEqual(by_ref["core/01"]["files"], ["src/api", "README.md"])
        self.assertEqual(by_ref["core/02"]["files"], ["src/api/users.py", "src/db"])
        self.assertEqual(by_ref["core/03"]["files"], ["src/db/schema.sql", "README.md"])
        self.assertEqual(by_ref["core/04"]["files"], [])
        self.assertEqual(by_ref["core/05"]["files"], ["src/api/auth.py", "src/db/pool.py", ".gitignore"])
        self.assertEqual(by_ref["core/06"]["files"], ["src/db/pool.py", "README.md"])
        self.assertEqual(data["file_overlaps"], [
            {"path": "src/db", "tasks": ["core/02", "core/03", "core/05", "core/06"]},
            {"path": "README.md", "tasks": ["core/01", "core/03", "core/06"]},
            {"path": "src/api", "tasks": ["core/01", "core/02", "core/05"]},
            {"path": "src/db/pool.py", "tasks": ["core/05", "core/06"]},
        ])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Shared files across ready tasks (serialize or coordinate): "
                      "src/db (core/02, core/03, core/05, core/06)", text)

    def test_reopened_task_ignores_merged_ancestor_branches_and_utf8_blobs(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/tasks/core/01-a.md", task("01", "初始任务", "core"))
        self.commit_all("plan")
        # Complete and archive core/01 on a task branch, keep remote & release refs, merge to main.
        self.git("checkout", "-q", "-b", "core/01-a")
        os.makedirs(os.path.join(self.p.root, ".workflow/done/core"), exist_ok=True)
        self.git("mv", ".workflow/tasks/core/01-a.md", ".workflow/done/core/01-a.md")
        self.commit_all("archive 01")
        self.git("update-ref", "refs/remotes/origin/core/01-a", "HEAD")
        self.git("branch", "release/v1", "HEAD")
        self.git("checkout", "-q", "main")
        self.git("merge", "-q", "--ff-only", "core/01-a")
        self.git("branch", "-D", "core/01-a")
        # Later reopen core/01 on main while stale origin/core/01-a and release/v1 still point to the old archive.
        os.makedirs(os.path.join(self.p.root, ".workflow/tasks/core"), exist_ok=True)
        self.git("mv", ".workflow/done/core/01-a.md", ".workflow/tasks/core/01-a.md")
        self.commit_all("reopen 01")

        # Also create a live UTF-8 paused branch for core/02 to verify binary cat-file --batch decoding.
        self.p.write(".workflow/tasks/core/02-utf8.md", task("02", "中文多字节标题", "core"))
        self.commit_all("add 02")
        self.git("checkout", "-q", "-b", "core/02-utf8")
        self.p.write(".workflow/tasks/core/02-utf8.md",
                     task("02", "中文多字节标题 — 暂停备注", "core", extra="**Status:** paused\n"))
        self.commit_all("pause 02 with utf8")
        self.git("checkout", "-q", "main")

        data = self.p.next()
        self.assertEqual([t["task"] for t in data["ready_tasks"]], ["core/01"])
        self.assertEqual([(t["task"], t["status"], t["branch"]) for t in data["in_progress"]],
                         [("core/02", "paused", "core/02-utf8")])
        self.assertEqual(data["duplicate_claims"], [])
    def test_next_brief_idle_handoff_and_active(self):
        idle = self.p.run("next", "--brief")
        self.assertEqual((idle.returncode, idle.stdout), (0, ""))

        self.p.write(".workflow/HANDOFF.md", "# Handoff\nNext: finish spec.\n")
        with_handoff = self.p.run("next", "--brief", "--no-color")
        self.assertIn(".workflow/HANDOFF.md present", with_handoff.stdout)
        self.assertNotIn("Pulse:", with_handoff.stdout)
        os.remove(os.path.join(self.p.root, ".workflow/HANDOFF.md"))

        self.p.write(".workflow/tasks/core/01-a.md",
                     task("01", "A", "core", extra="**Files:** src/shared.py\n"))
        self.p.write(".workflow/tasks/core/02-b.md",
                     task("02", "B", "core", extra="**Files:** src/shared.py\n"))
        self.p.write(".workflow/tasks/core/03-c.md",
                     task("03", "C", "core", extra="**Status:** paused\n"))
        brief = self.p.run("next", "--effort", "core", "--brief", "--no-color").stdout
        self.assertIn("Started: core/03 [paused]", brief)
        self.assertIn("Ready (2): core/01, core/02", brief)
        self.assertIn("Overlaps: src/shared.py (core/01+core/02)", brief)
        self.assertNotIn("Pulse:", brief)

        self.p.write(".workflow/research/auth-flow.md",
                     "# Research: Auth flow\n\n## Open questions\n- [ ] OIDC vs SAML?\n"
                     "- [ ] Session lifetime?\n")
        self.p.write(".workflow/research/settled.md",
                     "# Research: Settled\n\n## Open questions\n- [x] Done.\n")
        self.p.write(".workflow/research/nested/auth.md",
                     "# Research: Nested\n\n## Open questions\n- [ ] Not scanned.\n")
        next_all = json.loads(self.p.run("next", "--format", "json").stdout)
        self.assertEqual(next_all["open_research"],
                         [{"path": ".workflow/research/auth-flow.md", "slug": "auth-flow",
                           "title": "Auth flow", "open": 2}])
        self.assertNotIn("open_maps", next_all)
        next_scoped = json.loads(self.p.run("next", "--effort", "core", "--format", "json").stdout)
        self.assertEqual(next_scoped.get("open_research", []), [])
        next_text = self.p.run("next", "--no-color").stdout
        self.assertIn("Open research questions (continue with flow-grill):", next_text)
        self.assertIn(".workflow/research/auth-flow.md — Auth flow (2 open)", next_text)
        brief_text = self.p.run("next", "--brief", "--no-color").stdout
        self.assertIn("Research: .workflow/research/auth-flow.md (continue with flow-grill)",
                      brief_text)

    def test_flat_done_tree_git_parsing(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/done/01-done.md", task("01", "Done", "core"))
        self.commit_all("commit flat done")

        self.git("checkout", "-b", "feature")
        self.p.write(".workflow/tasks/core/02-next.md", task("02", "Next", "core", blocked="01"))

        data = self.p.next()
        self.assertEqual([t["number"] for t in data["ready_tasks"]], [2])
        self.assertEqual(data["ready_count"], 1)

    def test_brief_format_json_rejected(self):
        proc = self.p.run("next", "--brief", "--format", "json")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("Error: --brief cannot be combined with --format json", proc.stderr)
        self.assertEqual(proc.stdout, "")

        proc2 = self.p.run("next", "--format=json", "--brief")
        self.assertEqual(proc2.returncode, 2)
        self.assertIn("Error: --brief cannot be combined with --format json", proc2.stderr)

    def test_open_research_sections_text_and_json(self):
        self.p.write(".workflow/research/audit.md",
                     "# Research: Auth audit\n\n## Open questions\n\n- [ ] A\n- [ ] B\n- [x] C\n\n"
                     "## Notes\n\n- [ ] Not a question.\n")
        self.p.write(".workflow/research/settled.md",
                     "# Research: Settled\n\n## Open questions\n\n- [x] Done\n")
        self.p.write(".workflow/research/no-heading.md", "# Research: Plain\n\n- [ ] Top level\n")
        self.p.write(".workflow/research/sub/nested.md",
                     "# Research: Nested\n\n## Open questions\n\n- [ ] Hidden\n")
        self.p.write(".workflow/research/untitled.md", "## Open questions\n\n- [ ] No title\n")
        json_out = self.p.next()
        self.assertEqual(json_out["open_research"],
                         [{"path": ".workflow/research/audit.md", "slug": "audit",
                           "title": "Auth audit", "open": 2},
                          {"path": ".workflow/research/untitled.md", "slug": "untitled",
                           "title": "untitled", "open": 1}])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Open research questions (continue with flow-grill):", text)
        self.assertIn(".workflow/research/audit.md — Auth audit (2 open)", text)
        brief = self.p.run("next", "--brief", "--no-color").stdout
        self.assertEqual(brief.strip(),
                         "Research: .workflow/research/audit.md, .workflow/research/untitled.md "
                         "(continue with flow-grill)")
        scoped = json.loads(self.p.run("next", "--effort", "core", "--format", "json").stdout)
        self.assertNotIn("open_research", scoped)
        self.assertEqual(self.p.run("next", "--effort", "core", "--brief").stdout, "")

    def test_unarchived_tasks_are_not_ready(self):
        self.p.write(".workflow/tasks/core/01-done.md",
                     task("01", "Done", "core", extra="- [x] one\n- [x] two\n"))
        self.p.write(".workflow/tasks/core/02-open.md",
                     task("02", "Open", "core", extra="- [x] one\n- [ ] two\n"))
        self.p.write(".workflow/tasks/core/03-empty.md", task("03", "Empty", "core"))
        self.p.write(".workflow/tasks/core/04-started.md",
                     task("04", "Started", "core",
                          extra="**Status:** active\n- [x] one\n"))
        data = self.p.next()
        self.assertEqual(data["unarchived"],
                         [{"task": "core/01", "title": "Done"},
                          {"task": "core/04", "title": "Started"}])
        ready_refs = [t["task"] for t in data["ready_tasks"]]
        self.assertEqual(ready_refs, ["core/02", "core/03"])
        self.assertNotIn("core/01", ready_refs)
        self.assertNotIn("core/04", ready_refs)
        self.assertEqual([t["task"] for t in data["in_progress"]], ["core/04"])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Checklist complete, not archived "
                      "(record proof, then workflow task archive):\n  core/01 Done", text)
        brief = self.p.run("next", "--brief", "--no-color").stdout
        self.assertIn("Unarchived: core/01, core/04", brief)
        scoped = json.loads(self.p.run("next", "--effort", "core", "--format", "json").stdout)
        self.assertEqual(scoped["unarchived"], data["unarchived"])

    def test_ready_to_close_and_specs_without_tasks(self):
        self.p.write(".workflow/specs/closed.md", "# Spec: closed\n\n**Status:** in progress\n")
        self.p.write(".workflow/done/closed/01-a.md",
                     task("01", "A", "closed", extra="## Progress\n\nCheck after: ok\n"
                          "Review: pass (base abcdef)\n"))
        self.p.write(".workflow/specs/finished.md", "# Spec: finished\n\n**Status:** done\n")
        self.p.write(".workflow/done/finished/01-b.md", task("01", "B", "finished"))
        self.p.write(".workflow/specs/unplanned.md", "# Spec: unplanned\n\n**Status:** proposed\n")
        self.p.write(".workflow/specs/unplanned-later.md",
                     "# Spec: later\n\n**Status:** in progress\n")
        self.p.write(".workflow/specs/busy.md", "# Spec: busy\n\n**Status:** in progress\n")
        self.p.write(".workflow/tasks/busy/01-d.md", task("01", "D", "busy"))
        data = self.p.next()
        self.assertEqual(data["ready_to_close"], ["closed"])
        self.assertEqual(data["specs_without_tasks"], ["unplanned", "unplanned-later"])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Ready to close (flow-close <effort>): closed\n", text)
        self.assertIn("Specs without tasks (flow-break): unplanned, unplanned-later\n", text)
        brief = self.p.run("next", "--brief", "--no-color").stdout
        self.assertIn("Close: closed", brief)
        self.assertIn("Unplanned specs: unplanned, unplanned-later", brief)
        scoped = json.loads(self.p.run("next", "--effort", "busy", "--format", "json").stdout)
        self.assertEqual((scoped["ready_to_close"], scoped["specs_without_tasks"]), ([], []))
        # A spec integrating on another branch is not ready to close in this tree.
        self.p.write(".workflow/specs/elsewhere.md",
                     "# Spec: elsewhere\n\n**Status:** in progress\n"
                     "**Integration branch:** elsewhere/integration\n")
        self.p.write(".workflow/done/elsewhere/01-e.md", task("01", "E", "elsewhere"))
        self.commit_all("plan")
        self.git("branch", "elsewhere/integration")
        data = self.p.next()
        self.assertEqual([i["effort"] for i in data["integrating"]], ["elsewhere"])
        self.assertEqual(data["ready_to_close"], ["closed"])
        self.assertEqual(data["specs_without_tasks"], ["unplanned", "unplanned-later"])

    def test_resource_overlaps(self):
        self.p.write(".workflow/tasks/core/01-board.md",
                     task("01", "Board", "core", extra="**Resources:** Board, `device`\n"))
        self.p.write(".workflow/tasks/core/02-device.md",
                     task("02", "Device", "core", extra="**Resources:** `DEVICE`\n"))
        self.p.write(".workflow/tasks/core/03-none.md",
                     task("03", "None", "core", extra="**Resources:** None\n"))
        self.p.write(".workflow/tasks/core/04-none-list.md",
                     task("04", "None list", "core", extra="**Resources:** n/a\n"))
        data = self.p.next()
        self.assertEqual(data["resource_overlaps"],
                         [{"resource": "device", "tasks": ["core/01", "core/02"]}])
        self.assertEqual([t["resources"] for t in data["ready_tasks"]],
                         [["board", "device"], ["device"], [], []])
        text = self.p.run("next", "--no-color").stdout
        self.assertIn("Shared resources across ready tasks (run one at a time): "
                      "device (core/01, core/02)", text)
        brief = self.p.run("next", "--brief", "--no-color").stdout
        self.assertIn("Resources: device (core/01+core/02)", brief)

    def test_stale_worktrees(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/specs/core.md",
                     "# Spec: core\n\n**Status:** in progress\n"
                     "**Integration branch:** core/integration\n")
        self.commit_all("base")
        outside = tempfile.mkdtemp(prefix="wf-wt-")
        merged = os.path.join(outside, "merged")
        ahead = os.path.join(outside, "ahead")
        detached = os.path.join(outside, "detached")
        try:
            self.git("worktree", "add", "-q", "-b", "feature-merged", merged)
            subprocess.run(["git", "-C", merged, "-c", "user.email=t@t", "-c", "user.name=t",
                            "commit", "-q", "--allow-empty", "-m", "feature"],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.git("merge", "-q", "--no-ff", "feature-merged", "-m", "merge feature")
            self.git("worktree", "add", "-q", "-b", "feature-ahead", ahead)
            subprocess.run(["git", "-C", ahead, "-c", "user.email=t@t", "-c", "user.name=t",
                            "commit", "-q", "--allow-empty", "-m", "ahead"],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.git("worktree", "add", "-q", "--detach", detached)
            # An integration target branch that already merged a task branch with its own work.
            self.git("worktree", "add", "-q", "-b", "task/one", os.path.join(self.p.root, "task", "one-wt"))
            subprocess.run(["git", "-C", os.path.join(self.p.root, "task", "one-wt"),
                            "-c", "user.email=t@t", "-c", "user.name=t",
                            "commit", "-q", "--allow-empty", "-m", "task one"],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.git("checkout", "-q", "-b", "core/integration")
            self.git("merge", "-q", "--no-ff", "task/one", "-m", "merge one")
            self.git("checkout", "-q", "main")
            data = self.p.next()
            by_branch = {i["branch"]: i for i in data["stale_worktrees"]}
            self.assertEqual(sorted(by_branch), ["feature-merged", "task/one"])
            self.assertEqual(by_branch["feature-merged"]["merged_into"], "main")
            self.assertEqual(by_branch["task/one"]["merged_into"], "core/integration")
            self.assertNotIn("feature-ahead", by_branch)
            text = self.p.run("next", "--no-color").stdout
            self.assertIn("Stale worktrees (branch already merged; git worktree remove <path>): ",
                          text)
            self.assertIn(by_branch["feature-merged"]["path"], text)
            self.assertIn(by_branch["task/one"]["path"], text)
            brief = self.p.run("next", "--brief", "--no-color").stdout
            self.assertIn("Stale worktrees: 2", brief)
            # --effort omits the tree-wide worktree section.
            scoped = json.loads(self.p.run("next", "--effort", "core", "--format", "json").stdout)
            self.assertNotIn("stale_worktrees", scoped)
        finally:
            self.git("worktree", "remove", "--force", merged)
            self.git("worktree", "remove", "--force", ahead)
            self.git("worktree", "remove", "--force", detached)
            self.git("worktree", "remove", "--force", os.path.join(self.p.root, "task", "one-wt"))
            shutil.rmtree(outside, ignore_errors=True)

    def test_stale_worktrees_cap_and_all(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.commit_all("base")
        outside = tempfile.mkdtemp(prefix="wf-wt-")
        dirs = []
        base = self.head_short()
        try:
            for n in range(6):
                path = os.path.join(outside, "wt%d" % n)
                self.git("worktree", "add", "-q", "-b", "merged-%d" % n, path, base)
                subprocess.run(["git", "-C", path, "-c", "user.email=t@t", "-c", "user.name=t",
                                "commit", "-q", "--allow-empty", "-m", "work %d" % n],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.git("merge", "-q", "--no-ff", "merged-%d" % n, "-m", "merge %d" % n)
                dirs.append(path)
            data = self.p.next()
            self.assertEqual(len(data["stale_worktrees"]), 6)
            text = self.p.run("next", "--no-color").stdout
            self.assertIn("(+1 more)", text)
            all_text = self.p.run("next", "--all", "--no-color").stdout
            self.assertNotIn("(+1 more)", all_text)
        finally:
            for path in dirs:
                self.git("worktree", "remove", "--force", path)
            shutil.rmtree(outside, ignore_errors=True)


    def test_effort_blockers_queue_and_goal_dedup_and_delivers(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/specs/upstream.md",
                     "# Spec: upstream\n\n**Status:** in progress\n**Priority:** high\n\n"
                     "## What this is for\n\nUpstream goal.\n")
        self.p.write(".workflow/specs/downstream.md",
                     "# Spec: downstream\n\n**Status:** proposed\n**Priority:** normal\n"
                     "**Blocked by:** upstream\n\n## What this is for\n\nDownstream goal.\n")
        self.p.write(".workflow/tasks/upstream/01-u.md", task("01", "Up", "upstream"))
        self.p.write(".workflow/tasks/downstream/01-d1.md",
                     task("01", "D1", "downstream", extra="**Delivers:** First slice\n"))
        self.p.write(".workflow/tasks/downstream/02-d2.md",
                     task("02", "D2", "downstream"))
        # Also test task-level effort:<slug> blocker on a spec-less effort.
        self.p.write(".workflow/done/specless/01-s.md", task("01", "S", "specless"))
        self.p.write(".workflow/tasks/downstream/03-d3.md",
                     task("03", "D3", "downstream", blocked="effort:specless"))

        data = self.p.next()
        self.assertEqual([t["task"] for t in data["ready_tasks"]], ["upstream/01"])
        self.assertEqual(data["blocked_count"], 3)
        deps = {b["dependency"]: b for b in data["blockers"]}
        self.assertEqual(deps["upstream"]["count"], 3)

        # While upstream has an Integration branch checked out in a worktree, it stays unsatisfied
        # and integrating reports the worktree path.
        self.commit_all("plan")
        wt_dir = tempfile.mkdtemp(prefix="wf-int-")
        try:
            self.p.write(".workflow/specs/upstream.md",
                         "# Spec: upstream\n\n**Status:** done\n**Integration branch:** upstream/int\n")
            self.git("worktree", "add", "-q", "-b", "upstream/int", wt_dir)
            data2 = self.p.next()
            self.assertEqual(data2["integrating"][0]["worktree"], os.path.realpath(wt_dir))
            self.assertEqual(data2["ready_tasks"], [])
            text2 = self.p.run("next", "--no-color").stdout
            self.assertIn("upstream on upstream/int (%s):" % os.path.realpath(wt_dir), text2)
        finally:
            self.git("worktree", "remove", "--force", wt_dir)
            self.git("branch", "-D", "upstream/int")
            shutil.rmtree(wt_dir, ignore_errors=True)

        # Once upstream spec is done (and not integrating elsewhere), downstream tasks become ready.
        os.remove(os.path.join(self.p.root, ".workflow/tasks/upstream/01-u.md"))
        self.p.write(".workflow/done/upstream/01-u.md",
                     task("01", "Up", "upstream", extra="## Progress\n\nCheck after: ok\nReview: pass (base abcdef)\n"))
        self.p.write(".workflow/specs/upstream.md",
                     "# Spec: upstream\n\n**Status:** done\n**Priority:** high\n\n"
                     "## What this is for\n\nUpstream goal.\n")
        data3 = self.p.next()
        self.assertEqual([t["task"] for t in data3["ready_tasks"]],
                         ["downstream/01", "downstream/02", "downstream/03"])
        self.assertTrue(all(t["goal"] == "Downstream goal." for t in data3["ready_tasks"]))
        self.assertEqual(data3["ready_tasks"][0]["delivers"], "First slice")
        text3 = self.p.run("next", "--no-color").stdout
        self.assertEqual(text3.count("Goal: Downstream goal."), 1, text3)
        self.assertIn("Delivers: First slice", text3)

        # Scoped --effort downstream still checks upstream spec status.
        self.p.write(".workflow/specs/upstream.md",
                     "# Spec: upstream\n\n**Status:** in progress\n")
        scoped = json.loads(self.p.run("next", "--effort", "downstream", "--format", "json").stdout)
        self.assertEqual(scoped["ready_tasks"], [])
        self.assertEqual(scoped["blocked_count"], 3)

class TaskLifecycleTests(Base):
    def test_task_start_success(self):
        self.commit_all("initial commit")
        head = subprocess.run(["git", "-C", self.p.root, "rev-parse", "HEAD"],
                              stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()

        task_body = (
            "# 01: Start work\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** pytest\n\n"
            "<!-- custom comment -->\n"
            "## Context\n\n"
            "Preserved text body.\n"
        )
        self.p.write(".workflow/tasks/core/01-start.md", task_body)
        self.p.write(".workflow/specs/core.md",
                     "# Spec: core\n\n**Status:** proposed\n**Priority:** normal\n\n## What this is for\n\nGoal.\n")

        proc = self.p.run("task", "start", "core/01")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Started task core/01", proc.stdout)

        with open(os.path.join(self.p.root, ".workflow/tasks/core/01-start.md"), "r") as fh:
            content = fh.read()
        self.assertIn("**Base commit:** %s" % head, content)
        self.assertIn("**Status:** active", content)
        self.assertIn("<!-- custom comment -->", content)
        self.assertIn("Preserved text body.", content)

        with open(os.path.join(self.p.root, ".workflow/specs/core.md"), "r") as fh:
            spec_content = fh.read()
        self.assertIn("**Status:** in progress", spec_content)

        # Idempotent second run
        proc2 = self.p.run("task", "start", "core/01")
        self.assertEqual(proc2.returncode, 0)
        with open(os.path.join(self.p.root, ".workflow/tasks/core/01-start.md"), "r") as fh:
            content2 = fh.read()
        self.assertEqual(content2.count("Status:"), 1)
        self.assertEqual(content2.count("Base commit:"), 1)

    def test_task_start_checklist_items_do_not_make_fields_bulleted(self):
        self.commit_all("initial")
        task_body = (
            "# 01: Checklist first\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** pytest\n\n"
            "- [ ] write the code\n"
            "- [ ] run the tests\n\n"
            "## Context\n\n"
            "- a body bullet\n"
        )
        path = self.p.write(".workflow/tasks/core/01-check.md", task_body)
        proc = self.p.run("task", "start", "core/01")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        with open(path, "r") as fh:
            started = fh.read()
        self.assertIn("**Base commit:** ", started)
        self.assertIn("**Status:** active", started)
        self.assertNotIn("- **Base commit:**", started)
        self.assertNotIn("- **Status:** active", started)
        self.assertIn("- [ ] write the code", started)
        self.assertIn("- a body bullet", started)
        # Bulleted header fields still get bulleted inserts.
        bulleted = (
            "# 02: Bullet header\n\n"
            "- **Effort:** core\n"
            "- **Blocked by:** None\n"
            "- **Check:** pytest\n\n"
            "- [x] one\n"
        )
        path2 = self.p.write(".workflow/tasks/core/02-bullet.md", bulleted)
        proc2 = self.p.run("task", "start", "core/02")
        self.assertEqual(proc2.returncode, 0, proc2.stderr)
        with open(path2, "r") as fh:
            started2 = fh.read()
        self.assertIn("- **Base commit:** ", started2)
        self.assertIn("- **Status:** active", started2)

    def test_task_start_dirty_tree_warning(self):
        self.commit_all("initial")
        self.p.write(".workflow/tasks/core/01-start.md",
                     "# 01: Start work\n\n**Effort:** core\n**Blocked by:** None\n**Check:** pytest\n")
        proc = self.p.run("task", "start", "core/01")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Started task core/01", proc.stdout)
        # The new task file is under .workflow/, so nothing outside it is dirty yet.
        self.assertEqual(proc.stderr, "")
        self.p.write("src/app.py", "print('dirty')\n")
        self.p.write("README.md", "edited\n")
        self.p.write(".workflow/tasks/core/02-second.md",
                     "# 02: Second\n\n**Effort:** core\n**Blocked by:** None\n**Check:** pytest\n")
        proc2 = self.p.run("task", "start", "core/02")
        self.assertEqual(proc2.returncode, 0, proc2.stderr)
        self.assertIn("Warning: 2 uncommitted file(s) outside .workflow at Base commit; "
                      "flow-verify will review them as part of this task. Commit or stash "
                      "earlier work first.", proc2.stderr)
        self.assertIn("Started task core/02", proc2.stdout)

    def test_task_archive_prints_last_open_task_hint(self):
        self.commit_all("initial")
        self.p.write(".workflow/specs/core.md",
                     "# Spec: core\n\n**Status:** in progress\n**Priority:** normal\n")
        body = (
            "# 01: Only\n\n**Effort:** core\n**Blocked by:** None\n**Check:** echo ok\n"
            "**Base commit:** " + self.head_short() + "\n**Status:** active\n\n"
            "- [x] done\n\n## Progress\n\nCheck after: passed\nReview: pass (base abcdef)\n"
        )
        self.p.write(".workflow/tasks/core/01-only.md", body)
        proc = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Archived task core/01", proc.stdout)
        self.assertIn("Last open task of core: run flow-close core\n", proc.stdout)
        # No hint while another task stays open.
        for number, slug in (("02", "more"), ("03", "last")):
            self.p.write(".workflow/tasks/core/%s-%s.md" % (number, slug),
                         "# %s: Task\n\n**Effort:** core\n**Blocked by:** None\n"
                         "**Check:** echo ok\n**Status:** active\n\n- [x] done\n\n"
                         "## Progress\n\nCheck after: passed\nReview: pass (base abcdef)\n"
                         % number)
        proc2 = self.p.run("task", "archive", "core/02")
        self.assertEqual(proc2.returncode, 0, proc2.stderr)
        self.assertNotIn("flow-close", proc2.stdout)
        proc3 = self.p.run("task", "archive", "core/03")
        self.assertEqual(proc3.returncode, 0, proc3.stderr)
        self.assertIn("Last open task of core: run flow-close core\n", proc3.stdout)
        # No hint without a spec.
        os.remove(os.path.join(self.p.root, ".workflow/specs/core.md"))
        self.p.write(".workflow/tasks/core/04-last.md",
                     "# 04: Last\n\n**Effort:** core\n**Blocked by:** None\n**Check:** echo ok\n"
                     "**Status:** active\n\n- [x] done\n\n## Progress\n\nCheck after: passed\n"
                     "Review: pass (base abcdef)\n")
        proc4 = self.p.run("task", "archive", "core/04")
        self.assertEqual(proc4.returncode, 0, proc4.stderr)
        self.assertNotIn("flow-close", proc4.stdout)

    def test_task_start_no_head_error(self):
        # Brand new repo with no commits
        self.p.write(".workflow/tasks/core/01-start.md",
                     "# 01: Start work\n\n**Effort:** core\n**Blocked by:** None\n**Check:** pytest\n")
        proc = self.p.run("task", "start", "core/01")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("Error: cannot determine HEAD commit", proc.stderr)
        with open(os.path.join(self.p.root, ".workflow/tasks/core/01-start.md"), "r") as fh:
            content = fh.read()
        self.assertNotIn("Base commit:", content)
        self.assertNotIn("Status:", content)

    def test_task_start_resolution_variants_and_errors(self):
        self.commit_all("initial")
        self.p.write(".workflow/tasks/core/01-start.md",
                     "# 01: Start work\n\n**Effort:** core\n**Blocked by:** None\n**Check:** pytest\n")

        # By normalized number
        proc = self.p.run("task", "start", "core/1")
        self.assertEqual(proc.returncode, 0)

        # Nonexistent task
        proc_bad = self.p.run("task", "start", "core/99")
        self.assertEqual(proc_bad.returncode, 1)
        self.assertIn("task 'core/99' not found under .workflow/tasks", proc_bad.stderr)

        # Ambiguous bare number
        self.p.write(".workflow/tasks/api/01-api.md",
                     "# 01: Api work\n\n**Effort:** api\n**Blocked by:** None\n**Check:** pytest\n")
        proc_amb = self.p.run("task", "start", "01")
        self.assertEqual(proc_amb.returncode, 1)
        self.assertIn("ambiguous task reference '01'", proc_amb.stderr)

    def test_task_archive_success(self):
        self.commit_all("initial")
        task_body = (
            "# 01: Start work\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Base commit:** " + self.head_short() + "\n"
            "**Status:** active\n\n"
            "- [x] completed work item\n\n"
            "## Progress\n\n"
            "Check after: tests passed on live machine\n"
            "Review: pass (base abcdef)\n"
        )
        self.p.write(".workflow/tasks/core/01-start.md", task_body)

        proc = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Archived task core/01 to .workflow/done/core/01-start.md", proc.stdout)

        # Task file moved and status removed
        self.assertFalse(os.path.exists(os.path.join(self.p.root, ".workflow/tasks/core/01-start.md")))
        dest = os.path.join(self.p.root, ".workflow/done/core/01-start.md")
        self.assertTrue(os.path.isfile(dest))
        with open(dest, "r") as fh:
            content = fh.read()
        self.assertNotIn("Status:", content)
        self.assertIn("**Base commit:** " + self.head_short(), content)
        self.assertIn("- [x] completed work item", content)
        self.assertIn("Check after: tests passed on live machine", content)

        code, data = self.p.validate()
        self.assertEqual(code, 0)

    def test_task_archive_refuses_unticked_checkbox(self):
        self.commit_all("initial")
        task_body = (
            "# 01: Start work\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Status:** active\n\n"
            "- [ ] pending item\n\n"
            "## Progress\n\n"
            "Check after: ok\n"
            "Review: pass (base abcdef)\n"
        )
        src = self.p.write(".workflow/tasks/core/01-start.md", task_body)
        proc = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("archived with an unticked item: pending item", proc.stderr)
        self.assertTrue(os.path.isfile(src))
        self.assertFalse(os.path.exists(os.path.join(self.p.root, ".workflow/done/core/01-start.md")))

    def test_task_archive_refuses_missing_check_after(self):
        self.commit_all("initial")
        task_body = (
            "# 01: Start work\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Status:** active\n\n"
            "- [x] item\n\n"
            "## Progress\n\n"
            "Notes: ran manually\n"
        )
        src = self.p.write(".workflow/tasks/core/01-start.md", task_body)
        proc = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("archived without a Check after or Check waived record", proc.stderr)
        self.assertIn("archived without a Review record", proc.stderr)
        self.assertTrue(os.path.isfile(src))
        self.assertFalse(os.path.exists(os.path.join(self.p.root, ".workflow/done/core/01-start.md")))

    def test_task_archive_spike_requires_findings(self):
        self.commit_all("initial")
        task_body = (
            "# 01: Spike work\n\n"
            "**Effort:** core\n"
            "**Task type:** spike\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Status:** active\n\n"
            "- [x] explore options\n"
        )
        src = self.p.write(".workflow/tasks/core/01-spike.md", task_body)
        proc = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("spike archived without ## Findings", proc.stderr)

        # Adding Findings allows archive to succeed
        with open(src, "a") as fh:
            fh.write("\n## Findings\n\nApproach B is viable.\n")
        proc2 = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc2.returncode, 0, proc2.stderr)
        self.assertTrue(os.path.isfile(os.path.join(self.p.root, ".workflow/done/core/01-spike.md")))

    def test_task_archive_no_overwrite_existing_destination(self):
        self.commit_all("initial")
        dest = self.p.write(".workflow/done/core/01-start.md", "EXISTING_ARCHIVE_DATA\n")
        task_body = (
            "# 01: Start work\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Status:** active\n\n"
            "- [x] item\n\n"
            "## Progress\n\n"
            "Check after: ok\n"
            "Review: pass (base abcdef)\n"
        )
        src = self.p.write(".workflow/tasks/core/01-start.md", task_body)
        proc = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("destination file already exists", proc.stderr)

        with open(dest, "r") as fh:
            self.assertEqual(fh.read(), "EXISTING_ARCHIVE_DATA\n")
        self.assertTrue(os.path.isfile(src))

    def test_task_archive_atomic_rollback_on_validate_failure(self):
        self.commit_all("initial")
        self.p.write(".workflow/specs/core.md", "# Spec: core\n\n**Status:** done\n**Priority:** normal\n")
        # Duplicate Check metadata must make validation fail after the move.
        task_body = (
            "# 01: Start work\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Check:** duplicate command\n"
            "**Status:** active\n\n"
            "- [x] item\n\n"
            "## Progress\n\n"
            "Check after: ok\n"
            "Review: pass (base abcdef)\n"
        )
        src = self.p.write(".workflow/tasks/core/01-start.md", task_body)
        proc = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("validation failed after archiving task", proc.stderr)

        # Source file restored, destination cleaned up
        self.assertTrue(os.path.isfile(src))
        self.assertFalse(os.path.exists(os.path.join(self.p.root, ".workflow/done/mismatch/01-start.md")))
        self.assertFalse(os.path.exists(os.path.join(self.p.root, ".workflow/done/core/01-start.md")))

    def test_task_preserves_unrelated_content_and_metadata(self):
        self.commit_all("initial")
        complex_task = (
            "# 01: Complex task\n\n"
            "- **Effort:** core\n"
            "- **Blocked by:** None\n"
            "- **Check:** pytest\n"
            "- **Files:** src/core.py\n"
            "- **Read first:** docs/arch.md\n\n"
            "<!-- preserved HTML comment -->\n"
            "```python\n"
            "# Code fence that shouldn't be touched\n"
            "def foo():\n"
            "    Status = 'fake'\n"
            "```\n\n"
            "- [x] done check\n\n"
            "## Context\n\n"
            "Details about this complex task.\n\n"
            "## Progress\n\n"
            "Check after: passes 100%\n"
            "Review: pass (base abcdef)\n"
        )
        src = self.p.write(".workflow/tasks/core/01-complex.md", complex_task)
        proc = self.p.run("task", "start", "core/01")
        self.assertEqual(proc.returncode, 0)
        with open(src, "r") as fh:
            started = fh.read()
        self.assertIn("- **Base commit:**", started)
        self.assertIn("- **Status:** active", started)
        self.assertIn("- **Files:** src/core.py", started)
        self.assertIn("- **Read first:** docs/arch.md", started)
        self.assertIn("<!-- preserved HTML comment -->", started)
        self.assertIn("Status = 'fake'", started)
        self.assertIn("Details about this complex task.", started)

        proc_arch = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc_arch.returncode, 0, proc_arch.stderr)
        dest = os.path.join(self.p.root, ".workflow/done/core/01-complex.md")
        with open(dest, "r") as fh:
            archived = fh.read()
        self.assertNotIn("- **Status:**", archived)
        self.assertIn("- **Base commit:**", archived)
        self.assertIn("<!-- preserved HTML comment -->", archived)
        self.assertIn("Status = 'fake'", archived)
        self.assertIn("Details about this complex task.", archived)
        self.assertIn("Check after: passes 100%", archived)
        self.assertIn("Review: pass (base abcdef)", archived)

    def test_task_rejects_tasks_backup_and_symlink_escape(self):
        self.commit_all("initial")
        backup_content = (
            "# 01: Backup task\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
        )
        backup_path = self.p.write(".workflow/tasks-backup/01-backup.md", backup_content)

        # Direct path to tasks-backup must be rejected
        proc = self.p.run("task", "start", ".workflow/tasks-backup/01-backup.md")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("not under .workflow/tasks", proc.stderr)
        with open(backup_path, "r") as fh:
            self.assertEqual(fh.read(), backup_content)

        # Relative path variant
        proc_rel = self.p.run("task", "start", "tasks-backup/01-backup.md")
        self.assertEqual(proc_rel.returncode, 1)
        with open(backup_path, "r") as fh:
            self.assertEqual(fh.read(), backup_content)

        # Symlink inside tasks pointing outside tasks tree must be rejected
        outside_file = os.path.join(self.p.root, "outside.md")
        with open(outside_file, "w") as fh:
            fh.write(backup_content)
        symlink_path = os.path.join(self.p.root, ".workflow", "tasks", "core", "01-symlink.md")
        os.makedirs(os.path.dirname(symlink_path), exist_ok=True)
        os.symlink(outside_file, symlink_path)

        proc_sym = self.p.run("task", "start", "core/01")
        self.assertEqual(proc_sym.returncode, 1)
        self.assertIn("resolves outside .workflow/tasks", proc_sym.stderr)
        with open(outside_file, "r") as fh:
            self.assertEqual(fh.read(), backup_content)

    def test_task_rejects_flat_effort_traversal(self):
        self.commit_all("initial")
        outside_file = os.path.join(self.p.root, "outside.md")
        with open(outside_file, "w") as fh:
            fh.write("**Status:** proposed\n")

        escape_content = (
            "# 01: Escape task\n\n"
            "**Effort:** ../../../outside\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
        )
        task_path = self.p.write(".workflow/tasks/01-escape.md", escape_content)

        proc_start = self.p.run("task", "start", "01")
        self.assertEqual(proc_start.returncode, 1)
        self.assertIn("invalid effort slug", proc_start.stderr)

        # Neither the target outside file nor the task file was mutated
        with open(outside_file, "r") as fh:
            self.assertEqual(fh.read(), "**Status:** proposed\n")
        with open(task_path, "r") as fh:
            self.assertEqual(fh.read(), escape_content)

        # Archive also rejects traversal without mutating or moving
        proc_arch = self.p.run("task", "archive", "01")
        self.assertEqual(proc_arch.returncode, 1)
        self.assertIn("invalid effort slug", proc_arch.stderr)
        self.assertTrue(os.path.isfile(task_path))
        with open(outside_file, "r") as fh:
            self.assertEqual(fh.read(), "**Status:** proposed\n")

        os.remove(task_path)
        # Flat task with a valid effort works normally
        valid_flat = (
            "# 02: Valid flat task\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "- [x] item\n\n"
            "## Progress\n\n"
            "Check after: passed\n"
            "Review: pass (base abcdef)\n"
        )
        self.p.write(".workflow/tasks/02-valid.md", valid_flat)
        self.p.write(".workflow/specs/core.md",
                     "# Spec: core\n\n**Status:** proposed\n**Priority:** normal\n\n## What this is for\nGoal.\n")

        proc_ok = self.p.run("task", "start", "02")
        self.assertEqual(proc_ok.returncode, 0, proc_ok.stderr)
        with open(os.path.join(self.p.root, ".workflow/specs/core.md"), "r") as fh:
            self.assertIn("**Status:** in progress", fh.read())

        proc_arch_ok = self.p.run("task", "archive", "02")
        self.assertEqual(proc_arch_ok.returncode, 0, proc_arch_ok.stderr)
        self.assertTrue(os.path.isfile(os.path.join(self.p.root, ".workflow/done/core/02-valid.md")))

    def test_task_start_rejects_specs_symlink_escape_without_task_mutation(self):
        self.commit_all("initial")
        outside_spec = os.path.join(self.p.root, "outside_spec.md")
        with open(outside_spec, "w") as fh:
            fh.write("**Status:** proposed\n")

        task_content = (
            "# 01: Start work\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
        )
        task_path = self.p.write(".workflow/tasks/core/01-start.md", task_content)

        # 1. Spec file is a symlink resolving outside .workflow/specs
        spec_symlink = os.path.join(self.p.root, ".workflow", "specs", "core.md")
        os.makedirs(os.path.dirname(spec_symlink), exist_ok=True)
        os.symlink(outside_spec, spec_symlink)

        proc = self.p.run("task", "start", "core/01")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("resolves outside .workflow/specs", proc.stderr)

        # Outside spec untouched and task untouched
        with open(outside_spec, "r") as fh:
            self.assertEqual(fh.read(), "**Status:** proposed\n")
        with open(task_path, "r") as fh:
            self.assertEqual(fh.read(), task_content)

        # 2. .workflow/specs directory itself is a symlink resolving outside
        os.remove(spec_symlink)
        os.rmdir(os.path.dirname(spec_symlink))
        outside_specs_dir = os.path.join(self.p.root, "outside_specs")
        os.makedirs(outside_specs_dir, exist_ok=True)
        with open(os.path.join(outside_specs_dir, "core.md"), "w") as fh:
            fh.write("**Status:** proposed\n")
        os.symlink(outside_specs_dir, os.path.join(self.p.root, ".workflow", "specs"))

        proc2 = self.p.run("task", "start", "core/01")
        self.assertEqual(proc2.returncode, 1)
        self.assertIn("resolves outside .workflow", proc2.stderr)
        with open(os.path.join(outside_specs_dir, "core.md"), "r") as fh:
            self.assertEqual(fh.read(), "**Status:** proposed\n")
        with open(task_path, "r") as fh:
            self.assertEqual(fh.read(), task_content)

    def test_task_archive_rejects_done_symlink_escape_without_source_move(self):
        self.commit_all("initial")
        task_content = (
            "# 01: Done work\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Base commit:** " + self.head_short() + "\n"
            "**Status:** active\n\n"
            "- [x] completed\n\n"
            "## Progress\n\n"
            "Check after: ok\n"
            "Review: pass (base abcdef)\n"
        )
        task_path = self.p.write(".workflow/tasks/core/01-done.md", task_content)

        outside_done = os.path.join(self.p.root, "outside_done")
        os.makedirs(outside_done, exist_ok=True)
        done_core = os.path.join(self.p.root, ".workflow", "done", "core")
        os.makedirs(os.path.dirname(done_core), exist_ok=True)
        os.symlink(outside_done, done_core)

        proc = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("resolves outside .workflow/done", proc.stderr)

        # Source task preserved, no outside file created
        self.assertTrue(os.path.isfile(task_path))
        with open(task_path, "r") as fh:
            self.assertEqual(fh.read(), task_content)
        self.assertEqual(os.listdir(outside_done), [])

    def test_task_start_rollback_on_spec_update_failure(self):
        self.commit_all("initial")
        task_content = (
            "# 01: Start work\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
        )
        task_path = self.p.write(".workflow/tasks/core/01-start.md", task_content)
        spec_content = (
            "# Spec: core\n\n"
            "**Status:** proposed\n"
            "**Priority:** normal\n\n"
            "## What this is for\n\n"
            "Goal.\n"
        )
        spec_path = self.p.write(".workflow/specs/core.md", spec_content)

        # Make .workflow/specs directory read-only so atomic temp file replacement fails
        specs_dir = os.path.dirname(spec_path)
        os.chmod(specs_dir, 0o555)
        try:
            proc = self.p.run("task", "start", "core/01")
            self.assertEqual(proc.returncode, 1)
            self.assertIn("failed to update spec", proc.stderr)

            # Task must be rolled back to original content, not left partially active
            with open(task_path, "r") as fh:
                self.assertEqual(fh.read(), task_content)
            # Spec retains its old proposed status
            with open(spec_path, "r") as fh:
                self.assertEqual(fh.read(), spec_content)
        finally:
            os.chmod(specs_dir, 0o755)

    def test_task_archive_rejects_malformed_metadata_on_new_file_only(self):
        self.commit_all("initial")
        # Older archive in .workflow/done lacking required Check field (WARNING in validate)
        old_archive = (
            "# 00: Old archive\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "- [x] legacy item\n\n"
            "## Progress\n\n"
            "Check after: ok\n"
            "Review: pass (base abcdef)\n"
        )
        self.p.write(".workflow/done/core/00-old.md", old_archive)

        # 1. Valid new task archives successfully despite warning on older archive
        valid_content = (
            "# 01: Valid task\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Status:** active\n\n"
            "- [x] item\n\n"
            "## Progress\n\n"
            "Check after: ok\n"
            "Review: pass (base abcdef)\n"
        )
        self.p.write(".workflow/tasks/core/01-valid.md", valid_content)
        proc_ok = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc_ok.returncode, 0, proc_ok.stderr)
        self.assertTrue(os.path.isfile(os.path.join(self.p.root, ".workflow/done/core/01-valid.md")))

        # 2. Newly archived task lacking required Check field must be rejected
        bad_content = (
            "# 02: Bad task\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Status:** active\n\n"
            "- [x] item\n\n"
            "## Progress\n\n"
            "Check after: ok\n"
            "Review: pass (base abcdef)\n"
        )
        bad_path = self.p.write(".workflow/tasks/core/02-bad.md", bad_content)
        proc_bad = self.p.run("task", "archive", "core/02")
        self.assertEqual(proc_bad.returncode, 1)
        self.assertIn("validation failed after archiving task", proc_bad.stderr)
        self.assertIn("missing or empty required Check field", proc_bad.stderr)

        # Rollback: destination removed, source preserved
        self.assertTrue(os.path.isfile(bad_path))
        self.assertFalse(os.path.exists(os.path.join(self.p.root, ".workflow/done/core/02-bad.md")))

    def test_task_lifecycle_preserves_file_permissions(self):
        self.commit_all("initial")
        task_content = (
            "# 01: Perms task\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "- [x] done\n\n"
            "## Progress\n\n"
            "Check after: ok\n"
            "Review: pass (base abcdef)\n"
        )
        task_path = self.p.write(".workflow/tasks/core/01-perms.md", task_content)
        spec_content = (
            "# Spec: core\n\n"
            "**Status:** proposed\n"
            "**Priority:** normal\n\n"
            "## What this is for\n\n"
            "Goal.\n"
        )
        spec_path = self.p.write(".workflow/specs/core.md", spec_content)

        # Set 0644 mode explicitly
        os.chmod(task_path, 0o644)
        os.chmod(spec_path, 0o644)

        # Start task: both task file and spec file must retain 0644 (not drop to 0600)
        proc_start = self.p.run("task", "start", "core/01")
        self.assertEqual(proc_start.returncode, 0, proc_start.stderr)
        self.assertEqual(stat.S_IMODE(os.stat(task_path).st_mode), 0o644)
        self.assertEqual(stat.S_IMODE(os.stat(spec_path).st_mode), 0o644)

        # Archive task: archive destination must preserve source mode 0644
        proc_arch = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc_arch.returncode, 0, proc_arch.stderr)
        dest_path = os.path.join(self.p.root, ".workflow/done/core/01-perms.md")
        self.assertEqual(stat.S_IMODE(os.stat(dest_path).st_mode), 0o644)


    def test_task_archive_strips_base_branch_and_removes_empty_dir(self):
        self.commit_all("initial")
        self.git("branch", "blocker-branch")
        body = (
            "# 01: Base branch cleanup\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Base commit:** " + self.head_short() + "\n"
            "**Base branch:** blocker-branch\n"
            "**Status:** active\n\n"
            "- [x] done\n\n## Progress\n\nCheck after: ok\nReview: pass (base abcdef)\n"
        )
        src = self.p.write(".workflow/tasks/core/01-clean.md", body)
        proc = self.p.run("task", "archive", "core/01")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse(os.path.exists(os.path.dirname(src)))
        dest = os.path.join(self.p.root, ".workflow/done/core/01-clean.md")
        with open(dest, "r") as fh:
            archived = fh.read()
        self.assertNotIn("Base branch:", archived)
        self.assertNotIn("Status:", archived)

        # Rollback recreates the removed tasks/<effort>/ directory if validation fails.
        bad_body = (
            "# 02: Rollback dir\n\n"
            "**Effort:** core\n"
            "**Blocked by:** None\n"
            "**Check:** echo ok\n"
            "**Check:** dup\n"
            "**Status:** active\n\n"
            "- [x] done\n\n## Progress\n\nCheck after: ok\nReview: pass (base abcdef)\n"
        )
        bad_src = self.p.write(".workflow/tasks/core/02-bad.md", bad_body)
        proc_bad = self.p.run("task", "archive", "core/02")
        self.assertEqual(proc_bad.returncode, 1)
        self.assertTrue(os.path.isfile(bad_src))

    def test_task_land_modes_cleanup_and_guards(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.git("config", "user.email", "t@t")
        self.git("config", "user.name", "t")
        self.p.write(".workflow/specs/core.md", "# Spec: core\n\n**Status:** in progress\n")
        t1 = (
            "# 01: First task\n\n**Effort:** core\n**Blocked by:** None\n**Check:** echo ok\n"
            "- [x] done\n\n## Progress\n\nCheck after: ok\nReview: pass (base abcdef)\n"
        )
        t2 = (
            "# 02: Second task\n\n**Effort:** core\n**Blocked by:** None\n**Check:** echo ok\n"
            "- [x] done\n\n## Progress\n\nCheck after: ok\nReview: pass (base abcdef)\n"
        )
        self.p.write(".workflow/tasks/core/01-first.md", t1)
        self.p.write(".workflow/tasks/core/02-second.md", t2)
        self.commit_all("plan")

        outside = tempfile.mkdtemp(prefix="wf-land-")
        wt1 = os.path.join(outside, "wt1")
        wt2 = os.path.join(outside, "wt2")
        try:
            # Mode A: archive & commit in task worktree wt1, then land from wt1.
            self.git("worktree", "add", "-q", "-b", "core/01-first", wt1)
            proc_a = subprocess.run([sys.executable, CORE, "task", "archive", "core/01"], cwd=wt1,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            self.assertEqual(proc_a.returncode, 0, proc_a.stderr)
            subprocess.run(["git", "-C", wt1, "add", "-A"], check=True)
            subprocess.run(["git", "-C", wt1, "commit", "-qm", "finish 01"], check=True)
            # Dirty target worktree blocks landing.
            dirty_file = self.p.write("dirty.txt", "temp\n")
            proc_dirty = subprocess.run([sys.executable, CORE, "task", "land", "core/01"], cwd=wt1,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            self.assertEqual(proc_dirty.returncode, 1)
            self.assertIn("uncommitted changes", proc_dirty.stderr)
            os.remove(dirty_file)

            # Landing from inside wt1 with --cleanup merges onto main and keeps active wt1 with a note.
            proc_land1 = subprocess.run([sys.executable, CORE, "task", "land", "core/01", "--cleanup"], cwd=wt1,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            self.assertEqual(proc_land1.returncode, 0, proc_land1.stderr)
            self.assertIn("Landed task core/01 onto main", proc_land1.stdout)
            self.assertIn("Note: kept active worktree", proc_land1.stderr)
            self.assertTrue(os.path.isfile(os.path.join(self.p.root, ".workflow/done/core/01-first.md")))
            # --no-ff merge commit has 2 parents
            parents = subprocess.run(["git", "-C", self.p.root, "rev-list", "--parents", "-n", "1", "HEAD"],
                                     stdout=subprocess.PIPE, universal_newlines=True).stdout.split()
            self.assertEqual(len(parents), 3, parents)
            # Idempotent re-land
            proc_reland = subprocess.run([sys.executable, CORE, "task", "land", "core/01"], cwd=wt1,
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            self.assertEqual(proc_reland.returncode, 0, proc_reland.stderr)
            self.assertIn("already landed on main", proc_reland.stdout)
            self.git("worktree", "remove", "--force", wt1)
            self.git("branch", "-D", "core/01-first")

            # Mode B: branch created BEFORE main moved ahead -> target-moved-ahead rejection, then rebase & land with --cleanup.
            self.git("worktree", "add", "-q", "-b", "core/02-second", wt2, "main~1")
            proc_a2 = subprocess.run([sys.executable, CORE, "task", "archive", "core/02"], cwd=wt2,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            self.assertEqual(proc_a2.returncode, 0, proc_a2.stderr)
            subprocess.run(["git", "-C", wt2, "add", "-A"], check=True)
            subprocess.run(["git", "-C", wt2, "commit", "-qm", "finish 02"], check=True)

            # From main, land refuses because main moved ahead of core/02-second.
            proc_behind = self.p.run("task", "land", "core/02")
            self.assertEqual(proc_behind.returncode, 1)
            self.assertIn("has commits not in 'core/02-second'", proc_behind.stderr)

            # Rebase core/02-second onto main, then land from main with --cleanup.
            subprocess.run(["git", "-C", wt2, "rebase", "-q", "main"], check=True)
            proc_land2 = self.p.run("task", "land", "core/02", "--cleanup")
            self.assertEqual(proc_land2.returncode, 0, proc_land2.stderr)
            self.assertIn("Landed task core/02 onto main", proc_land2.stdout)
            self.assertFalse(os.path.exists(wt2))
            branches = subprocess.run(["git", "-C", self.p.root, "branch", "--list", "core/02-second"],
                                      stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
            self.assertEqual(branches, "")
            self.assertTrue(os.path.isfile(os.path.join(self.p.root, ".workflow/done/core/02-second.md")))
        finally:
            if os.path.exists(wt1):
                subprocess.run(["git", "-C", self.p.root, "worktree", "remove", "--force", wt1],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if os.path.exists(wt2):
                subprocess.run(["git", "-C", self.p.root, "worktree", "remove", "--force", wt2],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            shutil.rmtree(outside, ignore_errors=True)

    def test_task_land_non_checked_out_integration_branch(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.git("config", "user.email", "t@t")
        self.git("config", "user.name", "t")
        self.p.write(".workflow/specs/feat.md",
                     "# Spec: feat\n\n**Status:** in progress\n**Integration branch:** feat/int\n")
        self.p.write(".workflow/tasks/feat/01-item.md",
                     "# 01: Item\n\n**Effort:** feat\n**Blocked by:** None\n**Check:** echo ok\n"
                     "- [x] done\n\n## Progress\n\nCheck after: ok\nReview: pass (base abcdef)\n")
        self.commit_all("plan")
        self.git("branch", "feat/int")
        self.git("checkout", "-q", "-b", "feat/01-item", "feat/int")
        proc_a = self.p.run("task", "archive", "feat/01")
        self.assertEqual(proc_a.returncode, 0, proc_a.stderr)
        self.commit_all("finish feat/01")
        # feat/int is not checked out in any worktree -> uses commit-tree + update-ref
        proc_land = self.p.run("task", "land", "feat/01")
        self.assertEqual(proc_land.returncode, 0, proc_land.stderr)
        self.assertIn("Landed task feat/01 onto feat/int", proc_land.stdout)
        done_blob = subprocess.run(["git", "-C", self.p.root, "ls-tree", "--name-only", "feat/int",
                                    ".workflow/done/feat/01-item.md"],
                                   stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
        self.assertEqual(done_blob, ".workflow/done/feat/01-item.md")
        parents = subprocess.run(["git", "-C", self.p.root, "rev-list", "--parents", "-n", "1", "feat/int"],
                                 stdout=subprocess.PIPE, universal_newlines=True).stdout.split()
        self.assertEqual(len(parents), 3, parents)

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

    def test_many_branches_batch_fast(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.p.write(".workflow/done/core/01-done.md", task("01", "Done", "core"))
        self.p.write(".workflow/tasks/core/02-ready.md", task("02", "Ready", "core", blocked="01"))
        self.commit_all("seed")
        head = subprocess.run(["git", "-C", self.p.root, "rev-parse", "HEAD"],
                              stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
        refs_input = "".join(
            "create refs/remotes/origin/stale-feature-%03d %s\n" % (i, head) for i in range(200)
        )
        subprocess.run(["git", "-C", self.p.root, "update-ref", "--stdin"],
                       input=refs_input, universal_newlines=True, check=True)
        start = time.time()
        proc = self.p.run("next", "--format", "json")
        elapsed = time.time() - start
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertLess(elapsed, 2.0, "next with 200 branches took %.2fs" % elapsed)
        self.assertEqual([t["task"] for t in json.loads(proc.stdout)["ready_tasks"]], ["core/02"])


if __name__ == "__main__":
    unittest.main()
