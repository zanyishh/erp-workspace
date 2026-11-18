# Windows testing

Test the General ERP and Knitting editions against a synthetic ERPNext site running on your own Windows computer. Each tester gets their own database. No connection to a customer account is required.

## Download and start

1. Sign in to GitHub with an account invited to the private repository. Accept the invitation first. A private repository URL alone does not grant access.
2. Download the repository with **Code → Download ZIP** and extract it to a short path such as `C:\ERP`. Keep the complete extracted source tree: Docker mounts the server extension from it.
3. Install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/) with WSL 2 and Linux containers. Start Docker Desktop. Allow at least 4 GB for its Linux VM and sufficient disk space for the ERPNext, MariaDB and Redis images.
4. Open PowerShell in the extracted repository and run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows-test.ps1
   ```

   This process-scoped option runs the downloaded launcher without changing the machine's execution policy. Read the script before running it. The first start downloads images, creates `native-test.localhost`, installs the extension and seeds synthetic companies. It can take several minutes. Subsequent starts retain the same database and passwords.

5. Open `.local\windows-test\accounts.json` to get the two generated test logins. Do not commit or share this file. Use the general login for **Meridian Trading** and the knitting login for **Kaveri Loomworks**. The original ERPNext browser interface is also available at `http://127.0.0.1:8081` with the local evaluation `Administrator` / `admin` login.
6. Open the repository's **Actions → Windows tester builds**. Download both artifacts from a **successful** run: `ERP-Workspace-Windows-x64` and `Knitting-Workspace-Windows-x64`. Extract each into a different folder and open `erp_client.exe`. Keep every DLL and the `data` folder alongside the executable. Flutter and Visual Studio are unnecessary when using these compiled downloads. If required, install the official [Visual C++ x64 runtime](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist/).

Builds are unsigned test applications. A successful compilation and sign-in-window smoke check do not establish that every business workflow passes. Record failures with the artifact's commit SHA, edition, screen, steps and screenshot. No customer data is included.

## What to exercise

| Application | Login / company | Checks |
| --- | --- | --- |
| ERP Workspace | General login / Meridian Trading | Overview, company context, catalogue, customers, suppliers, purchase and sales documents, stock, accounting, reports, task planner, team access |
| Knitting Workspace | Knitting login / Kaveri Loomworks | Mill overview, jobs, yarn receipt, programme and batches, production, machines, operators, stoppages, delivery, returns, factory masters and reports |
| Shared invoicing | Sign in separately to each company | Register filters and totals, new draft, existing draft editor, review, save, submit/cancel as permitted, preview, export, company print settings; verify company separation |
| ERPNext browser interface | Local Administrator / ERP Native Verification | Original baseline UI and synthetic records; compare permitted native changes and read back postings |
| Both Flutter editions | Their scoped accounts | Resize, keyboard navigation, long lists, permission errors, retry after stopping/restarting the service, PDF opening and system printing |

The two Flutter editions share the same app engine and billing implementation. Android, iOS and macOS source folders are included. Windows cannot execute the Apple apps; their build/device checks are separate CI jobs. An unsigned iOS build is not an installable App Store or TestFlight release.

## Stop, restart and diagnose

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows-test.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows-test.ps1 -Action Stop
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows-test.ps1
```

The dedicated Docker Compose project is `erp-windows-test`. Stopping never removes volumes. Do not use `down -v` or delete its volumes. The default Docker context is `desktop-linux`; if Docker Desktop uses a different existing Linux context, pass `-DockerContext NAME`. Port 8081 must be free. All evaluation listeners remain on `127.0.0.1`.

If setup fails, inspect:

```powershell
docker --context desktop-linux compose --project-name erp-windows-test -f infrastructure/erpnext/compose.yaml --profile native-test logs --tail 100
```

## Rebuild or develop

Install the exact Flutter version from `infrastructure/erpnext/quality/flutter-toolchain.json`, Git, and Visual Studio with **Desktop development with C++** and a Windows SDK. The PDF regression tests also require Poppler's `pdfinfo` and `pdftotext` on `PATH` (CI installs Chocolatey's `poppler` 26.7.0; Linux uses `poppler-utils`). End users running the packaged app do not need Poppler. Then:

```powershell
cd apps\erp_client
flutter doctor -v
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub --dart-define=ERP_LOCAL_WORKSPACE=false --dart-define=ERP_SERVER=http://127.0.0.1:8081
flutter build windows --release --no-pub --dart-define=ERP_LOCAL_WORKSPACE=false --dart-define=ERP_KNITTING_CUSTOMER=true --dart-define=ERP_SERVER=http://127.0.0.1:8081
```

Copy the **whole** `build\windows\x64\runner\Release` folder after each build before compiling the other edition. Preserve the repository's licenses and notices with any redistributed build. The CI artifact includes them and an exact source revision link.
