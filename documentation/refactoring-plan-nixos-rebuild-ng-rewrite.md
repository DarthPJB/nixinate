# Nixinate Modernization Refactoring Plan

**Status:** Technical Specification  
**Date:** 2026-05-03  
**Project:** `DarthPJB/nixinate`  
**Consumer Reference:** `DarthPJB/NixOS-Configuration`

## Executive Summary

This plan modernizes nixinate for production-grade safety and `nixos-rebuild-ng` adoption. The work is organized around five critical issue clusters, phased implementation milestones, and explicit exit criteria. Modernization and risk elimination take priority over legacy compatibility.

---

## Critical Issue Clusters

### Cluster A: Rebuild Engine Modernization Blocker ⚠️ **CRITICAL**

**Issue:** The deployment path is hard-coupled to classic `nixos-rebuild` and lacks `nixos-rebuild-ng` detection or integration.

**Evidence:**
- `flake.nix` line 24: `nixos-rebuild` override
- `flake.nix` lines 69, 72, 77: direct command invocation paths

**Impact:** Production deployments are anchored to legacy semantics while the modernization target is ng-first. This blocks adoption of deterministic, reproducible rebuild workflows.

---

### Cluster B: Unsafe Command Construction ⚠️ **CRITICAL**

**Issue:** Deployment command assembly uses shell string concatenation with interpolated user-configured arguments (`nixOptions`, mode), creating quoting failures and injection vulnerabilities.

**Evidence:**
- `flake.nix` line 50: `concatStringsSep " "`
- `flake.nix` lines 69, 77: embedded command strings with interpolation

**Impact:** Production deployments fail unpredictably under edge cases. String-based composition complicates ng migration and increases maintenance burden.

---

### Cluster C: Missing Preflight Validation ⚠️ **CRITICAL**

**Issue:** The `_module.args.nixinate` contract is only partially validated. Runtime failures occur after expensive steps (host availability, authentication, port availability, tooling assumptions).

**Evidence:**
- `flake.nix` line 39: only `sshUser` is validated
- No explicit preflight phase in generated deploy flow

**Impact:** Failed deployments produce weak diagnostics and waste infrastructure resources. Production operations lack early failure detection.

---

### Cluster D: Cross-Architecture Hermetic Path Known-Broken 🔴 **HIGH**

**Issue:** The hermetic activation path has an acknowledged cross-architecture failure (see `flake.nix` line 69 TODO).

**Evidence:**
- `flake.nix` line 69: TODO comment indicating cross-arch inconsistency

**Impact:** Multi-architecture fleets cannot reliably use this path. Behavior is known-broken under cross-compilation scenarios.

---

### Cluster E: Runtime Dependency and Operational Debt 🔴 **HIGH**

**Issue:** Generated deploy scripts depend on presentation tools (`lolcat`, `figlet`, `parallel/sem`) and use monolithic logic patterns, increasing runtime fragility and hindering portability.

**Evidence:**
- `flake.nix` lines 35–36: cosmetic tooling dependencies
- `flake.nix` line 58: display tools in core path
- `flake.nix` line 85: empty `runtimeInputs` despite cosmetic dependencies

**Impact:** Higher failure surface, poor portability, and difficulty testing. Complicates structured, deterministic execution.

---

## Consumer Compatibility Risks

Analysis of usage patterns in `NixOS-Configuration` surface five risk areas:

| Risk | Severity | Description |
|------|----------|-------------|
| Default mode assumptions | CRITICAL | Existing workflows assume default behavior is safe and test-first |
| CLI pass-through contract | CRITICAL | Common pattern `nix run .#host -- switch` must remain deliberate |
| Remote-build hosts (`buildOn = "remote"`) | CRITICAL/HIGH | These hosts require explicit ng-capable execution paths |
| Legacy CI workflows | HIGH | Build/deploy commands still use legacy invocation patterns |
| Operational log paths | MEDIUM/HIGH | CI may depend on artifact paths and log output shape |

---

## Target Architecture

Adopt a **phased, ng-first modernization** with these design principles:

1. **Primary rebuild engine: `nixos-rebuild-ng`**
   - Make ng the first execution path with fallback strategy defined in M0.

2. **Deterministic phased deploy execution:**
   - Config/schema validation (early, fail-closed)
   - Target/preflight validation (host reachability, auth, tooling)
   - Build strategy decision (`local` vs `remote`)
   - Build execution and artifact transfer
   - Activation (with pre/post hooks)
   - Post-activation verification

