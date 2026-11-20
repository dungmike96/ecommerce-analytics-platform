# ============================================================
# ZOSEO ECOMMERCE DWH - TEST PIPELINE (6 luồng ingestion)
# File: automation\test_run_data_pipeline.ps1
#
# Exit codes:
#   0 = SUCCESS
#   1 = FAILED
#   2 = SKIPPED (instance khác đang chạy)
# ============================================================

$ErrorActionPreference = "Stop"

# Python in UTF-8: tránh lỗi mã hóa khi in tiếng Việt trên Windows (cp1252)
$env:PYTHONUTF8       = "1"
$env:PYTHONIOENCODING = "utf-8"


# ============================================================
# CONFIG
# ============================================================

# $PSScriptRoot = <project>\automation
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# $true = chạy dbt build sau ingestion
$RunDbtBuild = $true

$PythonExe     = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$DbtExe        = Join-Path $ProjectRoot ".venv\Scripts\dbt.exe"
$DbtProjectDir = Join-Path $ProjectRoot "dbt"
$IngestionDir  = Join-Path $ProjectRoot "ingestion"

$OrdersIngestionScript     = Join-Path $IngestionDir "ingest_nhanh_orders.py"
$CustomersIngestionScript  = Join-Path $IngestionDir "ingest_nhanh_customers.py"
$ProductsIngestionScript   = Join-Path $IngestionDir "ingest_nhanh_products_inventory.py"
$CategoriesIngestionScript = Join-Path $IngestionDir "ingest_nhanh_categories.py"
$Ga4IngestionScript        = Join-Path $IngestionDir "ingest_ga4_mkt.py"
$SheetsIngestionScript     = Join-Path $IngestionDir "ingest_google_sheets_expenses.py"


# ------------------------------------------------------------
# GA4 PARAMETERS
# ------------------------------------------------------------

# Property ID số (memory: 559523192)
$Ga4Property = "559523192"

# Stream ID số, lấy trong GA4 Admin > Data streams
# Nếu còn placeholder, pipeline dừng ở STEP 1
$Ga4Stream = "16155876969"

# $true = chỉ đọc GA4, không ghi PostgreSQL
$Ga4DryRun = $false

# Ngày lấy dữ liệu: hôm qua (GA4 có độ trễ)
$Ga4Date = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")

$Ga4Args = @(
    "--property", $Ga4Property,
    "--stream",   $Ga4Stream,
    "--start",    $Ga4Date,
    "--end",      $Ga4Date
)
if ($Ga4DryRun) {
    $Ga4Args += "--dry-run"
}


# ------------------------------------------------------------
# DANH SÁCH 6 LUỒNG (thứ tự chạy)
# ------------------------------------------------------------

$IngestionSteps = @(
    @{ Name = "orders";             Script = $OrdersIngestionScript;     Args = @() },
    @{ Name = "customers";          Script = $CustomersIngestionScript;  Args = @() },
    @{ Name = "products_inventory"; Script = $ProductsIngestionScript;   Args = @() },
    @{ Name = "categories";         Script = $CategoriesIngestionScript; Args = @() },
    @{ Name = "ga4_mkt";            Script = $Ga4IngestionScript;        Args = $Ga4Args },
    @{ Name = "google_sheets";      Script = $SheetsIngestionScript;     Args = @() }
)


# ------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------

$LogDir    = Join-Path $ProjectRoot "logs\automation"
$LockFile  = Join-Path $LogDir "data_pipeline_test.lock"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $LogDir "data_pipeline_test_$Timestamp.log"

$ExitCode  = 1
$LockOwned = $false


# ============================================================
# CREATE LOG DIRECTORY
# ============================================================

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null


# ============================================================
# LOG FUNCTION
# ============================================================

function Write-PipelineLog {
    param([string]$Message)

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "$Time | $Message"

    Write-Host $Line
    Add-Content -Path $LogFile -Value $Line -Encoding UTF8
}


# ============================================================
# NATIVE COMMAND HELPERS
#
# Trong PowerShell 5.1, với ErrorActionPreference = "Stop",
# stderr của lệnh native có thể bị coi là lỗi dừng script.
# Hai hàm dưới đây hạ mức đó xuống cục bộ trong hàm và
# quyết định thành công/thất bại chỉ bằng $LASTEXITCODE.
# ============================================================

# Chạy lệnh native, ghi từng dòng output (cả stderr) vào console và log.
# Trả về exit code.
function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $ErrorActionPreference = "Continue"

    & $FilePath @ArgumentList 2>&1 | ForEach-Object {
        $Line = "$_"
        Write-Host $Line
        Add-Content -Path $LogFile -Value $Line -Encoding UTF8
    }

    return $LASTEXITCODE
}

# Chạy lệnh native và trả về output đã gom lại cùng exit code.
function Invoke-NativeCapture {
    param([scriptblock]$Command)

    $ErrorActionPreference = "Continue"

    $Output = & $Command 2>&1 | ForEach-Object { "$_" }

    return [PSCustomObject]@{
        Output   = (($Output -join "`n").Trim())
        ExitCode = $LASTEXITCODE
    }
}


# ============================================================
# CONCURRENCY LOCK
# ============================================================

function Acquire-PipelineLock {

    if (Test-Path $LockFile) {

        $ExistingPid = $null
        try {
            $ExistingPid = (Get-Content $LockFile -ErrorAction Stop |
                Select-Object -First 1).Trim()
        }
        catch {
            $ExistingPid = $null
        }

        if ($ExistingPid -match '^\d+$') {
            $ExistingProcess = Get-Process -Id ([int]$ExistingPid) -ErrorAction SilentlyContinue

            if ($null -ne $ExistingProcess) {
                Write-PipelineLog "TEST PIPELINE SKIPPED - another instance is running (PID=$ExistingPid)"
                return $false
            }
        }

        Write-PipelineLog "Stale lock detected - removing old lock"
        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    }

    Set-Content -Path $LockFile -Value $PID -Encoding ASCII
    return $true
}


