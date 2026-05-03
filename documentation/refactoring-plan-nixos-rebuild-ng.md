# Nixinate Modernization Refactoring Plan (Synthesis Draft)

**Status:** Working Draft (Synthesized from multi-agent review)  
**Date:** 2026-05-03  
**Project Path:** `/speed-storage/repo/DarthPJB/nixinate`  
**Consumer Reference Path:** `/speed-storage/repo/DarthPJB/NixOS-Configuration`  
**Primary Goal:** Modernize nixinate for production safety and `determinate-systems/nixos-rebuild-ng` support, prioritizing critical risks first.

---

## 1) Scope and Intent

This plan is focused on:
- eliminating high-risk deployment behavior,
- aligning the deploy engine with modern ng-based rebuild workflows,
- simplifying architecture for deterministic, testable operation,
- and supporting a controlled migration path for existing consumers.

Legacy behavior is not the primary concern unless required for safe rollout.

---

## 2) Correlated Critical Issue Clusters

## Cluster A — Rebuild Engine Modernization Blocker (**CRITICAL**)

**Problem:** Current deploy path is hard-coupled to classic `nixos-rebuild` calls and does not implement `nixos-rebuild-ng` detection/integration.

**Evidence:**
- `/speed-storage/repo/DarthPJB/nixinate/flake.nix` line 24 (`nixos-rebuild` override)
- `/speed-storage/repo/DarthPJB/nixinate/flake.nix` lines 69, 72, 77 (direct command invocation paths)

**Why this matters:** Production deployments are anchored to legacy semantics while the modernization target is ng-first.

---

## Cluster B — Unsafe / Brittle Command Construction (**CRITICAL**)

**Problem:** Deployment command assembly relies on shell string concatenation and interpolated user-configured args (e.g., `nixOptions`, mode argument), creating high fragility and potential injection/quoting failures.

**Evidence:**
- `/speed-storage/repo/DarthPJB/nixinate/flake.nix` line 50 (`concatStringsSep " "`)
- `/speed-storage/repo/DarthPJB/nixinate/flake.nix` lines 69, 77 (embedded command strings)

**Why this matters:** Unclear quoting and shell composition can fail unpredictably under production edge cases and complicates ng migration.

---

## Cluster C — Missing Preflight Validation and Weak Contract Enforcement (**CRITICAL**)

**Problem:** `_module.args.nixinate` contract is only partially guarded; failures can occur late during runtime (host/auth/port/tooling assumptions not verified pre-deploy).

**Evidence:**
- `/speed-storage/repo/DarthPJB/nixinate/flake.nix` line 39 validates `sshUser` but not equivalent strict validation for all required fields.
- No explicit preflight phase in generated deploy flow.

**Why this matters:** Production deployments fail late after expensive steps and produce weaker operational diagnostics.

---

## Cluster D — Cross-Architecture Hermetic Path Known-Broken (**HIGH**)

**Problem:** Hermetic activation path includes an acknowledged cross-architecture failure.

**Evidence:**
- `/speed-storage/repo/DarthPJB/nixinate/flake.nix` line 69 TODO comment indicates cross-arch failure.

**Why this matters:** Multi-architecture fleets cannot safely rely on this path; behavior is known inconsistent.

---

## Cluster E — Runtime Dependency/Operational Design Debt (**HIGH**)

**Problem:** Generated deploy scripts depend on presentation/concurrency tools (`lolcat`, `figlet`, `parallel/sem`) and use monolithic logic, which raises runtime and maintenance risk.

**Evidence:**
- `/speed-storage/repo/DarthPJB/nixinate/flake.nix` lines 35–36 (`lolcat`, `sem`)
- `/speed-storage/repo/DarthPJB/nixinate/flake.nix` line 58 (`figlet`)
- `/speed-storage/repo/DarthPJB/nixinate/flake.nix` line 85 (`runtimeInputs = [ ]`, reinforcing fragility concerns from reviewers)

**Why this matters:** Increases failure surface, hinders portability, and complicates structured testing.

---

## 3) Consumer-Side Compatibility Risks (NixOS-Configuration)

From usage review at `/speed-storage/repo/DarthPJB/NixOS-Configuration`:

1. **Default mode assumptions are sensitive** (**CRITICAL**)
   - Existing workflows assume default behavior is safe/test-first.
2. **CLI pass-through contract must remain deliberate** (**CRITICAL**)
   - Common usage pattern: `nix run .#host -- switch`.
3. **`buildOn = "remote"` hosts require explicit ng-capable path** (**CRITICAL/HIGH**)
   - Example host class includes remote-build machines.
4. **CI build/deploy commands still include legacy patterns** (**HIGH**)
   - Build/deploy workflows need explicit migration steps.
5. **Operational log path/shape may be assumed by CI** (**MEDIUM/HIGH**)
   - Changes must include artifact-path review.

---

## 4) Target Architecture (Proposed)

Adopt a **hybrid of Vector A + B + C**:

1. **ng-first invocation layer**
   - Make `nixos-rebuild-ng` primary rebuild engine.
2. **Phased deploy engine**
   - Split into deterministic stages:
     1) config/schema validation
     2) target/preflight validation
     3) build strategy decision (`local` vs `remote`)
     4) transfer/build execution
     5) activation
     6) post-activation verification
3. **Strict production mode**
   - Fail-closed with explicit mode, explicit host/user/port, and explicit strategy.
4. **minimal dependency output**
   - Make cosmetic dependencies optional or remove from core deploy path.

---

## 5) Milestones and Exit Criteria

## M0 — Plan Ratification
- Confirm hard requirements:
  - ng hard requirement vs controlled fallback strategy
  - required compatibility surface for existing users
- **Exit:** acceptance criteria signed off.

## M1 — Critical Foundation (Modernization + Safety)
- Integrate ng-first execution path.
- Replace brittle string assembly with safer command argument handling.
- Enforce schema validation early.
- **Exit:** critical clusters A/B/C addressed.

## M2 — Diagnostics + Operational Hardening
- Add preflight checks (host reachability, auth expectations, tooling availability).
- Add structured/loggable phase output and clearer failure messages.
- **Exit:** predictable failure behavior with actionable diagnostics.

## M3 — Cross-Arch and Strategy Hardening
- Resolve or explicitly disable broken cross-arch hermetic behavior until fixed.
- Validate local/remote strategy behavior against representative targets.
- **Exit:** documented, reliable behavior matrix.

## M4 — Consumer Migration + Release
- Publish migration guide for existing usage patterns.
- Update CI examples and recommended invocation contract.
- **Exit:** upgrade path validated in `/speed-storage/repo/DarthPJB/NixOS-Configuration`-style consumers.

---

## 6) Immediate Implementation Priorities (Ordered)

1. **Define and freeze minimal `_module.args.nixinate` schema** (required/optional fields, strict defaults).
2. **Implement ng-first command layer behind a clean interface**.
3. **Refactor deploy script generation into phase functions**.
4. **Add preflight + postflight checks**.
5. **Reduce optional tooling in core path** (`lolcat`/`figlet`/`sem` behavior review).

---

## 7) Open Decisions for Human Oversight

1. Should ng be hard-required in first release, or soft-detected for one transition release?
2. Do we preserve exact CLI pass-through semantics, or intentionally tighten accepted modes?
3. Is test-first default mandatory going forward?
4. Should cross-arch hermetic be temporarily disabled until fixed?
5. What is the minimum consumer migration guarantee (1 release cycle vs immediate cutover)?

---

## 8) Change Log

- 2026-05-03: Initial placeholder created.
- 2026-05-03: Replaced with synthesized multi-agent modernization plan and prioritized issue clusters.
