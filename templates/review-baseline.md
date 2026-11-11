<!-- The team's review baseline. A team file, shipped with every deployment and never regenerated: the quality bar of a review does not depend on the project's knowledge being current. The change-reviewer applies every section; the Reviewer applies sections 4, 5 and 8. Stack-neutral by rule: no language, framework, tool or library is named here, so the same lines hold in every project the team serves. -->

# Review baseline

Apply this file **after** the project's `REVIEW-CHECKLIST.md`, never instead of it. Where the two disagree, the project's checklist wins, and the disagreement is reported: by the Reviewer as `advisory: checklist gap`, by the change-reviewer as an `unassessed:` item on its `Unverified` line, naming the checklist item and the section here.

The sections are in review order, and the order matters: a change that should not exist needs no line-by-line pass, and a security defect outranks any point of style. Every line is a rule: a change that breaks one is a finding, at the severity the scale at the end gives its consequence. A preference this file does not state is style, and style alone is never a finding above Nit.

## 0. Scope and simplicity

- The diff does what its intent says, and no more. Drive-by edits and unrelated refactors are findings, whatever their quality.
- The simplest correct implementation wins. An abstraction (an interface, a base type, a factory, a wrapper, a generic helper, an options object with one property, a new layer) needs two concrete uses today, no existing type that could carry it, and would duplicate logic, not merely shape, if it were removed.
- Defensive code for a state the types or an upstream guard already rule out is a finding.
- `TODO`, `HACK`, `FIXME` and commented-out code are findings.
- A new package or framework dependency needs a stated reason.

## 1. Intent coverage

- Every stated requirement is delivered by some hunk; a requirement no hunk delivers is a finding.
- A behavioural change the description does not mention is a finding, above all in shared code.
- A description that misleads the next reader about what the change does is a finding.

## 2. Correctness

- Null and empty values are handled; declared nullability is honoured, never suppressed.
- Boundaries hold: empty collections, zero, negative values, overflow, off-by-one, missing optional fields, time zones, culture-sensitive parsing.
- Error paths surface and carry context. No empty catch. No exceptions for expected control flow.
- Asynchronous work is awaited, never blocked on, never started and forgotten without a stated reason. Cancellation is propagated where the neighbouring code propagates it.
- Shared mutable state has a stated synchronisation strategy. A retried operation is idempotent.
- Anything that holds a resource is released on every path.
- A write in several steps runs in a transaction where the codebase uses them. A schema change carries a migration; a migration that changes data states its backfill.
- A shared helper reused by a new caller is right for that caller in every branch; two messages a person sees together never contradict each other.

## 3. Security

A security finding keeps its real severity whatever the focus of the review.

- Queries and commands are parameterised. No query, shell command, path or filter is built as a string from input.
- Every new endpoint, handler or job carries the authorisation its neighbours carry. No existing check is widened. Ownership of the object is verified, not only the role of the caller.
- Authorisation checks run before any other work in the handler, at the top, whatever branch the request takes.
- Where the codebase scopes data by tenant, account or organisation, every new query, command and cache key carries that scope.
- Input is validated at the boundary, against an allow-list.
- No secret in source, tests, fixtures, logs, messages or the description.
- No credentials, tokens, personal data or full request bodies in logs. Clients get generic errors.
- Untrusted payloads are never deserialised into arbitrary types. Paths are canonicalised and confined. Outbound addresses are allow-listed.
- Cryptography comes from the platform only. Transport security is never disabled, local development included.

## 4. Rule coverage — sibling paths

- When the change applies a rule, a check, a guard or a message to one path of a flow, every sibling path to the same data or the same action is named and either covered or shown not to need it.
- The sibling paths to look for: the other mode of the same endpoint or dialog, the other row component, the bulk variant, the client and the server, the legacy and the new interface, the other file that carries the same mapping or the same defect.
- A mode or a branch next to the changed one that does nothing and still reports success is a finding.
- A sibling path left uncovered without a stated reason is a finding at the severity of what the uncovered path can do.