3. **Strict production mode:**
   - Explicit deployment mode, host/user/port specification
   - Explicit build strategy selection
   - Fail-closed on ambiguity

4. **Minimal optional dependencies:**
   - Cosmetic tooling (`lolcat`, `figlet`) optional or removed from core path
   - Core deploy path has no runtime surprises

---

## Shared Guidelines Alignment (`/speed-storage/opencode/llm/shared`)

This refactor plan is aligned to reviewed shared guidance:

- `/speed-storage/opencode/llm/shared/prime_directives.md`
- `/speed-storage/opencode/llm/shared/NIX_FLEET_ENGINEERING_PRINCIPLES.md`
- `/speed-storage/opencode/llm/shared/NIX_LANGUAGE_GUIDE.md`
- `/speed-storage/opencode/llm/shared/common-infra-strategies.md`

### Alignment by Principle

1. **Flake-first, deterministic operations**
   - Plan remains flake-native and avoids non-flake deployment paths.
   - M1/M2 require explicit schema + preflight validation to reduce hidden runtime assumptions.

2. **Safety-first deployment posture**
   - Test-first behavior is treated as an explicit oversight decision in M0.
   - Strict mode and fail-closed validation are core architecture elements.

3. **Operational transparency and diagnostics**
   - M2 adds phase-based, actionable diagnostics.
   - Failure states are expected to be deterministic and reviewable.

4. **Secrets and remote-host discipline (Secrix-aware)**
   - Consumer migration explicitly accounts for remote deployment and host-key expectations.
   - No plan element requires changing cryptographic assets; deployments should continue to consume secret material through established Secrix patterns.

5. **Simplicity over complexity (KISS)**
   - Core path minimizes optional/cosmetic dependencies.
   - Monolithic script behavior is replaced with phased, testable execution boundaries.

### Milestone-Level Guideline Mapping

- **M0:** Policy decisions (ng requirement, compatibility scope, test-default posture).
- **M1:** Determinism + safety baseline (schema, argument handling, ng-first command path).
- **M2:** Transparent operations (structured diagnostics and preflight behavior).
- **M3:** Reliability boundaries (cross-arch behavior explicitly fixed or disabled).
- **M4:** Controlled migration and documented operational contract for consumers.

---

## Zipper Stage-Gate Delivery Model

This project uses a **zipper stage-gate** model with two coupled tracks:

- **Track A (Engine):** internal `nixinate` refactor/modernization gates
- **Track B (Consumer):** `NixOS-Configuration` compatibility gates

Progress to the next milestone requires both tracks to pass (or explicit human waiver).

### Global Invariants (Non-Break Policy)

These are mandatory across all milestones:

1. Existing consumer usage must continue to work without required refactor:
   - `nix run .#<host>`
   - `nix run .#<host> -- switch`
   - current `_module.args.nixinate` naming/shape
2. Default safety posture must not regress.
3. Any intentional behavioral tightening must be explicitly approved at gate review.

---

## Complete Stage-Gate Plan

### Stage M0 — Scope Lock + Gate Contract
**Objective:** ratify constraints, acceptance criteria, and testing matrix.

**Track A deliverables (Engine):**
- Finalize critical issue register and ownership.
- Freeze internal acceptance tests for identified issues.

**Track B deliverables (Consumer):**
- Freeze baseline compatibility contract from `/speed-storage/repo/DarthPJB/NixOS-Configuration`.
- Record baseline invocation patterns and CI assumptions.

**Gate G0 (must pass):**
- Non-break policy ratified.
- M1/M2 measurable acceptance criteria approved.

---

### Stage M1 — Compatibility-Preserving Core Refactor
**Objective:** modernize core internals without breaking consumer contract.

**Track A deliverables (Engine):**
- Introduce ng-first execution layer behind stable interface.
- Replace brittle command string composition with structured argument handling.
- Add strict schema validation for `_module.args.nixinate` (with compatibility-safe defaults).
- Add preflight checks (connectivity/auth/tooling) with actionable failures.

**Track B deliverables (Consumer):**
- Execute compatibility suite against existing `NixOS-Configuration` usage.
- Verify unchanged invocation semantics and expected outcomes.

