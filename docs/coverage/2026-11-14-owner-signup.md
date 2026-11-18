# Company signup, team invitations and first use

14 November 2026 · ERP Workspace · Isolated Mac verification on `native-test.localhost` with synthetic companies.

## What a new customer sees

1. **Create a company** asks for the owner's name, email, password, company name and choice of General ERP or Knitting. The app supplies the service address. Company setup uses the site's default country, currency and standard chart of accounts.
2. A General ERP owner opens the business dashboard. A knitting owner opens the mill. The pinned **General ERP** control opens the same company’s business overview. Its adjacent menu opens permitted business areas directly, including Sales, Purchasing, Stock and Accounts. Returning from a business module leads to the business overview. Switching back to the mill is explicit.
3. In account settings, the owner selects **Team access**, enters the staff member's email and picks their role. The owner can copy the invitation or share it through the operating system. Staff choose **Join with invitation** and enter their credentials and code. The invitation supplies their company and role. A pending code expires after three days, can be replaced or revoked, and can be redeemed once.

## Connected rehearsals

| Journey | Observed outcome |
| --- | --- |
| Two new owners used the Flutter signup screen, one choosing General ERP and the other Knitting. Each invited a staff member. | The Sales staff member and the Knitting operator entered their owner's company without repeating setup. Each owner saw two members and zero invitations pending after acceptance. Staff lacked team administration. |
| The General ERP owner created a customer, supplier, stock item and item prices, then purchased five cartons at ₹30 and sold two at ₹50. | The app submitted eight linked vouchers across the two orders, stock movements, invoices and payments. ERPNext showed both invoices paid, debits equal to credits for all six ledger-posting vouchers, and three cartons remaining at ₹90. The owner first encountered a missing Supplier permission. The corrected signup was used for the completed rehearsal. |
| The Knitting owner added the company's first customer and opened a new job. | The invited operator could open that job. The operator lacked billing and team-management access. |
| Back and navigation, narrow screens, large text and the keyboard. | Sign-in, signup, invitation and the company picker were tested at phone sizes. The picker previously overflowed by 167 pixels above the keyboard. Scrolling now makes company selection reachable. Business shortcuts were exercised with a restricted account. Desktop and phone captures show distinct record and report icons. |

In the General ERP journey the signup and initial master records used the same server methods as the app under the new owner's identity. Orders, receipts, invoices and payments used the Flutter screens over HTTP. The separate sign-up and invitation rehearsals used the Flutter forms throughout. The previous [staff pilot](2026-11-14-connected-pilot.md) documents a full mill cycle through invoicing, yarn return and closure.

## Final client and workflow checks

Choosing Knitting switches the company setup illustration to the circular mill machine on desktop and phone. General ERP manufacturing uses the assembly workstation for Work Orders. Sales, purchasing, invoices, stock and dispatch carry their own studio artwork from the module register to the document editor. The ten illustrations total 864,306 bytes across all three bundled sizes.

On a short phone, a successful invitation brings the receipt and Copy code action into view. The confirmation follows the server response and keeps the code available while the directory refreshes. Reduced motion jumps directly to the result. The Flutter suite passed 197 tests and static analysis found no issues. All 148 backend tests passed against the isolated site. Overlapping writes during the rehearsal exposed a database rollback that could hide the retry message. Knitting commands and invoice previews now retain the correct outcome and prompt the user to retry. A dedicated test covers both paths. The Mac ARM64 release passed strict local signature verification. The iPhone simulator and Android ARM64 debug builds compiled. All 30 studio WebP files inside each built app matched the source checksums.

Through the Flutter screens, a scoped mill employee received 15 kg, corrected an excessive entry, produced and inspected a 12 kg roll, dispatched and invoiced it, returned the remaining 2 kg and closed job `KN-NTEST-JOB-2026-00014`. Its invoice was ₹1,200. A separate real HTTP cycle returned a 44 kg roll, verified reinspection, cancelled the return, ₹4,400 credit and original invoice, and closed with replacement invoice `ACC-SINV-2026-00024` for ₹8,800. Stock, custody and unbilled balances reconciled. A trade clerk completed eight linked purchase and sales vouchers, including both payments. ERPNext confirmed the ledger postings and ending stock.

The final connected signup rehearsal created a General ERP owner and a knitting owner through the Flutter forms. Each invited a staff member who joined the correct company. Both owners saw two members and no pending invitations. The knitting operator opened the new job without billing access.

In the final native Mac profile at 714 × 900 logical pixels and 60 Hz, 11 of 200 register rows mounted on entry. No build or raster stage exceeded 16.67 ms across 302 warmed scroll frames, 216 production-selection frames and 192 sales-selection frames. First opening General ERP included one 60.028 ms build frame. These figures cover rendering with synthetic in-memory data. They exclude network time.

## Release scope

The local launcher supplies a loopback service. A public rollout requires a reachable HTTPS service that provisions and routes a separate Frappe site for each independent customer. An existing site can opt in to its first owner signup through private server configuration. Distribution, public provisioning and physical-device coverage remain open.

New owner-managed accounts use the native workspace. They can run ten reviewed company-scoped standard reports, including General Ledger, Balance Sheet, Stock Ledger, Accounts Receivable and Accounts Payable, subject to their role. The [remaining ERPNext coverage](../setup/NATIVE_WORKFLOWS.md) includes additional reports and document-specific workflows. The [Mac measurements](2026-11-14-mac-startup.md) distinguish first-frame rendering from actual sign-in and data access.

## Reproduce on this Mac

Start the local service with `scripts/setup-native-test.command`. From `apps/erp_client`, run the following with a fresh evidence directory. The provisioner creates credentials in the ignored directory with owner-only file permissions. No customer account is involved.

```sh
export PILOT_DIR="$(mktemp -d "$PWD/../../.local/owner-trade.XXXXXX")"
python3 tool/pilot_trade_fixture.py provision-owner "$PILOT_DIR"
PILOT_FLOW=Purchase flutter test --no-pub tool/pilot_trade_test.dart
PILOT_FLOW=Sales flutter test --no-pub tool/pilot_trade_test.dart
python3 tool/pilot_trade_fixture.py verify "$PILOT_DIR"
```

For the sign-up and invitation rehearsal, set `ERP_LOCAL_PILOT_PASSWORD` in the local process environment to the isolated site's administrator password, then run `flutter test --no-pub tool/pilot_onboarding_test.dart`. It checks the site identity before creating accounts. The Mac launcher is `scripts/erp-workspace.command`.
