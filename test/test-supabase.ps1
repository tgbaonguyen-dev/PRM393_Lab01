# powershell -NoProfile -ExecutionPolicy Bypass -File .\test\test-supabase.ps1
# Checks API connectivity only; does not read or write application records.
# Run from the repository root: .\test\test-supabase.ps1
param(
    [ValidateSet('all', 'frontend', 'backend')]
    [string]$Component = 'all'
)

$failed = $false
$repoRoot = Split-Path -Parent $PSScriptRoot
$components = if ($Component -eq 'all') { @('frontend', 'backend') } else { @($Component) }

foreach ($name in $components) {
    $envPath = Join-Path $repoRoot "$name/.env"
    $config = @{}

    if (-not (Test-Path -LiteralPath $envPath)) {
        Write-Host "[FAIL] ${name}: .env file is missing."
        $failed = $true
        continue
    }

    try {
        foreach ($line in Get-Content -LiteralPath $envPath -ErrorAction Stop) {
            if ($line -match '^\s*([A-Z_]+)\s*=(.*)$') {
                $config[$matches[1]] = $matches[2].Trim().Trim('"').Trim("'")
            }
        }

        $keyName = if ($name -eq 'frontend') { 'SUPABASE_PUBLISHABLE_KEY' } else { 'SUPABASE_SECRET_KEY' }
        $endpoint = if ($name -eq 'frontend') { '/auth/v1/settings' } else { '/rest/v1/' }

        if ([string]::IsNullOrWhiteSpace($config['SUPABASE_URL']) -or
            [string]::IsNullOrWhiteSpace($config[$keyName])) {
            Write-Host "[FAIL] ${name}: fill in SUPABASE_URL and $keyName in .env."
            $failed = $true
            continue
        }

        $projectUri = [uri]$config['SUPABASE_URL']
        if (-not $projectUri.IsAbsoluteUri -or $projectUri.Scheme -ne 'https' -or
            $projectUri.DnsSafeHost -notmatch '^[a-z0-9-]+\.supabase\.co$' -or
            $projectUri.UserInfo -or $projectUri.Query -or $projectUri.Fragment -or
            $projectUri.AbsolutePath -ne '/' -or -not $projectUri.IsDefaultPort) {
            Write-Host "[FAIL] ${name}: expected https://<project-ref>.supabase.co as SUPABASE_URL."
            $failed = $true
            continue
        }

        $response = Invoke-WebRequest `
            -Uri ($projectUri.GetLeftPart([System.UriPartial]::Authority) + $endpoint) `
            -Headers @{ apikey = $config[$keyName] } `
            -UserAgent 'PRM393-Backend-Connection-Check/1.0' `
            -MaximumRedirection 0 `
            -UseBasicParsing `
            -TimeoutSec 20 `
            -ErrorAction Stop

        if ([int]$response.StatusCode -eq 200) {
            Write-Host "[PASS] ${name}: HTTP 200 - Supabase API accepted the configuration."
        } else {
            Write-Host "[FAIL] ${name}: HTTP $([int]$response.StatusCode)."
            $failed = $true
        }
    } catch {
        # Never print the exception body, request headers, or environment values.
        if ($_.Exception.Response) {
            Write-Host "[FAIL] ${name}: HTTP $([int]$_.Exception.Response.StatusCode)."
        } else {
            Write-Host "[FAIL] ${name}: could not connect. Check .env, network, and TLS settings."
        }
        $failed = $true
    }
}

Write-Host 'This check does not verify table access, RLS, or Google sign-in.'
if ($failed) { exit 1 }
exit 0
