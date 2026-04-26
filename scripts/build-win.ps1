#!/usr/bin/env pwsh
# Windows-compatible build script for openclaw-zero-token
# Replaces: scripts/bundle-a2ui.sh (bash) + build steps

param(
    [switch]$SkipA2UI,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ROOT = $PSScriptRoot ? $PSScriptRoot : (Get-Location).Path
$CWD = $PWD

function Write-Step($message) {
    Write-Host "[BUILD] $message" -ForegroundColor Cyan
}

function Write-Done($message) {
    Write-Host "[DONE] $message" -ForegroundColor Green
}

function Write-Fail($message) {
    Write-Host "[FAIL] $message" -ForegroundColor Red
    exit 1
}

# Change to project root
Set-Location $ROOT

# Step 1: canvas:a2ui:bundle (skip if --SkipA2UI or if sources don't exist)
$A2UI_RENDERER = "$ROOT\vendor\a2ui\renderers\lit"
$A2UI_APP = "$ROOT\apps\shared\OpenClawKit\Tools\CanvasA2UI"
$OUTPUT_FILE = "$ROOT\src\canvas-host\a2ui\a2ui.bundle.js"

if (-not $SkipA2UI) {
    if ((Test-Path $A2UI_RENDERER) -and (Test-Path $A2UI_APP)) {
        Write-Step "Bundling A2UI..."
        
        # Check for rolldown
        $ROLLDOWN = Get-Command rolldown -ErrorAction SilentlyContinue
        if (-not $ROLLDOWN) {
            $ROLLDOWN = Get-Command npx -ErrorAction SilentlyContinue
        }
        
        try {
            # Build TypeScript first
            npx tsc -p "$A2UI_RENDERER\tsconfig.json" 2>$null
            
            # Build with rolldown
            if ($ROLLDOWN) {
                if ($Verbose) { $env:OPENCLAW_BUILD_VERBOSE = "1" }
                npx rolldown -c "$A2UI_APP_DIR\rolldown.config.mjs"
            } else {
                npx dlx rolldown -c "$A2UI_APP\rolldown.config.mjs"
            }
            Write-Done "A2UI bundle complete"
        } catch {
            Write-Host "A2UI bundle skipped (will use prebuilt if exists)" -ForegroundColor Yellow
        }
    } elseif (Test-Path $OUTPUT_FILE) {
        Write-Host "Using prebuilt A2UI bundle" -ForegroundColor Yellow
    } else {
        Write-Host "Warning: A2UI sources missing and no prebuilt bundle" -ForegroundColor Yellow
    }
}

# Step 2: TypeScript build
Write-Step "Building TypeScript..."
npx tsdown --config-loader unrun --logLevel $(if ($Verbose) { "info" } else { "warn" })
if ($LASTEXITCODE -ne 0) { Write-Fail "tsdown build failed" }
Write-Done "TypeScript build complete"

# Step 3: Copy plugin SDK root alias
Write-Step "Copying plugin SDK root alias..."
node scripts/copy-plugin-sdk-root-alias.mjs
if ($LASTEXITCODE -ne 0) { Write-Fail "copy-plugin-sdk-root-alias failed" }
Write-Done "Plugin SDK root alias copied"

# Step 4: Build plugin SDK DTS
Write-Step "Building plugin SDK declarations..."
npx tsc -p tsconfig.plugin-sdk.dts.json
if ($LASTEXITCODE -ne 0) { Write-Fail "plugin-sdk:dts failed" }
Write-Done "Plugin SDK declarations complete"

# Step 5-12: Post-build scripts
$scripts = @(
    "write-plugin-sdk-entry-dts.ts",
    "canvas-a2ui-copy.ts",
    "copy-hook-metadata.ts",
    "copy-export-html-templates.ts",
    "write-build-info.ts",
    "write-cli-startup-metadata.ts",
    "write-cli-compat.ts"
)

foreach ($script in $scripts) {
    Write-Step "Running $script..."
    node --import tsx "scripts\$script"
    if ($LASTEXITCODE -ne 0) { Write-Fail "$script failed" }
}

Write-Done "Build complete!"
Write-Host ""
Write-Host "Output:" -ForegroundColor Cyan
Write-Host "  dist/               - Compiled JavaScript"
Write-Host "  dist/plugin-sdk/    - Plugin SDK types"
Write-Host "  dist/extensions/    - Extension builds"