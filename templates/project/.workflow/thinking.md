# First Principles Thinking

A framework for decomposing problems when requirements are vague, solutions feel
over-engineered, or you are about to add complexity "because everyone does."

Used during `flow-grill` step 2 (writing the design tree) and whenever a decision
feels forced rather than derived.

---

## When to use this

Reach for first principles when:
- The requirement feels bloated before implementation begins
- "We need X" assumes a solution rather than stating a problem
- Multiple approaches exist but none feels clearly right
- You are about to add infrastructure, abstractions, or dependencies
- The simplest explanation would be "that's how it's always done"

Skip it when:
- The problem and constraints are concrete
- Prior art in this codebase solves the exact problem
- The decision is implementation detail with no architectural weight

---

## The framework

### Step 1: Restate the problem

Strip implementation details to one sentence describing the actual need.

Bad: "We need to add Redis caching to the user profile endpoint"  
Good: "User profile data takes too long to load"

Bad: "We should implement a message queue for notifications"  
Good: "Notifications must be delivered reliably even during load spikes"

The problem statement must not assume a solution category (caching, queuing,
microservices). If it does, ask "why?" until you hit the fundamental constraint.

### Step 2: List fundamental truths

What is absolutely true, not opinion or convention?

| Category | Examples |
|----------|----------|
| **Physical constraints** | Network latency ≥ 0ms, disk I/O has throughput limits, memory is finite |
| **Business rules** | Users must see their own data, payments are idempotent, audit logs immutable |
| **Technical invariants** | Data consistency requirements, backward compatibility promises, SLA commitments |
| **User needs** | Response time under Xms, availability ≥ Y%, cost below $Z/month |

Each truth must be:
- **Verifiable** — can be measured, tested, or observed
- **Constraining** — actually limits the solution space
- **Non-negotiable** — cannot be designed around

Discard "truths" that are really preferences: "REST is standard", "everyone uses
PostgreSQL", "microservices scale better". These are conventions, not constraints.

### Step 3: Challenge assumptions

For each component of the proposed solution, ask:

**Is this fact or convention?**  
- "We always use REST" — why? Would GraphQL, gRPC, or plain JSON-RPC violate a truth?
- "Data goes in PostgreSQL" — what truth requires a relational DB here?

**What if we removed this entirely?**  
- If nothing breaks, it's unnecessary overhead
- If something breaks, which fundamental truth does it protect?

**Are we solving the problem or a symptom?**  
Trace the causal chain backward:
- Slow endpoint → large payload → N+1 queries → missing join
- Or: Slow endpoint → stale cache → cache invalidation is hard → wrong granularity

**Who benefits from this complexity?**  
- Developers? Future flexibility that may never be needed (YAGNI)
- Users? Measure or estimate the actual impact
- Operations? Real operational burden or imagined one?
- Nobody? Delete it

### Step 4: Build up from truths

Start with the minimum viable mechanism that satisfies all fundamental truths:

1. **Enumerate the truths** this component must satisfy
2. **For each truth, name the simplest mechanism** that satisfies it
3. **Combine mechanisms** — prefer composition over invention
4. **Add complexity only when a truth demands it**

Each addition must answer: "Which truth requires this?"

Examples:

**Problem:** Notifications must be reliable during load spikes  
**Truth 1:** Cannot lose a notification (business rule)  
**Truth 2:** Load spikes 10x normal (observed constraint)  
**Simplest:**  
- Truth 1 → write to durable store before claiming success (DB transaction, file append)
- Truth 2 → async processing decouples spike from handling (worker reading the store)
- **Result:** Table-as-queue or append-only log, not a message broker (unless another truth demands broker features)

**Problem:** User profile data takes too long  
**Truth 1:** Profile changes rarely (observed: once per session)  
**Truth 2:** 95th percentile must be <200ms (SLA)  
**Simplest:**  
- Truth 1 → cache with long TTL
- Truth 2 → measure current p95, determine if caching alone suffices
- **Result:** In-memory cache (lru_cache, Rails.cache), not Redis (unless scale truth demands distributed cache)

### Step 5: Validate

Before committing to the design:

**Does it solve the original problem?**  
Trace from problem statement through truths to solution. Every step justified?

**What assumptions still need verification?**  
- Load estimates → load test
- Latency claims → benchmark
- "Rarely changes" → instrument and measure

**What is the simplest experiment to test this?**  
Prototype, spike, or minimal implementation that proves/disproves the approach.
Avoid multi-week commitments to untested designs.

---

## Worked example

**Initial:** "We need CDC pipeline with Kafka to keep search index in sync with database."

**Restate:** "Search results must reflect database changes without excessive lag."

**Truths:**
- Consistency: Search must not show deleted records beyond Xms
- Latency: <5s acceptable (asked user)
- Scale: 100 writes/sec peak (measured)
- Reliability: Cannot lose a write

**Challenge:**
- Is CDC required? Writes are rare (100/sec). Polling every 5s checks ~17k times for 8.6M events. Could push instead: DB trigger writes to notification table, worker polls that.
- Is Kafka required? Single consumer (search indexer). Table-as-queue suffices.

**Build up:**
- Cannot lose write → DB trigger appends to `search_updates` table (same transaction)
- <5s lag → worker polls every 2s, processes batch, deletes rows
- 100 writes/sec → batch processing handles burst

**Result:** DB trigger + polling worker. No Kafka, no CDC, no new infrastructure. Upgrade to CDC only if scale exceeds DB trigger throughput, multiple consumers emerge, or lag requirement tightens to <1s.

**Validate:** Trigger overhead <10ms (benchmark), worker keeps up (load test). Implement in 1 day, not 2 weeks for Kafka.

---

## Integration with workflow

**During `flow-grill` step 2:** When decision feels like "industry standard" rather than "forced by constraint", run Steps 1-3. Present decomposition to user before asking questions.

**During `flow-spec`:** Rejected alternatives eliminated by first principles get strongest case stated, then truth that killed them.

**During `flow-architect`:** Complexity that survived without truth-backing is candidate for removal.

---

## Anti-patterns

**Solving wrong problem** — running first principles on "how to build X" when "should we build X" is the real question. Always restate problem first.

**Fake truths** — "Microservices are more scalable" is not a truth unless current scale demonstrably exceeds monolith capacity.

**Paralysis** — first principles is a tool for expensive decisions (infrastructure, breaking changes, new dependencies), not a gate for every choice. Use it to question costly commitments, not to block routine implementation.
**Skipping validation** — building "simplest" solution without measuring whether it satisfies truths. Validate assumptions before committing.
