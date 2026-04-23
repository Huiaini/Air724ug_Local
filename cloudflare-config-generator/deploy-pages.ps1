param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [string]$Branch,

    [switch]$CreateProject,

    [string]$ProductionBranch = "main"
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name"
    }
}

function Stage-Files {
    param(
        [string]$SourceRoot,
        [string]$StageRoot
    )

    if (Test-Path $StageRoot) {
        Remove-Item -LiteralPath $StageRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $StageRoot | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $StageRoot "vendor") | Out-Null

    Copy-Item -LiteralPath (Join-Path $SourceRoot "index.html") -Destination $StageRoot
    Copy-Item -LiteralPath (Join-Path $SourceRoot "styles.css") -Destination $StageRoot
    Copy-Item -LiteralPath (Join-Path $SourceRoot "app.js") -Destination $StageRoot
    Copy-Item -LiteralPath (Join-Path $SourceRoot "vendor\crypto-js.min.js") -Destination (Join-Path $StageRoot "vendor")
}

Require-Command "wrangler"

$siteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $siteRoot
$stageRoot = Join-Path $repoRoot ("_temp\cloudflare-pages-upload-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Host "Checking Wrangler login state..."
& wrangler whoami | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Wrangler is not logged in. Run: wrangler login"
}

Write-Host "Preparing clean upload directory..."
Stage-Files -SourceRoot $siteRoot -StageRoot $stageRoot

if ($CreateProject) {
    Write-Host "Creating Pages project '$ProjectName'..."
    & wrangler pages project create $ProjectName --production-branch $ProductionBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create Pages project: $ProjectName"
    }
}

$deployArgs = @("pages", "deploy", $stageRoot, "--project-name", $ProjectName)
if ($Branch) {
    $deployArgs += "--branch=$Branch"
}

Write-Host "Deploying static assets to Cloudflare Pages..."
& wrangler @deployArgs
if ($LASTEXITCODE -ne 0) {
    throw "Wrangler deploy failed."
}

Write-Host ""
Write-Host "Deploy complete."
Write-Host "Project: $ProjectName"
Write-Host "Upload dir: $stageRoot"
if ($Branch) {
    Write-Host "Branch: $Branch"
} else {
    Write-Host "Branch: production"
}
