# GPL-3.0; see LICENSE and NOTICE.md. Windows PowerShell 5.1 or newer.
[CmdletBinding()]
param(
    [ValidateSet('Start', 'Stop', 'Status')][string]$Action = 'Start',
    [string]$DockerContext = 'desktop-linux'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $root 'infrastructure/erpnext/compose.yaml'
# A separate project prevents collisions with other Docker projects.
$compose = @('--context', $DockerContext, 'compose', '--project-name', 'erp-windows-test', '-f', $composeFile)

function Invoke-Compose {
    & docker @script:compose @args
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose failed (exit $LASTEXITCODE)." }
}
function Wait-TestSite {
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        try {
            $ping = Invoke-RestMethod -Uri 'http://127.0.0.1:8081/api/method/ping' -TimeoutSec 3
            if ($ping.message -eq 'pong') { return }
        } catch { }
        Start-Sleep -Seconds 2
    }
    throw 'The local test service is not ready. Run -Action Status and check the Docker logs.'
}
function New-TestPassword {
    $bytes = New-Object byte[] 24
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($bytes) } finally { $random.Dispose() }
    return [Convert]::ToBase64String($bytes)
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Install and start Docker Desktop with WSL 2 and Linux containers, then run this script again.'
}
& docker --context $DockerContext info --format '{{.OSType}}' | ForEach-Object {
    if ($_ -ne 'linux') { throw 'Select Linux containers in Docker Desktop.' }
}
if ($LASTEXITCODE -ne 0) { throw "Docker context '$DockerContext' is unavailable. Start Docker Desktop." }
if ($Action -eq 'Stop') {
    Invoke-Compose --profile native-test stop
    Write-Host 'Local test services stopped. All business data and volumes are retained.'
    return
}
if ($Action -eq 'Status') {
    Invoke-Compose --profile native-test ps -a
    return
}

$state = Join-Path $root '.local/windows-test'
New-Item -ItemType Directory -Force -Path $state | Out-Null
$accountsPath = Join-Path $state 'accounts.json'
if (-not (Test-Path -LiteralPath $accountsPath)) {
    @{
        general = @{ email = 'local-general-owner@workspace.example.invalid'; password = (New-TestPassword) }
        knitting = @{ email = 'local-owner@workspace.example.invalid'; password = (New-TestPassword) }
    } | ConvertTo-Json | Set-Content -LiteralPath $accountsPath -Encoding UTF8
}
$accounts = Get-Content -LiteralPath $accountsPath -Raw | ConvertFrom-Json
if ($accounts.general.email -ne 'local-general-owner@workspace.example.invalid' -or
    $accounts.knitting.email -ne 'local-owner@workspace.example.invalid' -or
    $accounts.general.password.Length -lt 20 -or $accounts.knitting.password.Length -lt 20) {
    throw 'The local tester accounts file is invalid. Preserve it and inspect it before continuing.'
}

Push-Location $root
try {
    # Wait for MariaDB, Redis and the common Frappe configuration to be ready.
    Invoke-Compose up -d --wait --wait-timeout 180 db redis-cache redis-queue
    Invoke-Compose up --no-deps --exit-code-from configurator configurator
    Invoke-Compose up -d backend websocket queue-short queue-long scheduler
    Invoke-Compose exec -T backend bash -ec 'wait-for-it -t 180 db:3306; wait-for-it -t 180 redis-cache:6379; wait-for-it -t 180 redis-queue:6379; if [ ! -d sites/native-test.localhost ]; then bench new-site native-test.localhost --db-root-username=root --db-root-password=admin --admin-password=admin --mariadb-user-host-login-scope="%" --install-app erpnext; fi'
    Invoke-Compose exec -T backend bash -ec 'if ! bench --site native-test.localhost list-apps | grep -q "^erp_extensions "; then bench --site native-test.localhost install-app erp_extensions; fi'
    Invoke-Compose exec -T backend bench --site native-test.localhost migrate
    $env:ERP_TEST_GENERAL_PASSWORD = $accounts.general.password
    $env:ERP_TEST_KNITTING_PASSWORD = $accounts.knitting.password
    try {
        Invoke-Compose exec -T -e ERP_TEST_GENERAL_PASSWORD -e ERP_TEST_KNITTING_PASSWORD backend bench --site native-test.localhost execute erp_extensions.test_bootstrap.provision_windows_test
    } finally {
        Remove-Item Env:ERP_TEST_GENERAL_PASSWORD, Env:ERP_TEST_KNITTING_PASSWORD -ErrorAction SilentlyContinue
    }
    Invoke-Compose --profile native-test up -d native-test-backend native-test-frontend
    Wait-TestSite
    Write-Host 'Ready: http://127.0.0.1:8081'
    Write-Host "Use the separate General ERP and Knitting logins in $accountsPath"
    Write-Host 'Extract each Windows app download completely, then open erp_client.exe.'
} finally { Pop-Location }