**Gate G1 (must pass):**
- No required downstream refactor.
- Existing invocations still valid.
- Critical clusters A/B/C closed.

---

### Stage M2 — Hardening Closure (All Identified Issues to Date)
**Objective:** close all currently identified internal issues and finalize production hardening.

**Track A deliverables (Engine):**
- Structured phase logging and diagnostics in deploy flow.
- Resolve runtime dependency/design debt in core path.
- Fix or explicitly disable broken cross-arch hermetic behavior (with clear policy).
- Close all known issues identified in this planning cycle.

**Track B deliverables (Consumer):**
- Re-run compatibility and operational checks on representative hosts/workflows.
- Validate CI/logging assumptions still function or are mapped with non-breaking defaults.

**Gate G2 (must pass):**
- All identified internal issues fixed or explicitly retired with approved rationale.
- No required consumer refactor.
- Production-ready diagnostics and failure behavior confirmed.

---

### Stage M3 — Validation Matrix + Controlled Rollout
**Objective:** prove reliability under realistic deployment conditions.

**Track A deliverables (Engine):**
- Execute local/remote strategy matrix and failure-path tests.
- Finalize supported/unsupported behavior matrix.

**Track B deliverables (Consumer):**
- Validate against representative `NixOS-Configuration` host classes.
- Confirm no contract regressions in batch and single-host flows.

**Gate G3 (must pass):**
- Validation matrix complete.
- Rollout decision approved by human oversight.

---

### Stage M4 — Release + Stewardship
**Objective:** publish and operationalize stabilized refactor.

**Track A deliverables (Engine):**
- Release notes and architecture notes.
- Ongoing maintenance checklist.

**Track B deliverables (Consumer):**
- Consumer-facing migration guidance (for optional improvements, not break-fixes).
- Post-release verification and incident playbook.

**Gate G4 (must pass):**
- Release artifacts published.
- Operational ownership and follow-up cadence assigned.

---

## Phase Workstreams (Cross-Cutting)

1. **Command/Invocation Safety Workstream**
   - ng-first abstraction + robust arg handling.
2. **Schema/Validation Workstream**
   - config contract, preflight, fail-closed behavior.
3. **Diagnostics/Observability Workstream**
   - phase-logs, error taxonomy, operator guidance.
4. **Compatibility Workstream**
   - frozen contract checks against `NixOS-Configuration`.
5. **Release Governance Workstream**
   - gate reviews, risk exceptions, change records.

---

## Delegation Model (Recommended)

- **@tuvok-deepseek:** adversarial risk and failure-mode review at each gate.
- **@tpol-xai:** systems architecture coherence and trade-off analysis.
- **@tpol-minimax:** milestone planning, exit criteria quality, and risk matrix maintenance.
- **@tpol-gpt:** consumer compatibility verification on `/speed-storage/repo/DarthPJB/NixOS-Configuration`.
- **@ezri-claude-haiku:** plan/document rewrites after each gate decision.

---

## Gate Checklists (Actionable)

### G0 Checklist
- [ ] Non-break invariants approved
- [ ] M1/M2 objective acceptance criteria approved
- [ ] Compatibility baseline frozen

### G1 Checklist
- [ ] ng-first layer integrated
- [ ] command-construction hardening complete
- [ ] preflight + schema checks active
- [ ] existing consumer usage passes unchanged

### G2 Checklist
- [ ] all identified internal issues resolved/retired with approval
- [ ] diagnostics and dependency hardening complete
- [ ] cross-arch hermetic policy resolved (fix or disable)
- [ ] compatibility reconfirmed

### G3 Checklist
- [ ] validation matrix complete
- [ ] representative host/workflow coverage complete
- [ ] rollout risk accepted by oversight

### G4 Checklist
- [ ] release docs complete
- [ ] consumer guidance complete
- [ ] post-release ownership assigned

---

## Open Decisions for Human Oversight

1. Should ng be hard-required immediately, or soft-detected through a transition window?
2. Should `nix run .#<host>` remain default-test semantics permanently?
3. For cross-arch hermetic behavior: fix now or disable until post-M2?
4. What explicit waiver format should be used if a gate cannot be fully satisfied?
5. What cadence do you want for gate review sessions (e.g., per PR, weekly, milestone-end)?

---

## Change Log

- 2026-05-03: Synthesized from multi-agent architecture review. Prioritized critical modernization clusters and phased implementation strategy.