# ============================================================
# INGESTION STEP (dùng chung cho 6 luồng)
# ============================================================

function Invoke-IngestionStep {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string[]]$ScriptArgs = @()
    )

    Write-PipelineLog "INGESTION START - $Name"

    $CommandArgs = @($ScriptPath) + $ScriptArgs

    $StepExitCode = Invoke-LoggedCommand -FilePath $PythonExe -ArgumentList $CommandArgs

    if ($StepExitCode -ne 0) {
        throw "$Name ingestion FAILED (exit code $StepExitCode)"
    }

    Write-PipelineLog "INGESTION SUCCESS - $Name"
}


# ============================================================
# PIPELINE START
# ============================================================

Write-PipelineLog "============================================================"
Write-PipelineLog "ZOSEO TEST PIPELINE START"
Write-PipelineLog "Project root: $ProjectRoot"
Write-PipelineLog "Process ID: $PID"
Write-PipelineLog "============================================================"


try {

    # ========================================================
    # STEP 1 - CHECK FILES
    # ========================================================

    Write-PipelineLog "STEP 1 - Checking project files"

    if (-not (Test-Path $PythonExe)) {
        throw "Python executable not found: $PythonExe"
    }

    foreach ($Step in $IngestionSteps) {
        if (-not (Test-Path $Step.Script)) {
            throw "Ingestion script not found ($($Step.Name)): $($Step.Script)"
        }
    }

    # Chặn sớm: không để chạy 4 luồng đầu rồi mới lỗi ở GA4
    if ($Ga4Stream -notmatch '^\d+$') {
        throw "Ga4Stream chưa được đặt (đang là '$Ga4Stream'). Điền Stream ID số trong GA4 Admin."
    }

    if ($RunDbtBuild) {
        if (-not (Test-Path $DbtExe)) {
            throw "dbt executable not found: $DbtExe"
        }
        if (-not (Test-Path $DbtProjectDir)) {
            throw "dbt project directory not found: $DbtProjectDir"
        }
    }

    Write-PipelineLog "Project files OK"


    # ========================================================
    # STEP 2 - LOCK
    # ========================================================

    Write-PipelineLog "STEP 2 - Checking concurrency lock"

    if (-not (Acquire-PipelineLock)) {
        exit 2
    }

    $LockOwned = $true
    Write-PipelineLog "Pipeline lock acquired"


    # ========================================================
    # STEP 3 - DOCKER
    # ========================================================

    Write-PipelineLog "STEP 3 - Checking Docker"

    if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI was not found in PATH"
    }

    $DockerInfo = Invoke-NativeCapture { docker info }
    if ($DockerInfo.ExitCode -ne 0) {
        throw "Docker Engine is not available"
    }

    Write-PipelineLog "Docker OK"


    # ========================================================
    # STEP 4 - POSTGRES
    # ========================================================

    Write-PipelineLog "STEP 4 - Checking PostgreSQL container"

    $Inspect = Invoke-NativeCapture { docker inspect -f '{{.State.Running}}' postgres_docker }
    if ($Inspect.ExitCode -ne 0 -or $Inspect.Output -ne "true") {
        throw "postgres_docker is not running"
    }

    $Ready = Invoke-NativeCapture { docker exec postgres_docker pg_isready -U postgres -d data_center }
    if ($Ready.ExitCode -ne 0) {
        throw "PostgreSQL data_center is not ready"
    }

    Write-PipelineLog "PostgreSQL OK"


    # ========================================================
    # STEP 5 - 6 LUỒNG INGESTION
    # ========================================================

    Write-PipelineLog "STEP 5 - Starting ingestion (6 flows)"

    foreach ($Step in $IngestionSteps) {
        Invoke-IngestionStep `
            -Name       $Step.Name `
            -ScriptPath $Step.Script `
            -ScriptArgs $Step.Args
    }

    Write-PipelineLog "STEP 5 - All ingestion flows completed"


    # ========================================================
    # STEP 6 - DBT BUILD
    # ========================================================

    if ($RunDbtBuild) {

        Write-PipelineLog "STEP 6 - Starting dbt build"

        Push-Location $DbtProjectDir
        try {
            $DbtCode = Invoke-LoggedCommand -FilePath $DbtExe -ArgumentList @("build")

            if ($DbtCode -ne 0) {
                throw "dbt build FAILED (exit code $DbtCode)"
            }
        }
        finally {
            Pop-Location
        }

        Write-PipelineLog "STEP 6 - dbt build SUCCESS"
    }
    else {
        Write-PipelineLog "STEP 6 - dbt build SKIPPED (RunDbtBuild = false)"
    }


    Write-PipelineLog "============================================================"
    Write-PipelineLog "TEST PIPELINE SUCCESS"
    Write-PipelineLog "============================================================"

    $ExitCode = 0
}
catch {

    Write-PipelineLog "============================================================"
    Write-PipelineLog "TEST PIPELINE FAILED"
    Write-PipelineLog "ERROR: $($_.Exception.Message)"
    Write-PipelineLog "============================================================"

    $ExitCode = 1
}
finally {

    if ($LockOwned -and (Test-Path $LockFile)) {
        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
        Write-PipelineLog "Pipeline lock released"
    }
}


# ============================================================
# RETURN EXIT CODE
# ============================================================

exit $ExitCode