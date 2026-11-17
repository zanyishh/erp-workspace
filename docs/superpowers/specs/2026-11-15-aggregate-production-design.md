# Aggregate knitting production

The user directs continued workflow improvement before hosting, under the approved industry-pack design and continuous implementation authorization. The customer uses aggregate roll counts and kilograms, separately from individual-roll entry. Existing imported Fabric Batch stock supports review, delivery, invoice and return, but new production currently requires individual roll weights. Close that gap without creating fictitious rolls or changing imported originals.

## Design

Add `produce_batch` to the existing permission-scoped, idempotent command contract. It records one running customer-custody job/programme line, measured `quantity_kg`, explicitly supplied integer `rolls` >= 0, actual `inputs` (lot, quantity_kg, units), `loss_kg`, optional warehouse/machine, shift and bounded remarks. Positive kilograms with zero recorded count are allowed: the captured source includes this case. Keep actual output and count independent; never divide kilograms into invented equal-weight rolls.

Reuse current production validation, custody consumption, programme allowance, machine/plan/component progress and version checks. Sum of actual input kg must equal output plus declared loss. This is the existing independent conservation rule, not a recovered vendor automatic-consumption formula. Preserve current excess limits and all imported programme output when checking remaining allowance. Only customer-owned inputs/output are supported by this aggregate action; reject owned or mixed materials before effects because existing batch delivery does not provide their stock valuation or separate material charging. Existing individual-roll workflows retain that functionality.

Create one awaiting-review Fabric Batch linked to the new production event; no Knitting Roll, stock voucher or invoice is fabricated. The immutable event stores initial quantity/count, programme and relevant specification/provenance for reports. Subsequent batch review, partial delivery, invoice, credit and return reuse existing guarded commands. Add dependency-safe cancellation only while the batch is untouched and no subsequent review/delivery/return or dependent progress prevents reversal. Cancelled batches retain event history and have zero available weight/count.

Reports reconstruct newly produced batches from event snapshots as well as imported baselines. Production/job/register/day totals include both measured-roll and aggregate events exactly once. As-of and period cancellation behavior must remain consistent. Extend full-job workflow summaries with permission-filtered batch review/hold/released cohorts so customer batch work appears in the primary guided actions even when its records are beyond the first page.

Flutter exposes **Record batch production** beside individual-roll entry, using total kg, count and actual consumption fields. The guided customer-custody production step opens aggregate entry; other ownership modes keep existing entry. Batch review/delivery are offered based on full server counts, with a unique batch preselected only when proven. Keep date/time labelled as current posting time; do not introduce an editable date that reports ignore.

## Verification and remaining differences

Synthetic fixture: 90.000 kg actual yarn -> 88.000 kg output, 7 recorded rolls and 2.000 kg loss. Review and dispatch 21.300 kg/2 rolls, leaving 66.700 kg/5 rolls; invoice/credit/return must retain exact independent quantities. Test zero-count output, invalid decimals/counts/ownership, denied sources, duplicate lots, overconsumption, stale/idempotent commands, imported and new programme totals, cancellation dependencies and simultaneous last-balance attempts on native-test.localhost.

Verify reports, guided full-job batch actions, narrow-layout form controls and existing individual-roll regressions. No source/customer-site writes. Unknown source automatic consumption/excess formulas, employee mapping, backdated production and owned/mixed aggregate valuation remain explicit limits, not inferred behavior. Native Mac walkthrough is unverified by user direction; hosting remains the last step.
