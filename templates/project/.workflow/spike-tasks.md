# Spike Tasks

A spike answers a question; code may be throwaway. Use it when the solution is unknown
and learning is the deliverable.
Use a spike to test a library/API, architecture, performance, or root cause of a
reproducible but unexplained bug (CONVENTIONS §8); the fix task is blocked by the spike.
Do not use one because a feature is hard (build it), requirements are unclear
(`flow-grill`), or to skip planning.
Use the regular task format (CONVENTIONS §2.1), plus:

```markdown
**Task type:** spike
**Question:** <what needs answering>
**Time box:** <what to stop after: one prototype, one benchmark run, N approaches tried>
```

`Delivers` is `Answer to: <question>`; the Check proves the question answered with
evidence, not that a feature works. Time-box scope (one prototype, benchmark, or set of
approaches), not hours. Stop at the limit and report unknowns. Production code is not
required.

Record results in `## Findings` and wherever useful: spec for a validated approach,
decisions for a rejected option, glossary for a clarified term, or a follow-up task for
work to build.

At completion, either turn kept code into real code with tests in follow-up work, or
discard it before committing / leave it only on a `spike/<effort>-<NN>` branch named in
Findings. Never leave spike code on main. Archive the task like any other.
## Example Spike Task

```markdown
# 03: Evaluate GraphQL federation performance

**Effort:** api-v2
**Task type:** spike
**Base commit:** <commit-sha>

**Question:** Can federated GraphQL handle 1000 req/s with acceptable latency?
**Time box:** one gateway with two subgraphs, one k6 run; no tuning

**Delivers:** Answer to: is federation viable at 1000 req/s?

**Blocked by:** None
**Files:** throwaway gateway on a spike branch

**Read first:** API v2 spec, "Performance" section

**Check:** `k6 run load.js` → p95 latency recorded in Findings

- [ ] Load test results documented in Findings
- [ ] Decision recorded: use federation or not

## Findings

<Filled in after spike>

**Result:** Federation adds 12ms overhead at p95, well within budget
**Recommendation:** Proceed with federation
**Recorded in:** decisions.md: 2026-02-10 - Use GraphQL federation for API v2
```
