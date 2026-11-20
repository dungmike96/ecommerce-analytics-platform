# ============================================================
# ZOSEO ECOMMERCE DWH
# AUTOMATED POSTGRESQL BACKUP -> AMAZON S3
#
# Exit codes:
#   0 = SUCCESS
#   1 = FAILED
#   2 = SKIPPED because another backup is running
# ============================================================

$ErrorActionPreference = "Stop"


# ============================================================
# CONFIG
# ============================================================

# $PSScriptRoot = <project>\automation
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$ContainerName = "postgres_docker"
$DatabaseName  = "data_center"
$DatabaseUser  = "postgres"

$BackupDir = "D:\ZOSEO_Backups\ecommerce-dwh\daily"
$LogDir    = Join-Path $ProjectRoot "logs\automation"
$LockFile  = Join-Path $LogDir "backup_s3.lock"

$AwsExe     = "D:\Programs\Amazon\aws.exe"
$AwsProfile = "ecommerce-backup"

$S3Bucket = "zoseo-ecommerce-dwh-backup-2026-dung01"
$S3Prefix = "postgres/data_center/daily"

# Giữ N file dump gần nhất trên máy local
$LocalRetentionCount = 14

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$BackupName              = "data_center_$Timestamp.dump"
$BackupPath              = Join-Path $BackupDir $BackupName
$ContainerBackupPath     = "/tmp/$BackupName"
$ValidationContainerPath = "/tmp/backup_validation_$Timestamp.dump"
$S3Key                   = "$S3Prefix/$BackupName"

$LogFile = Join-Path $LogDir "backup_s3_$Timestamp.log"

# Trạng thái
$ExitCode   = 1
$LockOwned  = $false
$BackupFile = $null
$BackupHash = $null


# ============================================================
# CREATE REQUIRED DIRECTORIES
# ============================================================

New-Item -ItemType Directory -Force -Path $LogDir    | Out-Null
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null


# ============================================================
# LOG FUNCTION
# ============================================================

function Write-BackupLog {
    param([string]$Message)

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "$Time | $Message"

    Write-Host $Line
    Add-Content -Path $LogFile -Value $Line -Encoding UTF8
}


# ============================================================
# STALE LOCK CHECK
# Trả về $true nếu khóa đang thuộc về một tiến trình còn chạy.
# Trả về $false nếu khóa cũ (tiến trình đã kết thúc hoặc file lỗi).
# ============================================================

function Test-LockActive {
    param([string]$Path)

    $LockPid = $null
    try {
        $LockPid = (Get-Content -Path $Path -ErrorAction Stop |
            Select-Object -First 1).Trim()
    }
    catch {
        return $false
    }

    if ($LockPid -match '^\d+$') {
        $Proc = Get-Process -Id ([int]$LockPid) -ErrorAction SilentlyContinue
        if ($null -ne $Proc) {
            return $true
        }
    }

    return $false
}


# ============================================================
# CONCURRENCY LOCK
# ============================================================

if (Test-Path $LockFile) {

    if (Test-LockActive -Path $LockFile) {
        Write-BackupLog "BACKUP SKIPPED - another backup is running (lock: $LockFile)"
        exit 2
    }

    Write-BackupLog "Stale backup lock detected - removing old lock"
    Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue
}

Set-Content -Path $LockFile -Value $PID -Encoding ASCII
$LockOwned = $true


# ============================================================
# START
# ============================================================

Write-BackupLog "============================================================"
Write-BackupLog "ZOSEO POSTGRESQL -> S3 BACKUP START"
Write-BackupLog "============================================================"
Write-BackupLog "PID: $PID"
Write-BackupLog "Database: $DatabaseName"
Write-BackupLog "Backup file: $BackupPath"
Write-BackupLog "S3 target: s3://$S3Bucket/$S3Key"


