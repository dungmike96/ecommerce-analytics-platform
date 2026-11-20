# ============================================================
# ZOSEO ECOMMERCE DWH - TEST PIPELINE (6 luồng ingestion)
# File: automation\test_run_data_pipeline_diagnostic.ps1
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

# Ẩn FutureWarning từ google.api_core / google.analytics để log sạch, tránh che lỗi thật
$env:PYTHONWARNINGS   = "ignore::FutureWarning"


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
# LOGGING & DIAGNOSTIC STATE
# ------------------------------------------------------------

$LogDir           = Join-Path $ProjectRoot "logs\automation"
$LockFile         = Join-Path $LogDir "data_pipeline_test.lock"
$Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile          = Join-Path $LogDir "data_pipeline_test_$Timestamp.log"
$FailureReportLog = Join-Path $LogDir "data_pipeline_test_${Timestamp}_FAILURE_REPORT.txt"

$ExitCode  = 1
$LockOwned = $false

# Biến theo dõi trạng thái phục vụ điều tra nguyên nhân dừng
$script:CurrentStep         = "INIT"
$script:CurrentCommand      = ""
$script:LastCommandExitCode = $null
$script:CurrentStepLines    = [System.Collections.Generic.List[string]]::new()
$script:StepHistory         = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:StepStartTime       = Get-Date


# ============================================================
# CREATE LOG DIRECTORY
# ============================================================

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null


# ============================================================
# LOG & TRACKING FUNCTIONS
# ============================================================

function Write-PipelineLog {
    param([string]$Message)

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "$Time | $Message"

    Write-Host $Line
    Add-Content -Path $LogFile -Value $Line -Encoding UTF8
}

function Start-TrackedStep {
    param([string]$StepName)

    $script:CurrentStep         = $StepName
    $script:CurrentCommand      = ""
    $script:LastCommandExitCode = $null
    $script:CurrentStepLines.Clear()
    $script:StepStartTime       = Get-Date
}

function Complete-TrackedStep {
    param(
        [string]$Status = "SUCCESS",
        [string]$Detail = ""
    )

    $Duration = [math]::Round(((Get-Date) - $script:StepStartTime).TotalSeconds, 2)
    $script:StepHistory.Add([PSCustomObject]@{
        Step     = $script:CurrentStep
        Status   = $Status
        Duration = "${Duration}s"
        Detail   = $Detail
    })
}


# ============================================================
# NATIVE COMMAND HELPERS
#
# Trong PowerShell 5.1, với ErrorActionPreference = "Stop",
# stderr của lệnh native có thể bị coi là lỗi dừng script.
# Hai hàm dưới đây hạ mức đó xuống cục bộ trong hàm và
# quyết định thành công/thất bại chỉ bằng $LASTEXITCODE.
# ============================================================

# Chạy lệnh native, ghi từng dòng output (cả stderr) vào console, log
# và lưu vào bộ đệm $script:CurrentStepLines để phân tích nếu lỗi.
function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $ErrorActionPreference = "Continue"
    $script:CurrentStepLines.Clear()

    $FormattedArgs = ($ArgumentList | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }) -join " "
    $script:CurrentCommand = "`"$FilePath`" $FormattedArgs".Trim()

    & $FilePath @ArgumentList 2>&1 | ForEach-Object {
        $Line = "$_"
        $script:CurrentStepLines.Add($Line)
        Write-Host $Line
        Add-Content -Path $LogFile -Value $Line -Encoding UTF8
    }

    $script:LastCommandExitCode = $LASTEXITCODE
    return $LASTEXITCODE
}

# Chạy lệnh native và trả về output đã gom lại cùng exit code.
function Invoke-NativeCapture {
    param([scriptblock]$Command)

    $ErrorActionPreference = "Continue"
    $script:CurrentStepLines.Clear()
    $script:CurrentCommand = $Command.ToString().Trim()

    $Output = & $Command 2>&1 | ForEach-Object {
        $Line = "$_"
        $script:CurrentStepLines.Add($Line)
        $Line
    }

    $script:LastCommandExitCode = $LASTEXITCODE
    return [PSCustomObject]@{
        Output   = (($Output -join "`n").Trim())
        ExitCode = $LASTEXITCODE
    }
}