## 5. Duplicated knowledge

- A constant, a contract, a validation rule, a business calculation or a message a person sees, written in two places, is a finding on the first repeat. Two look-alike functions that change for different reasons are not.
- A mapping between two sets of values (a type to a permission, a state to a label) has one owner; a second copy of it is a finding.
- A rule enforced before work is queued and again when the work runs shares one implementation.
- A derived list comes from its source, never from restating the members.

## 6. Performance

Flag only with a concrete reason. Never demand a micro-optimisation without a measurement or an obviously pathological case.

- Work that runs one query per item of a collection, where one query for the whole collection would do, is a finding.
- An unbounded result set is paged.
- No synchronous input or output on an asynchronous path.
- No input, output or expensive work inside a loop where it could be batched.
- On the interface side, effects declare exactly what they depend on, and repeated items carry stable keys.

## 7. Architecture and pattern alignment

- The change lives in the module the architecture file says owns that concern.
- Layer direction holds: a lower layer never imports from a higher one, and a re-export does not launder such an import.
- The documented base types, wrappers and patterns are used. Anything new is registered where its kind is registered. Names follow the documented conventions.
- Public contracts (interface shapes, events, shared data types) change only with a compatibility story.
- Consistency with the surrounding code beats abstract correctness.

## 8. Maintainability

- Names reveal intent and use the vocabulary of the file. A boolean reads as an assertion.
- A flag with three states where two would do is a finding.
- One level of abstraction per function. Guard clauses over nesting. A function that does two things is two functions; a boolean argument that switches behaviour is two functions.
- A contract between optional parameters (two that must be given together, one that is meaningless without another) is enforced by the type, never held by a comment.
- A loop that throws from its middle when the error could be collected and raised once after it is a finding when the surrounding code collects.
- Comments explain why. A comment that restates what simple code does is a finding; a stale comment is a finding.
- Dead code is a finding: unused imports, parameters, variables and branches, and a parameter whose last caller is gone.
- Visibility is the narrowest that works. Values are immutable by default. Magic values are named.

## 9. Tests

- Tests exist where the project's conventions require them for the behaviour the change adds or alters.
- They assert observable behaviour, never a mock verifying a mock.
- Boundary and error paths are covered, not only the expected path.
- Tests are deterministic.
- No passing test is weakened, deleted, skipped or changed to accommodate the change without a stated reason. A silently weakened test is High.
- Naming, structure and section markers follow the project's test conventions.

## 10. Compatibility and operability

- A breaking contract change is versioned, or stated with the consumers it affects.
- A new setting has a default and is documented where the codebase documents settings. A feature flag has a removal plan.
- A new failure mode is logged at the level the codebase uses for it. Nothing is swallowed silently. No log noise on hot paths.
- The change can be deployed and rolled back without data loss, and any ordering constraint between a schema change and the code is stated.
- Repository documentation the change makes stale is updated in the same change.

## 11. Change hygiene

- The description is enough for a future reader of the history.
- Generated files, build output, editor settings and secrets are not committed.
- Each file keeps its line endings.
- A change that should have been split is said so, and is reviewed anyway.

## Severity

Shared by both reviewers that read this file.

| Severity | Definition | Blocks |
|---|---|---|
| Critical | Security breach, a violated invariant of `PROJECT-RULES.md`, data loss or corruption, a likely production incident | Always |
| High | A significant functional or reliability defect; a silently weakened test; a breaking contract change without a compatibility story | Always |
| Medium | A real quality or risk issue: an unmet stated requirement, missing tests for changed behaviour, a pattern divergence with a concrete consequence, an uncovered sibling path with a bounded consequence | By default; the owner may accept it as a tracked follow-up |
| Low | A minor issue, an improvement with a small real benefit; most maintainability and duplication findings | No |
| Nit | Cosmetic; negligible risk | No, and never alone grounds for a change request |

Severity is consequence, not effort and not line count. A one-character fix that leaks another tenant's data is Critical; a 200-line refactor that is merely untidy is Low.