try {

    # ========================================================
    # STEP 1 - CHECK REQUIRED COMMANDS
    # ========================================================

    Write-BackupLog "STEP 1 - Checking Docker and AWS CLI"

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI not found"
    }

    if (-not (Test-Path $AwsExe)) {
        throw "AWS CLI not found: $AwsExe"
    }

    Write-BackupLog "Docker CLI OK"
    Write-BackupLog "AWS CLI OK"


    # ========================================================
    # STEP 2 - CHECK POSTGRESQL CONTAINER
    # ========================================================

    Write-BackupLog "STEP 2 - Checking PostgreSQL container"

    $ContainerRunning = docker inspect -f '{{.State.Running}}' $ContainerName 2>$null

    if ($LASTEXITCODE -ne 0 -or "$ContainerRunning".Trim() -ne "true") {
        throw "$ContainerName is not running"
    }

    Write-BackupLog "PostgreSQL container OK"


    # ========================================================
    # STEP 3 - CHECK DATABASE CONNECTION
    # ========================================================

    Write-BackupLog "STEP 3 - Checking database connection"

    docker exec $ContainerName pg_isready -U $DatabaseUser -d $DatabaseName *> $null

    if ($LASTEXITCODE -ne 0) {
        throw "Database $DatabaseName is not ready"
    }

    Write-BackupLog "Database connection OK"


    # ========================================================
    # STEP 4 - CREATE POSTGRESQL CUSTOM DUMP
    # ========================================================

    Write-BackupLog "STEP 4 - Creating PostgreSQL backup"

    docker exec $ContainerName pg_dump -U $DatabaseUser -d $DatabaseName -F c -f $ContainerBackupPath

    if ($LASTEXITCODE -ne 0) {
        throw "pg_dump FAILED"
    }

    Write-BackupLog "pg_dump SUCCESS"


    # ========================================================
    # STEP 5 - COPY DUMP FROM CONTAINER TO LOCAL DISK
    # ========================================================

    Write-BackupLog "STEP 5 - Copying backup to local disk"

    docker cp "${ContainerName}:${ContainerBackupPath}" "$BackupPath"

    if ($LASTEXITCODE -ne 0) {
        throw "docker cp FAILED"
    }

    if (-not (Test-Path $BackupPath)) {
        throw "Backup file does not exist after docker cp"
    }

    $BackupFile = Get-Item $BackupPath

    if ($BackupFile.Length -le 0) {
        throw "Backup file size is 0 bytes"
    }

    Write-BackupLog "Local backup created successfully"
    Write-BackupLog "Backup size: $($BackupFile.Length) bytes"


    # ========================================================
    # STEP 6 - REMOVE TEMP DUMP FROM CONTAINER
    # ========================================================

    Write-BackupLog "STEP 6 - Removing temporary container dump"

    docker exec $ContainerName rm -f $ContainerBackupPath

    if ($LASTEXITCODE -ne 0) {
        throw "Could not remove temporary dump from container"
    }

    Write-BackupLog "Container temporary file removed"


    # ========================================================
    # STEP 7 - VALIDATE POSTGRESQL ARCHIVE
    # ========================================================

    Write-BackupLog "STEP 7 - Validating PostgreSQL archive"

    docker cp "$BackupPath" "${ContainerName}:${ValidationContainerPath}"

    if ($LASTEXITCODE -ne 0) {
        throw "Could not copy backup into container for validation"
    }

    docker exec $ContainerName pg_restore -l $ValidationContainerPath *> $null

    if ($LASTEXITCODE -ne 0) {
        throw "pg_restore archive validation FAILED"
    }

    Write-BackupLog "PostgreSQL archive validation SUCCESS"

    docker exec $ContainerName rm -f $ValidationContainerPath

    if ($LASTEXITCODE -ne 0) {
        throw "Could not remove validation file from container"
    }


    # ========================================================
    # STEP 8 - CALCULATE SHA-256
    # ========================================================

    Write-BackupLog "STEP 8 - Calculating SHA-256"

    $BackupHash = (Get-FileHash -Path $BackupPath -Algorithm SHA256).Hash

    if ([string]::IsNullOrWhiteSpace($BackupHash)) {
        throw "Could not calculate SHA-256"
    }

    Write-BackupLog "SHA256: $BackupHash"


    # ========================================================
    # STEP 9 - CHECK AWS AUTHENTICATION
    # ========================================================

    Write-BackupLog "STEP 9 - Checking AWS authentication"

    & $AwsExe sts get-caller-identity --profile $AwsProfile --output json *> $null

    if ($LASTEXITCODE -ne 0) {
        throw "AWS authentication FAILED for profile $AwsProfile"
    }

    Write-BackupLog "AWS authentication OK"


    # ========================================================
    # STEP 10 - UPLOAD BACKUP TO AMAZON S3
    # ========================================================

    Write-BackupLog "STEP 10 - Uploading backup to Amazon S3"

    & $AwsExe s3 cp "$BackupPath" "s3://$S3Bucket/$S3Key" --profile $AwsProfile --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "S3 upload FAILED"
    }

    Write-BackupLog "S3 upload SUCCESS"


    # ========================================================
    # STEP 11 - VERIFY S3 OBJECT
    # ========================================================

    Write-BackupLog "STEP 11 - Verifying S3 object"

    $HeadJson = & $AwsExe s3api head-object `
        --bucket $S3Bucket `
        --key $S3Key `
        --profile $AwsProfile `
        --output json

    if ($LASTEXITCODE -ne 0) {
        throw "S3 head-object FAILED"
    }

    # aws trả về nhiều dòng, phải nối lại trước khi parse JSON
    $Head = ($HeadJson -join "`n") | ConvertFrom-Json

    if (-not $Head) {
        throw "Could not read S3 object metadata"
    }

    if ([int64]$Head.ContentLength -ne [int64]$BackupFile.Length) {
        throw "S3 ContentLength ($($Head.ContentLength)) does not match local size ($($BackupFile.Length))"
    }

    Write-BackupLog "S3 object exists"
    Write-BackupLog "S3 ContentLength: $($Head.ContentLength) bytes"

    if ($Head.ServerSideEncryption) {
        Write-BackupLog "S3 encryption: $($Head.ServerSideEncryption)"
    }

    if ($Head.VersionId) {
        Write-BackupLog "S3 VersionId: $($Head.VersionId)"
    }


    # ========================================================
    # STEP 12 - LOCAL RETENTION (không làm fail job)
    #
    # Chỉ chạy sau khi dump, validate, upload và verify đã thành công.
    # Lỗi ở bước này chỉ ghi cảnh báo, vì backup đã nằm an toàn trên S3.
    # ========================================================

    Write-BackupLog "STEP 12 - Applying local backup retention"

    try {
        $LocalBackups = @(
            Get-ChildItem -Path $BackupDir -Filter "data_center_*.dump" |
                Sort-Object LastWriteTime -Descending
        )

        if ($LocalBackups.Count -gt $LocalRetentionCount) {

            $FilesToDelete = $LocalBackups | Select-Object -Skip $LocalRetentionCount

            foreach ($File in $FilesToDelete) {
                Write-BackupLog "Deleting old local backup: $($File.Name)"
                Remove-Item -Path $File.FullName -Force
            }
        }
        else {
            Write-BackupLog "No local backups need deletion"
        }

        Write-BackupLog "Local retention SUCCESS"
    }
    catch {
        Write-BackupLog "WARNING: local retention failed - $($_.Exception.Message)"
    }


    # ========================================================
    # SUCCESS
    # ========================================================

    Write-BackupLog "============================================================"
    Write-BackupLog "POSTGRESQL -> S3 BACKUP SUCCESS"
    Write-BackupLog "Backup: $BackupName"
    Write-BackupLog "SHA256: $BackupHash"
    Write-BackupLog "S3: s3://$S3Bucket/$S3Key"
    Write-BackupLog "============================================================"

    $ExitCode = 0
}
catch {

    Write-BackupLog "============================================================"
    Write-BackupLog "POSTGRESQL -> S3 BACKUP FAILED"
    Write-BackupLog "ERROR: $($_.Exception.Message)"
    Write-BackupLog "============================================================"

    $ExitCode = 1
}
finally {

    # --------------------------------------------------------
    # Dọn file tạm trong container (best-effort, không fatal)
    # --------------------------------------------------------

    try {
        docker exec $ContainerName rm -f $ContainerBackupPath *> $null
    }
    catch { }

    try {
        docker exec $ContainerName rm -f $ValidationContainerPath *> $null
    }
    catch { }


    # --------------------------------------------------------
    # Giải phóng khóa: chỉ xóa khi chính script này tạo khóa
    # --------------------------------------------------------

    if ($LockOwned -and (Test-Path $LockFile)) {
        Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue
        Write-BackupLog "Backup lock released"
    }
}

exit $ExitCode