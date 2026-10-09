#!/usr/bin/env bash
# Deterministic tasks tests, also invoked by tests/cli-tests.sh workflow-tasks.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 - "$KIT" <<'PY'
import itertools
import json
import os
from pathlib import Path
import pty
import shutil
import subprocess
import sys
import tempfile
import unittest

kit = Path(sys.argv[1])


class TasksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="workflow-tasks-test-")
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.tasks = self.root / ".workflow" / "tasks"
        shutil.copytree(kit / "tests" / "fixtures" / "tasks", self.tasks)
        done = self.root / ".workflow" / "done" / "old-effort"
        done.mkdir(parents=True)
        (done / "7-completed.md").write_text("# 7: Completed\n")

    def tearDown(self):
        self.temp.cleanup()

    def run_tasks(self, *flags, cwd=None, wrapper=False):
        command = [str(kit / "bin" / ("workflow" if wrapper else "workflow-tasks"))]
        if wrapper:
            command.append("tasks")
        return subprocess.run(command + list(flags), cwd=cwd or self.root, capture_output=True, text=True)

    def data(self, *flags):
        result = self.run_tasks(*flags, "--format", "json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        return json.loads(result.stdout)

    def test_help_and_wrapper(self):
        for flag in ("--help", "-h"):
            result = self.run_tasks(flag, wrapper=True)
            self.assertEqual(result.returncode, 0)
            self.assertIn("Examples:", result.stdout)
            self.assertIn("--no-color", result.stdout)

    def test_numeric_order_and_escaping(self):
        items = self.data()
        self.assertEqual([x["number"] for x in items], [1, 2, 3, 4, 5, 6, 7, 8, 10, None])
        self.assertEqual(items[2]["title"], 'Paused "quoted" task')
        self.assertTrue(all(isinstance(x["blocked"], bool) for x in items))
        self.assertTrue(all(x["file"].endswith(".md") for x in items))

    def test_missing_fields_defaults(self):
        items = {x["number"]: x for x in self.data()}
        for field in ("effort", "blocked_by", "status", "base_commit", "started"):
            self.assertEqual(items[2][field], "N/A")
        self.assertEqual(items[8]["title"], "N/A")
        result = self.run_tasks("--no-color")
        self.assertEqual(result.returncode, 0)
        self.assertIn("N/A", result.stdout)

    def test_dependencies(self):
        items = {x["number"]: x for x in self.data()}
        self.assertTrue(items[10]["blocked"])  # 01 matches integer 1 and bold metadata
        self.assertTrue(items[5]["blocked"])   # multiline cross-effort reference
        self.assertFalse(items[6]["blocked"]) # 0007 matches archived 7
        self.assertTrue(items[7]["blocked"])  # missing targets must not appear ready

    def test_malformed_warnings_have_file_context(self):
        result = self.run_tasks("--format", "json")
        self.assertEqual(result.returncode, 0)
        self.assertIn(str(self.tasks / "04-malformed.md"), result.stderr)
        self.assertIn("expected NN or effort/NN", result.stderr)
        self.assertIn(str(self.tasks / "07-orphan.md"), result.stderr)
        json.loads(result.stdout)  # Diagnostics never pollute stdout.

    def test_all_flag_combinations(self):
        for selection, status, effort, no_color, fmt in itertools.product(
                ([], ["--ready"], ["--blocked"]), ([], ["--status"]),
                ([], ["--effort", "core"]), ([], ["--no-color"]), ("text", "json")):
            flags = selection + status + effort + no_color + ["--format", fmt]
            with self.subTest(flags=flags):
                result = self.run_tasks(*flags)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("\033", result.stdout)
                if fmt == "json":
                    value = json.loads(result.stdout)
                    if status:
                        self.assertEqual(value["total"], value["ready"] + value["blocked"])
                    else:
                        if selection:
                            self.assertTrue(all(x["blocked"] == (selection == ["--blocked"]) for x in value))
                        if effort:
                            self.assertTrue(all(x["effort"] == "core" for x in value))

    def test_status_summary(self):
        self.assertEqual(self.data("--status"), {"total": 10, "ready": 4, "blocked": 6, "paused": 1})
        self.assertEqual(self.data("--status", "--effort", "api-v2"), {"total": 1, "ready": 1, "blocked": 0, "paused": 1})

    def test_empty_directory(self):
        shutil.rmtree(self.tasks)
        self.tasks.mkdir()
        result = self.run_tasks()
        self.assertEqual(result.returncode, 0)
        self.assertIn("No tasks found", result.stdout)
        self.assertEqual(self.data(), [])
        self.assertEqual(self.data("--status"), {"total": 0, "ready": 0, "blocked": 0, "paused": 0})

    def test_missing_workflow(self):
        shutil.rmtree(self.root / ".workflow")
        result = self.run_tasks()
        self.assertEqual(result.returncode, 0)
        self.assertIn("No tasks directory", result.stdout)
        self.assertIn(str(self.tasks), result.stdout)
        self.assertEqual(self.data(), [])
        self.assertEqual(self.data("--status")["total"], 0)

    def test_subdirectory_root(self):
        subdir = self.root / "src" / "deep"
        subdir.mkdir(parents=True)
        result = self.run_tasks("--format", "json", cwd=subdir, wrapper=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)), 10)

    def test_non_git_fallback(self):
        shutil.rmtree(self.root / ".git")
        result = self.run_tasks("--format", "json")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(json.loads(result.stdout)), 10)

    def test_usage_errors(self):
        for flags in (("--unknown",), ("--effort",), ("--effort", ""), ("--effort", "../outside"),
                      ("--format",), ("--format", "xml"), ("--blocked", "--ready"), ("--effort", "--ready")):
            with self.subTest(flags=flags):
                result = self.run_tasks(*flags)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("error", result.stderr.lower())

    def test_no_match(self):
        self.assertEqual(self.data("--effort", "unknown"), [])
        result = self.run_tasks("--effort", "unknown")
        self.assertEqual(result.returncode, 0)
        self.assertIn("No matching tasks", result.stdout)

    def test_invalid_task_path(self):
        shutil.rmtree(self.tasks)
        self.tasks.write_text("not a directory")
        result = self.run_tasks()
        self.assertEqual(result.returncode, 1)
        self.assertIn(str(self.tasks), result.stderr)
        self.assertEqual(result.stdout, "")

    def test_invalid_utf8(self):
        (self.tasks / "09-invalid.md").write_bytes(b"\xff\xfe")
        result = self.run_tasks("--format", "json")
        self.assertEqual(result.returncode, 1)
        self.assertIn("09-invalid.md", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_circular_dependencies(self):
        for number, blocker in ((11, 12), (12, 11)):
            (self.tasks / f"{number}-cycle.md").write_text(f"# {number}: Cycle\nEffort: core\nBlocked by: {blocker}\n")
        items = {x["number"]: x for x in self.data()}
        self.assertTrue(items[11]["blocked"])
        self.assertTrue(items[12]["blocked"])

    def test_effort_isolation(self):
        (self.tasks / "11-isolated.md").write_text("# 11: Isolated\nEffort: api-v2\nBlocked by: 1\n")
        items = {x["number"]: x for x in self.data()}
        self.assertTrue(items[11]["blocked"])

    def test_same_numbers_are_scoped_by_effort(self):
        for number, effort, blocker in ((1, "api", "None"), (2, "api", "01"), (1, "web", "None")):
            (self.tasks / f"{number:02d}-{effort}.md").write_text(
                f"# {number}: {effort}\nEffort: {effort}\nBlocked by: {blocker}\n")
        items = {(x["effort"], x["number"]): x for x in self.data()}
        self.assertFalse(items[("api", 1)]["blocked"])
        self.assertFalse(items[("web", 1)]["blocked"])
        self.assertTrue(items[("api", 2)]["blocked"])
        (self.tasks / "01-api.md").unlink()
        result = self.run_tasks("--format", "json", "--effort", "api")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("missing task api/01", result.stderr)
        self.assertTrue(json.loads(result.stdout)[0]["blocked"])

    def test_titles_are_rejected_in_blockers(self):
        (self.tasks / "11-title.md").write_text("# 11: Title\nEffort: core\nBlocked by: 01 Build API\n")
        result = self.run_tasks("--format", "json")
        self.assertEqual(result.returncode, 0)
        self.assertIn("expected NN or effort/NN", result.stderr)
        item = next(x for x in json.loads(result.stdout) if x["number"] == 11)
        self.assertTrue(item["blocked"])

    def test_metadata_examples_and_comments(self):
        (self.tasks / "11-example.md").write_text(
            "# 11: Real task\n<!-- Effort: wrong -->\n```markdown\nEffort: wrong\nBlocked by: 1\n```\n"
            "- **Effort:** api-v2\n- **Blocked by:** None\nStatus: active\n")
        task = next(x for x in self.data() if x["number"] == 11)
        self.assertEqual(task["effort"], "api-v2")
        self.assertFalse(task["blocked"])

    def test_blocker_continuations_stop_at_section_boundaries(self):
        for separator in ("\n", "- [ ] Checklist\n", "## Goal\n", "Files: source.py\n", "```text\nexample\n```\n"):
            with self.subTest(separator=separator):
                (self.tasks / "11-boundary.md").write_text(
                    "Task: Boundary task\nEffort: core\nBlocked by: None\n" + separator + "  01\nBase: not-started\n")
                task = next(x for x in self.data() if x["number"] == 11)
                self.assertEqual(task["title"], "Boundary task")
                self.assertEqual(task["base_commit"], "not-started")
                self.assertEqual(task["blocked_by"], "None")
                self.assertFalse(task["blocked"])


    def test_crlf(self):
        (self.tasks / "11-crlf.md").write_bytes(b"# 11: CRLF\r\nEffort: core\r\nBlocked by: None\r\n")
        self.assertFalse(next(x for x in self.data() if x["number"] == 11)["blocked"])

    def test_huge_malformed_number(self):
        (self.tasks / "11-huge.md").write_text("# 11: Huge\nEffort: core\nBlocked by: " + "9" * 5000 + "\n")
        result = self.run_tasks("--format", "json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertTrue(next(x for x in json.loads(result.stdout) if x["number"] == 11)["blocked"])

    def tty_output(self, *flags):
        master, slave = pty.openpty()
        process = subprocess.Popen([str(kit / "bin" / "workflow-tasks"), *flags], cwd=self.root,
                                   stdout=slave, stderr=subprocess.DEVNULL)
        os.close(slave)
        output = b""
        try:
            while True:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
        finally:
            os.close(master)
        self.assertEqual(process.wait(), 0)
        return output.decode()

    def test_tty_colors(self):
        self.assertIn("\033[31m●", self.tty_output("--blocked"))
        self.assertNotIn("\033", self.tty_output("--no-color"))
        self.assertIsInstance(json.loads(self.tty_output("--format", "json")), list)


unittest.main(argv=[sys.argv[0]], verbosity=2)
PY
