# Knitting v1 execution decisions

These are the decisions made during the approved first-version build, in execution order. They are limits of the current evidence, not proof of vendor parity or a production rollout.

- Ruling: execute natively in the current project directory on a dedicated feature branch — existing approved deployment mounts and launchers use this location; no extra worktree or approval round — cost if wrong: branch integration needs review, but upstream/evaluation data are unaffected.

- Ruling: Frappe masks restricted native document fields with null rather than omitting their keys; the privacy assertion accepts null while rejecting any payload value — this preserves the established Frappe contract — cost if wrong: field existence is visible, but protected contents are not.

- Ruling: serialise initial knitting mutations on the per-company setup row as well as checking aggregate versions — makes revocation and quantity consumption atomic across this first pack — cost if wrong: write throughput is bounded per company; measure and refine row locking before a large factory rollout.

- Task 4: Ruling: Bring the guarded synthetic demo seed forward from Task 6 to support the required real Dart HTTP cycle — no live customer connection and test records remain inspectable — cost if wrong: demo seeding must remain repeatable and refuse all other sites.

- Task 4: Ruling: Use a separate ERP Knitting Verification company for rolled-back automated scenarios, leaving persisted exploration records in ERP Native Verification — demo obligations correctly blocked deactivation tests, so fixtures must be separate — cost if wrong: tests require an additional synthetic company/account chart.

- Task 6: Ruling: Recovery proof restores a compressed backup of the disposable knitting aggregate while comparing untouched original stock/GL records, and source replay uses stable command identities — validates the independent pack without overwriting an ERP site — cost if wrong: a full-site restore and real customer migration still require a separate authorised rehearsal with approved source samples.

- Final: Ruling: literal vendor parity, unknown customer formulas and real migration are not established by read-only observations — deliver independently specified functions and state sample-dependent gates explicitly — cost if wrong: a customer pilot needs separate approved examples and reconciliation before sale.

- Final: Ruling: provider submissions, real payments, Tally import parity and hardware behavior require separately chosen integrations/devices — keep unconfigured states and independent review exports truthful — cost if wrong: customer-required external workflows remain pilot gates.

- Final: Ruling: Windows/device signing, native walkthrough and frame measurements are executor evidence, not the reviewer's static verdict — compile supported local targets and record unavailable hosts/devices explicitly — cost if wrong: cross-device release readiness is not proven by source or simulator builds.

- Final: Ruling: production-scale throughput and full-site recovery remain separate from two-connection correctness and disposable aggregate restoration — retain the company-lock/fixture recovery scope — cost if wrong: larger deployment and disaster recovery need additional measurement/rehearsal.

- Final: Ruling: material charge allocations use original ERP quantity precision and original rate, with cumulative quantity/rounded-money conservation instead of sub-precision zero rows or increased return rates — cost if wrong: a partial invoice/credit can carry a whole minimum charge unit at a different instalment; complete source totals remain exact and the review shows ERP totals.

- Final: Ruling: generic pack Version diffs are disabled and pre-existing pack Versions removed because Desk does not mask private rate changes — the immutable scoped event journal remains the audit — cost if wrong: consumers of the generic pack Version feed must use the event history.

- Final: Ruling: deny a reconciliation if any required customer/job/warehouse source is restricted, rather than produce an incomplete available balance — cost if wrong: narrow-role users may need a manager with full source access for a full reconciliation.

- Final: Ruling: preserve the exact test history rather than claim every review correction was observed failing first — retained logs prove RED→GREEN for several defects, while other added regressions first passed — cost if wrong: some fixes have weaker reproduction evidence; final suites and native checks do not substitute for that missing history.

## Deferred minor

- Final: minor (deferred): GSM/loop-length entry helper text reuses the individual-roll comma-list wording; actual field labels and numeric validation work.
