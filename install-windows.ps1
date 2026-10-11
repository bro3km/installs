# Installiert / entfernt die Programme aus der README unter Windows (per winget).
# Nutzung:  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 [-y]
#   -y   Keine Rueckfragen pro Paket (alles mit "ja" beantworten)

param(
    [Alias("yes")]
    [switch]$y
)

$ErrorActionPreference = "Continue"
$AutoYes = [bool]$y

# ---------------------------------------------------------------------------
# Ausgabe / Rueckfragen
# ---------------------------------------------------------------------------
function Info($msg)  { Write-Host ":: " -ForegroundColor Blue -NoNewline; Write-Host $msg }
function Ok($msg)    { Write-Host "==> " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Warn($msg)  { Write-Host "==> WARNUNG: " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Err($msg)   { Write-Host "==> FEHLER: " -ForegroundColor Red -NoNewline; Write-Host $msg }

# Ask "Frage" [$true = Standard ja] -> $true / $false
function Ask([string]$Question, [bool]$DefaultYes = $true) {
    if ($AutoYes) {
        Info "$Question [automatisch: j]"
        return $true
    }
    $hint = if ($DefaultYes) { "[J/n]" } else { "[j/N]" }
    while ($true) {
        Write-Host ":: " -ForegroundColor Blue -NoNewline
        $answer = (Read-Host "$Question $hint").Trim().ToLower()
        if ($answer -eq "") { return $DefaultYes }
        if (@("j", "ja", "y", "yes") -contains $answer) { return $true }
        if (@("n", "nein", "no") -contains $answer) { return $false }
    }
}

# ---------------------------------------------------------------------------
# Paketliste
#   Ids:   winget-IDs; Alternativen -> die erste verfuegbare wird installiert,
#          jede gilt als "bereits installiert"
#   Url:   Download-Seite, falls keine ID gefunden wird
#   Note:  Hinweis (z.B. Windows-Ersatz)
#   Unsupported: gibt es fuer Windows nicht
# ---------------------------------------------------------------------------
$Items = @(
    @{ Cat = "Main";   Name = "Zen-Browser";               Ids = @("Zen-Team.Zen-Browser") }
    @{ Cat = "Main";   Name = "Only Office";               Ids = @("ONLYOFFICE.DesktopEditors") }
    @{ Cat = "Main";   Name = "Spotify";                   Ids = @("Spotify.Spotify") }
    @{ Cat = "Main";   Name = "VSCodium";                  Ids = @("VSCodium.VSCodium", "Microsoft.VisualStudioCode") }
    @{ Cat = "Main";   Name = "VM (VirtualBox)";           Ids = @("Oracle.VirtualBox") }
    @{ Cat = "Main";   Name = "WhatsApp";                  Ids = @("9NKSQGP7F2NH"); Source = "msstore" }
    @{ Cat = "Main";   Name = "Input Remapper (PowerToys)"; Ids = @("Microsoft.PowerToys"); Note = "Input Remapper gibt es nur fuer Linux - PowerToys (Keyboard Manager) als Ersatz." }
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

# ---------------------------------------------------------------------------
# winget-Hilfsfunktionen
# ---------------------------------------------------------------------------
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
        Warn "$name gibt es nicht fuer Windows - uebersprungen."
        return
    }
    $source = Get-Source $item

    foreach ($id in $item.Ids) {
        if (Test-Installed $id $source) {
            Ok "$name ist bereits installiert ($id)."
            return
        }
    }

    $chosen = $item.Ids | Where-Object { Test-Available $_ $source } | Select-Object -First 1
    if (-not $chosen) {
        Err "$name wurde in winget nicht gefunden."
        if ($item.Url) {
            Info "Manueller Download: $($item.Url)"
            if (-not $AutoYes -and (Ask "Download-Seite oeffnen?" $false)) { Start-Process $item.Url }
        }
        return
    }

    if ($item.Note) { Info $item.Note }
    if (-not (Ask "$name installieren? ($chosen)")) { return }

    & winget install --id $chosen --exact --source $source --silent `
        --accept-package-agreements @WingetCommon
    if ($LASTEXITCODE -eq 0) {
        Ok "$name installiert."
        Invoke-PostInstall $item
    } else {
        Err "$name konnte nicht installiert werden (Exit-Code $LASTEXITCODE)."
    }
}

function Uninstall-Item($item) {
    $name = $item.Name
    if ($item.Unsupported) { return }
    $source = Get-Source $item

    $installed = @($item.Ids | Where-Object { Test-Installed $_ $source })
    if ($installed.Count -eq 0) {
        Info "$name ist nicht installiert."
        return
    }
    if (-not (Ask "$name loeschen? ($($installed -join ', '))" $false)) { return }

    foreach ($id in $installed) {
        & winget uninstall --id $id --exact --source $source --silent @WingetCommon
        if ($LASTEXITCODE -eq 0) { Ok "$name ($id) geloescht." }
        else { Err "$name ($id) konnte nicht geloescht werden (Exit-Code $LASTEXITCODE)." }
    }
}

# Neu installierte Programme sind erst nach PATH-Aktualisierung aufrufbar
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
                if ($AutoYes) { Info 'Git-Name setzen mit: git config --global user.name "Dein Name"' }
                else {
                    $n = Read-Host ":: Git Name"
                    if ($n) { git config --global user.name $n }
                }
            }
            if (-not (git config --global user.email)) {
                if ($AutoYes) { Info 'Git-E-Mail setzen mit: git config --global user.email "du@example.com"' }
                else {
                    $e = Read-Host ":: Git E-Mail"
                    if ($e) { git config --global user.email $e }
                }
            }
        }
        "gh" {
            Update-Path
            if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return }
            & gh auth status *> $null
            if ($LASTEXITCODE -ne 0) {
                if ($AutoYes) { Info "GitHub-Login spaeter mit: gh auth login" }
                elseif (Ask "Jetzt bei GitHub anmelden (gh auth login)?") { gh auth login }
            }
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
    Write-Host "Kategorien:"
    for ($i = 0; $i -lt $Categories.Count; $i++) {
        Write-Host "  $($i + 1) $($Categories[$i])"
    }
    while ($true) {
        $selected = @()
        $line = Read-Host "Auswahl (z.B. 1 3)"
        foreach ($n in ($line -split '[\s,]+' | Where-Object { $_ })) {
            $num = 0
            if ([int]::TryParse($n, [ref]$num) -and $num -ge 1 -and $num -le $Categories.Count) {
                $selected += $Categories[$num - 1]
            } else {
                Write-Host "Ungueltig: $n"
            }
        }
        if ($selected.Count -gt 0) { return $selected | Select-Object -Unique }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Err "winget wurde nicht gefunden. Bitte 'App Installer' aus dem Microsoft Store installieren:"
    Write-Host "    https://apps.microsoft.com/detail/9NBLGGH4NNS1"
    exit 1
}

Write-Host "Was moechtest du tun?"
Write-Host "  1 Alles installieren"
Write-Host "  2 Gewuenschte Kategorien installieren"
Write-Host "  3 Gewuenschte Kategorien loeschen"
Write-Host "  4 Abbrechen"
$choice = Read-Host "Auswahl [1-4]"

switch ($choice) {
    "1" { Invoke-ForCategories ${function:Install-Item} $Categories }
    "2" { Invoke-ForCategories ${function:Install-Item} (Select-Categories) }
    "3" { Invoke-ForCategories ${function:Uninstall-Item} (Select-Categories) }
    default {
        Write-Host "Abgebrochen."
        exit 0
    }
}

Write-Host ""
Ok "Fertig."
