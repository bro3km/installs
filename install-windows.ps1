# Installs / removes the programs listed in the README on Windows (via winget).
# Usage:  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 [-y]
#   -y   Don't ask for confirmation per package (answer "yes" to everything)

param(
    [Alias("yes")]
    [switch]$y
)

$ErrorActionPreference = "Continue"
$AutoYes = [bool]$y

function Info($msg)  { Write-Host ":: " -ForegroundColor Blue -NoNewline; Write-Host $msg }
function Ok($msg)    { Write-Host "==> " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Warn($msg)  { Write-Host "==> WARNING: " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Err($msg)   { Write-Host "==> ERROR: " -ForegroundColor Red -NoNewline; Write-Host $msg }

# Ask "question" [$true = default yes] -> $true / $false
function Ask([string]$Question, [bool]$DefaultYes = $true) {
    if ($AutoYes) {
        Info "$Question [auto: y]"
        return $true
    }
    $hint = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        Write-Host ":: " -ForegroundColor Blue -NoNewline
        $answer = (Read-Host "$Question $hint").Trim().ToLower()
        if ($answer -eq "") { return $DefaultYes }
        if (@("y", "yes") -contains $answer) { return $true }
        if (@("n", "no") -contains $answer) { return $false }
    }
}

$Items = @(
    @{ Cat = "Main";   Name = "Zen-Browser";               Ids = @("Zen-Team.Zen-Browser") }
    @{ Cat = "Main";   Name = "Only Office";               Ids = @("ONLYOFFICE.DesktopEditors") }
    @{ Cat = "Main";   Name = "Spotify";                   Ids = @("Spotify.Spotify") }
    @{ Cat = "Main";   Name = "VSCodium";                  Ids = @("VSCodium.VSCodium", "Microsoft.VisualStudioCode") }
    @{ Cat = "Main";   Name = "VM (VirtualBox)";           Ids = @("Oracle.VirtualBox") }
    @{ Cat = "Main";   Name = "WhatsApp";                  Ids = @("9NKSQGP7F2NH"); Source = "msstore" }
    @{ Cat = "Main";   Name = "Input Remapper (PowerToys)"; Ids = @("Microsoft.PowerToys"); Note = "Input Remapper is Linux only - using PowerToys (Keyboard Manager) as a replacement." }
    @{ Cat = "Main";   Name = "Git";                       Ids = @("Git.Git"); Post = "git" }
    @{ Cat = "Main";   Name = "GitHub CLI";                Ids = @("GitHub.cli"); Post = "gh" }
    @{ Cat = "Main";   Name = "Pipewire";                  Unsupported = $true }
    @{ Cat = "Main";   Name = "Screensharing";             Unsupported = $true }
    @{ Cat = "Lab";    Name = "Docker Desktop";            Ids = @("Docker.DockerDesktop") }
    @{ Cat = "Lab";    Name = "Tailscale";                 Ids = @("Tailscale.Tailscale") }
    @{ Cat = "Game";   Name = "Swiftpoint Control Center"; Ids = @("Swiftpoint.X1ControlPanel"); Url = "https://www.swiftpoint.com/" }
    @{ Cat = "Game";   Name = "Steam";                     Ids = @("Valve.Steam") }
    @{ Cat = "Game";   Name = "Discord";                   Ids = @("Discord.Discord") }
    @{ Cat = "Game";   Name = "Minecraft Launcher";        Ids = @("Mojang.MinecraftLauncher") }
    @{ Cat = "Game";   Name = "Prism Launcher";            Ids = @("PrismLauncher.PrismLauncher") }
    @{ Cat = "Game";   Name = "Heroic Games Launcher";     Ids = @("HeroicGamesLauncher.HeroicGamesLauncher") }
    @{ Cat = "School"; Name = "wxMaxima";                  Ids = @("wxMaxima-developers.wxMaxima", "Maxima.Maxima"); Url = "https://wxmaxima-developers.github.io/wxmaxima/download.html" }
    @{ Cat = "School"; Name = "IntelliJ IDEA";             Ids = @("JetBrains.IntelliJIDEA.Ultimate", "JetBrains.IntelliJIDEA.Community"); Url = "https://www.jetbrains.com/idea/download/" }
    @{ Cat = "School"; Name = "Zotero";                    Ids = @("DigitalScholar.Zotero") }
    @{ Cat = "School"; Name = "SafeExam Browser";          Ids = @("ETHZurich.SafeExamBrowser"); Url = "https://safeexambrowser.org/download_en.html" }
)
$Categories = @("Main", "Game", "Lab", "School")

$WingetCommon = @("--accept-source-agreements", "--disable-interactivity")

function Get-Source($item) { if ($item.Source) { $item.Source } else { "winget" } }

function Test-Installed([string]$id, [string]$source) {
    & winget list --id $id --exact --source $source @WingetCommon *> $null
    return $LASTEXITCODE -eq 0
}

function Test-Available([string]$id, [string]$source) {
    & winget show --id $id --exact --source $source @WingetCommon *> $null
    return $LASTEXITCODE -eq 0
}

function Install-Item($item) {
    $name = $item.Name
    if ($item.Unsupported) {
        Warn "$name is not available for Windows - skipped."
        return
    }
    $source = Get-Source $item

    foreach ($id in $item.Ids) {
        if (Test-Installed $id $source) {
            Ok "$name is already installed ($id)."
            Invoke-PostInstall $item
            return
        }
    }

    $chosen = $item.Ids | Where-Object { Test-Available $_ $source } | Select-Object -First 1
    if (-not $chosen) {
        Err "$name was not found in winget."
        if ($item.Url) {
            Info "Manual download: $($item.Url)"
            if (-not $AutoYes -and (Ask "Open download page?" $false)) { Start-Process $item.Url }
        }
        return
    }

    if ($item.Note) { Info $item.Note }
    if (-not (Ask "Install $name? ($chosen)")) { return }

    & winget install --id $chosen --exact --source $source --silent `
        --accept-package-agreements @WingetCommon
    if ($LASTEXITCODE -eq 0) {
        Ok "$name installed."
        Invoke-PostInstall $item
    } else {
        Err "$name could not be installed (exit code $LASTEXITCODE)."
    }
}

function Uninstall-Item($item) {
    $name = $item.Name
    if ($item.Unsupported) { return }
    $source = Get-Source $item

    $installed = @($item.Ids | Where-Object { Test-Installed $_ $source })
    if ($installed.Count -eq 0) {
        Info "$name is not installed."
        return
    }
    if (-not (Ask "Remove $name? ($($installed -join ', '))" $false)) { return }

    foreach ($id in $installed) {
        & winget uninstall --id $id --exact --source $source --silent @WingetCommon
        if ($LASTEXITCODE -eq 0) { Ok "$name ($id) removed." }
        else { Err "$name ($id) could not be removed (exit code $LASTEXITCODE)." }
    }
}

# Newly installed programs are only callable after refreshing PATH
function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Invoke-PostInstall($item) {
    switch ($item.Post) {
        "git" {
            Update-Path
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
            if (-not (git config --global user.name)) {
                if ($AutoYes) { Info 'Set your Git name with: git config --global user.name "Your Name"' }
                else {
                    $n = Read-Host ":: Git name"
                    if ($n) { git config --global user.name $n }
                }
            }
            if (-not (git config --global user.email)) {
                if ($AutoYes) { Info 'Set your Git email with: git config --global user.email "you@example.com"' }
                else {
                    $e = Read-Host ":: Git email"
                    if ($e) { git config --global user.email $e }
                }
            }
        }
        "gh" {
            Update-Path
            if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return }
            & gh auth status *> $null
            if ($LASTEXITCODE -eq 0) { Ok "Already logged in to GitHub." }
            else {
                Info "Logging in to GitHub (gh auth login)..."
                gh auth login
                if ($LASTEXITCODE -ne 0) { Err "GitHub login failed."; return }
            }
            gh auth setup-git
        }
    }
}

function Invoke-ForCategories([scriptblock]$action, [string[]]$cats) {
    foreach ($cat in $cats) {
        Write-Host ""
        Write-Host "===== $cat =====" -ForegroundColor Green
        foreach ($item in $Items | Where-Object { $_.Cat -eq $cat }) {
            & $action $item
        }
    }
}

function Select-Categories {
    Write-Host "Categories:"
    for ($i = 0; $i -lt $Categories.Count; $i++) {
        Write-Host "  $($i + 1) $($Categories[$i])"
    }
    while ($true) {
        $selected = @()
        $line = Read-Host "Selection (e.g. 1 3)"
        foreach ($n in ($line -split '[\s,]+' | Where-Object { $_ })) {
            $num = 0
            if ([int]::TryParse($n, [ref]$num) -and $num -ge 1 -and $num -le $Categories.Count) {
                $selected += $Categories[$num - 1]
            } else {
                Write-Host "Invalid: $n"
            }
        }
        if ($selected.Count -gt 0) { return $selected | Select-Object -Unique }
    }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Err "winget was not found. Please install 'App Installer' from the Microsoft Store:"
    Write-Host "    https://apps.microsoft.com/detail/9NBLGGH4NNS1"
    exit 1
}

Write-Host "What do you want to do?"
Write-Host "  1 Install everything"
Write-Host "  2 Install selected categories"
Write-Host "  3 Remove selected categories"
Write-Host "  4 Cancel"
$choice = Read-Host "Selection [1-4]"

switch ($choice) {
    "1" { Invoke-ForCategories ${function:Install-Item} $Categories }
    "2" { Invoke-ForCategories ${function:Install-Item} (Select-Categories) }
    "3" { Invoke-ForCategories ${function:Uninstall-Item} (Select-Categories) }
    default {
        Write-Host "Cancelled."
        exit 0
    }
}

Write-Host ""
Ok "Done."