# ============================================================
# ROOT CAUSE INVESTIGATION (ĐIỀU TRA NGUYÊN NHÂN DỪNG PIPELINE)
# ============================================================

function Invoke-FailureInvestigation {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $ReportLines = [System.Collections.Generic.List[string]]::new()

    $ReportLines.Add("============================================================")
    $ReportLines.Add("BÁO CÁO ĐIỀU TRA NGUYÊN NHÂN DỪNG PIPELINE (ROOT CAUSE)")
    $ReportLines.Add("============================================================")
    $ReportLines.Add("Thời điểm dừng      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $ReportLines.Add("Điểm dừng (Step)    : $($script:CurrentStep)")
    $ReportLines.Add("Thông báo lỗi       : $($ErrorRecord.Exception.Message)")

    if ($null -ne $script:LastCommandExitCode) {
        $ReportLines.Add("Exit Code lệnh cuối : $($script:LastCommandExitCode)")
    }
    if (-not [string]::IsNullOrWhiteSpace($script:CurrentCommand)) {
        $ReportLines.Add("Lệnh đang thực thi  : $($script:CurrentCommand)")
    }
    if ($null -ne $ErrorRecord.InvocationInfo) {
        $ReportLines.Add("Vị trí trong PS1    : Dòng $($ErrorRecord.InvocationInfo.ScriptLineNumber) | $($ErrorRecord.InvocationInfo.Line.Trim())")
    }

    # 1. Lịch sử chạy từng bước để biết pipeline đi được tới đâu
    $ReportLines.Add("")
    $ReportLines.Add("--- [1] TIẾN TRÌNH CÁC BƯỚC TRƯỚC KHI DỪNG ---")
    if ($script:StepHistory.Count -eq 0) {
        $ReportLines.Add("  (Chưa hoàn thành bước nào trước khi lỗi)")
    }
    else {
        foreach ($Item in $script:StepHistory) {
            $Icon = if ($Item.Status -eq "SUCCESS") { "[OK]    " } else { "[FAILED]" }
            $Extra = if ($Item.Detail) { " -> $($Item.Detail)" } else { "" }
            $ReportLines.Add("  $Icon $($Item.Step) ($($Item.Duration))$Extra")
        }
    }

    # 2. Trích xuất lỗi gốc từ output của bước bị dừng (loại bỏ FutureWarning nhiễu)
    $ReportLines.Add("")
    $ReportLines.Add("--- [2] TRÍCH XUẤT LỖI GỐC TỪ OUTPUT BƯỚC BỊ DỪNG ---")

    $CleanLines = @($script:CurrentStepLines | Where-Object {
        $_ -notmatch 'FutureWarning:' -and $_ -notmatch 'warnings\.warn\(message, FutureWarning\)'
    })

    if ($CleanLines.Count -eq 0) {
        $ReportLines.Add("  (Lệnh không trả về output trên stdout/stderr - lỗi do kiểm tra điều kiện trong PowerShell)")
    }
    else {
        # Tìm vị trí Python Traceback nếu có
        $TracebackIdx = -1
        for ($i = 0; $i -lt $CleanLines.Count; $i++) {
            if ($CleanLines[$i] -match 'Traceback \(most recent call last\):') {
                $TracebackIdx = $i
                break
            }
        }

        if ($TracebackIdx -ge 0) {
            $ReportLines.Add("  >> Phát hiện Python Traceback:")
            for ($j = $TracebackIdx; $j -lt $CleanLines.Count; $j++) {
                $ReportLines.Add("     $($CleanLines[$j])")
            }
        }
        else {
            # Lọc các dòng chứa từ khóa lỗi phổ biến (dbt, Postgres, Docker, API...)
            $MatchedErrors = @($CleanLines | Where-Object {
                $_ -match '(?i)\b(error|exception|fatal|fail|failed|denied|refused|timeout|invalid|not found|traceback)\b'
            })

            if ($MatchedErrors.Count -gt 0) {
                $ReportLines.Add("  >> Các dòng cảnh báo/lỗi phát hiện được:")
                $MatchedErrors | Select-Object -Last 15 | ForEach-Object {
                    $ReportLines.Add("     $_")
                }
            }

            $ReportLines.Add("")
            $ReportLines.Add("  >> 15 dòng output cuối cùng của bước này:")
            $CleanLines | Select-Object -Last 15 | ForEach-Object {
                $ReportLines.Add("     $_")
            }
        }
    }

    # 3. Chẩn đoán tự động & gợi ý kiểm tra theo từng phân hệ
    $ReportLines.Add("")
    $ReportLines.Add("--- [3] CHẨN ĐOÁN NHANH & HƯỚNG XỬ LÝ ---")

    switch -Wildcard ($script:CurrentStep) {
        "STEP 1*" {
            $ReportLines.Add("  * Nguyên nhân: Thiếu file thực thi (.venv/dbt), thiếu script Python hoặc chưa cấu hình GA4 Stream ID.")
            $ReportLines.Add("  * Xử lý: Kiểm tra đường dẫn thư mục dự án (tránh ký tự đặc biệt nếu cần) và biến cấu hình ở đầu file.")
        }
        "STEP 3*" {
            $ReportLines.Add("  * Nguyên nhân: Docker Desktop chưa khởi động hoặc Docker Engine đang treo.")
            $ReportLines.Add("  * Xử lý: Mở Docker Desktop trên Windows và đợi biểu tượng cá voi chuyển sang trạng thái Running.")
        }
        "STEP 4*" {
            $ReportLines.Add("  * Nguyên nhân: Container 'postgres_docker' bị tắt, restart liên tục hoặc database 'data_center' chưa sẵn sàng.")
            try {
                $PgState = docker ps -a --filter "name=postgres_docker" --format "{{.Names}} | Status: {{.Status}}" 2>&1
                $ReportLines.Add("  * Trạng thái container hiện tại: $PgState")
                $PgLogs = docker logs --tail 10 postgres_docker 2>&1
                $ReportLines.Add("  * 10 dòng log cuối của postgres_docker:")
                foreach ($L in $PgLogs) { $ReportLines.Add("     $L") }
            }
            catch {
                $ReportLines.Add("  * Không thể truy vấn docker logs cho postgres_docker.")
            }
        }
        "STEP 5 - INGESTION (ga4_mkt)*" {
            $ReportLines.Add("  * Nguyên nhân: Lỗi gọi Google Analytics Data API (sai Property/Stream ID, hết quota, hoặc lỗi file credentials JSON).")
            $ReportLines.Add("  * Lệnh chạy tay để debug riêng luồng này:")
            $ReportLines.Add("    $($script:CurrentCommand)")
        }
        "STEP 5 - INGESTION (google_sheets)*" {
            $ReportLines.Add("  * Nguyên nhân: Lỗi đọc Google Sheets (thiếu quyền share sheet cho Service Account, sai tên tab hoặc lỗi mạng).")
            $ReportLines.Add("  * Lệnh chạy tay để debug riêng luồng này:")
            $ReportLines.Add("    $($script:CurrentCommand)")
        }
        "STEP 5 - INGESTION*" {
            $ReportLines.Add("  * Nguyên nhân: Lỗi API Nhanh.vn (hết hạn token, rate limit, thay đổi schema JSON) hoặc lỗi ghi vào PostgreSQL.")
            $ReportLines.Add("  * Lệnh chạy tay để debug riêng luồng này:")
            $ReportLines.Add("    $($script:CurrentCommand)")
        }
        "STEP 6 - DBT BUILD*" {
            $ReportLines.Add("  * Nguyên nhân: Model SQL bị lỗi cú pháp/schema hoặc dbt test phát hiện dữ liệu vi phạm ràng buộc (unique, not_null, relationships).")
            $ReportLines.Add("  * Xử lý: Kiểm tra tên model/test bị FAIL ở mục [2] phía trên và chạy thử: dbt build --select <tên_model_lỗi>")
        }
        default {
            $ReportLines.Add("  * Nguyên nhân: Lỗi ngoại lệ không xác định trong quá trình chạy script.")
        }
    }

    $ReportLines.Add("")
    $ReportLines.Add("File log đầy đủ       : $LogFile")
    $ReportLines.Add("File báo cáo lỗi này  : $FailureReportLog")
    $ReportLines.Add("============================================================")

    # In toàn bộ báo cáo ra Console, ghi vào Log chính và xuất riêng file FAILURE_REPORT
    foreach ($Line in $ReportLines) {
        Write-PipelineLog $Line
    }
    Set-Content -Path $FailureReportLog -Value $ReportLines -Encoding UTF8
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

    Start-TrackedStep -StepName "STEP 5 - INGESTION ($Name)"
    Write-PipelineLog "INGESTION START - $Name"

    $CommandArgs = @($ScriptPath) + $ScriptArgs

    $StepExitCode = Invoke-LoggedCommand -FilePath $PythonExe -ArgumentList $CommandArgs

    if ($StepExitCode -ne 0) {
        throw "$Name ingestion FAILED (exit code $StepExitCode)"
    }

    Complete-TrackedStep -Status "SUCCESS"
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

    Start-TrackedStep -StepName "STEP 1 - CHECK FILES"
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

    Complete-TrackedStep -Status "SUCCESS"
    Write-PipelineLog "Project files OK"


    # ========================================================
    # STEP 2 - LOCK
    # ========================================================

    Start-TrackedStep -StepName "STEP 2 - CONCURRENCY LOCK"
    Write-PipelineLog "STEP 2 - Checking concurrency lock"

    if (-not (Acquire-PipelineLock)) {
        exit 2
    }

    $LockOwned = $true
    Complete-TrackedStep -Status "SUCCESS"
    Write-PipelineLog "Pipeline lock acquired"


    # ========================================================
    # STEP 3 - DOCKER
    # ========================================================

    Start-TrackedStep -StepName "STEP 3 - DOCKER"
    Write-PipelineLog "STEP 3 - Checking Docker"

    if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI was not found in PATH"
    }

    $DockerInfo = Invoke-NativeCapture { docker info }
    if ($DockerInfo.ExitCode -ne 0) {
        throw "Docker Engine is not available"
    }

    Complete-TrackedStep -Status "SUCCESS"
    Write-PipelineLog "Docker OK"


    # ========================================================
    # STEP 4 - POSTGRES
    # ========================================================

    Start-TrackedStep -StepName "STEP 4 - POSTGRES"
    Write-PipelineLog "STEP 4 - Checking PostgreSQL container"

    $Inspect = Invoke-NativeCapture { docker inspect -f '{{.State.Running}}' postgres_docker }
    if ($Inspect.ExitCode -ne 0 -or $Inspect.Output -ne "true") {
        throw "postgres_docker is not running"
    }

    $Ready = Invoke-NativeCapture { docker exec postgres_docker pg_isready -U postgres -d data_center }
    if ($Ready.ExitCode -ne 0) {
        throw "PostgreSQL data_center is not ready"
    }

    Complete-TrackedStep -Status "SUCCESS"
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

        Start-TrackedStep -StepName "STEP 6 - DBT BUILD"
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

        Complete-TrackedStep -Status "SUCCESS"
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

    Complete-TrackedStep -Status "FAILED" -Detail $_.Exception.Message

    Write-PipelineLog "============================================================"
    Write-PipelineLog "TEST PIPELINE FAILED"
    Write-PipelineLog "ERROR: $($_.Exception.Message)"
    Write-PipelineLog "============================================================"

    # Chạy module điều tra & xuất báo cáo nguyên nhân dừng pipeline
    Invoke-FailureInvestigation -ErrorRecord $_

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
