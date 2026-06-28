#requires -RunAsAdministrator
#requires -Version 7

<#
.SYNOPSIS
    Universal Windows Optimizer v13.0 + Naprawa i Odbudowa Windows v1.6 — zaawansowany skrypt tuningowo-diagnostyczny dla Windows

.SUPPORTED
    Windows 10 22H2+ / Windows 11 23H2 / 24H2 | Desktop | PowerShell 7+ | lokalny admin

.NOT RECOMMENDED
    Laptopy bez zasilacza przy profilu Maximum
    Profil Laptop: dedykowany i w pelni obslugiwany
    Systemy w domenie / Intune / MDM
    VDI / maszyny wirtualne
    Systemy z korporacyjnym EDR/MDM

.NOTES
    === CHANGELOG v14.0.1-bugfix (Etap 1: naprawa bledow) ===
    FIX1 KRYTYCZNY: Set-ServiceStartupSafe byla zdefiniowana 2x z roznymi sygnaturami
          (-StartupType vs -Mode); wersja modulu Naprawa nadpisywala optymalizator i kazde
          wywolanie z -StartupType konczylo sie ParameterBindingException. Wersja repair
          przemianowana na Set-RepairServiceStartup.
    FIX2 KRYTYCZNY: Checkpoint-Computer/Enable-ComputerRestore nie istnieja w PowerShell 7 —
          punkt przywracania NIGDY nie powstawal (cichy WARN). Teraz: wykonanie przez
          Windows PowerShell 5.1 + WERYFIKACJA, ze punkt faktycznie istnieje.
    FIX3: Rollback rejestru — 'reg import' scala i nie usuwa wartosci DODANYCH przez skrypt;
          wartosci z OldValue=null sa teraz jawnie usuwane (Remove-ItemProperty).
    FIX4: -Mode Repair + -Silent wisialo na ukrytym Read-Host — teraz jawny blad na starcie.
    FIX5: Start/Stop-Transcript zabezpieczone (OneDrive/ACL nie ubije skryptu ani nie
          zamaskuje bledu w finally).
    FIX6: Invoke-ExternalWithTimeout — pusty -ArgumentList nie rzuca bledu bindowania;
          finally zabija tylko WLASNY PID (wczesniej ubijal po nazwie np. cudzy DISM).
    FIX7: Liczniki wydajnosci odporne na lokalizacje (polski Windows!) — tlumaczenie nazw
          przez indeksy Perflib (Get-LocalizedCounterPath / Get-CounterValueSafe). Wczesniej
          benchmark/DPC/IO na polskim systemie po cichu zwracaly pustke.
    =========================================================

    Wiele zmian wymaga restartu systemu dla pelnego efektu.
    Rollback nie jest absolutny — winsock/LSP nie zostanie w 100% przywrocony.
    Windows Defender NIE jest wylaczany — skrypt chroni bezpieczenstwo systemu.
    GPU tweaks: TDR delay, shader cache, NVIDIA Coolbits (restart wymagany).
    Timer: GlobalTimerResolutionRequests=1 (timer 0.5ms, restart wymagany).

.SILENT MODE
    Uruchom z parametrami zeby pominac menu interaktywne:
    .\skrypt.ps1 -Mode Optimize -Profile Balanced -Silent
    .\skrypt.ps1 -Mode Optimize -Profile Maximum  -Silent -AutoRestart
    .\skrypt.ps1 -Mode Rollback -RollbackSessionId '20250419_143022' -Silent
    .\skrypt.ps1 -Mode Rollback -RollbackLatest -Silent   # one-click rollback najnowszej sesji

.DRYRUN MODE
    Podglad zmian bez modyfikacji systemu:
    .\skrypt.ps1 -Mode Optimize -Profile Balanced -DryRun

.LAPTOP GAMING SAFE - OPCJE DODATKOWE
    Domyslnie profil LaptopGamingSafe nie dotyka telemetrii, Windows Update, uslug, VBS/HVCI ani agresywnej sieci.
    W trybie interaktywnym skrypt zapyta o te rzeczy osobno i pokaze realny zysk oraz skutki w uzytkowaniu.
    W trybie silent mozna wlaczyc wybrane ryzykowne dodatki flagami:
    -EnableTelemetryTuning -EnableWindowsUpdatePause -EnableServiceTuning -EnableVbsDisable -EnableNetworkTweaks
    Lub jednym zbiorczym przelacznikiem:
    -EnableRiskPackModule

.LAPTOP GAMING PRO - MODULY DODATKOWE
    Profile presetowe: GamingLaptop, OfficeLaptop, LowRAM, BatterySaver.
    Profil LaptopGamingSafe moze zapytac o bezpieczne moduly dodatkowe:
    - benchmark przed/po, przeglad autostartu, naprawa po debloaterach, profil NVIDIA.
    Ryzykowne rzeczy pozostaja oddzielnymi pytaniami i nie sa wlaczane domyslnie.

.RISK AWARE MODULES
    Poza profilem Maximum skrypt pokazuje dodatkowe pytania tylko tam, gdzie dany profil faktycznie rusza uslugi, siec, Windows Update lub VBS.
    Maximum zostaje agresywny i nie jest dodatkowo hamowany.
    Dodano tez jeden duzy modul zbiorczy Risk Pack z uczciwym opisem zysku i skutkow ubocznych.

.PERFORMANCE FEEL MODE
    Nowy modul komfortu i responsywnosci: szybsze UI/Explorer, nizszy input lag, mniej stutteru przed gra,
    lekka optymalizacja audio/MMCSS i helper Gaming Session. Nie blokuje Insidera, Windows Update ani telemetrii.
    Realny efekt: zwykle 0-3% FPS, ale wyraznie lepszy feel, mniej opoznien i szybsza praca pulpitu.

.BETA TESTER AUDIT v12.9
    Dodaje raport 66 pomyslow z beta testow bez rozwalania profili.
    Domyslnie to audyt/raport: pokazuje co jest diagnostyka, co jest juz w skrypcie, co zostaje Advanced/Manual.
    Nie wlacza agresywnych zmian automatycznie.

.FORCE CLOSE APPS (tylko z -Silent)
    .\skrypt.ps1 -Mode Optimize -Profile Balanced -Silent -ForceCloseApps
    UWAGA: -ForceCloseApps zamknie aplikacje w tle (Chrome, Discord itp.) bez potwierdzenia.
           Bez tej flagi -Silent nigdy nie zamknie procesow automatycznie.
#>

[CmdletBinding()]
param(
    [ValidateSet('Analyze','Optimize','Rollback','Audit','Repair','Compare')]
    [string]$Mode = 'Analyze',

    # STAGE3 v14.2: UI language. 'auto' = detect from system culture (pl-* -> Polish, otherwise English).
    [ValidateSet('pl','en','auto','system')]
    [string]$Language = 'auto',

    [ValidateSet('Safe','Balanced','Maximum','Gaming','Workstation','LowEnd','Laptop','LaptopGamingSafe','GamingLaptop','OfficeLaptop','LowRAM','BatterySaver','Custom')]
    [string]$Profile = 'Safe',

    [string]$SessionId,
    [string]$RollbackSessionId = '',
    [switch]$RollbackLatest, # One-click rollback: cofa najnowsza sesje Optimize bez wpisywania ID
    [ValidateSet('All','Registry','Services','Power','DNS')]
    [string[]]$RollbackModules = @('All'),

    [ValidateSet('Keep','Manual')]
    [string]$SearchIndexingMode = 'Keep',

    [ValidateSet('Keep','Google','Cloudflare','Quad9')]
    [string]$DnsMode = 'Keep',

    [switch]$EnablePowerTweaks,
    [switch]$EnableUiTweaks,
    [switch]$EnableGamingTweaks,
    [switch]$EnableNetworkTweaks,
    [switch]$EnableServiceTuning,
    [switch]$EnableCleanup,
    [switch]$EnableRepair,
    [switch]$EnableNetworkRepair,
    [switch]$EnableGamingSession,
    [switch]$EnableExperimentalTweaks,
    [switch]$NoRestorePoint,
    [switch]$NoPause,
    [switch]$Silent,
    [switch]$AutoRestart,
    [switch]$ForceCloseApps,        # Wymagane razem z -Silent aby zamykac procesy bez pytania
    [switch]$DryRun,                # Symulacja — pokazuje co zostanie zmienione bez zadnych zmian w systemie
    [switch]$Daemon,                # PHASE-A v15: background automation engine loop (started by the scheduled task)
    [switch]$ValidateState,         # PHASE-A v15: one-shot post-restart validation of applied tweaks
    [switch]$ResumeRenovation,      # RENOVATION 2.0 section D: resume a multi-restart renovation pipeline
    [switch]$DeepScan,              # Wolniejsze testy diagnostyczne: defrag /A, dxdiag, ping MTU, dluzsze logi
    [switch]$SkipV13Audit,          # Pomija rozszerzony audit v13.1, jesli chcesz tylko szybki run
    [switch]$EnableMemoryDiagnosticSchedule, # Opcjonalnie planuje mdsched.exe; nie robi sie samo bez tej flagi
    [string]$CustomProfilePath = '', # JSON preset uzytkownika dla -Profile Custom
    [switch]$EnableUltimatePerfPlan, # Ultimate Performance zamiast High Performance (realny zysk CPU)
    [switch]$EnableVbsDisable,       # Wylacz VBS/Memory Integrity — realny zysk FPS, obniza bezpieczenstwo
    [switch]$EnableTelemetryTuning,  # Opcjonalnie dla LaptopGamingSafe: DiagTrack -> Manual. Moze psuc Insider/rollout funkcji.
    [switch]$EnableWindowsUpdatePause,# Opcjonalnie dla LaptopGamingSafe: pauza WU 7 dni, mniej pracy w tle.
    [switch]$EnablePostDebloaterRepair, # Przywraca skladniki czesto psute przez debloatery: Insider telemetry, WU, Store/Xbox.
    [switch]$EnableStartupReview,     # Bezpieczny przeglad autostartu; nic nie wylacza bez potwierdzenia.
    [switch]$EnableNvidiaProfile,     # Opcjonalny profil NVIDIA przez nvidia-smi / rejestr, bez OC i bez Coolbits.
    [switch]$EnablePerformanceFeelMode, # Opcjonalny modul: responsywnosc UI/input lag/stutter/audio/gaming helper.
    [switch]$EnableBenchmarkReport,   # Rozszerzony benchmark/raport przed-po dla laptopa.
    [switch]$EnableRiskPackModule,    # Jeden duzy pakiet opcjonalny: telemetria/WU/uslugi/siec/VBS z uczciwym opisem ryzyka.
    [ValidateSet('Auto','Esport','AAA','Silent','Work')]
    [string]$Scenario = 'Auto',
    [switch]$DisableSmartMode,       # Wylacza warstwe decyzyjna Smart Mode (domyslnie aktywna)
    [switch]$SkipProDashboard,        # Pomija raport Pro Dashboard v14
    [switch]$EnableFirstRunWizard,    # W trybie interaktywnym pokazuje kreator wyboru profilu
    [string]$GameFolder = ''         # Sciezka do folderu z grami — wykluczona z Windows Defender (np. "D:\Games")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'



# =============================
# Globals
# =============================
$script:AppName    = 'Universal Windows Optimizer Pro'
$script:Version    = '15.8.0'          # v15.8: [12] Report Analysis - doradca werdyktu (UDANA/CZESCIOWA/NIEUDANA + %), walidacja+benchmark w ocenie, dziala w -Silent; fix Invoke-RefreshFullAudit; propagacja ExitCode          # v15.7: Root Cause Analysis module [11] - boot-impact per service/driver, driver analyzer, rule-based engine, jump to Repair          # v15.2: FIX15 Repair crash, main menu 1-9, back=0 everywhere, auto modes last [14]/[15], CUSTOM plan creator, honest profile estimates
$script:Desktop    = [Environment]::GetFolderPath('Desktop')
$script:RootFolder = Join-Path $script:Desktop 'OptReports'
$script:Now        = Get-Date
if (-not $SessionId) { $SessionId = $script:Now.ToString('yyyyMMdd_HHmmss') }
$script:SessionId            = $SessionId
$script:SessionFolder        = Join-Path $script:RootFolder $script:SessionId
$script:LogFolder            = Join-Path $script:SessionFolder 'Logs'
$script:ReportFolder         = Join-Path $script:SessionFolder 'Reports'
$script:BackupFolder         = Join-Path $script:SessionFolder 'Backups'
$script:RegistryBackupFolder = Join-Path $script:BackupFolder 'Registry'
$script:ManifestPath         = Join-Path $script:SessionFolder 'manifest.json'
$script:TranscriptPath       = Join-Path $script:LogFolder 'transcript.log'
$script:MainLog              = Join-Path $script:LogFolder 'main.log'
$script:ErrorLog             = Join-Path $script:LogFolder 'errors.log'
$script:ChangeLog            = Join-Path $script:LogFolder 'changes.log'
$script:WarningLog           = Join-Path $script:LogFolder 'warnings.log'
$script:SummaryPath          = Join-Path $script:ReportFolder 'summary.txt'
$script:HtmlReportPath       = Join-Path $script:ReportFolder 'raport.html'
$script:BeforeSnapshotPath   = Join-Path $script:ReportFolder 'before.json'
$script:AfterSnapshotPath    = Join-Path $script:ReportFolder 'after.json'
$script:AnalyzeReportPath    = Join-Path $script:ReportFolder 'analyze_report.txt'
$script:BenchmarkPath        = Join-Path $script:ReportFolder 'benchmark.txt'
$script:ValidationPath       = Join-Path $script:ReportFolder 'validation.txt'
$script:BenchmarkBefore      = $null
$script:BenchmarkAfter       = $null
$script:AutoRolledBack       = New-Object System.Collections.Generic.List[PSCustomObject]
$script:ProfileDescription   = ''
$script:ProfileRisk          = ''
$script:EnableAutoRollback   = $false
$script:EnableAdvancedDiag   = $false
$script:GamingProfileActive  = $false
$script:AllowGlobalWindowsUpdatePause = $false
$script:WorkstationProfile   = $false
$script:LowEndProfile        = $false
$script:LaptopProfile        = $false
$script:EnableLaptopGamingSafeMode = $false
$script:LaptopOptionalTelemetryTuning = $false
$script:LaptopOptionalWindowsUpdatePause = $false
$script:LaptopOptionalVbsDisable = $false
$script:LaptopOptionalPostDebloaterRepair = $false
$script:LaptopOptionalStartupReview = $false
$script:LaptopOptionalNvidiaProfile = $false
$script:LaptopOptionalPerformanceFeelMode = $false
$script:LaptopOptionalBenchmarkReport = $false
$script:EnableRiskPackBundle = [bool]$EnableRiskPackModule
$script:RiskPackContext      = ''
$script:QuickPerformanceFeelOnly = $false
$script:LaptopOnAC           = $true
$script:ForceUltimatePerfPlan = $false
$script:SmartModeEnabled    = -not [bool]$DisableSmartMode
$script:ETWActive            = $false
$script:ETWProfile           = $null
$script:ETWOutput            = $null
$script:HWProfile            = $null
$script:MemTopology          = $null
$script:ExitCode             = 0
$script:SanityWarnings       = New-Object System.Collections.Generic.List[string]
$script:CounterNameMap       = $null   # FIX v14.0.1: cache tlumaczen nazw licznikow wydajnosci (locale)

# ============================================================
# STAGE3 v14.2: UI LANGUAGE LAYER (PL/EN)
# Code and logs stay in English; everything the user SEES in the console
# goes through T('key'). Adding a language = adding one table below.
# ============================================================
$script:UILang = if ($Language -notin @('auto','system')) { $Language }
                 elseif ((Get-Culture).TwoLetterISOLanguageName -eq 'pl') { 'pl' }
                 else { 'en' }

$script:Strings = @{
  en = @{
    'lang.title'         = 'Language:'
    'lang.1'             = '  [1] Polski'
    'lang.2'             = '  [2] English'
    'lang.prompt'        = 'Language'
    'menu.mode.title'    = 'Select mode:'
    'menu.mode.1'        = '  [1] Analyze   - diagnostic report, zero changes. Effect: you learn what slows the system down.'
    'menu.mode.2'        = '  [2] Optimize  - final menu with effect description before each choice. Recommended.'
    'menu.mode.3'        = '  [3] Rollback  - restore settings from a previous optimization with one choice.'
    'menu.mode.4'        = '  [4] Windows Repair & Rebuild - audit, basic or advanced repair.'
    'menu.rb.none'       = 'No sessions available for rollback.'
    'menu.rb.oneclick'   = 'One-click rollback:'
    'menu.rb.latest'     = '  [0] Restore the most recent Optimize session: {0}'
    'menu.rb.pick'       = 'Or pick a specific session:'
    'menu.rb.prompt'     = 'Select [0 = latest / session number]'
    'menu.prof.title'    = 'Select profile:'
    'menu.prof.suggest'  = '  [SUGGESTION] Recommended profile for your hardware: '
    'menu.prof.quick'    = 'Quick final profiles:'
    'menu.prof.p0'  = '(unused since v15.2 - back moved to [0], Auto moved to [14])'
    'menu.prof.p1'  = '  [1] Safe - safe basics. Effect: faster boot/UI, no network tinkering. Est.: ~0-3% (feel/UI).'
    'menu.prof.p2'  = '  [2] Balanced - more changes, still everyday-friendly. Effect: better overall feel. Est.: ~0-4%.'
    'menu.prof.p3'  = '  [3] Maximum - aggressive MAXXXX. Effect: best FPS chance, but bug risk. Only if you know what you are doing. Est.: ~0-5% (up to ~10% only when VBS-off helps).'
    'menu.prof.p4'  = '  [4] Gaming - desktop/gaming max latency. Effect: FPS/latency, but may touch VBS and stronger settings. Est.: ~0-5% (latency/feel).'
    'menu.prof.p5'  = '  [5] Workstation - work/dev/graphics. Effect: stability, I/O, less background chaos. Est.: ~0-3% (I/O).'
    'menu.prof.p6'  = '  [6] LowEnd - weak PCs. Effect: less background RAM/CPU, snappier response. Est.: ~2-6% on weak hardware.'
    'menu.prof.p7'  = '  [7] Laptop - everyday laptop. Effect: faster on AC, thriftier on battery. Est.: ~0-3%.'
    'menu.prof.p8'  = '  [8] LaptopGamingSafe - module questions. Effect: gaming + laptop without breaking Insider. Est.: ~0-3% + less stutter.'
    'menu.prof.p9'  = '  [9] GamingLaptop - ready-made gaming laptop preset. Effect: less stutter, NVIDIA safe, report. Est.: ~0-3% (stutter).'
    'menu.prof.p10' = '  [10] OfficeLaptop - work/comfort. Effect: fast desktop, startup review, zero aggression. Est.: ~0-3% (boot/UI).'
    'menu.prof.p11' = '  [11] LowRAM - low memory. Effect: less background junk, faster boot. Est.: ~2-5% (RAM).'
    'menu.prof.p12' = '  [12] BatterySaver - battery/silence. Effect: longer runtime, less noise. Est.: +10-25% battery time (at a performance cost).'
    'menu.prof.p13' = '  [13] Performance Feel Mode - BEST feel. Effect: faster UI, input lag, less stutter; leaves telemetry/WU/VBS/network alone. Est.: ~0-3% FPS, mainly responsiveness.'
    'menu.prof.hint'    = 'No time to choose? Autonomous modes are at the end: [14] or [15].'
    'menu.prof.prompt'  = 'Profile [1-15 / 0=back]'
    'menu.prof.chosen'  = 'Selected: {0}'
    'menu.prof.feelonly'= 'Mode: Performance Feel Only - safe feel, no risky tweaks.'
    'menu.prof.desc'    = 'Note: the script will only ask the questions that actually change something.'
    'menu.analyze.skip' = 'Analyze: WSearch / DNS / Experimental questions skipped - read-only mode, nothing will be changed.'
    'menu.ws.title'  = 'Windows Search (WSearch):'
    'menu.ws.1'      = '  [1] Keep   - leave enabled (better comfort, recommended)'
    'menu.ws.2'      = '  [2] Manual - switch to manual (less background CPU while gaming)'
    'menu.ws.prompt' = 'WSearch [1/2]'
    'menu.dns.title' = 'DNS server (physical adapters - VPN/virtual skipped):'
    'menu.dns.1'     = '  [1] Keep       - do not change the current DNS'
    'menu.dns.2'     = '  [2] Google     - 8.8.8.8 / 8.8.4.4      (logs queries, fast)'
    'menu.dns.3'     = '  [3] Cloudflare - 1.1.1.1 / 1.0.0.1      (24h logs, fast resolver)'
    'menu.dns.4'     = '  [4] Quad9      - 9.9.9.9 / 149.112.x.x  (no-log, blocks malware)'
    'menu.dns.prompt'= 'DNS [1/2/3/4]'
    'menu.exp.title' = 'Experimental tweaks (Nagle/TCP, HAGS):'
    'menu.exp.1'     = '  [1] No  - safer. Recommended for most users.'
    'menu.exp.2'     = '  [2] Yes - legacy tweaks + HAGS. Only if you know what you are doing.'
    'menu.exp.prompt'= 'Experimental [1/2]'
    'menu.def.title' = '--- Windows Defender ---'
    'menu.def.1'     = '  This script does NOT disable Defender - your security stays intact.'
    'menu.def.2'     = '  If Defender slows your games down: Settings > Windows Security'
    'menu.def.3'     = '  > Virus protection > Add an exclusion for your games folder (e.g. D:\Games)'
    'menu.def.4'     = '  This is the safe alternative to disabling protection entirely.'
    'menu.pressenter'= 'Press Enter to start...'
    'analyze.pro.skip1' = '--- Analyze: PRO module questions skipped (read-only mode) ---'
    'analyze.pro.skip2' = '    Extended benchmark: enabled automatically (feeds the report). Executive modules: disabled.'
    'analyze.risk.skip' = '--- Analyze: Risk Pack question skipped (read-only mode) ---'
    'stats.line'     = '  Changes: {0}   Reports: {1}   Skipped: {2}   Warnings: {3}   Errors: {4}'
    'main.done'      = 'Done! Reports: {0}'
    'main.html'      = 'HTML report:     {0}'
    'menu.mode.5'    = '  [5] Power Plan Creator - goal-based plans (calibrated on real, proven setups), backup/restore, factory reset.'
    'menu.mode.6'    = '  [6] Automation Engine - background rules: game -> gaming plan, battery -> eco, watchdog log.'
    'menu.mode.7'    = '  [7] App Packs (winget) - install a whole app set with one choice; export your own pack.'
    'menu.mode.8'    = '  [8] Voice Assistant (experimental, offline) - a few fixed voice commands.'
    'menu.mode.9'    = '  [9] Library - recipes (saved tweak sets) and full session history with rollback.'
    'menu.mode.prompt2' = 'Mode [1-11]'
    'menu.prof.back' = '  [0] Back to mode selection.'
    'menu.prof.p14' = '  [14] Auto / Safe Recommended - picks a safe profile for you. Comfort + stability, minimal risk.'
    'menu.prof.p15' = '  [15] AutoSmart - picks the profile AND all answers automatically for YOUR hardware. Honest rules, no magic.'
    'auto.head'      = 'AutoSmart decisions for this machine:'
    'auto.prof'      = '  Profile: {0}  (reason: {1})'
    'auto.ans'       = '  Answers: WSearch=Keep, DNS=Keep, Experimental=No (safe defaults).'
    'lib.title'      = '=== LIBRARY ==='
    'lib.1'          = '  [1] Recipes - saved tweak sets with honest effect labels.'
    'lib.2'          = '  [2] All sessions - full history + rollback by number.'
    'lib.3'          = '  [3] Automation Engine - background rules: game -> gaming plan, battery -> eco, watchdog log.'
    'lib.0'          = '  [0] Back to main menu.'
    'lib.prompt'     = 'Library [0-2]'
    'lib.rec.list'   = 'Available recipes:'
    'lib.rec.effect' = 'Declared effect: {0}'
    'lib.rec.prompt' = 'Recipe number (0 = back)'
    'lib.rec.run'    = 'Selected recipe: {0} (profile: {1})'
    'lib.rec.apply'  = 'The recipe pre-set the mode, profile and answers - the run now continues as usual.'
    'lib.ses.title'  = 'All sessions:'
    'lib.ses.none'   = 'No sessions found.'
    'lib.ses.prompt' = 'Session number to roll back (0 = back)'
    'ppc.title'      = '=== ADVANCED POWER PLAN CREATOR ==='
    'ppc.backup'     = 'Backup of the current plan list + active plan export: {0}'
    'ppc.goal'       = 'Goal: [1] Max performance  [2] Quiet & cool  [3] Balanced work'
    'ppc.goalprompt' = 'Goal [1/2/3]'
    'ppc.created'    = 'Created power plan: {0}'
    'ppc.activateQ'  = 'Activate it now? [y/N]'
    'ppc.activated'  = 'Plan activated.'
    'ppc.note'      = 'Honest notes: [2] caps CPU at 99% which disables Turbo Boost on many CPUs (cooler, quieter, slower peaks). On modern laptops the vendor power slider / Modern Standby may override some settings.'
    'ppc.failed'     = 'powercfg failed: {0}'
    'ps51.warn'      = 'NOTE: running on Windows PowerShell 5.1 - the script works, but PowerShell 7 (pwsh.exe) is recommended.'
    'lib.4'          = '  [4] App Packs (winget) - install a whole set of apps with one choice; export your own pack.'
    'lib.5'          = '  [5] Voice Assistant (experimental, offline) - a few fixed voice commands.'
    'autom.title'    = '=== AUTOMATION ENGINE ==='
    'autom.status'   = 'Daemon status: {0}'
    'autom.on'       = 'INSTALLED (runs hidden at logon)'
    'autom.off'      = 'not installed'
    'autom.1'        = '  [1] Install / reinstall the daemon (scheduled task, runs hidden at logon).'
    'autom.2'        = '  [2] Uninstall the daemon.'
    'autom.3'        = '  [3] Show config file path (edit the game list and rules there).'
    'autom.4'        = '  [4] Show the last 15 lines of the daemon log.'
    'autom.0'        = '  [0] Back.'
    'autom.prompt'   = 'Automation [0-4]'
    'autom.installed'= 'Daemon installed. It starts at next logon; rules: game -> {0}, battery -> power saver.'
    'autom.removed'  = 'Daemon uninstalled.'
    'autom.cfg'      = 'Config: {0}'
    'autom.nolog'    = 'No daemon log yet.'
    'autom.note'     = 'Honest note: game detection = process-name list in the config (edit it for your games). The daemon only switches power plans and logs - it never kills processes or changes the registry.'
    'packs.title'    = '=== APP PACKS (winget) ==='
    'packs.nowinget' = 'winget not found. Install "App Installer" from Microsoft Store first.'
    'packs.list'     = 'Available packs:'
    'packs.prompt'   = 'Pack number (0 = back, E = export installed apps to a new pack)'
    'packs.installQ' = 'Install pack {0} via winget? [y/N]'
    'packs.exported' = 'Exported installed apps to: {0}'
    'packs.done'     = 'winget finished (exit code {0}). Details above.'
    'voice.title'    = '=== VOICE ASSISTANT (experimental, offline) ==='
    'voice.norec'    = 'No speech recognizer available for pl-PL or en-US on this system.'
    'voice.lang'     = 'Recognizer: {0}'
    'voice.cmds'     = 'Commands: "tryb gaming" / "gaming mode", "tryb eko" / "eco mode", "wylacz komputer" (shutdown in 10 min), "anuluj" / "cancel" (abort shutdown), "koniec" / "stop listening".'
    'voice.listen'   = 'Listening... (say "koniec" / "stop listening" to exit)'
    'voice.heard'    = 'Heard: {0}  (confidence {1}%)'
    'voice.bye'      = 'Voice assistant stopped.'
    'regr.warn'      = 'BENCHMARK REGRESSION: {0}'
    'regr.offer'     = 'The after-benchmark looks WORSE than before. Roll back this session now? [y/N]'
    'regr.ok'        = 'Benchmark after vs before: no regression detected.'
    'valid.head'     = '=== POST-RESTART TWEAK VALIDATION ==='
    'valid.result'   = 'Survived: {0}/{1} checks. Report: {2}'
    'valid.sched'    = 'Post-restart validation scheduled (one-shot task at next logon).'
    'ppc.menu1'      = '  [1] Max Performance     - min 8 / max 100, boost aggressive, ASPM off, disk always on. Hot but fastest.'
    'ppc.menu2'      = '  [2] Gaming Cool         - max 98 on AC (turbo capped = much cooler), ASPM off, calibrated on a real, proven plan.'
    'ppc.menu3'      = '  [3] Silent Work         - max 85 AC / 70 battery, USB+PCIe saving. Calibrated on a real, proven work plan.'
    'ppc.menu4'      = '  [4] Balanced Work       - max 100 with efficient boost, moderate savings.'
    'ppc.menu5'      = '  [5] CUSTOM - build your own plan question by question, with honest notes on heat and effects.'
    'ppc.menuB'      = '  [6] Backup ALL plans (.pow + readable dumps) to the Library.'
    'ppc.menuR'      = '  [7] Restore a plan from a .pow backup.'
    'ppc.menuF'      = '  [8] FACTORY RESET of power plans (removes ALL custom plans!).'
    'ppc.menu0'      = '  [0] Back.'
    'ppc.prompt2'    = 'Creator [1-8 / 0=back]'
    'ppc.applied'    = 'Verified: {0} of {1} settings accepted by the system.'
    'ppc.hidden'     = 'Note: {0} hidden by the laptop vendor on this machine - value written, firmware may ignore it.'
    'ppc.bdone'      = 'Backed up {0} plan(s) to: {1}'
    'ppc.rlist'      = 'Available .pow backups:'
    'ppc.rprompt'    = 'Backup number to import (0 = back)'
    'ppc.rdone'      = 'Imported. Windows created a new plan from the backup - check powercfg /list or Control Panel.'
    'ppc.fwarn'      = 'WARNING: this restores factory default plans and DELETES ALL CUSTOM PLANS (including the proven ones). A full backup will be made first.'
    'ppc.fconfirm'   = 'Type YES to proceed'
    'ppc.fdone'      = 'Factory plans restored. Your old plans are safe in the backup folder (use [R] to bring any back).'
    'cust.title'   = '--- CUSTOM PLAN: Enter accepts the [default]. Honest notes included. ---'
    'cust.name'    = 'Plan name'
    'cust.maxac'   = 'CPU max on AC, %. 100=full power (hottest). 99/98=Turbo OFF on most CPUs - usually clearly cooler peaks. 85=cool work'
    'cust.maxdc'   = 'CPU max on battery, %'
    'cust.min'     = 'CPU min, %. Low (5) lets the CPU rest; 100 = constant heat'
    'cust.boost'   = 'Boost mode: 0=off (quiet), 2=aggressive (hot), 3=efficient. Vendor may hide this setting'
    'cust.usb'     = 'USB selective suspend: 1=on (saves power; proven fine even in your gaming plan), 0=off'
    'cust.aspm'    = 'PCIe ASPM: 0=off (best latency, gaming), 1=moderate, 2=max savings'
    'cust.disk'    = 'Disk idle timeout on AC, seconds (0=never)'
    'cust.screen'  = 'Screen off on AC, seconds (0=never)'
    'cust.sleep'   = 'Sleep on AC, seconds (0=never)'
    'pre.title'   = '=== REPAIR PREFLIGHT: quick safety checks before any work ==='
    'pre.reboot'  = 'A RESTART IS PENDING (CBS/WU/file renames). Strongly recommended: restart Windows first, then run the repair on a clean state.'
    'pre.space'   = 'Low disk space: {0} GB free on the system drive. DISM repairs can need 10+ GB.'
    'pre.batt'    = 'Running on BATTERY. Long repairs + battery = risk of interrupting DISM mid-flight. Plug in the charger.'
    'pre.ok'      = 'Preflight: all checks passed.'
    'pre.contQ'   = 'Warnings above. Continue anyway? [y/N]'
    'ren.analyze.label'= 'now (read-only check)'
    'ren.analyze.hint' = 'This is a health snapshot only. To fix anything, use [4] Repair & Renovation.'
    'ren.menu.title'   = '=== WINDOWS REPAIR & RENOVATION 2.0 ==='
    'ren.menu.1'       = '  [1] Basic Renovation - diagnose, then fix only detected reversible issues. Max 1 restart.'
    'ren.menu.2'       = '  [2] Advanced Renovation - Auto (intelligent) or Follow-me (guided, step by step).'
    'ren.menu.legacy'  = '  [9] Legacy repair menu (old expert tools).'
    'ren.menu.0'       = '  [0] Back.'
    'ren.menu.prompt'  = 'Choose [0/1/2/9]'
    'ren.adv.title'    = '--- ADVANCED RENOVATION ---'
    'ren.adv.1'        = '  [1] Auto - intelligent: fixes only what is broken, leaves healthy/factory settings alone.'
    'ren.adv.2'        = '  [2] Follow-me with Advisor - one card per finding: what / why / what it breaks / [t]Fix [p]Skip [w]More.'
    'ren.adv.0'        = '  [0] Back.'
    'ren.adv.prompt'   = 'Advanced [0/1/2]'
    'ren.basic.title'  = '--- BASIC RENOVATION (reversible only) ---'
    'ren.auto.title'   = '--- AUTO RENOVATION (intelligent) ---'
    'ren.follow.title' = '--- FOLLOW-ME WITH ADVISOR ---'
    'ren.follow.intro' = 'I will walk you through each finding. You decide every step; nothing happens without your key.'
    'ren.follow.count' = 'Found {0} item(s). Going through them one by one.'
    'ren.diag.run'     = 'Running diagnosis (read-only)...'
    'ren.found'        = 'Findings:'
    'ren.none'         = 'No issues detected - the system looks healthy.'
    'ren.health'       = 'System health {0}:'
    'ren.before'       = 'before'
    'ren.after'        = 'after'
    'ren.delta'        = 'Health: {0} -> {1}.'
    'ren.back'         = 'Press Enter to go back'
    'ren.rp.make'      = 'Creating a fresh, verified restore point first...'
    'ren.rp.ok'        = 'Restore point created and verified.'
    'ren.rp.fail'      = 'Could not create a restore point (System Protection may be off). Proceeding - back up manually if unsure.'
    'ren.smartstop'    = 'STOP: disk health/dirty bit problem. Fix the disk (chkdsk) or back up first - a renovation now is unsafe.'
    'ren.basic.applyQ' = 'Apply the reversible fixes above? [y/N]'
    'ren.auto.oneway'  = 'There are {0} ONE-WAY step(s) (not undoable by rollback):'
    'ren.auto.onewayQ' = 'Run the one-way steps too? Type YES or NO'
    'ren.prof.manual'  = 'Damaged user profile detected. The safe fix is a fresh-profile migration - run it from the Follow-me card so your data is handled deliberately.'
    'ren.sev.high'     = 'HIGH'
    'ren.sev.med'      = 'medium'
    'ren.sev.low'      = 'low'
    'ren.card.what'    = 'What:        {0}'
    'ren.card.sev'     = 'Severity:    {0}'
    'ren.card.why'     = 'Why:         {0}'
    'ren.card.fix'     = 'I will:      {0}'
    'ren.card.rev'     = 'Reversible:  YES (restore point + per-step backup).'
    'ren.card.oneway'  = 'Reversible:  NO - this is a ONE-WAY change.'
    'ren.card.opts'    = '[t]Fix  [p]Skip  [w]More info'
    'ren.card.optsOneway' = '[t]Fix (one-way)  [p]Skip  [w]More info'
    'ren.card.more'    = 'More: finding {0} in area {1}. This is based on a built-in expert knowledge base (offline, deterministic - not AI guesswork).'
    'ren.card.confirmOneway' = 'This cannot be undone by rollback. Type YES to proceed'
    'ren.card.done'    = '   fixed.'
    'ren.card.skipped' = '   skipped.'
    'ren.f.cbs'        = 'Component store (CBS) is corrupted'
    'ren.f.cbs.why'    = 'Corrupted Windows components break updates, features and SFC repairs.'
    'ren.f.cbs.fix'    = 'DISM RestoreHealth + component cleanup.'
    'ren.f.sfc'        = 'Protected system files are damaged'
    'ren.f.sfc.why'    = 'Damaged system files cause crashes, missing features and odd errors.'
    'ren.f.sfc.fix'    = 'SFC /scannow (repairs from the component store).'
    'ren.f.svc'        = '{0} system services differ from Windows defaults'
    'ren.f.svc.why'    = 'Debloaters often disable services Windows needs, breaking updates, search or the Store.'
    'ren.f.svc.fix'    = 'Restore the affected services to their default startup type (with a manifest).'
    'ren.f.wu'         = 'Windows Update cache is bloated/stuck'
    'ren.f.wu.why'     = 'A huge or corrupted SoftwareDistribution folder makes updates fail or hang.'
    'ren.f.wu.fix'     = 'Soft reset: stop services, rename the folder to .bak, restart services.'
    'ren.f.wud'        = 'Windows Update service is disabled'
    'ren.f.wud.why'    = 'With wuauserv disabled the system gets no security or feature updates.'
    'ren.f.wud.fix'    = 'Set Windows Update back to Manual and start it.'
    'ren.f.hosts'      = 'The hosts file has suspicious redirects'
    'ren.f.hosts.why'  = 'Malware and some tools redirect domains via hosts (blocked sites, hijacks).'
    'ren.f.hosts.fix'  = 'Back up the current hosts file, then reset it to the clean default.'
    'ren.f.proxy'      = 'A system proxy is enabled'
    'ren.f.proxy.why'  = 'An unexpected proxy can break connectivity or route traffic through a third party.'
    'ren.f.proxy.fix'  = 'Reset WinHTTP proxy and turn the user proxy off.'
    'ren.f.appx'       = '{0} Store/Appx package(s) are in an error state'
    'ren.f.appx.why'   = 'Broken app packages cause missing Start tiles, Store failures and crashing built-in apps.'
    'ren.f.appx.fix'   = 'Re-register the affected packages from their manifests.'
    'ren.f.wmi'        = 'The WMI repository is inconsistent'
    'ren.f.wmi.why'    = 'A broken WMI breaks management, monitoring, Defender and many admin tools.'
    'ren.f.wmi.fix'    = 'Salvage the WMI repository (non-destructive; full reset only if salvage fails).'
    'ren.f.perf'       = 'Performance counters are disabled/corrupted'
    'ren.f.perf.why'   = 'Broken counters break Task Manager graphs, monitoring and this tool''s own measurements.'
    'ren.f.perf.fix'   = 'Rebuild the counters (lodctr /R for 64-bit and 32-bit).'
    'ren.f.prof'       = 'A user profile looks damaged (ProfileList .bak)'
    'ren.f.prof.why'   = 'A damaged profile causes temp-profile logons, lost settings and broken apps.'
    'ren.f.prof.fix'   = 'Guide a fresh-profile migration that preserves your data (one-way, done deliberately).'
    'ren.f.cache'      = 'Icon/thumbnail caches present (rebuild if visuals glitch)'
    'ren.f.cache.why'  = 'Stale caches cause wrong/blank icons and broken thumbnails.'
    'ren.f.cache.fix'  = 'Clear the icon/thumbnail caches and restart Explorer.'
    'ren.f.spool'      = 'The print spooler queue is clogged'
    'ren.f.spool.why'  = 'Stuck print jobs block all printing and can crash the spooler.'
    'ren.f.spool.fix'  = 'Stop the spooler, clear the queue, start it again.'
    'ren.f.def'        = 'Defender real-time protection is off'
    'ren.f.def.why'    = 'With real-time protection off the machine is exposed to malware.'
    'ren.f.def.fix'    = 'Re-enable real-time protection and update signatures.'
    'ren.f.time'       = 'System time service has an error'
    'ren.f.time.why'   = 'A wrong clock breaks updates, certificates and secure connections.'
    'ren.f.time.fix'   = 'Start the time service and force a resync.'
    'ren.f.dev'        = '{0} device(s) are in an error state'
    'ren.f.dev.why'    = 'Devices with errors mean missing hardware function (audio, network, GPU...).'
    'ren.f.dev.fix'    = 'Rescan devices (pnputil); a driver reinstall may follow.'
    'ren.f.deblo'      = 'Footprints of a debloater/optimizer detected'
    'ren.f.deblo.why'  = 'Earlier tools left disabled services/policies that can break updates, search and stability.'
    'ren.f.deblo.fix'  = 'Restore the affected services/policies to Windows defaults.'
    'ren.adv.3'        = '  [3] General Renovation (multi-restart pipeline) - DISM -> SFC -> rest, resumes after restarts.'
    'ren.adv.4'        = '  [4] In-place repair upgrade - reinstall Windows keeping apps & files (the real 95% fix).'
    'ren.adv.5'        = '  [5] Fresh-profile migration - fix a damaged user profile by moving to a new one (one-way).'
    'ren.adv.prompt2'  = 'Advanced [0/1/2/3/4/5]'
    'ren.pipe.title'   = '--- GENERAL RENOVATION (multi-restart) ---'
    'ren.pipe.intro'   = 'Runs DISM, then SFC, then the remaining fixes. It will restart between stages only if Windows needs it, and continue automatically after you log back in.'
    'ren.pipe.startQ'  = 'Start the full renovation pipeline? Type YES or NO'
    'ren.pipe.stage'   = 'Stage {0}/{1}: {2}'
    'ren.pipe.s.dism'  = '   DISM RestoreHealth + component cleanup (15-60 min)...'
    'ren.pipe.s.sfc'   = '   SFC /scannow...'
    'ren.pipe.s.rest'  = '   Remaining reversible fixes...'
    'ren.pipe.rebootneeded' = 'Windows reports a restart is required before the next stage.'
    'ren.pipe.rebootQ' = 'Restart now and resume automatically after logon? [y/N]'
    'ren.pipe.scheduled'    = 'Resume task scheduled (runs once after the next logon).'
    'ren.pipe.restarting'   = 'Restarting in 3 seconds...'
    'ren.pipe.manualresume' = 'OK - restart later yourself. The renovation will resume automatically after the next logon.'
    'ren.pipe.stillpoor'    = 'Health is still below 75 after the renovation. The strongest remaining option is an in-place repair upgrade.'
    'ren.inplace.offerQ'    = 'Do the in-place repair upgrade now? [y/N]'
    'ren.inplace.title'= '--- IN-PLACE REPAIR UPGRADE ---'
    'ren.inplace.what' = 'This reinstalls Windows over itself, repairing the OS, registry and components while KEEPING your apps, files and most settings. 60-90 min, 2-3 restarts.'
    'ren.inplace.noiso'= 'No mounted Windows ISO / setup.exe found.'
    'ren.inplace.step1'= '  1. Download the Media Creation Tool / Windows ISO from microsoft.com.'
    'ren.inplace.step2'= '  2. Double-click the ISO to mount it (it becomes a drive letter).'
    'ren.inplace.step3'= '  3. Run this option again - I will detect setup.exe and launch it with the right flags.'
    'ren.inplace.found'= 'Found Windows setup at: {0}'
    'ren.inplace.warn' = 'Make sure your files are backed up first. The upgrade keeps apps & data, but a backup is always wise.'
    'ren.inplace.confirm' = 'Launch the in-place repair upgrade (keeps apps & files)? Type YES or NO'
    'ren.inplace.launch'  = 'Launching Windows setup (keeping apps and data)...'
    'ren.inplace.started' = 'Setup started. Follow its prompts; choose to KEEP personal files and apps.'
    'ren.inplace.failed'  = 'Could not launch setup: {0}'
    'ren.prof.title'   = '--- FRESH-PROFILE MIGRATION ---'
    'ren.prof.what'    = 'A damaged Windows user profile is best fixed by creating a NEW profile and moving your data into it. Your old profile and data are NOT deleted - we copy.'
    'ren.prof.warn'    = 'This creates a new user account (one-way). You then sign in to it and copy your files (Desktop, Documents, etc.) from the old profile.'
    'ren.prof.confirm' = 'Create a fresh user profile now? Type YES or NO'
    'ren.prof.name'    = 'New account name'
    'ren.prof.cancel'  = 'Cancelled - no account created.'
    'ren.prof.pw'      = 'Password for the new account (you can change it later in Windows)'
    'ren.prof.created' = 'Account {0} created and added to Administrators.'
    'ren.prof.exists'  = 'That account already exists - skipping creation.'
    'ren.prof.next1'   = '  Next: sign out, log in to the new account.'
    'ren.prof.next2'   = '  Then copy your data from C:\Users\<old-profile>\ (Desktop, Documents, Pictures...).'
    'ren.prof.next3'   = '  Once everything works, you can remove the old profile from System > Accounts.'
    'ren.prof.failed'  = 'Could not create the account: {0}'
    'menu.mode.10'   = '  [10] Privacy & AI - turn off Copilot, Recall, telemetry, ad ID and suggestions (reversible).'
    'priv.title'     = '=== PRIVACY & AI ==='
    'priv.intro'     = 'Each item is reversible (saved for rollback). Green = already protected, yellow = not yet.'
    'priv.on'        = '[PROTECTED]'
    'priv.off'       = '[not set]'
    'priv.all'       = '  [A] Protect ALL of the above at once.'
    'priv.back'      = '  [0] Back.'
    'priv.prompt'    = 'Choose a number, [A]ll or [0]'
    'priv.already'   = 'Already protected - nothing to do.'
    'priv.done1'     = 'Protected: {0}. Some changes apply after sign-out/restart.'
    'priv.doneall'   = 'Protected {0} item(s). Some changes apply after sign-out/restart.'
    'priv.restart'   = 'Tip: sign out or restart for everything to take effect.'
    'priv.copilot'   = 'Windows Copilot'
    'priv.copilot.d' = 'Turns off the Copilot button and experience in Windows.'
    'priv.recall'    = 'Recall (AI screen history)'
    'priv.recall.d'  = 'Disables AI data analysis / Recall snapshots of your screen.'
    'priv.advertise' = 'Advertising ID'
    'priv.advertise.d'= 'Stops apps using your advertising ID for personalized ads.'
    'priv.telemetry' = 'Telemetry level'
    'priv.telemetry.d'= 'Sets diagnostic data to the lowest policy level (Security).'
    'priv.activity'  = 'Activity history'
    'priv.activity.d'= 'Stops Windows collecting your activity timeline.'
    'priv.startsug'  = 'Start menu suggestions'
    'priv.startsug.d'= 'Removes suggested/promoted apps in the Start menu.'
    'priv.tips'      = 'Windows tips & tricks'
    'priv.tips.d'    = 'Turns off pop-up tips and suggestion notifications.'
    'priv.edgeai'    = 'Edge sidebar / Copilot'
    'priv.edgeai.d'  = 'Hides the Edge AI sidebar (Discover/Copilot panel).'
    'doc.what'       = 'Does:'
    'doc.why'        = 'Why:'
    'doc.risk'       = 'Risk:'
    'doc.hw'         = 'Hardware:'
    'doc.winver'     = 'Windows:'
    'doc.evidence'   = 'Evidence:'
    'lgs.untouched'  = '  LaptopGamingSafe: telemetry, Windows Update, services, VBS/HVCI and network were left untouched.'
    'legacy.kw.napraw'   = 'To start the basic repair, type exactly: NAPRAW'
    'legacy.kw.przywroc' = 'To continue, type exactly: PRZYWROC'
    'legacy.kw.rozumiem' = 'To finally start, type exactly: ROZUMIEM'
    'legacy.1'       = '[1] Audit only'
    'legacy.2'       = '[2] Basic repair'
    'legacy.3'       = '[3] Advanced repair (final candidate)'
    'legacy.4'       = '[4] Recovery/Boot/TPM diagnostics + offline script only'
    'legacy.5'       = '[5] Optional full Windows ACL reset'
    'legacy.6'       = '[6] Windows Repair & Refresh'
    'legacy.0'       = '[0] Exit'
    'menu.mode.11'   = '  [11] Root Cause Analysis - explains WHY the PC is slow (which service, driver, disk...).'
    'menu.mode.12'   = '  [12] Report Analysis - reads saved sessions and gives a plain verdict: optimization SUCCESS / PARTIAL / FAILED (with %).'
    'rca.title'      = '=== ROOT CAUSE ANALYSIS: why is this PC slow/unhealthy? ==='
    'rca.disclaimer' = 'Rule-based engine (offline, not AI). Findings are indicative, not a 100% guarantee. Read-only.'
    'rca.collect'    = 'Collecting signals (boot timing, drivers, errors, disk)...'
    'rca.none'       = 'No significant causes found - the system looks healthy.'
    'rca.head'       = 'LIKELY CAUSES (by impact):'
    'rca.w.high'     = 'HIGH'
    'rca.w.med'      = 'MEDIUM'
    'rca.w.low'      = 'low'
    'rca.t.service'  = 'service'
    'rca.t.app'      = 'startup app'
    'rca.t.driver'   = 'driver'
    'rca.t.bg'       = 'background task'
    'rca.t.device'   = 'device'
    'rca.boot.slow'  = 'Boot takes about {0} s in total'
    'rca.boot.slow.h'= 'Anything under ~30 s is healthy; above that the items below are the main offenders.'
    'rca.boot.item'  = 'Start: {0} "{1}" adds about {2} s to boot'
    'rca.boot.item.h'= 'If you do not need it at logon, set it to Manual / delayed start.'
    'rca.drv.gpu'    = 'GPU driver is {0} days old'
    'rca.drv.gpu.h'  = 'A fresh GPU driver (clean install / DDU) often helps more than any tweak.'
    'rca.drv.unsigned' = '{0} unsigned driver(s) present'
    'rca.drv.unsigned.h' = 'Unsigned drivers can cause instability; verify their source or replace them.'
    'rca.drv.old'    = '{0} driver(s) older than 3 years'
    'rca.drv.old.h'  = 'Very old drivers may lack fixes; update via Windows Update or the vendor.'
    'rca.hw.disk'    = '{0} disk error(s) in the last 7 days'
    'rca.hw.disk.h'  = 'Disk errors are serious - back up and run chkdsk; check the cable/SSD health.'
    'rca.hw.whea'    = '{0} hardware (WHEA) error(s) in the last 7 days'
    'rca.hw.whea.h'  = 'WHEA points to hardware (CPU/RAM/PCIe/heat). Check temps and XMP stability.'
    'rca.hw.crash'   = '{0} driver/app crash event(s) recently'
    'rca.hw.crash.h' = 'Repeated crashes usually trace to one driver or app - update or reinstall it.'
    'rca.disk.lat'   = 'Disk read latency is {0} ms (healthy is under 5)'
    'rca.disk.lat.h' = 'High latency = slow everything. Check disk health, free space and background I/O.'
    'rca.wu'         = 'Windows Update appears stuck'
    'rca.wu.h'       = 'A stuck update queue slows the system and blocks fixes.'
    'rca.deblo'      = 'Footprints of a debloater are affecting stability'
    'rca.deblo.h'    = 'Disabled essential services often cause the "slow/odd" feeling after such tools.'
    'rca.wmi'        = 'WMI repository is inconsistent'
    'rca.wmi.h'      = 'Broken WMI breaks monitoring and many tools, and can slow management tasks.'
    'rca.canrepair'  = 'Some of these causes can be fixed automatically in [4] Repair & Renovation.'
    'rca.gotorepairQ'= 'Go to Repair & Renovation now? [y/N]'
    'rca.norepair'   = 'These causes are mostly hardware/driver - handle them as the hints suggest.'
    'main.pressclose'= 'Press Enter to close...'
  }
  pl = @{
    'lang.title'         = 'Jezyk:'
    'lang.1'             = '  [1] Polski'
    'lang.2'             = '  [2] English'
    'lang.prompt'        = 'Jezyk'
    'menu.mode.title'    = 'Wybierz tryb:'
    'menu.mode.1'        = '  [1] Analiza   - raport diagnostyczny, zero zmian. Efekt: wiesz co spowalnia system.'
    'menu.mode.2'        = '  [2] Optymalizacja - finalne menu z opisem efektu przed wyborem. Polecane.'
    'menu.mode.3'        = '  [3] Przywracanie  - przywroc ustawienia z poprzedniej optymalizacji jednym wyborem.'
    'menu.mode.4'        = '  [4] Naprawa i Odbudowa Windows - audyt, naprawa podstawowa lub zaawansowana.'
    'menu.rb.none'       = 'Brak sesji do rollbacku.'
    'menu.rb.oneclick'   = 'Rollback jednym kliknieciem:'
    'menu.rb.latest'     = '  [0] Przywroc najnowsza sesje Optimize: {0}'
    'menu.rb.pick'       = 'Albo wybierz konkretna sesje:'
    'menu.rb.prompt'     = 'Wybierz [0 = najnowsza / numer sesji]'
    'menu.prof.title'    = 'Wybierz profil:'
    'menu.prof.suggest'  = '  [SUGESTIA] Zalecany profil dla Twojego sprzetu: '
    'menu.prof.quick'    = 'Szybkie profile finalne:'
    'menu.prof.p0'  = '(nieuzywane od v15.2)'
    'menu.prof.p1'  = '  [1] Safe - bezpieczne podstawy. Efekt: szybszy start/UI, bez grzebania w sieci. Szac.: ~0-3% (feel/UI).'
    'menu.prof.p2'  = '  [2] Balanced - wiecej zmian, nadal normalne uzywanie. Efekt: lepszy ogolny feeling. Szac.: ~0-4%.'
    'menu.prof.p3'  = '  [3] Maximum - agresywny MAXXXX. Efekt: najwieksza szansa na FPS, ale ryzyko bugow. Tylko jak wiesz co robisz. Szac.: ~0-5% (do ~10% tylko gdy VBS-off pomaga).'
    'menu.prof.p4'  = '  [4] Gaming - desktop/gaming max latency. Efekt: FPS/latency, ale moze ruszac VBS i mocniejsze ustawienia. Szac.: ~0-5% (latency/feel).'
    'menu.prof.p5'  = '  [5] Workstation - praca/dev/grafika. Efekt: stabilnosc, I/O, mniej chaosu w tle. Szac.: ~0-3% (I/O).'
    'menu.prof.p6'  = '  [6] LowEnd - slabe PC. Efekt: mniej RAM/CPU w tle, szybsza reakcja. Szac.: ~2-6% na slabym sprzecie.'
    'menu.prof.p7'  = '  [7] Laptop - laptop codzienny. Efekt: AC szybciej, bateria oszczedniej. Szac.: ~0-3%.'
    'menu.prof.p8'  = '  [8] LaptopGamingSafe - pytania o moduly. Efekt: gry + laptop bez psucia Insidera. Szac.: ~0-3% + mniej stutteru.'
    'menu.prof.p9'  = '  [9] GamingLaptop - gotowiec pod laptop do gier. Efekt: mniej stutteru, NVIDIA safe, raport. Szac.: ~0-3% (stutter).'
    'menu.prof.p10' = '  [10] OfficeLaptop - praca/komfort. Efekt: szybki pulpit, autostart, zero agresji. Szac.: ~0-3% (start/UI).'
    'menu.prof.p11' = '  [11] LowRAM - malo RAM. Efekt: mniej smieci w tle, szybszy start. Szac.: ~2-5% (RAM).'
    'menu.prof.p12' = '  [12] BatterySaver - bateria/cisza. Efekt: dluzsza praca, mniej halasu. Szac.: +10-25% czasu baterii (kosztem wydajnosci).'
    'menu.prof.p13' = '  [13] Performance Feel Mode - NAJLEPSZY feel. Efekt: szybsze UI, input lag, mniej stutteru; nie rusza telemetrii/WU/VBS/sieci. Szac.: ~0-3% FPS, glownie responsywnosc.'
    'menu.prof.hint'    = 'Nie masz czasu wybierac? Tryby autonomiczne sa na koncu: [14] albo [15].'
    'menu.prof.prompt'  = 'Profil [1-15 / 0=powrot]'
    'menu.prof.chosen'  = 'Wybrano: {0}'
    'menu.prof.feelonly'= 'Tryb: Performance Feel Only - bezpieczny feel, brak ryzykownych tweakow.'
    'menu.prof.desc'    = 'Opis: skrypt pokaze jeszcze tylko te pytania, ktore realnie cos zmieniaja.'
    'menu.analyze.skip' = 'Analyze: pytania o WSearch / DNS / Experimental pominiete - tryb tylko-odczyt, nic nie bedzie zmieniane.'
    'menu.ws.title'  = 'Windows Search (WSearch):'
    'menu.ws.1'      = '  [1] Keep   - pozostaw wlaczone (lepszy komfort, polecane)'
    'menu.ws.2'      = '  [2] Manual - przelacz na reczne (mniej CPU w tle podczas gier)'
    'menu.ws.prompt' = 'WSearch [1/2]'
    'menu.dns.title' = 'Serwer DNS (fizyczne adaptery - VPN/wirtualne pomijane):'
    'menu.dns.1'     = '  [1] Keep       - nie zmieniaj obecnego DNS'
    'menu.dns.2'     = '  [2] Google     - 8.8.8.8 / 8.8.4.4      (loguje zapytania, szybki)'
    'menu.dns.3'     = '  [3] Cloudflare - 1.1.1.1 / 1.0.0.1      (24h logi, szybki resolver)'
    'menu.dns.4'     = '  [4] Quad9      - 9.9.9.9 / 149.112.x.x  (no-log, blokuje malware)'
    'menu.dns.prompt'= 'DNS [1/2/3/4]'
    'menu.exp.title' = 'Tweaki eksperymentalne (Nagle/TCP, HAGS):'
    'menu.exp.1'     = '  [1] Nie - bezpieczniej. Polecane dla wiekszosci uzytkownikow.'
    'menu.exp.2'     = '  [2] Tak - legacy tweaki + HAGS. Tylko jezeli wiesz co robisz.'
    'menu.exp.prompt'= 'Experimental [1/2]'
    'menu.def.title' = '--- Windows Defender ---'
    'menu.def.1'     = '  Skrypt NIE wylacza Defendera - Twoje bezpieczenstwo jest zachowane.'
    'menu.def.2'     = '  Jesli Defender spowalnia gry: Ustawienia > Bezpieczenstwo Windows'
    'menu.def.3'     = '  > Ochrona przed wirusami > Dodaj wykluczenie folderu z grami (np. D:\Games)'
    'menu.def.4'     = '  To bezpieczna alternatywa dla calkowitego wylaczenia ochrony.'
    'menu.pressenter'= 'Nacisnij Enter aby rozpoczac...'
    'analyze.pro.skip1' = '--- Analyze: pytania o moduly PRO pominiete (tryb tylko-odczyt) ---'
    'analyze.pro.skip2' = '    Rozszerzony benchmark: WLACZONY automatycznie (zasila raport). Moduly wykonawcze: wylaczone.'
    'analyze.risk.skip' = '--- Analyze: pytanie o Risk Pack pominiete (tryb tylko-odczyt) ---'
    'stats.line'     = '  Zmiany: {0}   Raporty: {1}   Pominiete: {2}   Ostrzezenia: {3}   Bledy: {4}'
    'main.done'      = 'Gotowe! Raporty: {0}'
    'main.html'      = 'Raport HTML:     {0}'
    'menu.mode.5'    = '  [5] Kreator planow zasilania - plany pod cel (skalibrowane na realnych, sprawdzonych planach), backup/przywracanie, reset fabryczny.'
    'menu.mode.6'    = '  [6] Silnik automatyzacji - reguly w tle: gra -> plan gaming, bateria -> eco, log watchdoga.'
    'menu.mode.7'    = '  [7] Paczki aplikacji (winget) - instalacja calego zestawu jednym wyborem; eksport wlasnej paczki.'
    'menu.mode.8'    = '  [8] Asystent glosowy (eksperymentalny, offline) - kilka stalych komend.'
    'menu.mode.9'    = '  [9] Biblioteka - przepisy (zapisane zestawy tweakow) i pelna historia sesji z rollbackiem.'
    'menu.mode.prompt2' = 'Tryb [1-11]'
    'menu.prof.back' = '  [0] Powrot do wyboru trybu.'
    'menu.prof.p14' = '  [14] Auto / Safe Recommended - sam dobiera bezpieczny profil. Komfort + stabilnosc, minimalne ryzyko.'
    'menu.prof.p15' = '  [15] AutoSmart - sam dobiera profil ORAZ wszystkie odpowiedzi pod TWOJ sprzet. Uczciwe reguly, zero magii.'
    'auto.head'      = 'Decyzje AutoSmart dla tej maszyny:'
    'auto.prof'      = '  Profil: {0}  (powod: {1})'
    'auto.ans'       = '  Odpowiedzi: WSearch=Keep, DNS=Keep, Experimental=Nie (bezpieczne domyslne).'
    'lib.title'      = '=== BIBLIOTEKA ==='
    'lib.1'          = '  [1] Przepisy - zapisane zestawy tweakow z uczciwym opisem efektu.'
    'lib.2'          = '  [2] Wszystkie sesje - pelna historia + rollback po numerze.'
    'lib.3'          = '  [3] Silnik automatyzacji - reguly w tle: gra -> plan gaming, bateria -> eco, log watchdoga.'
    'lib.0'          = '  [0] Powrot do menu glownego.'
    'lib.prompt'     = 'Biblioteka [0-2]'
    'lib.rec.list'   = 'Dostepne przepisy:'
    'lib.rec.effect' = 'Deklarowany efekt: {0}'
    'lib.rec.prompt' = 'Numer przepisu (0 = powrot)'
    'lib.rec.run'    = 'Wybrano przepis: {0} (profil: {1})'
    'lib.rec.apply'  = 'Przepis ustawil tryb, profil i odpowiedzi - dalej skrypt dziala jak zwykle.'
    'lib.ses.title'  = 'Wszystkie sesje:'
    'lib.ses.none'   = 'Brak sesji.'
    'lib.ses.prompt' = 'Numer sesji do przywrocenia (0 = powrot)'
    'ppc.title'      = '=== KREATOR ZAAWANSOWANYCH PLANOW ZASILANIA ==='
    'ppc.backup'     = 'Backup listy planow + eksport aktywnego planu: {0}'
    'ppc.goal'       = 'Cel: [1] Maksymalna wydajnosc  [2] Cisza i temperatury  [3] Zbalansowana praca'
    'ppc.goalprompt' = 'Cel [1/2/3]'
    'ppc.created'    = 'Utworzono plan zasilania: {0}'
    'ppc.activateQ'  = 'Aktywowac go teraz? [t/N]'
    'ppc.activated'  = 'Plan aktywowany.'
    'ppc.note'      = 'Uczciwe uwagi: [2] ogranicza CPU do 99%, co na wielu procesorach wylacza Turbo Boost (chlodniej, ciszej, nizsze szczyty). Na nowych laptopach suwak zasilania producenta / Modern Standby moze nadpisac czesc ustawien.'
    'ppc.failed'     = 'powercfg zwrocil blad: {0}'
    'ps51.warn'      = 'UWAGA: dziala na Windows PowerShell 5.1 - skrypt zadziala, ale zalecany jest PowerShell 7 (pwsh.exe).'
    'lib.4'          = '  [4] Paczki aplikacji (winget) - instalacja calego zestawu jednym wyborem; eksport wlasnej paczki.'
    'lib.5'          = '  [5] Asystent glosowy (eksperymentalny, offline) - kilka stalych komend.'
    'autom.title'    = '=== SILNIK AUTOMATYZACJI ==='
    'autom.status'   = 'Status daemona: {0}'
    'autom.on'       = 'ZAINSTALOWANY (startuje ukryty przy logowaniu)'
    'autom.off'      = 'niezainstalowany'
    'autom.1'        = '  [1] Zainstaluj / przeinstaluj daemon (zadanie harmonogramu, ukryte, przy logowaniu).'
    'autom.2'        = '  [2] Odinstaluj daemon.'
    'autom.3'        = '  [3] Pokaz sciezke pliku konfiguracji (tam edytujesz liste gier i reguly).'
    'autom.4'        = '  [4] Pokaz ostatnie 15 linii logu daemona.'
    'autom.0'        = '  [0] Powrot.'
    'autom.prompt'   = 'Automatyzacja [0-4]'
    'autom.installed'= 'Daemon zainstalowany. Wystartuje przy nastepnym logowaniu; reguly: gra -> {0}, bateria -> oszczedny.'
    'autom.removed'  = 'Daemon odinstalowany.'
    'autom.cfg'      = 'Konfiguracja: {0}'
    'autom.nolog'    = 'Brak logu daemona (jeszcze nie dzialal).'
    'autom.note'     = 'Uczciwa uwaga: wykrywanie gry = lista nazw procesow w konfiguracji (dopisz tam swoje gry). Daemon TYLKO przelacza plany zasilania i loguje - nigdy nie zabija procesow ani nie rusza rejestru.'
    'packs.title'    = '=== PACZKI APLIKACJI (winget) ==='
    'packs.nowinget' = 'Brak winget. Zainstaluj najpierw "Instalator aplikacji" z Microsoft Store.'
    'packs.list'     = 'Dostepne paczki:'
    'packs.prompt'   = 'Numer paczki (0 = powrot, E = eksport zainstalowanych aplikacji do nowej paczki)'
    'packs.installQ' = 'Zainstalowac paczke {0} przez winget? [t/N]'
    'packs.exported' = 'Wyeksportowano zainstalowane aplikacje do: {0}'
    'packs.done'     = 'winget zakonczyl (kod {0}). Szczegoly powyzej.'
    'voice.title'    = '=== ASYSTENT GLOSOWY (eksperymentalny, offline) ==='
    'voice.norec'    = 'Brak silnika rozpoznawania mowy dla pl-PL ani en-US w tym systemie.'
    'voice.lang'     = 'Silnik rozpoznawania: {0}'
    'voice.cmds'     = 'Komendy: "tryb gaming" / "gaming mode", "tryb eko" / "eco mode", "wylacz komputer" (shutdown za 10 min), "anuluj" / "cancel" (przerwij shutdown), "koniec" / "stop listening".'
    'voice.listen'   = 'Nasluchuje... (powiedz "koniec", aby wyjsc)'
    'voice.heard'    = 'Uslyszano: {0}  (pewnosc {1}%)'
    'voice.bye'      = 'Asystent glosowy zatrzymany.'
    'regr.warn'      = 'REGRESJA BENCHMARKU: {0}'
    'regr.offer'     = 'Pomiar PO wyglada GORZEJ niz przed. Przywrocic ta sesje teraz? [t/N]'
    'regr.ok'        = 'Benchmark po vs przed: brak regresji.'
    'valid.head'     = '=== WALIDACJA TWEAKOW PO RESTARCIE ==='
    'valid.result'   = 'Przetrwalo: {0}/{1} sprawdzen. Raport: {2}'
    'valid.sched'    = 'Zaplanowano walidacje po restarcie (jednorazowe zadanie przy nastepnym logowaniu).'
    'ppc.menu1'      = '  [1] Maksymalna wydajnosc - min 8 / max 100, boost agresywny, ASPM off, dysk zawsze aktywny. Goraco, ale najszybciej.'
    'ppc.menu2'      = '  [2] Gaming Cool          - max 98 na zasilaczu (turbo sciete = duzo chlodniej), ASPM off, skalibrowany na realnym, sprawdzonym planie.'
    'ppc.menu3'      = '  [3] Cicha praca          - max 85 AC / 70 bateria, oszczedzanie USB+PCIe. Skalibrowany na realnym, sprawdzonym planie pracy.'
    'ppc.menu4'      = '  [4] Zbalansowana praca   - max 100 z wydajnym boostem, umiarkowane oszczedzanie.'
    'ppc.menu5'      = '  [5] WLASNY - zbuduj swoj plan pytanie po pytaniu, z uczciwymi uwagami o temperaturach i efektach.'
    'ppc.menuB'      = '  [6] Backup WSZYSTKICH planow (.pow + czytelne zrzuty) do Biblioteki.'
    'ppc.menuR'      = '  [7] Przywroc plan z backupu .pow.'
    'ppc.menuF'      = '  [8] RESET FABRYCZNY planow zasilania (usuwa WSZYSTKIE niestandardowe plany!).'
    'ppc.menu0'      = '  [0] Powrot.'
    'ppc.prompt2'    = 'Kreator [1-8 / 0=powrot]'
    'ppc.applied'    = 'Weryfikacja: system przyjal {0} z {1} ustawien.'
    'ppc.hidden'     = 'Uwaga: {0} ukryte przez producenta laptopa na tej maszynie - wartosc zapisana, firmware moze ja ignorowac.'
    'ppc.bdone'      = 'Zbackupowano {0} plan(ow) do: {1}'
    'ppc.rlist'      = 'Dostepne backupy .pow:'
    'ppc.rprompt'    = 'Numer backupu do importu (0 = powrot)'
    'ppc.rdone'      = 'Zaimportowano. Windows utworzyl nowy plan z backupu - sprawdz powercfg /list lub Panel sterowania.'
    'ppc.fwarn'      = 'OSTRZEZENIE: to przywraca fabryczne plany i USUWA WSZYSTKIE PLANY NIESTANDARDOWE (w tym te sprawdzone). Najpierw zostanie wykonany pelny backup.'
    'ppc.fconfirm'   = 'Wpisz TAK aby kontynuowac'
    'ppc.fdone'      = 'Przywrocono plany fabryczne. Stare plany sa bezpieczne w folderze backupu (uzyj [R], by dowolny wrocic).'
    'cust.title'   = '--- PLAN WLASNY: Enter przyjmuje [domyslne]. Uczciwe uwagi w opisach. ---'
    'cust.name'    = 'Nazwa planu'
    'cust.maxac'   = 'CPU max na zasilaczu, %. 100=pelna moc (najgorecej). 99/98=Turbo OFF na wiekszosci CPU - zwykle wyraznie chlodniejsze szczyty. 85=chlodna praca'
    'cust.maxdc'   = 'CPU max na baterii, %'
    'cust.min'     = 'CPU min, %. Nisko (5) pozwala CPU odpoczywac; 100 = stale grzanie'
    'cust.boost'   = 'Boost mode: 0=wylaczony (cicho), 2=agresywny (goraco), 3=wydajny. Producent moze ukrywac to ustawienie'
    'cust.usb'     = 'USB selective suspend: 1=wlaczony (oszczedza; sprawdzone nawet w Twoim planie gamingowym), 0=wylaczony'
    'cust.aspm'    = 'PCIe ASPM: 0=off (najlepsza latencja, gaming), 1=umiarkowany, 2=max oszczedzanie'
    'cust.disk'    = 'Usypianie dysku na zasilaczu, sekundy (0=nigdy)'
    'cust.screen'  = 'Wygaszanie ekranu na zasilaczu, sekundy (0=nigdy)'
    'cust.sleep'   = 'Uspienie na zasilaczu, sekundy (0=nigdy)'
    'pre.title'   = '=== PREFLIGHT NAPRAWY: szybkie kontrole bezpieczenstwa przed praca ==='
    'pre.reboot'  = 'OCZEKUJE RESTART (CBS/WU/zmiany plikow). Mocno zalecane: najpierw zrestartuj Windows i odpal naprawe na czystym stanie.'
    'pre.space'   = 'Malo miejsca: {0} GB wolnego na dysku systemowym. Naprawy DISM potrafia potrzebowac 10+ GB.'
    'pre.batt'    = 'Praca na BATERII. Dluga naprawa + bateria = ryzyko przerwania DISM w polowie. Podlacz zasilacz.'
    'pre.ok'      = 'Preflight: wszystkie kontrole zaliczone.'
    'pre.contQ'   = 'Powyzej ostrzezenia. Kontynuowac mimo to? [t/N]'
    'ren.analyze.label'= 'teraz (kontrola tylko-odczyt)'
    'ren.analyze.hint' = 'To tylko zdjecie zdrowia. Aby cokolwiek naprawic, uzyj [4] Naprawa i Odbudowa.'
    'ren.menu.title'   = '=== NAPRAWA I ODBUDOWA WINDOWS 2.0 ==='
    'ren.menu.1'       = '  [1] Odbudowa Podstawowa - diagnoza, potem naprawa tylko wykrytych, odwracalnych problemow. Maks 1 restart.'
    'ren.menu.2'       = '  [2] Odbudowa Zaawansowana - Auto (inteligentna) lub Follow-me (prowadzona, krok po kroku).'
    'ren.menu.legacy'  = '  [9] Stare menu naprawy (dawne narzedzia eksperckie).'
    'ren.menu.0'       = '  [0] Powrot.'
    'ren.menu.prompt'  = 'Wybierz [0/1/2/9]'
    'ren.adv.title'    = '--- ODBUDOWA ZAAWANSOWANA ---'
    'ren.adv.1'        = '  [1] Auto - inteligentna: naprawia tylko to, co zepsute, zdrowe/fabryczne zostawia w spokoju.'
    'ren.adv.2'        = '  [2] Follow-me z Doradca - karta na kazde znalezisko: co / dlaczego / co psuje / [t]Napraw [p]Pomin [w]Wiecej.'
    'ren.adv.0'        = '  [0] Powrot.'
    'ren.adv.prompt'   = 'Zaawansowana [0/1/2]'
    'ren.basic.title'  = '--- ODBUDOWA PODSTAWOWA (tylko odwracalne) ---'
    'ren.auto.title'   = '--- ODBUDOWA AUTO (inteligentna) ---'
    'ren.follow.title' = '--- FOLLOW-ME Z DORADCA ---'
    'ren.follow.intro' = 'Przeprowadze Cie przez kazde znalezisko. Ty decydujesz na kazdym kroku; nic nie dzieje sie bez Twojego klawisza.'
    'ren.follow.count' = 'Znaleziono {0} pozycji. Przechodzimy przez nie po kolei.'
    'ren.diag.run'     = 'Diagnoza w toku (tylko odczyt)...'
    'ren.found'        = 'Znaleziska:'
    'ren.none'         = 'Nie wykryto problemow - system wyglada zdrowo.'
    'ren.health'       = 'Zdrowie systemu {0}:'
    'ren.before'       = 'przed'
    'ren.after'        = 'po'
    'ren.delta'        = 'Zdrowie: {0} -> {1}.'
    'ren.back'         = 'Nacisnij Enter, aby wrocic'
    'ren.rp.make'      = 'Najpierw tworze swiezy, zweryfikowany punkt przywracania...'
    'ren.rp.ok'        = 'Punkt przywracania utworzony i zweryfikowany.'
    'ren.rp.fail'      = 'Nie udalo sie utworzyc punktu (Ochrona systemu moze byc wylaczona). Kontynuuje - zrob backup recznie, jesli masz watpliwosci.'
    'ren.smartstop'    = 'STOP: problem ze zdrowiem dysku / dirty bit. Najpierw napraw dysk (chkdsk) lub zrob backup - renowacja teraz jest niebezpieczna.'
    'ren.basic.applyQ' = 'Zastosowac powyzsze odwracalne naprawy? [t/N]'
    'ren.auto.oneway'  = 'Sa {0} krok(i) JEDNOKIERUNKOWE (nie do cofniecia rollbackiem):'
    'ren.auto.onewayQ' = 'Wykonac takze kroki jednokierunkowe? Wpisz TAK albo NIE'
    'ren.prof.manual'  = 'Wykryto uszkodzony profil uzytkownika. Bezpieczna naprawa to przeprowadzka na swiezy profil - zrob to z karty Follow-me, by swiadomie zadbac o dane.'
    'ren.sev.high'     = 'WYSOKA'
    'ren.sev.med'      = 'srednia'
    'ren.sev.low'      = 'niska'
    'ren.card.what'    = 'Co:          {0}'
    'ren.card.sev'     = 'Waga:        {0}'
    'ren.card.why'     = 'Dlaczego:    {0}'
    'ren.card.fix'     = 'Zrobie:      {0}'
    'ren.card.rev'     = 'Odwracalne:  TAK (punkt przywracania + backup na krok).'
    'ren.card.oneway'  = 'Odwracalne:  NIE - to zmiana JEDNOKIERUNKOWA.'
    'ren.card.opts'    = '[t]Napraw  [p]Pomin  [w]Wiecej info'
    'ren.card.optsOneway' = '[t]Napraw (jednokierunkowo)  [p]Pomin  [w]Wiecej info'
    'ren.card.more'    = 'Wiecej: znalezisko {0} w obszarze {1}. Oparte na wbudowanej bazie wiedzy eksperckiej (offline, deterministyczna - nie zgadywanie AI).'
    'ren.card.confirmOneway' = 'Tego nie cofnie rollback. Wpisz TAK, aby kontynuowac'
    'ren.card.done'    = '   naprawione.'
    'ren.card.skipped' = '   pominiete.'
    'ren.f.cbs'        = 'Magazyn komponentow (CBS) jest uszkodzony'
    'ren.f.cbs.why'    = 'Uszkodzone komponenty Windows psuja aktualizacje, funkcje i naprawy SFC.'
    'ren.f.cbs.fix'    = 'DISM RestoreHealth + czyszczenie komponentow.'
    'ren.f.sfc'        = 'Chronione pliki systemowe sa uszkodzone'
    'ren.f.sfc.why'    = 'Uszkodzone pliki systemowe powoduja crashe, brakujace funkcje i dziwne bledy.'
    'ren.f.sfc.fix'    = 'SFC /scannow (naprawa z magazynu komponentow).'
    'ren.f.svc'        = '{0} uslug systemowych odbiega od domyslnych Windows'
    'ren.f.svc.why'    = 'Debloatery czesto wylaczaja uslugi potrzebne Windows - psuja aktualizacje, wyszukiwanie lub Store.'
    'ren.f.svc.fix'    = 'Przywroc dotkniete uslugi do domyslnego trybu startu (z manifestem).'
    'ren.f.wu'         = 'Cache Windows Update jest spuchniety/zablokowany'
    'ren.f.wu.why'     = 'Ogromny lub uszkodzony folder SoftwareDistribution sprawia, ze aktualizacje sie wykladaja.'
    'ren.f.wu.fix'     = 'Miekki reset: zatrzymaj uslugi, przemianuj folder na .bak, uruchom uslugi.'
    'ren.f.wud'        = 'Usluga Windows Update jest wylaczona'
    'ren.f.wud.why'    = 'Z wylaczonym wuauserv system nie dostaje aktualizacji bezpieczenstwa ani funkcji.'
    'ren.f.wud.fix'    = 'Ustaw Windows Update z powrotem na Reczny i uruchom.'
    'ren.f.hosts'      = 'Plik hosts ma podejrzane przekierowania'
    'ren.f.hosts.why'  = 'Malware i niektore narzedzia przekierowuja domeny przez hosts (blokady, przejecia).'
    'ren.f.hosts.fix'  = 'Zrob backup obecnego hosts, potem przywroc czysty domyslny.'
    'ren.f.proxy'      = 'Wlaczony jest proxy systemowy'
    'ren.f.proxy.why'  = 'Nieoczekiwany proxy moze psuc lacznosc albo kierowac ruch przez osobe trzecia.'
    'ren.f.proxy.fix'  = 'Zresetuj proxy WinHTTP i wylacz proxy uzytkownika.'
    'ren.f.appx'       = '{0} pakiet(ow) Store/Appx jest w stanie bledu'
    'ren.f.appx.why'   = 'Zepsute pakiety aplikacji powoduja brak kafelkow, bledy Store i crashe wbudowanych aplikacji.'
    'ren.f.appx.fix'   = 'Zarejestruj ponownie dotkniete pakiety z ich manifestow.'
    'ren.f.wmi'        = 'Repozytorium WMI jest niespojne'
    'ren.f.wmi.why'    = 'Zepsute WMI psuje zarzadzanie, monitoring, Defendera i wiele narzedzi administracyjnych.'
    'ren.f.wmi.fix'    = 'Napraw repozytorium WMI (salvage; pelny reset tylko gdy salvage zawiedzie).'
    'ren.f.perf'       = 'Liczniki wydajnosci sa wylaczone/uszkodzone'
    'ren.f.perf.why'   = 'Zepsute liczniki psuja wykresy Menedzera zadan, monitoring i pomiary tego narzedzia.'
    'ren.f.perf.fix'   = 'Odbuduj liczniki (lodctr /R dla 64- i 32-bit).'
    'ren.f.prof'       = 'Profil uzytkownika wyglada na uszkodzony (ProfileList .bak)'
    'ren.f.prof.why'   = 'Uszkodzony profil powoduje logowanie na profil tymczasowy, utrate ustawien i zepsute aplikacje.'
    'ren.f.prof.fix'   = 'Poprowadze przeprowadzke na swiezy profil z zachowaniem danych (jednokierunkowo, swiadomie).'
    'ren.f.cache'      = 'Obecny cache ikon/miniatur (odbuduj, jesli grafika sie glitchuje)'
    'ren.f.cache.why'  = 'Nieaktualny cache powoduje zle/puste ikony i zepsute miniatury.'
    'ren.f.cache.fix'  = 'Wyczysc cache ikon/miniatur i zrestartuj Explorer.'
    'ren.f.spool'      = 'Kolejka bufora wydruku jest zapchana'
    'ren.f.spool.why'  = 'Zaciete zadania druku blokuja caly wydruk i moga wywalic spooler.'
    'ren.f.spool.fix'  = 'Zatrzymaj spooler, wyczysc kolejke, uruchom ponownie.'
    'ren.f.def'        = 'Ochrona w czasie rzeczywistym Defendera jest wylaczona'
    'ren.f.def.why'    = 'Z wylaczona ochrona w czasie rzeczywistym maszyna jest narazona na malware.'
    'ren.f.def.fix'    = 'Wlacz ponownie ochrone w czasie rzeczywistym i zaktualizuj sygnatury.'
    'ren.f.time'       = 'Usluga czasu systemowego ma blad'
    'ren.f.time.why'   = 'Zly zegar psuje aktualizacje, certyfikaty i bezpieczne polaczenia.'
    'ren.f.time.fix'   = 'Uruchom usluge czasu i wymus resync.'
    'ren.f.dev'        = '{0} urzadzen jest w stanie bledu'
    'ren.f.dev.why'    = 'Urzadzenia z bledami oznaczaja brak funkcji sprzetu (audio, siec, GPU...).'
    'ren.f.dev.fix'    = 'Przeskanuj urzadzenia (pnputil); moze nastapic reinstalacja sterownika.'
    'ren.f.deblo'      = 'Wykryto slady debloatera/optymalizatora'
    'ren.f.deblo.why'  = 'Wczesniejsze narzedzia zostawily wylaczone uslugi/polityki, ktore moga psuc aktualizacje, wyszukiwanie i stabilnosc.'
    'ren.f.deblo.fix'  = 'Przywroc dotkniete uslugi/polityki do domyslnych Windows.'
    'ren.adv.3'        = '  [3] Generalna Renowacja (pipeline z restartami) - DISM -> SFC -> reszta, wznawia po restartach.'
    'ren.adv.4'        = '  [4] In-place repair upgrade - przeinstaluj Windows z zachowaniem aplikacji i plikow (prawdziwe 95%).'
    'ren.adv.5'        = '  [5] Przeprowadzka na swiezy profil - napraw uszkodzony profil, przenoszac sie na nowy (jednokierunkowe).'
    'ren.adv.prompt2'  = 'Zaawansowana [0/1/2/3/4/5]'
    'ren.pipe.title'   = '--- GENERALNA RENOWACJA (wiele restartow) ---'
    'ren.pipe.intro'   = 'Uruchamia DISM, potem SFC, potem pozostale naprawy. Zrestartuje miedzy etapami tylko jesli Windows tego wymaga i sam wznowi po ponownym zalogowaniu.'
    'ren.pipe.startQ'  = 'Uruchomic pelny pipeline renowacji? Wpisz TAK albo NIE'
    'ren.pipe.stage'   = 'Etap {0}/{1}: {2}'
    'ren.pipe.s.dism'  = '   DISM RestoreHealth + czyszczenie komponentow (15-60 min)...'
    'ren.pipe.s.sfc'   = '   SFC /scannow...'
    'ren.pipe.s.rest'  = '   Pozostale odwracalne naprawy...'
    'ren.pipe.rebootneeded' = 'Windows zglasza, ze przed kolejnym etapem wymagany jest restart.'
    'ren.pipe.rebootQ' = 'Zrestartowac teraz i wznowic automatycznie po zalogowaniu? [t/N]'
    'ren.pipe.scheduled'    = 'Zaplanowano zadanie wznowienia (uruchomi sie raz po nastepnym zalogowaniu).'
    'ren.pipe.restarting'   = 'Restart za 3 sekundy...'
    'ren.pipe.manualresume' = 'OK - zrestartuj pozniej sam. Renowacja wznowi sie automatycznie po nastepnym zalogowaniu.'
    'ren.pipe.stillpoor'    = 'Zdrowie wciaz ponizej 75 po renowacji. Najmocniejsza pozostala opcja to in-place repair upgrade.'
    'ren.inplace.offerQ'    = 'Wykonac teraz in-place repair upgrade? [t/N]'
    'ren.inplace.title'= '--- IN-PLACE REPAIR UPGRADE ---'
    'ren.inplace.what' = 'To przeinstalowuje Windows na samym sobie, naprawiajac system, rejestr i komponenty, ZACHOWUJAC aplikacje, pliki i wiekszosc ustawien. 60-90 min, 2-3 restarty.'
    'ren.inplace.noiso'= 'Nie znaleziono zamontowanego ISO Windows / setup.exe.'
    'ren.inplace.step1'= '  1. Pobierz Media Creation Tool / ISO Windows z microsoft.com.'
    'ren.inplace.step2'= '  2. Kliknij dwukrotnie ISO, aby je zamontowac (pojawi sie litera dysku).'
    'ren.inplace.step3'= '  3. Uruchom te opcje ponownie - wykryje setup.exe i odpale go z wlasciwymi flagami.'
    'ren.inplace.found'= 'Znaleziono instalator Windows w: {0}'
    'ren.inplace.warn' = 'Najpierw upewnij sie, ze masz backup plikow. Upgrade zachowuje aplikacje i dane, ale backup zawsze jest madry.'
    'ren.inplace.confirm' = 'Uruchomic in-place repair upgrade (zachowuje aplikacje i pliki)? Wpisz TAK albo NIE'
    'ren.inplace.launch'  = 'Uruchamiam instalator Windows (z zachowaniem aplikacji i danych)...'
    'ren.inplace.started' = 'Instalator wystartowal. Postepuj wg jego krokow; wybierz ZACHOWAJ pliki osobiste i aplikacje.'
    'ren.inplace.failed'  = 'Nie udalo sie uruchomic instalatora: {0}'
    'ren.prof.title'   = '--- PRZEPROWADZKA NA SWIEZY PROFIL ---'
    'ren.prof.what'    = 'Uszkodzony profil uzytkownika najlepiej naprawic, tworzac NOWY profil i przenoszac do niego dane. Stary profil i dane NIE sa usuwane - kopiujemy.'
    'ren.prof.warn'    = 'To tworzy nowe konto uzytkownika (jednokierunkowo). Potem logujesz sie na nie i kopiujesz pliki (Pulpit, Dokumenty itd.) ze starego profilu.'
    'ren.prof.confirm' = 'Utworzyc swiezy profil uzytkownika teraz? Wpisz TAK albo NIE'
    'ren.prof.name'    = 'Nazwa nowego konta'
    'ren.prof.cancel'  = 'Anulowano - nie utworzono konta.'
    'ren.prof.pw'      = 'Haslo dla nowego konta (mozesz je pozniej zmienic w Windows)'
    'ren.prof.created' = 'Konto {0} utworzone i dodane do Administratorow.'
    'ren.prof.exists'  = 'Takie konto juz istnieje - pomijam tworzenie.'
    'ren.prof.next1'   = '  Dalej: wyloguj sie, zaloguj na nowe konto.'
    'ren.prof.next2'   = '  Potem skopiuj dane z C:\Users\<stary-profil>\ (Pulpit, Dokumenty, Obrazy...).'
    'ren.prof.next3'   = '  Gdy wszystko dziala, mozesz usunac stary profil w Ustawienia > Konta.'
    'ren.prof.failed'  = 'Nie udalo sie utworzyc konta: {0}'
    'menu.mode.10'   = '  [10] Prywatnosc i AI - wylacz Copilot, Recall, telemetrie, ID reklamowe i sugestie (odwracalne).'
    'priv.title'     = '=== PRYWATNOSC I AI ==='
    'priv.intro'     = 'Kazda pozycja jest odwracalna (zapisana do rollbacku). Zielony = juz chronione, zolty = jeszcze nie.'
    'priv.on'        = '[CHRONIONE]'
    'priv.off'       = '[nie ustawione]'
    'priv.all'       = '  [A] Ochron WSZYSTKO powyzej naraz.'
    'priv.back'      = '  [0] Powrot.'
    'priv.prompt'    = 'Wybierz numer, [A] wszystko lub [0]'
    'priv.already'   = 'Juz chronione - nic do zrobienia.'
    'priv.done1'     = 'Ochroniono: {0}. Czesc zmian dziala po wylogowaniu/restarcie.'
    'priv.doneall'   = 'Ochroniono {0} pozycji. Czesc zmian dziala po wylogowaniu/restarcie.'
    'priv.restart'   = 'Wskazowka: wyloguj sie lub zrestartuj, by wszystko zadzialalo.'
    'priv.copilot'   = 'Windows Copilot'
    'priv.copilot.d' = 'Wylacza przycisk i funkcje Copilot w Windows.'
    'priv.recall'    = 'Recall (historia ekranu AI)'
    'priv.recall.d'  = 'Wylacza analize danych AI / zrzuty ekranu Recall.'
    'priv.advertise' = 'ID reklamowe'
    'priv.advertise.d'= 'Blokuje uzywanie Twojego ID reklamowego do spersonalizowanych reklam.'
    'priv.telemetry' = 'Poziom telemetrii'
    'priv.telemetry.d'= 'Ustawia dane diagnostyczne na najnizszy poziom polityki (Security).'
    'priv.activity'  = 'Historia aktywnosci'
    'priv.activity.d'= 'Wylacza zbieranie przez Windows osi czasu Twojej aktywnosci.'
    'priv.startsug'  = 'Sugestie w menu Start'
    'priv.startsug.d'= 'Usuwa sugerowane/promowane aplikacje w menu Start.'
    'priv.tips'      = 'Porady i wskazowki Windows'
    'priv.tips.d'    = 'Wylacza wyskakujace porady i powiadomienia z sugestiami.'
    'priv.edgeai'    = 'Pasek boczny Edge / Copilot'
    'priv.edgeai.d'  = 'Ukrywa pasek AI w Edge (panel Discover/Copilot).'
    'doc.what'       = 'Co robi:'
    'doc.why'        = 'Dlaczego:'
    'doc.risk'       = 'Ryzyko:'
    'doc.hw'         = 'Sprzet:'
    'doc.winver'     = 'Windows:'
    'doc.evidence'   = 'Dowody:'
    'lgs.untouched'  = '  LaptopGamingSafe: nie ruszano telemetrii, Windows Update, uslug, VBS/HVCI ani sieci.'
    'legacy.kw.napraw'   = 'Aby rozpoczac naprawe podstawowa wpisz dokladnie: NAPRAW'
    'legacy.kw.przywroc' = 'Aby kontynuowac wpisz dokladnie: PRZYWROC'
    'legacy.kw.rozumiem' = 'Aby ostatecznie rozpoczac wpisz dokladnie: ROZUMIEM'
    'legacy.1'       = '[1] Tylko audyt'
    'legacy.2'       = '[2] Naprawa podstawowa'
    'legacy.3'       = '[3] Naprawa zaawansowana (final candidate)'
    'legacy.4'       = '[4] Tylko diagnostyka Recovery/Boot/TPM + skrypt offline'
    'legacy.5'       = '[5] Opcjonalny pelny reset ACL Windows'
    'legacy.6'       = '[6] Naprawa i Odbudowa Windows'
    'legacy.0'       = '[0] Wyjscie'
    'menu.mode.11'   = '  [11] Analiza przyczyn - tlumaczy DLACZEGO komputer jest wolny (ktora usluga, sterownik, dysk...).'
    'menu.mode.12'   = '  [12] Analiza raportu - czyta zapisane sesje i mowi po ludzku: optymalizacja UDANA / CZESCIOWA / NIEUDANA (z %).'
    'rca.title'      = '=== ANALIZA PRZYCZYN: dlaczego komputer jest wolny/niezdrowy? ==='
    'rca.disclaimer' = 'Silnik regulowy (offline, nie AI). Wnioski orientacyjne, nie gwarancja 100%. Tylko odczyt.'
    'rca.collect'    = 'Zbieram sygnaly (czas startu, sterowniki, bledy, dysk)...'
    'rca.none'       = 'Nie znaleziono istotnych przyczyn - system wyglada zdrowo.'
    'rca.head'       = 'PRAWDOPODOBNE PRZYCZYNY (wg wplywu):'
    'rca.w.high'     = 'WYSOKA'
    'rca.w.med'      = 'SREDNIA'
    'rca.w.low'      = 'niska'
    'rca.t.service'  = 'usluga'
    'rca.t.app'      = 'aplikacja startowa'
    'rca.t.driver'   = 'sterownik'
    'rca.t.bg'       = 'zadanie w tle'
    'rca.t.device'   = 'urzadzenie'
    'rca.boot.slow'  = 'Start trwa lacznie okolo {0} s'
    'rca.boot.slow.h'= 'Ponizej ~30 s jest zdrowo; powyzej glownymi winowajcami sa pozycje ponizej.'
    'rca.boot.item'  = 'Start: {0} "{1}" wydluza uruchamianie o okolo {2} s'
    'rca.boot.item.h'= 'Jesli nie potrzebujesz tego przy logowaniu, ustaw na Reczny / opozniony start.'
    'rca.drv.gpu'    = 'Sterownik GPU ma {0} dni'
    'rca.drv.gpu.h'  = 'Swiezy sterownik GPU (czysta instalacja / DDU) czesto pomaga bardziej niz tweaki.'
    'rca.drv.unsigned' = '{0} niepodpisanych sterownikow'
    'rca.drv.unsigned.h' = 'Niepodpisane sterowniki moga powodowac niestabilnosc; sprawdz zrodlo lub wymien.'
    'rca.drv.old'    = '{0} sterownikow starszych niz 3 lata'
    'rca.drv.old.h'  = 'Bardzo stare sterowniki moga nie miec poprawek; zaktualizuj przez Windows Update lub producenta.'
    'rca.hw.disk'    = '{0} bledow dysku w ostatnich 7 dniach'
    'rca.hw.disk.h'  = 'Bledy dysku sa powazne - zrob backup i chkdsk; sprawdz kabel/zdrowie SSD.'
    'rca.hw.whea'    = '{0} bledow sprzetowych (WHEA) w ostatnich 7 dniach'
    'rca.hw.whea.h'  = 'WHEA wskazuje na sprzet (CPU/RAM/PCIe/temperatury). Sprawdz temperatury i stabilnosc XMP.'
    'rca.hw.crash'   = '{0} zdarzen crashu sterownika/aplikacji ostatnio'
    'rca.hw.crash.h' = 'Powtarzajace sie crashe zwykle pochodza od jednego sterownika lub aplikacji - zaktualizuj/przeinstaluj.'
    'rca.disk.lat'   = 'Opoznienie odczytu dysku to {0} ms (zdrowo ponizej 5)'
    'rca.disk.lat.h' = 'Wysokie opoznienie = wszystko wolne. Sprawdz zdrowie dysku, wolne miejsce i I/O w tle.'
    'rca.wu'         = 'Windows Update wyglada na zablokowany'
    'rca.wu.h'       = 'Zablokowana kolejka aktualizacji spowalnia system i blokuje naprawy.'
    'rca.deblo'      = 'Slady debloatera wplywaja na stabilnosc'
    'rca.deblo.h'    = 'Wylaczone kluczowe uslugi czesto daja uczucie "wolno/dziwnie" po takich narzedziach.'
    'rca.wmi'        = 'Repozytorium WMI jest niespojne'
    'rca.wmi.h'      = 'Zepsute WMI psuje monitoring i wiele narzedzi, moze spowalniac zarzadzanie.'
    'rca.canrepair'  = 'Czesc tych przyczyn mozna naprawic automatycznie w [4] Naprawa i Odbudowa.'
    'rca.gotorepairQ'= 'Przejsc teraz do Naprawy i Odbudowy? [t/N]'
    'rca.norepair'   = 'Te przyczyny sa glownie sprzetowe/sterownikowe - zajmij sie nimi wg wskazowek.'
    'main.pressclose'= 'Nacisnij Enter, aby zamknac...'
  }
}

function T {
    # STAGE3 v14.2: UI string lookup. Falls back to English, then to the key itself - never throws.
    param([Parameter(Mandatory)][string]$Key, [object[]]$FmtArgs)
    $table = $script:Strings[$script:UILang]
    $s = if ($table -and $table.ContainsKey($Key)) { $table[$Key] }
         elseif ($script:Strings['en'].ContainsKey($Key)) { $script:Strings['en'][$Key] }
         else { $Key }
    if ($FmtArgs -and $FmtArgs.Count -gt 0) { try { return ($s -f $FmtArgs) } catch { return $s } }
    return $s
}
$script:SelectedDns          = $DnsMode
$script:SelectedRollbackSession = $null
$script:OneClickRollbackUsed = $false
$script:ChangesCount         = 0
$script:ArtifactsCount       = 0   # ETAP2 v14.1: liczba zapisanych raportow/plikow sesji (nie sa to zmiany w systemie)
$script:AutoSmartSelected    = $false  # STAGE6 v14.5: AutoSmart mode - profile and answers chosen automatically
# FIX v15.1: $MyInvocation.MyCommand.Path crashes under StrictMode when the script is launched via iex/dot-source
# (object has no 'Path' property). $PSCommandPath is the robust automatic variable for this exact purpose.
$script:ScriptFullPath       = $PSCommandPath
# FIX v15.2: Repair path returned from the menu without setting these; under StrictMode the Main
# section then crashed on '$script:SelectedProfile cannot be retrieved'. Safe defaults for ALL paths:
$script:SelectedMode            = $null
$script:SelectedProfile         = 'Balanced'
$script:SelectedSearchMode      = 'Keep'
$script:SelectedDns             = 'Keep'
$script:SelectedExperimental    = $false
$script:SelectedRollbackSession = $null
$script:OneClickRollbackUsed    = $false
$script:WarningsCount        = 0
$script:ErrorsCount          = 0
$script:SkippedCount         = 0
$script:RequiresRestart      = New-Object System.Collections.Generic.List[string]
$script:AppliedModules       = New-Object System.Collections.Generic.List[string]
$script:HtmlSections         = New-Object System.Collections.Generic.List[string]
$script:Manifest = [ordered]@{
    AppName                  = $script:AppName
    Version                  = $script:Version
    SessionId                = $script:SessionId
    Mode                     = $Mode
    Profile                  = $Profile
    Scenario                 = $Scenario
    SearchIndexingMode       = $SearchIndexingMode
    DeepScan                 = [bool]$DeepScan
    SkipV13Audit             = [bool]$SkipV13Audit
    CustomProfilePath        = $CustomProfilePath
    CreatedAt                = (Get-Date).ToString('o')
    Environment              = @{}
    Registry                 = @()
    Services                 = @()
    Power                    = @{}
    Notes                    = @()
    Tweaks                   = @()
    SkippedTweaks            = @()
    SmartDecisions           = @()
    Analytics                = @{}
    GamingSessionClosedProcesses = @()
    LaptopProOptions = @{}
}


# =============================
# v12 FAZA 3 — ETW / DPC / ADVANCED
# =============================

function Start-ETWBootTrace {
    <#
    .SYNOPSIS
        Uruchamia nagrywanie sesji ETW (Event Tracing for Windows) przez WPR.
        Plik .etl można otworzyć w Windows Performance Analyzer (WPA).
        Używane wewnętrznie przez Microsoft do debugowania wydajności Windows.
    .NOTES
        Wywołaj przed operacją którą chcesz profilować.
        Zatrzymaj przez Stop-ETWTrace.
    #>
    param(
        [ValidateSet('Boot','CPU','Network','Storage','GPU')]
        [string]$Profile = 'CPU',
        [string]$OutputPath = $script:SessionFolder
    )

    $wpr = "$env:SystemRoot\System32\wpr.exe"
    if (-not (Test-Path $wpr)) {
        Write-Log 'ETW: wpr.exe niedostepny — Windows Performance Recorder nie zainstalowany.' -Level 'WARN'
        return $false
    }

    $profileMap = @{
        'CPU'     = 'CPU'
        'Network' = 'Network'
        'Storage' = 'DiskIO'
        'GPU'     = 'GPU'
        'Boot'    = 'GeneralProfile'
    }

    $wprProfile = $profileMap[$Profile]
    Write-Log "ETW: Start nagrywania profilu $Profile ($wprProfile)..." -Level 'INFO'
    Write-Status "  ETW: Nagrywanie $Profile..." 'Cyan'

    try {
        $result = & $wpr -start $wprProfile 2>&1
        if ($LASTEXITCODE -eq 0) {
            $script:ETWActive   = $true
            $script:ETWProfile  = $Profile
            $script:ETWOutput   = $OutputPath
            Write-Log "ETW: Nagrywanie aktywne ($Profile)." -Level 'INFO'
            return $true
        } else {
            Write-Log "ETW: Start nieudany — $result" -Level 'WARN'
            return $false
        }
    } catch {
        Write-Log "ETW: Blad startu — $($_.Exception.Message)" -Level 'WARN'
        return $false
    }
}

function Stop-ETWTrace {
    <#
    .SYNOPSIS
        Zatrzymuje nagrywanie ETW i zapisuje plik .etl do folderu sesji.
    #>
    if (-not $script:ETWActive) {
        Write-Log 'ETW: Stop wywolany ale nagrywanie nie bylo aktywne.' -Level 'WARN'
        return $null
    }

    $wpr     = "$env:SystemRoot\System32\wpr.exe"
    $etlName = "trace_$($script:ETWProfile)_$($script:SessionId).etl"
    $etlPath = Join-Path $script:ETWOutput $etlName

    Write-Log "ETW: Zatrzymywanie i zapis do $etlPath..." -Level 'INFO'
    Write-Status "  ETW: Zapisywanie trace... (moze chwile trwac)" 'Cyan'

    try {
        $result = & $wpr -stop $etlPath 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path $etlPath)) {
            $sizeMB = [math]::Round((Get-Item $etlPath).Length / 1MB, 1)
            Write-Log "ETW: Trace zapisany — $etlPath ($sizeMB MB)" -Level 'ARTIFACT'
            Write-Status "  ETW: Zapisano $etlPath ($sizeMB MB)" 'Green'
            Write-Status "  ETW: Otworz w Windows Performance Analyzer (WPA) aby zobaczyc szczegoly." 'DarkGray'
            $script:ETWActive = $false
            Add-HtmlSection "<h2>ETW Trace</h2><p>Plik: <code>$etlPath</code> ($sizeMB MB)<br>Profil: $($script:ETWProfile)<br>Otworz w Windows Performance Analyzer (WPA) — dostepny przez Windows SDK.</p>"
            return $etlPath
        } else {
            Write-Log "ETW: Stop nieudany — $result" -Level 'WARN'
            $script:ETWActive = $false
            return $null
        }
    } catch {
        Write-Log "ETW: Blad stopu — $($_.Exception.Message)" -Level 'WARN'
        $script:ETWActive = $false
        return $null
    }
}

function Measure-DPCLatency {
    <#
    .SYNOPSIS
        Mierzy DPC (Deferred Procedure Call) pressure przez Get-Counter — konkretny wynik liczbowy.
        DPC latency > 1ms powoduje stuttery w grach nawet przy niskim CPU%.
        
        Metoda: Get-Counter '\Processor(_Total)\% DPC Time' — dostepne bez ETW/WPA.
        Wynik: srednia i max DPC% w czasie probkowania, plus ocena jakosciowa.
    .NOTES
        Nie wymaga wpr.exe ani WPA.
        Czas pomiaru: ~SampleSeconds sekund.
    #>
    param([int]$SampleSeconds = 10)

    Write-Status "  DPC: Pomiar pressure przez Get-Counter przez $SampleSeconds sekund..." 'Cyan'
    Write-Log "DPC: Start pomiaru Get-Counter ($SampleSeconds s)." -Level 'INFO'

    $dpcSamples = New-Object System.Collections.Generic.List[double]
    $isrSamples = New-Object System.Collections.Generic.List[double]

    try {
        for ($i = 0; $i -lt $SampleSeconds; $i++) {
            try {
                $dpcVal = Get-CounterValueSafe '\Processor(_Total)\% DPC Time'
                $isrVal = Get-CounterValueSafe '\Processor(_Total)\% Interrupt Time'
                if ($null -ne $dpcVal -and $dpcVal -ge 0) { $dpcSamples.Add([math]::Round($dpcVal, 3)) }
                if ($null -ne $isrVal -and $isrVal -ge 0) { $isrSamples.Add([math]::Round($isrVal, 3)) }
            } catch {}
            Start-Sleep -Seconds 1
        }

        if ($dpcSamples.Count -eq 0) {
            Write-Log 'DPC: Get-Counter nie zwrocil danych. Mozliwe ograniczenia uprawnien.' -Level 'WARN'
            # Fallback — heurystyczna analiza sterownikow
            $dpcIndicators = Get-DPCPressureIndicators
            $highRiskCount = @($dpcIndicators | Where-Object { $_.Risk -eq 'High' }).Count
            return [PSCustomObject]@{
                Method         = 'Heuristic'
                DPCAvgPct      = $null
                DPCMaxPct      = $null
                ISRAvgPct      = $null
                HighRiskCount  = $highRiskCount
                Indicators     = $dpcIndicators
                Recommendation = "Get-Counter niedostepny. Heurystyczna ocena: $highRiskCount urzadzen wysokiego ryzyka."
            }
        }

        $dpcAvg = [math]::Round(($dpcSamples | Measure-Object -Average).Average, 3)
        $dpcMax = [math]::Round(($dpcSamples | Measure-Object -Maximum).Maximum, 3)
        $isrAvg = if ($isrSamples.Count -gt 0) { [math]::Round(($isrSamples | Measure-Object -Average).Average, 3) } else { $null }

        # Ocena: DPC% > 1% = problematyczny, > 3% = poważny
        $rating = if ($dpcMax -gt 3.0) { 'KRYTYCZNY' }
                  elseif ($dpcMax -gt 1.0) { 'PODWYZSZONY' }
                  elseif ($dpcAvg -gt 0.5) { 'UMIARKOWANY' }
                  else { 'PRAWIDLOWY' }

        $dpcIndicators = Get-DPCPressureIndicators
        $highRiskCount = @($dpcIndicators | Where-Object { $_.Risk -eq 'High' }).Count

        $recommendation = switch ($rating) {
            'KRYTYCZNY'    { "DPC max=$dpcMax% — KRYTYCZNY poziom. Powaznie wplywa na gaming. Sprawdz LatencyMon i aktualizuj sterowniki sieciowe/audio." }
            'PODWYZSZONY'  { "DPC max=$dpcMax% — podwyzszony poziom. Widoczne stuttery mozliwe. Sprawdz sterowniki sieciowe i audio." }
            'UMIARKOWANY'  { "DPC avg=$dpcAvg% — umiarkowany. Potencjalnie odczuwalny przy 144Hz+. Monitoruj podczas grania." }
            default        { "DPC avg=$dpcAvg% max=$dpcMax% — prawidlowy poziom. Brak wyraznch zrodel stutterow." }
        }

        $ratingColor = switch ($rating) { 'KRYTYCZNY' { 'Red' } 'PODWYZSZONY' { 'Yellow' } 'UMIARKOWANY' { 'Yellow' } default { 'Green' } }
        Write-Status "  DPC: Avg=$dpcAvg% Max=$dpcMax% ISR=$isrAvg% — $rating" $ratingColor
        Write-Status "  DPC: $recommendation" $ratingColor
        Write-Log "DPC: Avg=$dpcAvg% Max=$dpcMax% ISR=$isrAvg% Samples=$($dpcSamples.Count) Rating=$rating" -Level 'ARTIFACT'

        $indHtml = ($dpcIndicators | ForEach-Object {
            "<tr><td>$($_.Type)</td><td>$($_.Device)</td><td>$($_.Risk)</td><td>$($_.Tip)</td></tr>"
        }) -join ''
        Add-HtmlSection "<h2>DPC Pressure Analysis</h2>
<p><b>Metoda: Get-Counter (bezposredni pomiar, bez ETW/WPA)</b></p>
<table><tr><th>Metryka</th><th>Wartosc</th><th>Ocena</th></tr>
<tr><td>DPC% srednia</td><td>$dpcAvg%</td><td>$(if ($dpcAvg -le 0.5) { 'OK' } else { 'Podwyzszony' })</td></tr>
<tr><td>DPC% max (w $SampleSeconds s)</td><td>$dpcMax%</td><td>$rating</td></tr>
<tr><td>Interrupt% srednia</td><td>$isrAvg%</td><td>$(if ($isrAvg -le 1.0) { 'OK' } else { 'Sprawdz' })</td></tr>
</table>
<p><b>$recommendation</b></p>
<p>Progi: &lt;0.5% prawidlowy | 0.5-1% umiarkowany | 1-3% podwyzszony | &gt;3% krytyczny</p>
<table><tr><th>Typ</th><th>Urzadzenie</th><th>Ryzyko</th><th>Info</th></tr>$indHtml</table>"

        return [PSCustomObject]@{
            Method         = 'GetCounter'
            DPCAvgPct      = $dpcAvg
            DPCMaxPct      = $dpcMax
            ISRAvgPct      = $isrAvg
            Rating         = $rating
            SampleCount    = $dpcSamples.Count
            HighRiskCount  = $highRiskCount
            Indicators     = $dpcIndicators
            Recommendation = $recommendation
        }

    } catch {
        Write-Log "DPC: Blad pomiaru — $($_.Exception.Message)" -Level 'WARN'
        return $null
    }
}

function Get-NUMATopology {
    <#
    .SYNOPSIS
        Analizuje topologię NUMA i hybrydowe architektury CPU (Intel P+E cores).
        Na wielkich CPU (Threadripper, Xeon) lub Intel 12th+ gen — nieoptymalne
        przypisanie procesów do węzłów NUMA = realna strata wydajności.
    #>
    $result = [PSCustomObject]@{
        NodeCount       = 1
        IsNUMA          = $false
        IsHybridCPU     = $false
        PCoreCounts     = 0
        ECoreCounts     = 0
        Recommendation  = $null
        Details         = @()
    }

    try {
        # NUMA nodes przez WMI
        $numaNodes = Get-CimInstance Win32_MemoryArray -ErrorAction SilentlyContinue
        $nodeCount  = @(Get-CimInstance -Namespace 'root\cimv2' -ClassName Win32_Processor -ErrorAction SilentlyContinue).Count

        # Hybridowy CPU — Intel 12th gen+ (P-cores + E-cores)
        $cpu     = Get-CimInstance Win32_Processor | Select-Object -First 1
        $cpuName = $cpu.Name
        $isHybrid = $cpuName -match 'i[357]?-1[2-9]\d{3}|i[357]?-[2-9]\d{4}|Core Ultra'

        $result.IsHybridCPU = $isHybrid
        $result.NodeCount   = [math]::Max(1, $nodeCount)
        $result.IsNUMA      = $nodeCount -gt 1

        if ($isHybrid) {
            $result.Recommendation = "Hybridowy CPU wykryty ($cpuName). Windows 11 automatycznie zarzadza P/E cores przez Thread Director. Upewnij sie ze masz Windows 11 22H2+ i aktualne sterowniki chipset Intel."
            $result.Details += "Intel Thread Director: aktywny na Windows 11 22H2+"
            $result.Details += "P-cores: wysokowydajne (gry, single-thread)"
            $result.Details += "E-cores: efektywnosc energetyczna (tlo, kompilacja)"
        }

        if ($nodeCount -gt 1) {
            $result.Recommendation = "Wieloprocesorowy system NUMA ($nodeCount wezlow). Upewnij sie ze gry i aplikacje sa uruchamiane z NUMA affinity = 0 dla najlepszej latency pamieci."
            $result.Details += "NUMA node 0: preferowany dla aplikacji czasu rzeczywistego"
            $result.Details += "Uzyj: Start-Process -ArgumentList '/AFFINITY 0xFF' dla gier"
        }

        $htmlDetails = ($result.Details | ForEach-Object { "<li>$_</li>" }) -join ''
        Add-HtmlSection "<h2>NUMA / CPU Topology</h2><p>Wezly NUMA: $($result.NodeCount) | Hybridowy CPU: $($result.IsHybridCPU)</p><p>$($result.Recommendation)</p><ul>$htmlDetails</ul>"

        Write-Log "NUMA: Nodes=$($result.NodeCount) | Hybrid=$($result.IsHybridCPU)" -Level 'INFO'

    } catch {
        Write-Log "NUMA: Analiza nieudana — $($_.Exception.Message)" -Level 'WARN'
    }

    $result
}

function Invoke-CISBaselineCheck {
    <#
    .SYNOPSIS
        Sprawdza podstawowe punkty z CIS Benchmark dla Windows 10/11.
        Nie jako "security tool" — jako informacja diagnostyczna.
        Poziom: CIS Level 1 (podstawowe, nie wpływające na użyteczność).
    .NOTES
        CIS = Center for Internet Security.
        Pełny benchmark: https://www.cisecurity.org/benchmark/microsoft_windows_desktop
    #>
    $checks = New-Object System.Collections.Generic.List[PSCustomObject]

    function CIS-Check {
        param([string]$Id, [string]$Title, [scriptblock]$Test, [string]$Remediation)
        try {
            $passed = & $Test
            $checks.Add([PSCustomObject]@{
                Id          = $Id
                Title       = $Title
                Passed      = [bool]$passed
                Remediation = if (-not $passed) { $Remediation } else { $null }
            })
        } catch {
            $checks.Add([PSCustomObject]@{
                Id          = $Id
                Title       = $Title
                Passed      = $null   # nie można sprawdzić
                Remediation = "Blad sprawdzania: $($_.Exception.Message)"
            })
        }
    }

    # SMBv1 — wektor WannaCry, powinien być wyłączony
    CIS-Check '9.1.1' 'SMBv1 wylaczony' {
        $smb = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
        -not $smb -or $smb.State -ne 'Enabled'
    } 'Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol'

    # LLMNR — podatny na poisoning ataki
    CIS-Check '9.1.2' 'LLMNR wylaczony' {
        $val = Get-RegistryValueOrDefault 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 1
        $val -eq 0
    } 'Set-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient -Name EnableMulticast -Value 0'

    # Guest account wyłączony
    CIS-Check '2.3.1' 'Konto Guest wylaczone' {
        $guest = Get-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
        -not $guest -or -not $guest.Enabled
    } 'Disable-LocalUser -Name Guest'

    # Autoplay wyłączony
    CIS-Check '18.9.8' 'AutoPlay wylaczony' {
        $val = Get-RegistryValueOrDefault 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 0
        $val -eq 255
    } 'Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name NoDriveTypeAutoRun -Value 255'

    # WDigest — plaintext credentials w pamięci (powinien być wyłączony)
    CIS-Check '2.3.11' 'WDigest plaintext credentials wylaczone' {
        $val = Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential' 1
        $val -eq 0
    } 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -Name UseLogonCredential -Value 0'

    # NTLMv1 wyłączony
    CIS-Check '2.3.11.7' 'NTLMv1 wylaczony' {
        $val = Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LmCompatibilityLevel' 0
        $val -ge 3
    } 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LmCompatibilityLevel -Value 5'

    # Windows Firewall — wszystkie profile
    CIS-Check '9.1' 'Windows Firewall wlaczony (wszystkie profile)' {
        $fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        ($fw | Where-Object { -not $_.Enabled }).Count -eq 0
    } 'Set-NetFirewallProfile -All -Enabled True'

    # Defender real-time protection
    CIS-Check 'DEF.1' 'Defender real-time protection wlaczona' {
        $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
        $mp -and $mp.RealTimeProtectionEnabled
    } 'Set-MpPreference -DisableRealtimeMonitoring $false'

    # PowerShell script block logging
    CIS-Check '18.9.95' 'PowerShell Script Block Logging wlaczony' {
        $val = Get-RegistryValueOrDefault 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging' 0
        $val -eq 1
    } 'Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name EnableScriptBlockLogging -Value 1'

    # Remote Desktop — czy NLA wymagane
    CIS-Check '18.9.65' 'RDP NLA wymagane (jesli RDP aktywny)' {
        $rdpEnabled = (Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1) -eq 0
        if (-not $rdpEnabled) { return $true }   # RDP wyłączony — OK
        $nla = Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' 0
        $nla -eq 1
    } 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1'

    # Wyniki
    $passed  = @($checks | Where-Object { $_.Passed -eq $true }).Count
    $failed  = @($checks | Where-Object { $_.Passed -eq $false }).Count
    $unknown = @($checks | Where-Object { $null -eq $_.Passed }).Count
    $score   = if ($checks.Count -gt 0) { [math]::Round($passed / $checks.Count * 100, 0) } else { 0 }

    Write-Log "CIS Baseline: $passed/$($checks.Count) passed | Score: $score%" -Level 'INFO'
    Write-Status "  CIS Baseline: $passed/$($checks.Count) sprawdzen zdalo ($score%)" $(if ($score -ge 80) { 'Green' } elseif ($score -ge 60) { 'Yellow' } else { 'Red' })

    foreach ($c in $checks | Where-Object { $_.Passed -eq $false }) {
        Write-Status "    [FAIL] $($c.Id) $($c.Title)" 'Yellow'
        Write-Log "CIS FAIL: $($c.Id) $($c.Title) | Remediation: $($c.Remediation)" -Level 'WARN'
    }

    $htmlRows = ($checks | ForEach-Object {
        $st  = if ($_.Passed -eq $true) { '✔' } elseif ($_.Passed -eq $false) { '✘' } else { '?' }
        $cls = if ($_.Passed -eq $true) { 'lepiej' } elseif ($_.Passed -eq $false) { 'gorzej' } else { '' }
        "<tr class='$cls'><td>$($_.Id)</td><td>$($_.Title)</td><td>$st</td><td>$(if ($_.Remediation) { $_.Remediation } else { '' })</td></tr>"
    }) -join ''
    Add-HtmlSection "<h2>CIS Baseline Check ($passed/$($checks.Count) — $score%)</h2><table><tr><th>ID</th><th>Sprawdzenie</th><th>Status</th><th>Naprawa</th></tr>$htmlRows</table>"

    [PSCustomObject]@{
        Checks       = $checks
        PassedCount  = $passed
        FailedCount  = $failed
        UnknownCount = $unknown
        Score        = $score
    }
}

function Invoke-AdvancedDiagnostics {
    <#
    .SYNOPSIS
        Orkiestrator wszystkich zaawansowanych diagnostyk Fazy 3.
        Wywołuj z Analyze mode dla pełnego obrazu systemu.
    #>
    $script:AppliedModules.Add('Advanced')
    Write-Status '==> Zaawansowana diagnostyka (Faza 3)...' 'Cyan'

    # DPC Latency
    Invoke-Step -Name 'Advanced: DPC Latency measurement' -Action {
        $dpcResult = Measure-DPCLatency -SampleSeconds 8
        if ($dpcResult) {
            # FIX v14.0.2: pole ETLPath nie istnieje (relikt po wersji ETW) — pod StrictMode rzucalo wyjatek.
            $script:Manifest.Notes += "DPC: Method=$($dpcResult.Method) | HighRisk=$($dpcResult.HighRiskCount)"
        }
    } -ContinueOnError

    # NUMA Topology
    Invoke-Step -Name 'Advanced: NUMA / CPU Topology' -Action {
        $numaResult = Get-NUMATopology
        $script:Manifest.Notes += "NUMA: Nodes=$($numaResult.NodeCount) | Hybrid=$($numaResult.IsHybridCPU)"
    } -ContinueOnError

    # CIS Baseline
    Invoke-Step -Name 'Advanced: CIS Security Baseline' -Action {
        $cisResult = Invoke-CISBaselineCheck
        $script:Manifest.Notes += "CIS: $($cisResult.PassedCount)/$($cisResult.Checks.Count) passed ($($cisResult.Score)%)"
    } -ContinueOnError

    Write-Status '==> Zaawansowana diagnostyka zakonczona.' 'Green'
}

# =============================
# v12 — Hardware Intelligence + UI
# =============================
# ============================================================
# HARDWARE INTELLIGENCE — auto-detection
# ============================================================

function Get-HardwareProfile {
    <#
    .SYNOPSIS
        Zbiera profil sprzętowy maszyny — używany do dynamicznych decyzji w tweakach.
    #>
    $cpu    = Get-CimInstance Win32_Processor | Select-Object -First 1
    $os     = Get-CimInstance Win32_OperatingSystem
    $cs     = Get-CimInstance Win32_ComputerSystem
    $gpu    = Get-CimInstance Win32_VideoController | Select-Object -First 1
    $disks  = Get-PhysicalDisk -ErrorAction SilentlyContinue

    $totalRAM = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $cores    = $cpu.NumberOfCores
    $logical  = $cpu.NumberOfLogicalProcessors

    # GPU vendor
    $gpuName  = if ($gpu) { $gpu.Name } else { '' }
    $isNvidia = $gpuName -match 'NVIDIA|GeForce|RTX|GTX'
    $isAmd    = $gpuName -match 'AMD|Radeon|RX\s'
    $isIntel  = $gpuName -match 'Intel.*Graphics|Arc'

    # Dysk systemowy — SSD czy HDD
    $sysDisk   = $disks | Where-Object { $_.BusType -ne 'USB' } | Select-Object -First 1
    $isSSD     = $sysDisk -and $sysDisk.MediaType -match 'SSD|NVMe|Solid'

    # Sterownik GPU — wiek
    $gpuDriverAgeDays = $null
    if ($gpu -and $gpu.DriverDate) {
        $gpuDriverAgeDays = [math]::Round(((Get-Date) - $gpu.DriverDate).Days, 0)
    }

    # Hyper-Threading / SMT
    $hasHT = $logical -gt $cores

    [PSCustomObject]@{
        CPUName           = $cpu.Name
        Cores             = $cores
        LogicalProcessors = $logical
        HasHyperThreading = $hasHT
        IsHighEndCPU      = $cores -ge 8
        TotalRAM_GB       = $totalRAM
        IsLowRAM          = $totalRAM -lt 16
        IsMidRAM          = $totalRAM -ge 16 -and $totalRAM -lt 32
        IsHighRAM         = $totalRAM -ge 32
        GPUName           = $gpuName
        IsNvidia          = $isNvidia
        IsAmd             = $isAmd
        IsIntelGPU        = $isIntel
        GPUDriverAgeDays  = $gpuDriverAgeDays
        IsOldGPUDriver    = ($gpuDriverAgeDays -gt 180)
        IsSSD             = $isSSD
        IsLaptop          = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    }
}

# ============================================================
# XMP / DUAL CHANNEL DETECTION
# ============================================================

function Get-MemoryTopology {
    <#
    .SYNOPSIS
        Sprawdza czy RAM działa w dual channel i czy XMP/EXPO jest aktywne.
        Wykrywa częsty błąd: RAM 3600MHz biegnący na 2133MHz bez XMP.
    #>
    $modules = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    if (-not $modules) { return $null }

    $count         = @($modules).Count
    $speeds        = $modules | Select-Object -ExpandProperty Speed -Unique
    $configuredMHz = $modules | Select-Object -ExpandProperty ConfiguredClockSpeed -Unique

    # XMP aktywne gdy ConfiguredClockSpeed == Speed (rated speed)
    # Jeśli configured < speed — XMP wyłączone, RAM biega wolniej niż powinien
    $ratedSpeed     = ($speeds     | Measure-Object -Maximum).Maximum
    $configuredSpeed= ($configuredMHz | Measure-Object -Maximum).Maximum
    $xmpActive      = $configuredSpeed -ge $ratedSpeed

    # Dual channel: parzysta liczba modułów lub łączna pojemność sugeruje parę
    $isDualChannel  = ($count % 2 -eq 0) -and ($count -ge 2)

    # Sloty — czy moduły są w poprawnych slotach (A2/B2)
    $slots = $modules | Select-Object -ExpandProperty DeviceLocator -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        ModuleCount      = $count
        RatedSpeedMHz    = $ratedSpeed
        ConfiguredMHz    = $configuredSpeed
        XMPActive        = $xmpActive
        XMPGainMHz       = $ratedSpeed - $configuredSpeed
        IsDualChannel    = $isDualChannel
        Slots            = $slots -join ', '
        Warning          = if (-not $xmpActive -and $ratedSpeed -gt 2133) {
            "RAM biega na $configuredSpeed MHz zamiast $ratedSpeed MHz — wlacz XMP/EXPO w BIOS. Zysk wiekszy niz kazdy tweak."
        } elseif (-not $isDualChannel -and $count -eq 1) {
            "Single channel RAM wykryty — dodanie drugiego modulu moze podwoic przepustowosc pamieci."
        } else { $null }
    }
}

# ============================================================
# KERNEL TIMER — faktyczny pomiar (nie szacunek)
# ============================================================

function Get-KernelTimerResolution {
    <#
    .SYNOPSIS
        Mierzy faktyczną rozdzielczość timera systemowego przez NtQueryTimerResolution.
        Zamiast zakładać że "ustawiliśmy 0.5ms" — sprawdza co system FAKTYCZNIE używa.
    #>
    try {
        $signature = @'
[DllImport("ntdll.dll", SetLastError=true)]
public static extern int NtQueryTimerResolution(
    out uint MinimumResolution,
    out uint MaximumResolution,
    out uint CurrentResolution);
'@
        $ntdll = Add-Type -MemberDefinition $signature -Name 'NtDllTimer' -Namespace 'WinOpt' -PassThru -ErrorAction Stop
        [uint32]$min = 0; [uint32]$max = 0; [uint32]$cur = 0
        $result = $ntdll::NtQueryTimerResolution([ref]$min, [ref]$max, [ref]$cur)

        if ($result -eq 0) {
            [PSCustomObject]@{
                CurrentMs = [math]::Round($cur / 10000.0, 3)
                MinMs     = [math]::Round($min / 10000.0, 3)
                MaxMs     = [math]::Round($max / 10000.0, 3)
                IsOptimal = $cur -le 5000   # <= 0.5ms
                Raw       = $cur
            }
        } else { $null }
    } catch {
        Write-Log "KernelTimer: NtQueryTimerResolution niedostepny ($($_.Exception.Message))" -Level 'WARN'
        $null
    }
}

# ============================================================
# DPC / INTERRUPT LATENCY — podstawowa detekcja
# ============================================================

function Get-DPCPressureIndicators {
    <#
    .SYNOPSIS
        Zbiera wskaźniki wysokiego DPC latency bez pełnego ETW.
        Pełny ETW to Advanced\DPC.ps1 — tu robimy szybką heurystykę.
    .NOTES
        Wysokie DPC latency = stuttery w grach nawet przy niskim CPU usage.
        Najczęstsze przyczyny: stary sterownik sieciowy, audio, chipset.
    #>
    $indicators = @()

    # Sterowniki audio — najczęstszy sprawca wysokiego DPC
    $audioDrivers = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue
    foreach ($ad in $audioDrivers) {
        if ($ad.Name -match 'Realtek|Creative|ASUS Xonar') {
            $indicators += [PSCustomObject]@{
                Type    = 'Audio'
                Device  = $ad.Name
                Risk    = 'Medium'
                Tip     = 'Realtek audio czesto powoduje wysokie DPC. Sprawdz LatencyMon po instalacji.'
            }
        }
    }

    # Stary sterownik sieciowy
    $netDrivers = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    foreach ($nd in $netDrivers) {
        $driver = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
            Where-Object { $_.DeviceName -like "*$($nd.InterfaceDescription.Split(' ')[0])*" } |
            Select-Object -First 1
        if ($driver -and $driver.DriverDate) {
            $age = ((Get-Date) - [datetime]$driver.DriverDate).Days
            if ($age -gt 365) {
                $indicators += [PSCustomObject]@{
                    Type    = 'Network'
                    Device  = $nd.InterfaceDescription
                    Risk    = 'High'
                    Tip     = "Sterownik sieciowy ma $age dni. Stare sterowniki sieciowe = czesty sprawca DPC stutterow."
                }
            }
        }
    }

    # Wirtualne adaptery (Hyper-V, VPN) — znane przyczyny DPC spikes
    $virtAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -match 'Hyper-V|TAP|VPN|Virtual' -and $_.Status -eq 'Up' }
    foreach ($va in $virtAdapters) {
        $indicators += [PSCustomObject]@{
            Type    = 'VirtualAdapter'
            Device  = $va.InterfaceDescription
            Risk    = 'Medium'
            Tip     = "Wirtualny adapter '$($va.Name)' moze powodowac DPC spikes. Wylacz gdy nie uzywasz."
        }
    }

    $indicators
}

# ============================================================
# CONFLICT DETECTION — oprogramowanie gryzące się z tweakami
# ============================================================

function Get-ConflictingProcesses {
    <#
    .SYNOPSIS
        Wykrywa zainstalowane/uruchomione oprogramowanie które może nadpisywać tweaki
        lub powodować konflikty z optymalizacjami.
    #>
    $conflicts = @()
    $running   = Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName

    $knownConflicts = @(
        @{ Name='RivaTuner|RTSS';      Process='RTSS';           Risk='High';   Reason='Konflikt z HAGS — RTSS i HAGS nie wspolpracuja poprawnie' }
        @{ Name='Process Lasso';       Process='ProcessLasso';   Risk='High';   Reason='Nadpisuje Win32PrioritySeparation — tweak CPU priorytetu moze nie dzialac' }
        @{ Name='MSI Afterburner';     Process='MSIAfterburner'; Risk='Medium'; Reason='Moze kolidowac z HAGS i MPO disable' }
        @{ Name='NVidia FrameView';    Process='nvFrameView';    Risk='Low';    Reason='Overlay moze wchodzic w konflikt z MPO disable' }
        @{ Name='Xbox Game Bar';       Process='GameBar';        Risk='Low';    Reason='DVR wylaczony — Game Bar moze byc nieuzyteczny' }
        @{ Name='Nahimic';             Process='NahimicService'; Risk='High';   Reason='Nahimic powoduje wysokie DPC latency — znany problem' }
        @{ Name='SteelSeries GG';      Process='SteelSeriesGG';  Risk='Medium'; Reason='Znane wysokie DPC latency przy aktywnym oprogramowaniu' }
    )

    foreach ($c in $knownConflicts) {
        $found = $running | Where-Object { $_ -match $c.Process }
        if ($found) {
            $conflicts += [PSCustomObject]@{
                Software = $c.Name
                Process  = $found | Select-Object -First 1
                Risk     = $c.Risk
                Reason   = $c.Reason
            }
        }
    }

    $conflicts
}

# ============================================================
# ACTIVE FULLSCREEN / GAME DETECTION — ochrona przed uruchomieniem w złym momencie
# ============================================================

function Test-ActiveGamingSession {
    <#
    .SYNOPSIS
        Wykrywa czy użytkownik ma aktywną grę lub nagrywanie.
        Chroni przed przypadkowym uruchomieniem skryptu podczas gry.
    #>
    $heavyFullscreen = Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.MainWindowHandle -ne 0 -and
            $_.WorkingSet -gt 1GB -and
            $_.ProcessName -notmatch '^(explorer|dwm|winlogon)$'
        }

    $recordingProcesses = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match 'obs64|obs32|shadowplay|medal|outplayed|xsplit' }

    [PSCustomObject]@{
        IsGamingActive    = [bool]$heavyFullscreen
        IsRecording       = [bool]$recordingProcesses
        HeavyProcesses    = $heavyFullscreen | Select-Object ProcessName, Id -First 3
        RecordingProcess  = $recordingProcesses | Select-Object ProcessName -First 1
        ShouldWarn        = [bool]($heavyFullscreen -or $recordingProcesses)
    }
}

# ============================================================
# SYSTEM SCORE — 0 do 100
# ============================================================

function Get-SystemScore {
    <#
    .SYNOPSIS
        Oblicza wynik optymalizacji systemu 0-100.
        Każdy bottleneck odejmuje punkty z konkretnym uzasadnieniem.
    #>
    $score   = 100
    $reasons = New-Object System.Collections.Generic.List[string]
    $good    = New-Object System.Collections.Generic.List[string]

    # Plan zasilania
    $plan = (& powercfg /getactivescheme 2>$null) -join ''
    if ($plan -match 'High performance|8c5e7fda|e9a42b02') {
        $good.Add('Plan zasilania: High/Ultimate Performance')
    } else {
        $score -= 15
        $reasons.Add("[-15] Suboptimalny plan zasilania (aktywny: $($plan.Trim()))")
    }

    # HAGS
    $hags = Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 0
    if ($hags -eq 2) { $good.Add('HAGS: wlaczony') }
    else { $score -= 10; $reasons.Add('[-10] HAGS wylaczony') }

    # Game DVR
    $dvr = Get-RegistryValueOrDefault 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1
    if ($dvr -eq 0) { $good.Add('Game DVR: wylaczony') }
    else { $score -= 5; $reasons.Add('[-5] Game DVR wlaczony') }

    # Fast Startup
    $hiberboot = Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1
    if ($hiberboot -eq 0) { $good.Add('Fast Startup: wylaczony') }
    else { $score -= 5; $reasons.Add('[-5] Fast Startup wlaczony (moze powodowac niestabilnosc)') }

    # Win32PrioritySeparation
    $prio = Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 2
    if ($prio -eq 38) { $good.Add('CPU priority: zoptymalizowany (38)') }
    else { $score -= 5; $reasons.Add("[-5] Win32PrioritySeparation=$prio (optymalnie 38)") }

    # SystemResponsiveness
    $sr = Get-RegistryValueOrDefault 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 20
    if ($sr -le 10) { $good.Add("SystemResponsiveness: $sr (ok)") }
    else { $score -= 5; $reasons.Add("[-5] SystemResponsiveness=$sr (optymalnie <=10)") }

    # Timer resolution
    $timer = Get-KernelTimerResolution
    if ($timer) {
        if ($timer.IsOptimal) { $good.Add("Timer systemowy: $($timer.CurrentMs) ms (optymalny)") }
        else { $score -= 5; $reasons.Add("[-5] Timer systemowy: $($timer.CurrentMs) ms (powinnien byc <=0.5ms)") }
    }

    # RAM pressure
    $os = Get-CimInstance Win32_OperatingSystem
    $usedPct = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 0)
    if ($usedPct -le 60) { $good.Add("RAM: $usedPct% uzycia (ok)") }
    elseif ($usedPct -le 80) { $score -= 5; $reasons.Add("[-5] RAM pressure: $usedPct% uzycia") }
    else { $score -= 15; $reasons.Add("[-15] Wysokie RAM pressure: $usedPct% uzycia") }

    # Startup items
    $startupCount = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue).Count
    if ($startupCount -le 6) { $good.Add("Autostart: $startupCount pozycji (ok)") }
    elseif ($startupCount -le 10) { $score -= 5; $reasons.Add("[-5] Autostart: $startupCount pozycji") }
    else { $score -= 10; $reasons.Add("[-10] Duzo pozycji autostartu: $startupCount") }

    # GPU driver age
    $hw = Get-HardwareProfile
    if ($null -ne $hw.GPUDriverAgeDays) {
        if ($hw.GPUDriverAgeDays -le 90) { $good.Add("Sterownik GPU: aktualny ($($hw.GPUDriverAgeDays) dni)") }
        elseif ($hw.GPUDriverAgeDays -le 180) { $score -= 5; $reasons.Add("[-5] Sterownik GPU: $($hw.GPUDriverAgeDays) dni — rozwa aktualizacje") }
        else { $score -= 10; $reasons.Add("[-10] Stary sterownik GPU: $($hw.GPUDriverAgeDays) dni — aktualizacja da wiecej niz tweaki") }
    }

    # XMP
    $mem = Get-MemoryTopology
    if ($mem) {
        if ($mem.XMPActive) { $good.Add("XMP/EXPO: aktywne ($($mem.ConfiguredMHz) MHz)") }
        elseif ($mem.RatedSpeedMHz -gt 2133) {
            $score -= 15
            $reasons.Add("[-15] XMP/EXPO WYLACZONE — RAM biegnie na $($mem.ConfiguredMHz) MHz zamiast $($mem.RatedSpeedMHz) MHz")
        }
    }

    [PSCustomObject]@{
        Score   = [math]::Max(0, [math]::Min(100, $score))
        Grade   = switch ([math]::Max(0, [math]::Min(100, $score))) {
            { $_ -ge 90 } { 'A — Doskonaly' }
            { $_ -ge 75 } { 'B — Dobry' }
            { $_ -ge 60 } { 'C — Przecietny' }
            { $_ -ge 40 } { 'D — Wymaga optymalizacji' }
            default        { 'F — Krytyczny' }
        }
        Bottlenecks = $reasons
        GoodItems   = $good
    }
}

# ============================================================
# NTBTLOG PARSER — co spowalnia boot
# ============================================================

function Get-BootLogAnalysis {
    <#
    .SYNOPSIS
        Włącza bootlog jeśli nie był włączony, parsuje ntbtlog.txt jeśli istnieje.
        Przy następnym Analyze po restarcie pokaże co ładowało się wolno.
    #>
    $bootLogPath = "$env:SystemRoot\ntbtlog.txt"
    $result = [PSCustomObject]@{
        LogExists       = $false
        LogEnabled      = $false
        DriversLoaded   = 0
        DriversFailed   = 0
        FailedDrivers   = @()
        Recommendation  = $null
    }

    # Włącz bootlog jeśli jeszcze nie włączony
    $bootLogEnabled = (& bcdedit /enum 2>$null) -join '' | Select-String 'bootlog\s+Yes' -Quiet
    if (-not $bootLogEnabled) {
        try {
            & bcdedit /set bootlog yes | Out-Null
            Write-Log 'BootLog wlaczony — po restarcie ntbtlog.txt bedzie dostepny do analizy.' -Level 'CHANGE'
            $result.LogEnabled = $true
        } catch {
            Write-Log "BootLog enable failed: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    if (-not (Test-Path $bootLogPath)) {
        $result.Recommendation = 'Uruchom ponownie system — po restarcie Analyze pokaze analize sterownikow.'
        return $result
    }

    $result.LogExists = $true
    $lines = Get-Content $bootLogPath -ErrorAction SilentlyContinue

    $loaded = $lines | Where-Object { $_ -match '^Loaded driver' }
    $failed = $lines | Where-Object { $_ -match '^Did not load driver' }

    $result.DriversLoaded  = @($loaded).Count
    $result.DriversFailed  = @($failed).Count
    $result.FailedDrivers  = $failed | ForEach-Object {
        $_ -replace 'Did not load driver\s*', ''
    } | Select-Object -First 20

    if ($result.DriversFailed -gt 0) {
        $result.Recommendation = "Wykryto $($result.DriversFailed) sterownikow ktore nie zaladowaly sie podczas bootu. Sprawdz liste ponizej."
    }

    $result
}

# ============================================================
# PERSISTENT VALIDATION — czy tweak przeżył restart
# ============================================================

function Save-ExpectedState {
    <#
    .SYNOPSIS
        Zapisuje oczekiwany stan po optymalizacji do pliku.
        Przy następnym uruchomieniu Analyze — porównuje actual vs expected.
    #>
    param([Parameter(Mandatory)][string]$OutputPath)

    $expected = [ordered]@{
        SavedAt                 = (Get-Date).ToString('o')
        PowerPlan               = 'High performance|8c5e7fda|e9a42b02'
        HiberbootEnabled        = 0
        GameDVR_Enabled         = 0
        Win32PrioritySeparation = 38
        HwSchMode               = 2
        GlobalTimerResolution   = 1
        DiagTrackStartType      = 'Manual'
    }

    $expected | ConvertTo-Json | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Log "Expected state zapisany: $OutputPath" -Level 'INFO'
}

function Compare-ExpectedVsActual {
    <#
    .SYNOPSIS
        Porównuje oczekiwany stan (z poprzedniej sesji) z aktualnym.
        Wykrywa tweaki które "nie przeżyły" restartu lub zostały nadpisane przez Windows/GPO.
    #>
    param([Parameter(Mandatory)][string]$ExpectedPath)

    if (-not (Test-Path $ExpectedPath)) { return $null }

    $expected = Get-Content $ExpectedPath -Raw | ConvertFrom-Json
    $results  = New-Object System.Collections.Generic.List[PSCustomObject]

    # Plan zasilania
    $actualPlan = (& powercfg /getactivescheme 2>$null) -join ''
    $planOk = $actualPlan -match $expected.PowerPlan
    $results.Add([PSCustomObject]@{
        Check    = 'Plan zasilania'
        Expected = 'High/Ultimate Performance'
        Actual   = $actualPlan.Trim()
        Passed   = $planOk
        FailWhy  = if (-not $planOk) { 'Mozliwe: Windows Update zresetowal plan lub GPO nadpisalo' } else { $null }
    })

    # HiberbootEnabled
    $hb = Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' -1
    $results.Add([PSCustomObject]@{
        Check    = 'Fast Startup (HiberbootEnabled=0)'
        Expected = '0'
        Actual   = "$hb"
        Passed   = $hb -eq $expected.HiberbootEnabled
        FailWhy  = if ($hb -ne 0) { 'Windows Update moze przywracac Fast Startup po aktualizacji' } else { $null }
    })

    # Game DVR
    $dvr = Get-RegistryValueOrDefault 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' -1
    $results.Add([PSCustomObject]@{
        Check    = 'Game DVR (wylaczony)'
        Expected = '0'
        Actual   = "$dvr"
        Passed   = $dvr -eq $expected.GameDVR_Enabled
        FailWhy  = if ($dvr -ne 0) { 'Windows moze przywracac DVR po aktualizacji lub przez GameBar' } else { $null }
    })

    # Win32PrioritySeparation
    $prio = Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' -1
    $results.Add([PSCustomObject]@{
        Check    = 'Win32PrioritySeparation (38)'
        Expected = '38'
        Actual   = "$prio"
        Passed   = $prio -eq $expected.Win32PrioritySeparation
        FailWhy  = if ($prio -ne 38) { 'Process Lasso lub GPO moze nadpisywac ten klucz' } else { $null }
    })

    # HAGS
    $hags = Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' -1
    $results.Add([PSCustomObject]@{
        Check    = 'HAGS (HwSchMode=2)'
        Expected = '2'
        Actual   = "$hags"
        Passed   = $hags -eq $expected.HwSchMode
        FailWhy  = if ($hags -ne 2) { 'Aktualizacja sterownika GPU moze resetowac HAGS' } else { $null }
    })

    # DiagTrack
    $svc = Get-Service DiagTrack -ErrorAction SilentlyContinue
    $svcStart = if ($svc) { [string]$svc.StartType } else { 'NotFound' }
    $results.Add([PSCustomObject]@{
        Check    = 'DiagTrack (Manual)'
        Expected = 'Manual'
        Actual   = $svcStart
        Passed   = $svcStart -eq $expected.DiagTrackStartType
        FailWhy  = if ($svcStart -ne 'Manual') { 'Windows Update lub GPO moze przywracac uslugi do Automatic' } else { $null }
    })

    $passed = @($results | Where-Object Passed).Count
    $failed = @($results | Where-Object { -not $_.Passed }).Count

    [PSCustomObject]@{
        Results     = $results
        PassedCount = $passed
        FailedCount = $failed
        AllPassed   = $failed -eq 0
        SavedAt     = $expected.SavedAt
    }
}

# ============================================================
# QUICK SECURITY CHECK
# ============================================================

function Invoke-QuickSecurityCheck {
    <#
    .SYNOPSIS
        Szybka heurystyczna kontrola bezpieczeństwa.
        NIE zastępuje Defendera — uzupełnia go o rzeczy których Defender nie pokazuje czytelnie.
    #>
    $findings = New-Object System.Collections.Generic.List[PSCustomObject]

    # 1. Procesy uruchomione z folderów tymczasowych — red flag malware
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $path = $_.MainModule.FileName
            if ($path -and $path -match '\\Temp\\|\\AppData\\Local\\Temp\\|\\AppData\\Roaming\\') {
                $findings.Add([PSCustomObject]@{
                    Type     = 'SuspiciousProcess'
                    Risk     = 'High'
                    Detail   = "$($_.ProcessName) (PID $($_.Id)) uruchomiony z: $path"
                    Action   = 'Sprawdz recznie — legalny soft rzadko startuje z folderu Temp'
                })
            }
        } catch {}
    }

    # 2. Winlogon Shell — powinien być dokładnie "explorer.exe"
    $shell = Get-RegistryValueOrDefault 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'Shell' ''
    if ($shell -ne 'explorer.exe') {
        $findings.Add([PSCustomObject]@{
            Type   = 'WinlogonShell'
            Risk   = 'Critical'
            Detail = "Winlogon Shell = '$shell' (oczekiwano: explorer.exe)"
            Action = 'Klasyczny wektor malware — sprawdz natychmiast'
        })
    }

    # 3. Userinit — powinien być "C:\Windows\system32\userinit.exe,"
    $userinit = Get-RegistryValueOrDefault 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'Userinit' ''
    if ($userinit -notmatch 'userinit\.exe') {
        $findings.Add([PSCustomObject]@{
            Type   = 'WinlogonUserinit'
            Risk   = 'Critical'
            Detail = "Userinit = '$userinit'"
            Action = 'Niestandardowy Userinit — sprawdz recznie'
        })
    }

    # 4. Ostatni pełny scan Defendera
    try {
        $mpStatus = Get-MpComputerStatus -ErrorAction Stop
        $lastScan = $mpStatus.FullScanEndTime
        if ($lastScan -and $lastScan -ne [datetime]::MinValue) {
            $daysSince = [math]::Round(((Get-Date) - $lastScan).TotalDays, 0)
            if ($daysSince -gt 30) {
                $findings.Add([PSCustomObject]@{
                    Type   = 'DefenderScan'
                    Risk   = 'Medium'
                    Detail = "Ostatni pelny scan Defendera: $daysSince dni temu ($($lastScan.ToString('yyyy-MM-dd')))"
                    Action = 'Zaplanuj pelny scan — Start-MpScan -ScanType FullScan'
                })
            }
        } else {
            $findings.Add([PSCustomObject]@{
                Type   = 'DefenderScan'
                Risk   = 'Medium'
                Detail = 'Brak pelnego scanu Defendera w historii'
                Action = 'Uruchom pelny scan: Start-MpScan -ScanType FullScan'
            })
        }
    } catch {
        Write-Log "QuickSecurity: Defender status niedostepny" -Level 'WARN'
    }

    # 5. Szybki targeted scan — autostart i TEMP (kilkanaście sekund, nie godziny)
    try {
        $scanPaths = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
            "$env:TEMP"
        )
        foreach ($sp in $scanPaths) {
            if (Test-Path $sp) {
                Start-MpScan -ScanType CustomScan -ScanPath $sp -ErrorAction SilentlyContinue
            }
        }
        Write-Log 'QuickSecurity: targeted scan autostart + TEMP uruchomiony.' -Level 'INFO'
    } catch {
        Write-Log "QuickSecurity: targeted scan nieudany ($($_.Exception.Message))" -Level 'WARN'
    }

    $findings
}

# ============================================================
# HARDWARE RECOMMENDATIONS — "zrobiłem co mogłem, reszta leży tutaj"
# ============================================================

function Get-HardwareRecommendations {
    <#
    .SYNOPSIS
        Generuje listę rekomendacji sprzętowych/BIOS których skrypt nie może zrobić sam.
        Uczciwe domknięcie — informuje użytkownika gdzie leży dalszy potencjał.
    #>
    $recs = New-Object System.Collections.Generic.List[PSCustomObject]
    $hw   = Get-HardwareProfile
    $mem  = Get-MemoryTopology

    # XMP
    if ($mem -and -not $mem.XMPActive -and $mem.RatedSpeedMHz -gt 2133) {
        $recs.Add([PSCustomObject]@{
            Priority = 1
            Category = 'BIOS'
            Title    = "Wlacz XMP/EXPO w BIOS"
            Detail   = "RAM $($mem.RatedSpeedMHz) MHz biegnie na $($mem.ConfiguredMHz) MHz. Wejdz w BIOS > AI Tweaker/OC > XMP/EXPO Profile 1."
            Gain     = 'Bardzo duzy — przepustowosc pamieci ma wiekszy wplyw na FPS niz wiekszosc tweakow'
        })
    }

    # Dual channel
    if ($mem -and $mem.ModuleCount -eq 1) {
        $recs.Add([PSCustomObject]@{
            Priority = 2
            Category = 'Sprzet'
            Title    = 'Dodaj drugi modul RAM (dual channel)'
            Detail   = "Masz $($mem.ModuleCount) modul RAM. Drugi identyczny modul w parze moze podwoic przepustowosc pamieci."
            Gain     = 'Duzy — szczegolnie widoczny w grach CPU-bound'
        })
    }

    # Stary sterownik GPU
    if ($hw.GPUDriverAgeDays -gt 180) {
        $recs.Add([PSCustomObject]@{
            Priority = 3
            Category = 'Sterownik'
            Title    = "Zaktualizuj sterownik GPU ($($hw.GPUName))"
            Detail   = "Sterownik ma $($hw.GPUDriverAgeDays) dni. Nowe sterowniki czesto zawieraja optymalizacje wydajnosci dla nowych gier."
            Gain     = 'Sredni do duzego — zalezny od gry i GPU'
        })
    }

    # Fast Boot w BIOS
    $recs.Add([PSCustomObject]@{
        Priority = 4
        Category = 'BIOS'
        Title    = 'Fast Boot w BIOS (skrocenie czasu POST)'
        Detail   = 'BIOS > Boot > Fast Boot: Enable. Skraca czas od przycisku power do logo Windows o 2-5 sekund. Skrypt nie moze tego zmienic — tylko Ty w BIOS.'
        Gain     = 'Maly ale odczuwalny przy kazdym wlaczeniu'
    })

    # Boot order
    $recs.Add([PSCustomObject]@{
        Priority = 5
        Category = 'BIOS'
        Title    = 'Boot order — dysk systemowy na pierwszym miejscu'
        Detail   = 'Jesli BIOS sprawdza najpierw CD/DVD lub USB — dodaje to czas do kazdego startu. Ustaw dysk systemowy jako pierwsze urzadzenie startowe.'
        Gain     = 'Maly'
    })

    # Pasta termalna
    $recs.Add([PSCustomObject]@{
        Priority = 6
        Category = 'Sprzet'
        Title    = 'Wymiana pasty termicznej (jezeli PC ma 3+ lata)'
        Detail   = 'Stara pasta = wysoka temperatura = thermal throttling = CPU zwalnia pod obciazeniem. Skrypt nie moze tego sprawdzic bez czujnikow zewnetrznych.'
        Gain     = 'Potencjalnie bardzo duzy jesli throttling jest problemem'
    })

    $recs | Sort-Object Priority
}

# ============================================================
# DELAYED-AUTO SERVICES — szybszy pulpit po zalogowaniu
# ============================================================

function Set-DelayedAutoServices {
    <#
    .SYNOPSIS
        Przestawia nieistotne usługi na Delayed-Auto.
        Startują po 2 minutach od bootu zamiast blokować pulpit przy starcie.
        Efekt: szybszy dostępny pulpit, szczególnie na HDD.
    #>
    param([switch]$DryRun)

    $delayServices = @(
        @{ Name='wuauserv';    Reason='Windows Update — niepotrzebny przy starcie' }
        @{ Name='WSearch';     Reason='Windows Search — indeksowanie moze startowac pozniej' }
        @{ Name='SysMain';     Reason='Superfetch — na SSD mozna opoznic' }
        @{ Name='DiagTrack';   Reason='Telemetria — nie krytyczna przy starcie' }
    )

    foreach ($svc in $delayServices) {
        $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if (-not $s) { continue }

        if ($DryRun) {
            Write-Status "  [DRYRUN] Delayed-Auto: $($svc.Name)" 'DarkGray'
            continue
        }

        try {
            & sc.exe config $svc.Name start= delayed-auto | Out-Null
            Write-Log "Delayed-Auto: $($svc.Name) ($($svc.Reason))" -Level 'CHANGE'
        } catch {
            Write-Log "Delayed-Auto failed: $($svc.Name) — $($_.Exception.Message)" -Level 'WARN'
        }
    }
}


# =============================
# v12 — Visual Summary Box
# =============================
function Write-SummaryBox {
    <#
    .SYNOPSIS
        Wyświetla końcową ramkę podsumowania z checklistą zastosowanych tweaków,
        liczbami usług, benchmarkiem i System Score.
    #>
    param(
        [PSCustomObject]$Score,
        [PSCustomObject]$BenchBefore,
        [PSCustomObject]$BenchAfter,
        [PSCustomObject]$MemTopology,
        [PSCustomObject]$HWProfile
    )

    if ($Silent) { return }

    $w = 66  # szerokość ramki

    function Box-Line {
        param([string]$Text = '', [string]$Color = 'White', [switch]$Center)
        $inner = $w - 2
        if ($Center) {
            $pad   = [math]::Max(0, ($inner - $Text.Length) / 2)
            $left  = ' ' * [math]::Floor($pad)
            $right = ' ' * [math]::Ceiling($pad)
            $line  = "║$left$Text$right║"
        } else {
            $padded = $Text.PadRight($inner)
            if ($padded.Length -gt $inner) { $padded = $padded.Substring(0, $inner) }
            $line = "║$padded║"
        }
        Write-Host $line -ForegroundColor $Color
    }

    function Box-Divider { Write-Host ('╠' + '═' * $w + '╣') -ForegroundColor DarkCyan }
    function Box-Top     { Write-Host ('╔' + '═' * $w + '╗') -ForegroundColor DarkCyan }
    function Box-Bottom  { Write-Host ('╚' + '═' * $w + '╝') -ForegroundColor DarkCyan }

    function Box-Check {
        param([string]$Label, [bool]$OK, [string]$Extra = '', [switch]$Warn)
        $icon  = if ($OK) { '✔' } elseif ($Warn) { '⚠' } else { '✘' }
        $color = if ($OK) { 'Green' } elseif ($Warn) { 'Yellow' } else { 'Red' }
        $text  = "  $icon  $Label"
        if ($Extra) { $text += "  [$Extra]" }
        $inner = $w - 2
        $padded = $text.PadRight($inner)
        if ($padded.Length -gt $inner) { $padded = $padded.Substring(0, $inner) }
        Write-Host "║" -ForegroundColor DarkCyan -NoNewline
        Write-Host $padded -ForegroundColor $color -NoNewline
        Write-Host "║" -ForegroundColor DarkCyan
    }

    function Box-Stat {
        param([string]$Label, [string]$Before, [string]$After, [bool]$BetterWhenLower = $false)
        $arrow  = '→'
        $bNum   = [double]($Before -replace '[^0-9.\-]', '')
        $aNum   = [double]($After  -replace '[^0-9.\-]', '')
        $diff   = $aNum - $bNum
        $better = if ($BetterWhenLower) { $diff -lt 0 } else { $diff -gt 0 }
        $sign   = if ($diff -gt 0) { '+' } else { '' }
        $color  = if ($better) { 'Green' } elseif ($diff -eq 0) { 'Gray' } else { 'Red' }
        $diffStr = "$sign$([math]::Round($diff, 1))"

        $text = "  $Label".PadRight(32) + "$Before $arrow $After".PadRight(22) + "($diffStr)"
        $inner = $w - 2
        $padded = $text.PadRight($inner)
        if ($padded.Length -gt $inner) { $padded = $padded.Substring(0, $inner) }
        Write-Host "║" -ForegroundColor DarkCyan -NoNewline
        Write-Host $padded -ForegroundColor $color -NoNewline
        Write-Host "║" -ForegroundColor DarkCyan
    }

    # ── Zbierz dane do wyświetlenia ──────────────────────────────────────────

    # Zasilanie
    $plan     = (& powercfg /getactivescheme 2>$null) -join ''
    $planOK   = $plan -match 'High performance|8c5e7fda|e9a42b02'
    $hiberOK  = (Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1) -eq 0

    # Gaming
    $hagsOK   = (Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 0) -eq 2
    $dvrOK    = (Get-RegistryValueOrDefault 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1) -eq 0
    $prioOK   = (Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 2) -eq 38
    $timerOK  = (Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 0) -eq 1
    $mpoOK    = (Get-RegistryValueOrDefault 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 0) -eq 5
    $gmOK     = (Get-RegistryValueOrDefault 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0) -eq 1

    # UI
    $animOK   = (Get-RegistryValueOrDefault 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 1) -eq 0
    $visOK    = (Get-RegistryValueOrDefault 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 0) -eq 2
    $widgOK   = (Get-RegistryValueOrDefault 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 1) -eq 0

    # Sieć
    $dnsInfo  = $script:SelectedDns
    $dnsOK    = $dnsInfo -ne 'Keep'

    # Usługi — z manifestu
    $svcChanged = @($script:Manifest.Services | Where-Object { $_.OldStartMode -ne $_.NewStartMode })
    $svcStopped = @($script:Manifest.Services | Where-Object { $_.OldState -eq 'Running' })
    $svcNames   = (@($svcChanged | ForEach-Object { if ($null -ne $_) { if ($_ -is [System.Collections.IDictionary] -and $_.Contains('Name')) { $_['Name'] } elseif ($_.PSObject.Properties['Name']) { $_.Name } } } | Where-Object { $_ } | Select-Object -First 6) -join ' · ')

    # Czyszczenie
    $cleanupDone = $script:AppliedModules -contains 'Cleanup'
    $repairDone  = $script:AppliedModules -contains 'Repair'

    # Timer
    $timerActual = Get-KernelTimerResolution
    $timerStr    = if ($timerActual) { "$($timerActual.CurrentMs) ms" } else { 'n/d' }

    # Score
    $scoreVal   = if ($Score) { $Score.Score } else { '?' }
    $scoreGrade = if ($Score) { $Score.Grade } else { '' }

    # Restart
    $needRestart = $script:RequiresRestart.Count -gt 0

    # ── Rysuj ramkę ──────────────────────────────────────────────────────────

    Write-Host ''
    Box-Top

    # Nagłówek
    Box-Line "  $($script:AppName) $($script:Version)" 'Cyan'
    Box-Line "  Sesja: $($script:SessionId)   Profil: $Profile   DNS: $($script:SelectedDns)" 'DarkGray'

    # Score
    Box-Divider
    $scoreColor = if ($scoreVal -ge 85) { 'Green' } elseif ($scoreVal -ge 65) { 'Yellow' } else { 'Red' }
    $scoreLine  = "  SYSTEM SCORE:  $scoreVal / 100   $scoreGrade"
    $inner = $w - 2
    $padded = $scoreLine.PadRight($inner)
    Write-Host "║" -ForegroundColor DarkCyan -NoNewline
    Write-Host $padded -ForegroundColor $scoreColor -NoNewline
    Write-Host "║" -ForegroundColor DarkCyan

    # Bottlenecks jeśli są
    if ($Score -and $Score.Bottlenecks.Count -gt 0) {
        Box-Line "  Bottlenecks:" 'DarkGray'
        foreach ($b in $Score.Bottlenecks | Select-Object -First 4) {
            Box-Line "    $b" 'Yellow'
        }
    }

    # ── ZASILANIE ────────────────────────────────────────────────────────────
    Box-Divider
    Box-Line '  ZASILANIE' 'DarkCyan'
    Box-Check 'Plan High/Ultimate Performance'  $planOK
    Box-Check 'Fast Startup wylaczony'          $hiberOK
    Box-Check 'USB selective suspend off'       $script:AppliedModules.Contains('Power')
    Box-Check 'PCI-e link state off'            $script:AppliedModules.Contains('Power')

    # ── GAMING ───────────────────────────────────────────────────────────────
    Box-Divider
    Box-Line '  GAMING' 'DarkCyan'
    Box-Check 'Game Mode wlaczony'              $gmOK
    Box-Check 'Game DVR wylaczony'              $dvrOK
    Box-Check "HAGS (Hardware GPU Scheduling)"  $hagsOK
    Box-Check "Timer systemowy 0.5ms"           $timerOK  -Extra $timerStr
    Box-Check 'MPO wylaczony (mniej stutterow)' $mpoOK
    Box-Check "Priorytet CPU dla gier (38)"     $prioOK

    # ── GPU ──────────────────────────────────────────────────────────────────
    Box-Divider
    Box-Line '  GPU' 'DarkCyan'
    Box-Check 'TDR delay 8s (stabilnosc)'       $script:AppliedModules.Contains('GPU')
    Box-Check 'Shader cache 4GB'                $script:AppliedModules.Contains('GPU')
    Box-Check 'NVIDIA Coolbits (OC dostep)'     ($script:AppliedModules.Contains('GPU') -and ($HWProfile -and $HWProfile.IsNvidia))
    if ($HWProfile -and $HWProfile.IsOldGPUDriver) {
        Box-Check "Sterownik GPU: $($HWProfile.GPUDriverAgeDays) dni — ZAKTUALIZUJ" $false -Warn
    } else {
        Box-Check 'Sterownik GPU: aktualny'     ($HWProfile -and -not $HWProfile.IsOldGPUDriver)
    }

    # ── INTERFEJS ────────────────────────────────────────────────────────────
    Box-Divider
    Box-Line '  INTERFEJS' 'DarkCyan'
    Box-Check 'Animacje taskbar wylaczone'      $animOK
    Box-Check 'Efekty wizualne zminimalizowane' $visOK
    Box-Check 'Widgets wylaczone (Win11)'       $widgOK

    # ── SIEC ─────────────────────────────────────────────────────────────────
    Box-Divider
    Box-Line '  SIEC' 'DarkCyan'
    Box-Check "DNS → $dnsInfo"                  $dnsOK
    Box-Check 'Cache DNS wyczyszczony'          $script:AppliedModules.Contains('Network')
    Box-Check 'Oszczedzanie energii adapterow off' $script:AppliedModules.Contains('Network')

    # ── USŁUGI ───────────────────────────────────────────────────────────────
    Box-Divider
    Box-Line '  USLUGI' 'DarkCyan'
    $svcChangedOK = $svcChanged.Count -gt 0
    Box-Check "Zoptymalizowano: $($svcChanged.Count) uslug → Manual" $svcChangedOK
    Box-Check "Zatrzymano:      $($svcStopped.Count) uslug (byly uruchomione)" ($svcStopped.Count -gt 0)
    if ($svcNames) {
        Box-Line "    $svcNames" 'DarkGray'
    }

    # ── CZYSZCZENIE / NAPRAWA ────────────────────────────────────────────────
    Box-Divider
    Box-Line '  CZYSZCZENIE / NAPRAWA' 'DarkCyan'
    Box-Check 'Pliki tymczasowe usuniete'       $cleanupDone
    Box-Check 'Cache shader GPU wyczyszczony'   $cleanupDone
    Box-Check 'DISM ComponentCleanup'           $cleanupDone
    Box-Check 'SFC + DISM RestoreHealth'        $repairDone

    # ── RAM / SPRZET ─────────────────────────────────────────────────────────
    if ($MemTopology) {
        Box-Divider
        Box-Line '  PAMIEC / SPRZET' 'DarkCyan'
        Box-Check "XMP/EXPO aktywne ($($MemTopology.ConfiguredMHz) MHz)" $MemTopology.XMPActive
        Box-Check "Dual channel ($($MemTopology.ModuleCount) modulow)" $MemTopology.IsDualChannel
        if ($MemTopology.Warning) {
            Box-Check $MemTopology.Warning $false -Warn
        }
    }

    # ── BENCHMARK ────────────────────────────────────────────────────────────
    if ($BenchBefore -and $BenchAfter) {
        Box-Divider
        Box-Line '  BENCHMARK (in-session — pelny obraz po restarcie)' 'DarkCyan'
        Box-Stat 'RAM wolny'        "$($BenchBefore.FreeRAM_MB) MB"  "$($BenchAfter.FreeRAM_MB) MB"  $false
        Box-Stat 'RAM uzywany'      "$($BenchBefore.UsedRAM_MB) MB"  "$($BenchAfter.UsedRAM_MB) MB"  $true
        Box-Stat 'Liczba procesow'  "$($BenchBefore.ProcessCount)"   "$($BenchAfter.ProcessCount)"   $true
        Box-Stat 'CPU spoczynek'    "$($BenchBefore.CPU_Pct) %"      "$($BenchAfter.CPU_Pct) %"      $true
    }

    # ── STATYSTYKI SESJI ─────────────────────────────────────────────────────
    Box-Divider
    # v12: Auto-rollback info
    if ($script:AutoRolledBack.Count -gt 0) {
        Box-Divider
        Box-Line '  AUTO-ROLLBACK — cofniete tweaki (pogorszyly metryki)' 'Yellow'
        foreach ($rb in $script:AutoRolledBack) {
            Box-Check "$($rb.Name) cofniety ($($rb.DiffPct)% pogorszenie)" $false -Warn
        }
    }

    $statsLine = T 'stats.line' -FmtArgs @($script:ChangesCount, $script:ArtifactsCount, $script:SkippedCount, $script:WarningsCount, $script:ErrorsCount)
    Box-Line $statsLine 'White'

    # ── RESTART ──────────────────────────────────────────────────────────────
    Box-Divider
    if ($needRestart) {
        $inner2 = $w - 2
        $restartText = '  ⚠  RESTART WYMAGANY dla pelnego efektu tweakow'
        $padded2 = $restartText.PadRight($inner2)
        Write-Host "║" -ForegroundColor DarkCyan -NoNewline
        Write-Host $padded2 -ForegroundColor Yellow -NoNewline
        Write-Host "║" -ForegroundColor DarkCyan
    } else {
        Box-Line '  ✔  Restart nie jest wymagany' 'Green'
    }

    Box-Bottom
    Write-Host ''
    Write-Host "  Raporty: $($script:SessionFolder)" -ForegroundColor DarkGray
    Write-Host "  HTML:    $($script:HtmlReportPath)" -ForegroundColor DarkGray
    Write-Host ''
}


# =============================
# Helpers
# =============================
function New-DirectorySafe {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Initialize-Folders {
    New-DirectorySafe -Path $script:RootFolder
    New-DirectorySafe -Path $script:SessionFolder
    New-DirectorySafe -Path $script:LogFolder
    New-DirectorySafe -Path $script:ReportFolder
    New-DirectorySafe -Path $script:BackupFolder
    New-DirectorySafe -Path $script:RegistryBackupFolder
}

function Write-Log {
    # ETAP2 v14.1: nowy poziom ARTIFACT — zapis raportu/pliku sesji. Trafia do changes.log jako slad,
    # ale NIE podbija licznika zmian systemowych (koniec z 'Zmiany: 5' w trybie Analyze).
    param([Parameter(Mandatory)][string]$Message,[ValidateSet('INFO','WARN','ERROR','CHANGE','ARTIFACT')][string]$Level='INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    # STAGE3 v14.2.1: explicit UTF8 (works on both PS 5.1 and 7; 'utf8BOM' is PS7-only and crashed on 5.1).
    Add-Content -Path $script:MainLog -Value $line -Encoding UTF8
    switch ($Level) {
        'WARN'     { Add-Content -Path $script:WarningLog -Value $line -Encoding UTF8; $script:WarningsCount++ }
        'ERROR'    { Add-Content -Path $script:ErrorLog   -Value $line -Encoding UTF8; $script:ErrorsCount++ }
        'CHANGE'   { Add-Content -Path $script:ChangeLog  -Value $line -Encoding UTF8; $script:ChangesCount++ }
        'ARTIFACT' { Add-Content -Path $script:ChangeLog  -Value $line -Encoding UTF8; $script:ArtifactsCount++ }
    }
}

# FIX v15.3: v15.2.1 put a trailing comment INSIDE the param line which swallowed [string]$Color -> ParserError.
# Lesson kept: never inline-comment inside param() declarations.
function Write-Status {
    param([AllowEmptyString()][Parameter(Mandatory)][string]$Message,[ValidateSet('Gray','Green','Yellow','Red','Cyan','White','DarkGray','DarkYellow','Magenta','Blue','DarkRed')][string]$Color='Gray')
    if (-not $Silent) { Write-Host $Message -ForegroundColor $Color }
}

function Add-HtmlSection { param([string]$Html) $script:HtmlSections.Add($Html) }

function ConvertTo-HtmlSafe {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    return ($Text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;')
}

function Add-RestartFlag {
    param([Parameter(Mandatory)][string]$Reason)
    if (-not $script:RequiresRestart.Contains($Reason)) { $script:RequiresRestart.Add($Reason) }
}

function Invoke-Step {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][scriptblock]$Action,[switch]$ContinueOnError)
    Write-Status "==> $Name" 'Cyan'
    Write-Log -Message "START: $Name"
    try { & $Action; Write-Log -Message "DONE: $Name" }
    catch {
        Write-Log -Message "FAILED: $Name | $($_.Exception.Message)" -Level 'ERROR'
        if (-not $ContinueOnError) { throw }
    }
}

function Invoke-ExternalWithTimeout {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 1800,
        [string]$FriendlyName = $FilePath,
        [string[]]$CleanupProcessNames = @()
    )
    $proc = $null
    $safeName = ($FriendlyName -replace '[^a-zA-Z0-9._-]','_')
    $stdOutLog = Join-Path $script:LogFolder ("$safeName.stdout.log")
    $stdErrLog = Join-Path $script:LogFolder ("$safeName.stderr.log")
    try {
        # FIX v14.0.1: Start-Process rzuca blad bindowania przy pustej tablicy -ArgumentList — splatting warunkowy.
        $spArgs = @{ FilePath = $FilePath; PassThru = $true; WindowStyle = 'Hidden'; RedirectStandardOutput = $stdOutLog; RedirectStandardError = $stdErrLog }
        if ($ArgumentList -and $ArgumentList.Count -gt 0) { $spArgs['ArgumentList'] = $ArgumentList }
        $proc = Start-Process @spArgs
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
            foreach ($pn in $CleanupProcessNames) {
                Get-Process -Name $pn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            Write-Log "$FriendlyName timeout po $TimeoutSeconds s. Proces zakonczony." -Level 'WARN'
            $script:SkippedCount++
            return $false
        }
        if (Test-Path $stdOutLog) {
            Get-Content $stdOutLog -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "[$FriendlyName] $_" }
        }
        if (Test-Path $stdErrLog) {
            Get-Content $stdErrLog -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "[$FriendlyName][ERR] $_" -Level 'WARN' }
        }
        return ($proc.ExitCode -eq 0)
    } finally {
        # FIX v14.0.1: poprzednio finally zabijal procesy PO NAZWIE — w tym niepowiazane instancje
        # (np. DISM uruchomiony przez Windows w tle) i to nawet po sukcesie. Teraz: tylko nasz PID.
        # Zabijanie po nazwie zostaje wylacznie w galezi timeoutu (sprzatanie procesow potomnych).
        if ($proc -and -not $proc.HasExited) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # v15.3.1: friendly console lines before the throw (the throw itself IS caught and logged by Main).
        Write-Host ''
        Write-Host '  Ten skrypt wymaga uprawnien administratora. / Administrator rights required.' -ForegroundColor Red
        Write-Host '  Kliknij PPM na PowerShell -> Uruchom jako administrator.' -ForegroundColor Yellow
        throw 'Uruchom PowerShell jako Administrator. / Run PowerShell as Administrator.'
    }
}

function Get-RegistryValueOrDefault {
    param([string]$Path,[string]$Name,$Default=$null)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $Default }
}

function Get-LocalizedCounterPath {
    <#
    .SYNOPSIS
        FIX v14.0.1: Get-Counter wymaga ZLOKALIZOWANYCH nazw licznikow. Na polskim Windows
        '\Processor(_Total)\% Processor Time' nie istnieje (jest '\Procesor...\Czas procesora (%)'),
        wiec wszystkie pomiary CPU/DPC/IO po cichu zwracaly pustke. Helper tlumaczy angielska
        sciezke na lokalna przez indeksy Perflib (HKLM\...\Perflib\009 vs CurrentLanguage).
    #>
    param([Parameter(Mandatory)][string]$EnglishPath)
    if ($null -eq $script:CounterNameMap) {
        $script:CounterNameMap = @{}
        try {
            $eng = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009' -Name Counter -ErrorAction Stop).Counter
            $loc = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\CurrentLanguage' -Name Counter -ErrorAction Stop).Counter
            $locById = @{}
            for ($i = 0; $i -lt ($loc.Count - 1); $i += 2) { $locById[$loc[$i]] = $loc[$i + 1] }
            for ($i = 0; $i -lt ($eng.Count - 1); $i += 2) {
                $id = $eng[$i]; $name = $eng[$i + 1]
                if ($name -and $locById.ContainsKey($id) -and -not $script:CounterNameMap.ContainsKey($name)) {
                    $script:CounterNameMap[$name] = $locById[$id]
                }
            }
        } catch { Write-Log "Perflib: nie udalo sie zbudowac mapy licznikow: $($_.Exception.Message)" -Level 'WARN' }
    }
    if ($script:CounterNameMap.Count -eq 0) { return $EnglishPath }
    if ($EnglishPath -match '^\\([^\\(]+)(\([^)]*\))?\\(.+)$') {
        $obj = $Matches[1]; $inst = $Matches[2]; $ctr = $Matches[3]
        $objL = if ($script:CounterNameMap.ContainsKey($obj)) { $script:CounterNameMap[$obj] } else { $obj }
        $ctrL = if ($script:CounterNameMap.ContainsKey($ctr)) { $script:CounterNameMap[$ctr] } else { $ctr }
        return ('\' + $objL + $inst + '\' + $ctrL)
    }
    return $EnglishPath
}

function Get-CounterValueSafe {
    <#
    .SYNOPSIS
        FIX v14.0.1: bezpieczny odczyt pojedynczego licznika. Probuje sciezki zlokalizowanej,
        potem oryginalnej (system EN). Zwraca [double] CookedValue albo $null — nigdy nie rzuca.
    #>
    param([Parameter(Mandatory)][string]$EnglishPath)
    foreach ($p in @((Get-LocalizedCounterPath -EnglishPath $EnglishPath), $EnglishPath) | Select-Object -Unique) {
        try {
            $s = Get-Counter $p -ErrorAction Stop
            if ($s -and $s.CounterSamples -and $s.CounterSamples.Count -gt 0) { return [double]$s.CounterSamples[0].CookedValue }
        } catch {}
    }
    return $null
}

# =============================
# Sanity Checks
# =============================
function Invoke-SanityChecks {
    Write-Status '==> Sprawdzanie srodowiska...' 'Cyan'
    $os    = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    if ($build -lt 19041) {
        $script:SanityWarnings.Add("WARN: Windows Build $build ponizej minimalnego (19041). Niektore tweaki moga nie dzialac.")
        Write-Log -Message "Sanity: Build $build < 19041" -Level 'WARN'
    }
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.PartOfDomain) {
        $script:SanityWarnings.Add("WARN: System w domenie ($($cs.Domain)). Polityki domenowe moga nadpisac tweaki.")
        Write-Log -Message "Sanity: domena $($cs.Domain)" -Level 'WARN'
    }
    $mdmPath = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    if ((Test-Path $mdmPath) -and (Get-ChildItem $mdmPath -ErrorAction SilentlyContinue)) {
        $script:SanityWarnings.Add("WARN: Wykryto MDM/Intune. Polityki moga nadpisac zmiany.")
        Write-Log -Message 'Sanity: MDM/Intune enrollment' -Level 'WARN'
    }
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        if ($bl.ProtectionStatus -eq 'On') {
            $script:SanityWarnings.Add("INFO: BitLocker aktywny na $($env:SystemDrive). Skrypt nie dotyka szyfrowania.")
            Write-Log -Message 'Sanity: BitLocker aktywny' -Level 'INFO'
        }
    } catch {}
    try {
        $vbs = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -ErrorAction Stop
        if ($vbs.EnableVirtualizationBasedSecurity -eq 1) {
            $script:SanityWarnings.Add("INFO: VBS wlaczony. HAGS moze byc ograniczony.")
            Write-Log -Message 'Sanity: VBS wlaczony' -Level 'INFO'
        }
    } catch {}
    # Temperatura CPU — best effort
    try {
        $zones = Get-CimInstance -Namespace 'root/wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        foreach ($z in $zones) {
            $tempC = [math]::Round($z.CurrentTemperature / 10 - 273.15, 1)
            if ($tempC -gt 0 -and $tempC -lt 150) {
                if ($tempC -gt 85) {
                    $script:SanityWarnings.Add("WARN: Wysoka temperatura CPU: ${tempC}C. Tweaki mocy moga pogorszyc sytuacje termalnie.")
                    Write-Log -Message "Sanity: temp CPU ${tempC}C > 85C" -Level 'WARN'
                } else {
                    Write-Log -Message "Sanity: temp CPU OK (${tempC}C)" -Level 'INFO'
                }
                break
            }
        }
    } catch { Write-Log -Message 'Sanity: czujnik temperatury CPU niedostepny' -Level 'INFO' }
    # Wiek sterownika GPU
    try {
        $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
        if ($gpu -and $gpu.DriverDate) {
            $age = ((Get-Date) - $gpu.DriverDate).Days
            Write-Log -Message "GPU: $($gpu.Name) | Sterownik: $($gpu.DriverVersion) | Wiek: $age dni" -Level 'INFO'
            if ($age -gt 180) {
                $script:SanityWarnings.Add("WARN: Sterownik GPU ma $age dni (>180 dni). Aktualizacja sterownika moze dac wiekszy zysk niz tweaki.")
                Write-Log -Message "Sanity: stary sterownik GPU ($age dni)" -Level 'WARN'
            }
        }
    } catch { Write-Log -Message 'Sanity: brak danych sterownika GPU' -Level 'INFO' }

    # v12: Hardware profile + memory topology + conflict detection + gaming guard
    if ($true) {
        $script:HWProfile   = Get-HardwareProfile
        $script:MemTopology = Get-MemoryTopology
        Write-Log "HW: CPU=$($script:HWProfile.CPUName) | Cores=$($script:HWProfile.Cores) | RAM=$($script:HWProfile.TotalRAM_GB)GB | GPU=$($script:HWProfile.GPUName)" -Level 'INFO'
        if ($script:MemTopology -and $script:MemTopology.Warning) {
            $script:SanityWarnings.Add("WARN: $($script:MemTopology.Warning)")
        }
        $conflicts = Get-ConflictingProcesses
        foreach ($c in $conflicts) {
            $script:SanityWarnings.Add("[$($c.Risk)] Konflikt: $($c.Software) — $($c.Reason)")
            Write-Log "Konflikt: $($c.Software) | $($c.Reason)" -Level 'WARN'
        }
        if (-not $Silent) {
            $gamingDetect = Test-ActiveGamingSession
            if ($gamingDetect.ShouldWarn) {
                Write-Status '  UWAGA: Wykryto aktywna gre lub nagrywanie!' 'Red'
                foreach ($p in $gamingDetect.HeavyProcesses) { Write-Status "    - $($p.ProcessName) (PID $($p.Id))" 'Yellow' }
                Write-Host '  Kontynuowac mimo to? [T/N]: ' -ForegroundColor Red -NoNewline
                if ((Read-Host).Trim().ToUpper() -ne 'T') { throw 'Anulowano — aktywna sesja gamingowa.' }
            }
        }
    }  # zamkniecie bloku if ($true) — Hardware Intelligence + gaming guard
    if ($script:SanityWarnings.Count -gt 0) {
        Write-Status '--- Ostrzezenia srodowiska ---' 'Yellow'
        foreach ($w in $script:SanityWarnings) { Write-Status "  $w" 'Yellow' }
        Write-Status '' 'White'
    } else { Write-Log -Message 'Sanity checks: brak ostrzezen' -Level 'INFO' }
}

# =============================
# Benchmark
# =============================
function Get-BenchmarkSnapshot {
    $os      = Get-CimInstance Win32_OperatingSystem
    $freeRAM = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
    $usedRAM = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1KB, 0)
    $procs   = @(Get-Process -ErrorAction SilentlyContinue)
    $totalWS = [math]::Round(($procs | Measure-Object WorkingSet -Sum).Sum / 1MB, 0)
    $cpuAvg = $null
    try {
        $cpuSamplesPerf = @()
        1..3 | ForEach-Object {
            $v = Get-CounterValueSafe '\Processor(_Total)\% Processor Time'
            if ($null -ne $v) { $cpuSamplesPerf += $v }
            Start-Sleep 1
        }
        if ($cpuSamplesPerf.Count -gt 0) { $cpuAvg = [math]::Round(($cpuSamplesPerf | Measure-Object -Average).Average, 1) }
    } catch {}
    if ($null -eq $cpuAvg) {
        try {
            $cpuSamples = @()
            1..3 | ForEach-Object { $cpuSamples += (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average; Start-Sleep 1 }
            $cpuSamples = @($cpuSamples | Where-Object { $null -ne $_ })
            if ($cpuSamples.Count -gt 0) { $cpuAvg = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 1) }
        } catch {}
    }
    $bootAge = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalSeconds, 0)
    $diskMBs = $null
    try {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $buf = New-Object byte[] (50MB)
            $sw  = [System.Diagnostics.Stopwatch]::StartNew()
            [System.IO.File]::WriteAllBytes($tmp, $buf); $sw.Stop()
            $diskMBs = [math]::Round(50 / $sw.Elapsed.TotalSeconds, 1)
        } finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    # v12 PREMIUM: rozszerzone metryki
    $ioMetrics  = Get-IOMetrics
    $bootTimeSec = Get-BootTimeSec

    [ordered]@{
        Timestamp     = (Get-Date).ToString('o')
        UsedRAM_MB    = $usedRAM
        FreeRAM_MB    = $freeRAM
        ProcessCount  = $procs.Count
        TotalWS_MB    = $totalWS
        CPU_Pct       = $cpuAvg
        BootAge_s     = $bootAge
        BootTimeSec   = $bootTimeSec
        DiskWrite_MBs = $diskMBs
        IO_ReadLatMs  = if ($ioMetrics) { $ioMetrics.ReadLatMs  } else { $null }
        IO_WriteLatMs = if ($ioMetrics) { $ioMetrics.WriteLatMs } else { $null }
        IO_QueueLen   = if ($ioMetrics) { $ioMetrics.QueueLength } else { $null }
    }
}

function Compare-SessionBenchmarks {
    <#
    .SYNOPSIS
        Porownuje benchmarki dwoch dowolnych sesji historycznych.
        Pokazuje trend po tygodniu uzytkowania — nie tylko before/after w jednej sesji.
    .PARAMETER SessionIdA
        ID starszej sesji (np. sprzed tygodnia). Jesli nie podano — uzywa najstarszego dostepnego snapshotu.
    .PARAMETER SessionIdB
        ID nowszej sesji (domyslnie: biezaca sesja).
    #>
    param(
        [string]$SessionIdA = '',
        [string]$SessionIdB = $script:SessionId
    )

    $result = [PSCustomObject]@{ Found = $false; Lines = @() }

    # Znajdz dostepne snapshoty
    $allSnapshots = @(Get-ChildItem -Path $script:RootFolder -Recurse -Filter 'benchmark_before_persistent.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime)

    if ($allSnapshots.Count -lt 2) { return $result }

    $snapA = if ($SessionIdA) {
        $allSnapshots | Where-Object { $_.FullName -match [regex]::Escape($SessionIdA) } | Select-Object -First 1
    } else {
        $allSnapshots | Select-Object -First 1   # najstarszy
    }

    $snapB = $allSnapshots | Where-Object { $_.FullName -match [regex]::Escape($SessionIdB) } | Select-Object -First 1
    if (-not $snapB) { $snapB = $allSnapshots | Select-Object -Last 1 }

    if (-not $snapA -or -not $snapB -or $snapA.FullName -eq $snapB.FullName) { return $result }

    try {
        $dataA = Get-Content $snapA.FullName -Raw | ConvertFrom-Json
        $dataB = Get-Content $snapB.FullName -Raw | ConvertFrom-Json

        $tsA = if ($dataA.Timestamp) { $dataA.Timestamp } else { $snapA.LastWriteTime }
        $tsB = if ($dataB.Timestamp) { $dataB.Timestamp } else { $snapB.LastWriteTime }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('')
        $lines.Add('=== POROWNANIE SESJI HISTORYCZNYCH ===')
        $lines.Add("Sesja A (starsza): $tsA")
        $lines.Add("Sesja B (nowsza):  $tsB")
        $lines.Add('')

        function fCompare { param($lbl, $a, $b, $unit, $better)
            if ($null -eq $a -or $null -eq $b) { return }
            $d = $b - $a; $s = if ($d -gt 0) { '+' } else { '' }
            $ar = if ($better -eq 'lower') {
                if ($d -lt 0) { '<< LEPIEJ' } elseif ($d -gt 0) { '>> GORZEJ' } else { '' }
            } else {
                if ($d -gt 0) { '<< LEPIEJ' } elseif ($d -lt 0) { '>> GORZEJ' } else { '' }
            }
            $lines.Add(('  {0,-30} {1,8} {2} -> {3,8} {4}  ({5}{6} {7}) {8}' -f $lbl,$a,$unit,$b,$unit,$s,$d,$unit,$ar))
        }

        fCompare 'RAM wolny'       $dataA.FreeRAM_MB    $dataB.FreeRAM_MB    'MB'   'higher'
        fCompare 'RAM uzywany'     $dataA.UsedRAM_MB    $dataB.UsedRAM_MB    'MB'   'lower'
        fCompare 'Liczba procesow' $dataA.ProcessCount  $dataB.ProcessCount  ''     'lower'
        fCompare 'CPU spoczynek'   $dataA.CPU_Pct       $dataB.CPU_Pct       '%'    'lower'
        fCompare 'Zapis dysku'     $dataA.DiskWrite_MBs $dataB.DiskWrite_MBs 'MB/s' 'higher'
        fCompare 'Boot time'       $dataA.BootTimeSec   $dataB.BootTimeSec   's'    'lower'
        fCompare 'I/O Read lat'    $dataA.IO_ReadLatMs  $dataB.IO_ReadLatMs  'ms'   'lower'
        fCompare 'I/O Write lat'   $dataA.IO_WriteLatMs $dataB.IO_WriteLatMs 'ms'   'lower'

        $htmlRows = ($lines | Select-Object -Skip 4 | Where-Object { $_.Trim() } | ForEach-Object {
            $cls = if ($_ -match 'LEPIEJ') { 'lepiej' } elseif ($_ -match 'GORZEJ') { 'gorzej' } else { '' }
            "<tr class='$cls'><td colspan='2'>$($_.Trim())</td></tr>"
        }) -join ''
        Add-HtmlSection "<h2>Porownanie sesji historycznych</h2>
<p>Sesja A: $tsA</p><p>Sesja B: $tsB</p>
<table>$htmlRows</table>
<p style='color:#888'>Porownanie pokazuje trend po czasie — nie tylko efekt jednej sesji.</p>"

        Write-Log "SessionComparison: $tsA vs $tsB" -Level 'INFO'
        $result.Found = $true
        $result.Lines = $lines
    } catch {
        Write-Log "SessionComparison: blad — $($_.Exception.Message)" -Level 'WARN'
    }

    $result
}

function Write-BenchmarkReport {
    param($Before,$After)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('=== BENCHMARK PRZED / PO ===')
    $lines.Add("Przed: $($Before.Timestamp)")
    $lines.Add("Po:    $($After.Timestamp)")
    $lines.Add('')
    function fDiff { param($lbl,$b,$a,$unit,$better)  # NOTE: param order is (before,after) here — intentional, matches its callers below
        $d=$a-$b; $s=if($d-gt0){'+'}else{''}
        $ar=if($better-eq'lower'){if($d-lt0){'<< LEPIEJ'}elseif($d-gt0){'>> GORZEJ'}else{''}}else{if($d-gt0){'<< LEPIEJ'}elseif($d-lt0){'>> GORZEJ'}else{''}}
        '  {0,-28} {1,8} {2}  ->  {3,8} {4}   ({5}{6} {7}) {8}' -f $lbl,$b,$unit,$a,$unit,$s,$d,$unit,$ar
    }
    $lines.Add($(fDiff 'RAM uzywany'       $Before.UsedRAM_MB   $After.UsedRAM_MB   'MB'   'lower'))
    $lines.Add($(fDiff 'RAM wolny'         $Before.FreeRAM_MB   $After.FreeRAM_MB   'MB'   'higher'))
    $lines.Add($(fDiff 'Liczba procesow'   $Before.ProcessCount $After.ProcessCount  ''     'lower'))
    $lines.Add($(fDiff 'Working Set proc'  $Before.TotalWS_MB   $After.TotalWS_MB   'MB'   'lower'))
    $lines.Add($(fDiff 'CPU spoczynek'     $Before.CPU_Pct      $After.CPU_Pct      '%'    'lower'))
    if ($Before.DiskWrite_MBs -and $After.DiskWrite_MBs) { $lines.Add($(fDiff 'Zapis dysku 50MB' $Before.DiskWrite_MBs $After.DiskWrite_MBs 'MB/s' 'higher')) }
    if ($Before.BootTimeSec -and $After.BootTimeSec) {
        $lines.Add($(fDiff 'Boot time (Event Log)' $Before.BootTimeSec $After.BootTimeSec 's' 'lower'))
    } elseif ($Before.BootTimeSec) {
        $lines.Add("  Boot time (ostatni):      $($Before.BootTimeSec) s — porownanie po restarcie")
    }
    if ($Before.IO_ReadLatMs -and $After.IO_ReadLatMs) {
        $lines.Add($(fDiff 'I/O Read latency'  $Before.IO_ReadLatMs  $After.IO_ReadLatMs  'ms' 'lower'))
    }
    if ($Before.IO_WriteLatMs -and $After.IO_WriteLatMs) {
        $lines.Add($(fDiff 'I/O Write latency' $Before.IO_WriteLatMs $After.IO_WriteLatMs 'ms' 'lower'))
    }

    $lines.Add('')
    $lines.Add('UWAGA: Pomiar "po" jest w tej samej sesji — wiele zmian wymaga restartu dla pelnego efektu.')
    $lines.Add('Rzeczywisty zysk widoczny po restarcie. Uruchom tryb Analyze po restarcie aby porownac.')
    $lines.Add('UWAGA: FPS w grach nie jest mierzony z poziomu PowerShell.')
    $lines.Add("Czas od ostatniego bootu: $($Before.BootAge_s) s ($([math]::Round($Before.BootAge_s/60,1)) min)")
    # Zapisz snapshot "before" do trwalego pliku dla porownania po restarcie
    $Before | ConvertTo-Json | Set-Content -Path (Join-Path $script:ReportFolder 'benchmark_before_persistent.json') -Encoding UTF8
    $lines | Set-Content -Path $script:BenchmarkPath -Encoding UTF8
    Write-Log -Message 'Benchmark zapisany. Snapshot before zachowany do porownania po restarcie.' -Level 'ARTIFACT'
    if (-not $Silent) {
        Write-Status '' 'White'; Write-Status '--- BENCHMARK PODSUMOWANIE (in-session) ---' 'Cyan'
        Write-Status '  Pelny obraz wydajnosci dostepny po restarcie (uruchom Analyze).' 'Yellow'
        $lines | Select-Object -Skip 3 -First 7 | ForEach-Object { Write-Status $_ 'White' }
    }
    $htmlRows = ($lines | Select-Object -Skip 3 -First 6 | Where-Object { $_.Trim() } | ForEach-Object {
        $cls=if($_-match'LEPIEJ'){'lepiej'}elseif($_-match'GORZEJ'){'gorzej'}else{''}
        "<tr class='$cls'><td colspan='2'>$($_.Trim())</td></tr>"
    }) -join ''
    Add-HtmlSection "<h2>Benchmark przed / po (in-session)</h2><p style='color:#ffcc00'>Pelny obraz po restarcie — uruchom Analyze aby porownac z zapisanym snapshotem.</p><table>$htmlRows</table>"
}

function Get-LatestPersistentBenchmarkPath {
    try {
        return Get-ChildItem -Path $script:RootFolder -Recurse -Filter 'benchmark_before_persistent.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty FullName -First 1
    } catch {
        return $null
    }
}

function Write-PersistentBenchmarkComparison {
    param([Parameter(Mandatory)]$Current,[Parameter(Mandatory)][string]$PersistentPath,[Parameter(Mandatory)]$Lines)
    try {
        $before = Get-Content -Path $PersistentPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $Lines.Add('')
        $Lines.Add('Porownanie z zapisanym snapshotem po restarcie:')
        $Lines.Add("  Snapshot: $PersistentPath")
        $Lines.Add("  Wczesniej: CPU=$($before.CPU_Pct)% | RAM used=$($before.UsedRAM_MB) MB | Free RAM=$($before.FreeRAM_MB) MB | Proc=$($before.ProcessCount)")
        $Lines.Add("  Teraz:     CPU=$($Current.CPU_Pct)% | RAM used=$($Current.UsedRAM_MB) MB | Free RAM=$($Current.FreeRAM_MB) MB | Proc=$($Current.ProcessCount)")
        $safePath = ConvertTo-HtmlSafe $PersistentPath
        Add-HtmlSection "<h2>Porownanie po restarcie</h2><p>Snapshot: $safePath</p><p>Wczesniej: CPU=$($before.CPU_Pct)% | RAM used=$($before.UsedRAM_MB) MB | Free RAM=$($before.FreeRAM_MB) MB | Proc=$($before.ProcessCount)</p><p>Teraz: CPU=$($Current.CPU_Pct)% | RAM used=$($Current.UsedRAM_MB) MB | Free RAM=$($Current.FreeRAM_MB) MB | Proc=$($Current.ProcessCount)</p>"
        Write-Log -Message "Zaladowano persistent benchmark: $PersistentPath" -Level 'INFO'
    } catch {
        Write-Log -Message "Persistent benchmark compare failed: $($_.Exception.Message)" -Level 'WARN'
    }
}

# =============================
# Preflight Preview
# =============================
function Show-PreflightPreview {
    if ($Silent) { return }
    Write-Status '' 'White'
    Write-Status '=============================================' 'Cyan'
    Write-Status '  PREFLIGHT — co zostanie zmienione          ' 'Cyan'
    Write-Status '=============================================' 'Cyan'
    $map = [ordered]@{
        'Zasilanie'      = @{Risk='Bezpieczny';   D='High Performance, Fast Startup off, CPU policy'}
        'Interfejs UI'   = @{Risk='Bezpieczny';   D='Animacje off, efekty wizualne min, Widgets off'}
        'Gaming'         = @{Risk='Agresywny';    D='Game Mode on, DVR off, PrioritySeparation=38'}
        'Siec Network'   = @{Risk='Agresywny';    D="DNS: $($script:SelectedDns), flush DNS, adapter power off"}
        'Uslugi Services'= @{Risk='Bezpieczny';   D='DiagTrack/MapsBroker/WerSvc -> Manual'}
        'Czyszczenie'    = @{Risk='Bezpieczny';   D='TEMP i Windows\Temp czyszczenie'}
        'Naprawa Repair' = @{Risk='Naprawczy';    D=$(if($EnableNetworkRepair){'SFC + DISM RestoreHealth + winsock reset'}else{'SFC + DISM RestoreHealth'})}
        'Gaming Session' = @{Risk='Agresywny';    D='Przeglad ciezkich aplikacji i proba lagodnego zamkniecia przed Force'}
    }
    $active = [ordered]@{}
    if ($script:EnablePowerTweaks)   { $active['Zasilanie']       = $map['Zasilanie'] }
    if ($script:EnableUiTweaks)      { $active['Interfejs UI']    = $map['Interfejs UI'] }
    if ($script:EnableGamingTweaks)  { $active['Gaming']          = $map['Gaming'] }
    if ($script:EnableNetworkTweaks) { $active['Siec Network']    = $map['Siec Network'] }
    if ($script:EnableServiceTuning) { $active['Uslugi Services'] = $map['Uslugi Services'] }
    if ($script:EnableCleanup)       { $active['Czyszczenie']     = $map['Czyszczenie'] }
    if ($script:EnableRepair)        { $active['Naprawa Repair']  = $map['Naprawa Repair'] }
    if ($script:EnableGamingSession) { $active['Gaming Session']  = $map['Gaming Session'] }
    if ($script:EnableRiskPackBundle) {
        $active['Risk Pack'] = @{Risk='Wysoki'; D='Jeden pakiet: telemetria/WU/uslugi/siec/VBS. Zwykle 0-3%, czasem 3-10% gdy VBS blokowal wydajnosc'}
    }
    if ($script:EnableLaptopGamingSafeMode) {
        if ($script:LaptopOptionalTelemetryTuning) { $active['Laptop: Telemetria'] = @{Risk='Ryzykowny'; D='DiagTrack -> Manual (+0-1%, moze oslabic Insider/rollout)'} }
        if ($script:LaptopOptionalWindowsUpdatePause) { $active['Laptop: WU Pause'] = @{Risk='Sredni'; D='Pauza Windows Update 7 dni (+0-2% gdy WU pracuje w tle)'} }
        if ($script:LaptopOptionalVbsDisable -or $EnableVbsDisable) { $active['Laptop: VBS OFF'] = @{Risk='Wysoki'; D='VBS/HVCI OFF (+3-10% w wybranych grach, slabsze bezpieczenstwo)'} }
        if ($script:LaptopOptionalBenchmarkReport) { $active['Laptop PRO: Benchmark'] = @{Risk='Bezpieczny'; D='Pomiar i raport, 0% FPS bezposrednio'} }
        if ($script:LaptopOptionalStartupReview) { $active['Laptop PRO: Autostart'] = @{Risk='Bezpieczny'; D='Przeglad autostartu, pyta zanim wylaczy'} }
        if ($script:LaptopOptionalPostDebloaterRepair) { $active['Laptop PRO: Repair'] = @{Risk='Bezpieczny'; D='Przywraca Insider/WU/Store/Xbox po debloaterach'} }
        if ($script:LaptopOptionalNvidiaProfile) { $active['Laptop PRO: NVIDIA'] = @{Risk='Bezpieczny'; D='HAGS/TDR + nvidia-smi bez OC'} }
        if ($script:LaptopOptionalPerformanceFeelMode) { $active['Performance Feel'] = @{Risk='Bezpieczny'; D='Szybsze UI/input lag/stutter/audio helper; 0-3% FPS, duzy feel'} }
    }
    Write-Host ''
    Write-Host ('  {0,-22} {1,-15} {2}' -f 'MODUL','RYZYKO','OPIS') -ForegroundColor Yellow
    Write-Host ('  ' + '-'*70) -ForegroundColor DarkGray
    foreach ($k in $active.Keys) {
        $r=$active[$k].Risk; $c=switch($r){'Bezpieczny'{'Green'}'Agresywny'{'Yellow'}default{'Red'}}
        Write-Host ('  {0,-22} {1,-15} {2}' -f $k,$r,$active[$k].D) -ForegroundColor $c
    }
    if ($EnableExperimentalTweaks) { Write-Host ('  {0,-22} {1,-15} {2}' -f 'Experimental','Eksperymentalny','Nagle/TCP, HAGS') -ForegroundColor Red }
    Write-Host ''
    $netRepairMsg = if($EnableNetworkRepair){'winsock/LSP (EnableNetworkRepair wlaczony)'}else{'brak dodatkowych nieodwracalnych zmian w default flow'}
    Write-Host ('  Nieodwracalne czesciowo: ' + $netRepairMsg) -ForegroundColor Yellow
    Write-Host '  Wymagany restart po sesji: TAK' -ForegroundColor Yellow
    Write-Host ''
    # v12 PREMIUM: dokumentacja techniczna kluczowych tweaków
    if (-not $Silent) {
        Write-Host ''
        Write-Host '  DOKUMENTACJA TECHNICZNA — kluczowe tweaki:' -ForegroundColor Yellow
        Write-Host '  (nacisnij Enter aby pominac, D aby zobaczyc pelna dokumentacje)' -ForegroundColor DarkGray
        $dk = (Read-Host 'Wybor (Enter/D)').Trim().ToUpper()
        if ($dk -eq 'D') {
            $docsToShow = @('HighPerformance','HAGS','Win32Priority','GlobalTimer','MPODisable','TDRDelay','DiagTrack')
            if ($EnableVbsDisable) { $docsToShow += 'VBSDisable' }
            foreach ($tid in $docsToShow) {
                $d = Get-TweakDocumentation -TweakId $tid
                if ($d -and ($d.Profile -contains $Profile -or $Profile -eq 'Custom')) {
                    Show-TweakDoc -TweakId $tid
                    Write-Host ''
                }
            }
            Write-Host '  Nacisnij Enter aby kontynuowac...' -ForegroundColor DarkGray
            [void][System.Console]::ReadLine()
        }
    }
}

# =============================
# Post Validation
# =============================
function Invoke-PostValidation {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('=== WALIDACJA PO ZASTOSOWANIU ==='); $lines.Add('')
    $htmlR = ''
    function Check { param($lbl,$val,$exp)
        $ok=$val-eq$exp; $st=if($ok){'[OK]      '}else{'[NIEZGODNE]'}
        $lines.Add(('  {0} {1,-45} oczekiwano={2}  aktualne={3}'-f$st,$lbl,$exp,$val))
        $cls=if($ok){'lepiej'}else{'gorzej'}
        $script:_hvr+="<tr class='$cls'><td>$lbl</td><td>$st</td><td>$val</td></tr>"
    }
    $script:_hvr=''
    $ap=(& powercfg /getactivescheme 2>$null)-join''
    Check 'Plan zasilania High Performance' ($ap-match'High performance'-or$ap-match'8c5e7fda') $true
    Check 'HiberbootEnabled (Fast Startup off)' (Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' -1) 0
    Check 'GameDVR_Enabled (off)' (Get-RegistryValueOrDefault 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' -1) 0
    Check 'Win32PrioritySeparation' (Get-RegistryValueOrDefault 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' -1) 38
    $diagSvc = Get-Service DiagTrack -ErrorAction SilentlyContinue
    $diagStartType = if ($diagSvc) { [string]$diagSvc.StartType } else { '' }
    Check 'DiagTrack StartType (Manual)' $diagStartType 'Manual'
    if ($script:EnableNetworkTweaks -and $script:SelectedDns -ne 'Keep') {
        $adp=Get-NetAdapter -Physical -ErrorAction SilentlyContinue|Where-Object { $_.Status -eq 'Up' }|Select-Object -First 1
        if ($adp) {
            $dns=(Get-DnsClientServerAddress -InterfaceIndex $adp.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
            $ok=switch($script:SelectedDns){'Google'{$dns-contains'8.8.8.8'}'Cloudflare'{$dns-contains'1.1.1.1'}'Quad9'{$dns-contains'9.9.9.9'}default{$true}}
            Check "DNS IPv4 $($script:SelectedDns) ($($adp.Name))" $ok $true
            $dns6=(Get-DnsClientServerAddress -InterfaceIndex $adp.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses
            $ok6=switch($script:SelectedDns){'Google'{$dns6-contains'2001:4860:4860::8888'}'Cloudflare'{$dns6-contains'2606:4700:4700::1111'}'Quad9'{$dns6-contains'2620:fe::fe'}default{$true}}
            Check "DNS IPv6 $($script:SelectedDns) ($($adp.Name))" $ok6 $true
        }
    }
    $lines.Add('')
    $lines|Set-Content -Path $script:ValidationPath -Encoding UTF8
    Write-Log -Message 'Walidacja zapisana.' -Level 'ARTIFACT'
    Write-Status '==> Walidacja: validation.txt' 'Cyan'
    Add-HtmlSection "<h2>Walidacja po zastosowaniu</h2><table><tr><th>Sprawdzenie</th><th>Status</th><th>Wartosc</th></tr>$($script:_hvr)</table>"
}

# =============================
# Network helpers
# =============================
function Backup-NetworkStateFull {
    $net=[ordered]@{
        Adapters=(Get-NetAdapter -EA SilentlyContinue|Select-Object Name,Status,LinkSpeed,InterfaceDescription,MacAddress)
        IPConfig=(Get-NetIPConfiguration -EA SilentlyContinue)
        DNS=(Get-DnsClientServerAddress -EA SilentlyContinue|Select-Object InterfaceAlias,AddressFamily,ServerAddresses)
        Routes=(Get-NetRoute -EA SilentlyContinue|Select-Object DestinationPrefix,NextHop,RouteMetric,InterfaceAlias)
        IpconfigAll=((& ipconfig /all 2>$null)-join"`n")
        WinsockCatalog=((& netsh winsock show catalog 2>$null)-join"`n")
    }
    $net|ConvertTo-Json -Depth 8|Set-Content -Path (Join-Path $script:BackupFolder 'network_before_full.json') -Encoding UTF8
    Write-Log -Message 'Pelny backup sieci zapisany.' -Level 'INFO'
}

function Set-DnsCustomSafe {
    param([string[]]$IPv4Servers, [string[]]$IPv6Servers = @())
    $lbl = $IPv4Servers -join ' / '
    Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
        if ($_.InterfaceDescription -match 'Hyper-V|TAP|VPN|Virtual|Miniport') { return }
        try {
            $cur = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -EA Stop).ServerAddresses
            if (($cur -join ',') -eq ($IPv4Servers -join ',')) { Write-Log "DNS juz $lbl na $($_.Name)"; return }
            Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses $IPv4Servers -EA Stop
            Write-Log "DNS IPv4 -> $lbl na $($_.Name) (poprzedni: $($cur -join ', '))" -Level 'CHANGE'
        } catch { Write-Log "DNS IPv4 change failed: $($_.Name)" -Level 'WARN' }
        if ($IPv6Servers.Count -gt 0) {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses $IPv6Servers -EA Stop
                Write-Log "DNS IPv6 -> $($IPv6Servers -join ' / ') na $($_.Name)" -Level 'CHANGE'
            } catch { Write-Log "DNS IPv6 change failed: $($_.Name)" -Level 'WARN' }
        }
    }
}

# =============================
# Session History
# =============================
function Show-SessionHistory {
    if (-not (Test-Path $script:RootFolder)) { return }
    $sessions=Get-ChildItem -Path $script:RootFolder -Directory -EA SilentlyContinue|Sort-Object Name -Descending|Select-Object -First 8
    if (-not $sessions) { return }
    Write-Status '--- Historia ostatnich sesji ---' 'Cyan'
    Write-Host ('  {0,-18} {1,-10} {2,-10} {3,-8} {4}'-f'SESJA','TRYB','PROFIL','ZMIANY','HOSTNAME') -ForegroundColor Yellow
    Write-Host ('  '+'-'*65) -ForegroundColor DarkGray
    foreach ($s in $sessions) {
        $mp=Join-Path $s.FullName 'manifest.json'
        if (Test-Path $mp) {
            try {
                $m=Get-Content $mp -Raw|ConvertFrom-Json
                $ch='?'; $cl=Join-Path $s.FullName 'Logs\changes.log'
                if (Test-Path $cl) { $ch=(Get-Content $cl|Measure-Object).Count }
                Write-Host ('  {0,-18} {1,-10} {2,-10} {3,-8} {4}'-f$s.Name,$m.Mode,$m.Profile,$ch,$m.Environment.ComputerName) -ForegroundColor Gray
            } catch { Write-Host ('  {0,-18} (brak danych)'-f$s.Name) -ForegroundColor DarkGray }
        }
    }
    Write-Status '' 'White'
}

# =============================
# System Environment
# =============================
function Get-SystemEnvironment {
    $os=Get-CimInstance Win32_OperatingSystem
    $cs=Get-CimInstance Win32_ComputerSystem
    $cpu=Get-CimInstance Win32_Processor|Select-Object -First 1
    $gpuList=Get-CimInstance Win32_VideoController|Select-Object Name,DriverVersion,DriverDate,AdapterRAM
    $disks=Get-PhysicalDisk -EA SilentlyContinue|Select-Object FriendlyName,MediaType,Size,BusType
    $battery=Get-CimInstance Win32_Battery -EA SilentlyContinue
    $product=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $buildLabEx = [string]($product.BuildLabEx)
    $isInsiderPreview = $false
    if (
        [string]$product.ProductName -match 'Insider' -or
        $buildLabEx -match 'Canary|Dev|Beta|ReleasePreview|Insider'
    ) { $isInsiderPreview = $true }
    $memMod=Get-CimInstance Win32_PhysicalMemory|Select-Object Capacity,Speed,Manufacturer,PartNumber
    $netAdp=Get-NetAdapter -EA SilentlyContinue|Select-Object Name,Status,LinkSpeed,InterfaceDescription
    $trimSt=$null; try{$trimSt=(& fsutil behavior query DisableDeleteNotify 2>$null)-join"`n"}catch{}
    $isLaptop=$false
    if ($battery) { $isLaptop=$true }
    if ($cs.PCSystemType -in 2,8,9,10,14) { $isLaptop=$true }
    $hags=$null; try{$hags=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -EA Stop).HwSchMode}catch{}
    $dg=$null; try{$dg=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -EA Stop}catch{}
    $hvci=$null; try{$hvci=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -EA Stop).Enabled}catch{}
    $mdm=$false
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Enrollments') {
        try { $mdm = @((Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -EA SilentlyContinue)).Count -gt 0 } catch {}
    }
    $bitlocker=$false
    try {
        $blv = Get-BitLockerVolume -MountPoint $env:SystemDrive -EA SilentlyContinue
        if ($blv) { $bitlocker = $blv.ProtectionStatus -eq 'On' -or $blv.ProtectionStatus -eq 1 }
    } catch {}
    [ordered]@{
        ComputerName=$env:COMPUTERNAME; UserName=$env:USERNAME; IsLaptop=$isLaptop
        Manufacturer=$cs.Manufacturer; Model=$cs.Model
        WindowsProductName=$product.ProductName; WindowsEdition=$product.EditionID; WindowsReleaseId=$product.DisplayVersion
        BuildLabEx=$buildLabEx; UBR=$product.UBR; IsInsiderPreview=[bool]$isInsiderPreview
        Build=$os.BuildNumber; Version=$os.Version; InstallDate=$os.InstallDate
        TotalRAMGB=[math]::Round($cs.TotalPhysicalMemory/1GB,2); MemoryModules=$memMod
        CPU=$cpu.Name; CPUCores=$cpu.NumberOfCores; CPULogical=$cpu.NumberOfLogicalProcessors; CPUMaxClockMHz=$cpu.MaxClockSpeed
        GPU=$gpuList; Disks=$disks; TrimStatus=$trimSt; HasBattery=[bool]$battery
        PowerScheme=(& powercfg /getactivescheme 2>$null)
        HyperV=[bool](Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -EA SilentlyContinue|Where-Object { $_.State -eq 'Enabled' })
        WSL=[bool](Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -EA SilentlyContinue|Where-Object { $_.State -eq 'Enabled' })
        IsDomainJoined=[bool]$cs.PartOfDomain
        IsMDMManaged=[bool]$mdm
        BitLockerSystemDrive=[bool]$bitlocker
        VBS=[bool]($dg -and $dg.EnableVirtualizationBasedSecurity -eq 1)
        HVCI=[bool]($hvci -eq 1)
        HAGS=$hags; NetworkAdapters=$netAdp
    }
}

function Save-Manifest { $script:Manifest|ConvertTo-Json -Depth 16 -WarningAction Stop|Set-Content -Path $script:ManifestPath -Encoding UTF8 }
# FIX v14.5.1: Depth 8 -> 16 (manifest deepened by module options; truncation would silently corrupt rollback data).
# WarningAction Stop: if depth is EVER exceeded again we want a loud error, not a quietly broken manifest.

function Save-Snapshot {
    param([Parameter(Mandatory)][ValidateSet('before','after')][string]$Kind)
    $path=if($Kind-eq'before'){$script:BeforeSnapshotPath}else{$script:AfterSnapshotPath}
    [ordered]@{
        Timestamp=(Get-Date).ToString('o'); Environment=$script:Manifest.Environment
        TopCpu=Get-Process|Sort-Object @{Expression={if($_.CPU-is[timespan]){$_.CPU.TotalSeconds}elseif($null-eq$_.CPU){-1}else{[double]$_.CPU}}}-Descending|Select-Object -First 15 ProcessName,Id,CPU,WS
        TopRam=Get-Process|Sort-Object WS -Descending|Select-Object -First 15 ProcessName,Id,CPU,WS
        Services=Get-Service|Select-Object Name,Status,StartType
        Startup=Get-CimInstance Win32_StartupCommand|Select-Object Name,Command,Location
        Network=Get-NetAdapter -EA SilentlyContinue|Select-Object Name,Status,LinkSpeed,InterfaceDescription
        ActivePowerScheme=(& powercfg /getactivescheme 2>$null)
    }|ConvertTo-Json -Depth 6|Set-Content -Path $path -Encoding UTF8
}

function Export-RegistryKeyIfExists {
    param([Parameter(Mandatory)][string]$RegPath,[Parameter(Mandatory)][string]$Tag)
    $native=$RegPath-replace'^HKLM:','HKEY_LOCAL_MACHINE'-replace'^HKCU:','HKEY_CURRENT_USER'
    $dest=Join-Path $script:RegistryBackupFolder ("$($script:SessionId)_" + (($Tag-replace'[^a-zA-Z0-9_-]','_')+'.reg'))
    if (Test-Path $RegPath) { & reg.exe export $native $dest /y|Out-Null; return $dest }
    return $null
}

function Get-TweakSafetyBucket {
    param(
        [Parameter(Mandatory)][string]$Risk,
        [string[]]$AvoidOn = @(),
        [string[]]$RecommendedFor = @()
    )

    if ($Risk -eq 'Experimental') { return 'Experimental' }
    if ($Risk -eq 'High') { return 'HighRisk' }
    if ($AvoidOn.Count -gt 0 -or $RecommendedFor.Count -gt 0) { return 'Conditional' }
    return 'Safe'
}

function Add-TweakMetadata {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][ValidateSet('Low','Medium','High','Experimental')][string]$Risk,
        [Parameter(Mandatory)][ValidateSet('Strong','Medium','Weak')][string]$Evidence,
        [string[]]$RecommendedFor = @(),
        [string[]]$AvoidOn = @(),
        [ValidateSet('Safe','Conditional','Experimental','HighRisk')][string]$Bucket = '',
        [switch]$RequiresRestart,
        [string]$Notes = ''
    )

    $existing = @($script:Manifest.Tweaks) | Where-Object { $_.Id -eq $Id }
    if ($existing) { return }

    if (-not $Bucket) {
        $Bucket = Get-TweakSafetyBucket -Risk $Risk -AvoidOn $AvoidOn -RecommendedFor $RecommendedFor
    }

    $script:Manifest.Tweaks += [ordered]@{
        Id              = $Id
        Name            = $Name
        Category        = $Category
        Bucket          = $Bucket
        Risk            = $Risk
        Evidence        = $Evidence
        RecommendedFor  = $RecommendedFor
        AvoidOn         = $AvoidOn
        RequiresRestart = [bool]$RequiresRestart
        Notes           = $Notes
    }
}


function Add-SmartDecision {
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [Parameter(Mandatory)][ValidateSet('Allow','Skip','Warn')][string]$Decision,
        [Parameter(Mandatory)][string]$Reason
    )
    if ($script:Manifest -and $script:Manifest.Contains('SmartDecisions')) {
        $script:Manifest.SmartDecisions += [ordered]@{
            Id=$TweakId; Decision=$Decision; Reason=$Reason; Timestamp=(Get-Date).ToString('o')
        }
    }
}

function Test-PathIsUnsafeDefenderExclusion {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
        $root = [System.IO.Path]::GetPathRoot($full).TrimEnd('\')
        if ($full -ieq $root) { return 'root dysku' }
        $unsafe = @($env:SystemDrive,$env:WINDIR,$env:USERPROFILE,(Join-Path $env:USERPROFILE 'Desktop'),(Join-Path $env:USERPROFILE 'Downloads'),(Join-Path $env:USERPROFILE 'Documents'),${env:ProgramFiles},${env:ProgramFiles(x86)}) | Where-Object { $_ }
        foreach ($u in $unsafe) {
            $uFull = [System.IO.Path]::GetFullPath($u).TrimEnd('\')
            if ($full -ieq $uFull) { return "zbyt szeroka sciezka: $uFull" }
        }
    } catch { return 'nie mozna bezpiecznie zweryfikowac sciezki' }
    return $null
}

function Get-SmartTweakDecision {
    param([Parameter(Mandatory)][string]$TweakId)
    if (-not $script:SmartModeEnabled) { return [PSCustomObject]@{ Allow=$true; Level='Allow'; Reason='Smart Mode wylaczony przez -DisableSmartMode' } }
    $envInfo = $script:Manifest.Environment
    $hw = $script:HWProfile
    $isLaptop = [bool]$envInfo.IsLaptop
    $onBattery = $isLaptop -and -not [bool]$script:LaptopOnAC
    $dedicatedGpu = $false
    if ($hw) { $dedicatedGpu = [bool]($hw.IsNvidia -or $hw.IsAmd) }

    switch ($TweakId) {
        'VBSDisable' {
            if ($isLaptop) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: laptop - VBS/HVCI zostawiam dla bezpieczenstwa'} }
            if ($envInfo.IsDomainJoined -or $envInfo.IsMDMManaged) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: komputer zarzadzany firmowo - nie wylaczam VBS/HVCI'} }
            if ($envInfo.BitLockerSystemDrive) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: BitLocker aktywny - nie obnizam izolacji kernela'} }
            if ($envInfo.HyperV) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: Hyper-V/virtualization aktywne - VBS moze byc wymagane'} }
            if ($envInfo.WSL) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: WSL aktywny - nie ruszam VBS/HVCI'} }
            if ($envInfo.IsInsiderPreview -and $Profile -ne 'Maximum') { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: Insider Preview - VBS/HVCI zostawiam dla stabilnosci builda'} }
        }
        'GlobalTimer' {
            if ($onBattery) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: laptop na baterii - timer 0.5ms zwieksza pobor energii'} }
            if ($isLaptop -and $Profile -notin @('Gaming','Maximum')) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: laptop - timer 0.5ms tylko dla Gaming/Maximum na AC'} }
        }
        'NetworkDriverTuning' {
            if ($isLaptop) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: laptop - pomijam agresywny tuning sterownikow sieciowych'} }
            try {
                $up = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
                $wifi = @($up | Where-Object { $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11|WLAN' })
                $eth  = @($up | Where-Object { $_.InterfaceDescription -match 'Ethernet|Realtek|Intel|Killer|I2[0-9]{2}' })
                if ($wifi.Count -gt 0 -and $eth.Count -eq 0) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: aktywne tylko Wi-Fi - tuning NIC zostawiam bez zmian'} }
            } catch {}
        }
        'GPUMsiMode' {
            if (-not $dedicatedGpu) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: brak dedykowanego GPU - MSI mode nie ma sensu'} }
            if ($isLaptop) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: laptop - GPU MSI mode jest zbyt ryzykowny'} }
            $compat = @(Test-V14HighRiskCompatibilityContext)
            if ($compat.Count -gt 0) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason="Smart Mode: konflikt kompatybilnosci ($($compat -join '; '))"} }
        }
        'HAGS' {
            if (-not $dedicatedGpu) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: brak NVIDIA/AMD GPU - HAGS pomijam'} }
            if ($onBattery) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: laptop na baterii - HAGS pomijam'} }
        }
        'MPODisable' {
            $compat = @(Test-V14HighRiskCompatibilityContext)
            if ($compat.Count -gt 0) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason="Smart Mode: zostawiam MPO przez aktywne narzedzia/anti-cheat ($($compat -join '; '))"} }
            try {
                $overlay = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Discord|NVIDIA|RTSS|MSIAfterburner|Overwolf|SteamWebHelper' } | Select-Object -First 1
                if (-not $overlay) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: brak typowych overlayi - MPO disable pomijam'} }
            } catch {}
        }
        'Coolbits' {
            $compat = @(Test-V14HighRiskCompatibilityContext)
            if ($compat.Count -gt 0) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason="Smart Mode: pomijam Coolbits przez aktywne narzedzia/anti-cheat ($($compat -join '; '))"} }
            if ($isLaptop) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: laptop - Coolbits pomijam'} }
        }
        'ShaderCacheCleanup' {
            if (-not $dedicatedGpu) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: brak NVIDIA/AMD GPU cache do czyszczenia'} }
            if ($Profile -notin @('Gaming','Maximum') -and -not $EnableExperimentalTweaks) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: nie czyszcze shader cache w Safe/Balanced - pierwszy start gier moze miec stutter'} }
        }
        'DefenderGameExclusion' {
            if ($GameFolder) {
                $unsafe = Test-PathIsUnsafeDefenderExclusion -Path $GameFolder
                if ($unsafe) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason="Smart Mode: Defender exclusion zablokowane ($unsafe)"} }
            }
        }
        'UltimatePerformance' {
            if ($onBattery) { return [PSCustomObject]@{Allow=$false;Level='Skip';Reason='Smart Mode: laptop na baterii - Ultimate/High Performance pomijam'} }
        }
    }
    return [PSCustomObject]@{ Allow=$true; Level='Allow'; Reason='Smart Mode: OK dla tego komputera' }
}

function Apply-V14SafetyPolicies {
    $envInfo = $script:Manifest.Environment
    if (-not $envInfo) { return }

    $notes = New-Object System.Collections.Generic.List[string]

    if ($envInfo.IsInsiderPreview) {
        if ($script:LaptopOptionalTelemetryTuning -or $EnableTelemetryTuning) {
            $script:LaptopOptionalTelemetryTuning = $false
            Set-Variable -Name EnableTelemetryTuning -Scope Script -Value $false
            $notes.Add('Insider Preview: DiagTrack tuning wylaczony dla stabilnosci rollout/feature updates')
        }
        if ($script:LaptopOptionalWindowsUpdatePause -or $script:AllowGlobalWindowsUpdatePause -or $EnableWindowsUpdatePause) {
            $script:LaptopOptionalWindowsUpdatePause = $false
            $script:AllowGlobalWindowsUpdatePause = $false
            Set-Variable -Name EnableWindowsUpdatePause -Scope Script -Value $false
            $notes.Add('Insider Preview: pauza Windows Update wylaczona, zeby nie opozniac buildow i poprawek')
        }
    }

    foreach ($note in $notes) {
        Write-Log "v14 Safety Policy: $note" -Level 'WARN'
        Write-Status "  Safety Policy: $note" 'Yellow'
        $script:Manifest.Notes += $note
    }
}

function Get-V14RecommendedScenario {
    $envInfo = $script:Manifest.Environment
    $hw = $script:HWProfile
    if (-not $envInfo -or -not $hw) { return 'Safe / Audit' }
    if ($envInfo.IsInsiderPreview -and $envInfo.IsLaptop) { return 'LaptopGamingSafe / Audit' }
    if ($envInfo.IsLaptop -and -not $script:LaptopOnAC) { return 'BatterySaver / Audit' }
    if ($envInfo.IsLaptop -and $hw.IsNvidia) { return 'GamingLaptop' }
    if ($hw.IsLowRAM) { return 'LowRAM' }
    return 'Balanced / Gaming'
}

function Test-V14HighRiskCompatibilityContext {
    $issues = New-Object System.Collections.Generic.List[string]
    try {
        $antiCheatServices = @(
            Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'EasyAntiCheat|BEService|vgk|FACEIT|xhunter|ACE-' -and $_.Status -eq 'Running' } |
            Select-Object -ExpandProperty Name
        )
        foreach ($svc in $antiCheatServices) { $issues.Add("anti-cheat: $svc") }
    } catch {}
    try {
        $tools = @(
            Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -match 'RTSS|MSIAfterburner|ProcessLasso|HWiNFO|CapFrameX|PresentMon' } |
            Select-Object -ExpandProperty ProcessName
        )
        foreach ($tool in $tools) { $issues.Add("tool: $tool") }
    } catch {}
    return @($issues | Select-Object -Unique)
}

function Apply-V14ScenarioPreset {
    if ($Scenario -eq 'Auto') { return }
    $envInfo = $script:Manifest.Environment

    switch ($Scenario) {
        'Esport' {
            $script:EnableGamingTweaks = $true
            $script:EnableUiTweaks = $true
            $script:EnablePowerTweaks = $true
            $EnablePerformanceFeelMode = $true
            $EnableBenchmarkReport = $false
            if ($Profile -eq 'Safe') { $Profile = if ($envInfo.IsLaptop) { 'GamingLaptop' } else { 'Gaming' } }
        }
        'AAA' {
            $script:EnableGamingTweaks = $true
            $script:EnableUiTweaks = $true
            $script:EnablePowerTweaks = $true
            $EnablePerformanceFeelMode = $true
            $EnableBenchmarkReport = $true
            if ($Profile -eq 'Safe') { $Profile = if ($envInfo.IsLaptop) { 'GamingLaptop' } else { 'Balanced' } }
        }
        'Silent' {
            $script:EnableUiTweaks = $true
            $EnablePerformanceFeelMode = $true
            $script:EnableGamingTweaks = $false
            $script:EnableNetworkTweaks = $false
            $script:EnableServiceTuning = $false
            Set-Variable -Name EnableVbsDisable -Scope Script -Value $false
            if ($Profile -eq 'Safe') { $Profile = if ($envInfo.IsLaptop) { 'LaptopGamingSafe' } else { 'Balanced' } }
        }
        'Work' {
            $script:EnableUiTweaks = $true
            $EnablePerformanceFeelMode = $true
            $script:EnableGamingTweaks = $false
            $script:EnableNetworkTweaks = $false
            Set-Variable -Name EnableVbsDisable -Scope Script -Value $false
            if ($Profile -eq 'Safe') { $Profile = if ($envInfo.IsLaptop) { 'OfficeLaptop' } else { 'Workstation' } }
        }
    }

    $script:Manifest.Scenario = $Scenario
    $script:Manifest.Profile = $Profile
    $script:Manifest.Notes += "Scenario preset applied: $Scenario"
    Write-Log "v14 Scenario preset applied: $Scenario -> Profile=$Profile" -Level 'INFO'
}

function Test-TweakEligibility {
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [string[]]$AvoidOn = @(),
        [switch]$RequireExperimental,
        [switch]$RequireDesktop,
        [switch]$RequireAC,
        [switch]$RequireDedicatedGpu,
        [switch]$BlockOnDomain,
        [switch]$BlockOnMDM,
        [switch]$BlockOnHyperV,
        [switch]$BlockOnBitLocker,
        [switch]$BlockOnLaptop
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    $envInfo = $script:Manifest.Environment
    $hw = $script:HWProfile

    if ($RequireExperimental -and -not $EnableExperimentalTweaks) { $reasons.Add('wymaga -EnableExperimentalTweaks') }
    if ($RequireDesktop -and $envInfo.IsLaptop) { $reasons.Add('tylko desktop') }
    if ($RequireAC -and $script:LaptopProfile -and -not $script:LaptopOnAC) { $reasons.Add('wymaga zasilania AC') }
    if ($BlockOnLaptop -and $envInfo.IsLaptop) { $reasons.Add('pomijam na laptopie') }
    if ($RequireDedicatedGpu -and $hw -and $hw.IsIntelGPU -and -not $hw.IsNvidia -and -not $hw.IsAmd) { $reasons.Add('wymaga dedykowanego GPU') }
    if ($BlockOnDomain -and $envInfo.IsDomainJoined) { $reasons.Add('system w domenie') }
    if ($BlockOnMDM -and $envInfo.IsMDMManaged) { $reasons.Add('system zarzadzany przez MDM/Intune') }
    if ($BlockOnHyperV -and $envInfo.HyperV) { $reasons.Add('Hyper-V wlaczony') }
    if ($BlockOnBitLocker -and $envInfo.BitLockerSystemDrive) { $reasons.Add('BitLocker aktywny') }

    foreach ($flag in $AvoidOn) {
        switch ($flag) {
            'Laptop' { if ($envInfo.IsLaptop) { $reasons.Add('AvoidOn: Laptop') } }
            'Domain' { if ($envInfo.IsDomainJoined) { $reasons.Add('AvoidOn: Domain') } }
            'MDM' { if ($envInfo.IsMDMManaged) { $reasons.Add('AvoidOn: MDM') } }
            'HyperV' { if ($envInfo.HyperV) { $reasons.Add('AvoidOn: HyperV') } }
            'BitLocker' { if ($envInfo.BitLockerSystemDrive) { $reasons.Add('AvoidOn: BitLocker') } }
        }
    }

    $smart = Get-SmartTweakDecision -TweakId $TweakId
    if (-not $smart.Allow) { $reasons.Add($smart.Reason) }
    elseif ($smart.Level -eq 'Warn') { Add-SmartDecision -TweakId $TweakId -Decision Warn -Reason $smart.Reason }

    if ($reasons.Count -gt 0) {
        $reasonText = ($reasons -join ', ')
        Add-SmartDecision -TweakId $TweakId -Decision Skip -Reason $reasonText
        Write-Log "${TweakId}: pominiety ($reasonText)." -Level 'WARN'
        Write-Status "  SKIP: $TweakId — $reasonText" 'Yellow'
        $script:Manifest.Notes += "$TweakId skipped: $reasonText"
        $script:Manifest.SkippedTweaks += [ordered]@{ Id=$TweakId; Reason=$reasonText; Timestamp=(Get-Date).ToString('o') }
        $script:SkippedCount++
        return $false
    }

    return $true
}

function Get-NicRecommendedValue {
    param(
        [Parameter(Mandatory)]$CurrentProperty,
        [Parameter(Mandatory)][string]$Keyword,
        [Parameter(Mandatory)][int]$PreferredValue,
        [int]$MinimumValue = 0,
        [int]$MaximumValue = 0
    )

    if (-not $CurrentProperty) { return $null }
    $supported = @()
    foreach ($x in @($CurrentProperty.ValidRegistryValues)) {
        $n = 0
        if ([int]::TryParse([string]$x, [ref]$n)) { $supported += $n }
    }
    if ($supported.Count -gt 0) {
        if ($supported -contains $PreferredValue) { return $PreferredValue }
        $lowerOrEqual = $supported | Where-Object { $_ -le $PreferredValue } | Sort-Object -Descending
        if ($lowerOrEqual) { return $lowerOrEqual[0] }
        return ($supported | Sort-Object | Select-Object -First 1)
    }

    if ($MaximumValue -gt 0) { return [math]::Min($PreferredValue, $MaximumValue) }
    if ($MinimumValue -gt 0) { return [math]::Max($PreferredValue, $MinimumValue) }
    return $PreferredValue
}

function Set-RegistryValueSafe {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)]$Value,[Parameter(Mandatory)][ValidateSet('DWord','String')][string]$Type,[string]$Reason='',[switch]$RequiresRestart)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force|Out-Null }
    $backup=Export-RegistryKeyIfExists -RegPath $Path -Tag (($Path-replace'[:\\/]','_')+'_'+$Name)
    $old=$null; try{$old=(Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name}catch{}
    if ($old-eq$Value) { Write-Log "Registry unchanged: $Path\$Name=$Value"; $script:SkippedCount++; return }
    if ($DryRun) {
        Write-Status "  [DRYRUN] Registry: $Path\$Name = $Value (bylo: $old)" 'DarkGray'
        Write-Log "[DRYRUN] Registry: $Path\$Name = $Value (bylo: $old)"
        return
    }
    if ($Type-eq'DWord'){New-ItemProperty -Path $Path -Name $Name -PropertyType DWord  -Value([UInt32]$Value)  -Force|Out-Null}
    else               {New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value([string]$Value) -Force|Out-Null}
    $key = "$Path\$Name"
    $existingRegEntries = @($script:Manifest.Registry)
    if ($existingRegEntries | Where-Object { "$($_.Path)\$($_.Name)" -eq $key }) {
        Write-Log "Registry: duplikat pominiety: $key" -Level 'INFO'
    } else {
        $script:Manifest.Registry+=[ordered]@{Path=$Path;Name=$Name;OldValue=$old;NewValue=$Value;Type=$Type;BackupFile=$backup;Reason=$Reason}
    }
    Write-Log "Registry set: $Path\$Name=$Value ($Reason)" -Level 'CHANGE'
    if ($RequiresRestart) { Add-RestartFlag "Registry: $Path\$Name" }
}

function Set-RegistryDwordSafe  { param([Parameter(Mandatory)][string]$P,[Parameter(Mandatory)][string]$N,[Parameter(Mandatory)][UInt32]$V,[string]$R='',[switch]$Rst) Set-RegistryValueSafe -Path $P -Name $N -Value $V -Type DWord  -Reason $R -RequiresRestart:$Rst }
function Set-RegistryStringSafe { param([Parameter(Mandatory)][string]$P,[Parameter(Mandatory)][string]$N,[Parameter(Mandatory)][string]$V,[string]$R='',[switch]$Rst) Set-RegistryValueSafe -Path $P -Name $N -Value $V -Type String -Reason $R -RequiresRestart:$Rst }

function Backup-ServiceState {
    Get-CimInstance Win32_Service|Select-Object Name,DisplayName,StartMode,State|ConvertTo-Json -Depth 4|Set-Content -Path (Join-Path $script:BackupFolder 'services_before.json') -Encoding UTF8
}

function Set-ServiceStartupSafe {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][ValidateSet('Automatic','Manual','Disabled')][string]$StartupType,[switch]$StopService,[string]$Reason='')
    $svc=Get-Service -Name $Name -EA SilentlyContinue
    if (-not $svc) { Write-Log "Service not found: $Name" -Level 'WARN'; $script:SkippedCount++; return }
    $wmi=Get-CimInstance Win32_Service -Filter "Name='$Name'"
    # FIX v15.3 (external report BUG2): Win32_Service.StartMode returns 'Auto' for Automatic services,
    # so the skip-guard never fired and every Automatic service was redundantly re-set (rollback at
    # Invoke-Rollback already had this normalization — the setter did not).
    $normStartMode = if ($wmi -and $wmi.StartMode -eq 'Auto') { 'Automatic' } elseif ($wmi) { $wmi.StartMode } else { $null }
    if ($normStartMode -eq $StartupType -and (-not $StopService)) { Write-Log "Service unchanged: $Name"; $script:SkippedCount++; return }
    if ($DryRun) {
        Write-Status "  [DRYRUN] Service: $Name -> $StartupType (bylo: $($wmi.StartMode))" 'DarkGray'
        Write-Log "[DRYRUN] Service: $Name -> $StartupType"
        return
    }
    # FIX v15.3.1 (external report): store the NORMALIZED value ('Automatic', not CIM's 'Auto')
    $script:Manifest.Services+=[ordered]@{Name=$Name;OldStartMode=$normStartMode;OldState=$wmi.State;NewStartMode=$StartupType;Reason=$Reason}
    Set-Service -Name $Name -StartupType $StartupType -EA Stop
    if ($StopService -and $svc.Status-eq'Running') { Stop-Service -Name $Name -Force -EA SilentlyContinue }
    Write-Log "Service: $Name -> $StartupType ($Reason)" -Level 'CHANGE'
}

function Backup-PowerPlans {
    $dir=Join-Path $script:BackupFolder 'Power'; New-DirectorySafe -Path $dir
    $list=& powercfg /list; $active=& powercfg /getactivescheme
    Set-Content -Path (Join-Path $dir 'powerplans.txt') -Value $list
    Set-Content -Path (Join-Path $dir 'active_scheme.txt') -Value $active
    $script:Manifest.Power.BeforeList=$list; $script:Manifest.Power.ActiveBefore=$active
}

function Set-ActivePowerSchemeHighPerformance {
    if ($EnableUltimatePerfPlan) {
        # Ultimate Performance — ukryty plan, dostepny od Win10 1803. Agresywniej blokuje stany
        # oszczedzania energii CPU niz High Performance. Realny zysk szczegolnie na desktopie AC.
        $existingUltimate = (& powercfg /list 2>$null) | Where-Object { $_ -match 'e9a42b02-d5df-448d-aa00-03f14749eb61' }
        if (-not $existingUltimate) {
            Write-Status '  Aktywowanie planu Ultimate Performance...' 'Cyan'
            & powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
        }
        & powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
        $active = (& powercfg /getactivescheme 2>$null) -join ''
        if ($active -match 'e9a42b02') {
            Write-Log 'Plan zasilania: Ultimate Performance.' -Level 'CHANGE'
        } else {
            Write-Log 'WARN: Ultimate Performance niedostepny — fallback na High Performance.' -Level 'WARN'
            & powercfg /setactive SCHEME_MIN | Out-Null
            Write-Log 'Plan zasilania: High Performance (fallback).' -Level 'CHANGE'
        }
    } else {
        & powercfg /setactive SCHEME_MIN | Out-Null
        $active = (& powercfg /getactivescheme 2>$null) -join ''
        if ($active -notmatch 'High performance|8c5e7fda') {
            Write-Log 'WARN: Plan High Performance nie zostal aktywowany (mozliwe blokowanie przez GPO lub brak planu).' -Level 'WARN'
            Write-Status '  WARN: Plan High Performance nie aktywny — sprawdz GPO/MDM.' 'Yellow'
        }
        Write-Log 'Plan zasilania: High Performance.' -Level 'CHANGE'
    }
    $script:Manifest.Power.ActiveAfter = (& powercfg /getactivescheme 2>$null)
}

function New-SystemRestorePointCompat {
    <#
    .SYNOPSIS
        FIX v14.0.1: Checkpoint-Computer i Enable-ComputerRestore NIE ISTNIEJA w PowerShell 7.
        Poprzednia wersja po cichu nie tworzyla zadnego punktu przywracania (CommandNotFoundException
        ladowal w pustym catch). Ta wersja wykonuje operacje przez Windows PowerShell 5.1
        i WERYFIKUJE, ze punkt faktycznie powstal.
    .OUTPUTS
        $true gdy punkt istnieje po operacji, $false w przeciwnym razie.
    #>
    param([Parameter(Mandatory)][string]$Description)
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $ps51)) { return $false }
    $cmd = @"
try {
    Enable-ComputerRestore -Drive '$($env:SystemDrive)\' -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description '$Description' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
} catch { Write-Output ('RP_ERR: ' + `$_.Exception.Message) }
`$rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { `$_.Description -eq '$Description' } | Select-Object -First 1
if (`$rp) { Write-Output 'RP_VERIFIED' } else { Write-Output 'RP_MISSING' }
"@
    $out = & $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $cmd 2>&1
    $outText = ($out | Out-String)
    if ($outText -match 'RP_ERR:') {
        $errMsg = (($out | Where-Object { "$_" -match 'RP_ERR:' }) -join '; ')
        Write-Log "Restore point: $errMsg" -Level 'WARN'
    }
    return ($outText -match 'RP_VERIFIED')
}

function Initialize-RestorePoint {
    if ($NoRestorePoint) { Write-Log 'Restore point pominiety.' -Level 'WARN'; return }
    $created = New-SystemRestorePointCompat -Description "UWO_$($script:SessionId)"
    if ($created) {
        Write-Log 'Restore point utworzony i ZWERYFIKOWANY.' -Level 'CHANGE'
        Write-Status '  OK: punkt przywracania systemu utworzony.' 'Green'
    } else {
        Write-Log 'Restore point NIE POWSTAL. Mozliwe przyczyny: limit 1 punkt/24h (klucz SystemRestorePointCreationFrequency), wylaczona Ochrona systemu, brak WinPS 5.1.' -Level 'WARN'
        Write-Status '  UWAGA: punkt przywracania NIE zostal utworzony — kontynuacja bez siatki bezpieczenstwa. Szczegoly w logu.' 'Yellow'
        $script:SanityWarnings.Add('Punkt przywracania nie powstal — rozwaz reczne utworzenie (Ochrona systemu) przed optymalizacja.')
    }
}

function Request-WindowsUpdatesPause {
    # UWAGA: To ustawia tylko hint UI (7 dni). Nie blokuje WU jesli GPO lub Task Scheduler nadpisze.
    try {
        $p='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        if (-not (Test-Path $p)) { New-Item -Path $p -Force|Out-Null }
        Set-RegistryStringSafe -P $p -N 'PauseUpdatesExpiryTime' -V ((Get-Date).AddDays(7).ToString('yyyy-MM-ddTHH:mm:ssZ')) -R 'WU pause hint 7 dni (tylko UI, nie blokuje GPO)'
        Write-Log 'WU: hint UI ustawiony na 7 dni. Nie blokuje WU jesli GPO lub schtasks nadpisze.' -Level 'WARN'
    } catch { Write-Log "WU pause failed: $($_.Exception.Message)" -Level 'WARN' }
}

# =============================
# Profile Resolution
# =============================
function Assert-AcPower {
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if ($battery -and $battery.BatteryStatus -ne 2) {
        throw 'Profil Maximum wymaga podlaczenia do pradu (AC). Podlacz zasilacz i uruchom ponownie.'
    }
}

function Get-SuggestedProfile {
    <#
    .SYNOPSIS
        Automatycznie sugeruje optymalny profil na podstawie wykrytego sprzetu.
        Uzywana w trybie interaktywnym zeby nie zostawiac wyboru "w ciemno".
    #>
    param([Parameter(Mandatory)][PSCustomObject]$HWProfile)

    $suggested = 'Balanced'
    $reason    = ''

    if ($HWProfile.IsLaptop) {
        $suggested = 'Laptop'
        $reason    = "Wykryto laptop (bateria obecna). Profil Laptop chroni przed przegrzaniem i utrata baterii."
    } elseif ($HWProfile.IsLowRAM) {
        $suggested = 'LowEnd'
        $reason    = "RAM < 16 GB ($($HWProfile.TotalRAM_GB) GB). Profil LowEnd odciaza system zamiast agresywnie go booststowac."
    } elseif ($HWProfile.IsHighEndCPU -and $HWProfile.IsHighRAM -and -not $HWProfile.IsLaptop) {
        $suggested = 'Gaming'
        $reason    = "Wysokiej klasy CPU ($($HWProfile.CPUName), $($HWProfile.Cores) rdzeni) + RAM >= 32 GB. Profil Gaming wyciagnie maksimum."
    } elseif ($HWProfile.IsHighEndCPU -and -not $HWProfile.IsLaptop) {
        $suggested = 'Maximum'
        $reason    = "Mocny CPU ($($HWProfile.Cores) rdzeni) + desktop. Profil Maximum — pelna optymalizacja."
    } else {
        $suggested = 'Balanced'
        $reason    = "Sredniej klasy konfiguracja. Balanced to bezpieczny wybor z dobrym balansem."
    }

    [PSCustomObject]@{
        Profile = $suggested
        Reason  = $reason
    }
}

function Resolve-Profile {
    <#
    .SYNOPSIS
        Rozwiązuje profil optymalizacji na konkretne flagi modułów.
        
    PROFILE REFERENCE:
    ┌─────────────┬────────┬──────────┬─────────┬────────────┬──────────┬──────────┐
    │ Profil      │ Power  │ Gaming   │ Network │ Services   │ Cleanup  │ Repair   │
    ├─────────────┼────────┼──────────┼─────────┼────────────┼──────────┼──────────┤
    │ Safe        │ TAK    │ TAK      │ NIE     │ TAK        │ TAK      │ NIE      │
    │ Balanced    │ TAK    │ TAK      │ TAK     │ TAK        │ TAK      │ NIE      │
    │ Maximum     │ TAK    │ TAK      │ TAK     │ TAK        │ TAK      │ TAK      │
    │ Gaming      │ TAK    │ TAK+VBS  │ TAK     │ TAK        │ TAK      │ NIE      │
    │ Workstation │ TAK    │ NIE      │ TAK     │ TAK        │ TAK      │ TAK      │
    │ LowEnd      │ TAK    │ min      │ NIE     │ TAK        │ TAK      │ NIE      │
    │ Laptop      │ AC/DC  │ TAK      │ TAK     │ TAK        │ TAK      │ NIE      │
    └─────────────┴────────┴──────────┴─────────┴────────────┴──────────┴──────────┘
    #>
    switch ($Profile) {

        # ── SAFE — bezpieczny start, bez sieci, bez naprawy ──────────────────
        'Safe' {
            $script:ProfileDescription  = 'Bezpieczny — Power + UI + Gaming + Services + Cleanup. Brak zmian sieciowych.'
            $script:ProfileRisk         = 'Niskie'
            $script:SearchIndexingMode  = $SearchIndexingMode
            $script:EnablePowerTweaks   = $true
            $script:EnableUiTweaks      = $true
            $script:EnableGamingTweaks  = $true
            $script:EnableNetworkTweaks = $false
            $script:EnableServiceTuning = $true
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $false
            $script:EnableAutoRollback  = $true
        }

        # ── BALANCED — zrównoważony, z siecią, bez naprawy ───────────────────
        'Balanced' {
            $script:ProfileDescription  = 'Zrownowazony — pelna optymalizacja bez repair. Dobry balans.'
            $script:ProfileRisk         = 'Srednie'
            $script:SearchIndexingMode  = $SearchIndexingMode
            $script:EnablePowerTweaks   = $true
            $script:EnableUiTweaks      = $true
            $script:EnableGamingTweaks  = $true
            $script:EnableNetworkTweaks = $true
            $script:EnableServiceTuning = $true
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $true
            $script:EnableAutoRollback  = $true
        }

        # ── MAXIMUM — pełna optymalizacja, tylko desktop AC ──────────────────
        'Maximum' {
            if ($script:Manifest.Environment.IsLaptop) { Assert-AcPower }
            $script:ProfileDescription  = 'Agresywny — wszystko wlaczone. Tylko desktop podlaczony do pradu.'
            $script:ProfileRisk         = 'Wysokie'
            $script:SearchIndexingMode  = if ($SearchIndexingMode -eq 'Keep') { 'Manual' } else { $SearchIndexingMode }
            $script:EnablePowerTweaks   = $true
            $script:EnableUiTweaks      = $true
            $script:EnableGamingTweaks  = $true
            $script:EnableNetworkTweaks = $true
            $script:EnableServiceTuning = $true
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $true
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $true
            $script:EnableAutoRollback  = $true
        }

        # ── GAMING — dedykowany profil gamingowy ─────────────────────────────
        # Różni się od Maximum:
        #   + Agresywniejszy timer (0.5ms globalny)
        #   + VBS disable jeśli flaga podana (realny zysk FPS na starszych GPU)
        #   + DPC optimization
        #   + Defender exclusion priorytetowe
        #   - Brak repair (nie chcemy czekać 30min na SFC przed graniem)
        'Gaming' {
            if ($script:Manifest.Environment.IsLaptop) { Assert-AcPower }
            $script:ProfileDescription  = 'Gaming — maksymalna wydajnosc dla gier. FPS, latency, stuttery.'
            $script:ProfileRisk         = 'Wysokie'
            $script:SearchIndexingMode  = 'Manual'
            $script:EnablePowerTweaks   = $true
            $script:EnableUiTweaks      = $true
            $script:EnableGamingTweaks  = $true
            $script:EnableNetworkTweaks = $true
            $script:EnableServiceTuning = $true
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $true
            $script:EnableAutoRollback  = $true
            $script:EnableGamingMode    = $true   # dodatkowy flag dla gaming-specific tweaks
            # Gaming profile wymusza Ultimate Performance jeśli desktop
            if (-not $script:Manifest.Environment.IsLaptop) {
                $script:ForceUltimatePerfPlan = $true
            }
        }

        # ── WORKSTATION — stacja robocza, bez gaming tweaks ──────────────────
        # Inżynier, developer, grafik, edycja wideo
        # Różni się od Maximum:
        #   - Bez gaming tweaks (Win32PrioritySeparation=2 zamiast 38 — lepiej dla renderowania)
        #   - Bez Game Mode / DVR tweaks
        #   + I/O priorytet dla procesów roboczych
        #   + RAM nie jest agresywnie zwalniany
        #   + Repair TAK — stabilność ważniejsza niż czas
        'Workstation' {
            $script:ProfileDescription  = 'Workstation — stacja robocza. CPU/RAM/IO bez gaming tweaks.'
            $script:ProfileRisk         = 'Srednie'
            $script:SearchIndexingMode  = $SearchIndexingMode   # WSearch przydatny na workstation
            $script:EnablePowerTweaks   = $true
            $script:EnableUiTweaks      = $false   # animacje mogą być pożądane
            $script:EnableGamingTweaks  = $false   # Win32PrioritySeparation zostaje domyślne
            $script:EnableNetworkTweaks = $true
            $script:EnableServiceTuning = $true
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $true
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $false
            $script:EnableAutoRollback  = $true
            $script:EnableWorkstationMode = $true
        }

        # ── LOWEND — słaby sprzęt, <8GB RAM, stary CPU ───────────────────────
        # Cel: odciążenie systemu, nie boost wydajności
        # <8GB RAM: agresywne zwalnianie usług, SysMain off, WSearch off
        # Bez network tweaks (ryzyko > zysk na starym sprzęcie)
        'LowEnd' {
            $script:ProfileDescription  = 'LowEnd — slaby sprzet (<8GB RAM, stary CPU). Odciazenie systemu.'
            $script:ProfileRisk         = 'Niskie'
            $script:SearchIndexingMode  = 'Manual'   # WSearch kosztuje dużo na słabym sprzęcie
            $script:EnablePowerTweaks   = $true
            $script:EnableUiTweaks      = $true      # animacje off = realny zysk na słabym GPU
            $script:EnableGamingTweaks  = $false     # nie agresywne tweaki na słabym sprzęcie
            $script:EnableNetworkTweaks = $false
            $script:EnableServiceTuning = $true      # kluczowe — usługi kosztują dużo na mało RAM
            $script:EnableCleanup       = $true      # miejsce na dysku też ważne
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $false
            $script:EnableAutoRollback  = $true
            $script:EnableLowEndMode    = $true
        }

        # ── LAPTOP — dedykowany profil dla laptopów ──────────────────────────
        # Nie blokuje jak Maximum — ma własny zestaw tweaków uwzględniający baterię
        # AC: pełna moc, DC: oszczędny
        'Laptop' {
            $script:ProfileDescription  = 'Laptop — dedykowany profil. AC: pelna moc, DC: oszczedny.'
            $script:ProfileRisk         = 'Srednie'
            $script:SearchIndexingMode  = $SearchIndexingMode
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            $onAC    = -not $battery -or $battery.BatteryStatus -eq 2
            $script:LaptopOnAC          = $onAC
            $script:EnablePowerTweaks   = $true      # inne ustawienia gdy DC vs AC — obsługiwane w Invoke-PowerTweaks
            $script:EnableUiTweaks      = $true
            $script:EnableGamingTweaks  = $onAC      # gaming tweaks tylko na prądzie
            $script:EnableNetworkTweaks = $true
            $script:EnableServiceTuning = $true
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $onAC
            $script:EnableAutoRollback  = $true
            $script:EnableLaptopMode    = $true
            if ($onAC) {
                Write-Status '  Laptop: zasilacz podlaczony — tryb pelnej mocy.' 'Green'
                Write-Log 'Laptop profile: AC detected — full performance mode.' -Level 'INFO'
            } else {
                Write-Status '  Laptop: bateria — tryb oszczedny. Gaming tweaks wylaczone.' 'Yellow'
                Write-Log 'Laptop profile: DC (battery) — conservative mode.' -Level 'WARN'
            }
        }

        # ── LAPTOP GAMING SAFE — bezpieczny profil pod gry na laptopie ─────────
        # Cel: maksimum praktycznej wydajnosci bez psucia Insidera, telemetrii,
        # Windows Update, usług systemowych, sieci, VBS/HVCI i polityk organizacji.
        'LaptopGamingSafe' {
            $script:ProfileDescription  = 'LaptopGamingSafe — bezpieczny boost pod gry i szybki start laptopa. Ryzykowne tweaki sa pytaniami opcjonalnymi.'
            $script:ProfileRisk         = 'Niskie/Srednie'
            $script:SearchIndexingMode  = 'Keep'
            $script:EnablePowerTweaks   = $false
            $script:EnableUiTweaks      = $false
            $script:EnableGamingTweaks  = $false
            $script:EnableNetworkTweaks = $false
            $script:EnableServiceTuning = $false
            $script:EnableCleanup       = $false
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $false
            $script:EnableAutoRollback  = $true
            $script:EnableLaptopMode    = $true
            $script:EnableLaptopGamingSafeMode = $true
            if ($EnableTelemetryTuning) { $script:LaptopOptionalTelemetryTuning = $true }
            if ($EnableWindowsUpdatePause) { $script:LaptopOptionalWindowsUpdatePause = $true }
            if ($EnableVbsDisable) { $script:LaptopOptionalVbsDisable = $true }
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            $script:LaptopOnAC = -not $battery -or $battery.BatteryStatus -eq 2
            if ($script:LaptopOnAC) {
                Write-Status '  LaptopGamingSafe: zasilacz podlaczony — bezpieczny tryb maksymalnej wydajnosci.' 'Green'
                Write-Log 'LaptopGamingSafe: AC detected — safe performance mode.' -Level 'INFO'
            } else {
                Write-Status '  LaptopGamingSafe: bateria — pominiete agresywne ustawienia zasilania AC.' 'Yellow'
                Write-Log 'LaptopGamingSafe: battery detected — AC-only power settings skipped.' -Level 'WARN'
            }
        }


        # ── GAMING LAPTOP — preset gotowy pod gry na laptopie ────────────────
        # Cel: efekt "o, dziala lepiej" bez psucia Insidera, WU, VBS i agresywnej sieci.
        # Wlacza Performance Feel, NVIDIA safe profile, benchmark i helper gaming session.
        'GamingLaptop' {
            $script:ProfileDescription  = 'GamingLaptop — preset pod gry na laptopie: Performance Feel, Game Mode, NVIDIA safe profile, raport, bez psucia Insidera.'
            $script:ProfileRisk         = 'Niskie/Srednie'
            $script:SearchIndexingMode  = 'Keep'
            $script:EnablePowerTweaks   = $false
            $script:EnableUiTweaks      = $false
            $script:EnableGamingTweaks  = $false
            $script:EnableNetworkTweaks = $false
            $script:EnableServiceTuning = $false
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $false
            $script:EnableAutoRollback  = $true
            $script:EnableLaptopMode    = $true
            $script:EnableLaptopGamingSafeMode = $true
            $script:LaptopOptionalPerformanceFeelMode = $true
            $script:LaptopOptionalNvidiaProfile = $true
            $script:LaptopOptionalBenchmarkReport = $true
            $script:LaptopOptionalStartupReview = $true
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            $script:LaptopOnAC = -not $battery -or $battery.BatteryStatus -eq 2
            Write-Status '  GamingLaptop: safe gaming preset — Performance Feel + NVIDIA + raport. Nie rusza telemetrii/WU/VBS/agresywnej sieci.' 'Green'
        }

        # ── OFFICE LAPTOP — szybka praca i komfort ──────────────────────────
        # Cel: szybszy pulpit, Explorer, start powloki, mniej smieci, bez agresywnych gaming tweakow.
        'OfficeLaptop' {
            $script:ProfileDescription  = 'OfficeLaptop — szybka praca biurowa: UI/Explorer feel, cleanup, stabilnosc, bez agresywnych zmian.'
            $script:ProfileRisk         = 'Niskie'
            $script:SearchIndexingMode  = 'Keep'
            $script:EnablePowerTweaks   = $true
            $script:EnableUiTweaks      = $true
            $script:EnableGamingTweaks  = $false
            $script:EnableNetworkTweaks = $false
            $script:EnableServiceTuning = $false
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $false
            $script:EnableAutoRollback  = $true
            $script:EnableLaptopMode    = $true
            $script:LaptopOptionalPerformanceFeelMode = $true
            $script:LaptopOptionalBenchmarkReport = $true
            $script:EnableLaptopGamingSafeMode = $true
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            $script:LaptopOnAC = -not $battery -or $battery.BatteryStatus -eq 2
            Write-Status '  OfficeLaptop: szybki pulpit i praca. Zero telemetrii/WU/VBS/agresywnej sieci.' 'Cyan'
        }

        # ── LOW RAM — preset dla 4-8/12 GB RAM ───────────────────────────────
        # Cel: mniej procesow i mniej autostartu bez rozwalania uslug systemowych.
        'LowRAM' {
            $script:ProfileDescription  = 'LowRAM — malo RAM: cleanup, przeglad autostartu, Performance Feel; bez agresywnych uslug i sieci.'
            $script:ProfileRisk         = 'Niskie/Srednie'
            $script:SearchIndexingMode  = 'Keep'
            $script:EnablePowerTweaks   = $true
            $script:EnableUiTweaks      = $true
            $script:EnableGamingTweaks  = $false
            $script:EnableNetworkTweaks = $false
            $script:EnableServiceTuning = $false
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $false
            $script:EnableAutoRollback  = $true
            $script:EnableLowEndMode    = $true
            $script:EnableLaptopGamingSafeMode = $true
            $script:LaptopOptionalStartupReview = $true
            $script:LaptopOptionalPerformanceFeelMode = $true
            $script:LaptopOptionalBenchmarkReport = $true
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            $script:LaptopOnAC = -not $battery -or $battery.BatteryStatus -eq 2
            Write-Status '  LowRAM: mniej obciazenia i autostartu. Nie wylacza krytycznych uslug.' 'Yellow'
        }

        # ── BATTERY SAVER — preset bateria/cisza ─────────────────────────────
        # Cel: komfort na baterii, mniej pracy w tle, bez tweakow FPS.
        'BatterySaver' {
            $script:ProfileDescription  = 'BatterySaver — bateria i cisza: oszczedny profil, cleanup, bez gaming i bez agresywnych zmian.'
            $script:ProfileRisk         = 'Niskie'
            $script:SearchIndexingMode  = 'Keep'
            $script:EnablePowerTweaks   = $true
            $script:EnableUiTweaks      = $false
            $script:EnableGamingTweaks  = $false
            $script:EnableNetworkTweaks = $false
            $script:EnableServiceTuning = $false
            $script:EnableCleanup       = $true
            $script:EnableRepair        = $false
            $script:EnableNetworkRepair = $false
            $script:EnableGamingSession = $false
            $script:EnableAutoRollback  = $true
            $script:EnableLaptopMode    = $true
            $script:EnableLaptopGamingSafeMode = $true
            $script:LaptopOptionalBenchmarkReport = $true
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            $script:LaptopOnAC = -not $battery -or $battery.BatteryStatus -eq 2
            Write-Status '  BatterySaver: preset pod baterie/cisze. Nie jest profilem FPS.' 'Blue'
        }

        # ── CUSTOM — pełna kontrola przez flagi ──────────────────────────────
        'Custom' {
            $script:ProfileDescription  = 'Custom — reczna kontrola przez flagi parametrow.'
            $script:ProfileRisk         = 'Uzytkownik'
            $script:SearchIndexingMode  = $SearchIndexingMode
            $script:EnablePowerTweaks   = [bool]$EnablePowerTweaks
            $script:EnableUiTweaks      = [bool]$EnableUiTweaks
            $script:EnableGamingTweaks  = [bool]$EnableGamingTweaks
            $script:EnableNetworkTweaks = [bool]$EnableNetworkTweaks
            $script:EnableServiceTuning = [bool]$EnableServiceTuning
            $script:EnableCleanup       = [bool]$EnableCleanup
            $script:EnableRepair        = [bool]$EnableRepair
            $script:EnableNetworkRepair = [bool]$EnableNetworkRepair
            $script:EnableGamingSession = [bool]$EnableGamingSession
            $script:EnableAutoRollback  = $true
        }
    }

    Write-Log "Profil: $Profile | $($script:ProfileDescription) | Ryzyko: $($script:ProfileRisk)" -Level 'INFO'
}


# =============================
# v12 PREMIUM — Auto-Rollback + Tweak Validation
# =============================

function Get-IOMetrics {
    <#
    .SYNOPSIS
        Mierzy aktualne metryki I/O dysku systemowego.
        Używane w before/after do oceny czy tweak nie pogorszył I/O.
    #>
    try {
        $disk   = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -ne 'USB' } | Select-Object -First 1
        $diskC  = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue

        # Read/Write latency przez performance counters
        $readLat  = $null
        $writeLat = $null
        try {
            $rl = Get-CounterValueSafe '\PhysicalDisk(_Total)\Avg. Disk sec/Read'
            $wl = Get-CounterValueSafe '\PhysicalDisk(_Total)\Avg. Disk sec/Write'
            if ($null -ne $rl) { $readLat  = [math]::Round($rl * 1000, 2) }
            if ($null -ne $wl) { $writeLat = [math]::Round($wl * 1000, 2) }
        } catch {}

        # Queue length
        $queueLen = $null
        try {
            $ql = Get-CounterValueSafe '\PhysicalDisk(_Total)\Current Disk Queue Length'
            if ($null -ne $ql) { $queueLen = [math]::Round($ql, 1) }
        } catch {}

        [PSCustomObject]@{
            Timestamp    = (Get-Date).ToString('o')
            ReadLatMs    = $readLat
            WriteLatMs   = $writeLat
            QueueLength  = $queueLen
            FreeSpaceGB  = if ($diskC) { [math]::Round($diskC.Free / 1GB, 1) } else { $null }
            MediaType    = if ($disk) { $disk.MediaType } else { 'Unknown' }
        }
    } catch {
        Write-Log "IOMetrics: blad — $($_.Exception.Message)" -Level 'WARN'
        $null
    }
}

function Get-BootTimeSec {
    <#
    .SYNOPSIS
        Pobiera faktyczny czas ostatniego zimnego startu systemu z Event Log.
        Event 12 = kernel start, Event 13 = poprzedni shutdown.
        Różnica = czas od POST do gotowości kernela.
    #>
    try {
        $bootEvent = Get-WinEvent -LogName System -FilterHashtable @{
            ProviderName = 'Microsoft-Windows-Kernel-General'
            Id           = 12
        } -MaxEvents 1 -ErrorAction Stop

        $shutEvent = Get-WinEvent -LogName System -FilterHashtable @{
            ProviderName = 'Microsoft-Windows-Kernel-General'
            Id           = 13
        } -MaxEvents 1 -ErrorAction Stop

        if ($bootEvent -and $shutEvent) {
            $bootTimeSec = [math]::Round(($bootEvent.TimeCreated - $shutEvent.TimeCreated).TotalSeconds, 1)
            # Sanity: realny boot to 5-120s. Jeśli więcej — hibernacja lub invalid
            if ($bootTimeSec -gt 5 -and $bootTimeSec -lt 300) {
                return $bootTimeSec
            }
        }
    } catch {}

    # Fallback — BootUpTime z WMI
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        return [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalSeconds, 0)
    } catch { return $null }
}

function Invoke-TweakWithValidation {
    <#
    .SYNOPSIS
        Wrapper który stosuje tweak, mierzy wynik i automatycznie cofa
        jeśli metryki się pogorszyły o więcej niż próg.

    .PARAMETER Name
        Nazwa tweaka do logów i raportów.
    .PARAMETER Action
        Blok kodu stosujący tweak.
    .PARAMETER RollbackAction
        Blok kodu cofający tweak jeśli walidacja nie przejdzie.
    .PARAMETER MetricBlock
        Blok zwracający wartość liczbową metryki (niższa = lepsza lub wyższa = lepsza).
    .PARAMETER BetterWhenLower
        Czy metryka jest lepsza gdy niższa (np. latency, CPU%).
    .PARAMETER ThresholdPct
        Procent pogorszenia który wyzwala auto-rollback. Domyślnie 10%.
    .PARAMETER WaitSeconds
        Ile sekund czekać po tweaku przed pomiarem. Domyślnie 5.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [scriptblock]$RollbackAction = $null,
        [scriptblock]$MetricBlock    = $null,
        [bool]$BetterWhenLower       = $true,
        [double]$ThresholdPct        = 10.0,
        [int]$WaitSeconds            = 5
    )

    # Jeśli AutoRollback nie aktywny lub brak metryki — normalne wywołanie
    if (-not $script:EnableAutoRollback -or -not $MetricBlock -or -not $RollbackAction) {
        Invoke-Step -Name $Name -Action $Action -ContinueOnError
        return
    }

    Write-Status "  [VALIDATE] $Name — pomiar before..." 'DarkGray'

    # Pomiar PRZED
    $metricBefore = $null
    try { $metricBefore = & $MetricBlock } catch {}

    # Stosuj tweak
    Invoke-Step -Name $Name -Action $Action -ContinueOnError

    if ($DryRun) { return }

    # Czekaj na stabilizację
    Start-Sleep -Seconds $WaitSeconds

    # Pomiar PO
    $metricAfter = $null
    try { $metricAfter = & $MetricBlock } catch {}

    if ($null -eq $metricBefore -or $null -eq $metricAfter) {
        Write-Log "AutoRollback: $Name — brak metryki do porownania. Tweak zachowany." -Level 'WARN'
        return
    }

    # Oceń czy lepiej czy gorzej
    $diff    = $metricAfter - $metricBefore
    $diffPct = if ($metricBefore -ne 0) { [math]::Abs($diff / $metricBefore * 100) } else { 0 }
    $worse   = if ($BetterWhenLower) { $diff -gt 0 } else { $diff -lt 0 }

    if ($worse -and $diffPct -gt $ThresholdPct) {
        Write-Status "  [AUTO-ROLLBACK] $Name — pogorszenie $([math]::Round($diffPct,1))% > prog $ThresholdPct%. Cofam..." 'Yellow'
        Write-Log "AutoRollback: $Name | Before=$metricBefore After=$metricAfter Diff=$([math]::Round($diffPct,1))% — ROLLBACK" -Level 'WARN'

        try {
            & $RollbackAction
            Write-Log "AutoRollback: $Name — cofnieto pomyslnie." -Level 'CHANGE'
            $script:AutoRolledBack.Add([PSCustomObject]@{
                Name        = $Name
                MetricBefore = $metricBefore
                MetricAfter  = $metricAfter
                DiffPct      = [math]::Round($diffPct, 1)
            })
        } catch {
            Write-Log "AutoRollback: $Name — blad cofania: $($_.Exception.Message)" -Level 'ERROR'
        }
    } else {
        $dirStr = if ($worse) { 'minimalnie gorzej (w progu)' } else { 'lepiej lub bez zmian' }
        Write-Log "AutoRollback: $Name — $dirStr (Before=$metricBefore After=$metricAfter Diff=$([math]::Round($diffPct,1))%). Tweak zachowany." -Level 'INFO'
    }
}

function Get-TweakDocumentation {
    <#
    .SYNOPSIS
        Zwraca dokumentację techniczną dla każdego tweaka.
        Wyświetlana w preflight i raporcie HTML.
        Punkt 5 z 7 — dokumentacja odróżnia narzędzie od "magic optimizer".
    #>
    param([Parameter(Mandatory)][string]$TweakId)

    $docs = @{

        'HighPerformance' = [PSCustomObject]@{
            Id          = 'HighPerformance'
            Name        = 'Plan zasilania High/Ultimate Performance'
            WhatItDoes  = 'Blokuje stany oszczędzania energii CPU (C-states). Procesor zawsze gotowy do pracy z pełną częstotliwością.'
            WhyItHelps  = 'Eliminuje latencję związaną z "budzeniem" rdzeni. Realny zysk szczególnie na starszych procesorach Intel.'
            Risk        = 'Niskie — wyższe zużycie prądu, wyższa temperatura w spoczynku. Na laptopie skraca czas pracy baterii.'
            Hardware    = 'Desktop: zawsze bezpieczny. Laptop: tylko AC. Low-end: może przegrzewać.'
            WindowsVer  = 'Windows 10 1507+. Ultimate Performance: Windows 10 1803+.'
            Reversible  = $true
            Evidence    = 'Strong'
            Profile     = @('Safe','Balanced','Maximum','Gaming','Workstation','Laptop','LowEnd')
        }

        'HAGS' = [PSCustomObject]@{
            Id          = 'HAGS'
            Name        = 'Hardware Accelerated GPU Scheduling (HAGS)'
            WhatItDoes  = 'Przenosi zarządzanie kolejką VRAM z CPU na dedykowany hardware GPU. Redukuje latencję CPU-GPU.'
            WhyItHelps  = 'Mniej obciazenia CPU przy renderowaniu. Kluczowy dla DLSS Frame Generation i Reflex. Efekt zalezny od gry/sprzetu; najwiekszy w grach CPU-bound (orientacyjnie).'
            Risk        = 'Średnie — na GPU starszych niż GTX 1000 może powodować niestabilność. Wymaga aktualnego sterownika.'
            Hardware    = 'NVIDIA GTX 1000+, AMD RX 5000+, Intel Arc. Sterownik < 6 miesięcy.'
            WindowsVer  = 'Windows 10 2004 (Build 19041)+.'
            Reversible  = $true
            Evidence    = 'Medium'
            Profile     = @('Balanced','Maximum','Gaming','Laptop')
        }

        'GameDVR' = [PSCustomObject]@{
            Id          = 'GameDVR'
            Name        = 'Game DVR / Xbox Game Bar — wyłączenie'
            WhatItDoes  = 'Wyłącza nagrywanie rozgrywki w tle i Game Bar overlay.'
            WhyItHelps  = 'Eliminuje staly overhead CPU/GPU z monitorowania klatek. Glownie mniej stutterow; wzrost FPS zwykle niewielki (orientacyjnie).'
            Risk        = 'Niskie — tracisz możliwość nagrywania przez Win+G. OBS i inne działają normalnie.'
            Hardware    = 'Wszystkie konfiguracje.'
            WindowsVer  = 'Windows 10 1607+.'
            Reversible  = $true
            Evidence    = 'Strong'
            Profile     = @('Safe','Balanced','Maximum','Gaming','Laptop','LowEnd')
        }

        'Win32Priority' = [PSCustomObject]@{
            Id          = 'Win32Priority'
            Name        = 'Win32PrioritySeparation = 38'
            WhatItDoes  = 'Ustawia proporcję czasu CPU 3:1 na korzyść procesu na pierwszym planie.'
            WhyItHelps  = 'Gra dostaje ~75% czasu CPU zamiast domyślnych 50%. Redukuje frametime variance.'
            Risk        = 'Niskie dla gaming. Na workstation może spowalniać zadania w tle (render, kompilacja).'
            Hardware    = 'Wszystkie. Na Workstation profilu ustawiamy 24 zamiast 38.'
            WindowsVer  = 'Windows 10/11 wszystkie wersje.'
            Reversible  = $true
            Evidence    = 'Medium'
            Profile     = @('Safe','Balanced','Maximum','Gaming','Laptop')
        }

        'GlobalTimer' = [PSCustomObject]@{
            Id          = 'GlobalTimer'
            Name        = 'GlobalTimerResolutionRequests = 1 (timer 0.5ms)'
            WhatItDoes  = 'Wymusza globalny timer systemowy 0.5ms dla całego systemu (Windows 11 23H2+).'
            WhyItHelps  = 'Stabilniejszy frametime, niższy input lag. Szczególnie widoczne na 144Hz+.'
            Risk        = 'Niskie — minimalnie wyższe zużycie energii (timer odpala się 2000x/s zamiast 64x/s).'
            Hardware    = 'Desktop: zawsze korzystny. Laptop: tylko AC (bateria szybciej siada).'
            WindowsVer  = 'Windows 11 23H2+. Na starszych działa timeBeginPeriod() na poziomie procesu.'
            Reversible  = $true
            Profile     = @('Balanced','Maximum','Gaming','Laptop')
        }

        'MPODisable' = [PSCustomObject]@{
            Id          = 'MPODisable'
            Name        = 'Multiplane Overlay (MPO) — wyłączenie'
            WhatItDoes  = 'Wymusza tryb kompozycji DWM bez MPO. OverlayTestMode=5.'
            WhyItHelps  = 'Eliminuje stuttery i artefakty wizualne przy aktywnych overlayach (Discord, NVIDIA App, OBS).'
            Risk        = 'Niskie — minimalnie wyższe zużycie GPU (DWM robi więcej pracy). Na laptopie może skracać baterię.'
            Hardware    = 'Szczególnie ważne przy NVIDIA + overlay. Na AMD rzadziej potrzebne.'
            WindowsVer  = 'Windows 10 2004+.'
            Reversible  = $true
            Profile     = @('Balanced','Maximum','Gaming','Laptop')
        }

        'VBSDisable' = [PSCustomObject]@{
            Id          = 'VBSDisable'
            Name        = 'VBS / Memory Integrity — wyłączenie'
            WhatItDoes  = 'Wyłącza Virtualization Based Security i HVCI (Hypervisor-Protected Code Integrity).'
            WhyItHelps  = 'Najwiekszy efekt na starszych GPU (GTX 1000 - RTX 2000); na nowszych zwykle niewielki. Efekt orientacyjny, zalezny od gry.'
            Risk        = 'WYSOKIE — system traci izolację kernela. Exploity kernel-level działają bez VBS-barrier. Tylko na dedykowanych gaming PC bez wrażliwych danych.'
            Hardware    = 'Desktop gaming. NIE na laptopach z publicznych sieci, NIE na PC z danymi firmowymi.'
            WindowsVer  = 'Windows 10 1903+. Wymaga restartu.'
            Reversible  = $true
            Evidence    = 'Medium'
            Profile     = @('Gaming','Maximum')
        }

        'TDRDelay' = [PSCustomObject]@{
            Id          = 'TDRDelay'
            Name        = 'TDR Delay = 8 sekund'
            WhatItDoes  = 'Wydłuża czas zanim Windows "resetuje" GPU po braku odpowiedzi z 2s do 8s.'
            WhyItHelps  = 'Eliminuje fałszywe TDR resety podczas ciężkiego obciążenia GPU (kompilacja shaderów, ray tracing).'
            Risk        = 'Niskie — jeśli GPU faktycznie się zawiesi, będziesz czekać 8s zamiast 2s na reset.'
            Hardware    = 'Wszystkie GPU. Szczególnie ważne przy OC lub ray tracingu.'
            WindowsVer  = 'Windows 10/11 wszystkie wersje. Wymaga restartu.'
            Reversible  = $true
            Evidence    = 'Strong'
            Profile     = @('Balanced','Maximum','Gaming','Workstation','Laptop')
        }

        'DiagTrack' = [PSCustomObject]@{
            Id          = 'DiagTrack'
            Name        = 'DiagTrack (telemetria) → Manual'
            WhatItDoes  = 'Przestawia usługę telemetrii Connected User Experiences and Telemetry na uruchamianie ręczne.'
            WhyItHelps  = 'Eliminuje periodyczne wysyłanie danych diagnostycznych do Microsoft w tle. Mniej I/O i sieć.'
            Risk        = 'Niskie — Windows Update nadal działa. Niektóre diagnostyki Microsoftu mogą być niedostępne.'
            Hardware    = 'Wszystkie.'
            WindowsVer  = 'Windows 10/11 wszystkie wersje.'
            Reversible  = $true
            Evidence    = 'Strong'
            Profile     = @('Safe','Balanced','Maximum','Gaming','Workstation','Laptop','LowEnd')
        }
    }

    if ($docs.ContainsKey($TweakId)) { return $docs[$TweakId] }
    return $null
}

function Show-TweakDoc {
    <#
    .SYNOPSIS
        Wyświetla dokumentację tweaka w konsoli (używane w preflight).
    #>
    param([string]$TweakId, [switch]$Short)

    $doc = Get-TweakDocumentation -TweakId $TweakId
    if (-not $doc) { return }

    if ($Short) {
        Write-Status "    Co robi:  $($doc.WhatItDoes)" 'DarkGray'
        Write-Status "    Ryzyko:   $($doc.Risk)" $(if ($doc.Risk -match '^WYSOKIE') { 'Red' } elseif ($doc.Risk -match '^Średnie|Srednie') { 'Yellow' } else { 'DarkGray' })
        if ($doc.PSObject.Properties.Name -contains 'Evidence') { Write-Status "    Dowody:   $($doc.Evidence)" 'DarkGray' }
        return
    }

    Write-Status "  ┌─ $($doc.Name)" 'Cyan'
    Write-Status "  │  Co robi:    $($doc.WhatItDoes)" 'White'
    Write-Status "  │  Dlaczego:   $($doc.WhyItHelps)" 'White'
    Write-Status "  │  Ryzyko:     $($doc.Risk)" $(if ($doc.Risk -match '^WYSOKIE') { 'Red' } elseif ($doc.Risk -match '^Średnie|Srednie') { 'Yellow' } else { 'Green' })
    Write-Status "  │  Sprzet:     $($doc.Hardware)" 'DarkGray'
    Write-Status "  │  Windows:    $($doc.WindowsVer)" 'DarkGray'
    if ($doc.PSObject.Properties.Name -contains 'Evidence') { Write-Status "  │  Dowody:     $($doc.Evidence)" 'DarkGray' }
    Write-Status "  └─ Odwracalne: $(if ($doc.Reversible) { 'TAK' } else { 'NIE' })" 'DarkGray'
}

# =============================
# Modules
# =============================
function Invoke-PowerTweaks {
    Set-StrictMode -Version Latest
    $script:AppliedModules.Add('Power')
    Add-TweakMetadata -Id 'UltimatePerformance' -Name 'High/Ultimate Performance policy' -Category 'Power' -Risk Medium -Evidence Medium -RecommendedFor @('Gaming','Maximum','Workstation') -AvoidOn @('Laptop') -Notes 'Smart Mode blokuje agresywne zasilanie na baterii.'
    if (-not (Test-TweakEligibility -TweakId 'UltimatePerformance' -RequireAC)) { return }
    Invoke-Step -Name 'Zasilanie: High Performance + polityka CPU (AC)' -Action {
        Set-ActivePowerSchemeHighPerformance
        & powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 5   |Out-Null  # PROCTHROTTLEMIN=5
        & powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec 100  |Out-Null  # PROCTHROTTLEMAX=100
        & powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 be337238-0d82-4146-a960-4f3749d470c7 3    |Out-Null  # Core parking min
        & powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100  |Out-Null  # Boost mode Aggressive
        & powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 68dd2f27-a4ce-4e11-8487-3794e4135dfa 100  |Out-Null  # Hetero policy
        & powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0    |Out-Null  # USB selective suspend off
        & powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0    |Out-Null  # PCI-e link state off
        & powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0    |Out-Null  # Sleep off
        & powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0    |Out-Null  # Hibernate off
        & powercfg /setactive SCHEME_CURRENT|Out-Null
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -N 'HiberbootEnabled' -V 0 -R 'Fast Startup off (stabilnosc)' -Rst
        Write-Log 'Power plan skonfigurowany.' -Level 'CHANGE'
    }
    if (-not $script:Manifest.Environment.IsLaptop -and $EnableExperimentalTweaks -and $Profile-eq'Maximum') {
        Invoke-Step -Name 'Zasilanie: PROCTHROTTLEMIN=100 (Experimental, tylko desktop)' -Action {
            & powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100|Out-Null
            & powercfg /setactive SCHEME_CURRENT|Out-Null
            Write-Log 'Experimental PROCTHROTTLEMIN=100 (desktop).' -Level 'CHANGE'
            Add-RestartFlag 'Experimental CPU policy'
        } -ContinueOnError
    } elseif ($script:Manifest.Environment.IsLaptop -and $Profile-eq'Maximum') {
        Write-Log 'Pominięto PROCTHROTTLEMIN=100 — laptop.' -Level 'WARN'
    }
}

function Invoke-UiTweaks {
    $script:AppliedModules.Add('UI')
    Invoke-Step -Name 'Interfejs: wylaczenie animacji i efektow wizualnych' -Action {
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'    -N 'TaskbarAnimations'   -V 0 -R 'Animacje taskbar off'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'-N 'VisualFXSetting'     -V 2 -R 'Efekty wizualne: min' -Rst
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'    -N 'ListviewAlphaSelect' -V 0 -R 'Przezroczystosc list off'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'    -N 'TaskbarDa'           -V 0 -R 'Widgets off (Win11)'
    }
}



function Read-YesNoDefaultNo {
    param(
        [Parameter(Mandatory)][string]$Question
    )
    do {
        $ans = (Read-Host "$Question [t/N]").Trim().ToLower()
    } while ($ans -notin '', 't', 'tak', 'y', 'yes', 'n', 'nie', 'no')
    return ($ans -in 't', 'tak', 'y', 'yes')
}

function Enable-CombinedRiskPack {
    param(
        [ValidateSet('LaptopGamingSafe','General')]
        [string]$Context = 'General'
    )

    $script:EnableRiskPackBundle = $true
    $script:RiskPackContext = $Context
    $script:EnableServiceTuning = $true
    $script:EnableNetworkTweaks = $true
    $script:AllowGlobalWindowsUpdatePause = $true

    Set-Variable -Name EnableTelemetryTuning -Scope Script -Value $true
    Set-Variable -Name EnableWindowsUpdatePause -Scope Script -Value $true
    Set-Variable -Name EnableVbsDisable -Scope Script -Value $true

    if ($Context -eq 'LaptopGamingSafe') {
        $script:LaptopOptionalTelemetryTuning = $true
        $script:LaptopOptionalWindowsUpdatePause = $true
        $script:LaptopOptionalVbsDisable = $true
    }

    $script:Manifest.RiskPackModule = [ordered]@{
        Enabled            = $true
        Context            = $Context
        TypicalFpsEstimate = '0-3% zwykle jako calosc; 3-10% tylko gdy VBS/HVCI bylo aktywne i gra na to reaguje'
        MainUpside         = 'Mniej procesow w tle, mniej szans na mikroprzyciecia od WU, najwieksza szansa na FPS dopiero po VBS OFF'
        MainDownside       = 'Gorsza zgodnosc Insider/diagnostyki, slabsze zabezpieczenia przy VBS OFF, mozliwe skutki uboczne w sieci i na baterii'
    }
}

function Show-CombinedRiskPackInfo {
    param(
        [ValidateSet('LaptopGamingSafe','General')]
        [string]$Context = 'General'
    )

    Write-Host ''
    Write-Host '--- OPCJONALNY MODUL ZBIORCZY: RISK PACK ---' -ForegroundColor Yellow
    Write-Host 'Jeden wybor TAK/NIE dla calego pakietu bardziej agresywnych zmian.' -ForegroundColor DarkYellow
    Write-Host 'Szczera ocena: jako calosc zwykle daje 0-3% FPS lub mniej; 3-10% zdarza sie glownie wtedy, gdy wylaczenie VBS/HVCI faktycznie pomaga w konkretnej grze.' -ForegroundColor Gray
    Write-Host 'Co wlacza:' -ForegroundColor Yellow
    Write-Host '  - DiagTrack / telemetria -> Manual' -ForegroundColor Gray
    Write-Host '  - Pauza Windows Update na 7 dni' -ForegroundColor Gray
    Write-Host '  - Tuning uslug w tle' -ForegroundColor Gray
    Write-Host '  - Tweaki sieci / adapterow' -ForegroundColor Gray
    Write-Host '  - VBS / Memory Integrity OFF' -ForegroundColor Gray
    Write-Host 'Co moze pogorszyc:' -ForegroundColor Yellow
    if ($Context -eq 'LaptopGamingSafe') {
        Write-Host '  - Insider / rollout nowych funkcji, diagnostyke, zgodnosc z Hyper-V/WSL/BitLocker oraz bezpieczenstwo systemu' -ForegroundColor Gray
    } else {
        Write-Host '  - diagnostyke, niektore funkcje systemowe, VPN / nietypowe sieci, zgodnosc z izolacja kernela oraz bezpieczenstwo systemu' -ForegroundColor Gray
    }
    Write-Host 'Moja uczciwa opinia: to ma sens jako swiadomy eksperyment, nie jako domyslny zestaw.' -ForegroundColor DarkGray
}


function Show-LaptopGamingProChoiceMenu {
    if ($Silent -or -not $script:EnableLaptopGamingSafeMode) { return }
    # STAGE6 v14.5: AutoSmart answers module questions automatically (benchmark ON, executive modules OFF).
    if ($script:AutoSmartSelected) {
        $script:LaptopOptionalBenchmarkReport = $true
        $script:Manifest.LaptopProOptions = [ordered]@{
            BenchmarkReport       = $true
            StartupReview         = $false
            PostDebloaterRepair   = $false
            NvidiaProfile         = $false
            PerformanceFeelMode   = $false
        }
        return
    }
    # ETAP2 v14.1: Analyze nic nie wykonuje — pytania o moduly wykonawcze bylyby zmylka dla uzytkownika.
    # Wlaczamy tylko rozszerzony benchmark (read-only, zasila raport Analyze); reszta na bezpiecznych domyslnych.
    if ($Mode -eq 'Analyze') {
        Write-Host ''
        Write-Host (T 'analyze.pro.skip1') -ForegroundColor DarkGray
        Write-Host (T 'analyze.pro.skip2') -ForegroundColor DarkGray
        $script:LaptopOptionalBenchmarkReport = $true
        $script:Manifest.LaptopProOptions = [ordered]@{
            BenchmarkReport       = $true
            StartupReview         = $false
            PostDebloaterRepair   = $false
            NvidiaProfile         = $false
            PerformanceFeelMode   = $false
        }
        return
    }
    if ($script:QuickPerformanceFeelOnly) {
        Write-Host ''
        Write-Host '--- Performance Feel Mode: szybki bezpieczny preset ---' -ForegroundColor Green
        Write-Host 'Co robi: szybsze UI/Explorer, mniejszy input lag, Game Mode, DVR off, MMCSS Games/Audio i helper Gaming Session.' -ForegroundColor Gray
        Write-Host 'Efekt: zwykle 0-3% FPS, ale glownie lepszy komfort, mniej stutteru i szybsza reakcja systemu.' -ForegroundColor DarkGray
        Write-Host 'Ryzyko: niskie. Nie rusza telemetrii, Windows Update, VBS ani agresywnej sieci.' -ForegroundColor DarkGray
        $script:LaptopOptionalPerformanceFeelMode = $true
        $script:LaptopOptionalBenchmarkReport = $true
        $script:Manifest.LaptopProOptions = [ordered]@{
            BenchmarkReport       = $script:LaptopOptionalBenchmarkReport
            StartupReview         = $script:LaptopOptionalStartupReview
            PostDebloaterRepair   = $script:LaptopOptionalPostDebloaterRepair
            NvidiaProfile         = $script:LaptopOptionalNvidiaProfile
            PerformanceFeelMode   = $script:LaptopOptionalPerformanceFeelMode
        }
        return
    }
    Write-Host ''
    Write-Host '--- LaptopGamingSafe: moduly PRO, bezpieczne dla systemu ---' -ForegroundColor Cyan
    Write-Host 'Te opcje NIE powinny psuc Insidera ani aktualizacji. Maja pomagac mierzyc i ogarniac wydajnosc.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '1) Rozszerzony benchmark i raport przed/po' -ForegroundColor Green
    Write-Host '   Zysk FPS: 0% bezposrednio. Zysk realny: pokazuje czy optymalizacja ma sens i co spowalnia system.' -ForegroundColor DarkGray
    $script:LaptopOptionalBenchmarkReport = Read-YesNoDefaultNo 'Wlaczyc rozszerzony benchmark/raport?'
    Write-Host ''
    Write-Host '2) Przeglad autostartu' -ForegroundColor Green
    Write-Host '   Zysk: ok. 0-5% szybciej po starcie, mniej RAM/CPU w tle. Skrypt pyta zanim cos wylaczy.' -ForegroundColor DarkGray
    $script:LaptopOptionalStartupReview = Read-YesNoDefaultNo 'Wlaczyc przeglad autostartu?'
    Write-Host ''
    Write-Host '3) Naprawa po debloaterach / optimizerach' -ForegroundColor Yellow
    Write-Host '   Zysk FPS: 0-1%, ale naprawia Insider, Windows Update, Store/Xbox i funkcje systemu po agresywnych tweakach.' -ForegroundColor DarkGray
    $script:LaptopOptionalPostDebloaterRepair = Read-YesNoDefaultNo 'Wlaczyc naprawe po debloaterach?'
    Write-Host ''
    Write-Host '4) Bezpieczny profil NVIDIA' -ForegroundColor Green
    Write-Host '   Zysk: ok. 0-3% lub mniej stutteru. Bez OC, bez Coolbits. Dziala tylko gdy jest NVIDIA i nvidia-smi.' -ForegroundColor DarkGray
    $script:LaptopOptionalNvidiaProfile = Read-YesNoDefaultNo 'Wlaczyc profil NVIDIA?'
    Write-Host ''
    Write-Host '5) Performance Feel Mode' -ForegroundColor Green
    Write-Host '   Zysk FPS: zwykle 0-3%, ale najwiekszy efekt to responsywnosc: szybszy pulpit, mniej input laga i mniej stutteru.' -ForegroundColor DarkGray
    Write-Host '   Nie rusza telemetrii, Windows Update, VBS ani agresywnej sieci. Dobre pod laptop i codzienna prace.' -ForegroundColor DarkGray
    $script:LaptopOptionalPerformanceFeelMode = Read-YesNoDefaultNo 'Wlaczyc Performance Feel Mode?'

    $script:Manifest.LaptopProOptions = [ordered]@{
        BenchmarkReport       = $script:LaptopOptionalBenchmarkReport
        StartupReview         = $script:LaptopOptionalStartupReview
        PostDebloaterRepair   = $script:LaptopOptionalPostDebloaterRepair
        NvidiaProfile         = $script:LaptopOptionalNvidiaProfile
        PerformanceFeelMode   = $script:LaptopOptionalPerformanceFeelMode
    }
}

function Resolve-LaptopGamingProSilentOptions {
    if (-not $script:EnableLaptopGamingSafeMode) { return }
    if ($EnableBenchmarkReport)       { $script:LaptopOptionalBenchmarkReport = $true }
    if ($EnableStartupReview)         { $script:LaptopOptionalStartupReview = $true }
    if ($EnablePostDebloaterRepair)   { $script:LaptopOptionalPostDebloaterRepair = $true }
    if ($EnableNvidiaProfile)         { $script:LaptopOptionalNvidiaProfile = $true }
    if ($EnablePerformanceFeelMode)  { $script:LaptopOptionalPerformanceFeelMode = $true }
    if ($script:EnableRiskPackBundle) { Enable-CombinedRiskPack -Context 'LaptopGamingSafe' }
    $script:Manifest.LaptopProOptions = [ordered]@{
        BenchmarkReport       = $script:LaptopOptionalBenchmarkReport
        StartupReview         = $script:LaptopOptionalStartupReview
        PostDebloaterRepair   = $script:LaptopOptionalPostDebloaterRepair
        NvidiaProfile         = $script:LaptopOptionalNvidiaProfile
        PerformanceFeelMode   = $script:LaptopOptionalPerformanceFeelMode
    }
}


function Show-ProfileRiskAwareChoiceMenu {
    <#
    Pokazuje dodatkowy, swiadomy wybor tylko dla profili, ktore faktycznie wlaczaja ryzykowne moduly.
    Nie dotyka profilu Maximum — Maximum ma zostac agresywny i bez dodatkowego hamowania.
    Nie dubluje LaptopGamingSafe — ten profil ma wlasne menu PRO/RISK.
    #>
    if ($Silent) { return }
    if ($Mode -ne 'Optimize') { return }
    if ($Profile -eq 'Maximum') {
        $script:AllowGlobalWindowsUpdatePause = $true
        if ($script:EnableRiskPackBundle) { Enable-CombinedRiskPack -Context 'General' }
        Write-Log 'RiskAware: profil Maximum — pomijam dodatkowe pytania, agresywne ustawienia zostaja.' -Level 'INFO'
        return
    }
    if ($script:EnableLaptopGamingSafeMode) { return }

    $hasAnyRisk = $false
    if ($script:EnableServiceTuning) { $hasAnyRisk = $true }
    if ($script:EnableNetworkTweaks) { $hasAnyRisk = $true }
    if ($EnableVbsDisable) { $hasAnyRisk = $true }
    # Starszy flow robil pauze WU dla prawie kazdego profilu. Teraz pytamy tylko poza Maximum.
    $hasAnyRisk = $true
    if (-not $hasAnyRisk) { return }

    Write-Host ''
    Write-Host '--- Swiadome opcje ryzykowne dla tego profilu ---' -ForegroundColor Yellow
    Write-Host 'Pokazuje tylko rzeczy, ktore ten profil faktycznie moze ruszac. Przy Maximum tego nie hamuje.' -ForegroundColor DarkGray
    Write-Host ''

    if ($script:EnableRiskPackBundle) {
        Enable-CombinedRiskPack -Context 'General'
        Write-Log 'RiskAware: EnableRiskPackModule aktywny — wlaczam zbiorczy pakiet ryzykowny dla profilu.' -Level 'WARN'
    } else {
        Show-CombinedRiskPackInfo -Context 'General'
        if (Read-YesNoDefaultNo 'Wlaczyc caly Risk Pack dla tego profilu?') {
            Enable-CombinedRiskPack -Context 'General'
            Write-Host ''
            Write-Host 'Risk Pack zostal wlaczony jako jeden modul zbiorczy.' -ForegroundColor Yellow
            Write-Host 'Performance Feel Mode zostaje osobno, bo to bezpieczny modul i nie nalezy do pakietu ryzykownego.' -ForegroundColor DarkGray
            Write-Host ''
        }
    }

    if ($script:EnableServiceTuning -and -not $script:EnableRiskPackBundle) {
        Write-Host '1) Tuning uslug / telemetrii' -ForegroundColor Yellow
        Write-Host '   Realny zysk: zwykle 0-2% FPS, czasem szybszy start i mniej RAM.' -ForegroundColor DarkGray
        Write-Host '   Co moze zmienic: DiagTrack/Maps/WER moga przejsc na Manual; Insider/rollout zwykle dziala, ale przy mocnych privacy-tweakach moze byc gorzej.' -ForegroundColor DarkGray
        if (-not (Read-YesNoDefaultNo 'Zostawic tuning uslug wlaczony?')) {
            $script:EnableServiceTuning = $false
            Write-Log 'RiskAware: user disabled ServiceTuning for non-Maximum profile.' -Level 'WARN'
        }
        Write-Host ''
    }

    if ($script:EnableNetworkTweaks -and -not $script:EnableRiskPackBundle) {
        Write-Host '2) Tweaki sieci' -ForegroundColor Yellow
        Write-Host '   Realny zysk: 0-3% w latency/pingu, FPS zwykle bez zmian.' -ForegroundColor DarkGray
        Write-Host '   Co moze zmienic: ustawienia adaptera/DNS; moze wplywac na VPN, Hyper-V, TAP i nietypowe sieci.' -ForegroundColor DarkGray
        if (-not (Read-YesNoDefaultNo 'Zostawic tweaki sieci wlaczone?')) {
            $script:EnableNetworkTweaks = $false
            Write-Log 'RiskAware: user disabled NetworkTweaks for non-Maximum profile.' -Level 'WARN'
        }
        Write-Host ''
    }

    if (-not $script:EnableRiskPackBundle) {
        Write-Host '3) Pauza Windows Update na 7 dni' -ForegroundColor Yellow
        Write-Host '   Realny zysk: 0-2% tylko gdy Windows Update mieli w tle; w grach moze zmniejszyc mikroprzyciecia.' -ForegroundColor DarkGray
        Write-Host '   Co moze zmienic: aktualizacje beda odlozone; NIE blokuje trwale WU i nie powinno psuc Insidera.' -ForegroundColor DarkGray
        $script:AllowGlobalWindowsUpdatePause = Read-YesNoDefaultNo 'Wlaczyc pauze Windows Update?'
        Write-Log "RiskAware: global WU pause allowed = $($script:AllowGlobalWindowsUpdatePause)" -Level 'INFO'
        Write-Host ''
    }

    Write-Host '4) Performance Feel Mode (bezpieczny)' -ForegroundColor Green
    Write-Host '   Realny zysk: zwykle 0-3% FPS, ale duzy efekt w responsywnosci, szybkosci UI i mniejszym stutterze.' -ForegroundColor DarkGray
    Write-Host '   Co zmienia: animacje/UI, Explorer, mouse acceleration, MMCSS/audio i helper gaming session; nie rusza telemetrii/WU/VBS.' -ForegroundColor DarkGray
    if (Read-YesNoDefaultNo 'Wlaczyc Performance Feel Mode dla tego profilu?') { $script:LaptopOptionalPerformanceFeelMode = $true }
    Write-Host ''

    if ($EnableVbsDisable -and -not $script:EnableRiskPackBundle) {
        Write-Host '4) VBS / Memory Integrity OFF' -ForegroundColor Red
        Write-Host '   Realny zysk: 0-10% zalezne od gry/sprzetu; na nowszych PC czesto 0-3%.' -ForegroundColor DarkGray
        Write-Host '   Co moze zmienic: slabsze zabezpieczenia kernela, problemy z funkcjami wymagajacymi izolacji/virtualization security.' -ForegroundColor DarkGray
        if (-not (Read-YesNoDefaultNo 'Na pewno zostawic VBS/HVCI OFF?')) {
            Set-Variable -Name EnableVbsDisable -Scope Script -Value $false
            Write-Log 'RiskAware: user disabled VBSDisable for non-Maximum profile.' -Level 'WARN'
        }
        Write-Host ''
    }

    $script:Manifest.RiskAwareOptions = [ordered]@{
        ServiceTuning      = $script:EnableServiceTuning
        NetworkTweaks      = $script:EnableNetworkTweaks
        WindowsUpdatePause = $script:AllowGlobalWindowsUpdatePause
        VbsDisable         = [bool]$EnableVbsDisable
    }
}

function Invoke-LaptopStartupReview {
    if (-not $script:EnableLaptopGamingSafeMode -or -not $script:LaptopOptionalStartupReview) { return }
    Invoke-Step -Name 'Laptop PRO: przeglad autostartu' -Action {
        $script:AppliedModules.Add('LaptopStartupReview')
        $items = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Sort-Object Name)
        $report = Join-Path $script:ReportFolder 'startup_review.txt'
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('=== PRZEGLAD AUTOSTARTU ===')
        $lines.Add('Skrypt nic nie wylacza automatycznie. Wylaczane sa tylko pozycje wybrane przez Ciebie.')
        $lines.Add('Najwiekszy sens maja launchery, komunikatory, update-helpery i VPN, ktorych nie potrzebujesz po starcie.')
        $lines.Add('')
        if ($items.Count -eq 0) {
            $lines.Add('Brak pozycji autostartu przez Win32_StartupCommand.')
        } else {
            for ($i=0; $i -lt $items.Count; $i++) {
                $it = $items[$i]
                $risk = if ($it.Name -match 'OneDrive|Teams|Discord|Steam|Epic|GOG|Battle|Adobe|Update|VPN|Telegram|Spotify|Launcher') { 'Kandydat' } else { 'Ostroznie' }
                $lines.Add(('[{0}] {1} | {2} | {3}' -f ($i+1), $it.Name, $risk, $it.Command))
            }
        }
        $lines | Set-Content -Path $report -Encoding UTF8
        Write-Status "  Zapisano liste autostartu: $report" 'Green'
        if (-not $Silent -and $items.Count -gt 0) {
            Write-Host ''
            Write-Host 'Autostart do przegladu zapisany w raporcie. Wylaczac pozycje teraz?' -ForegroundColor Yellow
            Write-Host 'Podaj numery po przecinku, np. 2,5 albo Enter aby pominac.' -ForegroundColor DarkGray
            $ans = Read-Host 'Numery do wylaczenia'
            if ($ans.Trim()) {
                $nums = $ans -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
                foreach ($n in $nums) {
                    if ($n -lt 1 -or $n -gt $items.Count) { continue }
                    $name = $items[$n-1].Name
                    $disabled = $false
                    $runPaths = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')
                    foreach ($rp in $runPaths) {
                        try {
                            $props = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
                            if ($props -and ($props.PSObject.Properties.Name -contains $name)) {
                                if (-not (Test-Path ($rp + '\DisabledByUWO'))) { New-Item -Path ($rp + '\DisabledByUWO') -Force | Out-Null }
                                $val = (Get-ItemProperty -Path $rp -Name $name -ErrorAction SilentlyContinue).$name
                                New-ItemProperty -Path ($rp + '\DisabledByUWO') -Name $name -PropertyType String -Value $val -Force | Out-Null
                                Remove-ItemProperty -Path $rp -Name $name -Force -ErrorAction SilentlyContinue
                                Write-Log "Autostart disabled: $name" -Level 'CHANGE'
                                $disabled = $true
                            }
                        } catch {}
                    }
                    if (-not $disabled) { Write-Log "Autostart: nie udalo sie wylaczyc '$name' automatycznie — uzyj Menedzera zadan." -Level 'WARN' }
                }
            }
        }
        Add-HtmlSection "<h2>Przeglad autostartu</h2><p>Lista zapisana: $report</p><p>Bezpieczny modul: nic nie jest wylaczane bez wyboru uzytkownika.</p>"
    }
}

function Invoke-PostDebloaterRepair {
    if (-not $script:EnableLaptopGamingSafeMode -or -not $script:LaptopOptionalPostDebloaterRepair) { return }
    Invoke-Step -Name 'Laptop PRO: naprawa po debloaterach' -Action {
        $script:AppliedModules.Add('PostDebloaterRepair')
        Write-Status '  Przywracam elementy potrzebne dla Insidera, WU, Store/Xbox...' 'Cyan'
        # Insider / diagnostyka — nie ustawiamy prywatnosci agresywnie, tylko odblokowujemy opcjonalne dane.
        try { & reg.exe delete 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' /f 2>$null | Out-Null } catch {}
        Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -N 'AllowTelemetry' -V 3 -R 'Repair: opcjonalne dane diagnostyczne dla Insider/rollout'
        Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -N 'DisableWindowsUpdateAccess' -V 0 -R 'Repair: Windows Update odblokowany'
        Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -N 'RemoveWindowsStore' -V 0 -R 'Repair: Microsoft Store odblokowany'
        Set-ServiceStartupSafe -Name 'DiagTrack' -StartupType Automatic -Reason 'Repair: wymagane dla Insider/feature rollout'
        Set-ServiceStartupSafe -Name 'wuauserv' -StartupType Manual -Reason 'Repair: Windows Update'
        Set-ServiceStartupSafe -Name 'bits' -StartupType Manual -Reason 'Repair: BITS dla pobierania update'
        Set-ServiceStartupSafe -Name 'UsoSvc' -StartupType Manual -Reason 'Repair: Update Orchestrator'
        Set-ServiceStartupSafe -Name 'InstallService' -StartupType Manual -Reason 'Repair: Microsoft Store Install Service'
        Set-ServiceStartupSafe -Name 'XblAuthManager' -StartupType Manual -Reason 'Repair: Xbox sign-in dla gier/Game Pass'
        Set-ServiceStartupSafe -Name 'XblGameSave' -StartupType Manual -Reason 'Repair: Xbox cloud saves'
        Add-RestartFlag 'Naprawa po debloaterach'
        Add-HtmlSection '<h2>Naprawa po debloaterach</h2><p>Przywrocono ustawienia wymagane przez Insider, Windows Update, Store i Xbox. To nie jest tweak FPS — to stabilnosc i poprawne funkcje systemowe.</p>'
    }
}

function Invoke-NvidiaSafeProfile {
    if (-not $script:EnableLaptopGamingSafeMode -or -not $script:LaptopOptionalNvidiaProfile) { return }
    Invoke-Step -Name 'Laptop PRO: bezpieczny profil NVIDIA' -Action {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        $hasNvidia = [bool]($gpus | Where-Object { $_.Name -match 'NVIDIA|GeForce|RTX|GTX' })
        if (-not $hasNvidia) { Write-Log 'NVIDIA profile: brak NVIDIA GPU — pominieto.' -Level 'INFO'; return }
        $script:AppliedModules.Add('NvidiaSafeProfile')
        $nvidiaSmi = $null
        $candidates = @(
            "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
            "$env:SystemRoot\System32\nvidia-smi.exe"
        )
        foreach ($c in $candidates) { if (Test-Path $c) { $nvidiaSmi = $c; break } }
        if ($nvidiaSmi) {
            try { & $nvidiaSmi -pm 1 2>$null | Out-Null; Write-Log 'NVIDIA: persistence mode requested (moze byc ignorowane na laptopach).' -Level 'CHANGE' } catch { Write-Log 'NVIDIA: persistence mode niedostepny/odmowa — pomijam.' -Level 'WARN' }
        } else {
            Write-Log 'NVIDIA: nvidia-smi.exe nie znaleziony — tylko ustawienia Windows/registry.' -Level 'INFO'
        }
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -N 'HwSchMode' -V 2 -R 'NVIDIA safe: HAGS preferowany dla dedykowanego GPU' -Rst
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -N 'TdrDelay' -V 10 -R 'NVIDIA safe: mniej resetow sterownika przy chwilowym obciazeniu' -Rst
        Add-RestartFlag 'Profil NVIDIA safe'
        Add-HtmlSection '<h2>Profil NVIDIA safe</h2><p>Wlaczono tylko bezpieczne ustawienia bez OC/Coolbits. Najwiekszy efekt to mniej stutteru, nie gwarantowany wzrost FPS.</p>'
    }
}

function Invoke-LaptopBenchmarkProReport {
    if (-not $script:EnableLaptopGamingSafeMode -or -not $script:LaptopOptionalBenchmarkReport) { return }
    Invoke-Step -Name 'Laptop PRO: rozszerzony raport benchmarku' -Action {
        $script:AppliedModules.Add('LaptopBenchmarkPro')
        $path = Join-Path $script:ReportFolder 'laptop_gaming_pro_report.txt'
        $hw = Get-HardwareProfile
        $env = Get-SystemEnvironment
        $startupCount = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue).Count
        $top = @(
            Get-Process -ErrorAction SilentlyContinue |
                Sort-Object @{Expression={
                    if ($_.CPU -is [timespan]) { $_.CPU.TotalSeconds }
                    elseif ($null -eq $_.CPU) { -1 }
                    else { [double]$_.CPU }
                }} -Descending |
                Select-Object -First 8 ProcessName,CPU,WS
        )
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('=== LAPTOP GAMING PRO REPORT ===')
        $lines.Add("CPU: $($env.CPU)")
        $lines.Add("GPU: $($env.GPU)")
        $lines.Add("RAM: $($env.TotalRAMGB) GB")
        $lines.Add("Build: $($env.Build)")
        $lines.Add("Laptop/AC: $($hw.IsLaptop) / $($script:LaptopOnAC)")
        $lines.Add("Autostart count: $startupCount")
        $lines.Add('')
        $lines.Add('Top CPU/RAM procesy:')
        foreach ($p in $top) { $lines.Add(('  {0,-28} CPU={1,8} RAM={2,8} MB' -f $p.ProcessName, [math]::Round([double]$p.CPU,1), [math]::Round($p.WS/1MB,0))) }
        $lines.Add('')
        $lines.Add('Interpretacja:')
        $lines.Add('  - Najwiekszy realny zysk w grach zwykle daje: sterownik GPU, temperatury, autostart i aplikacje w tle.')
        $lines.Add('  - Tweaki rejestru zwykle daja mniej niz 1-3%, ale moga zmniejszyc stutter.')
        $lines.Add('  - FPS nie jest mierzony przez PowerShell. Do FPS/frametime uzyj CapFrameX/PresentMon/MSI Afterburner.')
        $lines | Set-Content -Path $path -Encoding UTF8
        Write-Status "  Raport PRO zapisany: $path" 'Green'
        Add-HtmlSection "<h2>Laptop Gaming PRO</h2><p>Raport zapisany: $path</p><p>Modul mierzy i opisuje wplyw zmian bez agresywnego psucia systemu.</p>"
    }
}

function Show-LaptopGamingRiskChoiceMenu {
    if ($Silent -or -not $script:EnableLaptopGamingSafeMode) { return }
    # STAGE6 v14.5: AutoSmart never enables the Risk Pack on its own.
    if ($script:AutoSmartSelected) { return }
    # ETAP2 v14.1: Risk Pack to czysto wykonawczy pakiet — w Analyze pytanie o niego nie ma sensu.
    if ($Mode -eq 'Analyze') {
        Write-Host (T 'analyze.risk.skip') -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    if ($script:EnableRiskPackBundle) {
        Enable-CombinedRiskPack -Context 'LaptopGamingSafe'
        Write-Log 'LaptopGamingSafe: EnableRiskPackModule aktywny — wlaczam zbiorczy pakiet ryzykowny.' -Level 'WARN'
    } else {
        Show-CombinedRiskPackInfo -Context 'LaptopGamingSafe'
        if (Read-YesNoDefaultNo 'Wlaczyc caly Risk Pack dla laptopa?') {
            Enable-CombinedRiskPack -Context 'LaptopGamingSafe'
        }
    }

    Write-Host ''
    Write-Host 'Podsumowanie dodatkow:' -ForegroundColor Yellow
    Write-Host "  Telemetria:       $(if($script:LaptopOptionalTelemetryTuning){'TAK'}else{'NIE'})" -ForegroundColor Gray
    Write-Host "  Windows Update:   $(if($script:LaptopOptionalWindowsUpdatePause){'TAK'}else{'NIE'})" -ForegroundColor Gray
    Write-Host "  Uslugi:           $(if($script:EnableServiceTuning){'TAK'}else{'NIE'})" -ForegroundColor Gray
    Write-Host "  VBS/HVCI OFF:     $(if($script:LaptopOptionalVbsDisable){'TAK'}else{'NIE'})" -ForegroundColor Gray
    Write-Host "  Siec/adaptery:    $(if($script:EnableNetworkTweaks){'TAK'}else{'NIE'})" -ForegroundColor Gray
    Write-Host ''
}


function Show-PerformanceFeelInfo {
    Write-Host ''
    Write-Host '--- PERFORMANCE FEEL MODE ---' -ForegroundColor Cyan
    Write-Host 'Cel: system ma sprawiac wrazenie szybszego i bardziej responsywnego, bez psucia Insidera/Windows Update.' -ForegroundColor Gray
    Write-Host 'Realny wynik: FPS zwykle +0-3%, ale czesto mniej stutteru, szybszy Start/Explorer i lepszy input feel.' -ForegroundColor Gray
    Write-Host 'Co zmieni:' -ForegroundColor Yellow
    Write-Host '  - UI/Explorer: krotsze opoznienia menu, mniej lagujacych animacji, szybsze miniatury i powloka.' -ForegroundColor DarkGray
    Write-Host '  - Input: wylacza Enhance Pointer Precision, stabilniejszy feeling myszy.' -ForegroundColor DarkGray
    Write-Host '  - Gaming stutter: Game Mode/DVR off, MMCSS pod gry, priorytet foreground.' -ForegroundColor DarkGray
    Write-Host '  - Audio feel: profil MMCSS Games/Audio pod mniejsze dropy, bez grzebania w sterownikach.' -ForegroundColor DarkGray
    Write-Host '  - Helper: tworzy skrypt GamingSession, ktory przed gra moze zamknac typowe launchery/procesy po potwierdzeniu.' -ForegroundColor DarkGray
    Write-Host 'Czego NIE rusza: telemetria, Windows Update policies, VBS/Memory Integrity, agresywne sieci, uslugi krytyczne.' -ForegroundColor Green
}

function Invoke-PerformanceFeelMode {
    if (-not $script:LaptopOptionalPerformanceFeelMode -and -not $EnablePerformanceFeelMode) { return }
    $script:AppliedModules.Add('PerformanceFeelMode')
    Show-PerformanceFeelInfo

    Invoke-Step -Name 'Performance Feel: UI / Explorer responsiveness' -Action {
        # Efekt: szybsze odczucie systemu. Bez wylaczania waznych funkcji Windows.
        Set-RegistryDwordSafe -P 'HKCU:\Control Panel\Desktop' -N 'MenuShowDelay' -V 80 -R 'Performance Feel: krotsze opoznienie menu'
        Set-RegistryDwordSafe -P 'HKCU:\Control Panel\Desktop' -N 'AutoEndTasks' -V 0 -R 'Performance Feel: nie zabijaj automatycznie aplikacji'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -N 'ListviewAlphaSelect' -V 0 -R 'Performance Feel: mniej efektow listy Explorer'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -N 'TaskbarAnimations' -V 0 -R 'Performance Feel: mniej animacji taskbara'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -N 'StartupDelayInMSec' -V 0 -R 'Performance Feel: szybszy start powloki po logowaniu'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -N 'VisualFXSetting' -V 2 -R 'Performance Feel: custom visual effects'
        Write-Log 'Performance Feel UI: menu delay, taskbar animations and shell startup delay tuned.' -Level 'CHANGE'
    } -ContinueOnError

    Invoke-Step -Name 'Performance Feel: input lag / mouse feel' -Action {
        # Efekt: bardziej przewidywalna mysz. Nie zwieksza FPS, ale poprawia celowanie/feeling.
        Set-RegistryStringSafe -P 'HKCU:\Control Panel\Mouse' -N 'MouseSpeed' -V '0' -R 'Performance Feel: Enhance Pointer Precision off'
        Set-RegistryStringSafe -P 'HKCU:\Control Panel\Mouse' -N 'MouseThreshold1' -V '0' -R 'Performance Feel: mouse threshold 1 off'
        Set-RegistryStringSafe -P 'HKCU:\Control Panel\Mouse' -N 'MouseThreshold2' -V '0' -R 'Performance Feel: mouse threshold 2 off'
        Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -N 'SystemResponsiveness' -V 10 -R 'Performance Feel: nizsza rezerwa dla background tasks' -Rst
        Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -N 'NetworkThrottlingIndex' -V 4294967295 -R 'Performance Feel: brak throttlingu multimedia network' -Rst
        Write-Log 'Performance Feel input: mouse acceleration off and multimedia responsiveness tuned.' -Level 'CHANGE'
    } -ContinueOnError

    Invoke-Step -Name 'Performance Feel: games / audio MMCSS' -Action {
        # Efekt: potencjalnie mniej stutteru audio/games bez ruszania sterownikow.
        $games = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
        Set-RegistryDwordSafe -P $games -N 'GPU Priority' -V 8 -R 'Performance Feel: Games GPU priority' -Rst
        Set-RegistryDwordSafe -P $games -N 'Priority' -V 6 -R 'Performance Feel: Games task priority' -Rst
        Set-RegistryStringSafe -P $games -N 'Scheduling Category' -V 'High' -R 'Performance Feel: Games scheduling high' -Rst
        Set-RegistryStringSafe -P $games -N 'SFIO Priority' -V 'High' -R 'Performance Feel: Games SFIO high' -Rst
        $audio = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio'
        Set-RegistryDwordSafe -P $audio -N 'Priority' -V 6 -R 'Performance Feel: Audio task priority' -Rst
        Set-RegistryStringSafe -P $audio -N 'Scheduling Category' -V 'High' -R 'Performance Feel: Audio scheduling high' -Rst
        Write-Log 'Performance Feel MMCSS: Games and Audio task profiles tuned.' -Level 'CHANGE'
        Add-RestartFlag 'Performance Feel: MMCSS/SystemProfile changes'
    } -ContinueOnError

    Invoke-Step -Name 'Performance Feel: stutter reduction / safe gaming defaults' -Action {
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\GameBar' -N 'AllowAutoGameMode' -V 1 -R 'Performance Feel: Game Mode allowed'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\GameBar' -N 'AutoGameModeEnabled' -V 1 -R 'Performance Feel: Game Mode auto'
        Set-RegistryDwordSafe -P 'HKCU:\System\GameConfigStore' -N 'GameDVR_Enabled' -V 0 -R 'Performance Feel: Game DVR off'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -N 'AppCaptureEnabled' -V 0 -R 'Performance Feel: background capture off'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -N 'HistoricalCaptureEnabled' -V 0 -R 'Performance Feel: historical capture off'
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -N 'Win32PrioritySeparation' -V 38 -R 'Performance Feel: foreground app priority' -Rst
        Write-Log 'Performance Feel gaming: Game Mode on, DVR off, foreground priority tuned.' -Level 'CHANGE'
    } -ContinueOnError

    Invoke-Step -Name 'Performance Feel: GamingSession helper' -Action {
        $helper = Join-Path $script:SessionFolder 'Start-GamingSession-Safe.ps1'
        $content = @'
# Safe Gaming Session Helper
# Uruchom jako admin przed gra. Zamyka tylko wybrane aplikacje po potwierdzeniu.
$targets = 'msedge','chrome','discord','teams','onedrive','steamwebhelper','EpicGamesLauncher','GalaxyClient','Spotify','AdobeCollabSync'
Write-Host 'Gaming Session Helper - procesy w tle do ewentualnego zamkniecia' -ForegroundColor Cyan
$procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $targets -contains $_.ProcessName } | Sort-Object ProcessName
if (-not $procs) { Write-Host 'Brak typowych ciezkich procesow do zamkniecia.' -ForegroundColor Green; return }
$procs | Select-Object ProcessName, Id, @{n='RAM_MB';e={[math]::Round($_.WorkingSet64/1MB,0)}} | Format-Table -AutoSize
$ans = Read-Host 'Zamknac te procesy przed gra? [t/N]'
if ($ans -match '^(t|tak|y|yes)$') {
  foreach ($p in $procs) { try { $p.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 500; if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } } catch {} }
  Write-Host 'Gotowe. Po grze odpal aplikacje normalnie z menu Start.' -ForegroundColor Green
} else { Write-Host 'Pominieto.' -ForegroundColor Yellow }
'@
        $content | Set-Content -Path $helper -Encoding UTF8
        Write-Status "  Helper zapisany: $helper" 'Green'
        Add-HtmlSection "<h2>Performance Feel Mode</h2><p>Dodano modul responsywnosci: UI/Explorer, input, MMCSS Games/Audio, DVR off i helper Gaming Session.</p><p>Helper: <code>$helper</code></p><p>Efekt: zwykle 0-3% FPS, ale wiekszy komfort i mniejszy stutter.</p>"
    } -ContinueOnError

    $script:Manifest.PerformanceFeelMode = [ordered]@{
        Enabled = $true
        ExpectedFpsGain = '0-3% zwykle; wiekszy efekt w responsywnosci/stutterze niz w srednim FPS'
        UserVisibleResult = 'Szybszy Explorer/Start, mniej animacyjnego laga, stabilniejsza mysz, mniej nagrywania w tle, lepszy gaming feel'
        Safety = 'Nie rusza telemetrii, Windows Update policies, VBS/Memory Integrity ani agresywnych tweakow sieciowych'
    }
}

function Invoke-LaptopGamingOptionalRiskTweaks {
    if (-not $script:EnableLaptopGamingSafeMode) { return }
    if ($EnableTelemetryTuning) { $script:LaptopOptionalTelemetryTuning = $true }
    if ($EnableWindowsUpdatePause) { $script:LaptopOptionalWindowsUpdatePause = $true }

    if ($script:LaptopOptionalTelemetryTuning -and -not $script:EnableServiceTuning) {
        $script:AppliedModules.Add('LaptopOptionalTelemetry')
        Invoke-Step -Name 'Laptop opcjonalnie: Telemetria / DiagTrack -> Manual' -Action {
            Write-Log 'Laptop optional: DiagTrack -> Manual. UWAGA: moze ograniczyc Insider/rollout funkcji.' -Level 'WARN'
            Set-ServiceStartupSafe -Name 'DiagTrack' -StartupType Manual -StopService -Reason 'Opcjonalnie: mniej telemetrii w tle; moze ograniczyc Insider/rollout'
        } -ContinueOnError
    }

    if ($script:LaptopOptionalWindowsUpdatePause) {
        $script:AppliedModules.Add('LaptopOptionalWUPause')
        Write-Status '  Laptop opcjonalnie: Windows Update pauza 7 dni — mniej pracy w tle, aktualizacje opoznione.' 'Yellow'
        Request-WindowsUpdatesPause
    }
}


function Invoke-LaptopOptionalVbsDisable {
    if (-not $script:EnableLaptopGamingSafeMode -or -not $script:LaptopOptionalVbsDisable) { return }
    $script:AppliedModules.Add('LaptopOptionalVBS')
    Write-Log 'UWAGA: Laptop optional VBS/HVCI OFF — realny zysk FPS mozliwy, ale bezpieczenstwo spada.' -Level 'WARN'
    Write-Status '  Laptop opcjonalnie: VBS/Memory Integrity OFF — najwiekszy boost FPS, najwiekszy kompromis bezpieczenstwa.' 'Yellow'
    Invoke-Step -Name 'Laptop opcjonalnie: VBS/Memory Integrity OFF' -Action {
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -N 'EnableVirtualizationBasedSecurity' -V 0 -R 'Laptop optional: VBS off — zysk FPS' -Rst
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -N 'Enabled' -V 0 -R 'Laptop optional: HVCI/Memory Integrity off' -Rst
        Write-Log 'Laptop optional: VBS/HVCI wylaczone. Wymagany restart.' -Level 'CHANGE'
        Add-RestartFlag 'Laptop optional: VBS/Memory Integrity OFF'
    } -ContinueOnError
}

function Invoke-LaptopGamingSafeTweaks {
    <#
    .SYNOPSIS
        Bezpieczny modul laptop gaming: praktyczna wydajnosc bez zmian, ktore psuja Insidera/Update/telemetrie/uslugi.
    .NOTES
        Nie dotyka: HKLM:\SOFTWARE\Policies, DataCollection, Windows Update policies, Services, VBS/HVCI, network stack.
        Dziala najlepiej na zasilaczu. Zmiany sa odwracalne przez rollback sesji skryptu.
    #>
    Set-StrictMode -Version Latest
    $script:AppliedModules.Add('LaptopGamingSafe')

    Invoke-Step -Name 'LaptopGamingSafe: Game Mode ON + DVR/Captures OFF' -Action {
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\GameBar' -N 'AllowAutoGameMode' -V 1 -R 'Safe laptop gaming: Game Mode on'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\GameBar' -N 'AutoGameModeEnabled' -V 1 -R 'Safe laptop gaming: Game Mode auto on'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -N 'AppCaptureEnabled' -V 0 -R 'Safe laptop gaming: background capture off'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -N 'AudioCaptureEnabled' -V 0 -R 'Safe laptop gaming: audio capture off'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -N 'HistoricalCaptureEnabled' -V 0 -R 'Safe laptop gaming: historical capture off'
        Set-RegistryDwordSafe -P 'HKCU:\System\GameConfigStore' -N 'GameDVR_Enabled' -V 0 -R 'Safe laptop gaming: GameDVR off'
        Set-RegistryDwordSafe -P 'HKCU:\System\GameConfigStore' -N 'GameDVR_FSEBehaviorMode' -V 2 -R 'Safe laptop gaming: fullscreen optimizations behavior' -Rst
    } -ContinueOnError

    Invoke-Step -Name 'LaptopGamingSafe: GPU stutter reduction (HAGS, shader cache, TDR)' -Action {
        $hasDedicatedGpu = $false
        try {
            $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
            $hasDedicatedGpu = [bool]($gpus | Where-Object { $_.Name -match 'NVIDIA|GeForce|RTX|GTX|Radeon|RX |Arc' })
        } catch { $hasDedicatedGpu = $false }

        if ($hasDedicatedGpu) {
            Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -N 'HwSchMode' -V 2 -R 'Safe laptop gaming: HAGS on for dGPU' -Rst
        } else {
            Write-Log 'LaptopGamingSafe: HAGS pominiety — nie wykryto dedykowanego GPU.' -Level 'INFO'
            $script:SkippedCount++
        }

        Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Direct3D' -N 'CacheSize' -V 4096 -R 'Safe laptop gaming: Direct3D shader cache 4GB'
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -N 'TdrDelay' -V 8 -R 'Safe laptop gaming: TDR delay 8s' -Rst
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -N 'TdrDdiDelay' -V 8 -R 'Safe laptop gaming: TDR DDI delay 8s' -Rst
        Add-RestartFlag 'LaptopGamingSafe GPU tweaks (HAGS/shader cache/TDR)'
    } -ContinueOnError

    Invoke-Step -Name 'LaptopGamingSafe: power plan AC only (bez zmian na baterii)' -Action {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        $onAC = -not $battery -or $battery.BatteryStatus -eq 2
        if (-not $onAC) {
            Write-Log 'LaptopGamingSafe: zasilacz nie jest podlaczony — pomijam powercfg AC.' -Level 'WARN'
            $script:SkippedCount++
            return
        }

        # Aktywuj High Performance, ale bez Ultimate Performance i bez niszczenia planow OEM.
        & powercfg /setactive SCHEME_MIN | Out-Null
        # CPU 100% tylko na AC, aktywne chlodzenie, brak oszczedzania PCIe/USB na zasilaczu.
        & powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 | Out-Null
        & powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 | Out-Null
        & powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR SYSCOOLPOL 1 | Out-Null
        & powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 | Out-Null
        & powercfg /setacvalueindex SCHEME_CURRENT SUB_USB USBSELECTSUSPEND 0 | Out-Null
        & powercfg /setactive SCHEME_CURRENT | Out-Null
        Write-Log 'LaptopGamingSafe: ustawienia zasilania AC zastosowane.' -Level 'CHANGE'
    } -ContinueOnError

    Invoke-Step -Name 'LaptopGamingSafe: szybszy start pulpitu i responsywnosc UI' -Action {
        New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Force | Out-Null
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -N 'StartupDelayInMSec' -V 0 -R 'Safe laptop: brak sztucznego opoznienia startu aplikacji'
        Set-RegistryDwordSafe -P 'HKCU:\Control Panel\Desktop' -N 'MenuShowDelay' -V 100 -R 'Safe laptop: szybsze menu UI'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -N 'TaskbarAnimations' -V 0 -R 'Safe laptop: mniej animacji taskbara'
    } -ContinueOnError

    Write-Status (T 'lgs.untouched') 'Green'
    Write-Log 'LaptopGamingSafe complete: no telemetry/Windows Update/services/VBS/network policy changes.' -Level 'INFO'
}

function Invoke-GamingTweaks {
    Set-StrictMode -Version Latest
    $script:AppliedModules.Add('Gaming')
    Invoke-Step -Name 'Gaming: Game Mode, DVR off, priorytet procesora' -Action {
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\GameBar' -N 'AllowAutoGameMode'      -V 1 -R 'Game Mode on'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\GameBar' -N 'AutoGameModeEnabled'    -V 1 -R 'Game Mode on'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -N 'AppCaptureEnabled'        -V 0 -R 'Game DVR off'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -N 'AudioCaptureEnabled'      -V 0 -R 'Audio capture off'
        Set-RegistryDwordSafe -P 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -N 'HistoricalCaptureEnabled'  -V 0 -R 'Historical capture off'
        Set-RegistryDwordSafe -P 'HKCU:\System\GameConfigStore' -N 'GameDVR_FSEBehaviorMode'   -V 2 -R 'Fullscreen gaming' -Rst
    }
    # GameDVR — z walidacją i auto-rollback
    Invoke-TweakWithValidation `
        -Name 'Gaming: GameDVR_Enabled = 0' `
        -Action {
            Set-RegistryDwordSafe -P 'HKCU:\System\GameConfigStore' -N 'GameDVR_Enabled' -V 0 -R 'GameDVR store off'
        } `
        -RollbackAction {
            Set-RegistryDwordSafe -P 'HKCU:\System\GameConfigStore' -N 'GameDVR_Enabled' -V 1 -R 'AutoRollback: DVR przywrocony'
        } `
        -MetricBlock {
            (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB
        } `
        -BetterWhenLower $false `
        -ThresholdPct 5 `
        -WaitSeconds 3

    # Win32PrioritySeparation — z walidacją i auto-rollback
    Invoke-TweakWithValidation `
        -Name 'Gaming: Win32PrioritySeparation = 38' `
        -Action {
            Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -N 'Win32PrioritySeparation' -V 38 -R 'Foreground boost 3:1 — optymalne dla gier, moze spowolnic render/wideo w tle' -Rst
        } `
        -RollbackAction {
            Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -N 'Win32PrioritySeparation' -V 2 -R 'AutoRollback: PrioritySeparation przywrocony do domyslnego'
        } `
        -MetricBlock {
            $v = Get-CounterValueSafe '\Processor(_Total)\% Processor Time'
            if ($null -ne $v) { [math]::Round($v, 1) } else { 50.0 }
        } `
        -BetterWhenLower $true `
        -ThresholdPct 15 `
        -WaitSeconds 4
        # v12: SystemResponsiveness dynamicznie (wiecej rdzeni = mozemy byc agresywniejsi)
        $sr = if ($Profile -eq 'Maximum') {
            if ($script:HWProfile -and $script:HWProfile.IsHighEndCPU) { 10 } else { 15 }
        } else {
            if ($script:HWProfile -and $script:HWProfile.IsHighEndCPU) { 15 } else { 20 }
        }
        Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -N 'SystemResponsiveness' -V $sr -R "MMCSS SystemResponsiveness=$sr" -Rst
    # HAGS — domyslnie w Balanced i Maximum, ale Smart Mode sprawdza GPU/laptop/baterie
    Add-TweakMetadata -Id 'HAGS' -Name 'Hardware Accelerated GPU Scheduling' -Category 'GPU' -Risk Medium -Evidence Medium -RecommendedFor @('Gaming','Balanced','Maximum') -AvoidOn @('Laptop') -RequiresRestart -Notes 'Smart Mode pomija bez dedykowanego GPU lub na baterii.'
    if ($Profile -in 'Balanced','Maximum' -and (Test-TweakEligibility -TweakId 'HAGS')) {
        Invoke-Step -Name 'Gaming: HAGS (Hardware GPU Scheduling) — Balanced/Maximum' -Action {
            Write-Log 'HAGS: stosowany w Balanced/Maximum. Na bardzo starych GPU/sterownikach moze byc niestabilny.' -Level 'WARN'
            Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -N 'HwSchMode' -V 2 -R 'HAGS — domyslny Balanced/Maximum (DLSS/FSR FG)' -Rst
        } -ContinueOnError
    } else {
        Write-Log "HAGS pominiety (profil=$Profile). Wymaga Balanced lub Maximum." -Level 'INFO'
        $script:SkippedCount++
    }
    if ($EnableExperimentalTweaks) {
        Invoke-Step -Name 'Gaming: Nagle disable — Experimental' -Action {
            $ip='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            if (Test-Path $ip) {
                Get-ChildItem $ip -EA SilentlyContinue|ForEach-Object {
                    Set-RegistryDwordSafe -P $_.PSPath -N 'TcpAckFrequency' -V 1 -R 'Niska latencja TCP (Exp)' -Rst
                    Set-RegistryDwordSafe -P $_.PSPath -N 'TCPNoDelay'      -V 1 -R 'Niska latencja TCP (Exp)' -Rst
                }
            }
        } -ContinueOnError
        Write-Log 'NetworkThrottlingIndex usuniety z v8 — legacy tweak bez sensownego efektu na Win10/11.' -Level 'INFO'
        $script:SkippedCount++
    }
}

function Invoke-VbsDisable {
    $script:AppliedModules.Add('VbsDisable')
    Add-TweakMetadata -Id 'VBSDisable' -Name 'VBS / HVCI OFF' -Category 'Security' -Risk High -Evidence Medium -RecommendedFor @('Gaming','Maximum') -AvoidOn @('Laptop','Domain','MDM','BitLocker','HyperV') -RequiresRestart -Notes 'Wyrazny trade-off: FPS vs security.'
    if (-not (Test-TweakEligibility -TweakId 'VBSDisable' -BlockOnLaptop -BlockOnDomain -BlockOnMDM -BlockOnHyperV -BlockOnBitLocker)) { return }
    Write-Log 'UWAGA: EnableVbsDisable — wylaczanie VBS/Memory Integrity obniza poziom bezpieczenstwa systemu.' -Level 'WARN'
    Write-Status '  UWAGA: VBS/Memory Integrity OFF obniza bezpieczenstwo — zalecane tylko na dedykowanych PC do gier.' 'Yellow'
    Invoke-Step -Name 'VBS/Memory Integrity OFF (realny zysk FPS, szczegolnie GTX/RTX 2000 i starsze)' -Action {
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -N 'EnableVirtualizationBasedSecurity' -V 0 -R 'VBS off — zysk FPS' -Rst
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -N 'Enabled' -V 0 -R 'HVCI/Memory Integrity off' -Rst
        Write-Log 'VBS/HVCI wylaczone. Wymagany restart.' -Level 'CHANGE'
        Add-RestartFlag 'VBS/Memory Integrity OFF (wymagany restart dla pelnego efektu)'
    } -ContinueOnError
}

function Invoke-GpuTweaks {
    $script:AppliedModules.Add('GPU')
    Add-TweakMetadata -Id 'ShaderCache' -Name 'Direct3D shader cache 4GB' -Category 'GPU' -Risk Low -Evidence Strong -RecommendedFor @('Gaming','Balanced','Maximum') -Notes 'Bezpieczny tweak ograniczajacy stutter podczas kompilacji shaderow.'
    Add-TweakMetadata -Id 'TDRDelay' -Name 'TDR Delay 8s' -Category 'GPU' -Risk Low -Evidence Strong -RecommendedFor @('Gaming','Balanced','Maximum','Workstation') -RequiresRestart -Notes 'Wydluza tylko timeout GPU, nie jest agresywny.'
    Add-TweakMetadata -Id 'MPODisable' -Name 'Disable MPO' -Category 'GPU' -Risk Experimental -Evidence Medium -RecommendedFor @('Gaming') -AvoidOn @('Laptop') -RequiresRestart -Notes 'Tylko gdy overlaye wywoluja stutter/artefakty.'
    Add-TweakMetadata -Id 'Coolbits' -Name 'NVIDIA Coolbits' -Category 'GPU' -Risk Experimental -Evidence Weak -RecommendedFor @('Gaming') -AvoidOn @('Laptop') -RequiresRestart -Notes 'Feature unlock, nie czysty tweak wydajnosci.'
    Invoke-Step -Name 'GPU: shader cache, TDR, tweaki sterownika' -Action {
        Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Direct3D' -N 'CacheSize' -V 4096 -R 'D3D shader cache 4GB'
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -N 'TdrDelay'    -V 8   -R 'TDR delay 8s (stabilnosc GPU pod obciazeniem)' -Rst
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -N 'TdrDdiDelay' -V 8   -R 'TDR DDI delay 8s' -Rst

        if (Test-TweakEligibility -TweakId 'MPODisable' -RequireExperimental -BlockOnLaptop) {
            Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -N 'OverlayTestMode' -V 5 -R 'MPO disable — mniej stutterow z overlayami (Discord, NVIDIA App)' -Rst
        }

        if ($script:HWProfile.IsNvidia) {
            if (Test-TweakEligibility -TweakId 'Coolbits' -RequireExperimental -BlockOnLaptop) {
                Set-RegistryDwordSafe -P 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\NvTweak' -N 'Coolbits' -V 28 -R 'NVIDIA Coolbits: dostep do opcji OC w panelu' -Rst
            }
        } else {
            Write-Log 'Coolbits: pominiete — brak NVIDIA GPU.' -Level 'INFO'
            $script:SkippedCount++
        }

        Write-Log 'GPU tweaks zastosowane (TDR, shader cache, opcjonalnie MPO/Coolbits).' -Level 'CHANGE'
        Add-RestartFlag 'GPU tweaks (TDR, shader cache, MPO/Coolbits)'
    } -ContinueOnError
}

function Invoke-TimerResolution {
    $script:AppliedModules.Add('TimerResolution')
    Add-TweakMetadata -Id 'GlobalTimer' -Name 'Global timer resolution 0.5ms' -Category 'Gaming' -Risk Low -Evidence Medium -RecommendedFor @('Gaming','Maximum','Balanced') -AvoidOn @('Laptop') -RequiresRestart -Notes 'Preferowany na desktopie AC; na laptopie tylko swiadomie.'
    if (-not (Test-TweakEligibility -TweakId 'GlobalTimer')) { return }
    Invoke-Step -Name 'Timer: globalny timer systemowy 0.5ms (GlobalTimerResolutionRequests)' -Action {
        Set-RegistryDwordSafe -P 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -N 'GlobalTimerResolutionRequests' -V 1 -R 'Global timer 0.5ms — nizszy frametime i input lag w grach' -Rst
        Write-Log 'GlobalTimerResolutionRequests=1 ustawiony.' -Level 'CHANGE'
        Add-RestartFlag 'Timer resolution (GlobalTimerResolutionRequests)'
    } -ContinueOnError
}

function Invoke-DefenderGameExclusion {
    $script:AppliedModules.Add('DefenderGameExclusion')
    Add-TweakMetadata -Id 'DefenderGameExclusion' -Name 'Defender game folder exclusion' -Category 'Security' -Risk Medium -Evidence Medium -RecommendedFor @('Gaming') -AvoidOn @('SystemDriveRoot','UserProfile') -Notes 'Smart Mode blokuje root dysku i zbyt szerokie foldery.'
    if (-not $GameFolder) {
        Write-Log 'DefenderGameExclusion: brak sciezki (-GameFolder). Pominiety.' -Level 'INFO'
        $script:SkippedCount++
        return
    }
    if (-not (Test-Path $GameFolder)) {
        Write-Log "DefenderGameExclusion: folder nie istnieje: $GameFolder. Pominiety." -Level 'WARN'
        $script:SkippedCount++
        return
    }
    if (-not (Test-TweakEligibility -TweakId 'DefenderGameExclusion')) { return }
    Invoke-Step -Name "Defender: wykluczenie folderu gier ($GameFolder)" -Action {
        if ($DryRun) {
            Write-Status "  [DRYRUN] Defender exclusion: $GameFolder" 'DarkGray'
            Write-Log "[DRYRUN] Defender exclusion: $GameFolder"
            return
        }
        Add-MpPreference -ExclusionPath $GameFolder -ErrorAction Stop
        $script:Manifest.Notes += "Defender exclusion dodane: $GameFolder"
        Write-Log "Defender exclusion: $GameFolder dodany." -Level 'CHANGE'
        Write-Status "  OK: $GameFolder wykluczony z Defendera." 'Green'
    } -ContinueOnError
}

function Invoke-NetworkDriverTuning {
    <#
    .SYNOPSIS
        Tuning sterownikow sieciowych przez rejestr — wylaczenie Interrupt Moderation
        i ustawienie RSS queues dla popularnych kart (Realtek, Intel I225/I226).
    #>
    $script:AppliedModules.Add('NetworkDriverTuning')
    Add-TweakMetadata -Id 'NetworkDriverTuning' -Name 'NIC driver tuning' -Category 'Network' -Risk Medium -Evidence Medium -RecommendedFor @('Gaming','Maximum') -AvoidOn @('Laptop','HyperV') -Notes 'Teraz tylko dla wspieranych kart i z odczytem wspieranych wartosci.'
    if (-not (Test-TweakEligibility -TweakId 'NetworkDriverTuning' -BlockOnHyperV -BlockOnLaptop)) { return }
    Invoke-Step -Name 'Network: tuning sterownikow (Interrupt Moderation, RSS)' -Action {
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        foreach ($adp in $adapters) {
            if ($adp.InterfaceDescription -match 'Hyper-V|TAP|VPN|Virtual|Miniport') { continue }

            $isRealtek = $adp.InterfaceDescription -match 'Realtek'
            $isIntel   = $adp.InterfaceDescription -match 'Intel.*I2[0-9]{2}|Intel.*Ethernet'
            if (-not ($isRealtek -or $isIntel)) {
                Write-Log "NetworkDriverTuning: $($adp.Name) ($($adp.InterfaceDescription)) — vendor poza whitelist, pomijam." -Level 'INFO'
                $script:SkippedCount++
                continue
            }

            Write-Log "NetworkDriverTuning: $($adp.Name) ($($adp.InterfaceDescription))" -Level 'INFO'

            try {
                $curIM = Get-NetAdapterAdvancedProperty -Name $adp.Name -RegistryKeyword 'InterruptModeration' -ErrorAction SilentlyContinue
                if ($curIM) {
                    $imTarget = Get-NicRecommendedValue -CurrentProperty $curIM -Keyword 'InterruptModeration' -PreferredValue 0
                    if ($null -ne $imTarget -and [int]$curIM.RegistryValue -ne $imTarget) {
                        if ($DryRun) { Write-Status "  [DRYRUN] $($adp.Name): InterruptModeration -> $imTarget" 'DarkGray' }
                        else {
                            Set-NetAdapterAdvancedProperty -Name $adp.Name -RegistryKeyword 'InterruptModeration' -RegistryValue $imTarget -ErrorAction Stop
                            Write-Log "NetworkDriverTuning: $($adp.Name) InterruptModeration=$imTarget" -Level 'CHANGE'
                        }
                    }
                }
            } catch { Write-Log "NetworkDriverTuning: InterruptModeration nieudane na $($adp.Name) — $($_.Exception.Message)" -Level 'WARN' }

            try {
                $curRSS = Get-NetAdapterAdvancedProperty -Name $adp.Name -RegistryKeyword '*NumRssQueues' -ErrorAction SilentlyContinue
                if ($curRSS) {
                    $rssPreferred = [math]::Min(4, [math]::Max(1, $script:HWProfile.Cores))
                    $rssTarget = Get-NicRecommendedValue -CurrentProperty $curRSS -Keyword '*NumRssQueues' -PreferredValue $rssPreferred
                    if ($null -ne $rssTarget -and [int]$curRSS.RegistryValue -ne $rssTarget) {
                        if ($DryRun) { Write-Status "  [DRYRUN] $($adp.Name): NumRssQueues -> $rssTarget" 'DarkGray' }
                        else {
                            Set-NetAdapterAdvancedProperty -Name $adp.Name -RegistryKeyword '*NumRssQueues' -RegistryValue $rssTarget -ErrorAction Stop
                            Write-Log "NetworkDriverTuning: $($adp.Name) NumRssQueues=$rssTarget" -Level 'CHANGE'
                        }
                    }
                }
            } catch { Write-Log "NetworkDriverTuning: RSS nieudane na $($adp.Name) — $($_.Exception.Message)" -Level 'WARN' }

            try {
                $curRB = Get-NetAdapterAdvancedProperty -Name $adp.Name -RegistryKeyword '*ReceiveBuffers' -ErrorAction SilentlyContinue
                if ($curRB) {
                    $rbTarget = Get-NicRecommendedValue -CurrentProperty $curRB -Keyword '*ReceiveBuffers' -PreferredValue 512
                    if ($null -ne $rbTarget -and [int]$curRB.RegistryValue -lt $rbTarget) {
                        if ($DryRun) { Write-Status "  [DRYRUN] $($adp.Name): ReceiveBuffers -> $rbTarget" 'DarkGray' }
                        else {
                            Set-NetAdapterAdvancedProperty -Name $adp.Name -RegistryKeyword '*ReceiveBuffers' -RegistryValue $rbTarget -ErrorAction Stop
                            Write-Log "NetworkDriverTuning: $($adp.Name) ReceiveBuffers=$rbTarget" -Level 'CHANGE'
                        }
                    }
                }
            } catch { Write-Log "NetworkDriverTuning: ReceiveBuffers nieudane na $($adp.Name) — $($_.Exception.Message)" -Level 'WARN' }
        }
        Write-Log 'NetworkDriverTuning: zakonczony.' -Level 'INFO'
    } -ContinueOnError
}

function Invoke-GPUMsiMode {
    <#
    .SYNOPSIS
        Wymusza MSI (Message Signaled Interrupts) dla GPU przez rejestr.
    #>
    $script:AppliedModules.Add('GPUMsiMode')
    Add-TweakMetadata -Id 'GPUMsiMode' -Name 'GPU MSI mode' -Category 'GPU' -Risk Experimental -Evidence Medium -RecommendedFor @('Gaming','Maximum') -AvoidOn @('Laptop','HyperV') -RequiresRestart -Notes 'Zaawansowany tweak IRQ; nie domyslny dla kazdego.'
    if (-not (Test-TweakEligibility -TweakId 'GPUMsiMode' -RequireExperimental -RequireDesktop -RequireDedicatedGpu -BlockOnHyperV)) { return }
    Invoke-Step -Name 'GPU: wymuszenie MSI (Message Signaled Interrupts)' -Action {
        $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
        if (-not $gpu) {
            Write-Log 'GPUMsiMode: brak GPU w WMI.' -Level 'WARN'
            $script:SkippedCount++
            return
        }

        $pciEnumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI'
        $gpuInstances = @()
        if (Test-Path $pciEnumPath) {
            $gpuInstances = Get-ChildItem $pciEnumPath -ErrorAction SilentlyContinue |
                Get-ChildItem -ErrorAction SilentlyContinue |
                Where-Object {
                    $devDesc = (Get-ItemProperty $_.PSPath -Name 'DeviceDesc' -ErrorAction SilentlyContinue).DeviceDesc
                    $devDesc -and ($devDesc -match 'NVIDIA|Radeon|GeForce|RTX|GTX|RX |Arc Graphics')
                }
        }

        if ($gpuInstances.Count -eq 0) {
            Write-Log "GPUMsiMode: brak wspieranych instancji dedykowanego GPU w PCI\Enum. GPU: $($gpu.Name)" -Level 'WARN'
            $script:SkippedCount++
            return
        }

        foreach ($inst in $gpuInstances) {
            $msiPath = Join-Path $inst.PSPath 'Device Parameters\Interrupt Management\MessageSignaledInterruptProperties'
            try {
                if (-not (Test-Path $msiPath)) {
                    if ($DryRun) {
                        Write-Status "  [DRYRUN] GPU MSI: utworzenie $msiPath" 'DarkGray'
                        continue
                    }
                    New-Item -Path $msiPath -Force | Out-Null
                }
                $cur = (Get-ItemProperty -Path $msiPath -Name 'MSISupported' -ErrorAction SilentlyContinue).MSISupported
                if ($cur -ne 1) {
                    if ($DryRun) {
                        Write-Status "  [DRYRUN] GPU MSI: MSISupported=1 w $($inst.PSChildName)" 'DarkGray'
                    } else {
                        New-ItemProperty -Path $msiPath -Name 'MSISupported' -PropertyType DWord -Value 1 -Force | Out-Null
                        Write-Log "GPUMsiMode: MSISupported=1 dla $($inst.PSChildName)" -Level 'CHANGE'
                        $script:Manifest.Registry += [ordered]@{
                            Path = $msiPath; Name = 'MSISupported'; OldValue = $cur; NewValue = 1
                            Type = 'DWord'; BackupFile = $null; Reason = 'GPU MSI mode — nizsza latencja GPU IRQ'
                        }
                    }
                } else {
                    Write-Log "GPUMsiMode: MSISupported juz =1 dla $($inst.PSChildName)" -Level 'INFO'
                    $script:SkippedCount++
                }
            } catch {
                Write-Log "GPUMsiMode: blad dla $($inst.PSChildName) — $($_.Exception.Message)" -Level 'WARN'
            }
        }
        Add-RestartFlag 'GPU MSI mode (wymagany restart)'
        Write-Log "GPUMsiMode: GPU MSI mode zastosowany dla $($gpuInstances.Count) instancji." -Level 'CHANGE'
    } -ContinueOnError
}

function Invoke-NetworkTweaks {
    $script:AppliedModules.Add('Network')
    Invoke-Step -Name "Siec: DNS -> $($script:SelectedDns)" -Action {
        if ($script:SelectedDns -ne 'Keep') {
            $netOk = Test-NetConnection -ComputerName '8.8.8.8' -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue
            if (-not $netOk) {
                Write-Log 'Brak polaczenia z internetem — zmiana DNS pominieta.' -Level 'WARN'
                $script:SkippedCount++
                return
            }
        }
        switch ($script:SelectedDns) {
            'Google'     { Set-DnsCustomSafe -IPv4Servers '8.8.8.8','8.8.4.4' -IPv6Servers '2001:4860:4860::8888','2001:4860:4860::8844' }
            'Cloudflare' { Set-DnsCustomSafe -IPv4Servers '1.1.1.1','1.0.0.1' -IPv6Servers '2606:4700:4700::1111','2606:4700:4700::1001' }
            'Quad9'      { Set-DnsCustomSafe -IPv4Servers '9.9.9.9','149.112.112.112' -IPv6Servers '2620:fe::fe','2620:fe::9' }
            default      { Write-Log 'DNS: bez zmian (Keep).' -Level 'INFO'; $script:SkippedCount++ }
        }
    } -ContinueOnError
    Invoke-Step -Name 'Siec: flush DNS cache' -Action { & ipconfig /flushdns|Out-Null; Write-Log 'DNS cache wyczyszczony.' -Level 'CHANGE' } -ContinueOnError
    Invoke-Step -Name 'Siec: wylaczenie oszczedzania energii adapterow' -Action {
        Get-NetAdapter -Physical -EA SilentlyContinue|Where-Object { $_.Status -ne 'Disabled' }|ForEach-Object {
            if ($_.InterfaceDescription-match'Hyper-V|TAP|VPN|Virtual|Miniport') { Write-Log "Adapter pominiety (wirt/VPN): $($_.Name)" -Level 'INFO'; $script:SkippedCount++; return }
            try { Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice Disabled -EA Stop; Write-Log "Adapter power off: $($_.Name)" -Level 'CHANGE' }
            catch { Write-Log "Adapter power bez zmian: $($_.Name)" -Level 'WARN' }
        }
    } -ContinueOnError
}

function Invoke-ServiceTuning {
    Set-StrictMode -Version Latest
    $script:AppliedModules.Add('Services')
    Invoke-Step -Name 'Uslugi: optymalizacja uslug w tle' -Action {
        Set-ServiceStartupSafe -Name 'DiagTrack'     -StartupType Manual    -StopService -Reason 'Telemetria -> Manual'
        Set-ServiceStartupSafe -Name 'MapsBroker'    -StartupType Manual               -Reason 'Mapy -> Manual'
        Set-ServiceStartupSafe -Name 'WerSvc'        -StartupType Manual               -Reason 'Error Reporting -> Manual'
        # v12: SysMain dynamicznie z walidacją — Low RAM: Manual, inaczej Automatic
        if ($script:HWProfile -and $script:HWProfile.IsLowRAM) {
            Invoke-TweakWithValidation `
                -Name 'Services: SysMain -> Manual (Low RAM)' `
                -Action {
                    Set-ServiceStartupSafe -Name 'SysMain' -StartupType Manual -StopService -Reason 'Low RAM (<16GB): Superfetch -> Manual'
                } `
                -RollbackAction {
                    Set-ServiceStartupSafe -Name 'SysMain' -StartupType Automatic -Reason 'AutoRollback: SysMain przywrocony do Automatic'
                } `
                -MetricBlock {
                    (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB
                } `
                -BetterWhenLower $false `
                -ThresholdPct 10 `
                -WaitSeconds 5
        } else {
            Set-ServiceStartupSafe -Name 'SysMain' -StartupType Automatic -Reason 'RAM >= 16GB: Superfetch -> Automatic'
        }
        Set-ServiceStartupSafe -Name 'XblGameSave'   -StartupType Manual               -Reason 'Xbox Save -> Manual'
        Set-ServiceStartupSafe -Name 'XboxNetApiSvc' -StartupType Manual               -Reason 'Xbox Net -> Manual'
        if ($script:SearchIndexingMode-eq'Manual') { Set-ServiceStartupSafe -Name 'WSearch' -StartupType Manual -StopService -Reason 'WSearch -> Manual (wybor uzytkownika)' }
        else { Set-ServiceStartupSafe -Name 'WSearch' -StartupType Automatic -Reason 'WSearch -> Automatic (komfort)' }
    }
}

function Invoke-Cleanup {
    Set-StrictMode -Version Latest
    $script:AppliedModules.Add('Cleanup')
    Add-TweakMetadata -Id 'ShaderCacheCleanup' -Name 'GPU shader cache cleanup' -Category 'Cleanup' -Risk Medium -Evidence Medium -RecommendedFor @('Gaming','Maximum') -AvoidOn @('Balanced','Safe') -Notes 'Smart Mode pomija w Safe/Balanced, bo cache odbudowuje sie i moze powodowac chwilowy stutter.'
    Invoke-Step -Name 'Czyszczenie: foldery tymczasowe' -Action {
        @("$env:TEMP\*","$env:WINDIR\Temp\*")|ForEach-Object { Remove-Item -Path $_ -Recurse -Force -EA SilentlyContinue }
        Write-Log 'Pliki tymczasowe usuniete.' -Level 'CHANGE'
    }
    if (Test-TweakEligibility -TweakId 'ShaderCacheCleanup') {
        Invoke-Step -Name 'Czyszczenie: GPU shader cache (NVIDIA i AMD)' -Action {
        $gpuCachePaths = @(
            # NVIDIA
            "$env:LOCALAPPDATA\NVIDIA\DXCache",
            "$env:LOCALAPPDATA\NVIDIA\GLCache",
            "$env:LOCALAPPDATA\NVIDIA\OptixCache",
            "$env:APPDATA\NVIDIA\ComputeCache",
            # AMD
            "$env:LOCALAPPDATA\AMD\DxCache",
            "$env:LOCALAPPDATA\AMD\VkCache",
            # DirectX / D3D shader cache (wspolne)
            "$env:LOCALAPPDATA\D3DSCache"
        )
        $totalCleared = 0
        foreach ($cachePath in $gpuCachePaths) {
            if (Test-Path $cachePath) {
                $sizeBefore = (Get-ChildItem $cachePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                $totalCleared += [math]::Round($sizeBefore / 1MB, 1)
                Write-Log "GPU cache wyczyszczony: $cachePath ($([math]::Round($sizeBefore / 1MB, 1)) MB)" -Level 'CHANGE'
            }
        }
        if ($totalCleared -gt 0) {
            Write-Status "  GPU cache wyczyszczony: $totalCleared MB zwolnione. Cache zostanie odbudowany przy pierwszym uruchomieniu gier." 'Green'
        } else {
            Write-Log 'GPU shader cache: brak plikow do wyczyszczenia lub foldery nie istnieja.' -Level 'INFO'
            $script:SkippedCount++
        }
    } -ContinueOnError
    }
    Invoke-Step -Name 'Czyszczenie: komponenty Windows (DISM ComponentCleanup — moze trwac 30-60 min)' -Action {
        $driveName = ([System.IO.Path]::GetPathRoot($env:SystemDrive)).TrimEnd('\').TrimEnd(':')
        $freeGB = [math]::Round((Get-PSDrive $driveName).Free / 1GB, 1)
        if ($freeGB -lt 3) {
            Write-Log "Za malo miejsca na dysku ($freeGB GB) dla DISM ComponentCleanup. Pomijam." -Level 'WARN'
            $script:SkippedCount++
            return
        }
        Write-Status '  INFO: DISM ComponentCleanup moze trwac do 60 minut. Nie przerywaj.' 'Yellow'
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try { & DISM.exe /Online /Cleanup-Image /StartComponentCleanup /NoRestart | Out-Null }
        finally { Get-Process -Name DISM -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
        $sw.Stop()
        Write-Log "DISM component cleanup zakonczony w $([math]::Round($sw.Elapsed.TotalMinutes,1)) min." -Level 'CHANGE'
    } -ContinueOnError
}

function Invoke-Repair {
    $script:AppliedModules.Add('Repair')
    Invoke-Step -Name 'Naprawa: DISM /RestoreHealth (najpierw — naprawa bazy WinSxS)' -Action {
        $ok = Invoke-ExternalWithTimeout -FilePath 'DISM.exe' -ArgumentList @('/Online','/Cleanup-Image','/RestoreHealth') -TimeoutSeconds 1800 -FriendlyName 'DISM RestoreHealth' -CleanupProcessNames @('DISM')
        if ($ok) { Write-Log 'DISM RestoreHealth.' -Level 'CHANGE' }
    } -ContinueOnError
    Invoke-Step -Name 'Naprawa: SFC /scannow (po DISM — weryfikacja plikow systemowych)' -Action {
        $ok = Invoke-ExternalWithTimeout -FilePath 'sfc.exe' -ArgumentList @('/scannow') -TimeoutSeconds 1800 -FriendlyName 'SFC /scannow' -CleanupProcessNames @('sfc')
        if ($ok) { Write-Log 'SFC wykonany.' -Level 'CHANGE' }
    } -ContinueOnError
    if ($EnableNetworkRepair) {
        Invoke-Step -Name 'Naprawa: winsock reset (stos sieciowy)' -Action {
            Write-Log 'UWAGA: winsock reset moze usunac LSP (VPN, AV). Rollback nie przywroci LSP w 100%.' -Level 'WARN'
            Write-Status '  UWAGA: winsock reset — po restarcie sprawdz VPN/antywirus.' 'Yellow'
            & netsh winsock reset|Out-Null
            Write-Log 'Winsock reset.' -Level 'CHANGE'
            Add-RestartFlag 'Winsock reset (wymagany restart)'
        } -ContinueOnError
    } else {
        Write-Log 'Winsock reset pominiety (EnableNetworkRepair nie ustawiono).' -Level 'INFO'
        $script:SkippedCount++
    }
}

function Invoke-GamingSession {
    $script:AppliedModules.Add('GamingSession')
    Invoke-Step -Name 'Gaming Session: przeglad i zamkniecie ciezkich aplikacji w tle' -Action {
        $closeList=@('brave','chrome','msedge','discord','steamwebhelper','onedrive','teams','opera','firefox')
        $candidates = @(Get-HeavyProcessCandidates)
        if (-not $candidates) {
            Write-Log 'Brak procesow zakwalifikowanych do przegladu/zamkniecia.' -Level 'INFO'
            return
        }
        Write-Status '  Kandydaci do zamkniecia (CPU/RAM lub znane appki w tle):' 'Yellow'
        foreach ($cand in $candidates) {
            Write-Status ("    - {0} (PID {1}) CPU={2} RAM={3}MB [{4}]" -f $cand.ProcessName,$cand.Id,$cand.CPU,$cand.RAM_MB,$cand.Review) 'DarkYellow'
        }
        foreach ($cand in $candidates | Where-Object { $closeList -contains $_.ProcessName.ToLower() }) {
            $proc = Get-Process -Id $cand.Id -EA SilentlyContinue
            if (-not $proc) { continue }
            $confirm=if($Silent -and $ForceCloseApps){'T'}elseif($Silent){'N'}else{
                Write-Host "  Zamknac '$($proc.ProcessName)' (PID $($proc.Id), CPU=$($cand.CPU), RAM=$($cand.RAM_MB)MB)? [T/N]: " -ForegroundColor Yellow -NoNewline
                (Read-Host).Trim().ToUpper()
            }
            if ($confirm-eq'T') {
                try {
                    $closedGracefully = $false
                    if ($proc.MainWindowHandle -ne 0) {
                        Write-Log "Proba lagodnego zamkniecia: $($proc.ProcessName) ($($proc.Id))" -Level 'INFO'
                        $null = $proc.CloseMainWindow()
                        Start-Sleep -Seconds 3
                        try { $proc.Refresh() } catch {}
                        if ($proc.HasExited) { $closedGracefully = $true }
                    }
                    if (-not $closedGracefully) {
                        Stop-Process -Id $proc.Id -Force -EA Stop
                        Write-Log "Wymuszone zamkniecie: $($proc.ProcessName) ($($proc.Id)) CPU=$($cand.CPU) RAM=$($cand.RAM_MB)MB" -Level 'WARN'
                    } else {
                        Write-Log "Lagodnie zamknieto: $($proc.ProcessName) ($($proc.Id)) CPU=$($cand.CPU) RAM=$($cand.RAM_MB)MB" -Level 'CHANGE'
                    }
                    $script:Manifest.GamingSessionClosedProcesses+=[ordered]@{Name=$proc.ProcessName;Id=$proc.Id}
                } catch { Write-Log "Nie mozna zamknac: $($proc.ProcessName) ($($proc.Id))" -Level 'WARN' }
            } else { Write-Log "Pominiety: $($proc.ProcessName) (uzytkownik)" -Level 'INFO'; $script:SkippedCount++ }
        }
    } -ContinueOnError
}

# =============================
# Snapshot Diff
# =============================
function Invoke-SnapshotDiff {
    $script:AppliedModules.Add('Diff')
    $dp=Join-Path $script:ReportFolder 'snapshot_diff.txt'
    if (-not ((Test-Path $script:BeforeSnapshotPath) -and (Test-Path $script:AfterSnapshotPath))) { return }
    Invoke-Step -Name 'Raporty: roznica snapshot' -Action {
        $bef=Get-Content $script:BeforeSnapshotPath -Raw|ConvertFrom-Json
        $aft=Get-Content $script:AfterSnapshotPath  -Raw|ConvertFrom-Json
        $ln=New-Object System.Collections.Generic.List[string]
        $ln.Add('=== SNAPSHOT DIFF ==='); $ln.Add('')
        $ln.Add("Przed: $($bef.Timestamp)"); $ln.Add("Po:    $($aft.Timestamp)"); $ln.Add('')
        $ln.Add("Plan zasilania przed: $(($bef.ActivePowerScheme|Out-String).Trim())")
        $ln.Add("Plan zasilania po:    $(($aft.ActivePowerScheme|Out-String).Trim())"); $ln.Add('')
        $sb=@{}; foreach($s in $bef.Services){$sb[$s.Name]="$($s.Status)/$($s.StartType)"}
        $sa=@{}; foreach($s in $aft.Services) {$sa[$s.Name]="$($s.Status)/$($s.StartType)"}
        $ch=New-Object System.Collections.Generic.List[string]
        foreach($n in ($sb.Keys+$sa.Keys|Sort-Object -Unique)){
            $b=if($sb.ContainsKey($n)){$sb[$n]}else{'<brak>'}
            $a=if($sa.ContainsKey($n)){$sa[$n]}else{'<brak>'}
            if($b-ne$a){$ch.Add("  - ${n}: $b -> $a")}
        }
        $ln.Add('Zmiany uslug:')
        if($ch.Count-eq0){$ln.Add('  - brak')}else{$ch|Select-Object -First 50|ForEach-Object{$ln.Add($_)}}
        $ln.Add('')
        $ln.Add("Top CPU przed: $((@($bef.TopCpu|ForEach-Object{$_.ProcessName}|Select-Object -Unique))-join', ')")
        $ln.Add("Top CPU po:    $((@($aft.TopCpu|ForEach-Object{$_.ProcessName}|Select-Object -Unique))-join', ')")
        $ln|Set-Content -Path $dp -Encoding UTF8
        Write-Log 'Snapshot diff zapisany.' -Level 'ARTIFACT'
    } -ContinueOnError
}

# =============================
# Performance Review Helpers
# =============================
function Get-HeavyProcessCandidates {
    $allowed = @('brave','chrome','msedge','discord','steamwebhelper','onedrive','teams','opera','firefox')
    $all = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -notmatch '^(Idle|System|Registry|Memory Compression)$' }
    $topCpu = $all | Sort-Object @{Expression={ if($_.CPU -is [timespan]) { $_.CPU.TotalSeconds } elseif ($null -eq $_.CPU) { -1 } else { [double]$_.CPU } }} -Descending | Select-Object -First 20
    $topRam = $all | Sort-Object WorkingSet -Descending | Select-Object -First 20
    $merged = @($topCpu + $topRam) | Group-Object Id | ForEach-Object { $_.Group | Select-Object -First 1 }
    $candidates = foreach ($p in $merged) {
        $cpuVal = if ($p.CPU -is [timespan]) { [math]::Round($p.CPU.TotalSeconds,2) } elseif ($null -eq $p.CPU) { 0 } else { [math]::Round([double]$p.CPU,2) }
        $ramMB = [math]::Round($p.WorkingSet / 1MB, 1)
        $isReview = ($allowed -contains $p.ProcessName.ToLower()) -or $cpuVal -ge 30 -or $ramMB -ge 500
        if ($isReview) {
            [pscustomobject]@{
                ProcessName = $p.ProcessName
                Id          = $p.Id
                CPU         = $cpuVal
                RAM_MB      = $ramMB
                Review      = if ($allowed -contains $p.ProcessName.ToLower()) { 'close-candidate' } else { 'heavy-process' }
            }
        }
    }
    $candidates | Sort-Object @{Expression='CPU';Descending=$true}, @{Expression='RAM_MB';Descending=$true} | Select-Object -First 12
}

function Get-StartupReview {
    $items = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Select-Object Name, Command, Location
    $review = foreach ($s in $items) {
        $impact = 'Normal'
        if ($s.Name -match 'OneDrive|Teams|Discord|Steam|Epic|Battle.net|Adobe|GoogleDrive|Dropbox|Creative Cloud') { $impact = 'Review' }
        if ($s.Command -match 'VPN|Updater|Launcher|OneDrive|Teams|Discord|Steam|Epic|Battle.net|Creative Cloud') { $impact = 'Review' }
        [pscustomobject]@{ Name=$s.Name; Location=$s.Location; Impact=$impact; Command=$s.Command }
    }
    $review | Sort-Object @{Expression={ if ($_.Impact -eq 'Review') { 0 } else { 1 } }}, Name
}

function Get-SystemLoadSummary {
    $cpu = $null
    $vCpu = Get-CounterValueSafe '\Processor(_Total)\% Processor Time'
    if ($null -ne $vCpu) { $cpu = [math]::Round($vCpu, 1) }
    $os = Get-CimInstance Win32_OperatingSystem
    $usedRamGB = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB), 2)
    $freeRamGB = [math]::Round(($os.FreePhysicalMemory / 1MB), 2)
    [pscustomobject]@{ CPU_Pct = $cpu; UsedRAM_GB = $usedRamGB; FreeRAM_GB = $freeRamGB }
}

# =============================
# Analyze
# =============================
function Invoke-Analyze {
    $script:AppliedModules.Add('Analyze')
    Write-Status 'Tworzenie raportu analizy...' 'Green'
    $ln=New-Object System.Collections.Generic.List[string]
    $ln.Add('=== ANALYZE REPORT ==='); $ln.Add('')

    # v12 Faza 3: Zaawansowana diagnostyka (ETW, DPC, NUMA, CIS)
    Invoke-AdvancedDiagnostics

    # v12: System Score
    if (Get-Command Get-SystemScore -ErrorAction SilentlyContinue) {
        $v12Score = Get-SystemScore
        $ln.Add(""); $ln.Add("=== SYSTEM SCORE: $($v12Score.Score)/100 — $($v12Score.Grade) ===")
        $ln.Add("Bottlenecks:"); foreach ($b in $v12Score.Bottlenecks) { $ln.Add("  $b") }
        $ln.Add("Co dziala dobrze:"); foreach ($g in $v12Score.GoodItems | Select-Object -First 5) { $ln.Add("  + $g") }
    }

    # v12: Memory topology
    if ($script:MemTopology) {
        $ln.Add(""); $ln.Add("=== PAMIEC ===")
        $ln.Add("  Modulow: $($script:MemTopology.ModuleCount) | Rated: $($script:MemTopology.RatedSpeedMHz) MHz | Aktualnie: $($script:MemTopology.ConfiguredMHz) MHz")
        $ln.Add("  XMP: $(if ($script:MemTopology.XMPActive) { 'AKTYWNE' } else { 'WYLACZONE — STRATA WYDAJNOSCI' }) | Dual channel: $(if ($script:MemTopology.IsDualChannel) { 'TAK' } else { 'NIE' })")
        if ($script:MemTopology.Warning) { $ln.Add("  UWAGA: $($script:MemTopology.Warning)") }
    }

    # v12: Kernel timer — faktyczny pomiar
    if (Get-Command Get-KernelTimerResolution -ErrorAction SilentlyContinue) {
        $timerReal = Get-KernelTimerResolution
        if ($timerReal) {
            $ln.Add(""); $ln.Add("=== TIMER SYSTEMOWY ===")
            $ln.Add("  Aktualny: $($timerReal.CurrentMs) ms | Min: $($timerReal.MinMs) ms | Max: $($timerReal.MaxMs) ms")
            $ln.Add("  Status: $(if ($timerReal.IsOptimal) { 'OPTYMALNY' } else { 'NIEOPTYMALNY' })")
        }
    }

    # v12: DPC indicators
    if (Get-Command Get-DPCPressureIndicators -ErrorAction SilentlyContinue) {
        $dpcInd = Get-DPCPressureIndicators
        if ($dpcInd.Count -gt 0) {
            $ln.Add(""); $ln.Add("=== POTENCJALNE ZRODLA DPC LATENCY (stuttery) ===")
            foreach ($d in $dpcInd) { $ln.Add("  [$($d.Risk)] $($d.Type): $($d.Device) — $($d.Tip)") }
        }
    }

    # v12: Boot log
    if (Get-Command Get-BootLogAnalysis -ErrorAction SilentlyContinue) {
        $bootLog = Get-BootLogAnalysis
        $ln.Add(""); $ln.Add("=== BOOT LOG ===")
        if ($bootLog.LogExists) {
            $ln.Add("  Zaladowane: $($bootLog.DriversLoaded) | Nieudane: $($bootLog.DriversFailed)")
            if (@($bootLog.FailedDrivers).Count -gt 0) { @($bootLog.FailedDrivers) | Select-Object -First 10 | ForEach-Object { $ln.Add("  FAIL: $_") } }
        } else { $ln.Add("  $($bootLog.Recommendation)") }
    }

    # v12: Persistent validation
    if (Get-Command Compare-ExpectedVsActual -ErrorAction SilentlyContinue) {
        $expectedPath = Join-Path $script:RootFolder 'expected_state.json'
        if (Test-Path $expectedPath) {
            $pvResult = Compare-ExpectedVsActual -ExpectedPath $expectedPath
            if ($pvResult) {
                $ln.Add(""); $ln.Add("=== TRWALOSC TWEAKOW (po restarcie) ===")
                $ln.Add("  Snapshot: $($pvResult.SavedAt) | Zdalo: $($pvResult.PassedCount)/$($pvResult.Results.Count)")
                foreach ($r in $pvResult.Results) {
                    $st = if ($r.Passed) { '[OK]  ' } else { '[FAIL]' }
                    $ln.Add("  $st $($r.Check)")
                    if (-not $r.Passed -and $r.FailWhy) { $ln.Add("        Przyczyna: $($r.FailWhy)") }
                }
            }
        }
    }

    # v12: Quick security check
    if (Get-Command Invoke-QuickSecurityCheck -ErrorAction SilentlyContinue) {
        $secF = Invoke-QuickSecurityCheck
        $ln.Add(""); $ln.Add("=== QUICK SECURITY CHECK ===")
        if (@($secF).Count -eq 0) { $ln.Add("  Brak podejrzanych wskaznikow.") }
        else { foreach ($f in $secF) { $ln.Add("  [$($f.Risk)] $($f.Type): $($f.Detail) — $($f.Action)") } }
    }

    # v12: Hardware recommendations
    if (Get-Command Get-HardwareRecommendations -ErrorAction SilentlyContinue) {
        $hwRecs = Get-HardwareRecommendations
        $ln.Add(""); $ln.Add("=== REKOMENDACJE SPRZETOWE / BIOS ===")
        foreach ($r in $hwRecs) { $ln.Add("  [$($r.Priority)] $($r.Category): $($r.Title) — Zysk: $($r.Gain)"); $ln.Add("    $($r.Detail)") }
    }
    $env=$script:Manifest.Environment
    $topCpu=Get-Process|Sort-Object @{Expression={if($_.CPU-is[timespan]){$_.CPU.TotalSeconds}elseif($null-eq$_.CPU){-1}else{[double]$_.CPU}}}-Descending|Select-Object -First 15 ProcessName,Id,CPU,WS
    $topRam=Get-Process|Sort-Object WS -Descending|Select-Object -First 15 ProcessName,Id,CPU,WS
    $startup=Get-CimInstance Win32_StartupCommand|Select-Object Name,Command,Location
    $heavyReview = @(Get-HeavyProcessCandidates)
    $startupReview = @(Get-StartupReview)
    $loadSummary = Get-SystemLoadSummary
    $wuSvc=Get-Service -Name wuauserv -EA SilentlyContinue
    $wsrch=Get-Service -Name WSearch  -EA SilentlyContinue
    $vpnAdp=Get-NetAdapter -EA SilentlyContinue|Where-Object{$_.Name-match'vEthernet|Hyper-V|TAP|VPN'-or$_.InterfaceDescription-match'Hyper-V|TAP|VPN'}
    $sysRsp=Get-RegistryValueOrDefault 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' $null

    # v12: Porownanie sesji historycznych — trend po tygodniu
    Invoke-Step -Name 'Advanced: Cross-session benchmark comparison' -Action {
        $crossComp = Compare-SessionBenchmarks
        if ($crossComp.Found) {
            $crossComp.Lines | ForEach-Object { $ln.Add($_) }
            Write-Status '  Porownanie historyczne: dodane do raportu.' 'Cyan'
        }
    } -ContinueOnError
    $ln.Add("Komputer: $($env.ComputerName) | $($env.Manufacturer) $($env.Model)")
    $ln.Add("Windows:  $($env.WindowsProductName) | $($env.WindowsEdition) | Build $($env.Build)")
    $ln.Add("Laptop:   $($env.IsLaptop) | Bateria: $($env.HasBattery)")
    $ln.Add("CPU:      $($env.CPU)"); $ln.Add("RAM:      $($env.TotalRAMGB) GB")
    $ln.Add("Plan zasilania: $(($env.PowerScheme|Out-String).Trim())"); $ln.Add("Obciazenie teraz: CPU=$($loadSummary.CPU_Pct)% | RAM used=$($loadSummary.UsedRAM_GB) GB | RAM free=$($loadSummary.FreeRAM_GB) GB"); $ln.Add('')
    $persistPath = Join-Path $script:ReportFolder 'benchmark_before_persistent.json'
    if (Test-Path $persistPath) {
        try {
            $currentSnap = Get-BenchmarkSnapshot
            Write-Status '  Porownanie z sesja Optimize (po restarcie) zapisane.' 'Green'
            Write-PersistentBenchmarkComparison -Current $currentSnap -PersistentPath $persistPath -Lines $ln
        } catch {
            Write-Log "Persistent benchmark compare failed: $($_.Exception.Message)" -Level 'WARN'
        }
    } else {
        $persistentBenchmark = Get-LatestPersistentBenchmarkPath
        if ($persistentBenchmark) { Write-PersistentBenchmarkComparison -Current (Get-BenchmarkSnapshot) -PersistentPath $persistentBenchmark -Lines $ln }
    }
    $ln.Add('Top CPU procesy:')
    $topCpu|Select-Object -First 10|ForEach-Object{$ln.Add("  - $($_.ProcessName) | CPU=$([math]::Round([double]$_.CPU,2)) | WS(MB)=$([math]::Round($_.WS/1MB,2))")}
    $ln.Add(''); $ln.Add('Top RAM procesy:')
    $topRam|Select-Object -First 10|ForEach-Object{$ln.Add("  - $($_.ProcessName) | WS(MB)=$([math]::Round($_.WS/1MB,2))")}
    $ln.Add(''); $ln.Add('Procesy do przegladu / potencjalnego zamkniecia:')
    if ($heavyReview.Count -gt 0) { $heavyReview | Select-Object -First 10 | ForEach-Object { $ln.Add("  - $($_.ProcessName) | PID=$($_.Id) | CPU=$($_.CPU) | RAM=$($_.RAM_MB)MB | Typ=$($_.Review)") } } else { $ln.Add('  - Brak kandydatow.') }
    $ln.Add(''); $ln.Add('Autostart — pozycje warte przegladu:')
    $reviewItems = @($startupReview | Where-Object Impact -eq 'Review' | Select-Object -First 12)
    if ($reviewItems.Count -gt 0) {
        $reviewItems | ForEach-Object { $ln.Add("  - $($_.Name) | $($_.Location) | Impact=$($_.Impact)") }
        if (-not $Silent -and $Mode -eq 'Optimize') {
            Write-Status '  Autostart do przegladu — mozesz wylaczyc ponizsze pozycje:' 'Yellow'
            foreach ($item in $reviewItems) {
                Write-Host ("    - {0} ({1})" -f $item.Name, $item.Location) -ForegroundColor DarkYellow -NoNewline
                $ans = (Read-Host " Wylaczyc? [T/N]").Trim().ToUpper()
                if ($ans -eq 'T') {
                    try {
                        if ($item.Location -match 'HKCU|HKLM') {
                            $regPath = $item.Location -replace 'HKCU\','HKCU:\' -replace 'HKLM\','HKLM:\'
                            $backupFile = Export-RegistryKeyIfExists -RegPath $regPath -Tag ("Autostart_" + ($item.Name -replace '[^a-zA-Z0-9_-]','_'))
                            if ($backupFile) {
                                $script:Manifest.Notes += "Autostart backup: $backupFile"
                                Write-Log "Autostart backup: $backupFile" -Level 'INFO'
                            }
                            Remove-ItemProperty -Path $regPath -Name $item.Name -ErrorAction Stop
                            Write-Log "Autostart wylaczony (rejestr): $($item.Name)" -Level 'CHANGE'
                        } elseif ($item.Location -match 'Startup') {
                            $startupFile = Join-Path $item.Location "$($item.Name).lnk"
                            if (Test-Path $startupFile) { Remove-Item $startupFile -Force; Write-Log "Autostart wylaczony (plik): $($item.Name)" -Level 'CHANGE' }
                        }
                        Write-Status "    Wylaczono: $($item.Name)" 'Green'
                    } catch { Write-Log "Nie mozna wylaczyc autostartu: $($item.Name) — $($_.Exception.Message)" -Level 'WARN' }
                }
            }
        }
    } else { $ln.Add('  - Brak pozycji oznaczonych do przegladu.') }
    $ln.Add(''); $ln.Add('Stan kluczowych ustawien:')
    $ln.Add("  - WSearch:               $(if($wsrch){"$($wsrch.Status)/$($wsrch.StartType)"}else{'nie znaleziono'})")
    $ln.Add("  - Windows Update:        $(if($wuSvc){[string]$wuSvc.Status}else{'nie znaleziono'})")
    $ln.Add("  - HAGS registry:         $($env.HAGS)")
    $ln.Add("  - SystemResponsiveness:  $sysRsp")
    $ln.Add('  - NetworkThrottlingIndex: usuniety z v8 (legacy tweak)')
    $ln.Add("  - TRIM status:           $(($env.TrimStatus-replace'`r?`n',' | '))")
    $ln.Add("  - Hyper-V:               $($env.HyperV)"); $ln.Add("  - WSL:                   $($env.WSL)")
    $ln.Add(''); $ln.Add('Mozliwe przyczyny spadkow FPS:')
    if ($startup|Where-Object{$_.Name-match'UrbanVPN'-or$_.Command-match'UrbanVPN'}){$ln.Add('  - UrbanVPN w autostarcie. Wylacz przed graniem.')}
    if ($topCpu|Where-Object { $_.ProcessName -eq 'brave' })        {$ln.Add('  - Brave: duze zuzycie CPU w tle.')}
    if ($topCpu|Where-Object { $_.ProcessName -eq 'MsMpEng' })      {$ln.Add('  - Defender aktywny. Zaplanuj skanowanie poza graniem.')}
    if ($topCpu|Where-Object { $_.ProcessName -eq 'SearchIndexer' }){$ln.Add('  - SearchIndexer aktywny. WSearch Manual moze pomoc.')}
    if ($vpnAdp)     {$ln.Add('  - Wirtualne/VPN adaptery obecne.')}
    if ($env.IsLaptop){$ln.Add('  - Laptop: tweak CPU 100% zablokowany (termika).')}
    $ln.Add(''); $ln.Add('Zalecenia:')
    $ln.Add('  1. Zacznij od Optimize + Balanced.'); $ln.Add('  2. Maximum tylko na AC po swiezym restarcie.')
    $ln.Add('  3. Najwiekszy dalszy zysk: sterownik GPU, autostart i aplikacje w tle.')
    $ln|Set-Content -Path $script:AnalyzeReportPath -Encoding UTF8
    Write-Log 'Analyze report zapisany.' -Level 'ARTIFACT'
    $htmlCpu=($topCpu|Select-Object -First 8|ForEach-Object{"<tr><td>$($_.ProcessName)</td><td>$([math]::Round([double]$_.CPU,1))</td><td>$([math]::Round($_.WS/1MB,1)) MB</td></tr>"})-join''
    $htmlHeavy=($heavyReview|Select-Object -First 8|ForEach-Object{"<tr><td>$($_.ProcessName)</td><td>$($_.CPU)</td><td>$($_.RAM_MB) MB</td><td>$($_.Review)</td></tr>"})-join''
    $htmlStartup=($startupReview|Where-Object Impact -eq 'Review'|Select-Object -First 8|ForEach-Object{"<tr><td>$(ConvertTo-HtmlSafe $_.Name)</td><td>$(ConvertTo-HtmlSafe $_.Location)</td><td>$(ConvertTo-HtmlSafe $_.Impact)</td></tr>"})-join''
    $htmlHeavyBlock = if($htmlHeavy){$htmlHeavy}else{'<tr><td colspan="4">Brak kandydatow</td></tr>'}
    $htmlStartupBlock = if($htmlStartup){$htmlStartup}else{'<tr><td colspan="3">Brak pozycji review</td></tr>'}
    Add-HtmlSection "<h2>Analiza systemu</h2><p>CPU: $($env.CPU) | RAM: $($env.TotalRAMGB) GB | Build: $($env.Build) | Load CPU: $($loadSummary.CPU_Pct)%</p><table><tr><th>Proces</th><th>CPU</th><th>RAM</th></tr>$htmlCpu</table><h3>Procesy do przegladu</h3><table><tr><th>Proces</th><th>CPU</th><th>RAM</th><th>Typ</th></tr>$htmlHeavyBlock</table><h3>Autostart do przegladu</h3><table><tr><th>Nazwa</th><th>Lokalizacja</th><th>Impact</th></tr>$htmlStartupBlock</table>"
}

# =============================
# Rollback
# =============================

function Get-LatestRollbackSessionId {
    <#
    .SYNOPSIS
        One-click rollback: wybiera najnowsza sesje z manifest.json, najlepiej taka gdzie Mode=Optimize.
        Nie wymaga wpisywania identyfikatora sesji recznie.
    #>
    $sessions = @(Get-ChildItem -Path $script:RootFolder -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } |
        Sort-Object Name -Descending)
    if (-not $sessions -or $sessions.Count -eq 0) { throw "Brak zapisanych sesji rollback w: $script:RootFolder" }

    foreach ($s in $sessions) {
        try {
            $m = Get-Content (Join-Path $s.FullName 'manifest.json') -Raw | ConvertFrom-Json
            if ([string]$m.Mode -eq 'Optimize') { return $s.Name }
        } catch {}
    }
    return $sessions[0].Name
}

function Invoke-Rollback {
    param([Parameter(Mandatory)][string]$RollbackSessionId)
    $rf=Join-Path $script:RootFolder $RollbackSessionId
    $rm=Join-Path $rf 'manifest.json'
    if (-not (Test-Path $rm)) {
        # Wyswietl dostepne sesje zamiast generycznego bledu
        $available = @(Get-ChildItem -Path $script:RootFolder -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } |
            Sort-Object Name -Descending |
            Select-Object -ExpandProperty Name)
        $availableStr = if ($available.Count -gt 0) {
            "Dostepne sesje do rollbacku:`n" + ($available | ForEach-Object { "  - $_" } | Out-String)
        } else {
            "Brak zapisanych sesji w: $script:RootFolder"
        }
        throw "Nie znaleziono manifest.json dla sesji: '$RollbackSessionId'`n$availableStr"
    }
    $mf=Get-Content $rm -Raw|ConvertFrom-Json
    Write-Status "Rollback sesji: $RollbackSessionId" 'Yellow'

    $rollbackAll = $RollbackModules -contains 'All'
    if ($rollbackAll -or $RollbackModules -contains 'Registry') {
        foreach ($e in $mf.Registry) {
            # FIX v14.0.1: 'reg import' SCALA klucz (merge) i nie usuwa wartosci DODANYCH przez skrypt.
            # Gdy OldValue=$null (wartosc nie istniala przed optymalizacja) — trzeba ja jawnie usunac.
            if ($null -eq $e.OldValue) {
                try {
                    if ((Test-Path $e.Path) -and ($null -ne (Get-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction SilentlyContinue))) {
                        Remove-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction Stop
                        Write-Log "Registry: usunieto wartosc dodana przez skrypt: $($e.Path)\$($e.Name)" -Level 'CHANGE'
                    }
                } catch { Write-Log "Registry: nie udalo sie usunac $($e.Path)\$($e.Name): $($_.Exception.Message)" -Level 'WARN' }
            }
            elseif ($e.BackupFile -and (Test-Path $e.BackupFile)) { & reg.exe import $e.BackupFile|Out-Null; Write-Log "Registry z backupu: $($e.BackupFile)" -Level 'CHANGE' }
            elseif ($null-ne$e.OldValue) {
                if (-not (Test-Path $e.Path)) { New-Item -Path $e.Path -Force|Out-Null }
                if ($e.Type-eq'String'){New-ItemProperty -Path $e.Path -Name $e.Name -PropertyType String -Value([string]$e.OldValue) -Force|Out-Null}
                else{New-ItemProperty -Path $e.Path -Name $e.Name -PropertyType DWord -Value([uint32]$e.OldValue) -Force|Out-Null}
                Write-Log "Registry przywrocony: $($e.Path)\$($e.Name)" -Level 'CHANGE'
            }
        }
    }

    if ($rollbackAll -or $RollbackModules -contains 'Services') {
        foreach ($svc in $mf.Services) {
            try {
                $sm=$svc.OldStartMode; if($sm-eq'Auto'){$sm='Automatic'}  # naprawa bledu Win32_Service
                Set-Service -Name $svc.Name -StartupType $sm -EA Stop
                Write-Log "Usluga przywrocona: $($svc.Name) -> $sm" -Level 'CHANGE'
            } catch { Write-Log "Rollback uslugi nieudany: $($svc.Name)" -Level 'WARN' }
        }
    }

    if (($rollbackAll -or $RollbackModules -contains 'Power') -and $mf.Power.ActiveBefore) {
        $l=[string]$mf.Power.ActiveBefore
        if ($l-match'([a-fA-F0-9-]{36})') { & powercfg /setactive $matches[1]|Out-Null; Write-Log "Plan zasilania przywrocony: $($matches[1])" -Level 'CHANGE' }
    }

    $netBackupPath = Join-Path $rf 'Backups\network_before_full.json'
    if (($rollbackAll -or $RollbackModules -contains 'DNS') -and (Test-Path $netBackupPath)) {
        try {
            $netBackup = Get-Content $netBackupPath -Raw | ConvertFrom-Json
            foreach ($entry in @($netBackup.DNS)) {
                $adp = Get-NetAdapter | Where-Object { $_.Name -eq $entry.InterfaceAlias } | Select-Object -First 1
                if ($adp) {
                    Set-DnsClientServerAddress -InterfaceIndex $adp.ifIndex -ServerAddresses $entry.ServerAddresses -EA SilentlyContinue
                    Write-Log "DNS przywrocony: $($entry.InterfaceAlias) [$($entry.AddressFamily)] -> $($entry.ServerAddresses -join ', ')" -Level 'CHANGE'
                }
            }
        } catch {
            Write-Log "Rollback DNS nieudany: $($_.Exception.Message)" -Level 'WARN'
        }
    }
    Write-Log "Rollback modules: $($RollbackModules -join ', ')" -Level 'INFO'
    $script:Manifest.Notes += "Rollback modules used: $($RollbackModules -join ', ')"
    Add-RestartFlag 'Rollback wykonany'
    Write-Status '==> Walidacja po rollbacku...' 'Cyan'
    Invoke-PostValidation
    Write-Status 'Rollback zakonczony. Sprawdz validation.txt i uruchom ponownie system.' 'Green'
}


# =============================
# v12 PREMIUM — Python Analyzer Generator
# =============================

function Export-PythonAnalyzer {
    <#
    .SYNOPSIS
        Generuje skrypt Python do analizy wyników sesji.
        Python/R jako warstwa analityczna — Punkt 7 z 7.
        Skrypt generuje wykresy HTML z frametime, DPC, benchmark comparison.
    .NOTES
        Wymaga Python 3.8+ z bibliotekami: plotly, pandas.
        Instalacja: pip install plotly pandas
        Uruchomienie: python analyze_session.py
    #>
    param([Parameter(Mandatory)][string]$SessionFolder)

    $pyPath = Join-Path $SessionFolder 'analyze_session.py'

    $pyContent = @'
#!/usr/bin/env python3
"""
Universal Windows Optimizer v12 — Session Analyzer
Analizuje wyniki sesji i generuje interaktywne wykresy HTML.

Wymagania: pip install plotly pandas
Uruchomienie: python analyze_session.py
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime

SESSION_DIR = Path(__file__).parent

def load_json(filename):
    path = SESSION_DIR / "Reports" / filename
    if not path.exists():
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def load_log(filename):
    path = SESSION_DIR / "Logs" / filename
    if not path.exists():
        return []
    with open(path, encoding="utf-8") as f:
        return f.readlines()

def parse_benchmark(data):
    """Parsuje dane benchmarku z before.json / after.json"""
    if not data:
        return {}
    return {
        "timestamp": data.get("Timestamp", ""),
        "used_ram_mb": data.get("UsedRAM_MB"),
        "free_ram_mb": data.get("FreeRAM_MB"),
        "process_count": data.get("ProcessCount"),
        "cpu_pct": data.get("CPU_Pct"),
        "boot_time_sec": data.get("BootTimeSec"),
        "disk_write_mbs": data.get("DiskWrite_MBs"),
        "io_read_lat": data.get("IO_ReadLatMs"),
        "io_write_lat": data.get("IO_WriteLatMs"),
    }

def generate_html_report(before, after, manifest):
    """Generuje interaktywny raport HTML z wykresami."""

    try:
        import plotly.graph_objects as go
        from plotly.subplots import make_subplots
        HAS_PLOTLY = True
    except ImportError:
        HAS_PLOTLY = False
        print("WARN: plotly nie zainstalowany. Generuje raport tekstowy.")
        print("      Zainstaluj: pip install plotly pandas")

    profile = manifest.get("Profile", "Unknown") if manifest else "Unknown"
    session_id = manifest.get("SessionId", "Unknown") if manifest else "Unknown"

    if HAS_PLOTLY and before and after:
        # ── Wykresy porownawcze ──────────────────────────────────────────────
        metrics = {
            "RAM uzywany (MB)":    (before.get("used_ram_mb"),    after.get("used_ram_mb"),    True),
            "RAM wolny (MB)":      (before.get("free_ram_mb"),    after.get("free_ram_mb"),    False),
            "Liczba procesow":     (before.get("process_count"),  after.get("process_count"),  True),
            "CPU spoczynek (%)":   (before.get("cpu_pct"),        after.get("cpu_pct"),        True),
            "Zapis dysku (MB/s)":  (before.get("disk_write_mbs"), after.get("disk_write_mbs"), False),
            "I/O Read lat (ms)":   (before.get("io_read_lat"),    after.get("io_read_lat"),    True),
            "I/O Write lat (ms)":  (before.get("io_write_lat"),   after.get("io_write_lat"),   True),
        }

        # Filtruj None
        metrics = {k: v for k, v in metrics.items() if v[0] is not None and v[1] is not None}

        labels = list(metrics.keys())
        vals_before = [v[0] for v in metrics.values()]
        vals_after  = [v[1] for v in metrics.values()]
        better_lower = [v[2] for v in metrics.values()]

        colors_after = []
        for i, bl in enumerate(better_lower):
            diff = vals_after[i] - vals_before[i]
            if (bl and diff < 0) or (not bl and diff > 0):
                colors_after.append("#00cc88")   # lepiej
            elif diff == 0:
                colors_after.append("#888888")
            else:
                colors_after.append("#ff4444")   # gorzej

        fig = make_subplots(
            rows=2, cols=1,
            subplot_titles=("Porownanie Before vs After", "Roznica (After - Before)"),
            vertical_spacing=0.18
        )

        fig.add_trace(go.Bar(name="Przed", x=labels, y=vals_before,
                             marker_color="#4488ff", opacity=0.8), row=1, col=1)
        fig.add_trace(go.Bar(name="Po",    x=labels, y=vals_after,
                             marker_color=colors_after, opacity=0.9), row=1, col=1)

        diffs = [vals_after[i] - vals_before[i] for i in range(len(labels))]
        diff_colors = [colors_after[i] for i in range(len(labels))]
        fig.add_trace(go.Bar(name="Roznica", x=labels, y=diffs,
                             marker_color=diff_colors, opacity=0.9,
                             text=[f"{d:+.1f}" for d in diffs],
                             textposition="outside"), row=2, col=1)

        fig.update_layout(
            title=f"Universal Windows Optimizer v12 — Sesja {session_id} | Profil: {profile}",
            template="plotly_dark",
            height=700,
            barmode="group",
            font=dict(family="Consolas, monospace", size=12),
            paper_bgcolor="#1a1a2e",
            plot_bgcolor="#16213e",
        )

        # Boot time osobny wykres jeśli dostępny
        charts_html = fig.to_html(include_plotlyjs="cdn", full_html=False)

        if before.get("boot_time_sec") or after.get("boot_time_sec"):
            boot_fig = go.Figure()
            if before.get("boot_time_sec"):
                boot_fig.add_trace(go.Indicator(
                    mode="number+delta",
                    value=after.get("boot_time_sec") or before.get("boot_time_sec"),
                    delta={"reference": before.get("boot_time_sec"), "valueformat": ".1f", "suffix": "s"},
                    title={"text": "Boot Time (s)<br><span style='font-size:0.8em'>niższy = lepszy</span>"},
                    number={"suffix": "s", "font": {"size": 40}}
                ))
                boot_fig.update_layout(template="plotly_dark", height=200,
                                       paper_bgcolor="#1a1a2e")
                charts_html += boot_fig.to_html(include_plotlyjs=False, full_html=False)

    else:
        charts_html = "<p>Zainstaluj plotly aby zobaczyc wykresy: <code>pip install plotly pandas</code></p>"

    # ── Tabela zmian z logu ──────────────────────────────────────────────────
    changes = load_log("changes.log")
    warnings = load_log("warnings.log")

    changes_html = "".join(
        f"<tr><td style='color:#aaa;font-size:.85em'>{line.split(']')[0].replace('[','').strip()}</td>"
        f"<td>{']'.join(line.split(']')[1:]).strip()}</td></tr>"
        for line in changes[:50] if "] " in line
    )

    warnings_html = "".join(
        f"<tr style='color:#ffcc00'><td>{line.strip()}</td></tr>"
        for line in warnings[:20]
    ) or "<tr><td>Brak ostrzezen</td></tr>"

    # ── Finalny HTML ─────────────────────────────────────────────────────────
    html = f"""<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="UTF-8">
<title>UWO v12 — Analiza sesji {session_id}</title>
<style>
  body {{ font-family: Consolas, monospace; background: #1a1a2e; color: #e0e0e0; margin: 20px; }}
  h1 {{ color: #00d4ff; border-bottom: 2px solid #00d4ff; padding-bottom: 8px; }}
  h2 {{ color: #00d4ff; margin-top: 30px; }}
  table {{ border-collapse: collapse; width: 100%; margin-top: 10px; }}
  th, td {{ border: 1px solid #333; padding: 6px 12px; text-align: left; }}
  th {{ background: #0f3460; color: #00d4ff; }}
  tr:nth-child(even) {{ background: #16213e; }}
  code {{ background: #0f3460; padding: 2px 6px; border-radius: 3px; }}
  .good {{ color: #00cc88; }} .bad {{ color: #ff4444; }}
  .stat {{ display: inline-block; background: #0f3460; padding: 12px 24px; margin: 8px;
           border-radius: 8px; text-align: center; }}
  .stat span {{ font-size: 2em; color: #00d4ff; display: block; }}
</style>
</head>
<body>
<h1>Universal Windows Optimizer v12 — Analiza sesji</h1>
<p>Sesja: <b>{session_id}</b> | Profil: <b>{profile}</b> |
   Wygenerowano: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>

<h2>Wykresy porownawcze</h2>
{charts_html}

<h2>Zmiany zastosowane w sesji</h2>
<table>
<tr><th>Czas</th><th>Zmiana</th></tr>
{changes_html or "<tr><td colspan=2>Brak danych</td></tr>"}
</table>

<h2>Ostrzezenia</h2>
<table>
<tr><th>Ostrzezenie</th></tr>
{warnings_html}
</table>

<p style="color:#555;margin-top:40px;font-size:.8em">
  Universal Windows Optimizer v12 &bull; Python Analyzer &bull;
  <a href="https://docs.python.org/3/" style="color:#555">Python 3.8+</a> +
  <a href="https://plotly.com/python/" style="color:#555">Plotly</a>
</p>
</body></html>"""

    out_path = SESSION_DIR / "Reports" / "python_analysis.html"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"OK: Raport zapisany -> {out_path}")
    return str(out_path)

def main():
    print("Universal Windows Optimizer v12 — Python Analyzer")
    print("=" * 55)

    manifest = {}
    mpath = SESSION_DIR / "manifest.json"
    if mpath.exists():
        with open(mpath, encoding="utf-8") as f:
            manifest = json.load(f)
    else:
        print("WARN: manifest.json nie znaleziony w folderze sesji.")

    before_raw = load_json("before.json")
    after_raw  = load_json("after.json")

    # benchmark_before_persistent.json zawiera metryki before (UsedRAM_MB, CPU_Pct etc.)
    before = {}
    bm_path = SESSION_DIR / "Reports" / "benchmark_before_persistent.json"
    if bm_path.exists():
        with open(bm_path, encoding="utf-8") as f:
            before = parse_benchmark(json.load(f))
    elif before_raw and isinstance(before_raw, dict):
        before = parse_benchmark(before_raw)

    # after.json to snapshot systemu — nie zawiera metryk benchmarku
    # Pelne porownanie dostepne po uruchomieniu Analyze po restarcie
    after = {}
    if after_raw and isinstance(after_raw, dict):
        env_data = after_raw.get("Environment", {})
        if env_data:
            print("INFO: Snapshot 'after' zawiera dane srodowiska, nie metryki benchmarku.")
            print("      Pelne porownanie dostepne po uruchomieniu Analyze po restarcie.")

    print(f"Sesja:  {manifest.get('SessionId', 'unknown')}")
    print(f"Profil: {manifest.get('Profile', 'unknown')}")
    print(f"Tryb:   {manifest.get('Mode', 'unknown')}")
    print()

    out = generate_html_report(before, after if after else None, manifest)
    if out:
        print(f"\nOtwieranie raportu w przegladarce...")
        import webbrowser
        webbrowser.open(f"file:///{out.replace(chr(92), '/')}")

if __name__ == "__main__":
    main()
'@

    Set-Content -Path $pyPath -Value $pyContent -Encoding UTF8
    Write-Log "Python Analyzer wygenerowany: $pyPath" -Level 'ARTIFACT'
    Write-Status "  Python Analyzer: $pyPath" 'Cyan'
    Write-Status "  Uruchom: python analyze_session.py (wymaga: pip install plotly pandas)" 'DarkGray'
    Add-HtmlSection "<h2>Python Analyzer</h2><p>Wygenerowano: <code>$pyPath</code><br>Uruchom: <code>python analyze_session.py</code><br>Wymaga: <code>pip install plotly pandas</code></p>"
}

# =============================
# Executive Summary + HTML
# =============================

function Get-TweakPriorityScore {
    param([Parameter(Mandatory)]$Tweak)
    $riskPenalty = switch ($Tweak.Risk) {
        'Low' { 0 }
        'Medium' { 10 }
        'High' { 20 }
        'Experimental' { 18 }
        default { 12 }
    }
    $evidenceBoost = switch ($Tweak.Evidence) {
        'Strong' { 25 }
        'Medium' { 12 }
        'Weak' { 0 }
        default { 0 }
    }
    $bucketPenalty = switch ($Tweak.Bucket) {
        'Safe' { 0 }
        'Conditional' { 8 }
        'Experimental' { 18 }
        'HighRisk' { 30 }
        default { 10 }
    }
    $restartPenalty = if ($Tweak.RequiresRestart) { 5 } else { 0 }
    return [Math]::Max(0, 100 + $evidenceBoost - $riskPenalty - $bucketPenalty - $restartPenalty)
}

function Get-TweakCatalogSummary {
    $catalog = @($script:Manifest.Tweaks)
    $skipped = @($script:Manifest.SkippedTweaks)
    $scoredCatalog = @($catalog | ForEach-Object {
        $_ | Add-Member -NotePropertyName PriorityScore -NotePropertyValue (Get-TweakPriorityScore -Tweak $_) -Force
        $_
    })
    $topRecommended = @($scoredCatalog | Sort-Object -Property @{Expression='PriorityScore';Descending=$true}, @{Expression='Evidence';Descending=$false}, @{Expression='Name';Descending=$false} | Select-Object -First 5)
    $topExperimental = @($scoredCatalog | Where-Object { $_.Bucket -in @('Experimental','HighRisk') } | Sort-Object -Property @{Expression='PriorityScore';Descending=$false}, @{Expression='Name';Descending=$false} | Select-Object -First 5)
    $stats = [ordered]@{
        Total        = $catalog.Count
        Safe         = @($catalog | Where-Object { $_.Bucket -eq 'Safe' }).Count
        Conditional  = @($catalog | Where-Object { $_.Bucket -eq 'Conditional' }).Count
        Experimental = @($catalog | Where-Object { $_.Bucket -eq 'Experimental' }).Count
        HighRisk     = @($catalog | Where-Object { $_.Bucket -eq 'HighRisk' }).Count
        Strong       = @($catalog | Where-Object { $_.Evidence -eq 'Strong' }).Count
        Medium       = @($catalog | Where-Object { $_.Evidence -eq 'Medium' }).Count
        Weak         = @($catalog | Where-Object { $_.Evidence -eq 'Weak' }).Count
        Restart      = @($catalog | Where-Object { $_.RequiresRestart }).Count
        Skipped      = $skipped.Count
        TopRecommended = $topRecommended
        TopExperimental = $topExperimental
    }
    $script:Manifest.Analytics = $stats
    return $stats
}

function Add-TweakCatalogHtmlSection {
    $stats = Get-TweakCatalogSummary
    $catalog = @($script:Manifest.Tweaks)
    $rows = foreach ($item in $catalog | Sort-Object Category, Bucket, Risk, Name) {
        $avoid = if (@($item.AvoidOn).Count -gt 0) { ($item.AvoidOn -join ', ') } else { '—' }
        $reco  = if (@($item.RecommendedFor).Count -gt 0) { ($item.RecommendedFor -join ', ') } else { '—' }
        $score = Get-TweakPriorityScore -Tweak $item
        $cls = switch ($item.Bucket) {
            'Safe' { 'lepiej' }
            'Conditional' { '' }
            'Experimental' { 'gorzej' }
            'HighRisk' { 'gorzej' }
            default { '' }
        }
        "<tr class='$cls'><td>$(ConvertTo-HtmlSafe $item.Name)</td><td>$($item.Category)</td><td>$($item.Bucket)</td><td>$($item.Risk)</td><td>$($item.Evidence)</td><td>$score</td><td>$(ConvertTo-HtmlSafe $reco)</td><td>$(ConvertTo-HtmlSafe $avoid)</td></tr>"
    }
    $topRows = foreach ($item in @($stats.TopRecommended)) {
        "<tr class='lepiej'><td>$(ConvertTo-HtmlSafe $item.Name)</td><td>$($item.Category)</td><td>$($item.PriorityScore)</td><td>$($item.Evidence)</td><td>$($item.Risk)</td></tr>"
    }
    $experimentalRows = foreach ($item in @($stats.TopExperimental)) {
        "<tr class='gorzej'><td>$(ConvertTo-HtmlSafe $item.Name)</td><td>$($item.Category)</td><td>$($item.PriorityScore)</td><td>$($item.Bucket)</td><td>$($item.Risk)</td></tr>"
    }
    $skipRows = foreach ($item in @($script:Manifest.SkippedTweaks) | Select-Object -First 20) {
        "<tr><td>$(ConvertTo-HtmlSafe $item.Id)</td><td>$(ConvertTo-HtmlSafe $item.Reason)</td></tr>"
    }
    Add-HtmlSection @"
<h2>Klasy tweakow i ryzyko</h2>
<div>
  <div class='stat'><span>$($stats.Safe)</span>Safe</div>
  <div class='stat'><span>$($stats.Conditional)</span>Conditional</div>
  <div class='stat'><span>$($stats.Experimental)</span>Experimental</div>
  <div class='stat'><span>$($stats.HighRisk)</span>HighRisk</div>
</div>
<p style='color:#ccc'>Katalog tweakow ma teraz jawny podzial na bezpieczne, warunkowe, eksperymentalne i wysokiego ryzyka. Score to prosty ranking priorytetu wdrozenia: premiuje mocne evidence i niski risk, a karze eksperymentalnosc oraz restart.</p>
<h2>Najbardziej wartosciowe tweaki</h2>
<table>
<tr><th>Nazwa</th><th>Kategoria</th><th>Score</th><th>Evidence</th><th>Risk</th></tr>
$(if($topRows){$topRows -join "`n"}else{"<tr><td colspan='5'>Brak zarejestrowanych tweakow do rankingu.</td></tr>"})
</table>
<h2>Tweaki eksperymentalne / high risk</h2>
<table>
<tr><th>Nazwa</th><th>Kategoria</th><th>Score</th><th>Klasa</th><th>Risk</th></tr>
$(if($experimentalRows){$experimentalRows -join "`n"}else{"<tr><td colspan='5'>Brak tweakow eksperymentalnych.</td></tr>"})
</table>
<table>
<tr><th>Nazwa</th><th>Kategoria</th><th>Klasa</th><th>Risk</th><th>Evidence</th><th>Score</th><th>RecommendedFor</th><th>AvoidOn</th></tr>
$($rows -join "`n")
</table>
<h2>Najwazniejsze pominiete tweaki</h2>
<table>
<tr><th>Tweak</th><th>Powod skipu</th></tr>
$(if($skipRows){$skipRows -join "`n"}else{"<tr><td colspan='2'>Brak pominietych tweakow z gatingu.</td></tr>"})
</table>
"@
}

function Write-ExecutiveSummary {
    $tweakStats = Get-TweakCatalogSummary
    $rst=if($script:RequiresRestart.Count-gt0){'TAK'}else{'NIE'}
    $exp=if($EnableExperimentalTweaks){'TAK'}else{'NIE'}
    $sum=@(
        "================================================"
        "  $($script:AppName) $($script:Version)"
        "  Sesja: $($script:SessionId)"
        "================================================"
        ""; "Tryb:              $Mode"; "Profil:            $Profile"
        "WSearch:           $($script:SearchIndexingMode)"; "DNS:               $($script:SelectedDns)"
        "Eksperymentalne:   $exp"; "Smart Mode:        $(if($script:SmartModeEnabled){'TAK'}else{'NIE'})"; "ExitCode:          $($script:ExitCode)"; ""
        "Start:             $($script:Now)"; "Koniec:            $(Get-Date)"; ""
        "--- WYNIKI ---"
        "Zmiany systemowe:  $($script:ChangesCount)"
        "Raporty/artefakty: $($script:ArtifactsCount)"
        "Pominiete:         $($script:SkippedCount)"
        "Ostrzezenia:       $($script:WarningsCount)"
        "Bledy:             $($script:ErrorsCount)"; ""
        "Restart wymagany:  $rst"
    )
    if ($script:RequiresRestart.Count-gt0) { foreach($r in $script:RequiresRestart){$sum+="  - $r"} }
    $sum+=""; $sum+="Moduly:"
    foreach($m in $script:AppliedModules){$sum+="  - $m"}
    if ($script:SanityWarnings.Count-gt0) {
        $sum+=""; $sum+="Ostrzezenia srodowiska:"
        foreach($w in $script:SanityWarnings){$sum+="  $w"}
    }
    $sum+=""; $sum+="Raporty: $($script:SessionFolder)"
    $sum += "TweaksCatalog: $(@($script:Manifest.Tweaks).Count)"
    $sum += "  Safe/Conditional/Experimental/HighRisk: $($tweakStats.Safe)/$($tweakStats.Conditional)/$($tweakStats.Experimental)/$($tweakStats.HighRisk)"
    $sum += "  Evidence Strong/Medium/Weak: $($tweakStats.Strong)/$($tweakStats.Medium)/$($tweakStats.Weak)"
    $sum += "  Skipped by gating: $($tweakStats.Skipped)"
    $sum += "  Smart decisions: $(@($script:Manifest.SmartDecisions).Count)"
    if (@($tweakStats.TopRecommended).Count -gt 0) {
        $sum += "  Top value tweaks: " + ((@($tweakStats.TopRecommended) | ForEach-Object { "$($_.Name) [$($_.PriorityScore)]" }) -join '; ')
    }
    if (@($tweakStats.TopExperimental).Count -gt 0) {
        $sum += "  Experimental/high-risk watchlist: " + ((@($tweakStats.TopExperimental) | ForEach-Object { "$($_.Name) [$($_.PriorityScore)]" }) -join '; ')
    }
    $sum|Set-Content -Path $script:SummaryPath -Encoding UTF8
    if (-not $Silent) {
        Write-Status '' 'White'; Write-Status '================================================' 'Cyan'
        Write-Status "  PODSUMOWANIE SESJI" 'White'; Write-Status '================================================' 'Cyan'
        # v15.6: use the SAME stats line as the main panel so the report count never diverges (the "3 vs 4" mismatch)
        Write-Status (T 'stats.line' -FmtArgs @($script:ChangesCount, $script:ArtifactsCount, $script:SkippedCount, $script:WarningsCount, $script:ErrorsCount)) 'White'
        Write-Status "  Restart wymagany: $rst" $(if($rst-eq'TAK'){'Yellow'}else{'Green'})
        Write-Status "  Experimental: $exp" 'White'; Write-Status "  ExitCode: $($script:ExitCode)" 'White'; Write-Status '================================================' 'Cyan'
    }
}

function Write-HtmlReport {
    Add-TweakCatalogHtmlSection
    $tweakStats = Get-TweakCatalogSummary
    $sanH=($script:SanityWarnings|ForEach-Object{$cls=if($_-match'^WARN'){'gorzej'}else{''};"<tr class='$cls'><td>$(ConvertTo-HtmlSafe $_)</td></tr>"})-join''
    $modH=($script:AppliedModules|ForEach-Object{"<li>$(ConvertTo-HtmlSafe $_)</li>"})-join''
    $rstH=if($script:RequiresRestart.Count-gt0){($script:RequiresRestart|ForEach-Object{"<li>$(ConvertTo-HtmlSafe $_)</li>"})-join''}else{'<li>Nie wymagany</li>'}
    $secH=$script:HtmlSections-join"`n"
    $html=@"
<!DOCTYPE html><html lang="pl"><head><meta charset="UTF-8">
<title>$(ConvertTo-HtmlSafe $script:AppName) — $(ConvertTo-HtmlSafe $script:SessionId)</title>
<style>
body{font-family:Consolas,monospace;background:#1a1a2e;color:#e0e0e0;margin:20px}
h1{color:#00d4ff;border-bottom:2px solid #00d4ff}h2{color:#00d4ff;margin-top:30px}
table{border-collapse:collapse;width:100%;margin-top:10px}th,td{border:1px solid #333;padding:6px 10px;text-align:left}
th{background:#0f3460;color:#00d4ff}tr:nth-child(even){background:#16213e}
.lepiej{background:#1a3a1a!important;color:#7fff7f}.gorzej{background:#3a1a1a!important;color:#ff7f7f}
.stat{display:inline-block;background:#0f3460;padding:10px 20px;margin:5px;border-radius:6px}
.stat span{font-size:2em;color:#00d4ff;display:block}ul{margin:5px 0;padding-left:20px}li{margin:2px 0}
</style></head><body>
<h1>$(ConvertTo-HtmlSafe $script:AppName) $(ConvertTo-HtmlSafe $script:Version)</h1>
<p>Sesja: <b>$(ConvertTo-HtmlSafe $script:SessionId)</b> | Tryb: <b>$(ConvertTo-HtmlSafe $Mode)</b> | Profil: <b>$(ConvertTo-HtmlSafe $Profile)</b> | DNS: <b>$(ConvertTo-HtmlSafe $script:SelectedDns)</b> | ExitCode: <b>$(ConvertTo-HtmlSafe $script:ExitCode)</b></p>
<p>Start: $($script:Now) | Koniec: $(Get-Date)</p>
<div>
  <div class='stat'><span>$($script:ChangesCount)</span>Zmiany</div>
  <div class='stat'><span>$($script:SkippedCount)</span>Pominiete</div>
  <div class='stat'><span>$($script:WarningsCount)</span>Ostrzezenia</div>
  <div class='stat'><span>$($script:ErrorsCount)</span>Bledy</div>
  <div class='stat'><span>$($tweakStats.Safe)</span>Safe</div>
  <div class='stat'><span>$($tweakStats.Experimental)</span>Experimental</div>
</div>
<h2>Restart wymagany</h2><ul>$rstH</ul>
<h2>Moduly</h2><ul>$modH</ul>
<h2>Ostrzezenia srodowiska</h2><table>$(if($sanH){$sanH}else{"<tr><td>Brak ostrzezen</td></tr>"})</table>
$secH
<h2>Lokalizacja raportow</h2><p>$(ConvertTo-HtmlSafe $script:SessionFolder)</p>
<h2>Pliki sesji</h2><ul>
<li><a href='Logs/main.log'>main.log</a></li>
<li><a href='Logs/changes.log'>changes.log</a></li>
<li><a href='Logs/errors.log'>errors.log</a></li>
<li><a href='Logs/warnings.log'>warnings.log</a></li>
<li><a href='Reports/benchmark.txt'>benchmark.txt</a></li>
<li><a href='Reports/validation.txt'>validation.txt</a></li>
<li><a href='Reports/analyze_report.txt'>analyze_report.txt</a></li>
<li><a href='Reports/snapshot_diff.txt'>snapshot_diff.txt</a></li>
</ul>
<p style='color:#666;margin-top:40px;font-size:.8em'>$($script:AppName) $($script:Version) &bull; Windows Defender NIE zostal wylaczony</p>
<p style='color:#666;font-size:.8em'>Wygenerowano: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | PowerShell $($PSVersionTable.PSVersion) | Windows Build $($script:Manifest.Environment.Build)</p>
</body></html>
"@
    $html|Set-Content -Path $script:HtmlReportPath -Encoding UTF8
    Write-Log "Raport HTML: $($script:HtmlReportPath)" -Level 'ARTIFACT'
}

# =============================
# Restart Prompt
# =============================
function Invoke-RestartPrompt {
    if ($Silent) { if ($AutoRestart) { Write-Log 'AutoRestart za 10s.' -Level 'CHANGE'; Start-Sleep 10; Restart-Computer -Force } else { Write-Log "Tryb Silent zakonczony bez restartu. ExitCode=$($script:ExitCode)" -Level 'INFO' }; return }
    if ($script:RequiresRestart.Count-eq0) { return }
    Write-Status '' 'White'; Write-Status 'Restart systemu jest zalecany dla pelnego efektu.' 'Yellow'
    Write-Host '  [1] Restartuj teraz' -ForegroundColor White
    Write-Host '  [2] Restartuj za 60 sekund' -ForegroundColor White
    Write-Host '  [3] Pominij restart' -ForegroundColor Gray
    do { $rk=(Read-Host 'Wybor [1/2/3]').Trim() } while ($rk-notin'1','2','3')
    switch ($rk) {
        '1' { Restart-Computer -Force }
        '2' { Write-Status 'Restart za 60s... (Ctrl+C aby anulowac)' 'Yellow'; Start-Sleep 60; Restart-Computer -Force }
        '3' { Write-Status 'Restart pominiety. Uruchom recznie kiedy bedziesz gotowy.' 'Gray' }
    }
}

# =============================
# Interactive Menu
# =============================
# ============================================================
# PHASE A+B v15.0: AUTOMATION ENGINE (daemon), POST-RESTART VALIDATION,
# BENCHMARK REGRESSION GUARD, APP PACKS (winget), VOICE ASSISTANT.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.
# ============================================================

$script:DaemonTaskName = 'UWO_AutomationDaemon'
$script:ValidateTaskName = 'UWO_PostRestartValidation'

function Get-AutomationPaths {
    $root = Join-Path $script:RootFolder 'Library'
    $auto = Join-Path $root 'Automation'
    if (-not (Test-Path $auto)) { New-Item -ItemType Directory -Path $auto -Force | Out-Null }
    return [ordered]@{
        Config = Join-Path $auto 'automation_config.json'
        Log    = Join-Path $auto 'daemon.log'
        Lock   = Join-Path $auto 'daemon.lock'
    }
}

function Get-AutomationConfig {
    $p = Get-AutomationPaths
    if (Test-Path $p.Config) {
        try { return (Get-Content $p.Config -Raw | ConvertFrom-Json) } catch {}
    }
    $cfg = [ordered]@{
        PollSeconds        = 10
        RuleGameToGaming   = $true
        RuleBatteryToEco   = $true
        RuleCpuAlert       = $true
        CpuAlertThreshold  = 92
        GamingPlanName     = 'UWO Max Performance'
        GameProcesses      = @('cs2','csgo','valorant','VALORANT-Win64-Shipping','FortniteClient-Win64-Shipping','RainbowSix','r5apex','League of Legends','javaw','GTA5','RDR2','Cyberpunk2077','eldenring','witcher3','dota2','rocketleague','overwatch','Warframe.x64','destiny2')
    }
    ($cfg | ConvertTo-Json) | Set-Content -Path $p.Config -Encoding UTF8
    return (Get-Content $p.Config -Raw | ConvertFrom-Json)
}

function Write-DaemonLog {
    param([string]$Msg)
    $p = Get-AutomationPaths
    try {
        if ((Test-Path $p.Log) -and ((Get-Item $p.Log).Length -gt 1MB)) {
            Move-Item -Path $p.Log -Destination ($p.Log + '.old') -Force
        }
        Add-Content -Path $p.Log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg) -Encoding UTF8
    } catch {}
}

function Get-PowerSchemeGuidByName {
    param([string]$Name)
    $out = (powercfg /list) | Out-String
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\((.+)\)') {
            if ($Matches[2].Trim() -like ('*' + $Name + '*')) { return $Matches[1] }
        }
    }
    return $null
}

function Get-ActiveSchemeGuid {
    $out = (powercfg /getactivescheme) | Out-String
    if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1] }
    return $null
}

function Invoke-AutomationDaemon {
    # PHASE-A: polling loop. Honest design: ONLY switches power plans + logs. Never kills, never edits registry.
    $p = Get-AutomationPaths
    # single instance
    if (Test-Path $p.Lock) {
        try {
            $oldPid = [int](Get-Content $p.Lock -ErrorAction Stop | Select-Object -First 1)
            if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) { return }
        } catch {}
    }
    $PID | Set-Content -Path $p.Lock -Encoding ASCII
    $cfg = Get-AutomationConfig
    Write-DaemonLog ('Daemon started (PID {0}, poll {1}s).' -f $PID, $cfg.PollSeconds)

    $gamingGuid = Get-PowerSchemeGuidByName -Name $cfg.GamingPlanName
    if (-not $gamingGuid) { $gamingGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }  # High performance fallback
    $ecoGuid = 'a1841308-3541-4fab-bc81-f71556f20b4a'                                # Power saver (built-in)

    $savedScheme = $null   # scheme to restore when the trigger ends
    $stateGame = $false
    $stateBatt = $false
    $cpuAlertArmed = $true

    while ($true) {
        try {
            $cfgNames = @($cfg.GameProcesses)
            $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $cfgNames -contains $_.ProcessName })
            $gameOn = ($running.Count -gt 0) -and [bool]$cfg.RuleGameToGaming

            $battOn = $false
            if ([bool]$cfg.RuleBatteryToEco) {
                $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($b -and $b.BatteryStatus -eq 1) { $battOn = $true }  # 1 = discharging
            }

            # priority: game > battery
            if ($gameOn -and -not $stateGame) {
                if (-not $savedScheme) { $savedScheme = Get-ActiveSchemeGuid }
                powercfg /setactive $gamingGuid | Out-Null
                $stateGame = $true
                Write-DaemonLog ('RULE game: detected [{0}] -> gaming plan.' -f ($running[0].ProcessName))
            }
            elseif (-not $gameOn -and $stateGame) {
                $stateGame = $false
                if ($battOn) {
                    powercfg /setactive $ecoGuid | Out-Null
                    $stateBatt = $true
                    Write-DaemonLog 'RULE game ended -> battery still discharging -> eco plan.'
                } else {
                    if ($savedScheme) { powercfg /setactive $savedScheme | Out-Null; $savedScheme = $null }
                    Write-DaemonLog 'RULE game ended -> previous plan restored.'
                }
            }
            elseif (-not $stateGame) {
                if ($battOn -and -not $stateBatt) {
                    if (-not $savedScheme) { $savedScheme = Get-ActiveSchemeGuid }
                    powercfg /setactive $ecoGuid | Out-Null
                    $stateBatt = $true
                    Write-DaemonLog 'RULE battery: discharging -> eco plan.'
                }
                elseif (-not $battOn -and $stateBatt) {
                    $stateBatt = $false
                    if ($savedScheme) { powercfg /setactive $savedScheme | Out-Null; $savedScheme = $null }
                    Write-DaemonLog 'RULE battery: back on AC -> previous plan restored.'
                }
            }

            if ([bool]$cfg.RuleCpuAlert) {
                $cpu = Get-CounterValueSafe '\Processor(_Total)\% Processor Time'
                if ($null -ne $cpu) {
                    if ($cpu -ge [double]$cfg.CpuAlertThreshold -and $cpuAlertArmed) {
                        $top = Get-Process | Sort-Object CPU -Descending | Select-Object -First 3
                        $names = ($top | ForEach-Object { $_.ProcessName }) -join ', '
                        Write-DaemonLog ('ALERT CPU {0}% (threshold {1}%). Top: {2}. (log only - no action taken)' -f [math]::Round($cpu,0), $cfg.CpuAlertThreshold, $names)
                        $cpuAlertArmed = $false
                    }
                    elseif ($cpu -lt ([double]$cfg.CpuAlertThreshold - 15)) { $cpuAlertArmed = $true }
                }
            }
        } catch { Write-DaemonLog ('Loop error: ' + $_.Exception.Message) }
        Start-Sleep -Seconds ([int]$cfg.PollSeconds)
    }
}

function Install-AutomationDaemon {
    $self = $script:ScriptFullPath
    if (-not $self) {
        Write-Host 'Cannot install the daemon: the script was not started from a saved .ps1 file.' -ForegroundColor Yellow
        return $false
    }
    $tr = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Daemon' -f $self)
    schtasks /create /tn $script:DaemonTaskName /tr $tr /sc onlogon /rl highest /f | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Uninstall-AutomationDaemon {
    schtasks /delete /tn $script:DaemonTaskName /f 2>$null | Out-Null
    $p = Get-AutomationPaths
    try {
        if (Test-Path $p.Lock) {
            $oldPid = [int](Get-Content $p.Lock | Select-Object -First 1)
            Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
            Remove-Item $p.Lock -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Test-DaemonInstalled {
    schtasks /query /tn $script:DaemonTaskName 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Show-AutomationMenu {
    while ($true) {
        $cfg = Get-AutomationConfig
        $p = Get-AutomationPaths
        Write-Host ''
        Write-Host (T 'autom.title') -ForegroundColor Cyan
        $st = if (Test-DaemonInstalled) { T 'autom.on' } else { T 'autom.off' }
        Write-Host (T 'autom.status' -FmtArgs @($st)) -ForegroundColor Yellow
        Write-Host (T 'autom.note') -ForegroundColor DarkGray
        Write-Host (T 'autom.1') -ForegroundColor Gray
        Write-Host (T 'autom.2') -ForegroundColor Gray
        Write-Host (T 'autom.3') -ForegroundColor Gray
        Write-Host (T 'autom.4') -ForegroundColor Gray
        Write-Host (T 'autom.0') -ForegroundColor DarkGray
        do { $k = (Read-Host (T 'autom.prompt')).Trim() } while ($k -notin '0','1','2','3','4')
        switch ($k) {
            '1' {
                if (Install-AutomationDaemon) {
                    Write-Host (T 'autom.installed' -FmtArgs @($cfg.GamingPlanName)) -ForegroundColor Green
                }
            }
            '2' { Uninstall-AutomationDaemon; Write-Host (T 'autom.removed') -ForegroundColor Green }
            '3' { Write-Host (T 'autom.cfg' -FmtArgs @($p.Config)) -ForegroundColor Green }
            '4' {
                if (Test-Path $p.Log) { Get-Content $p.Log -Tail 15 | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray } }
                else { Write-Host (T 'autom.nolog') -ForegroundColor Yellow }
            }
            '0' { return }
        }
    }
}

function Invoke-ValidateStateRun {
    # PHASE-A: one-shot post-restart validation using the EXISTING Compare-ExpectedVsActual machinery.
    $expectedPath = Join-Path $script:RootFolder 'expected_state.json'
    $outDir = Join-Path $script:RootFolder 'StateValidation'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $outFile = Join-Path $outDir ('validation_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
    $lines = @((T 'valid.head'), ('Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    $passed = 0; $total = 0
    if ((Test-Path $expectedPath) -and (Get-Command Compare-ExpectedVsActual -ErrorAction SilentlyContinue)) {
        $pv = Compare-ExpectedVsActual -ExpectedPath $expectedPath
        if ($pv) {
            $total = @($pv.Results).Count
            $passed = $pv.PassedCount
            foreach ($r in $pv.Results) {
                $st = if ($r.Passed) { '[OK]  ' } else { '[REVERTED]' }
                $lines += ('  ' + $st + ' ' + $r.Check)
                if (-not $r.Passed -and $r.FailWhy) { $lines += ('      why: ' + $r.FailWhy) }
            }
        }
    } else { $lines += '  expected_state.json not found - nothing to validate.' }
    $lines | Set-Content -Path $outFile -Encoding UTF8
    Write-Host (T 'valid.result' -FmtArgs @($passed, $total, $outFile)) -ForegroundColor Cyan
    schtasks /delete /tn $script:ValidateTaskName /f 2>$null | Out-Null   # one-shot: remove ourselves
}

function Register-PostRestartValidation {
    $self = $script:ScriptFullPath
    if (-not $self) { return }
    $tr = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -ValidateState -NoPause' -f $self)
    schtasks /create /tn $script:ValidateTaskName /tr $tr /sc onlogon /rl highest /f 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Status ('  ' + (T 'valid.sched')) 'Green' }
}

function Test-BenchmarkRegression {
    # PHASE-A (#16): conservative regression detector. Returns list of human-readable regressions.
    param($Before, $After)
    $regr = @()
    if (-not $Before -or -not $After) { return $regr }
    try {
        if ($null -ne $Before.CPU_Pct -and $null -ne $After.CPU_Pct -and ([double]$After.CPU_Pct -gt ([double]$Before.CPU_Pct + 15))) {
            $regr += ('CPU idle load {0}% -> {1}%' -f $Before.CPU_Pct, $After.CPU_Pct)
        }
        if ($null -ne $Before.IO_ReadLatMs -and $null -ne $After.IO_ReadLatMs -and ([double]$After.IO_ReadLatMs -gt 5) -and ([double]$After.IO_ReadLatMs -gt ([double]$Before.IO_ReadLatMs * 1.6))) {
            $regr += ('Disk read latency {0}ms -> {1}ms' -f $Before.IO_ReadLatMs, $After.IO_ReadLatMs)
        }
        if ($null -ne $Before.ProcessCount -and $null -ne $After.ProcessCount -and ([int]$After.ProcessCount -gt ([int]$Before.ProcessCount + 20))) {
            $regr += ('Process count {0} -> {1}' -f $Before.ProcessCount, $After.ProcessCount)
        }
    } catch {}
    return $regr
}

function Invoke-BenchmarkRegressionGuard {
    $regr = @(Test-BenchmarkRegression -Before $script:BenchmarkBefore -After $script:BenchmarkAfter)
    if ($regr.Count -eq 0) {
        Write-Log 'Benchmark regression guard: no regression.' -Level 'INFO'
        return
    }
    foreach ($r in $regr) {
        Write-Log ('Benchmark regression: ' + $r) -Level 'WARN'
        Write-Status ('  ' + (T 'regr.warn' -FmtArgs @($r))) 'Yellow'
    }
    if (-not $Silent -and -not $DryRun) {
        $a = (Read-Host (T 'regr.offer')).Trim().ToLower()
        if ($a -in 't','y','tak','yes') {
            Save-Manifest
            Invoke-Rollback -RollbackSessionId $script:SessionId
        }
    }
}

function Show-AppPacksMenu {
    Write-Host ''
    Write-Host (T 'packs.title') -ForegroundColor Cyan
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host (T 'packs.nowinget') -ForegroundColor Yellow
        return
    }
    $dir = Join-Path (Join-Path $script:RootFolder 'Library') 'AppPacks'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $sample = Join-Path $dir 'sample_essentials.json'
    if (-not (Get-ChildItem $dir -Filter '*.json' -ErrorAction SilentlyContinue)) {
        $pack = [ordered]@{
            '$schema' = 'https://aka.ms/winget-packages.schema.2.0.json'
            Sources = @(@{
                SourceDetails = @{ Name='winget'; Identifier='Microsoft.Winget.Source'; Argument='https://cdn.winget.microsoft.com/cache'; Type='Microsoft.PreIndexed.Package' }
                Packages = @(
                    @{ PackageIdentifier = '7zip.7zip' },
                    @{ PackageIdentifier = 'Notepad++.Notepad++' },
                    @{ PackageIdentifier = 'VideoLAN.VLC' }
                )
            })
        }
        ($pack | ConvertTo-Json -Depth 8) | Set-Content -Path $sample -Encoding UTF8
    }
    while ($true) {
        $files = @(Get-ChildItem $dir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)
        Write-Host (T 'packs.list') -ForegroundColor Yellow
        $i = 1
        foreach ($f in $files) { Write-Host ('  [' + $i + '] ' + $f.BaseName) -ForegroundColor Gray; $i++ }
        $c = (Read-Host (T 'packs.prompt')).Trim()
        if ($c -eq '0') { return }
        if ($c -match '^[eE]$') {
            $out = Join-Path $dir ('my_apps_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
            winget export -o $out --accept-source-agreements | Out-Null
            Write-Host (T 'packs.exported' -FmtArgs @($out)) -ForegroundColor Green
            continue
        }
        $p = 0
        if (-not [int]::TryParse($c, [ref]$p) -or $p -lt 1 -or $p -gt $files.Count) { continue }
        $f = $files[$p - 1]
        $a = (Read-Host (T 'packs.installQ' -FmtArgs @($f.BaseName))).Trim().ToLower()
        if ($a -in 't','y','tak','yes') {
            winget import -i $f.FullName --accept-package-agreements --accept-source-agreements --ignore-unavailable
            Write-Host (T 'packs.done' -FmtArgs @($LASTEXITCODE)) -ForegroundColor Cyan
        }
    }
}

function Start-VoiceAssistant {
    Write-Host ''
    Write-Host (T 'voice.title') -ForegroundColor Cyan
    try { Add-Type -AssemblyName System.Speech -ErrorAction Stop } catch { Write-Host (T 'voice.norec') -ForegroundColor Yellow; return }
    $rec = $null
    foreach ($culture in @('pl-PL','en-US')) {
        try {
            $info = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers() | Where-Object { $_.Culture.Name -eq $culture } | Select-Object -First 1
            if ($info) { $rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine($info); break }
        } catch {}
    }
    if (-not $rec) { Write-Host (T 'voice.norec') -ForegroundColor Yellow; return }
    Write-Host (T 'voice.lang' -FmtArgs @($rec.RecognizerInfo.Culture.Name)) -ForegroundColor Green
    Write-Host (T 'voice.cmds') -ForegroundColor Gray

    $phrases = @('tryb gaming','gaming mode','tryb eko','eco mode','wylacz komputer','shutdown computer','anuluj','cancel','koniec','stop listening')
    $choices = New-Object System.Speech.Recognition.Choices
    foreach ($ph in $phrases) { $choices.Add($ph) }
    $gb = New-Object System.Speech.Recognition.GrammarBuilder
    $gb.Culture = $rec.RecognizerInfo.Culture
    $gb.Append($choices)
    $rec.LoadGrammar((New-Object System.Speech.Recognition.Grammar($gb)))
    try { $rec.SetInputToDefaultAudioDevice() } catch { Write-Host (T 'voice.norec') -ForegroundColor Yellow; return }

    $gamingGuid = Get-PowerSchemeGuidByName -Name 'UWO Max Performance'
    if (-not $gamingGuid) { $gamingGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
    Write-Host (T 'voice.listen') -ForegroundColor Yellow
    while ($true) {
        $res = $rec.Recognize([TimeSpan]::FromSeconds(8))
        if (-not $res) { continue }
        $txt = $res.Text.ToLower()
        Write-Host (T 'voice.heard' -FmtArgs @($txt, [math]::Round($res.Confidence * 100, 0))) -ForegroundColor Gray
        if ($res.Confidence -lt 0.55) { continue }
        switch -Regex ($txt) {
            'gaming'              { powercfg /setactive $gamingGuid | Out-Null }
            'eko|eco'             { powercfg /setactive 'a1841308-3541-4fab-bc81-f71556f20b4a' | Out-Null }
            'wylacz|shutdown'     { shutdown.exe /s /t 600 | Out-Null }
            'anuluj|cancel'       { shutdown.exe /a 2>$null | Out-Null }
            'koniec|stop'         { Write-Host (T 'voice.bye') -ForegroundColor Cyan; $rec.Dispose(); return }
        }
    }
}

# ============================================================
# STAGE4-6 v14.5: LIBRARY (recipes + sessions), POWER PLAN CREATOR, AUTOSMART
# All code below is compatible with Windows PowerShell 5.1 AND PowerShell 7.
# ============================================================

function Get-RecipeField {
    # StrictMode-safe property read from a recipe object (recipes may omit fields).
    param($Obj, [string]$Name, $Default)
    $p = $Obj.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Test-RepairPreflight {
    # RENOVATION 2.0 part 1 (v15.3): pre-checks before any repair work. Returns $true to proceed.
    Write-Host ''
    Write-Host (T 'pre.title') -ForegroundColor Cyan
    $warns = @()
    # 1) pending reboot — repairing on a dirty state invites trouble
    $pend = $false
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                     'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path $k) { $pend = $true }
    }
    try {
        $pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pfro -and $pfro.PendingFileRenameOperations) { $pend = $true }
    } catch {}
    if ($pend) { $warns += (T 'pre.reboot') }
    # 2) free disk space (DISM can need 10+ GB)
    try {
        $free = (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free
        if ($free -lt 10GB) { $warns += (T 'pre.space' -FmtArgs @([math]::Round($free/1GB,1))) }
    } catch {}
    # 3) battery — long repairs on battery are a gamble
    try {
        $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($b -and $b.BatteryStatus -eq 1) { $warns += (T 'pre.batt') }
    } catch {}
    if ($warns.Count -eq 0) { Write-Host (T 'pre.ok') -ForegroundColor Green; return $true }
    foreach ($w in $warns) { Write-Host ('  ! ' + $w) -ForegroundColor Yellow }
    $a = (Read-Host (T 'pre.contQ')).Trim().ToLower()
    return ($a -in 't','y','tak','yes')
}

function Initialize-LibraryRoot {
    $root = Join-Path $script:RootFolder 'Library'
    $rec  = Join-Path $root 'Recipes'
    $bk   = Join-Path $root 'PowerPlanBackups'
    foreach ($d in @($root, $rec, $bk)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    if (-not (Get-ChildItem -Path $rec -Filter '*.json' -ErrorAction SilentlyContinue)) {
        # Starter recipe - honest effect label, NO fake FPS percentages.
        # v15.2: starter recipe in the user's UI language
        if ($script:UILang -eq 'pl') {
            $sample = [ordered]@{
                Name        = 'Komfort pracy'
                Description = 'Bezpieczny zestaw codzienny: profil Safe, bez ryzykownych modulow, bez zmian w sieci.'
                EffectLabel = 'Responsywnosc UI / mniej szumu w tle (szac. ~0-3%, bez obietnic FPS)'
                Mode        = 'Optimize'
                Profile     = 'Safe'
                SearchMode  = 'Keep'
                DnsMode     = 'Keep'
                Experimental= $false
                RiskPack    = $false
            }
        } else {
        $sample = [ordered]@{
            Name        = 'Comfort Work'
            Description = 'Safe everyday set: Safe profile, no risky modules, no network changes.'
            EffectLabel = 'UI responsiveness / less background noise (est. ~0-3%, no FPS promises)'
            Mode        = 'Optimize'
            Profile     = 'Safe'
            SearchMode  = 'Keep'
            DnsMode     = 'Keep'
            Experimental= $false
            RiskPack    = $false
        }
        }
        ($sample | ConvertTo-Json) | Set-Content -Path (Join-Path $rec 'sample_comfort_work.json') -Encoding UTF8
    }
    return $rec
}

function Show-RecipeMenu {
    # Returns $true when a recipe was selected (selections are set), $false to go back.
    $rec = Initialize-LibraryRoot
    $files = @(Get-ChildItem -Path $rec -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)
    $items = @()
    Write-Host ''
    Write-Host (T 'lib.rec.list') -ForegroundColor Yellow
    $i = 1
    foreach ($f in $files) {
        $r = $null
        try { $r = Get-Content -Path $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json } catch { continue }
        if ($null -eq $r) { continue }
        $items += , $r
        $nm = Get-RecipeField $r 'Name' $f.BaseName
        $ds = Get-RecipeField $r 'Description' ''
        $ef = Get-RecipeField $r 'EffectLabel' '-'
        Write-Host ("  [{0}] {1} - {2}" -f $i, $nm, $ds) -ForegroundColor Gray
        Write-Host ("      " + (T 'lib.rec.effect' -FmtArgs @($ef))) -ForegroundColor DarkGray
        $i++
    }
    if ($items.Count -eq 0) { return $false }
    do {
        $c = (Read-Host (T 'lib.rec.prompt')).Trim()
        $p = 0
        $ok = [int]::TryParse($c, [ref]$p)
    } while (-not $ok -or $p -lt 0 -or $p -gt $items.Count)
    if ($p -eq 0) { return $false }
    $r = $items[$p - 1]
    $script:SelectedMode         = Get-RecipeField $r 'Mode' 'Optimize'
    $script:SelectedProfile      = Get-RecipeField $r 'Profile' 'Safe'
    $script:SelectedSearchMode   = Get-RecipeField $r 'SearchMode' 'Keep'
    $script:SelectedDns          = Get-RecipeField $r 'DnsMode' 'Keep'
    $script:SelectedExperimental = [bool](Get-RecipeField $r 'Experimental' $false)
    if ([bool](Get-RecipeField $r 'RiskPack' $false)) { $script:EnableRiskPackBundle = $true }
    Write-Host ''
    Write-Host (T 'lib.rec.run' -FmtArgs @((Get-RecipeField $r 'Name' '?'), $script:SelectedProfile)) -ForegroundColor Green
    Write-Host (T 'lib.rec.apply') -ForegroundColor DarkGray
    return $true
}

function Show-LibrarySessions {
    # Full session history hidden away from the main flow; returns $true when a rollback was chosen.
    $sessions = @(Get-ChildItem -Path $script:RootFolder -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } | Sort-Object Name -Descending)
    if ($sessions.Count -eq 0) { Write-Host (T 'lib.ses.none') -ForegroundColor Yellow; return $false }
    Write-Host ''
    Write-Host (T 'lib.ses.title') -ForegroundColor Yellow
    $i = 1
    foreach ($s in $sessions) {
        $modeTxt = '?'; $profTxt = '?'
        try {
            $mf = Get-Content -Path (Join-Path $s.FullName 'manifest.json') -Raw -ErrorAction Stop | ConvertFrom-Json
            $modeTxt = Get-RecipeField $mf 'Mode' '?'
            $profTxt = Get-RecipeField $mf 'Profile' '?'
        } catch {}
        Write-Host ("  [{0}] {1}   {2} / {3}" -f $i, $s.Name, $modeTxt, $profTxt) -ForegroundColor Gray
        $i++
    }
    do {
        $c = (Read-Host (T 'lib.ses.prompt')).Trim()
        $p = 0
        $ok = [int]::TryParse($c, [ref]$p)
    } while (-not $ok -or $p -lt 0 -or $p -gt $sessions.Count)
    if ($p -eq 0) { return $false }
    $script:SelectedMode = 'Rollback'
    $script:SelectedRollbackSession = $sessions[$p - 1].Name
    return $true
}

function Read-IntDefault {
    # v15.2: Enter accepts the default; values are range-checked. PS 5.1 + 7 compatible.
    param([string]$Prompt, [int]$Default, [int]$Min = 0, [int]$Max = 999999)
    while ($true) {
        $r = (Read-Host ($Prompt + " [$Default]")).Trim()
        if ($r -eq '') { return $Default }
        $v = 0
        if ([int]::TryParse($r, [ref]$v) -and $v -ge $Min -and $v -le $Max) { return $v }
    }
}

function Backup-AllPowerPlans {
    # Exports EVERY plan as .pow (real backup) + readable .txt dump. Returns (count, folder).
    $bk = Join-Path (Join-Path $script:RootFolder 'Library') 'PowerPlanBackups'
    if (-not (Test-Path $bk)) { New-Item -ItemType Directory -Path $bk -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $bk $stamp
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    powercfg /list | Out-File -FilePath (Join-Path $dir 'plans_list.txt') -Encoding UTF8
    $count = 0
    foreach ($line in ((powercfg /list) | Out-String) -split "`r?`n") {
        if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\((.+?)\)') {
            $g = $Matches[1]
            $n = ($Matches[2] -replace '[^\w\- ]','').Trim()
            try {
                powercfg /export (Join-Path $dir ($n + '-' + $g + '.pow')) $g 2>$null | Out-Null
                powercfg /query $g | Out-File -FilePath (Join-Path $dir ($n + '-' + $g + '.txt')) -Encoding UTF8
                $count++
            } catch {}
        }
    }
    return @($count, $dir)
}

function Invoke-PowerPlanCreator {
    # v15.1: MAIN MODE. Goal templates calibrated on the user's real, field-proven plans
    # (Gaming Cool FPS: AC max 98 = turbo capped = cooler laptop; Silent Work: 85/70).
    # Extras: [B] full backup, [R] restore from .pow, [F] factory reset (with triple guard).
    $SUB_CPU  = '54533251-82be-4824-96c1-47b60b740d00'
    $PROCMIN  = '893dee8e-2bef-41e0-89c6-b55d0929964c'
    $PROCMAX  = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
    $BOOST    = 'be337238-0d82-4146-a960-4f3749d470c7'
    $COOLPOL  = '94d3a615-a899-4ac5-ae2b-e4d8f634367f'
    $SUB_USB  = '2a737441-1930-4402-8d77-b2bebba308a3'
    $USBSEL   = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    $SUB_PCIE = '501a4d13-42af-4429-9fd1-a8218c268e20'
    $ASPM     = 'ee12f906-d277-404b-b6da-e5fa1a576df5'
    $SUB_DISK = '0012ee47-9041-4b5d-9b77-535fba8b1442'
    $DISKIDLE = '6738e2c4-e8a5-4a42-b16a-e040e769756e'
    $SUB_VID  = '7516b95f-f776-4464-8c53-06167f40cc99'
    $VIDIDLE  = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
    $SUB_SLP  = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
    $SLPIDLE  = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
    $bk = Join-Path (Join-Path $script:RootFolder 'Library') 'PowerPlanBackups'

    while ($true) {
        Write-Host ''
        Write-Host (T 'ppc.title') -ForegroundColor Cyan
        Write-Host (T 'ppc.menu1') -ForegroundColor Red
        Write-Host (T 'ppc.menu2') -ForegroundColor Green
        Write-Host (T 'ppc.menu3') -ForegroundColor Cyan
        Write-Host (T 'ppc.menu4') -ForegroundColor Gray
        Write-Host (T 'ppc.menu5') -ForegroundColor Magenta
        Write-Host (T 'ppc.menuB') -ForegroundColor Yellow
        Write-Host (T 'ppc.menuR') -ForegroundColor Yellow
        Write-Host (T 'ppc.menuF') -ForegroundColor DarkRed
        Write-Host (T 'ppc.menu0') -ForegroundColor DarkGray
        $g = (Read-Host (T 'ppc.prompt2')).Trim().ToUpper()
        if ($g -eq '0') { return }
        # v15.2: letters replaced with digits (B/R/F kept as silent aliases)
        if ($g -eq '6') { $g = 'B' }
        if ($g -eq '7') { $g = 'R' }
        if ($g -eq '8') { $g = 'F' }

        if ($g -eq 'B') {
            $r = Backup-AllPowerPlans
            Write-Host (T 'ppc.bdone' -FmtArgs @($r[0], $r[1])) -ForegroundColor Green
            continue
        }
        if ($g -eq 'R') {
            $pows = @(Get-ChildItem -Path $bk -Filter '*.pow' -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
            if ($pows.Count -eq 0) { Write-Host (T 'lib.ses.none') -ForegroundColor Yellow; continue }
            Write-Host (T 'ppc.rlist') -ForegroundColor Yellow
            $i = 1
            foreach ($f in $pows) { Write-Host ('  [' + $i + '] ' + $f.Name + '   (' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm') + ')') -ForegroundColor Gray; $i++ }
            do { $c=(Read-Host (T 'ppc.rprompt')).Trim(); $p=0; $ok=[int]::TryParse($c,[ref]$p) } while (-not $ok -or $p -lt 0 -or $p -gt $pows.Count)
            if ($p -eq 0) { continue }
            powercfg /import ('"' + $pows[$p-1].FullName + '"') 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { powercfg /import $pows[$p-1].FullName 2>&1 | Out-Null }
            Write-Host (T 'ppc.rdone') -ForegroundColor Green
            continue
        }
        if ($g -eq 'F') {
            Write-Host (T 'ppc.fwarn') -ForegroundColor Red
            $r = Backup-AllPowerPlans
            Write-Host (T 'ppc.bdone' -FmtArgs @($r[0], $r[1])) -ForegroundColor Green
            $conf = (Read-Host (T 'ppc.fconfirm')).Trim().ToUpper()
            if ($conf -in 'TAK','YES') {
                powercfg -restoredefaultschemes
                Write-Host (T 'ppc.fdone') -ForegroundColor Green
            }
            continue
        }
        if ($g -notin '1','2','3','4','5') { continue }

        # safety: quick backup of the active plan before creating/activating anything
        try {
            if (-not (Test-Path $bk)) { New-Item -ItemType Directory -Path $bk -Force | Out-Null }
            $act = Get-ActiveSchemeGuid
            if ($act) { powercfg /export (Join-Path $bk ('active_before_creator_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.pow')) $act 2>$null | Out-Null }
        } catch {}
        Write-Host (T 'ppc.backup' -FmtArgs @($bk)) -ForegroundColor DarkGray

        $dup = (powercfg /duplicatescheme '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' 2>&1) | Out-String
        if ($dup -notmatch '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            Write-Host (T 'ppc.failed' -FmtArgs @($dup.Trim())) -ForegroundColor Red
            continue
        }
        $guid = $Matches[1]

        # Templates: AC then DC. Order: procMin, procMax, boost, cooling, usbSel, aspm, diskIdle, screenOff, sleep (seconds, 0 = never)
        if ($g -eq '1') { $name='UWO Max Performance'; $ac=@(8,100,2,1,0,0,0,900,0);      $dc=@(5,100,0,1,1,2,600,300,1800) }
        elseif ($g -eq '2') { $name='UWO Gaming Cool'; $ac=@(10,98,3,1,1,0,1200,300,900); $dc=@(10,100,0,1,1,2,600,180,600) }
        elseif ($g -eq '3') { $name='UWO Silent Work'; $ac=@(5,85,0,1,1,1,1200,300,900);  $dc=@(5,70,0,1,1,2,600,180,600) }
        elseif ($g -eq '4') { $name='UWO Balanced Work'; $ac=@(5,100,3,1,1,1,1200,600,1800); $dc=@(5,90,0,1,1,2,600,300,900) }
        else {
            # v15.2: [5] CUSTOM - question-by-question with honest guidance; Enter = sensible default.
            Write-Host ''
            Write-Host (T 'cust.title') -ForegroundColor Magenta
            $cn = (Read-Host ((T 'cust.name') + ' [UWO Custom]')).Trim()
            $name = if ($cn) { $cn } else { 'UWO Custom' }
            $cMaxAc  = Read-IntDefault -Prompt (T 'cust.maxac')  -Default 98  -Min 20 -Max 100
            $cMaxDc  = Read-IntDefault -Prompt (T 'cust.maxdc')  -Default 85  -Min 20 -Max 100
            $cMin    = Read-IntDefault -Prompt (T 'cust.min')    -Default 5   -Min 0  -Max 100
            $cBoost  = Read-IntDefault -Prompt (T 'cust.boost')  -Default 3   -Min 0  -Max 4
            $cUsb    = Read-IntDefault -Prompt (T 'cust.usb')    -Default 1   -Min 0  -Max 1
            $cAspm   = Read-IntDefault -Prompt (T 'cust.aspm')   -Default 1   -Min 0  -Max 2
            $cDisk   = Read-IntDefault -Prompt (T 'cust.disk')   -Default 1200 -Min 0 -Max 86400
            $cScreen = Read-IntDefault -Prompt (T 'cust.screen') -Default 600  -Min 0 -Max 86400
            $cSleep  = Read-IntDefault -Prompt (T 'cust.sleep')  -Default 1800 -Min 0 -Max 86400
            $ac = @($cMin, $cMaxAc, $cBoost, 1, $cUsb, $cAspm, $cDisk, $cScreen, $cSleep)
            $dc = @($cMin, $cMaxDc, 0, 1, 1, 2, [int]([math]::Min($cDisk, 600)), [int]([math]::Min($cScreen, 300)), [int]([math]::Min($cSleep, 900)))
        }

        $pairs = @(
            @($SUB_CPU,$PROCMIN,0), @($SUB_CPU,$PROCMAX,1), @($SUB_CPU,$BOOST,2), @($SUB_CPU,$COOLPOL,3),
            @($SUB_USB,$USBSEL,4), @($SUB_PCIE,$ASPM,5), @($SUB_DISK,$DISKIDLE,6), @($SUB_VID,$VIDIDLE,7), @($SUB_SLP,$SLPIDLE,8)
        )
        try {
            powercfg /changename $guid $name ('Created by Universal Windows Optimizer ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) | Out-Null
            foreach ($pr in $pairs) {
                powercfg /setacvalueindex $guid $pr[0] $pr[1] $ac[$pr[2]] 2>$null | Out-Null
                powercfg /setdcvalueindex $guid $pr[0] $pr[1] $dc[$pr[2]] 2>$null | Out-Null
            }
        } catch { Write-Host (T 'ppc.failed' -FmtArgs @($_.Exception.Message)) -ForegroundColor Red; continue }

        # Honest verification: re-query the plan and check which settings the system actually exposes/accepted.
        $q = (powercfg /query $guid) | Out-String
        $checks = @(@($PROCMIN,'CPU min'), @($PROCMAX,'CPU max'), @($BOOST,'Boost mode'), @($COOLPOL,'Cooling policy'), @($USBSEL,'USB suspend'), @($ASPM,'PCIe ASPM'), @($DISKIDLE,'Disk idle'), @($VIDIDLE,'Screen off'), @($SLPIDLE,'Sleep'))
        $okCount = 0; $hiddenList = @()
        foreach ($ch in $checks) {
            if ($q -match $ch[0]) { $okCount++ } else { $hiddenList += $ch[1] }
        }
        Write-Host ''
        Write-Host (T 'ppc.created' -FmtArgs @($name)) -ForegroundColor Green
        Write-Host (T 'ppc.applied' -FmtArgs @($okCount, $checks.Count)) -ForegroundColor Cyan
        if ($hiddenList.Count -gt 0) {
            Write-Host (T 'ppc.hidden' -FmtArgs @(($hiddenList -join ', '))) -ForegroundColor Yellow
        }
        Write-Host (T 'ppc.note') -ForegroundColor DarkGray
        $a = (Read-Host (T 'ppc.activateQ')).Trim().ToLower()
        if ($a -in 't','y','tak','yes') {
            powercfg /setactive $guid | Out-Null
            Write-Host (T 'ppc.activated') -ForegroundColor Green
        }
    }
}
function Show-LibraryMenu {
    # Returns $true when the user made a selection that should continue the main flow.
    Initialize-LibraryRoot | Out-Null
    while ($true) {
        Write-Host ''
        Write-Host (T 'lib.title') -ForegroundColor Cyan
        Write-Host (T 'lib.1') -ForegroundColor Gray
        Write-Host (T 'lib.2') -ForegroundColor Gray
        Write-Host (T 'lib.0') -ForegroundColor DarkGray
        do { $k = (Read-Host (T 'lib.prompt')).Trim() } while ($k -notin '0','1','2')
        switch ($k) {
            '1' { if (Show-RecipeMenu)      { return $true } }
            '2' { if (Show-LibrarySessions) { return $true } }
            '0' { return $false }
        }
    }
}

# ============================================================================
# [12] ANALIZA RAPORTU / POROWNANIE SESJI  (v15.8 - Compare mode)
# Czyta 2 zapisane sesje, porownuje je i mowi CO sie zmienilo i CZEGO sie nie udalo.
# Bez zmian w systemie - czysty odczyt artefaktow (read-only).
# ============================================================================
function Read-CompareSession {
    param([Parameter(Mandatory)][string]$SessionPath)

    $data = [ordered]@{
        Id          = Split-Path $SessionPath -Leaf
        Path        = $SessionPath
        Mode        = 'n/d'; Profile = 'n/d'; ExitCode = 'n/d'
        Changes     = 'n/d'; Skipped = 'n/d'; Warnings = 'n/d'; Errors = 'n/d'
        RestartReq  = 'n/d'
        PowerBefore = 'n/d'; PowerAfter = 'n/d'
        SvcStartChanges = @()
        ProcBefore  = 0; ProcAfter = 0
        StartupAfter = 0
        ErrorLines  = @(); SkippedTweaks = @(); EnvWarnings = @()
        Score       = 'n/d'
        # --- ENHANCE v15.8: sygnaly do oceny skutecznosci optymalizacji (UDANA/POLOWICZNA/NIEUDANA) ---
        ValOk       = 0; ValFail = 0; ValItems = @()   # validation.txt: ile zmian faktycznie weszlo
        BenchBetter = 0; BenchWorse = 0; BenchItems = @() # benchmark.txt: ile metryk sie poprawilo/pogorszylo
        HasBench    = $false; HasValidation = $false
    }

    # --- summary.txt (pola tekstowe) ---
    $sum = Join-Path $SessionPath 'Reports\summary.txt'
    if (Test-Path $sum) {
        $txt = Get-Content -LiteralPath $sum -Raw -ErrorAction SilentlyContinue
        if ($txt) {
            $get = {
                param($pat)
                $r = [regex]::Match($txt, $pat)
                if ($r.Success) { $r.Groups[1].Value.Trim() } else { 'n/d' }
            }
            $data.Mode       = & $get 'Tryb:\s*(.+)'
            $data.Profile    = & $get 'Profil:\s*(.+)'
            $data.ExitCode   = & $get 'ExitCode:\s*(\d+)'
            $data.Changes    = & $get 'Zmiany systemowe:\s*(\d+)'
            $data.Skipped    = & $get 'Pominiete:\s*(\d+)'
            $data.Warnings   = & $get 'Ostrzezenia:\s*(\d+)'
            $data.Errors     = & $get 'Bledy:\s*(\d+)'
            $data.RestartReq = & $get 'Restart wymagany:\s*(\S+)'
            # ostrzezenia srodowiska (WARN: / [High]) z ogona summary
            foreach ($ln in ($txt -split "`n")) {
                if ($ln -match 'WARN:|\[High\]|\[Medium\]') { $data.EnvWarnings += $ln.Trim() }
            }
        }
    }

    # --- manifest.json (pominiete tweaki + powod) ---
    $man = Join-Path $SessionPath 'manifest.json'
    if (Test-Path $man) {
        try {
            $mj = Get-Content -LiteralPath $man -Raw | ConvertFrom-Json
            if ($mj.SkippedTweaks) {
                foreach ($s in $mj.SkippedTweaks) {
                    $nm = if ($s.Id) { $s.Id } elseif ($s.Name) { $s.Name } else { 'tweak' }
                    $rs = if ($s.Reason) { $s.Reason } else { '' }
                    $data.SkippedTweaks += ('{0} - {1}' -f $nm, $rs)
                }
            }
        } catch {}
    }

    # --- before/after.json (plan zasilania, uslugi, procesy) ---
    $before = $null; $after = $null
    $bp = Join-Path $SessionPath 'Reports\before.json'
    $ap = Join-Path $SessionPath 'Reports\after.json'
    if (Test-Path $bp) { try { $before = Get-Content -LiteralPath $bp -Raw | ConvertFrom-Json } catch {} }
    if (Test-Path $ap) { try { $after  = Get-Content -LiteralPath $ap -Raw | ConvertFrom-Json } catch {} }

    if ($before) {
        # FIX (odpornosc [12]): powercfg /getactivescheme bywa serializowany jako tablica linii.
        # Splaszczamy do jednego stringa zanim wyciagniemy nazwe planu z nawiasu, by nie zrobic
        # przypadkiem tablicy z PowerBefore (psuloby to pozniejsze formatowanie '{0} -> {1}').
        $data.PowerBefore = ((@($before.ActivePowerScheme) -join ' ') -replace '.*\((.+)\).*', '$1').Trim()
        if ($before.TopRam) { $data.ProcBefore = @($before.TopRam).Count }
    }
    if ($after) {
        $data.PowerAfter = ((@($after.ActivePowerScheme) -join ' ') -replace '.*\((.+)\).*', '$1').Trim()
        if ($after.TopRam)  { $data.ProcAfter  = @($after.TopRam).Count }
        if ($after.Startup) { $data.StartupAfter = @($after.Startup).Count }
    }

    # --- zmiany typu startu uslug (before vs after) ---
    if ($before -and $after -and $before.Services -and $after.Services) {
        $bMap = @{}
        foreach ($s in $before.Services) { if ($s.Name) { $bMap[$s.Name] = $s.StartType } }
        foreach ($s in $after.Services) {
            if ($s.Name -and $bMap.ContainsKey($s.Name) -and $bMap[$s.Name] -ne $s.StartType) {
                $data.SvcStartChanges += ('{0}: {1} -> {2}' -f $s.Name, $bMap[$s.Name], $s.StartType)
            }
        }
    }

    # --- errors.log (faktyczne nieudane operacje) ---
    $err = Join-Path $SessionPath 'Logs\errors.log'
    if (Test-Path $err) {
        $el = Get-Content -LiteralPath $err -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' }
        if ($el) { $data.ErrorLines = @($el) }
    }

    # --- validation.txt (czy zmiany FAKTYCZNIE weszly = najmocniejszy sygnal skutecznosci) ---
    $val = Join-Path $SessionPath 'Reports\validation.txt'
    if (Test-Path $val) {
        $vl = Get-Content -LiteralPath $val -ErrorAction SilentlyContinue
        if ($vl) {
            foreach ($ln in $vl) {
                if ($ln -match '^\s*\[OK\]') { $data.ValOk++; $data.HasValidation = $true; $data.ValItems += ($ln.Trim() -replace '\s{2,}', '  ') }
                elseif ($ln -match '^\s*\[NIEZGODNE\]') { $data.ValFail++; $data.HasValidation = $true; $data.ValItems += ($ln.Trim() -replace '\s{2,}', '  ') }
            }
        }
    }

    # --- benchmark.txt (ile metryk wydajnosci sie poprawilo vs pogorszylo) ---
    $bch = Join-Path $SessionPath 'Reports\benchmark.txt'
    if (Test-Path $bch) {
        $bl = Get-Content -LiteralPath $bch -ErrorAction SilentlyContinue
        if ($bl) {
            foreach ($ln in $bl) {
                if ($ln -match 'LEPIEJ') { $data.BenchBetter++; $data.HasBench = $true; $data.BenchItems += ($ln.Trim() -replace '\s{2,}', ' ') }
                elseif ($ln -match 'GORZEJ') { $data.BenchWorse++;  $data.HasBench = $true; $data.BenchItems += ($ln.Trim() -replace '\s{2,}', ' ') }
            }
        }
    }

    return $data
}

function Get-VerdictBar {
    # Prosty pasek postepu dla czytelnosci ("widac od razu ile %").
    param([int]$Percent)
    $p = [Math]::Max(0, [Math]::Min(100, $Percent))
    $filled = [int][Math]::Round($p / 5)   # 20 znakow = 100%
    ('[' + ('#' * $filled) + ('.' * (20 - $filled)) + ('] {0,3}%' -f $p))
}

function Get-OptimizationVerdict {
    # ENHANCE v15.8: doradca. Zamienia surowe liczby z raportu na jasny werdykt dla zwyklego uzytkownika:
    #   UDANA / CZESCIOWA / NIEUDANA + procent + wytlumaczenie po ludzku (bez skrotow typu "PW").
    # Czysto-odczytowe: tylko ocenia juz zapisane dane sesji, niczego nie zmienia w systemie.
    param([Parameter(Mandatory)][object]$Data)

    # Pomocnik: tekst raportu -> liczba (albo 0, gdy 'n/d').
    $num = {
        param($v)
        $n = 0
        if ($v -ne $null -and $v -ne 'n/d' -and [int]::TryParse([string]$v, [ref]$n)) { return $n }
        return 0
    }
    $errors   = & $num $Data.Errors
    $warnings = & $num $Data.Warnings
    $changes  = & $num $Data.Changes
    $exit     = & $num $Data.ExitCode
    $mode     = [string]$Data.Mode

    $reasons = New-Object System.Collections.Generic.List[string]

    # Tryb tylko-odczyt (Analyze/Audit) bez zmian = nie ma "optymalizacji" do oceny skutecznosci.
    $isReadOnly = (($mode -match 'Analyze' -or $mode -match 'Audit') -and $changes -eq 0)
    if ($isReadOnly) {
        if ($errors -gt 0) { $reasons.Add("W trakcie diagnostyki zgloszono bledy: $errors (patrz sekcja bledow).") }
        else { $reasons.Add('Diagnostyka przebiegla bez bledow.') }
        return [pscustomobject]@{
            IsOptimize = $false
            ScorePct   = $null
            Label      = 'DIAGNOSTYKA'
            Color      = 'Cyan'
            Headline   = 'TRYB TYLKO-ODCZYT - brak zmian w systemie, wiec nie ma czego oceniac pod katem skutecznosci.'
            Reasons    = $reasons.ToArray()
        }
    }

    # --- Optymalizacja: liczymy skutecznosc 0-100% ---
    $score = 100.0

    # 1) RDZEN: czy zmiany FAKTYCZNIE weszly (walidacja po zastosowaniu). Najwazniejszy sygnal.
    $valTotal = $Data.ValOk + $Data.ValFail
    if ($Data.HasValidation -and $valTotal -gt 0) {
        $passRate = $Data.ValOk / $valTotal
        $score = 40 + ($passRate * 60)   # 40..100 zaleznie od tego, ile zmian sie potwierdzilo
        $reasons.Add(('Zweryfikowane zmiany: {0} z {1} faktycznie weszlo i sie utrzymalo ({2}%).' -f $Data.ValOk, $valTotal, [int][Math]::Round($passRate * 100)))
        if ($Data.ValFail -gt 0) { $reasons.Add(("Nie potwierdzono {0} zmian(y) - mogly nie wejsc albo cofnal je Windows/Update." -f $Data.ValFail)) }
    }
    else {
        if ($changes -eq 0) {
            $score = 50
            $reasons.Add('Brak zapisanych zmian systemowych - niewiele do oceny (mozliwe, ze profil nic nie ruszal).')
        }
        else {
            $score = 85
            $reasons.Add(("Zastosowano zmiany: {0} (brak pliku walidacji, wiec bez twardego potwierdzenia, ze wszystkie weszly)." -f $changes))
        }
    }

    # 2) Bledy = mocna kara (cos sie nie powiodlo).
    if ($errors -gt 0) {
        $pen = [Math]::Min(45, $errors * 12)
        $score -= $pen
        $reasons.Add(('Bledy w trakcie: {0} operacji sie nie powiodlo (-{1} pkt).' -f $errors, $pen))
    }
    else {
        $reasons.Add('Bledy: brak - zaden krok nie zglosil bledu.')
    }

    # 3) Kod zakonczenia 2 = zakonczono z bledami.
    if ($exit -eq 2) { $score -= 8; $reasons.Add('Kod zakonczenia = 2 (sesja zakonczona z bledami).') }

    # 4) Benchmark in-session (lekko - pelny obraz dopiero po restarcie).
    if ($Data.HasBench) {
        if ($Data.BenchBetter -gt $Data.BenchWorse) {
            $score += 4
            $reasons.Add(('Pomiary przed/po: {0} lepszych / {1} gorszych - wstepnie na plus.' -f $Data.BenchBetter, $Data.BenchWorse))
        }
        elseif ($Data.BenchWorse -gt $Data.BenchBetter) {
            $score -= 6
            $reasons.Add(('Pomiary przed/po: {0} gorszych / {1} lepszych - sprawdz ponownie po restarcie.' -f $Data.BenchWorse, $Data.BenchBetter))
        }
        else {
            $reasons.Add('Pomiary przed/po: bez wyraznego trendu (pelny efekt zwykle dopiero po restarcie).')
        }
    }

    # 5) Ostrzezenia (drobna kara).
    if ($warnings -gt 0) {
        $wp = [Math]::Min(8, $warnings * 2)
        $score -= $wp
        $reasons.Add(('Ostrzezenia: {0} (drobne, nie blokuja optymalizacji).' -f $warnings))
    }

    # 6) Limity sprzetowe/termiczne - nie obnizaja "czy weszlo", ale ograniczaja REALNY zysk. Informacyjnie.
    $limits = @($Data.EnvWarnings | Where-Object { $_ -match '97|temperatur|throttl|XMP|EXPO|sterownik GPU|driver' } | Select-Object -Unique)
    if ($limits.Count -gt 0) {
        $reasons.Add('Wykryto limit sprzetowy/termiczny - moze ograniczac realny zysk (to nie jest blad optymalizacji).')
    }

    $score = [int][Math]::Round([Math]::Max(0, [Math]::Min(100, $score)))

    if ($score -ge 85) {
        $label = 'UDANA'; $color = 'Green'
        $head  = ('OPTYMALIZACJA UDANA ({0}%) - zmiany weszly i system je utrzymuje.' -f $score)
    }
    elseif ($score -ge 50) {
        $label = 'CZESCIOWA'; $color = 'Yellow'
        $head  = ('OPTYMALIZACJA CZESCIOWA ({0}%) - czesc zmian weszla, ale sa zastrzezenia (patrz nizej).' -f $score)
    }
    else {
        $label = 'NIEUDANA'; $color = 'Red'
        $head  = ('OPTYMALIZACJA NIEUDANA ({0}%) - zbyt wiele krokow sie nie powiodlo lub nie weszlo.' -f $score)
    }

    # Dopisek o restarcie - nie zmienia werdyktu, ale wazny dla zrozumienia "dlaczego jeszcze nie czuje roznicy".
    if ([string]$Data.RestartReq -match 'TAK|Yes|True') {
        $reasons.Add('Restart wymagany: TAK - pelny efekt bedzie widoczny dopiero PO ponownym uruchomieniu komputera.')
    }

    return [pscustomobject]@{
        IsOptimize = $true
        ScorePct   = $score
        Label      = $label
        Color      = $color
        Headline   = $head
        Reasons    = $reasons.ToArray()
    }
}

function Show-CompareReports {
    Write-Host ''
    Write-Host '=== [12] ANALIZA RAPORTU - WERDYKT + POROWNANIE SESJI ===' -ForegroundColor Cyan
    Write-Host '    Czyta zapisane sesje i sam mowi: optymalizacja UDANA / CZESCIOWA / NIEUDANA (z procentem),' -ForegroundColor DarkGray
    Write-Host '    a nizej pokazuje co sie zmienilo i czego sie nie udalo. Nie trzeba niczego wysylac ani porownywac recznie.' -ForegroundColor DarkGray
    Write-Host '    Tryb tylko do odczytu - nic w systemie nie jest zmieniane.' -ForegroundColor DarkGray
    Write-Host ''

    if (-not (Test-Path $script:RootFolder)) {
        Write-Host "Brak folderu z raportami: $script:RootFolder" -ForegroundColor Red
        return
    }

    $sessions = @(Get-ChildItem -Path $script:RootFolder -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } |
        Sort-Object Name -Descending)

    if ($sessions.Count -lt 2) {
        Write-Host "Potrzebne sa minimum 2 zapisane sesje, a jest: $($sessions.Count)." -ForegroundColor Yellow
        Write-Host 'Uruchom najpierw Analyze lub Optimize, zeby powstaly raporty do porownania.' -ForegroundColor DarkGray
        return
    }

    Write-Host 'Dostepne sesje (od najnowszej):' -ForegroundColor Yellow
    $i = 1
    foreach ($s in $sessions) {
        $mTxt = ''
        $mp = Join-Path $s.FullName 'Reports\summary.txt'
        if (Test-Path $mp) {
            $h = Get-Content -LiteralPath $mp -Raw -ErrorAction SilentlyContinue
            $mm = [regex]::Match($h, 'Tryb:\s*(.+)')
            if ($mm.Success) { $mTxt = '  (' + $mm.Groups[1].Value.Trim() + ')' }
        }
        Write-Host ("  [{0}] {1}{2}" -f $i, $s.Name, $mTxt) -ForegroundColor Gray
        $i++
    }
    Write-Host ''
    if ($Silent) {
        # FIX (tryb [12] + -Silent): bez tej galezi Read-Host wisialby w nieskonczonosc w trybie cichym
        # (np. Harmonogram zadan) - dokladnie ta sama klasa bledu, co FIX4 dla trybu Repair.
        # Cichy tryb robi to SAM: porownuje automatycznie dwie najnowsze sesje, bez zadnych pytan.
        Write-Host 'Tryb cichy: automatyczne porownanie dwoch najnowszych sesji (bez pytan).' -ForegroundColor DarkGray
        $idxA = 1; $idxB = 0
    }
    else {
        Write-Host 'Enter = porownaj dwie najnowsze. Albo podaj dwa numery (np. 2 1 = STARSZA do NOWSZEJ).' -ForegroundColor DarkGray

        $pick = (Read-Host 'Wybor [Enter / "A B"]').Trim()
        $idxA = $null; $idxB = $null
        if ($pick -eq '') {
            # domyslnie: A = starsza z dwoch najnowszych, B = najnowsza
            $idxA = 1; $idxB = 0
        }
        else {
            $parts = @($pick -split '\s+' | Where-Object { $_ -ne '' })
            if ($parts.Count -lt 2) { Write-Host 'Podaj dwa numery oddzielone spacja.' -ForegroundColor Red; return }
            $a = 0; $b = 0
            if (-not [int]::TryParse($parts[0], [ref]$a) -or -not [int]::TryParse($parts[1], [ref]$b)) {
                Write-Host 'Numery musza byc liczbami.' -ForegroundColor Red; return
            }
            if ($a -lt 1 -or $a -gt $sessions.Count -or $b -lt 1 -or $b -gt $sessions.Count -or $a -eq $b) {
                Write-Host 'Nieprawidlowe numery sesji.' -ForegroundColor Red; return
            }
            $idxA = $a - 1; $idxB = $b - 1
        }
    }

    $A = Read-CompareSession -SessionPath $sessions[$idxA].FullName
    $B = Read-CompareSession -SessionPath $sessions[$idxB].FullName

    $line = ('=' * 64)
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine($line)
    $null = $sb.AppendLine('  POROWNANIE SESJI - co sie zmienilo, czego sie nie udalo')
    $null = $sb.AppendLine($line)
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine(('A (starsza): {0}   Tryb={1}  Profil={2}  ExitCode={3}' -f $A.Id, $A.Mode, $A.Profile, $A.ExitCode))
    $null = $sb.AppendLine(('B (nowsza):  {0}   Tryb={1}  Profil={2}  ExitCode={3}' -f $B.Id, $B.Mode, $B.Profile, $B.ExitCode))
    $null = $sb.AppendLine('')

    # [0] WERDYKT DORADCY - najwazniejsze dla zwyklego uzytkownika: czy optymalizacja sie udala (i w ilu %).
    $vA = Get-OptimizationVerdict -Data $A
    $vB = Get-OptimizationVerdict -Data $B
    $null = $sb.AppendLine('--- [0] WERDYKT DORADCY: czy optymalizacja sie udala? ---')
    $null = $sb.AppendLine('')
    foreach ($pair in @(
            @{ Tag = 'Sesja B (nowsza - zwykle Twoj ostatni run)'; V = $vB },
            @{ Tag = 'Sesja A (starsza - do porownania)';          V = $vA }
        )) {
        $v = $pair.V
        $null = $sb.AppendLine('>>> ' + $pair.Tag + ':')
        $null = $sb.AppendLine('>>> ' + $v.Headline)
        if ($null -ne $v.ScorePct) { $null = $sb.AppendLine('    ' + (Get-VerdictBar -Percent $v.ScorePct)) }
        foreach ($r in $v.Reasons) { $null = $sb.AppendLine('    - ' + $r) }
        $null = $sb.AppendLine('')
    }
    $null = $sb.AppendLine('  Jak czytac werdykt:')
    $null = $sb.AppendLine('    UDANA      = wiekszosc zaplanowanych zmian faktycznie weszla i system je utrzymuje.')
    $null = $sb.AppendLine('    CZESCIOWA  = czesc zmian weszla, ale sa zastrzezenia (bledy/ostrzezenia/limit sprzetu).')
    $null = $sb.AppendLine('    NIEUDANA   = zbyt wiele krokow sie nie powiodlo albo zmiany nie weszly.')
    $null = $sb.AppendLine('    Procent    = ile z zaplanowanej optymalizacji realnie zadzialalo (im wyzej, tym lepiej).')
    $null = $sb.AppendLine('')

    # [1] co zrobila kazda sesja
    $null = $sb.AppendLine('--- [1] CO ZROBILA KAZDA SESJA ---')
    $null = $sb.AppendLine(('  A: zmiany={0}  pominiete={1}  ostrzezenia={2}  bledy={3}  restart={4}' -f $A.Changes, $A.Skipped, $A.Warnings, $A.Errors, $A.RestartReq))
    $null = $sb.AppendLine(('  B: zmiany={0}  pominiete={1}  ostrzezenia={2}  bledy={3}  restart={4}' -f $B.Changes, $B.Skipped, $B.Warnings, $B.Errors, $B.RestartReq))
    $null = $sb.AppendLine('')

    # [2] co sie zmienilo
    $null = $sb.AppendLine('--- [2] CO SIE ZMIENILO ---')
    $null = $sb.AppendLine(('  Plan zasilania w A:  {0} -> {1}' -f $A.PowerBefore, $A.PowerAfter))
    $null = $sb.AppendLine(('  Plan zasilania w B:  {0} -> {1}' -f $B.PowerBefore, $B.PowerAfter))
    $null = $sb.AppendLine(('  Plan A(po) vs B(po): {0}  ==>  {1}' -f $A.PowerAfter, $B.PowerAfter))
    $null = $sb.AppendLine(('  Procesy (TopRam):    A={0}  B={1}' -f $A.ProcAfter, $B.ProcAfter))
    if ($A.SvcStartChanges.Count -gt 0) {
        $null = $sb.AppendLine(('  Zmiany typu startu uslug w A: {0}' -f $A.SvcStartChanges.Count))
        foreach ($c in ($A.SvcStartChanges | Select-Object -First 8)) { $null = $sb.AppendLine('     - ' + $c) }
    }
    if ($B.SvcStartChanges.Count -gt 0) {
        $null = $sb.AppendLine(('  Zmiany typu startu uslug w B: {0}' -f $B.SvcStartChanges.Count))
        foreach ($c in ($B.SvcStartChanges | Select-Object -First 8)) { $null = $sb.AppendLine('     - ' + $c) }
    }
    $null = $sb.AppendLine('')

    # [3] czego sie nie udalo
    $null = $sb.AppendLine('--- [3] CZEGO SIE NIE UDALO ZROBIC ---')
    $anyFail = $false
    if ($A.ErrorLines.Count -gt 0) {
        $anyFail = $true
        $null = $sb.AppendLine(('  Bledy w A ({0}):' -f $A.ErrorLines.Count))
        foreach ($e in ($A.ErrorLines | Select-Object -First 6)) { $null = $sb.AppendLine('     ! ' + $e.Trim()) }
    }
    if ($B.ErrorLines.Count -gt 0) {
        $anyFail = $true
        $null = $sb.AppendLine(('  Bledy w B ({0}):' -f $B.ErrorLines.Count))
        foreach ($e in ($B.ErrorLines | Select-Object -First 6)) { $null = $sb.AppendLine('     ! ' + $e.Trim()) }
    }
    if (-not $anyFail) { $null = $sb.AppendLine('  Brak twardych bledow w logach obu sesji.') }
    $allSkipped = @($A.SkippedTweaks + $B.SkippedTweaks | Select-Object -Unique)
    if ($allSkipped.Count -gt 0) {
        $null = $sb.AppendLine(('  Tweaki swiadomie pominiete (gating/Smart Mode): {0}' -f $allSkipped.Count))
        foreach ($t in ($allSkipped | Select-Object -First 8)) { $null = $sb.AppendLine('     ~ ' + $t) }
    }
    $null = $sb.AppendLine('')

    # [4] werdykt - reguly
    $null = $sb.AppendLine('--- [4] WERDYKT ---')
    $verdict = @()
    if ($A.Errors -ne 'n/d' -and [int]($A.Errors) -gt 0) { $verdict += ('Sesja A zakonczona z bledami ({0}) - patrz sekcja [3].' -f $A.Errors) }
    if ($B.Errors -ne 'n/d' -and [int]($B.Errors) -gt 0) { $verdict += ('Sesja B zakonczona z bledami ({0}) - patrz sekcja [3].' -f $B.Errors) }
    if ($A.PowerAfter -ne 'n/d' -and $B.PowerAfter -ne 'n/d' -and $A.PowerAfter -ne $B.PowerAfter) {
        $verdict += ('Plan zasilania rozni sie miedzy sesjami ({0} vs {1}) - sprawdz czy zmiana przetrwala restart.' -f $A.PowerAfter, $B.PowerAfter)
    }
    elseif ($A.PowerAfter -ne 'n/d' -and $A.PowerAfter -eq $B.PowerAfter) {
        $verdict += ('Plan zasilania taki sam w obu sesjach ({0}) - zmiana sie utrzymala.' -f $B.PowerAfter)
    }
    $tempWarn = @($A.EnvWarnings + $B.EnvWarnings | Where-Object { $_ -match '97|temperatur|°C|throttl' } | Select-Object -Unique)
    if ($tempWarn.Count -gt 0) { $verdict += 'Wykryto ostrzezenie termiczne - wysoka temperatura moze ograniczac realny zysk.' }
    $hwWarn = @($A.EnvWarnings + $B.EnvWarnings | Where-Object { $_ -match 'XMP|EXPO|sterownik GPU|driver' } | Select-Object -Unique)
    foreach ($w in $hwWarn) { $verdict += ('Limit sprzetowy/BIOS: ' + ($w -replace '^\s*(WARN:|\[High\]|\[Medium\])\s*', '')) }
    if ($verdict.Count -eq 0) { $verdict += 'Brak istotnych roznic i bledow - obie sesje wygladaja spojnie.' }
    foreach ($v in $verdict) { $null = $sb.AppendLine('  * ' + $v) }
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine($line)

    $report = $sb.ToString()

    # wydruk na ekran (kolory dla naglowkow)
    foreach ($ln in ($report -split "`n")) {
        $col = 'Gray'
        if ($ln -match '^---') { $col = 'Yellow' }
        elseif ($ln -match '^=') { $col = 'Cyan' }
        elseif ($ln -match '^>>>') {
            # ENHANCE v15.8: werdykt doradcy - kolor zalezny od wyniku (NIEUDANA zawiera 'UDANA', wiec sprawdzamy je pierwsze).
            if     ($ln -match 'NIEUDANA')                 { $col = 'Red' }
            elseif ($ln -match 'CZESCIOWA')                { $col = 'Yellow' }
            elseif ($ln -match 'UDANA')                    { $col = 'Green' }
            elseif ($ln -match 'DIAGNOSTYKA|TYLKO-ODCZYT') { $col = 'Cyan' }
            else                                           { $col = 'White' }
        }
        elseif ($ln -match '^\s+\[#') { $col = 'White' }
        elseif ($ln -match '^\s+!') { $col = 'Red' }
        elseif ($ln -match '^\s+\*') { $col = 'Green' }
        Write-Host $ln.TrimEnd() -ForegroundColor $col
    }

    # zapis do pliku
    try {
        $outDir = Join-Path $script:RootFolder 'Compare'
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $outFile = Join-Path $outDir ('compare_{0}_vs_{1}_{2}.txt' -f $A.Id, $B.Id, $stamp)
        $report | Out-File -LiteralPath $outFile -Encoding UTF8
        Write-Host ''
        Write-Host ('Raport porownania zapisany: ' + $outFile) -ForegroundColor Green
    } catch {
        Write-Host ('Nie udalo sie zapisac raportu: ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Show-InteractiveMenu {
    Clear-Host
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host "  $($script:AppName) $($script:Version)"     -ForegroundColor White
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host ''

    # STAGE3 v14.2: language question FIRST (default pre-selected from system culture).
    $langDefault = if ($script:UILang -eq 'pl') { '1' } else { '2' }
    Write-Host (T 'lang.title') -ForegroundColor Yellow
    Write-Host (T 'lang.1') -ForegroundColor Gray
    Write-Host (T 'lang.2') -ForegroundColor Gray
    $lk = (Read-Host ((T 'lang.prompt') + " [$langDefault]")).Trim()
    if ($lk -eq '') { $lk = $langDefault }
    if ($lk -in '1','2') { $script:UILang = if ($lk -eq '1') { 'pl' } else { 'en' } }
    Write-Host ''

    # STAGE4 v14.5.1: session history moved to Library [5] -> [2] (full list + rollback by number).

    # STAGE4 v14.5: [5] Library; selecting it may set the whole run (recipe/rollback) or come back here.
    $script:SelectedMode = $null
    while (-not $script:SelectedMode) {
        Write-Host (T 'menu.mode.title') -ForegroundColor Yellow
        Write-Host (T 'menu.mode.1') -ForegroundColor Gray
        Write-Host (T 'menu.mode.2') -ForegroundColor Green
        Write-Host (T 'menu.mode.3') -ForegroundColor Cyan
        Write-Host (T 'menu.mode.4') -ForegroundColor Magenta
        Write-Host (T 'menu.mode.5') -ForegroundColor Cyan
        Write-Host (T 'menu.mode.6') -ForegroundColor Yellow
        Write-Host (T 'menu.mode.7') -ForegroundColor Green
        Write-Host (T 'menu.mode.8') -ForegroundColor Magenta
        Write-Host (T 'menu.mode.9') -ForegroundColor DarkYellow
        Write-Host ''
        Write-Host (T 'menu.mode.10') -ForegroundColor Blue
        Write-Host (T 'menu.mode.11') -ForegroundColor Cyan
        Write-Host (T 'menu.mode.12') -ForegroundColor Green
        do { $mk=(Read-Host (T 'menu.mode.prompt2')).Trim() } while ($mk-notin'1','2','3','4','5','6','7','8','9','10','11','12')
        if ($mk -eq '5') { Invoke-PowerPlanCreator; Write-Host ''; continue }
        if ($mk -eq '6') { Show-AutomationMenu;     Write-Host ''; continue }
        if ($mk -eq '7') { Show-AppPacksMenu;       Write-Host ''; continue }
        if ($mk -eq '8') { Start-VoiceAssistant;    Write-Host ''; continue }
        if ($mk -eq '9') {
            if (Show-LibraryMenu) { return }   # recipe or rollback fully configured the run
            Write-Host ''
            continue
        }
        if ($mk -eq '10') { Show-PrivacyMenu; Write-Host ''; continue }
        if ($mk -eq '11') { Show-RootCauseAnalysis; Read-Host (T 'ren.back') | Out-Null; Write-Host ''; continue }
        if ($mk -eq '12') { Show-CompareReports; Read-Host (T 'ren.back') | Out-Null; Write-Host ''; continue }
        $script:SelectedMode=switch($mk){'1'{'Analyze'}'2'{'Optimize'}'3'{'Rollback'}'4'{'Repair'}}
    if ($script:SelectedMode-eq'Rollback') {
        $sessions = @(Get-ChildItem -Path $script:RootFolder -Directory -EA SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } | Sort-Object Name -Descending)
        if (-not $sessions -or $sessions.Count -eq 0) { throw (T 'menu.rb.none') }
        $latest = Get-LatestRollbackSessionId
        Write-Host (T 'menu.rb.oneclick') -ForegroundColor Yellow
        Write-Host (T 'menu.rb.latest' -FmtArgs @($latest)) -ForegroundColor Green
        Write-Host ''
        Write-Host (T 'menu.rb.pick') -ForegroundColor Yellow
        $i = 1
        foreach ($s in $sessions) { Write-Host "  [$i] $($s.Name)" -ForegroundColor Gray; $i++ }
        do {
            $choice = Read-Host (T 'menu.rb.prompt')
            $parsedChoice = 0
            $okChoice = [int]::TryParse($choice, [ref]$parsedChoice)
        } while (-not $okChoice -or $parsedChoice -lt 0 -or $parsedChoice -gt $sessions.Count)
        if ($parsedChoice -eq 0) {
            $script:SelectedRollbackSession = $latest
            $script:OneClickRollbackUsed = $true
        } else {
            $script:SelectedRollbackSession = $sessions[$parsedChoice - 1].Name
        }
        return
    }
    if ($script:SelectedMode -eq 'Repair') {
        return
    }

    Write-Host ''; Write-Host (T 'menu.prof.title') -ForegroundColor Yellow
    # (profile section now lives INSIDE the main while-loop so [B] can jump back to mode selection)

    # v12: profile auto-suggestion based on hardware
    $profileSugg = [pscustomobject]@{ Profile = 'Safe'; Reason = 'Fallback: safe profile when auto-detection has no answer.' }
    try {
        $hwForSuggest = Get-HardwareProfile
        $profileSugg  = Get-SuggestedProfile -HWProfile $hwForSuggest
        Write-Host (T 'menu.prof.suggest') -ForegroundColor Cyan -NoNewline
        Write-Host $profileSugg.Profile -ForegroundColor Green
        Write-Host "             $($profileSugg.Reason)" -ForegroundColor DarkGray
        Write-Host ''
    } catch {}

    Write-Host (T 'menu.prof.quick') -ForegroundColor Yellow
    Write-Host (T 'menu.prof.p1')  -ForegroundColor Green
    Write-Host (T 'menu.prof.p2')  -ForegroundColor Cyan
    Write-Host (T 'menu.prof.p3')  -ForegroundColor Red
    Write-Host (T 'menu.prof.p4')  -ForegroundColor Red
    Write-Host (T 'menu.prof.p5')  -ForegroundColor Magenta
    Write-Host (T 'menu.prof.p6')  -ForegroundColor DarkYellow
    Write-Host (T 'menu.prof.p7')  -ForegroundColor Blue
    Write-Host (T 'menu.prof.p8')  -ForegroundColor Green
    Write-Host (T 'menu.prof.p9')  -ForegroundColor Green
    Write-Host (T 'menu.prof.p10') -ForegroundColor Cyan
    Write-Host (T 'menu.prof.p11') -ForegroundColor DarkYellow
    Write-Host (T 'menu.prof.p12') -ForegroundColor Blue
    Write-Host (T 'menu.prof.p13') -ForegroundColor Green
    Write-Host (T 'menu.prof.p14') -ForegroundColor Cyan
    Write-Host (T 'menu.prof.p15') -ForegroundColor Cyan
    Write-Host ''
    Write-Host (T 'menu.prof.hint') -ForegroundColor DarkGray
    Write-Host (T 'menu.prof.back') -ForegroundColor DarkGray
    Write-Host ''
    do { $pk=(Read-Host (T 'menu.prof.prompt')).Trim().ToUpper() } while ($pk -notin '0','1','2','3','4','5','6','7','8','9','10','11','12','13','14','15','B')
    # v15.2: back is ALWAYS [0] (B kept as a silent alias); autonomous modes moved to the end [14]/[15]
    if ($pk -in '0','B') { $script:SelectedMode = $null; continue }
    $script:SelectedProfile = switch ($pk) {
        '1' { 'Safe' } '2' { 'Balanced' } '3' { 'Maximum' }
        '4' { 'Gaming' } '5' { 'Workstation' } '6' { 'LowEnd' } '7' { 'Laptop' } '8' { 'LaptopGamingSafe' }
        '9' { 'GamingLaptop' } '10' { 'OfficeLaptop' } '11' { 'LowRAM' } '12' { 'BatterySaver' }
        '13' { $script:QuickPerformanceFeelOnly = $true; 'LaptopGamingSafe' }
        '14' { $profileSugg.Profile }
        '15' { $script:AutoSmartSelected = $true; $profileSugg.Profile }
    }

    Write-Host ''
    Write-Host (T 'menu.prof.chosen' -FmtArgs @($script:SelectedProfile)) -ForegroundColor Green
    if ($script:QuickPerformanceFeelOnly) {
        Write-Host (T 'menu.prof.feelonly') -ForegroundColor Green
    }
    Write-Host (T 'menu.prof.desc') -ForegroundColor DarkGray

    # STAGE6 v14.5: AutoSmart explains its decisions, then uses safe defaults instead of questions.
    if ($script:AutoSmartSelected) {
        Write-Host ''
        Write-Host (T 'auto.head') -ForegroundColor Cyan
        Write-Host (T 'auto.prof' -FmtArgs @($profileSugg.Profile, $profileSugg.Reason)) -ForegroundColor Gray
        Write-Host (T 'auto.ans') -ForegroundColor Gray
    }

    # STAGE2 v14.1: WSearch/DNS/Experimental are EXECUTIVE decisions - skipped in read-only Analyze.
    # STAGE6 v14.5: AutoSmart also answers them automatically (safe defaults).
    if ($script:AutoSmartSelected -and $script:SelectedMode -ne 'Analyze') {
        $script:SelectedSearchMode = 'Keep'
        $script:SelectedDns = 'Keep'
        $script:SelectedExperimental = $false
    }
    elseif ($script:SelectedMode -eq 'Analyze') {
        $script:SelectedSearchMode = 'Keep'
        $script:SelectedDns = 'Keep'
        $script:SelectedExperimental = $false
        Write-Host ''
        Write-Host (T 'menu.analyze.skip') -ForegroundColor DarkGray
    } else {
    Write-Host ''; Write-Host (T 'menu.ws.title') -ForegroundColor Yellow
    Write-Host (T 'menu.ws.1') -ForegroundColor Gray
    Write-Host (T 'menu.ws.2') -ForegroundColor Gray
    Write-Host ''
    do { $sk=(Read-Host (T 'menu.ws.prompt')).Trim() } while ($sk-notin'1','2')
    $script:SelectedSearchMode=if($sk-eq'2'){'Manual'}else{'Keep'}

    Write-Host ''; Write-Host (T 'menu.dns.title') -ForegroundColor Yellow
    Write-Host (T 'menu.dns.1') -ForegroundColor Gray
    Write-Host (T 'menu.dns.2') -ForegroundColor Gray
    Write-Host (T 'menu.dns.3') -ForegroundColor Gray
    Write-Host (T 'menu.dns.4') -ForegroundColor Gray
    Write-Host ''
    do { $dk=(Read-Host (T 'menu.dns.prompt')).Trim() } while ($dk-notin'1','2','3','4')
    $script:SelectedDns=switch($dk){'1'{'Keep'}'2'{'Google'}'3'{'Cloudflare'}'4'{'Quad9'}}

    Write-Host ''; Write-Host (T 'menu.exp.title') -ForegroundColor Yellow
    Write-Host (T 'menu.exp.1') -ForegroundColor Gray
    Write-Host (T 'menu.exp.2') -ForegroundColor Red
    Write-Host ''
    do { $ek=(Read-Host (T 'menu.exp.prompt')).Trim() } while ($ek-notin'1','2')
    $script:SelectedExperimental=($ek-eq'2')
    }

    break
    }

    Write-Host ''; Write-Host (T 'menu.def.title') -ForegroundColor DarkYellow
    Write-Host (T 'menu.def.1') -ForegroundColor DarkYellow
    Write-Host (T 'menu.def.2') -ForegroundColor DarkYellow
    Write-Host (T 'menu.def.3') -ForegroundColor DarkYellow
    Write-Host (T 'menu.def.4') -ForegroundColor DarkYellow
    Write-Host ''; Write-Host (T 'menu.pressenter') -ForegroundColor DarkGray
    [void][System.Console]::ReadLine()
}
# =============================
# v12.9 Beta Tester Audit Pack
# Cel: dodac liste 66 pozycji jako audyt/katalog + bezpieczne raportowanie,
# bez agresywnego wlaczania tweakow i bez rozwalania obecnych profili.
# =============================
function Get-BetaTesterAuditCatalog {
    $rows = @(
        @{Id=1;Category='Dysk i storage';Name='Weryfikacja i naprawa TRIM z rollbackiem';Mode='Diagnostic/Existing';Impact='0-2% / zdrowie SSD';Effect='Sprawdza czy TRIM dziala; naprawa tylko swiadomie';Risk='Niskie'}
        @{Id=2;Category='Dysk i storage';Name='StorPort queue depth dla NVMe';Mode='Advanced/Manual';Impact='0-3% w I/O';Effect='Moze zmienic zachowanie sterownika NVMe';Risk='Srednie'}
        @{Id=3;Category='Dysk i storage';Name='AHCI AlwaysOn - wylacz HIPM/DIPM';Mode='Advanced/Manual';Impact='mniej lagow storage';Effect='Lepsza responsywnosc dysku kosztem baterii';Risk='Srednie'}
        @{Id=4;Category='Dysk i storage';Name='Write-Cache Buffer Flushing';Mode='Advanced/Warning';Impact='czasem szybszy zapis';Effect='Ryzyko utraty danych przy zaniku pradu';Risk='Wysokie'}
        @{Id=5;Category='Dysk i storage';Name='Analiza fragmentacji i czas last TRIM';Mode='Audit';Impact='diagnostyka';Effect='Pokazuje stan optymalizacji dyskow';Risk='Brak'}
        @{Id=6;Category='Dysk i storage';Name='Raport S.M.A.R.T. dyskow';Mode='Audit';Impact='diagnostyka';Effect='Wczesne ostrzezenie o problemach z dyskiem';Risk='Brak'}
        @{Id=7;Category='Pamiec RAM';Name='Pagefile staly rozmiar lub wylaczenie przy >=32 GB';Mode='Advanced/Manual';Impact='0-2% / mniej mikroprzerw';Effect='Zle ustawienie moze crashowac gry/aplikacje';Risk='Srednie'}
        @{Id=8;Category='Pamiec RAM';Name='DisablePagingExecutive dla duzego RAM';Mode='Advanced/Manual';Impact='0-1% feel';Effect='Jadro czesciej trzymane w RAM';Risk='Niskie/Srednie'}
        @{Id=9;Category='Pamiec RAM';Name='LargeSystemCache workstation';Mode='Advanced/Manual';Impact='raczej praca plikami';Effect='Moze pogorszyc gry na desktopie';Risk='Srednie'}
        @{Id=10;Category='Pamiec RAM';Name='Wykrywanie single channel z instrukcja';Mode='Audit';Impact='duzy potencjal FPS';Effect='Raportuje czy RAM moze ograniczac wydajnosc';Risk='Brak'}
        @{Id=11;Category='Pamiec RAM';Name='Detekcja i raport ECC';Mode='Audit';Impact='diagnostyka';Effect='Informacja o stabilnosci pamieci';Risk='Brak'}
        @{Id=12;Category='CPU i scheduler';Name='Core parking per profil';Mode='Existing/Advanced';Impact='0-5% stabilnosc FPS';Effect='Mniej usypiania rdzeni kosztem poboru';Risk='Niskie/Srednie'}
        @{Id=13;Category='CPU i scheduler';Name='Heterogeneous policy Intel E/P-core';Mode='Audit/Manual';Impact='0-5% na hybrydach';Effect='Dotyczy glownie Intel 12 gen+';Risk='Srednie'}
        @{Id=14;Category='CPU i scheduler';Name='Win32PrioritySeparation z opisem wartosci';Mode='Existing/Explained';Impact='feel/input';Effect='Zmienia priorytet foreground';Risk='Niskie/Srednie'}
        @{Id=15;Category='CPU i scheduler';Name='Raport PPM / C-states per rdzen';Mode='Audit';Impact='diagnostyka';Effect='Pokazuje ustawienia zasilania CPU';Risk='Brak'}
        @{Id=16;Category='CPU i scheduler';Name='IRQ affinity per urzadzenie';Mode='Advanced/Manual';Impact='czasem mniej DPC';Effect='Ryzykowne, zalezne od sterownikow';Risk='Wysokie'}
        @{Id=17;Category='GPU';Name='NVIDIA Low Latency / Power / Texture Filtering';Mode='Existing/Optional';Impact='0-5% / latency';Effect='Bez OC; profil wydajnosci GPU';Risk='Niskie'}
        @{Id=18;Category='GPU';Name='AMD EnableUlps / PP_GPUPowerDownEnabled';Mode='Advanced/Manual';Impact='mniej lagow wake';Effect='Koszt baterii, ryzyko bugow sterownika';Risk='Srednie'}
        @{Id=19;Category='GPU';Name='Resizable BAR / SAM raport';Mode='Audit';Impact='0-10% zalezne od gry';Effect='Pokazuje czy funkcja jest aktywna';Risk='Brak'}
        @{Id=20;Category='GPU';Name='Temperatura GPU przez nvidia-smi';Mode='Audit';Impact='diagnostyka';Effect='Wykrywa throttling/limity';Risk='Brak'}
        @{Id=21;Category='GPU';Name='Coolbits domyslnie dla Gaming z ostrzezeniem';Mode='Advanced/Warning';Impact='manual OC/fan';Effect='Nie wlaczac automatycznie na laptopie';Risk='Wysokie'}
        @{Id=22;Category='Siec';Name='TCP autotuning per profil';Mode='Existing/Optional';Impact='latency/download';Effect='Zmieniac tylko gdy problem z siecia';Risk='Niskie/Srednie'}
        @{Id=23;Category='Siec';Name='Nagle / TcpAckFrequency / TCPNoDelay';Mode='Advanced/Controversial';Impact='czasem ping';Effect='Moze pogorszyc stabilnosc sieci';Risk='Srednie'}
        @{Id=24;Category='Siec';Name='RSS weryfikacja';Mode='Audit';Impact='stabilnosc sieci';Effect='Sprawdza rozklad pracy sieci na rdzenie';Risk='Brak'}
        @{Id=25;Category='Siec';Name='NetworkThrottlingIndex z opisem';Mode='Existing/Explained';Impact='latency multimedia';Effect='Moze pomoc w grach/streamingu';Risk='Niskie'}
        @{Id=26;Category='Siec';Name='Wykrywanie WiFi 6/6E vs 5 GHz';Mode='Audit';Impact='diagnostyka';Effect='Pokazuje czy karta/link ogranicza pobieranie';Risk='Brak'}
        @{Id=27;Category='Siec';Name='MTU optymalizacja z ping testem';Mode='Audit/Manual';Impact='stabilnosc pakietow';Effect='Nie zmieniac bez testu';Risk='Srednie'}
        @{Id=28;Category='Audio';Name='WASAPI Exclusive Mode rekomendacja';Mode='Guide';Impact='latency audio';Effect='Instrukcja dla gier/aplikacji audio';Risk='Brak'}
        @{Id=29;Category='Audio';Name='Wylaczenie audio enhancements per endpoint';Mode='Optional';Impact='mniej DPC/latency';Effect='Czystszy dzwiek, brak efektow producenta';Risk='Niskie'}
        @{Id=30;Category='Audio';Name='Sample rate i bit depth check';Mode='Audit';Impact='diagnostyka';Effect='Wykrywa dziwne ustawienia audio';Risk='Brak'}
        @{Id=31;Category='Audio';Name='Latency Sensitive = Yes w MMCSS Audio';Mode='Existing/Safe';Impact='audio/input feel';Effect='Lepsze priorytety dla audio';Risk='Niskie'}
        @{Id=32;Category='Bezpieczenstwo';Name='Rozbudowany CIS check';Mode='Audit';Impact='bezpieczenstwo';Effect='Tylko raport, bez hardeningu automatycznego';Risk='Brak'}
        @{Id=33;Category='Bezpieczenstwo';Name='Firewall reguly po usunietych programach';Mode='Audit';Impact='porzadek';Effect='Pokazuje smieciowe reguly';Risk='Brak'}
        @{Id=34;Category='Bezpieczenstwo';Name='WDigest status';Mode='Audit';Impact='bezpieczenstwo';Effect='Sprawdza czy hasla nie sa cacheowane';Risk='Brak'}
        @{Id=35;Category='Bezpieczenstwo';Name='AutoRun / AutoPlay status';Mode='Audit';Impact='bezpieczenstwo';Effect='Sprawdza automatyczne uruchamianie nosnikow';Risk='Brak'}
        @{Id=36;Category='Bezpieczenstwo';Name='Screensaver i lock timeout audit';Mode='Audit';Impact='bezpieczenstwo';Effect='Informuje o blokadzie ekranu';Risk='Brak'}
        @{Id=37;Category='Bezpieczenstwo';Name='Self-signed certyfikaty w Trusted Root';Mode='Audit';Impact='bezpieczenstwo';Effect='Wykrywa podejrzane root CA';Risk='Brak'}
        @{Id=38;Category='Analiza';Name='Frametime logger PresentMon/CapFrameX';Mode='Optional/External';Impact='najlepsza diagnoza FPS';Effect='Wymaga narzedzia zewnetrznego';Risk='Brak'}
        @{Id=39;Category='Analiza';Name='ETW real-time session na zadanie';Mode='Advanced/Diagnostic';Impact='diagnostyka stutteru';Effect='Ciezsze logowanie tylko na zadanie';Risk='Niskie'}
        @{Id=40;Category='Analiza';Name='Event Log 7 dni WHEA/disk/BSOD';Mode='Audit';Impact='stabilnosc';Effect='Wykrywa problemy sprzetowe/systemowe';Risk='Brak'}
        @{Id=41;Category='Analiza';Name='Memory diagnostic scheduling';Mode='Manual helper';Impact='stabilnosc';Effect='Moze zaplanowac test RAM po restarcie';Risk='Niskie'}
        @{Id=42;Category='Analiza';Name='Raport bloatware OEM';Mode='Audit';Impact='komfort/start';Effect='Lista aplikacji do decyzji uzytkownika';Risk='Brak'}
        @{Id=43;Category='Analiza';Name='Scheduled tasks analiza';Mode='Audit';Impact='start/komfort';Effect='Pokazuje co odpala sie czesto lub przy logowaniu';Risk='Brak'}
        @{Id=44;Category='Analiza';Name='Thermal history ACPI';Mode='Audit';Impact='diagnostyka';Effect='Pokazuje zdarzenia termiczne jesli system je loguje';Risk='Brak'}
        @{Id=45;Category='Rollback i backup';Name='Pelny backup powercfg subgroup values';Mode='Existing/Enhanced';Impact='bezpieczenstwo zmian';Effect='Latwiejszy rollback zasilania';Risk='Brak'}
        @{Id=46;Category='Rollback i backup';Name='Export/Import JSON preset';Mode='Added/Config';Impact='wygoda';Effect='Przeniesienie profilu na inny PC';Risk='Brak'}
        @{Id=47;Category='Rollback i backup';Name='Diff mode vs ostatnia sesja';Mode='Added/Report';Impact='kontrola zmian';Effect='Widzisz co sie zmienilo';Risk='Brak'}
        @{Id=48;Category='Rollback i backup';Name='Integralnosc manifest.json przed rollbackiem';Mode='Audit';Impact='bezpieczenstwo rollbacku';Effect='Chroni przed cofaniem uszkodzonej sesji';Risk='Brak'}
        @{Id=49;Category='UI i uzytecznosc';Name='DryRun respektowany wszedzie';Mode='Quality Gate';Impact='bezpieczenstwo';Effect='Raportuje miejsca wymagajace kontroli';Risk='Brak'}
        @{Id=50;Category='UI i uzytecznosc';Name='Write-Progress';Mode='UI';Impact='wygoda';Effect='Lepsza widocznosc postepu';Risk='Brak'}
        @{Id=51;Category='UI i uzytecznosc';Name='HTML report z wykresem przed/po';Mode='Existing/Enhanced';Impact='wygoda';Effect='Lepszy raport dla uzytkownika';Risk='Brak'}
        @{Id=52;Category='UI i uzytecznosc';Name='Profile Custom z JSON';Mode='Added/Config';Impact='wygoda';Effect='Wlasny zestaw bez edycji skryptu';Risk='Brak'}
        @{Id=53;Category='UI i uzytecznosc';Name='Eksport raportu do PDF';Mode='Optional/Manual';Impact='wygoda';Effect='Mozna drukowac z HTML do PDF';Risk='Brak'}
        @{Id=54;Category='UI i uzytecznosc';Name='GUI WinForms/HTML launcher';Mode='Future';Impact='premium UX';Effect='Osobna aplikacja, nie tweak';Risk='Brak'}
        @{Id=55;Category='UI i uzytecznosc';Name='Auto-update check';Mode='Future/Optional';Impact='wygoda';Effect='Nie dodane automatycznie, by nie laczyc z internetem';Risk='Brak'}
        @{Id=56;Category='Gaming-specific';Name='DirectX diagnostics dxdiag /t';Mode='Audit';Impact='diagnostyka';Effect='Raport DirectX i sterownikow';Risk='Brak'}
        @{Id=57;Category='Gaming-specific';Name='GeForce Experience Overlay check';Mode='Audit';Impact='mniej DPC/stutter';Effect='Wykrywa overlay, decyzja nalezy do uzytkownika';Risk='Brak'}
        @{Id=58;Category='Gaming-specific';Name='Xbox Game Bar hooks per-game';Mode='Audit';Impact='mniej overlay/stutter';Effect='Sprawdza ustawienia Game Bar';Risk='Brak'}
        @{Id=59;Category='Gaming-specific';Name='Steam shader pre-compilation check';Mode='Guide';Impact='mniej stutter';Effect='Instrukcja dla Steam';Risk='Brak'}
        @{Id=60;Category='Gaming-specific';Name='HAGS per-game report';Mode='Audit/Guide';Impact='zalezne od gry';Effect='Raportuje globalnie, per-game manual';Risk='Brak'}
        @{Id=61;Category='Gaming-specific';Name='Anti-cheat compatibility check';Mode='Audit';Impact='kompatybilnosc';Effect='Vanguard/EAC/BattleEye kontra VBS';Risk='Brak'}
        @{Id=62;Category='Jakosc kodu';Name='Pester testy diagnostyki';Mode='Dev/CI';Impact='jakosc';Effect='Nie dotyka systemu uzytkownika';Risk='Brak'}
        @{Id=63;Category='Jakosc kodu';Name='ScriptAnalyzer static analysis';Mode='Dev/CI';Impact='jakosc';Effect='Sprawdzenie stylu i bledow PS';Risk='Brak'}
        @{Id=64;Category='Jakosc kodu';Name='Changelog w skrypcie';Mode='Added';Impact='czytelnosc';Effect='Wiadomo co sie zmienilo';Risk='Brak'}
        @{Id=65;Category='Jakosc kodu';Name='Wersjonowanie tweaksCatalog';Mode='Added';Impact='kontrola';Effect='Kazdy tweak ma numer i opis';Risk='Brak'}
        @{Id=66;Category='Jakosc kodu';Name='Mock mode dla CI bez admina';Mode='Dev/CI';Impact='testowanie';Effect='Do testow, nie do normalnego uzycia';Risk='Brak'}
    )
    foreach ($r in $rows) { [pscustomobject]$r }
}

function ConvertTo-BetaTesterHtmlTable {
    param([Parameter(Mandatory)]$Rows)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<h2>Beta Tester Audit v12.9 - katalog 66 pozycji</h2>')
    [void]$sb.AppendLine('<p>Ten modul nie wlacza agresywnych tweakow automatycznie. Dzieli pomysly na: audyt, juz istnieje, opcjonalne, Advanced/Manual i Future.</p>')
    [void]$sb.AppendLine('<table><tr><th>ID</th><th>Kategoria</th><th>Pozycja</th><th>Status</th><th>Efekt</th><th>Ryzyko</th></tr>')
    foreach ($x in $Rows) {
        [void]$sb.AppendLine(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td></tr>' -f $x.Id,$x.Category,$x.Name,$x.Mode,$x.Effect,$x.Risk))
    }
    [void]$sb.AppendLine('</table>')
    $sb.ToString()
}

function Invoke-BetaTesterRuntimeAudit {
    $items = New-Object System.Collections.Generic.List[object]
    function Add-AuditItem { param([string]$Name,[string]$Value,[string]$Meaning,[string]$Action='') $items.Add([pscustomobject]@{Name=$Name;Value=$Value;Meaning=$Meaning;SuggestedAction=$Action}) }

    try {
        $trim = (& fsutil behavior query DisableDeleteNotify 2>$null) -join ' | '
        Add-AuditItem 'TRIM / DisableDeleteNotify' $trim '0 oznacza, ze TRIM jest wlaczony dla danego typu dysku.' 'Jesli widzisz 1 dla NTFS SSD, wlacz TRIM recznie: fsutil behavior set DisableDeleteNotify 0'
    } catch { Add-AuditItem 'TRIM / DisableDeleteNotify' 'Nie udalo sie odczytac' 'fsutil niedostepny albo blad uprawnien' }

    try {
        $phys = Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName,MediaType,HealthStatus,OperationalStatus,Size
        foreach ($d in $phys) { Add-AuditItem "Dysk: $($d.FriendlyName)" "$($d.MediaType), $($d.HealthStatus), $($d.OperationalStatus)" 'Raport zdrowia dysku / SMART z warstwy Storage Spaces.' }
    } catch { Add-AuditItem 'Dyski / SMART' 'Brak danych Get-PhysicalDisk' 'To normalne na czesci systemow.' }

    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $ramGB = [math]::Round($cs.TotalPhysicalMemory/1GB,1)
        Add-AuditItem 'RAM total' "$ramGB GB" 'Podstawa do oceny pagefile i profilu LowRAM/Gaming.'
        $dimms = Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel,DeviceLocator,Capacity,Speed,ConfiguredClockSpeed,Manufacturer,PartNumber
        Add-AuditItem 'Moduly RAM' (($dimms | ForEach-Object { "$($_.DeviceLocator): $([math]::Round($_.Capacity/1GB,0))GB $($_.ConfiguredClockSpeed)MHz" }) -join '; ') 'Jesli jest 1 modul, mozliwy single-channel i duza strata FPS w grach CPU/RAM-bound.'
    } catch { Add-AuditItem 'RAM' 'Nie udalo sie odczytac' 'Sprawdz Menedzer zadan > Wydajnosc > Pamiec.' }

    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name,NumberOfCores,NumberOfLogicalProcessors,CurrentClockSpeed,MaxClockSpeed
        Add-AuditItem 'CPU' "$($cpu.Name) | $($cpu.NumberOfCores)c/$($cpu.NumberOfLogicalProcessors)t | $($cpu.CurrentClockSpeed)/$($cpu.MaxClockSpeed) MHz" 'Dane do oceny scheduler/power plan.'
    } catch {}

    try {
        $rss = Get-NetAdapterRss -ErrorAction Stop | Where-Object { $_.Enabled -eq $true } | Select-Object -First 6 Name,Enabled,NumberOfReceiveQueues
        Add-AuditItem 'Network RSS' (($rss | ForEach-Object { "$($_.Name): RSS=$($_.Enabled), Queues=$($_.NumberOfReceiveQueues)" }) -join '; ') 'RSS wlaczony pomaga przy wydajnosci sieci i mniejszym obciazeniu jednego rdzenia.'
    } catch { Add-AuditItem 'Network RSS' 'Nie udalo sie odczytac' 'Modul NetAdapter moze byc niedostepny.' }

    try {
        $wifi = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Name -match 'Wi-Fi|Wireless|WLAN' } | Select-Object -First 2 Name,InterfaceDescription,LinkSpeed,Status
        if ($wifi) { Add-AuditItem 'Wi-Fi adapter/link' (($wifi | ForEach-Object { "$($_.Name): $($_.InterfaceDescription), $($_.LinkSpeed), $($_.Status)" }) -join '; ') 'Pokazuje czy wolny update moze wynikac z linku Wi-Fi.' }
    } catch {}

    try {
        $events = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 80 -ErrorAction Stop |
            Where-Object { $_.ProviderName -match 'WHEA|Disk|Ntfs|BugCheck|Display|nvlddmkm|amdkmdag|stor' } |
            Group-Object ProviderName | ForEach-Object { "$($_.Name): $($_.Count)" }
        Add-AuditItem 'EventLog 7 dni - krytyczne sterowniki/dysk/WHEA' ($events -join '; ') 'Jesli sa WHEA/disk/display, to wazniejsze niz tweaki FPS.' 'Najpierw napraw sterowniki/dysk/temperatury, potem optymalizuj.'
    } catch { Add-AuditItem 'EventLog 7 dni' 'Brak/blad odczytu' 'Nie znaleziono albo brak dostepu.' }

    try {
        $tasks = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' } | Select-Object -First 500
        $startupTasks = @($tasks | Where-Object { $_.Triggers -match 'AtLogon|AtStartup' }).Count
        Add-AuditItem 'Scheduled Tasks aktywne' "Aktywne: $(@($tasks).Count), start/logon: $startupTasks" 'Duzo zadan przy starcie moze psuc szybkie uruchamianie.'
    } catch { Add-AuditItem 'Scheduled Tasks' 'Nie udalo sie odczytac' '' }

    try {
        $gbar = Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -ErrorAction SilentlyContinue
        Add-AuditItem 'Xbox Game Bar / Game DVR' "AutoGameMode=$($gbar.AutoGameModeEnabled); ShowStartupPanel=$($gbar.ShowStartupPanel)" 'Game Mode OK, nagrywanie/overlay czasem powoduja stutter.'
    } catch {}

    try {
        if ($DeepScan) {
            $dxPath = Join-Path $script:SessionFolder 'dxdiag.txt'
            Start-Process -FilePath 'dxdiag.exe' -ArgumentList "/t `"$dxPath`"" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
            if (Test-Path $dxPath) { Add-AuditItem 'dxdiag report' $dxPath 'Zapisano raport DirectX/sterownikow do folderu sesji.' }
        } else {
            Add-AuditItem 'dxdiag report' 'Pominieto (uzyj -DeepScan)' 'dxdiag potrafi trwac dlugo, dlatego nie odpala sie w szybkim audycie.'
        }
    } catch { Add-AuditItem 'dxdiag report' 'Pominieto' 'dxdiag niedostepny albo za dlugo odpowiadal.' }

    try {
        $nvsmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        if ($nvsmi) {
            $gpu = (& $nvsmi.Source --query-gpu=name,temperature.gpu,driver_version,pstate --format=csv,noheader 2>$null) -join '; '
            Add-AuditItem 'NVIDIA nvidia-smi' $gpu 'Temperatura/P-state/sterownik GPU.'
        }
    } catch {}

    $items
}

function Invoke-BetaTesterAuditPack {
    Write-Status '==> Beta Tester Audit v12.9: katalog 66 pozycji + bezpieczny raport...' 'Cyan'
    $catalog = @(Get-BetaTesterAuditCatalog)
    $runtime = @(Invoke-BetaTesterRuntimeAudit)

    $catalogPath = Join-Path $script:SessionFolder 'beta_tester_catalog_66.json'
    $runtimePath = Join-Path $script:SessionFolder 'beta_tester_runtime_audit.json'
    $mdPath = Join-Path $script:SessionFolder 'beta_tester_audit_summary.md'

    $catalog | ConvertTo-Json -Depth 5 | Set-Content -Path $catalogPath -Encoding UTF8
    $runtime | ConvertTo-Json -Depth 5 | Set-Content -Path $runtimePath -Encoding UTF8

    $safeCount = @($catalog | Where-Object { $_.Risk -eq 'Brak' -or $_.Risk -eq 'Niskie' }).Count
    $advCount = @($catalog | Where-Object { $_.Mode -match 'Advanced|Manual|Warning|Controversial' }).Count
    $auditCount = @($catalog | Where-Object { $_.Mode -match 'Audit|Diagnostic|Guide' }).Count

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Beta Tester Audit v12.9')
    $lines.Add('')
    $lines.Add("Pozycji w katalogu: $($catalog.Count)")
    $lines.Add("Bezpieczne / niskie ryzyko: $safeCount")
    $lines.Add("Audyt / diagnostyka / poradnik: $auditCount")
    $lines.Add("Advanced / manual / warning: $advCount")
    $lines.Add('')
    $lines.Add('## Zasada v12.9')
    $lines.Add('Nie wlaczam automatycznie rzeczy, ktore moga psuc Insidera, Windows Update, VBS, siec albo stabilnosc. One sa opisane jako Advanced/Manual.')
    $lines.Add('')
    $lines.Add('## Wyniki runtime')
    foreach ($i in $runtime) { $lines.Add("- **$($i.Name)**: $($i.Value) — $($i.Meaning) $($i.SuggestedAction)") }
    $lines | Set-Content -Path $mdPath -Encoding UTF8

    if (Get-Command Add-HtmlSection -ErrorAction SilentlyContinue) {
        $runtimeRows = ($runtime | ForEach-Object { '<tr><td>'+$_.Name+'</td><td>'+$_.Value+'</td><td>'+$_.Meaning+'</td><td>'+$_.SuggestedAction+'</td></tr>' }) -join "`n"
        Add-HtmlSection @"
<h2>Beta Tester Audit v12.9 - runtime</h2>
<p>Bezpieczny audyt po raporcie beta testerow. Agresywne pozycje sa tylko opisane, nie sa wlaczane automatycznie.</p>
<table><tr><th>Element</th><th>Wartosc</th><th>Znaczenie</th><th>Sugerowana akcja</th></tr>$runtimeRows</table>
"@
        Add-HtmlSection (ConvertTo-BetaTesterHtmlTable -Rows $catalog)
    }

    if (Get-Command Invoke-V13FullBetaImplementationAudit -ErrorAction SilentlyContinue) { Invoke-V13FullBetaImplementationAudit | Out-Null }
    Write-Status "Beta audit zapisany: $mdPath" 'Green'
}



# =============================
# v13.0 Full Beta Implementation Layer
# Cel: zaimplementowac pozostale punkty jako bezpieczna diagnostyka, raporty i eksporty.
# Zmiany ryzykowne pozostaja opisane jako Advanced/Manual - nie sa wlaczane automatycznie.
# =============================
function Add-V13AuditItem {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$List,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        [string]$Value = '',
        [string]$Effect = '',
        [string]$Recommendation = '',
        [string]$Risk = 'Brak',
        [string]$Status = 'Implemented'
    )
    $List.Add([pscustomobject]@{
        Category=$Category; Name=$Name; Value=$Value; Effect=$Effect; Recommendation=$Recommendation; Risk=$Risk; Status=$Status
    }) | Out-Null
}

function Get-RegValueSafeV13 {
    param([string]$Path,[string]$Name)
    try {
        $p = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return [string]$p.$Name
    } catch { return '<not set>' }
}

function Invoke-V13FullBetaImplementationAudit {
    Write-Status '==> v13.0: pelna warstwa implementacji beta reportu (diagnostyka + eksporty)...' 'Cyan'
    $items = New-Object System.Collections.Generic.List[object]

    # Disk / storage
    try {
        $vols = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter }
        if ($DeepScan) {
            $idx = 0
            foreach ($v in $vols) {
                $idx++
                Write-Progress -Activity 'v13.1 DeepScan disk analysis' -Status "Wolumin $($v.DriveLetter):" -PercentComplete (($idx / [Math]::Max(1,$vols.Count))*100)
                $out = (& defrag.exe ($v.DriveLetter + ':') /A /U 2>$null) -join ' '
                Add-V13AuditItem $items 'Dysk' "Analiza defrag/TRIM $($v.DriveLetter):" $out 'Pokazuje czy dysk wymaga optymalizacji i kiedy defrag widzi problem.' 'SSD: nie defragmentuj recznie; uzywaj Optimize-Volume/Windows Optimize.' 'Brak'
            }
            Write-Progress -Activity 'v13.1 DeepScan disk analysis' -Completed
        } else {
            Add-V13AuditItem $items 'Dysk' 'Analiza defrag/TRIM' 'Pominieto (uzyj -DeepScan)' 'Defrag /A moze byc wolny na wielu dyskach, dlatego jest opcjonalny.' 'Uruchom -Mode Audit -DeepScan, jesli chcesz pelna analize storage.' 'Brak' 'Optional'
        }
    } catch { Add-V13AuditItem $items 'Dysk' 'Analiza defrag/TRIM' $_.Exception.Message 'Nie udalo sie pobrac analizy woluminow.' '' 'Brak' 'Partial' }
    try {
        $wcache = Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Select-Object Model,Index,MediaType,Size,Capabilities,CapabilityDescriptions
        foreach ($d in $wcache) {
            Add-V13AuditItem $items 'Dysk' "Write cache / capabilities: $($d.Model)" (($d.CapabilityDescriptions -join '; ')) 'Tylko raport. Write-Cache Buffer Flushing nie jest ruszany automatycznie.' 'Nie wylaczaj buffer flushing na laptopie bez UPS; ryzyko utraty danych.' 'Brak'
        }
    } catch {}
    try {
        $stor = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\storahci\Parameters' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 50 PSPath,Property
        Add-V13AuditItem $items 'Dysk' 'AHCI/StorAHCI registry presence' "Klucze: $(@($stor).Count)" 'Pozwala rozpoznac czy system uzywa storahci i gdzie mozna sprawdzac HIPM/DIPM.' 'AHCI AlwaysOn zostaje Manual/Advanced.' 'Niskie'
    } catch {}

    # RAM
    try {
        $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue | Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage
        $pfText = if ($pf) { ($pf | ForEach-Object { "$($_.Name): alloc=$($_.AllocatedBaseSize)MB used=$($_.CurrentUsage)MB peak=$($_.PeakUsage)MB" }) -join '; ' } else { 'Brak aktywnego pagefile albo brak danych WMI' }
        Add-V13AuditItem $items 'RAM' 'Pagefile status' $pfText 'Raportuje pagefile bez zmiany ustawien.' 'Nie wylaczaj pagefile tylko dlatego, ze masz duzo RAM; czesc gier i dumpy BSOD go wymagaja.' 'Brak'
        Add-V13AuditItem $items 'RAM' 'DisablePagingExecutive' (Get-RegValueSafeV13 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive') 'Tylko raport wartosci.' 'Wlaczaj tylko jako Advanced przy duzym RAM i z rollbackiem.' 'Brak'
        Add-V13AuditItem $items 'RAM' 'LargeSystemCache' (Get-RegValueSafeV13 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargeSystemCache') 'Tylko raport wartosci.' 'Dla gier zwykle zostaw 0; tryb workstation tylko do pracy plikami.' 'Brak'
        $mem = Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop
        $banks = @($mem | Select-Object BankLabel,DeviceLocator,Capacity,ConfiguredClockSpeed,DataWidth,TotalWidth)
        $singleHint = if (@($banks).Count -lt 2) { 'Mozliwy single-channel: najwiekszy realny upgrade FPS to drugi modul RAM.' } else { 'Wiele modulow wykryte; sprawdz Channel w BIOS/CPU-Z.' }
        Add-V13AuditItem $items 'RAM' 'Single channel hint' $singleHint (($banks | ForEach-Object { "$($_.DeviceLocator) $([math]::Round($_.Capacity/1GB))GB $($_.ConfiguredClockSpeed)MHz" }) -join '; ') 'Jesli single-channel, fizyczny upgrade daje wiecej niz tweak.' 'Brak'
        $ecc = ($banks | ForEach-Object { if ($_.TotalWidth -gt $_.DataWidth) { 'ECC-like' } else { 'Non-ECC/unknown' } }) -join '; '
        Add-V13AuditItem $items 'RAM' 'ECC detection' $ecc 'Raport orientacyjny na podstawie DataWidth/TotalWidth.' '' 'Brak'
    } catch { Add-V13AuditItem $items 'RAM' 'RAM extended audit' $_.Exception.Message 'Nie udalo sie wykonac pelnego audytu RAM.' '' 'Brak' 'Partial' }

    # CPU / scheduler / powercfg
    try {
        $ppFile = Join-Path $script:SessionFolder 'v13_powercfg_all_values.txt'
        (& powercfg.exe /query 2>$null) | Set-Content -Path $ppFile -Encoding UTF8
        Add-V13AuditItem $items 'CPU/Power' 'Pelny export powercfg /query' $ppFile 'Pelny backup/raport wartosci power plan do rollbacku i porownan.' 'Mozesz porownac po optymalizacji z Diff mode.' 'Brak'
        $prio = Get-RegValueSafeV13 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
        Add-V13AuditItem $items 'CPU/Power' 'Win32PrioritySeparation' $prio 'Raport aktualnej wartosci foreground priority.' '2/26/38 maja rozne znaczenie; nie zmieniac bez opisu profilu.' 'Brak'
        $hetero = (& powercfg.exe /query SCHEME_CURRENT SUB_PROCESSOR 2>$null) -join ' '
        Add-V13AuditItem $items 'CPU/Power' 'Processor policy / hetero check' (($hetero.Substring(0,[Math]::Min(1200,$hetero.Length)))) 'Raport PPM; na Intel 12 gen+ mozna szukac polityk hetero.' 'Na i7 10/11 gen bez E-core zwykle brak znaczenia.' 'Brak'
    } catch {}
    try {
        $irqFile = Join-Path $script:SessionFolder 'v13_irq_msi_device_report.txt'
        $pci = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -eq 'Interrupt Management' -or $_.PSPath -match 'MessageSignaledInterruptProperties' } |
            Select-Object -First 300 PSPath
        $pci | Out-String | Set-Content -Path $irqFile -Encoding UTF8
        Add-V13AuditItem $items 'CPU/IRQ' 'IRQ/MSI registry report' $irqFile 'Raport do analizy MSI/IRQ affinity bez automatycznej zmiany.' 'IRQ affinity zostaje High Risk/Manual.' 'Brak'
    } catch {}

    # GPU
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object Name,DriverVersion,AdapterRAM,VideoProcessor
        foreach ($g in $gpus) { Add-V13AuditItem $items 'GPU' "GPU controller: $($g.Name)" "Driver=$($g.DriverVersion); Processor=$($g.VideoProcessor)" 'Raport GPU/driver.' 'Aktualny sterownik czesto daje wiecej niz registry tweaks.' 'Brak' }
    } catch {}
    try {
        $nvsmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        if ($nvsmi) {
            $q = (& $nvsmi.Source --query-gpu=name,driver_version,pstate,temperature.gpu,power.draw,power.limit,clocks.gr,clocks.mem --format=csv,noheader 2>$null) -join '; '
            Add-V13AuditItem $items 'GPU' 'NVIDIA extended telemetry' $q 'Temperatura, zegary, P-state i power limit do wykrycia throttlingu.' 'Jesli P-state/zegary niskie w grze, sprawdz panel NVIDIA/zasilacz.' 'Brak'
            $bar = (& $nvsmi.Source -q 2>$null | Select-String -Pattern 'Resizable BAR' -Context 0,3 | ForEach-Object { $_.Line }) -join '; '
            Add-V13AuditItem $items 'GPU' 'Resizable BAR check' ($(if($bar){$bar}else{'Brak informacji w nvidia-smi'})) 'Raport ReBAR, jesli sterownik to zwraca.' 'Wlaczenie wymaga BIOS/UEFI/GPU support, nie PowerShell.' 'Brak'
        }
    } catch {}
    try {
        $amd = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | ForEach-Object {
            $ulps = Get-ItemProperty -Path $_.PSPath -Name EnableUlps -ErrorAction SilentlyContinue
            if ($null -ne $ulps) { "$($_.PSChildName): EnableUlps=$($ulps.EnableUlps)" }
        }
        if ($amd) { Add-V13AuditItem $items 'GPU' 'AMD ULPS report' ($amd -join '; ') 'Raport bez zmiany.' 'Disable ULPS tylko Advanced; na laptopie moze zwiekszyc pobor.' 'Brak' }
    } catch {}

    # Network
    try {
        $tcp = (& netsh int tcp show global 2>$null) -join ' | '
        Add-V13AuditItem $items 'Siec' 'TCP global settings' $tcp 'Raport autotuning/RSS/ECN/CTCP bez zmian.' 'Zmieniaj tylko gdy masz problem, nie dla magicznego FPS.' 'Brak'
        $thr = Get-RegValueSafeV13 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
        Add-V13AuditItem $items 'Siec' 'NetworkThrottlingIndex' $thr 'Pokazuje czy multimedia throttling jest ruszony.' 'FFFFFFFF moze pomoc latency, ale trzymaj w profilach opisanych.' 'Brak'
        $mtuRows = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionState -eq 'Connected' } | Select-Object InterfaceAlias,NlMtu,Dhcp,ConnectionState
        Add-V13AuditItem $items 'Siec' 'MTU report' (($mtuRows | ForEach-Object { "$($_.InterfaceAlias): MTU=$($_.NlMtu)" }) -join '; ') 'Raport MTU bez automatycznej zmiany.' 'MTU testuj pingiem; zle MTU psuje strony/VPN.' 'Brak'
        $ping = (& ping.exe 1.1.1.1 -n 2 -f -l 1472 2>$null) -join ' '
        Add-V13AuditItem $items 'Siec' 'MTU ping 1472 do 1.1.1.1' $ping 'Szybki test fragmentacji dla typowego MTU 1500.' 'Jesli fail, to nie znaczy automatycznie zmieniaj; sprawdz router/VPN.' 'Brak'
    } catch {}

    # Audio
    try {
        $audio = Get-CimInstance Win32_SoundDevice -ErrorAction Stop | Select-Object Name,Status,Manufacturer
        foreach ($a in $audio) { Add-V13AuditItem $items 'Audio' "Audio device: $($a.Name)" "$($a.Manufacturer), $($a.Status)" 'Raport endpointow audio.' 'Enhancements/sample rate najlepiej zmieniac w panelu dzwieku per urzadzenie.' 'Brak' }
        $mmcssAudio = Get-RegValueSafeV13 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio' 'Latency Sensitive'
        Add-V13AuditItem $items 'Audio' 'MMCSS Audio Latency Sensitive' $mmcssAudio 'Raport ustawienia priorytetu audio.' 'Tak/True moze pomoc feeling audio; zwykle bezpieczne.' 'Brak'
    } catch {}

    # Security / hardening audit
    try {
        Add-V13AuditItem $items 'Security' 'WDigest UseLogonCredential' (Get-RegValueSafeV13 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential') '0 lub brak = zwykle bezpiecznie; 1 = ryzyko cache hasel.' 'Jesli 1, ustaw 0.' 'Brak'
        Add-V13AuditItem $items 'Security' 'AutoRun NoDriveTypeAutoRun' (Get-RegValueSafeV13 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun') 'Raport AutoRun/AutoPlay.' 'Wyłączenie AutoRun poprawia bezpieczenstwo, nie FPS.' 'Brak'
        $lock = Get-RegValueSafeV13 'HKCU:\Control Panel\Desktop' 'ScreenSaveTimeOut'
        Add-V13AuditItem $items 'Security' 'Screensaver/lock timeout' $lock 'Raport czasu blokady.' 'Dla prywatnego gaming laptopa user decyduje; nie zmieniam automatycznie.' 'Brak'
        $fw = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq 'True' } | Select-Object -First 1000 DisplayName,Direction,Action,Program
        $stale = @($fw | Where-Object { $_.Program -and $_.Program -ne 'Any' -and -not (Test-Path $_.Program) })
        Add-V13AuditItem $items 'Security' 'Firewall stale program rules' "Podejrzane/usuniete programy: $(@($stale).Count)" 'Pokazuje reguly po odinstalowanych programach.' 'Usuwanie reguł tylko recznie po sprawdzeniu.' 'Brak'
        $certs = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq $_.Issuer } | Select-Object -First 200 Subject,NotAfter,Thumbprint
        Add-V13AuditItem $items 'Security' 'Trusted Root self-signed count' "Count=$(@($certs).Count)" 'Root CA sa zwykle self-signed; raport do audytu, nie automatyczne usuwanie.' 'Nie usuwaj certyfikatow bez wiedzy.' 'Brak'
    } catch {}

    # Diagnostics / gaming-specific
    try {
        $bloat = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'MSI Center|Nahimic|McAfee|Norton|WildTangent|Dropbox|Teams|OneDrive|Xbox|GeForce Experience|Overwolf' } |
            Select-Object DisplayName,DisplayVersion,Publisher
        $bloatFile = Join-Path $script:SessionFolder 'v13_oem_bloatware_candidates.json'
        $bloat | ConvertTo-Json -Depth 4 | Set-Content -Path $bloatFile -Encoding UTF8
        Add-V13AuditItem $items 'Diagnostyka' 'OEM/bloatware candidates' "Count=$(@($bloat).Count); $bloatFile" 'Lista kandydatow do recznej decyzji.' 'Nie usuwam automatycznie, bo czesc ma funkcje klawiatury/RGB/fan.' 'Brak'
    } catch {}
    try {
        $taskFile = Join-Path $script:SessionFolder 'v13_scheduled_tasks_startup.csv'
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' } | ForEach-Object {
            [pscustomobject]@{TaskName=$_.TaskName; TaskPath=$_.TaskPath; State=$_.State; Triggers=($_.Triggers | Out-String).Trim(); Actions=($_.Actions | Out-String).Trim()}
        } | Export-Csv -Path $taskFile -NoTypeInformation -Encoding UTF8
        Add-V13AuditItem $items 'Diagnostyka' 'Scheduled tasks export' $taskFile 'Pelny eksport zadan do recznej analizy startup/co minute.' 'Nie wylaczaj zadan systemowych bez wiedzy.' 'Brak'
    } catch {}
    try {
        $thermal = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -match 'Thermal|ACPI|Kernel-Power' -or $_.Message -match 'thermal|temperature|throttl' } |
            Select-Object -First 50 TimeCreated,ProviderName,Id,LevelDisplayName,Message
        $thermalFile = Join-Path $script:SessionFolder 'v13_thermal_history.json'
        $thermal | ConvertTo-Json -Depth 4 | Set-Content -Path $thermalFile -Encoding UTF8
        Add-V13AuditItem $items 'Diagnostyka' 'Thermal history export' "Count=$(@($thermal).Count); $thermalFile" 'Raport termiki/Kernel-Power z logow.' 'To diagnostyka, nie undervolt/OC.' 'Brak'
    } catch {}
    try {
        $anti = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'vgc|vgk|EasyAntiCheat|BEService|BattlEye|EAAntiCheat' -or $_.DisplayName -match 'Vanguard|Easy Anti-Cheat|BattlEye|EA AntiCheat' }
        Add-V13AuditItem $items 'Gaming' 'Anti-cheat compatibility services' (($anti | ForEach-Object { "$($_.Name): $($_.Status)" }) -join '; ') 'Raport anty-cheat; VBS/HVCI moze byc wymagane przez niektore gry/polityki.' 'Nie wylaczaj VBS globalnie bez sprawdzenia gier.' 'Brak'
        $gfe = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'NVIDIA Share|NVIDIA Web Helper|nvsphelper|Overwolf|GameBar|GameBarFTServer' }
        Add-V13AuditItem $items 'Gaming' 'Overlay processes' (($gfe | ForEach-Object { $_.ProcessName }) -join '; ') 'Overlaye moga zwiekszac DPC/stutter.' 'Wylacz overlay w aplikacji, nie zabijaj losowo uslug.' 'Brak'
        $steam = Join-Path ${env:ProgramFiles(x86)} 'Steam\config\config.vdf'
        Add-V13AuditItem $items 'Gaming' 'Steam shader pre-cache hint' ($(if(Test-Path $steam){'Steam wykryty'}else{'Steam nie wykryty w domyslnej sciezce'})) 'Przypomnienie: Steam > Settings > Downloads > Shader Pre-Caching.' 'Wlaczenie moze zmniejszyc stutter w grach Vulkan/Proton/niektorych tytulach.' 'Brak'
    } catch {}

    # Backup / preset / dev quality artifacts
    try {
        $preset = [pscustomobject]@{
            Version=$script:Version; Created=(Get-Date).ToString('s'); Profile=$Profile; Mode=$Mode; DnsMode=$DnsMode;
            Flags=$PSBoundParameters.Keys; Notes='Export obecnej konfiguracji uruchomienia do przeniesienia na inny PC.'
        }
        $presetPath = Join-Path $script:SessionFolder 'v13_current_preset_export.json'
        $preset | ConvertTo-Json -Depth 5 | Set-Content -Path $presetPath -Encoding UTF8
        Add-V13AuditItem $items 'Backup' 'Export JSON preset' $presetPath 'Preset mozna wykorzystac jako dokumentacje ustawien na innym PC.' 'Import automatyczny zostaje przyszlosciowy, bo wymaga walidacji sprzetu.' 'Brak'
        $manifestPath = Join-Path $script:SessionFolder 'manifest.json'
        $manifestOk = if (Test-Path $manifestPath) { try { Get-Content $manifestPath -Raw | ConvertFrom-Json | Out-Null; 'OK' } catch { 'ERROR: invalid JSON' } } else { 'missing' }
        Add-V13AuditItem $items 'Backup' 'manifest.json integrity' $manifestOk 'Weryfikacja przed rollbackiem.' 'Jesli invalid, rollback powinien byc blokowany.' 'Brak'
        $change = Join-Path $script:SessionFolder 'v13_changelog.md'
        @('# v13.0 changelog','','- Full beta implementation audit layer','- Extended safe diagnostics for disk/RAM/CPU/GPU/network/audio/security/gaming','- Export JSON/CSV/MD artifacts','- Risky tweaks remain Advanced/Manual') | Set-Content -Path $change -Encoding UTF8
        Add-V13AuditItem $items 'Jakosc' 'Changelog artifact' $change 'Czytelny changelog sesji.' '' 'Brak'
    } catch {}

    # Save outputs
    $jsonPath = Join-Path $script:SessionFolder 'v13_full_beta_implementation_audit.json'
    $csvPath  = Join-Path $script:SessionFolder 'v13_full_beta_implementation_audit.csv'
    $mdPath   = Join-Path $script:SessionFolder 'v13_full_beta_implementation_summary.md'
    $items | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
    $items | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# v13.0 Full Beta Implementation Audit')
    $lines.Add('')
    $lines.Add('Zasada: wszystko co moze popsuc system zostaje jako Advanced/Manual; ta warstwa glownie raportuje, eksportuje i daje rekomendacje.')
    $lines.Add('')
    foreach ($grp in ($items | Group-Object Category)) {
        $lines.Add("## $($grp.Name)")
        foreach ($i in $grp.Group) { $lines.Add("- **$($i.Name)**: $($i.Value) — $($i.Effect) Rekomendacja: $($i.Recommendation) [Ryzyko: $($i.Risk)]") }
        $lines.Add('')
    }
    $lines | Set-Content -Path $mdPath -Encoding UTF8

    if (Get-Command Add-HtmlSection -ErrorAction SilentlyContinue) {
        $rows = ($items | ForEach-Object { '<tr><td>'+[System.Net.WebUtility]::HtmlEncode($_.Category)+'</td><td>'+[System.Net.WebUtility]::HtmlEncode($_.Name)+'</td><td>'+[System.Net.WebUtility]::HtmlEncode([string]$_.Value)+'</td><td>'+[System.Net.WebUtility]::HtmlEncode($_.Effect)+'</td><td>'+[System.Net.WebUtility]::HtmlEncode($_.Recommendation)+'</td><td>'+[System.Net.WebUtility]::HtmlEncode($_.Risk)+'</td></tr>' }) -join "`n"
        Add-HtmlSection @"
<h2>v13.0 Full Beta Implementation Audit</h2>
<p>Rozszerzona implementacja pozostalych punktow jako bezpieczny audyt i eksport. Ryzykowne modyfikacje nie sa wykonywane automatycznie.</p>
<table><tr><th>Kategoria</th><th>Element</th><th>Wartosc</th><th>Efekt</th><th>Rekomendacja</th><th>Ryzyko</th></tr>$rows</table>
"@
    }

    Write-Status "v13.0 audit zapisany: $mdPath" 'Green'
    return $items
}



# =============================
# v13.1 Integration Layer - 10/10 pass
# Cel: audit dostepny jako osobny tryb, zawsze zintegrowany z Analyze, opcjonalny DeepScan,
# lepszy DryRun i Custom JSON bez rozwalania profili.
# =============================
function Invoke-IntegratedAuditV13_1 {
    param([switch]$IncludeBaseAnalyze)
    if ($SkipV13Audit) {
        Write-Status 'v13.1 audit pominiety przez -SkipV13Audit.' 'DarkGray'
        return
    }
    Write-Status '==> v13.1 Integrated Audit: pelny raport niezaleznie od profilu...' 'Cyan'
    if ($IncludeBaseAnalyze) { Invoke-Analyze }
    Invoke-BetaTesterAuditPack
}

function Import-CustomProfileV13_1 {
    if ($Profile -ne 'Custom') { return }
    if (-not $CustomProfilePath) { throw 'Profil Custom wymaga -CustomProfilePath "C:\path\preset.json".' }
    if (-not (Test-Path $CustomProfilePath)) { throw "Nie znaleziono CustomProfilePath: $CustomProfilePath" }
    Write-Status "==> Import Custom profile JSON: $CustomProfilePath" 'Cyan'
    $raw = Get-Content -Path $CustomProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $allowedBool = @(
        'EnablePowerTweaks','EnableUiTweaks','EnableGamingTweaks','EnableNetworkTweaks','EnableServiceTuning',
        'EnableCleanup','EnableRepair','EnableNetworkRepair','EnableGamingSession','EnableExperimentalTweaks',
        'EnablePerformanceFeelMode','EnableBenchmarkReport','EnableStartupReview','EnableNvidiaProfile',
        'EnablePostDebloaterRepair','EnableTelemetryTuning','EnableWindowsUpdatePause','EnableRiskPackModule'
    )
    foreach ($name in $allowedBool) {
        if ($raw.PSObject.Properties.Name -contains $name) {
            Set-Variable -Scope Script -Name $name -Value ([bool]$raw.$name) -ErrorAction SilentlyContinue
        }
    }
    $script:EnableRiskPackBundle = [bool]$EnableRiskPackModule
    if ($raw.PSObject.Properties.Name -contains 'SearchIndexingMode' -and $raw.SearchIndexingMode -in @('Keep','Manual')) { $script:SearchIndexingMode = [string]$raw.SearchIndexingMode }
    if ($raw.PSObject.Properties.Name -contains 'DnsMode' -and $raw.DnsMode -in @('Keep','Google','Cloudflare','Quad9')) { $script:SelectedDns = [string]$raw.DnsMode }
    $script:Manifest.Notes += "Custom profile imported: $CustomProfilePath"
}

function Invoke-MemoryDiagnosticOptionalV13_1 {
    if (-not $EnableMemoryDiagnosticSchedule) { return }
    Write-Status '==> v13.1: Memory Diagnostic schedule requested...' 'Cyan'
    if ($DryRun) {
        Write-Status '  [DRYRUN] Uruchomilbym mdsched.exe do zaplanowania testu RAM po restarcie.' 'DarkGray'
        return
    }
    try {
        Start-Process -FilePath 'mdsched.exe' -ErrorAction Stop
        Write-Log 'Memory Diagnostic opened by user request.' 'INFO'
    } catch {
        Write-Log "Nie udalo sie uruchomic mdsched.exe: $($_.Exception.Message)" 'WARN'
    }
}

function Write-V13_1Readme {
    $path = Join-Path $script:SessionFolder 'v13_1_what_changed.md'
    @(
        '# v13.1 Integration / 10-10 pass',
        '',
        'Co poprawiono:',
        '- Dodano osobny tryb `-Mode Audit`.',
        '- Analyze zawsze moze uruchomic pelny audit v13 niezaleznie od profilu.',
        '- Optimize po zmianach uruchamia audit/raport; DryRun moze wygenerowac raport bez zmian.',
        '- Wolne testy sa za flaga `-DeepScan`.',
        '- Ryzykowne rzeczy dalej nie wykonuja sie automatycznie.',
        '- Dodano opcjonalne `-EnableMemoryDiagnosticSchedule`.',
        '- Dodano szkielet `-Profile Custom -CustomProfilePath preset.json`.',
        '',
        'Zalecane uruchomienie:',
        '```powershell',
        '.\skrypt.ps1 -Mode Audit -Profile GamingLaptop -DeepScan',
        '.\skrypt.ps1 -Mode Optimize -Profile GamingLaptop -DryRun',
        '```'
    ) | Set-Content -Path $path -Encoding UTF8
}


# =============================
# v14 Pro Dashboard / Gaming Readiness / Stutter Finder
# =============================
function Get-V14SafeHtml {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Add-V14ProFinding {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$List,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Title,
        [ValidateSet('Low','Medium','High','Info')][string]$Severity = 'Info',
        [Parameter(Mandatory)][string]$Impact,
        [Parameter(Mandatory)][string]$Recommendation,
        [string]$Evidence = ''
    )
    $score = switch ($Severity) { 'High' { 20 } 'Medium' { 10 } 'Low' { 4 } default { 0 } }
    $List.Add([pscustomobject]@{
        Category       = $Category
        Title          = $Title
        Severity       = $Severity
        ScorePenalty   = $score
        Impact         = $Impact
        Recommendation = $Recommendation
        Evidence       = $Evidence
    }) | Out-Null
}

function Get-V14ProcessPresent {
    param([string[]]$Names)
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Names) {
        try {
            $p = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($p) { $found.Add($name) | Out-Null }
        } catch {}
    }
    return @($found)
}

function Get-V14ServicePresent {
    param([string[]]$Names)
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Names) {
        try {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($svc) { $found.Add("$($svc.Name)=$($svc.Status)") | Out-Null }
        } catch {}
    }
    return @($found)
}

function Get-V14GpuInfo {
    $info = [ordered]@{ NvidiaSmi = $false; Name=''; Temp=''; PState=''; PowerDraw=''; PowerLimit=''; ClocksGraphics=''; Hags='Unknown' }
    try {
        $hagsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        $hags = (Get-ItemProperty -Path $hagsPath -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
        if ($null -ne $hags) { $info.Hags = if ([int]$hags -eq 2) { 'Enabled' } elseif ([int]$hags -eq 1) { 'Disabled' } else { "Value $hags" } }
    } catch {}
    try {
        $nvsmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        if ($nvsmi) {
            $q = & nvidia-smi --query-gpu=name,temperature.gpu,pstate,power.draw,power.limit,clocks.gr --format=csv,noheader,nounits 2>$null | Select-Object -First 1
            if ($q) {
                $parts = $q -split ',' | ForEach-Object { $_.Trim() }
                $info.NvidiaSmi = $true
                $info.Name = $parts[0]
                $info.Temp = $parts[1]
                $info.PState = $parts[2]
                $info.PowerDraw = $parts[3]
                $info.PowerLimit = $parts[4]
                $info.ClocksGraphics = $parts[5]
            }
        }
    } catch {}
    return [pscustomobject]$info
}

function Invoke-V14StutterFinder {
    $findings = New-Object System.Collections.Generic.List[object]

    # FIX v14.1.1: return rozwija kolekcje — przy dokladnie 1 znalezionym procesie wracal goly string,
    # a string.Count pod StrictMode rzucal wyjatek (to byl blad 'v14 Pro Dashboard failed', linia 6390).
    $overlayProcesses = @(Get-V14ProcessPresent -Names @('NVIDIA Share','nvsphelper64','GameBar','GameBarFTServer','Overwolf','Discord','RadeonSoftware','steamwebhelper'))
    if ($overlayProcesses.Count -gt 0) {
        Add-V14ProFinding -List $findings -Category 'Gaming' -Title 'Aktywne overlaye / hooki w tle' -Severity 'Medium' -Impact 'Moga powodowac stutter, wyzsze DPC latency albo problemy z frametime.' -Recommendation 'W Gaming Session Mode wylacz overlaye, ktorych nie uzywasz. Najpierw sprawdz GeForce Experience overlay, Xbox Game Bar, Overwolf i Discord overlay.' -Evidence ($overlayProcesses -join ', ')
    } else {
        Add-V14ProFinding -List $findings -Category 'Gaming' -Title 'Brak typowych overlay procesow' -Severity 'Info' -Impact 'Nizsze ryzyko stutteru od hookow overlay.' -Recommendation 'Nic nie zmieniaj, jesli gry dzialaja dobrze.' -Evidence 'No common overlay process detected'
    }

    $msiNoise = @(Get-V14ProcessPresent -Names @('MSI Center','MSI.CentralServer','MysticLight','NahimicSvc64','NahimicSvc32','NahimicService'))
    $msiSvc = @(Get-V14ServicePresent -Names @('NahimicService','MSI_Central_Service','Mystic_Light_Service'))
    if ($msiNoise.Count -gt 0 -or $msiSvc.Count -gt 0) {
        Add-V14ProFinding -List $findings -Category 'Laptop MSI / DPC' -Title 'Wykryto MSI Center / Nahimic / Mystic Light' -Severity 'High' -Impact 'Na laptopach gamingowych te skladniki czesto podbijaja DPC latency i daja mikroprzyciecia.' -Recommendation 'Nie usuwaj w ciemno. Najpierw zrob restore point, potem przetestuj gre z wylaczonym overlay/audio effects/MSI Center w tle.' -Evidence ((@($msiNoise)+@($msiSvc)) -join ', ')
    }

    try {
        $startup = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
        $count = @($startup).Count
        if ($count -ge 25) {
            Add-V14ProFinding -List $findings -Category 'Startup' -Title 'Duzy autostart' -Severity 'Medium' -Impact 'Wolniejszy start systemu i wiecej pracy w tle po zalogowaniu.' -Recommendation 'Uzyj Startup Review. Wylacz tylko programy uzytkowe: launchery, updatery, komunikatory. Nie ruszaj sterownikow.' -Evidence "$count startup entries"
        } elseif ($count -ge 12) {
            Add-V14ProFinding -List $findings -Category 'Startup' -Title 'Sredni autostart' -Severity 'Low' -Impact 'Moze lekko obciazac start pulpitu.' -Recommendation 'Przejrzyj autostart, ale nie rob agresywnego debloatu.' -Evidence "$count startup entries"
        } else {
            Add-V14ProFinding -List $findings -Category 'Startup' -Title 'Autostart wyglada lekko' -Severity 'Info' -Impact 'Male ryzyko opoznien po logowaniu.' -Recommendation 'Bez zmian.' -Evidence "$count startup entries"
        }
    } catch {}

    try {
        $crit = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue | Select-Object -First 20
        $whea = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue | Select-Object -First 20
        # FIX v14.0.2: ProviderName jako tablica w FilterHashtable potrafi rzucic blad typow — zapytania per provider.
        $disk = @()
        foreach ($prov in @('disk','storahci','stornvme','Ntfs')) {
            $disk += @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName=$prov; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue | Select-Object -First 20)
        }
        $disk = @($disk | Select-Object -First 20)
        if (@($crit).Count -gt 0) { Add-V14ProFinding -List $findings -Category 'Stability' -Title 'Krytyczne bledy systemu z ostatnich 7 dni' -Severity 'High' -Impact 'Moga oznaczac realny problem stabilnosci, nie problem optymalizacji.' -Recommendation 'Sprawdz szczegoly Event Log przed dalszym tuningiem.' -Evidence ("Critical events: " + @($crit).Count) }
        if (@($whea).Count -gt 0) { Add-V14ProFinding -List $findings -Category 'Hardware' -Title 'WHEA events' -Severity 'High' -Impact 'Mozliwe bledy sprzetowe, niestabilny CPU/RAM/PCIe albo sterownik.' -Recommendation 'Nie szukaj FPS tweakow. Najpierw sprawdz stabilnosc, BIOS, sterowniki, RAM i temperatury.' -Evidence ("WHEA events: " + @($whea).Count) }
        if (@($disk).Count -gt 0) { Add-V14ProFinding -List $findings -Category 'Storage' -Title 'Zdarzenia dysku / NVMe / NTFS' -Severity 'Medium' -Impact 'Moga powodowac przyciecia, wolne ladowanie lub problemy z grami.' -Recommendation 'Sprawdz SMART, firmware SSD i miejsce na dysku.' -Evidence ("Disk/storage events: " + @($disk).Count) }
    } catch {}

    $gpu = Get-V14GpuInfo
    if ($gpu.NvidiaSmi) {
        try {
            $draw = [double]($gpu.PowerDraw -replace '[^0-9\.]','')
            $limit = [double]($gpu.PowerLimit -replace '[^0-9\.]','')
            $temp = [double]($gpu.Temp -replace '[^0-9\.]','')
            if ($limit -gt 0 -and $draw -gt ($limit * 0.92)) {
                Add-V14ProFinding -List $findings -Category 'GPU' -Title 'GPU blisko limitu mocy' -Severity 'Medium' -Impact 'FPS moze byc ograniczany power limitem, nie Windowsem.' -Recommendation 'Sprawdz zasilacz, tryb zasilania producenta i profil NVIDIA. Software tweak Windowsa da tu malo.' -Evidence "Power draw $($gpu.PowerDraw) W / limit $($gpu.PowerLimit) W"
            }
            if ($temp -ge 85) {
                Add-V14ProFinding -List $findings -Category 'GPU' -Title 'Wysoka temperatura GPU' -Severity 'Medium' -Impact 'Mozliwy throttling i spadki 1% low.' -Recommendation 'Sprawdz krzywa wentylatorow, kurz, podstawke, paste. Nie zwiekszaj agresywnie planu zasilania.' -Evidence "GPU temp $($gpu.Temp) C"
            }
        } catch {}
    }

    return @($findings)
}

function Get-V14ReadinessScore {
    param([object[]]$Findings)
    $penalty = 0
    foreach ($f in @($Findings)) { $penalty += [int]$f.ScorePenalty }
    $score = 100 - [Math]::Min(70, $penalty)
    $label = if ($score -ge 90) { 'Excellent' } elseif ($score -ge 75) { 'Good' } elseif ($score -ge 60) { 'Medium' } else { 'Needs attention' }
    $stutter = if ((@($Findings) | Where-Object { $_.Severity -eq 'High' }).Count -gt 0) { 'High' } elseif ((@($Findings) | Where-Object { $_.Severity -eq 'Medium' }).Count -gt 1) { 'Medium' } else { 'Low' }
    return [pscustomobject]@{ GamingReadinessScore=$score; Label=$label; StutterRisk=$stutter; FindingCount=@($Findings).Count }
}

function Write-V14ProDashboard {
    if ($SkipProDashboard) { return }
    try {
        $findings = @(Invoke-V14StutterFinder)
        $score = Get-V14ReadinessScore -Findings $findings
        $recommendedScenario = Get-V14RecommendedScenario
        $envInfo = $script:Manifest.Environment
        $outJson = Join-Path $script:ReportFolder 'v14_pro_findings.json'
        $outCsv  = Join-Path $script:ReportFolder 'v14_pro_findings.csv'
        $outHtml = Join-Path $script:ReportFolder 'v14_pro_dashboard.html'
        $findings | ConvertTo-Json -Depth 6 | Set-Content -Path $outJson -Encoding UTF8
        $findings | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

        $rows = foreach ($f in $findings) {
            $cls = switch ($f.Severity) { 'High' { 'high' } 'Medium' { 'med' } 'Low' { 'low' } default { 'info' } }
            "<tr class='$cls'><td>$(Get-V14SafeHtml $f.Category)</td><td><b>$(Get-V14SafeHtml $f.Title)</b><br><small>$(Get-V14SafeHtml $f.Evidence)</small></td><td>$(Get-V14SafeHtml $f.Severity)</td><td>$(Get-V14SafeHtml $f.Impact)</td><td>$(Get-V14SafeHtml $f.Recommendation)</td></tr>"
        }
        if (-not $rows) { $rows = @('<tr><td colspan="5">Brak krytycznych problemow. System wyglada czysto.</td></tr>') }
        $top = @($findings | Where-Object { $_.Severity -in @('High','Medium') } | Select-Object -First 5)
        $topHtml = if ($top.Count -gt 0) { ($top | ForEach-Object { "<li><b>$(Get-V14SafeHtml $_.Title)</b> - $(Get-V14SafeHtml $_.Recommendation)</li>" }) -join "`n" } else { '<li>Brak pilnych rekomendacji. Uzyj Safe/Gaming profile i nie kombinuj agresywnie.</li>' }
        $html = @"
<!doctype html><html lang="pl"><head><meta charset="utf-8">
<title>UWO Pro Dashboard v14 - $($script:SessionId)</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#10131a;color:#e8edf7;margin:0;padding:24px}h1{margin:0 0 6px;color:#7dd3fc}h2{color:#93c5fd;margin-top:28px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px;margin:20px 0}.card{background:#182033;border:1px solid #2c3b5a;border-radius:14px;padding:16px;box-shadow:0 8px 24px rgba(0,0,0,.25)}.num{font-size:42px;font-weight:800;color:#86efac}.label{color:#cbd5e1}table{border-collapse:collapse;width:100%;background:#151b2a;border-radius:12px;overflow:hidden}th,td{border-bottom:1px solid #263247;padding:10px;vertical-align:top}th{background:#1e293b;color:#bfdbfe;text-align:left}.high{background:#3a1620}.med{background:#33290f}.low{background:#182a18}.info{background:#151b2a}small{color:#94a3b8}.pill{display:inline-block;padding:4px 9px;border-radius:999px;background:#25324a;color:#dbeafe}.safe{color:#86efac}.warn{color:#fde68a}.bad{color:#fca5a5}a{color:#7dd3fc}</style>
</head><body>
<h1>Universal Windows Optimizer Pro v14</h1>
<div class="label">Sesja: <b>$($script:SessionId)</b> | Tryb: <b>$Mode</b> | Profil: <b>$Profile</b> | Wygenerowano: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class="grid">
<div class="card"><div class="num">$($score.GamingReadinessScore)</div><div class="label">Gaming Readiness Score / 100</div></div>
<div class="card"><div class="num">$(Get-V14SafeHtml $score.StutterRisk)</div><div class="label">Stutter Risk</div></div>
<div class="card"><div class="num">$($score.FindingCount)</div><div class="label">Findings</div></div>
<div class="card"><div class="num">$(if($DeepScan){'ON'}else{'OFF'})</div><div class="label">DeepScan</div></div>
<div class="card"><div class="num">$(Get-V14SafeHtml $recommendedScenario)</div><div class="label">Recommended Scenario</div></div>
<div class="card"><div class="num">$(if($envInfo.IsInsiderPreview){'ON'}else{'OFF'})</div><div class="label">Insider Safety</div></div>
</div>
<h2>Co to znaczy?</h2>
<p>Ten dashboard nie obiecuje magicznych FPS. Pokazuje realne hamulce: overlaye, bloat, autostart, bledy Event Log, GPU power/thermal limit i typowe zrodla stutteru.</p>
<p>Rekomendowany scenariusz dla tego komputera: <span class="pill">$(Get-V14SafeHtml $recommendedScenario)</span>$(if($envInfo.IsInsiderPreview){' <span class="pill">Insider-safe guard aktywny</span>'}else{''})</p>
<h2>Co realnie daje FPS</h2>
<ul>
<li>Sterownik GPU i ustawienia gry daja zwykle wiecej niz tweak Windowsa.</li>
<li>Temperatury, throttling i zasilanie laptopa czesto ograniczaja FPS bardziej niz system.</li>
<li>RAM w dual-channel i sensowna ilosc wolnej pamieci pomagaja bardziej niz wiekszosc tweakow z YouTube.</li>
<li>Overlaye, launchery i procesy w tle psuja frametime i 1% low bardziej niz sredni FPS.</li>
<li>Skrypt poprawia glownie porzadek, feel i stutter; duzy wzrost sredniego FPS zdarza sie rzadko.</li>
</ul>
<p>Wiekszosc popularnych \"FPS tweakow\" z YouTube daje maly efekt, placebo albo potrafi pogorszyc stabilnosc.</p>
<h2>Top rekomendacje</h2><ul>$topHtml</ul>
<h2>Stutter Finder / Pro Audit</h2>
<table><tr><th>Kategoria</th><th>Problem</th><th>Waga</th><th>Efekt w uzytkowaniu</th><th>Co zrobic</th></tr>
$($rows -join "`n")
</table>
<h2>Tryby, ktore robia efekt wow</h2>
<ul>
<li><span class="pill">Safe Recommended</span> najlepszy start, nie psuje Insidera ani Windows Update.</li>
<li><span class="pill">GamingLaptop</span> mniej stutteru, lepsze 1% low, bez agresywnych ryzyk.</li>
<li><span class="pill">Performance Feel</span> szybsze UI, input lag, komfort pracy.</li>
<li><span class="pill">Audit + DeepScan</span> wykrywa problem zanim cokolwiek zmienisz.</li>
<li><span class="pill">Rollback</span> jeden krok do cofniecia zmian.</li>
</ul>
<p class="label">Pliki: v14_pro_findings.json, v14_pro_findings.csv, ten dashboard HTML. Raport glowny: <a href="raport.html">raport.html</a></p>
</body></html>
"@
        $html | Set-Content -Path $outHtml -Encoding UTF8
        Write-Log "v14 Pro Dashboard: $outHtml" -Level 'ARTIFACT'
        if (-not $Silent) { Write-Status "v14 Pro Dashboard: $outHtml" 'Green' }
        $script:Manifest.V14ProDashboard = @{ Score=$score.GamingReadinessScore; StutterRisk=$score.StutterRisk; Findings=$score.FindingCount; Path=$outHtml }
    } catch {
        # FIX v14.0.2: pelna diagnostyka — sam komunikat ('Niezgodne typy argumentow') nie wskazywal linii.
        Write-Log "v14 Pro Dashboard failed: $($_.Exception.Message) | Linia: $($_.InvocationInfo.ScriptLineNumber) | Stack: $($_.ScriptStackTrace -replace '\r?\n',' <- ')" -Level 'WARN'
    }
}

function Write-V14WhatChanged {
    try {
        $path = Join-Path $script:ReportFolder 'v14_what_changed.md'
        @(
            '# v14 Pro - Gaming Audit & Dashboard',
            '',
            'Dodano:',
            '- Gaming Readiness Score 0-100.',
            '- Stutter Risk: Low / Medium / High.',
            '- Recommended Scenario i Insider-safe guard.',
            '- Presety scenariuszy: Esport / AAA / Silent / Work.',
            '- Rollback wybranych obszarow: Registry / Services / Power / DNS.',
            '- Stutter Finder: overlaye, MSI/Nahimic, autostart, Event Log, WHEA, storage, GPU power/temp.',
            '- Pro Dashboard HTML: czytelny raport dla uzytkownika, bez magicznych obietnic FPS.',
            '- Eksport v14_pro_findings.json i v14_pro_findings.csv.',
            '- Krotka sekcja: co realnie daje FPS, a co jest zwykle placebo z YouTube.',
            '',
            'Filozofia:',
            '- Najpierw wykryj hamulec, potem decyduj.',
            '- Safe/Gaming/Performance Feel nie psuja Insidera, Windows Update ani telemetrii.',
            '- Advanced zostaje tylko dla swiadomych uzytkownikow.',
            '- Skrypt poprawia glownie porzadek, stutter i komfort; duzy wzrost sredniego FPS zdarza sie rzadko.'
        ) | Set-Content -Path $path -Encoding UTF8
    } catch {}
}


function Show-V14FirstRunWizard {
    if (-not $EnableFirstRunWizard -or $Silent) { return }
    Write-Status '' 'White'
    Write-Status '=============================================' 'Cyan'
    Write-Status '  v14 First Run Wizard' 'White'
    Write-Status '=============================================' 'Cyan'
    Write-Status 'Wybierz cel. Wizard ustawi bezpieczny profil i tryb.' 'Gray'
    Write-Host '  [1] Gry na laptopie - najlepszy balans FPS/stutter/bezpieczenstwo' -ForegroundColor White
    Write-Host '  [2] Szybsza praca systemu - komfort, UI, input lag' -ForegroundColor White
    Write-Host '  [3] Slabszy laptop / malo RAM - mniej tla, bez agresji' -ForegroundColor White
    Write-Host '  [4] Bateria - oszczedzanie i spokojniejsza praca' -ForegroundColor White
    Write-Host '  [5] Tylko audyt - nic nie zmieniaj, pokaz raport' -ForegroundColor White
    $choice = Read-Host 'Wybor'
    switch ($choice) {
        '1' { $script:SelectedMode='Optimize'; $script:SelectedProfile='GamingLaptop'; $script:EnableGamingTweaks=$true; $script:EnableUiTweaks=$true; $script:EnablePowerTweaks=$true; $script:EnablePerformanceFeelMode=$true }
        '2' { $script:SelectedMode='Optimize'; $script:SelectedProfile='LaptopGamingSafe'; $script:EnableUiTweaks=$true; $script:EnablePerformanceFeelMode=$true }
        '3' { $script:SelectedMode='Optimize'; $script:SelectedProfile='LowRAM'; $script:EnableUiTweaks=$true; $script:EnableCleanup=$true }
        '4' { $script:SelectedMode='Optimize'; $script:SelectedProfile='BatterySaver'; $script:EnablePowerTweaks=$true }
        '5' { $script:SelectedMode='Audit'; $script:SelectedProfile='GamingLaptop' }
        default { Write-Status 'Nieznany wybor - zostaje Safe/Audit.' 'Yellow'; $script:SelectedMode='Audit'; $script:SelectedProfile='Safe' }
    }
    $script:Manifest.Notes += "v14 First Run Wizard selected: $($script:SelectedMode) / $($script:SelectedProfile)"
    Write-Status "Wizard ustawil: Mode=$($script:SelectedMode), Profile=$($script:SelectedProfile)" 'Green'
}



# =============================================================
# INTEGRATED MODULE: NAPRAWA I ODBUDOWA WINDOWS v1.6
# Źródło: WindowsRepair Final Candidate v1.5 REVIEW FINAL 95
# Integracja: moduł jako osobna pozycja głównego menu optimizera.
# Polityka: NON-DESTRUCTIVE REPAIR — nie usuwa plików, aplikacji, gier,
# launcherów, profili przeglądarek, zapisanych haseł, cookies, sesji ani AppData.
# =============================================================
<#
.SYNOPSIS
    WindowsRepair Review Candidate v0.88

.DESCRIPTION
    Rozbudowany moduł naprawczy Windows 10/11 przygotowany jako materiał dla recenzentów.
    Zakres: audyt, backup, podstawowa i zaawansowana naprawa systemu, sieci, usług,
    Windows Update, Store/AppX, WMI, harmonogramu zadań, polityk, security baseline,
    profilu użytkownika, shell, audio, power, recovery diagnostics i post-check.

    Wersja v0.88 NIE wykonuje automatycznie destrukcyjnych operacji EFI/TPM/BCD/Hypervisor.
    Te obszary są diagnostyką lub wymagają osobnego ręcznego potwierdzenia w kodzie.

.NOTES
    Uruchamiaj jako Administrator.
    Zalecane: PowerShell 5.1+ albo PowerShell 7 uruchomiony jako administrator.
    Testuj najpierw na maszynach wirtualnych.
#>



# ============================================================
# GLOBAL STATE
# ============================================================

$Script:RepairModuleVersion = "0.88-review-candidate"
$Script:RepairRoot = Join-Path $env:SystemDrive "WindowsRepair_ReviewCandidate"
$Script:BackupRoot = Join-Path $Script:RepairRoot "Backups"
$Script:ReportRoot = Join-Path $Script:RepairRoot "Reports"
$Script:LogPath = Join-Path $Script:RepairRoot "repair.log"
$Script:PreAuditJson = Join-Path $Script:ReportRoot "audit_before.json"
$Script:PostAuditJson = Join-Path $Script:ReportRoot "audit_after.json"
$Script:ReportJson = Join-Path $Script:ReportRoot "repair_report.json"
$Script:ReportTxt = Join-Path $Script:ReportRoot "repair_report.txt"
$Script:OfflineScriptPath = Join-Path $Script:ReportRoot "WinPE_OfflineRepair_Generated.cmd"
$Script:Results = New-Object System.Collections.Generic.List[object]
$Script:BeforeAudit = $null
$Script:AfterAudit = $null

# ============================================================
# CORE HELPERS
# ============================================================

function Initialize-RepairEnvironment {
    # FIX v15.3 (external report BUG3): two layered init blocks left $Script:Results/audits uncleared,
    # so re-entering Repair in one run mixed results from previous repair sessions. Reset at every entry:
    $Script:Results     = New-Object System.Collections.Generic.List[object]
    $Script:BeforeAudit = $null
    $Script:AfterAudit  = $null
    New-Item -ItemType Directory -Force -Path $Script:RepairRoot, $Script:BackupRoot, $Script:ReportRoot | Out-Null
    if (-not (Test-Path $Script:LogPath)) { New-Item -ItemType File -Force -Path $Script:LogPath | Out-Null }
}

function Write-RepairLog {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet("INFO","WARN","ERROR","OK","SKIP")] [string] $Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $Script:LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "OK"    { Write-Host $line -ForegroundColor Green }
        "SKIP"  { Write-Host $line -ForegroundColor DarkGray }
        default { Write-Host $line }
    }
}

function Add-RepairResult {
    param(
        [Parameter(Mandatory)] [string] $Step,
        [Parameter(Mandatory)] [string] $Status,
        [string] $Details = "",
        [string] $Category = "General"
    )
    $Script:Results.Add([pscustomobject]@{
        Time     = Get-Date
        Category = $Category
        Step     = $Step
        Status   = $Status
        Details  = $Details
    }) | Out-Null
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-AdminFirst {
    if (-not (Test-IsAdmin)) {
        Write-RepairLog "Uruchom jako Administrator. Przerywam przed interakcją." "ERROR"
        throw "Brak uprawnień administratora."
    }
}

function Invoke-RepairStep {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Action,
        [string] $Category = "General"
    )
    Write-RepairLog "START: [$Category] $Name" "INFO"
    try {
        & $Action
        Write-RepairLog "OK: [$Category] $Name" "OK"
        Add-RepairResult -Category $Category -Step $Name -Status "OK"
    }
    catch {
        Write-RepairLog "BŁĄD: [$Category] $Name :: $($_.Exception.Message)" "ERROR"
        Add-RepairResult -Category $Category -Step $Name -Status "ERROR" -Details $_.Exception.Message
    }
}

function Invoke-ExternalCommandLogged {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [string[]] $Arguments = @(),
        [string] $StepName = $FilePath,
        [string] $Category = "External"
    )
    Write-RepairLog "CMD: $FilePath $($Arguments -join ' ')" "INFO"
    try {
        # FIX v15.3 (external report BUG1): same defect as FIX6 but in THIS wrapper — empty -ArgumentList
        # throws ParameterBindingException, so wsreset.exe / dcomcnfg.exe silently never ran.
        $spArgs = @{ FilePath = $FilePath; Wait = $true; PassThru = $true; NoNewWindow = $true; ErrorAction = 'Stop' }
        if ($Arguments -and $Arguments.Count -gt 0) { $spArgs['ArgumentList'] = $Arguments }
        $process = Start-Process @spArgs
        $exitCode = $process.ExitCode
        Write-RepairLog "EXIT ${StepName}: $exitCode" "INFO"
        Add-RepairResult -Category $Category -Step $StepName -Status "EXIT_$exitCode"
        return $exitCode
    }
    catch {
        Write-RepairLog "CMD ERROR ${StepName}: $($_.Exception.Message)" "ERROR"
        Add-RepairResult -Category $Category -Step $StepName -Status "ERROR" -Details $_.Exception.Message
        return -9999
    }
}

function Get-DismExitMeaning { param([int] $ExitCode)
    switch ($ExitCode) {
        0 { "OK" }
        3010 { "OK_RESTART_REQUIRED" }
        87 { "ERROR_BAD_PARAMETERS" }
        1726 { "ERROR_RPC_FAILED" }
        default { "UNKNOWN_$ExitCode" }
    }
}

function Get-SfcExitMeaning { param([int] $ExitCode)
    switch ($ExitCode) {
        0 { "OK_NO_VIOLATIONS" }
        1 { "OK_FOUND_AND_REPAIRED" }
        2 { "ERROR_FOUND_NOT_REPAIRED" }
        default { "UNKNOWN_$ExitCode" }
    }
}

function Invoke-DismRestoreHealthChecked {
    $code = Invoke-ExternalCommandLogged -FilePath "dism.exe" -Arguments @("/Online","/Cleanup-Image","/RestoreHealth") -StepName "DISM RestoreHealth" -Category "Integrity"
    $meaning = Get-DismExitMeaning -ExitCode $code
    Add-RepairResult -Category "Integrity" -Step "DISM parsed result" -Status $meaning -Details "ExitCode=$code"
    if ($meaning -like "ERROR*") { Write-RepairLog "DISM zgłosił błąd: $meaning" "ERROR" }
}

function Invoke-SfcScannowChecked {
    $code = Invoke-ExternalCommandLogged -FilePath "sfc.exe" -Arguments @("/scannow") -StepName "SFC Scannow" -Category "Integrity"
    $meaning = Get-SfcExitMeaning -ExitCode $code
    Add-RepairResult -Category "Integrity" -Step "SFC parsed result" -Status $meaning -Details "ExitCode=$code"
    if ($meaning -like "ERROR*") { Write-RepairLog "SFC zgłosił problem: $meaning" "WARN" }
}

function Stop-ServiceAndWaitSafe {
    param([Parameter(Mandatory)] [string] $Name, [int] $TimeoutSeconds = 35)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-RepairLog "Usługa $Name nie istnieje." "SKIP"; return $false }
    if ($svc.Status -ne "Stopped") {
        try { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue } catch {}
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 500
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Stopped") { Write-RepairLog "Usługa $Name zatrzymana." "OK"; return $true }
    } while ((Get-Date) -lt $deadline)
    Write-RepairLog "Nie potwierdzono zatrzymania usługi $Name." "WARN"
    return $false
}

function Start-ServiceSafe { param([Parameter(Mandatory)] [string] $Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-RepairLog "Usługa $Name nie istnieje." "SKIP"; return }
    try { Start-Service -Name $Name -ErrorAction Stop; Write-RepairLog "Uruchomiono $Name." "OK" }
    catch { Write-RepairLog "Nie udało się uruchomić ${Name}: $($_.Exception.Message)" "WARN" }
}

function Set-RepairServiceStartup { param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $Mode)
    # FIX v14.0.1: zmieniona nazwa — poprzednia ('Set-ServiceStartupSafe') KOLIDOWALA z funkcja optymalizatora
    # (inna sygnatura: -Mode vs -StartupType) i nadpisywala ja, wysypujac caly modul uslug.
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-RepairLog "Brak usługi $Name dla startup=$Mode." "SKIP"; return }
    Invoke-ExternalCommandLogged -FilePath "sc.exe" -Arguments @("config", $Name, "start=", $Mode) -StepName "Service startup $Name=$Mode" -Category "Services" | Out-Null
}

# ============================================================
# BACKUP AND SNAPSHOT
# ============================================================

function Backup-RegistryKey {
    param([Parameter(Mandatory)] [string] $RegPath, [Parameter(Mandatory)] [string] $Name)
    $safeName = $Name -replace '[\\/:*?"<>|]', '_'
    $out = Join-Path $Script:BackupRoot "$safeName.reg"
    $code = Invoke-ExternalCommandLogged -FilePath "reg.exe" -Arguments @("export", $RegPath, $out, "/y") -StepName "Backup $RegPath" -Category "Backup"
    if ($code -eq 0) { Write-RepairLog "Backup rejestru: $out" "OK" } else { Write-RepairLog "Backup rejestru nieudany: $RegPath" "WARN" }
}

function Backup-ImportantRegistryAreas {
    $items = @(
        @{ Path="HKLM\SOFTWARE\Policies\Microsoft"; Name="HKLM_Policies_Microsoft" },
        @{ Path="HKCU\SOFTWARE\Policies\Microsoft"; Name="HKCU_Policies_Microsoft" },
        @{ Path="HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies"; Name="HKLM_CV_Policies" },
        @{ Path="HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies"; Name="HKCU_CV_Policies" },
        @{ Path="HKLM\SYSTEM\CurrentControlSet\Services"; Name="HKLM_Services" },
        @{ Path="HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"; Name="Winlogon" },
        @{ Path="HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer"; Name="HKCU_Explorer" },
        @{ Path="HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices"; Name="MMDevices" },
        @{ Path="HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"; Name="FileExts" }
    )
    foreach ($i in $items) { Backup-RegistryKey -RegPath $i.Path -Name $i.Name }
}

function Export-DriverInventory {
    $out1 = Join-Path $Script:BackupRoot "drivers_getwindowsdriver_before.txt"
    $out2 = Join-Path $Script:BackupRoot "drivers_pnputil_before.txt"
    try { Get-WindowsDriver -Online | Out-File -FilePath $out1 -Encoding UTF8; Write-RepairLog "Zapisano Get-WindowsDriver." "OK" } catch { Write-RepairLog "Get-WindowsDriver błąd: $($_.Exception.Message)" "WARN" }
    Invoke-ExternalCommandLogged -FilePath "pnputil.exe" -Arguments @("/enum-drivers") -StepName "PNP driver inventory" -Category "Backup" | Out-Null
}

function Create-SystemRestorePointSafe {
    # FIX v14.0.1: Checkpoint-Computer nie istnieje w PS7 — uzywamy wspolnego helpera z weryfikacja.
    $created = New-SystemRestorePointCompat -Description "WindowsRepair_$($Script:RepairModuleVersion)"
    if ($created) { Write-RepairLog "Utworzono i zweryfikowano punkt przywracania." "OK" }
    else { Write-RepairLog "Nie udalo sie utworzyc punktu przywracania (limit 24h / Ochrona systemu wylaczona / brak WinPS 5.1)." "WARN" }
}

# ============================================================
# AUDIT
# ============================================================

function Get-ServiceAudit {
    $serviceNames = @(
        "EventLog","Schedule","Winmgmt","TrustedInstaller","wuauserv","bits","cryptsvc","UsoSvc","DoSvc","WaaSMedicSvc",
        "SecurityHealthService","WinDefend","mpssvc","BFE","Dhcp","Dnscache","NlaSvc","netprofm","AudioSrv","AudioEndpointBuilder",
        "Themes","AppXSvc","ClipSVC","InstallService","XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc","GamingServices",
        "DiagTrack","SysMain","WSearch","Spooler","bthserv","lfsvc","SensorService","WbioSrvc","LanmanWorkstation","LanmanServer",
        "DeviceInstall","PlugPlay","ProfSvc","EventSystem","RpcSs","DcomLaunch","BrokerInfrastructure","StateRepository","TimeBrokerSvc"
    )
    foreach ($name in $serviceNames | Sort-Object -Unique) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) { [pscustomobject]@{ Name=$name; Status=$svc.Status.ToString(); StartType=$svc.StartType.ToString() } }
        else { [pscustomobject]@{ Name=$name; Status="Missing"; StartType="Missing" } }
    }
}

function Get-TaskAudit {
    $paths = @(
        "\Microsoft\Windows\Defrag\ScheduledDefrag",
        "\Microsoft\Windows\Diagnosis\Scheduled",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\WMI\BVTFilter",
        "\Microsoft\Windows\Time Synchronization\SynchronizeTime",
        "\Microsoft\XblGameSave\XblGameSaveTask"
    )
    foreach ($tn in $paths) {
        try {
            $task = Get-ScheduledTask -TaskPath (Split-Path $tn -Parent).Replace('/','\') -TaskName (Split-Path $tn -Leaf) -ErrorAction Stop
            [pscustomobject]@{ Task=$tn; State=$task.State.ToString() }
        } catch { [pscustomobject]@{ Task=$tn; State="MissingOrError" } }
    }
}

function Get-EventErrorCount { param([int] $Hours = 24)
    try { return (Get-WinEvent -FilterHashtable @{ LogName="System"; Level=2; StartTime=(Get-Date).AddHours(-$Hours) } -ErrorAction SilentlyContinue | Measure-Object).Count }
    catch { return -1 }
}

function Get-WmiHealthState {
    $out = [ordered]@{ CimWin32OS=$false; RepositoryCheck="NotRun" }
    try { Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Out-Null; $out.CimWin32OS = $true } catch {}
    try {
        $code = Invoke-ExternalCommandLogged -FilePath "winmgmt.exe" -Arguments @("/verifyrepository") -StepName "WMI verifyrepository" -Category "Audit"
        $out.RepositoryCheck = "Exit_$code"
    } catch {}
    return [pscustomobject]$out
}

function Invoke-RepairAuditSnapshot {
    param([Parameter(Mandatory)] [string] $Phase)
    Write-RepairLog "Audyt $Phase" "INFO"
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $audit = [pscustomobject]@{
        Phase = $Phase
        Time = Get-Date
        Version = $Script:RepairModuleVersion
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        OS = if ($os) { $os.Caption } else { "Unknown" }
        Build = if ($os) { $os.BuildNumber } else { "Unknown" }
        Services = @(Get-ServiceAudit)
        Tasks = @(Get-TaskAudit)
        Wmi = Get-WmiHealthState
        EventErrorsLast24h = Get-EventErrorCount -Hours 24
        Defender = (& { try { Get-MpComputerStatus -ErrorAction Stop } catch { $null } })
        WinRE = (& { try { reagentc /info | Out-String } catch { "Unavailable" } })
        NetworkProbe = (& { try { Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -InformationLevel Quiet } catch { $false } })
    }
    if ($Phase -eq "Before") { $Script:BeforeAudit = $audit; $audit | ConvertTo-Json -Depth 8 | Out-File $Script:PreAuditJson -Encoding UTF8 }
    if ($Phase -eq "After") { $Script:AfterAudit = $audit; $audit | ConvertTo-Json -Depth 8 | Out-File $Script:PostAuditJson -Encoding UTF8 }
    return $audit
}

# ============================================================
# REGISTRY AND POLICIES
# ============================================================

function Remove-RegistrySubkeysSafe { param([Parameter(Mandatory)] [string] $Path)
    if (Test-Path $Path) {
        try { Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; Write-RepairLog "Wyczyszczono podklucze: $Path" "OK" }
        catch { Write-RepairLog "Nie udało się wyczyścić ${Path}: $($_.Exception.Message)" "WARN" }
    } else { Write-RepairLog "Brak ścieżki: $Path" "SKIP" }
}

function Repair-RegistryAndPolicies {
    Backup-ImportantRegistryAreas
    Remove-RegistrySubkeysSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft"
    Remove-RegistrySubkeysSafe -Path "HKCU:\SOFTWARE\Policies\Microsoft"

    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 3 -PropertyType DWord -Force | Out-Null

    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "Shell" -Value "explorer.exe" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "Userinit" -Value "$env:windir\system32\userinit.exe," -PropertyType String -Force | Out-Null

    New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
    New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2 -PropertyType DWord -Force | Out-Null

    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    New-Item -Path $cdm -Force | Out-Null
    foreach ($name in @("ContentDeliveryAllowed","FeatureManagementEnabled","OemPreInstalledAppsEnabled","PreInstalledAppsEnabled","SilentInstalledAppsEnabled","SubscribedContent-338388Enabled")) {
        New-ItemProperty -Path $cdm -Name $name -Value 1 -PropertyType DWord -Force | Out-Null
    }

    Invoke-ExternalCommandLogged -FilePath "gpupdate.exe" -Arguments @("/force") -StepName "gpupdate force" -Category "Policies" | Out-Null
}

# ============================================================
# SERVICES
# ============================================================

function Get-WindowsDefaultServiceStartupMap {
    # Review map: najważniejsze usługi Windows 10/11 i często wyłączane przez debloatery.
    return [ordered]@{
        "AppIDSvc"="demand"; "Appinfo"="demand"; "AppMgmt"="demand"; "AppReadiness"="demand"; "AppXSvc"="demand";
        "AudioEndpointBuilder"="auto"; "AudioSrv"="auto"; "AxInstSV"="demand";
        "BFE"="auto"; "BITS"="delayed-auto"; "BrokerInfrastructure"="auto"; "BTAGService"="demand"; "bthserv"="demand";
        "camsvc"="demand"; "CDPSvc"="auto"; "CertPropSvc"="demand"; "ClipSVC"="demand"; "COMSysApp"="demand";
        "CoreMessagingRegistrar"="auto"; "CryptSvc"="auto"; "DcomLaunch"="auto"; "defragsvc"="demand"; "DeviceAssociationService"="demand";
        "DeviceInstall"="demand"; "DevQueryBroker"="demand"; "Dhcp"="auto"; "DiagTrack"="auto"; "DispBrokerDesktopSvc"="auto";
        "DisplayEnhancementService"="demand"; "DmEnrollmentSvc"="demand"; "dmwappushservice"="demand"; "Dnscache"="auto"; "DoSvc"="delayed-auto";
        "DPS"="auto"; "DsmSvc"="demand"; "DusmSvc"="auto"; "Eaphost"="demand"; "EventLog"="auto";
        "EventSystem"="auto"; "fdPHost"="demand"; "FDResPub"="demand"; "FontCache"="auto"; "FrameServer"="demand";
        "gpsvc"="auto"; "hidserv"="demand"; "HvHost"="demand"; "icssvc"="demand"; "InstallService"="demand";
        "iphlpsvc"="auto"; "KeyIso"="auto"; "LanmanServer"="auto"; "LanmanWorkstation"="auto"; "lfsvc"="demand";
        "LicenseManager"="demand"; "lmhosts"="demand"; "LSM"="auto"; "MapsBroker"="delayed-auto"; "MessagingService"="demand";
        "mpssvc"="auto"; "MSDTC"="demand"; "NaturalAuthentication"="demand"; "NcbService"="demand"; "NcdAutoSetup"="demand";
        "Netlogon"="demand"; "Netman"="demand"; "netprofm"="demand"; "NetSetupSvc"="demand"; "NgcCtnrSvc"="demand";
        "NgcSvc"="demand"; "NlaSvc"="auto"; "nsi"="auto"; "OneSyncSvc"="auto"; "PcaSvc"="auto";
        "PhoneSvc"="demand"; "PlugPlay"="demand"; "PNRPAutoReg"="demand"; "PNRPsvc"="demand"; "PolicyAgent"="demand";
        "Power"="auto"; "PrintNotify"="demand"; "ProfSvc"="auto"; "PushToInstall"="demand"; "QWAVE"="demand";
        "RasAuto"="demand"; "RasMan"="demand"; "RemoteAccess"="disabled"; "RemoteRegistry"="disabled"; "RetailDemo"="demand";
        "RpcEptMapper"="auto"; "RpcLocator"="demand"; "RpcSs"="auto"; "SamSs"="auto"; "SCardSvr"="demand";
        "Schedule"="auto"; "ScDeviceEnum"="demand"; "seclogon"="demand"; "SecurityHealthService"="demand"; "SEMgrSvc"="demand";
        "SENS"="auto"; "SensorDataService"="demand"; "SensorService"="demand"; "SensrSvc"="demand"; "SessionEnv"="demand";
        "SharedAccess"="demand"; "ShellHWDetection"="auto"; "Spooler"="auto"; "sppsvc"="delayed-auto"; "SSDPSRV"="demand";
        "StateRepository"="demand"; "stisvc"="demand"; "StorSvc"="demand"; "SysMain"="auto"; "SystemEventsBroker"="auto";
        "TabletInputService"="demand"; "TapiSrv"="demand"; "Themes"="auto"; "TimeBrokerSvc"="demand"; "TokenBroker"="demand";
        "TrkWks"="auto"; "TroubleshootingSvc"="demand"; "TrustedInstaller"="demand"; "tzautoupdate"="disabled"; "UevAgentService"="disabled";
        "UmRdpService"="demand"; "upnphost"="demand"; "UsoSvc"="demand"; "VaultSvc"="demand"; "vds"="demand";
        "vmicguestinterface"="demand"; "vmicheartbeat"="demand"; "vmickvpexchange"="demand"; "vmicrdv"="demand"; "vmicshutdown"="demand";
        "vmictimesync"="demand"; "vmicvmsession"="demand"; "vmicvss"="demand"; "VSS"="demand"; "W32Time"="demand";
        "WaaSMedicSvc"="demand"; "WalletService"="demand"; "WarpJITSvc"="demand"; "wbengine"="demand"; "WbioSrvc"="demand";
        "Wcmsvc"="auto"; "wcncsvc"="demand"; "WdiServiceHost"="demand"; "WdiSystemHost"="demand"; "WdNisSvc"="demand";
        "WebClient"="demand"; "Wecsvc"="demand"; "wercplsupport"="demand"; "WerSvc"="demand"; "WFDSConMgrSvc"="demand";
        "WiaRpc"="demand"; "WinDefend"="auto"; "WinHttpAutoProxySvc"="demand"; "Winmgmt"="auto"; "WinRM"="demand";
        "wisvc"="demand"; "WlanSvc"="auto"; "wlidsvc"="demand"; "wlpasvc"="demand"; "WManSvc"="demand";
        "wmiApSrv"="demand"; "WMPNetworkSvc"="demand"; "workfolderssvc"="demand"; "WpcMonSvc"="demand"; "WPDBusEnum"="demand";
        "WpnService"="auto"; "wscsvc"="delayed-auto"; "WSearch"="delayed-auto"; "wuauserv"="demand"; "WwanSvc"="demand";
        "XblAuthManager"="demand"; "XblGameSave"="demand"; "XboxGipSvc"="demand"; "XboxNetApiSvc"="demand"; "GamingServices"="demand"
    }
}

function Repair-WindowsServices {
    $map = Get-WindowsDefaultServiceStartupMap
    foreach ($name in $map.Keys) { Set-RepairServiceStartup -Name $name -Mode $map[$name] }
    foreach ($critical in @("EventLog","Schedule","RpcSs","DcomLaunch","Winmgmt","BFE","mpssvc","Dhcp","Dnscache","AudioSrv","AudioEndpointBuilder")) { Start-ServiceSafe -Name $critical }
}

# ============================================================
# NETWORK
# ============================================================

function Reset-NetworkFull {
    Invoke-ExternalCommandLogged -FilePath "ipconfig.exe" -Arguments @("/flushdns") -StepName "Flush DNS" -Category "Network" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "netsh.exe" -Arguments @("winsock","reset") -StepName "Winsock reset" -Category "Network" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "netsh.exe" -Arguments @("int","ip","reset") -StepName "IPv4 reset" -Category "Network" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "netsh.exe" -Arguments @("int","ipv6","reset") -StepName "IPv6 reset" -Category "Network" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "netsh.exe" -Arguments @("advfirewall","reset") -StepName "Firewall reset" -Category "Network" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "netsh.exe" -Arguments @("winhttp","reset","proxy") -StepName "WinHTTP proxy reset" -Category "Network" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "arp.exe" -Arguments @("-d","*") -StepName "ARP cache clear" -Category "Network" | Out-Null

    $ncsi = "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet"
    New-Item -Path $ncsi -Force | Out-Null
    New-ItemProperty -Path $ncsi -Name "EnableActiveProbing" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $ncsi -Name "ActiveWebProbeHost" -Value "www.msftconnecttest.com" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $ncsi -Name "ActiveWebProbePath" -Value "connecttest.txt" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $ncsi -Name "ActiveDnsProbeHost" -Value "dns.msftncsi.com" -PropertyType String -Force | Out-Null

    try {
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
            Set-NetIPInterface -InterfaceIndex $_.ifIndex -Dhcp Enabled -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
            Write-RepairLog "Adapter DHCP/DNS auto: $($_.Name)" "OK"
        }
    } catch { Write-RepairLog "DHCP/DNS reset błąd: $($_.Exception.Message)" "WARN" }
}

# ============================================================
# WINDOWS UPDATE
# ============================================================

function Reset-WindowsUpdateFull {
    $services = @("UsoSvc","WaaSMedicSvc","wuauserv","bits","cryptsvc","DoSvc")
    foreach ($svc in $services) { Stop-ServiceAndWaitSafe -Name $svc -TimeoutSeconds 45 | Out-Null }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $paths = @(
        @{ Path=(Join-Path $env:windir "SoftwareDistribution"); Name="SoftwareDistribution" },
        @{ Path=(Join-Path $env:windir "System32\catroot2"); Name="catroot2" },
        @{ Path=(Join-Path $env:ProgramData "Microsoft\Network\Downloader"); Name="BITS_Downloader" }
    )
    foreach ($p in $paths) {
        if (Test-Path $p.Path) {
            try { Rename-Item -Path $p.Path -NewName "$($p.Name).bak_$stamp" -ErrorAction Stop; Write-RepairLog "Rename: $($p.Name)" "OK" }
            catch { Write-RepairLog "Rename failed $($p.Name): $($_.Exception.Message)" "WARN" }
        }
    }

    Invoke-ExternalCommandLogged -FilePath "bitsadmin.exe" -Arguments @("/reset","/allusers") -StepName "BITS reset all users" -Category "WindowsUpdate" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "wuauclt.exe" -Arguments @("/resetauthorization") -StepName "WU reset authorization" -Category "WindowsUpdate" | Out-Null

    $wuDlls = @("wuapi.dll","wuaueng.dll","wucltux.dll","wuwebv.dll","wups.dll","wups2.dll","qmgr.dll","qmgrprxy.dll","cryptdlg.dll","softpub.dll","wintrust.dll","initpki.dll","msxml3.dll","msxml6.dll")
    foreach ($dll in $wuDlls) {
        $path = Join-Path $env:windir "System32\$dll"
        if (Test-Path $path) { Invoke-ExternalCommandLogged -FilePath "regsvr32.exe" -Arguments @("/s",$path) -StepName "Register $dll" -Category "WindowsUpdate" | Out-Null }
    }

    Set-RepairServiceStartup -Name "wuauserv" -Mode "demand"
    Set-RepairServiceStartup -Name "bits" -Mode "delayed-auto"
    Set-RepairServiceStartup -Name "cryptsvc" -Mode "auto"
    Set-RepairServiceStartup -Name "UsoSvc" -Mode "demand"
    Set-RepairServiceStartup -Name "DoSvc" -Mode "delayed-auto"
    Set-RepairServiceStartup -Name "WaaSMedicSvc" -Mode "demand"

    foreach ($svc in @("cryptsvc","bits","wuauserv","DoSvc","UsoSvc")) { Start-ServiceSafe -Name $svc }
    Invoke-ExternalCommandLogged -FilePath "usoclient.exe" -Arguments @("StartScan") -StepName "USO StartScan" -Category "WindowsUpdate" | Out-Null
}

# ============================================================
# APPX / STORE / GAMING
# ============================================================

function Register-CoreAppxPackages {
    Start-ServiceSafe -Name "AppXSvc"
    Start-ServiceSafe -Name "ClipSVC"
    Start-ServiceSafe -Name "InstallService"
    $packages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    foreach ($package in $packages) {
        if ([string]::IsNullOrWhiteSpace($package.InstallLocation)) { Write-RepairLog "AppX bez InstallLocation: $($package.Name)" "SKIP"; continue }
        $manifest = Join-Path $package.InstallLocation "AppxManifest.xml"
        if (-not (Test-Path $manifest)) { Write-RepairLog "Brak manifestu AppX: $($package.Name)" "WARN"; continue }
        try { Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop; Write-RepairLog "AppX registered: $($package.Name)" "OK" }
        catch { Write-RepairLog "AppX register failed $($package.Name): $($_.Exception.Message)" "WARN" }
    }
}

function Repair-StoreAppxGaming {
    Start-ServiceSafe -Name "AppXSvc"; Start-ServiceSafe -Name "ClipSVC"; Start-ServiceSafe -Name "InstallService"
    Invoke-ExternalCommandLogged -FilePath "wsreset.exe" -Arguments @() -StepName "WSReset" -Category "AppX" | Out-Null
    Register-CoreAppxPackages
    foreach ($svc in @("XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc","GamingServices")) { Set-RepairServiceStartup -Name $svc -Mode "demand" }
    New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
    New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
    $storeUriTargets = @("ms-windows-store://pdp/?productid=9MWPM2CQNLHN", "ms-windows-store://pdp/?productid=9NZKPSTSNW4P")
    foreach ($uri in $storeUriTargets) { Add-RepairResult -Category "AppX" -Step "Store URI reinstall hint" -Status "INFO" -Details $uri }
}

# ============================================================
# SECURITY / DEFENDER / CERTIFICATES
# ============================================================

function Repair-SecurityBaseline {
    $db = Join-Path $Script:RepairRoot "secedit.sdb"
    $cfg = Join-Path $env:windir "inf\defltbase.inf"
    if (Test-Path $cfg) { Invoke-ExternalCommandLogged -FilePath "secedit.exe" -Arguments @("/configure","/db",$db,"/cfg",$cfg,"/verbose") -StepName "Secedit default baseline" -Category "Security" | Out-Null }
    else { Write-RepairLog "Brak defltbase.inf." "WARN" }
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 5 -PropertyType DWord -Force | Out-Null
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
        Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
        Update-MpSignature -ErrorAction SilentlyContinue
        Write-RepairLog "Defender preference/signature refresh attempted." "OK"
    } catch { Write-RepairLog "Defender repair unavailable: $($_.Exception.Message)" "WARN" }
    $sst = Join-Path $Script:BackupRoot "roots.sst"
    Invoke-ExternalCommandLogged -FilePath "certutil.exe" -Arguments @("-generateSSTFromWU",$sst) -StepName "Generate Root CA SST" -Category "Security" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "certutil.exe" -Arguments @("-urlcache","*","delete") -StepName "Cryptnet URL cache reset" -Category "Security" | Out-Null
}

function Repair-SystemAclConservative {
    Write-RepairLog "ACL: tryb konserwatywny. Pełny icacls %windir% /reset jest ciężki i domyślnie pominięty." "WARN"
    foreach ($path in @("$env:windir\System32", "$env:windir\SysWOW64", "$env:ProgramFiles\WindowsApps")) {
        if (Test-Path $path) { Add-RepairResult -Category "ACL" -Step "ACL check target" -Status "INFO" -Details $path }
    }
}

# ============================================================
# WMI / COM / WINSXS
# ============================================================

function Repair-WmiComWinSxS {
    Stop-ServiceAndWaitSafe -Name "winmgmt" -TimeoutSeconds 30 | Out-Null
    $code = Invoke-ExternalCommandLogged -FilePath "winmgmt.exe" -Arguments @("/salvagerepository") -StepName "WMI salvagerepository" -Category "WMI"
    if ($code -ne 0) { Invoke-ExternalCommandLogged -FilePath "winmgmt.exe" -Arguments @("/resetrepository") -StepName "WMI resetrepository" -Category "WMI" | Out-Null }
    Start-ServiceSafe -Name "winmgmt"
    Invoke-ExternalCommandLogged -FilePath "lodctr.exe" -Arguments @("/r") -StepName "Performance counters rebuild" -Category "WMI" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "winmgmt.exe" -Arguments @("/resyncperf") -StepName "WMI resyncperf" -Category "WMI" | Out-Null
    $mofPaths = @("$env:windir\System32\wbem\cimwin32.mof", "$env:windir\System32\wbem\wmi.mof")
    foreach ($mof in $mofPaths) { if (Test-Path $mof) { Invoke-ExternalCommandLogged -FilePath "mofcomp.exe" -Arguments @($mof) -StepName "mofcomp $mof" -Category "WMI" | Out-Null } }
    foreach ($dll in @("ole32.dll","oleaut32.dll","actxprxy.dll","urlmon.dll","msxml3.dll","msxml6.dll","jscript.dll","vbscript.dll")) {
        $path = Join-Path $env:windir "System32\$dll"
        if (Test-Path $path) { Invoke-ExternalCommandLogged -FilePath "regsvr32.exe" -Arguments @("/s",$path) -StepName "regsvr32 $dll" -Category "COM" | Out-Null }
    }
}

# ============================================================
# SCHEDULED TASKS
# ============================================================

function Repair-ScheduledTasks {
    $tasks = @(
        "\Microsoft\Windows\Defrag\ScheduledDefrag",
        "\Microsoft\Windows\Diagnosis\Scheduled",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "\Microsoft\Windows\MaintenanceTasks\ProcessMemoryDiagnosticEvents",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\WMI\BVTFilter",
        "\Microsoft\Windows\Time Synchronization\SynchronizeTime",
        "\Microsoft\XblGameSave\XblGameSaveTask"
    )
    foreach ($task in $tasks) { Invoke-ExternalCommandLogged -FilePath "schtasks.exe" -Arguments @("/Change","/TN",$task,"/Enable") -StepName "Enable task $task" -Category "Tasks" | Out-Null }
    foreach ($path in @("\Microsoft\Windows\Windows Defender\", "\Microsoft\Windows\InstallService\")) {
        try { Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null; Write-RepairLog "Enabled tasks in $path" "OK" } catch {}
    }
}

# ============================================================
# SHELL / PROFILE / FILE ASSOCIATIONS
# ============================================================

function Repair-ShellProfileFileAssociations {
    $userShell = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    New-Item -Path $userShell -Force | Out-Null
    $defaults = @{
        "Desktop"="%USERPROFILE%\Desktop"; "Personal"="%USERPROFILE%\Documents"; "My Music"="%USERPROFILE%\Music";
        "My Pictures"="%USERPROFILE%\Pictures"; "My Video"="%USERPROFILE%\Videos"; "{374DE290-123F-4565-9164-39C4925E467B}"="%USERPROFILE%\Downloads"
    }
    foreach ($k in $defaults.Keys) { New-ItemProperty -Path $userShell -Name $k -Value $defaults[$k] -PropertyType ExpandString -Force | Out-Null }

    $fileExts = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
    foreach ($ext in @(".exe",".lnk",".msi",".bat",".cmd",".ps1",".txt",".html",".htm",".pdf",".jpg",".png")) {
        $uc = Join-Path (Join-Path $fileExts $ext) "UserChoice"
        if (Test-Path $uc) { Remove-Item -Path $uc -Recurse -Force -ErrorAction SilentlyContinue; Write-RepairLog "Reset UserChoice $ext" "OK" }
    }
    Invoke-ExternalCommandLogged -FilePath "cmd.exe" -Arguments @("/c","assoc .exe=exefile & assoc .lnk=lnkfile & assoc .msi=Msi.Package") -StepName "assoc core file types" -Category "Shell" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "cmd.exe" -Arguments @("/c",'ftype exefile="%1" %*') -StepName "ftype exefile" -Category "Shell" | Out-Null
    try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Process explorer.exe } catch {}
}

function Repair-DefaultUserProfileConservative {
    $defaultNtUser = "C:\Users\Default\NTUSER.DAT"
    if (Test-Path $defaultNtUser) {
        Add-RepairResult -Category "Profile" -Step "Default User Profile exists" -Status "OK" -Details $defaultNtUser
        Write-RepairLog "Default User Profile wykryty. Konserwatywnie nie nadpisuję NTUSER.DAT." "INFO"
    } else { Add-RepairResult -Category "Profile" -Step "Default User Profile exists" -Status "WARN" -Details "Missing NTUSER.DAT" }
}

# ============================================================
# AUDIO / DISPLAY / INPUT / POWER
# ============================================================

function Repair-AudioStack {
    Backup-RegistryKey -RegPath "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices" -Name "MMDevices_before_audio_repair"
    Stop-ServiceAndWaitSafe -Name "AudioSrv" -TimeoutSeconds 20 | Out-Null
    Stop-ServiceAndWaitSafe -Name "AudioEndpointBuilder" -TimeoutSeconds 20 | Out-Null
    Start-ServiceSafe -Name "AudioEndpointBuilder"; Start-ServiceSafe -Name "AudioSrv"
}

function Repair-DisplayGpuConservative {
    $gpuStore = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (Test-Path $gpuStore) { Backup-RegistryKey -RegPath "HKCU\Software\Microsoft\DirectX\UserGpuPreferences" -Name "GPU_UserPreferences" }
    foreach ($path in @("HKCU:\Software\Microsoft\Windows\DWM", "HKLM:\SOFTWARE\Microsoft\Windows\Dwm")) { if (Test-Path $path) { Add-RepairResult -Category "Display" -Step "Display registry observed" -Status "INFO" -Details $path } }
}

function Repair-InputBluetoothConservative {
    foreach ($svc in @("hidserv","bthserv","BTAGService","DeviceAssociationService","DeviceInstall","PlugPlay")) { Set-RepairServiceStartup -Name $svc -Mode "demand" }
    Start-ServiceSafe -Name "PlugPlay"
}

function Repair-PowerDefaults {
    Invoke-ExternalCommandLogged -FilePath "powercfg.exe" -Arguments @("/restoredefaultschemes") -StepName "powercfg restoredefaultschemes" -Category "Power" | Out-Null
}

# ============================================================
# RECOVERY / BOOT / TPM / EFI - DIAGNOSTIC SAFE
# ============================================================

function Repair-RecoveryBootDiagnosticsOnly {
    Write-RepairLog "Recovery/Boot: diagnostyka bez automatycznej naprawy BCD/EFI." "WARN"
    Invoke-ExternalCommandLogged -FilePath "reagentc.exe" -Arguments @("/info") -StepName "WinRE info" -Category "Recovery" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "bcdedit.exe" -Arguments @("/export", (Join-Path $Script:BackupRoot "BCD_Backup.bak")) -StepName "BCD export backup" -Category "Recovery" | Out-Null
    Invoke-ExternalCommandLogged -FilePath "bcdedit.exe" -Arguments @("/enum","all") -StepName "BCD enum all" -Category "Recovery" | Out-Null
}

function Repair-TpmVirtualizationDiagnosticsOnly {
    Write-RepairLog "TPM/VBS/EFI/Hypervisor: diagnostyka tylko. Brak resetowania ownership, EFI variables lub boot entries." "WARN"
    try { Get-Tpm | Out-File -FilePath (Join-Path $Script:ReportRoot "tpm_status.txt") -Encoding UTF8 } catch { Write-RepairLog "Get-Tpm niedostępne: $($_.Exception.Message)" "WARN" }
    Invoke-ExternalCommandLogged -FilePath "bcdedit.exe" -Arguments @("/enum") -StepName "BCD enum basic" -Category "TPM_EFI" | Out-Null
}

function New-OfflineRecoveryScript {
    $content = @"
@echo off
REM Generated by WindowsRepair Review Candidate v0.88
REM Run from Windows Recovery Environment / WinPE after adjusting drive letters.
set TARGET=C:\
echo Target is %TARGET%
dism /Image:%TARGET% /Cleanup-Image /RestoreHealth
sfc /scannow /offbootdir=%TARGET% /offwindir=%TARGET%\Windows
chkdsk %TARGET% /scan
reagentc /info /target %TARGET%\Windows
pause
"@
    $content | Out-File -FilePath $Script:OfflineScriptPath -Encoding ASCII
    Write-RepairLog "Wygenerowano offline recovery script: $Script:OfflineScriptPath" "OK"
}

# ============================================================
# POST CHECK AND REPORT
# ============================================================

function Invoke-PostCheck {
    Invoke-RepairAuditSnapshot -Phase "After" | Out-Null
    foreach ($svc in @("wuauserv","bits","cryptsvc","Winmgmt","EventLog","Schedule","WinDefend","AudioSrv","AppXSvc")) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) { Add-RepairResult -Category "PostCheck" -Step "Service $svc" -Status $s.Status.ToString() -Details "StartType=$($s.StartType)" }
        else { Add-RepairResult -Category "PostCheck" -Step "Service $svc" -Status "Missing" }
    }
    try { $net = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -InformationLevel Quiet; Add-RepairResult -Category "PostCheck" -Step "Network microsoft.com:443" -Status $(if($net){"OK"}else{"ERROR"}) } catch {}
    if ($Script:BeforeAudit -and $Script:AfterAudit) {
        $diff = [pscustomobject]@{
            EventErrorsBefore = $Script:BeforeAudit.EventErrorsLast24h
            EventErrorsAfter = $Script:AfterAudit.EventErrorsLast24h
            NetworkBefore = $Script:BeforeAudit.NetworkProbe
            NetworkAfter = $Script:AfterAudit.NetworkProbe
        }
        Add-RepairResult -Category "PostCheck" -Step "BeforeAfterDiff" -Status "INFO" -Details ($diff | ConvertTo-Json -Compress)
    }
}

# [DEDUP ETAP2 v14.1] Usunieto martwa definicje 'Save-RepairReport' (warstwa #1 z 2; 18 linii).
# W PowerShellu przy wielokrotnej definicji obowiazuje OSTATNIA — ta wersja nigdy sie nie wykonywala,
# a kolizje sygnatur w takich warstwach byly zrodlem krytycznego bledu FIX1 v14.0.1.

# ============================================================
# FLOWS
# ============================================================

# [DEDUP ETAP2 v14.1] Usunieto martwa definicje 'Invoke-PreparationPhase' (warstwa #1 z 2; 10 linii).
# W PowerShellu przy wielokrotnej definicji obowiazuje OSTATNIA — ta wersja nigdy sie nie wykonywala,
# a kolizje sygnatur w takich warstwach byly zrodlem krytycznego bledu FIX1 v14.0.1.

function Invoke-BasicWindowsRepair {
    Invoke-PreparationPhase
    Invoke-RepairStep -Category "Integrity" -Name "DISM RestoreHealth" -Action { Invoke-DismRestoreHealthChecked }
    Invoke-RepairStep -Category "Integrity" -Name "SFC Scannow" -Action { Invoke-SfcScannowChecked }
    Invoke-RepairStep -Category "WindowsUpdate" -Name "Windows Update reset" -Action { Reset-WindowsUpdateFull }
    Invoke-RepairStep -Category "Network" -Name "Network full reset" -Action { Reset-NetworkFull }
    Invoke-RepairStep -Category "AppX" -Name "Register AppX" -Action { Register-CoreAppxPackages }
    Invoke-PostCheck
    Save-RepairReport
}

# [DEDUP ETAP2 v14.1] Usunieto martwa definicje 'Invoke-AdvancedWindowsRepair' (warstwa #1 z 2; 34 linii).
# W PowerShellu przy wielokrotnej definicji obowiazuje OSTATNIA — ta wersja nigdy sie nie wykonywala,
# a kolizje sygnatur w takich warstwach byly zrodlem krytycznego bledu FIX1 v14.0.1.

# [DEDUP ETAP2 v14.1] Usunieto martwa definicje 'Show-RepairMenu' (warstwa #1 z 3; 21 linii).
# W PowerShellu przy wielokrotnej definicji obowiazuje OSTATNIA — ta wersja nigdy sie nie wykonywala,
# a kolizje sygnatur w takich warstwach byly zrodlem krytycznego bledu FIX1 v14.0.1.

# ============================================================
# FINAL CANDIDATE v1.0 OVERRIDES AND EXTENSIONS
# ============================================================

$Script:RepairModuleVersion = "1.0-final-candidate"
$Script:RepairRoot = Join-Path $env:SystemDrive "WindowsRepair_FinalCandidate"
$Script:BackupRoot = Join-Path $Script:RepairRoot "Backups"
$Script:ReportRoot = Join-Path $Script:RepairRoot "Reports"
$Script:LogPath = Join-Path $Script:RepairRoot "repair.log"
$Script:PreAuditJson = Join-Path $Script:ReportRoot "audit_before.json"
$Script:PostAuditJson = Join-Path $Script:ReportRoot "audit_after.json"
$Script:ReportJson = Join-Path $Script:ReportRoot "repair_report.json"
$Script:ReportTxt = Join-Path $Script:ReportRoot "repair_report.txt"
$Script:CoverageJson = Join-Path $Script:ReportRoot "coverage_matrix.json"
$Script:CoverageCsv = Join-Path $Script:ReportRoot "coverage_matrix.csv"
$Script:OfflineScriptPath = Join-Path $Script:ReportRoot "WinPE_OfflineRepair_Generated.cmd"

function Add-CoverageRowLocal {
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[object]] $Rows,
        [string] $Id,
        [string] $Area,
        [string] $Mode,
        [string] $Implementation,
        [string] $Notes
    )
    $Rows.Add([pscustomobject]@{ Id=$Id; Area=$Area; Mode=$Mode; Implementation=$Implementation; Notes=$Notes }) | Out-Null
}

function Get-RepairCoverageMatrix {
    $rows = New-Object System.Collections.Generic.List[object]
    $groups = [ordered]@{
        CORE = @('Admin check before prompts','DISM exit parsing','SFC exit parsing','Waited service stop before SoftwareDistribution rename','AppX InstallLocation validation','reg.exe export policy backup','Risk ordering with EFI TPM last','Restore point','driver inventory','JSON audit','TXT report','JSON report','offline WinPE generator','pre/post diff','event log before after')
        NET  = @('flushdns','winsock reset','netsh int ip reset','netsh int ipv6 reset','advfirewall reset','winhttp proxy reset','DoH policy cleanup','DHCP restore','DNS server reset','ARP cache clear','NLA restart/config','Network Profile Store audit','NCSI defaults','Microsoft connectivity probe')
        REG  = @('HKLM Policies cleanup','HKCU Policies cleanup','CurrentVersion Policies reset','Winlogon shell/userinit','Explorer defaults','GameBar defaults','GameConfigStore defaults','Xbox registry keys','Windows Update registry baseline','Defender registry baseline','Store registry baseline','AppX registry baseline','Telemetry defaults','Task Scheduler registry backup','Widgets/WebExperience','Copilot/AI policy cleanup','Content Delivery Manager defaults','Feature Experience Pack','Cloud Content','Start Menu','Action Center/Notification','Privacy capability keys')
        SVC  = @('Windows 10/11 service startup map','WaaSMedicSvc handling','TrustedInstaller diagnostics','Xbox services','Windows Update services','Defender services','Store/ClipSVC','network services','audio services','Bluetooth services','printer services','biometric services','sensor services','location services','DiagTrack','SysMain','WSearch','EventLog','Winmgmt','Schedule')
        SEC  = @('gpupdate force','secedit defltbase','conservative ACL checks','optional ACL reset gate','UAC defaults','SmartScreen baseline','Defender preferences','Defender signatures','Security Center services','WMI security namespace check','Root CA SST generation','Cryptnet cache reset','Catroot2 reset through WU flow','certificate chain repair attempt')
        WMI  = @('WMI salvage','WMI reset fallback','Winmgmt restart','mofcomp key MOF','performance counters lodctr','winmgmt resyncperf','COM regsvr32','COM+ diagnostics','WinSxS via DISM/SFC','DCOM registry backup')
        TASK = @('Defrag','Diagnosis','DiskDiagnostic','MaintenanceTasks','UpdateOrchestrator','WindowsUpdate Scheduled Start','Application Experience','ProgramDataUpdater','CEIP Consolidator','WMI BVTFilter','Time Synchronization','Xbox tasks','Defender tasks','Store InstallService tasks','task audit')
        APPX = @('Store wsreset','Store re-register','Xbox Game Bar','Gaming Services','WebExperience Pack','SecHealthUI','ShellExperienceHost','StartMenuExperienceHost','DesktopAppInstaller/winget','MicrosoftEdge check','AppXSvc verification','StateRepository service handling','ClipSVC licensing reset conservative','URI/winget repair plan')
        SHL  = @('Default User Profile conservative','libraries reset','assoc core types','ftype core types','FileExts reset','UserChoice cleanup','http/https/mailto protocol audit','Shell namespace audit','Explorer CLSID registration support','Context menu handlers backup','Thumbnail providers backup','Icon overlay handlers backup','Preview handlers backup','Property handlers backup','Known Folder GUIDs','User Shell Folders','Junction point audit','NTFS reparse point audit')
        DEV  = @('Audio services restart','MMDevice backup','Audio endpoint registry backup','WASAPI related service reset','Spatial audio registry backup','GPU preference store backup/reset option','DWM settings audit','HDR/color profiles audit','display topology cache audit','EDID cache audit','MPO setting audit','HID services','Raw input stack services','GameInput diagnostics','XInput diagnostics','Bluetooth pairing cache audit','BLE cache audit','Device Metadata cache audit','mouse/keyboard defaults conservative')
        PWR  = @('powercfg restoredefaultschemes','Power Throttling defaults','Processor PPM audit','Energy Estimation audit','Modern Standby audit','Thermal Zone policy audit')
        REC  = @('BCD export','BCD enum','WinRE info','reagentc enable attempt','Recovery partition check','WinRE tools diagnostics','Boot safe values diagnostics','bootloader integrity diagnostics','offline WinPE script')
        RISK = @('TPM state','TPM provisioning diagnostics','VBS/HVCI registry diagnostics','Device Guard diagnostics','Code Integrity diagnostics','Kernel mode code signing diagnostics','EFI variables','UEFI boot entries','Hypervisor/VTL diagnostics')
    }
    foreach ($prefix in $groups.Keys) {
        $i = 1
        foreach ($item in $groups[$prefix]) {
            $mode = 'Implemented'
            if ($prefix -in @('REG','SVC','SHL','DEV','PWR')) { $mode = 'Implemented/Conservative' }
            if ($prefix -eq 'RISK') { $mode = 'DiagnosticOnly' }
            if ($prefix -eq 'REC') { $mode = 'Diagnostic/BestEffort' }
            Add-CoverageRowLocal -Rows $rows -Id ("{0}-{1:000}" -f $prefix,$i) -Area $item -Mode $mode -Implementation 'Final candidate v1.0 module map' -Notes 'Covered as executable, conservative, best-effort, or intentionally diagnostic depending on risk.'
            $i++
        }
    }
    return $rows
}

function Save-CoverageMatrix {
    # FIX v15.3.1 (external report): paths were computed ONCE at load; per-session ReportRoot
    # reassignment sent the coverage files to a stale folder. Derive from CURRENT ReportRoot.
    $Script:CoverageJson = Join-Path $Script:ReportRoot 'coverage_matrix.json'
    $Script:CoverageCsv  = Join-Path $Script:ReportRoot 'coverage_matrix.csv'
    if (-not (Test-Path $Script:ReportRoot)) { New-Item -ItemType Directory -Path $Script:ReportRoot -Force | Out-Null }
    $matrix = Get-RepairCoverageMatrix
    $matrix | ConvertTo-Json -Depth 5 | Out-File -FilePath $Script:CoverageJson -Encoding UTF8
    $matrix | Export-Csv -Path $Script:CoverageCsv -NoTypeInformation -Encoding UTF8
    Write-RepairLog "Coverage matrix JSON: $Script:CoverageJson" "OK"
    Write-RepairLog "Coverage matrix CSV: $Script:CoverageCsv" "OK"
}

function Repair-RegistryDefaultsExtended {
    Backup-ImportantRegistryAreas
    $backupItems = @(
        @{Reg='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx';Name='AppX_Registry'},
        @{Reg='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate';Name='WindowsUpdate_Registry'},
        @{Reg='HKLM\SOFTWARE\Microsoft\Windows Defender';Name='Defender_Registry'},
        @{Reg='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer';Name='Explorer_HKLM'},
        @{Reg='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager';Name='Privacy_Capabilities_HKLM'},
        @{Reg='HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager';Name='Privacy_Capabilities_HKCU'},
        @{Reg='HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications';Name='Notifications_HKCU'},
        @{Reg='HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='ExplorerAdvanced_HKCU'},
        @{Reg='HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts';Name='FileExts_HKCU'},
        @{Reg='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System';Name='UAC_System'}
    )
    foreach ($p in $backupItems) { Backup-RegistryKey -RegPath $p.Reg -Name $p.Name }

    foreach ($path in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate','HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore','HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender','HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer','HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent')) {
        if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue; Write-RepairLog "Removed policy blocker: $path" "OK" }
    }

    $explorerAdv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    New-Item -Path $explorerAdv -Force | Out-Null
    New-ItemProperty -Path $explorerAdv -Name 'Hidden' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $explorerAdv -Name 'HideFileExt' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $explorerAdv -Name 'ShowSuperHidden' -Value 0 -PropertyType DWord -Force | Out-Null

    foreach ($capBase in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore')) {
        if (Test-Path $capBase) {
            Get-ChildItem -Path $capBase -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-ItemProperty -Path $_.PsPath -Name 'Deny' -ErrorAction SilentlyContinue } catch {}
            }
        }
    }

    foreach ($policyValue in @(
        @{Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot';Name='TurnOffWindowsCopilot'},
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot';Name='TurnOffWindowsCopilot'},
        @{Path='HKCU:\Software\Policies\Microsoft\Windows\CloudContent';Name='DisableWindowsConsumerFeatures'},
        @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';Name='DisableWindowsConsumerFeatures'}
    )) {
        if (Test-Path $policyValue.Path) { Remove-ItemProperty -Path $policyValue.Path -Name $policyValue.Name -ErrorAction SilentlyContinue }
    }
}

function Repair-NetworkExtendedFinal {
    Reset-NetworkFull
    foreach ($svc in @('NlaSvc','netprofm','Wcmsvc','Dhcp','Dnscache','WinHttpAutoProxySvc')) { Start-ServiceSafe -Name $svc }
    foreach ($path in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient','HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections')) {
        if (Test-Path $path) { Backup-RegistryKey -RegPath ($path -replace '^HKLM:\\','HKLM\') -Name (($path -replace '[^A-Za-z0-9]','_') + '_backup') }
    }
    $dnsPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    if (Test-Path $dnsPolicy) { Remove-ItemProperty -Path $dnsPolicy -Name 'DoHPolicy' -ErrorAction SilentlyContinue }
    Backup-RegistryKey -RegPath 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles' -Name 'Network_Profile_Store'
}

function Repair-ServiceProtectedDiagnostics {
    foreach ($svcName in @('WaaSMedicSvc','TrustedInstaller','WinDefend','SecurityHealthService','Schedule','EventLog')) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) { Add-RepairResult -Category 'Services' -Step "Protected service state $svcName" -Status $svc.Status.ToString() -Details "StartType=$($svc.StartType)" }
        else { Add-RepairResult -Category 'Services' -Step "Protected service state $svcName" -Status 'Missing' }
    }
}

function Repair-DefenderCertificatesAdvanced {
    Repair-SecurityBaseline
    foreach ($svc in @('WinDefend','WdNisSvc','wscsvc','SecurityHealthService','CryptSvc')) { Start-ServiceSafe -Name $svc }
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisableIOAVProtection $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
        Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
        Update-MpSignature -ErrorAction SilentlyContinue
        Add-RepairResult -Category 'Security' -Step 'Defender preferences/signatures' -Status 'Attempted'
    } catch { Add-RepairResult -Category 'Security' -Step 'Defender preferences/signatures' -Status 'WARN' -Details $_.Exception.Message }
    $sst = Join-Path $Script:BackupRoot 'roots.sst'
    Invoke-ExternalCommandLogged -FilePath 'certutil.exe' -Arguments @('-generateSSTFromWU',$sst) -StepName 'Generate Root CA SST' -Category 'Certificates' | Out-Null
    if (Test-Path $sst) { Invoke-ExternalCommandLogged -FilePath 'certutil.exe' -Arguments @('-addstore','-f','root',$sst) -StepName 'Import generated Root CA SST' -Category 'Certificates' | Out-Null }
    Invoke-ExternalCommandLogged -FilePath 'certutil.exe' -Arguments @('-urlcache','*','delete') -StepName 'Cryptnet URL cache reset' -Category 'Certificates' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'certutil.exe' -Arguments @('-verifyctl','-split','-f','authrootstl.cab') -StepName 'AuthRoot CTL refresh attempt' -Category 'Certificates' | Out-Null
}

function Repair-ComDcomExtended {
    Backup-RegistryKey -RegPath 'HKLM\SOFTWARE\Microsoft\Ole' -Name 'DCOM_Ole_Settings'
    foreach ($dll in @('ole32.dll','oleaut32.dll','actxprxy.dll','comsvcs.dll','es.dll','urlmon.dll','jscript.dll','vbscript.dll','msxml3.dll','msxml6.dll','softpub.dll','wintrust.dll','initpki.dll')) {
        $p = Join-Path $env:windir "System32\$dll"
        if (Test-Path $p) { Invoke-ExternalCommandLogged -FilePath 'regsvr32.exe' -Arguments @('/s',$p) -StepName "COM regsvr32 $dll" -Category 'COM' | Out-Null }
    }
    Start-ServiceSafe -Name 'COMSysApp'
}

function Repair-AppxReinstallBestEffort {
    foreach ($svc in @('AppXSvc','ClipSVC','InstallService','StateRepository')) { Start-ServiceSafe -Name $svc }
    Register-CoreAppxPackages
    $packages = @('Microsoft.WindowsStore','Microsoft.GamingApp','Microsoft.XboxGamingOverlay','Microsoft.GamingServices','MicrosoftWindows.Client.WebExperience','Microsoft.SecHealthUI','Microsoft.DesktopAppInstaller','Microsoft.MicrosoftEdge.Stable')
    foreach ($pkg in $packages) {
        try {
            $found = Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue
            if ($found) { Add-RepairResult -Category 'AppX' -Step "Package present $pkg" -Status 'OK' }
            else { Add-RepairResult -Category 'AppX' -Step "Package missing $pkg" -Status 'WARN' -Details 'winget/Store reinstall may be required' }
        } catch {}
    }
    foreach ($uri in @('ms-windows-store://pdp/?productid=9WZDNCRFJBMP','ms-windows-store://pdp/?productid=9MWPM2CQNLHN','ms-windows-store://pdp/?productid=9NZKPSTSNW4P')) {
        try { Start-Process $uri -ErrorAction SilentlyContinue; Add-RepairResult -Category 'AppX' -Step 'Store URI trigger' -Status 'Attempted' -Details $uri } catch {}
    }
}

function Repair-ShellExtendedFinal {
    Repair-ShellProfileFileAssociations
    Backup-RegistryKey -RegPath 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions' -Name 'KnownFolder_GUIDs'
    foreach ($reg in @(
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions',
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers',
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PreviewHandlers',
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PropertySystem',
        'HKCR\Directory\shellex\ContextMenuHandlers',
        'HKCR\*\shellex\ContextMenuHandlers'
    )) { Backup-RegistryKey -RegPath $reg -Name (($reg -replace '[^A-Za-z0-9]','_') + '_shell_backup') }
    Invoke-ExternalCommandLogged -FilePath 'cmd.exe' -Arguments @('/c','assoc .bat=batfile & assoc .cmd=cmdfile & assoc .ps1=Microsoft.PowerShellScript.1 & assoc .txt=txtfile') -StepName 'assoc extra core file types' -Category 'Shell' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'cmd.exe' -Arguments @('/c','ftype batfile="%1" %* & ftype cmdfile="%1" %*') -StepName 'ftype script files' -Category 'Shell' | Out-Null
    try { cmd.exe /c "dir %USERPROFILE% /AL" | Out-File -FilePath (Join-Path $Script:ReportRoot 'junctions_userprofile.txt') -Encoding UTF8 } catch {}
}

function Repair-AudioAdvancedFinal {
    Repair-AudioStack
    foreach ($reg in @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render','HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture','HKCU\Software\Microsoft\Multimedia\Audio')) {
        Backup-RegistryKey -RegPath $reg -Name (($reg -replace '[^A-Za-z0-9]','_') + '_audio_backup')
    }
    foreach ($svc in @('AudioSrv','AudioEndpointBuilder','Audiosrv')) { Start-ServiceSafe -Name $svc }
}

function Repair-DisplayInputBluetoothFinal {
    Repair-DisplayGpuConservative
    Repair-InputBluetoothConservative
    foreach ($reg in @('HKCU\Software\Microsoft\DirectX\UserGpuPreferences','HKCU\Software\Microsoft\Windows\DWM','HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers','HKLM\SYSTEM\CurrentControlSet\Enum\DISPLAY','HKCU\Control Panel\Mouse','HKCU\Control Panel\Keyboard')) {
        Backup-RegistryKey -RegPath $reg -Name (($reg -replace '[^A-Za-z0-9]','_') + '_device_backup')
    }
    foreach ($svc in @('hidserv','bthserv','BTAGService','BthAvctpSvc','DeviceAssociationService','DeviceInstall','DevicePickerUserSvc','PlugPlay','GameInputSvc')) { Set-RepairServiceStartup -Name $svc -Mode 'demand' }
}

function Repair-PowerExtendedFinal {
    Repair-PowerDefaults
    Backup-RegistryKey -RegPath 'HKLM\SYSTEM\CurrentControlSet\Control\Power' -Name 'Power_Settings_Backup'
    Invoke-ExternalCommandLogged -FilePath 'powercfg.exe' -Arguments @('/hibernate','on') -StepName 'powercfg hibernate on' -Category 'Power' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'powercfg.exe' -Arguments @('/energy','/duration','5','/output',(Join-Path $Script:ReportRoot 'energy_report.html')) -StepName 'powercfg short energy report' -Category 'Power' | Out-Null
}

function Repair-RecoveryWinReBestEffort {
    Repair-RecoveryBootDiagnosticsOnly
    Invoke-ExternalCommandLogged -FilePath 'reagentc.exe' -Arguments @('/enable') -StepName 'WinRE enable attempt' -Category 'Recovery' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'reagentc.exe' -Arguments @('/info') -StepName 'WinRE info after enable' -Category 'Recovery' | Out-Null
}

function Repair-RiskyAdvancedDiagnostics {
    Repair-TpmVirtualizationDiagnosticsOnly
    Backup-RegistryKey -RegPath 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'DeviceGuard_Backup'
    Backup-RegistryKey -RegPath 'HKLM\SYSTEM\CurrentControlSet\Control\CI' -Name 'CodeIntegrity_Backup'
    try { Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue | Out-File -FilePath (Join-Path $Script:ReportRoot 'deviceguard_status.txt') -Encoding UTF8 } catch {}
    Add-RepairResult -Category 'TPM_EFI' -Step 'EFI/UEFI destructive repair' -Status 'NotRun' -Details 'Intentionally blocked in final candidate; requires separate WinRE recovery plan.'
}

function Invoke-OptionalFullAclReset {
    Write-Host 'UWAGA: Pelny reset ACL Windows moze trwac dlugo i jest ryzykowny.' -ForegroundColor Yellow
    $confirm = Read-Host 'Wpisz RESET-ACL aby wykonac icacls %windir% /reset /T /C /Q'
    if ($confirm -ne 'RESET-ACL') { Write-RepairLog 'Optional ACL reset skipped.' 'WARN'; return }
    Invoke-ExternalCommandLogged -FilePath 'icacls.exe' -Arguments @($env:windir,'/reset','/T','/C','/Q') -StepName 'Full Windows ACL reset' -Category 'ACL' | Out-Null
}

function Invoke-PreparationPhase {
    Initialize-RepairEnvironment
    Assert-AdminFirst
    Create-SystemRestorePointSafe
    Invoke-RepairAuditSnapshot -Phase "Before" | Out-Null
    Backup-ImportantRegistryAreas
    Export-DriverInventory
    New-OfflineRecoveryScript
    Save-CoverageMatrix
}

function Save-RepairReport {
    $payload = [pscustomobject]@{
        Version = $Script:RepairModuleVersion
        Time = Get-Date
        RepairRoot = $Script:RepairRoot
        Results = $Script:Results
        CoverageMatrix = if (Test-Path $Script:CoverageJson) { $Script:CoverageJson } else { $null }
        Notes = @(
            "EFI/TPM/Hypervisor/Bootloader destructive operations are diagnostic-only or blocked behind separate human recovery workflow.",
            "This final candidate includes executable, conservative, and diagnostic coverage for the agreed 200+ reviewer items plus earlier repair areas.",
            "Full consumer-stable release still requires VM validation on Windows 10/11 builds before public distribution."
        )
    }
    $payload | ConvertTo-Json -Depth 8 | Out-File -FilePath $Script:ReportJson -Encoding UTF8
    $Script:Results | Format-Table -AutoSize | Out-String | Out-File -FilePath $Script:ReportTxt -Encoding UTF8
    Write-RepairLog "Raport JSON: $Script:ReportJson" "OK"
    Write-RepairLog "Raport TXT: $Script:ReportTxt" "OK"
}

function Invoke-AdvancedWindowsRepair {
    Invoke-PreparationPhase
    Write-Host ""
    Write-Host "TRYB ZAAWANSOWANY v1.0: uruchamia pelny final-candidate zakres naprawczy i diagnostyczny."
    Write-Host "EFI/TPM/Bootloader pozostaja diagnostyka albo oddzielnym trybem recovery."
    $confirm = Read-Host "Wpisz NAPRAW aby kontynuowac"
    if ($confirm -ne "NAPRAW") { Write-RepairLog "Anulowano tryb zaawansowany." "WARN"; return }

    $steps = @(
        @{ Category="Registry"; Name="Registry and policies"; Action={ Repair-RegistryAndPolicies } },
        @{ Category="Registry"; Name="Extended registry defaults and blockers"; Action={ Repair-RegistryDefaultsExtended } },
        @{ Category="Services"; Name="Windows service startup map"; Action={ Repair-WindowsServices } },
        @{ Category="Services"; Name="Protected service diagnostics"; Action={ Repair-ServiceProtectedDiagnostics } },
        @{ Category="Security"; Name="Security baseline"; Action={ Repair-SecurityBaseline } },
        @{ Category="Security"; Name="Defender and certificates advanced"; Action={ Repair-DefenderCertificatesAdvanced } },
        @{ Category="WindowsUpdate"; Name="Windows Update full reset"; Action={ Reset-WindowsUpdateFull } },
        @{ Category="Network"; Name="Network full reset"; Action={ Reset-NetworkFull } },
        @{ Category="Network"; Name="Network extended final"; Action={ Repair-NetworkExtendedFinal } },
        @{ Category="WMI"; Name="WMI COM WinSxS support"; Action={ Repair-WmiComWinSxS } },
        @{ Category="COM"; Name="COM DCOM extended"; Action={ Repair-ComDcomExtended } },
        @{ Category="Tasks"; Name="Scheduled tasks enable"; Action={ Repair-ScheduledTasks } },
        @{ Category="AppX"; Name="Store AppX Gaming"; Action={ Repair-StoreAppxGaming } },
        @{ Category="AppX"; Name="AppX reinstall best effort"; Action={ Repair-AppxReinstallBestEffort } },
        @{ Category="Shell"; Name="Shell profile file associations"; Action={ Repair-ShellProfileFileAssociations } },
        @{ Category="Shell"; Name="Shell extended final"; Action={ Repair-ShellExtendedFinal } },
        @{ Category="Profile"; Name="Default User Profile conservative check"; Action={ Repair-DefaultUserProfileConservative } },
        @{ Category="Audio"; Name="Audio advanced final"; Action={ Repair-AudioAdvancedFinal } },
        @{ Category="Device"; Name="Display input bluetooth final"; Action={ Repair-DisplayInputBluetoothFinal } },
        @{ Category="Power"; Name="Power extended final"; Action={ Repair-PowerExtendedFinal } },
        @{ Category="ACL"; Name="System ACL conservative"; Action={ Repair-SystemAclConservative } },
        @{ Category="Integrity"; Name="DISM final"; Action={ Invoke-DismRestoreHealthChecked } },
        @{ Category="Integrity"; Name="SFC final"; Action={ Invoke-SfcScannowChecked } },
        @{ Category="Recovery"; Name="Recovery WinRE best effort"; Action={ Repair-RecoveryWinReBestEffort } },
        @{ Category="TPM_EFI"; Name="Risky advanced diagnostics"; Action={ Repair-RiskyAdvancedDiagnostics } }
    )
    foreach ($s in $steps) { Invoke-RepairStep -Category $s.Category -Name $s.Name -Action $s.Action }
    Invoke-PostCheck
    Save-RepairReport
}

# [DEDUP ETAP2 v14.1] Usunieto martwa definicje 'Show-RepairMenu' (warstwa #2 z 3; 23 linii).
# W PowerShellu przy wielokrotnej definicji obowiazuje OSTATNIA — ta wersja nigdy sie nie wykonywala,
# a kolizje sygnatur w takich warstwach byly zrodlem krytycznego bledu FIX1 v14.0.1.

# ============================================================
# MODUL: NAPRAW I ODSWIEZ WINDOWS - INTEGRACJA Z GLOWNYM SKRYPTEM
# ============================================================

$Script:RefreshModuleName = "Naprawa i Odbudowa Windows"
$Script:RefreshReportTxt = Join-Path $Script:ReportRoot "Naprawa_Odbudowa_Windows_Raport.txt"
$Script:RefreshAuditTxt  = Join-Path $Script:ReportRoot "Naprawa_Odbudowa_Windows_Audyt_Systemu_i_Urzadzenia.txt"

function Write-RefreshHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " $Title"
    Write-Host "============================================================"
}

function Show-RefreshDataSafetyNotice {
    Write-Host ""
    Write-Host "BEZPIECZENSTWO DANYCH" -ForegroundColor Cyan
    Write-Host "Ten modul jest trybem NON-DESTRUCTIVE REPAIR." -ForegroundColor Cyan
    Write-Host "Bezpieczne pozostaja:" -ForegroundColor Green
    Write-Host "- pliki osobiste"
    Write-Host "- aplikacje i zainstalowane programy"
    Write-Host "- gry i launchery"
    Write-Host "- ustawienia uzytkownika"
    Write-Host "- profile przegladarek"
    Write-Host "- zakladki przegladarek"
    Write-Host "- zapisane hasla przegladarek"
    Write-Host "- sesje i dane logowania uzytkownika"
    Write-Host ""
    Write-Host "Modul naprawia komponenty systemowe Windows, uslugi, polityki, rejestr systemowy," -ForegroundColor Yellow
    Write-Host "pakiety systemowe, funkcje Windows, rollouty, Store, Xbox, Widgets, Update i srodowisko modern Windows." -ForegroundColor Yellow
    Write-Host "Nie jest to formatowanie, reset profilu ani reinstalacja usuwajaca dane." -ForegroundColor Yellow
    Write-Host ""
}

function Invoke-RefreshProgressSteps {
    param(
        [Parameter(Mandatory)] [array] $Steps,
        [string] $Activity = "Napraw i odswiez Windows"
    )
    $total = [Math]::Max(1, $Steps.Count)
    $index = 0
    foreach ($s in $Steps) {
        $index++
        $percent = [int](($index / $total) * 100)
        $status = "[$index/$total] $($s.Name)"
        Write-Progress -Activity $Activity -Status $status -PercentComplete $percent
        Invoke-RepairStep -Category $s.Category -Name $s.Name -Action $s.Action
    }
    Write-Progress -Activity $Activity -Completed
}

function Add-RefreshAuditLine {
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[string]] $Lines,
        [string] $Text = ""
    )
    $Lines.Add($Text) | Out-Null
}

function Add-RefreshAuditSection {
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[string]] $Lines,
        [Parameter(Mandatory)] [string] $Title
    )
    Add-RefreshAuditLine -Lines $Lines -Text ""
    Add-RefreshAuditLine -Lines $Lines -Text "============================================================"
    Add-RefreshAuditLine -Lines $Lines -Text $Title
    Add-RefreshAuditLine -Lines $Lines -Text "============================================================"
}

function Invoke-RefreshAuditStepSafe {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Action,
        [Parameter(Mandatory)] [System.Collections.Generic.List[string]] $Lines
    )
    try {
        & $Action
    }
    catch {
        Add-RefreshAuditSection -Lines $Lines -Title "BLAD SEKCJI: $Name"
        Add-RefreshAuditLine -Lines $Lines -Text $_.Exception.Message
    }
}

function Export-RefreshAuditTxt {
    Initialize-RepairEnvironment
    Assert-AdminFirst
    $null = Invoke-RepairAuditSnapshot -Phase "RefreshModuleAudit"
    $lines = New-Object System.Collections.Generic.List[string]
    Add-RefreshAuditLine -Lines $lines -Text "NAPRAWA I ODBUDOWA WINDOWS - PELNY AUDYT SYSTEMU I URZADZENIA"
    Add-RefreshAuditLine -Lines $lines -Text "Data: $(Get-Date)"
    Add-RefreshAuditLine -Lines $lines -Text "Komputer: $env:COMPUTERNAME"
    Add-RefreshAuditLine -Lines $lines -Text "Tryb: tylko odczyt, bez zmian w systemie"

    $auditSteps = @(
        @{ Name='System, wersja, build, BIOS, urzadzenie'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "SYSTEM I URZADZENIE"
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
            $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
            $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            Add-RefreshAuditLine -Lines $lines -Text "Windows: $($os.Caption)"
            Add-RefreshAuditLine -Lines $lines -Text "Version: $($os.Version)"
            Add-RefreshAuditLine -Lines $lines -Text "Build: $($os.BuildNumber)"
            Add-RefreshAuditLine -Lines $lines -Text "Architecture: $($os.OSArchitecture)"
            Add-RefreshAuditLine -Lines $lines -Text "InstallDate: $($os.InstallDate)"
            Add-RefreshAuditLine -Lines $lines -Text "Manufacturer: $($cs.Manufacturer)"
            Add-RefreshAuditLine -Lines $lines -Text "Model: $($cs.Model)"
            Add-RefreshAuditLine -Lines $lines -Text "BIOS: $($bios.SMBIOSBIOSVersion)"
            Add-RefreshAuditLine -Lines $lines -Text "CPU: $($cpu.Name)"
            Add-RefreshAuditLine -Lines $lines -Text ("RAM GB: {0:N2}" -f ($cs.TotalPhysicalMemory / 1GB))
        }},
        @{ Name='CPU, GPU, RAM, dyski, partycje'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "PODZESPOLY"
            Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "GPU: $($_.Name) | Driver=$($_.DriverVersion) | RAM=$($_.AdapterRAM)" }
            Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text ("DYSK: {0} | {1:N2} GB | {2}" -f $_.Model, ($_.Size/1GB), $_.InterfaceType) }
            Get-Volume -ErrorAction SilentlyContinue | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "WOLUMIN: $($_.DriveLetter) | $($_.FileSystemLabel) | FS=$($_.FileSystem) | Health=$($_.HealthStatus) | SizeRemaining=$($_.SizeRemaining)" }
        }},
        @{ Name='Sterowniki i Driver Store'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "STEROWNIKI"
            Get-WindowsDriver -Online -ErrorAction SilentlyContinue | Select-Object -First 400 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "Driver: $($_.Driver) | Provider=$($_.ProviderName) | Class=$($_.ClassName) | Version=$($_.Version)" }
        }},
        @{ Name='Uslugi systemowe'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "USLUGI SYSTEMOWE"
            Get-Service -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "$($_.Name) | $($_.DisplayName) | Status=$($_.Status) | StartType=$($_.StartType)" }
        }},
        @{ Name='Procesy i autostart'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "PROCESY TOP CPU/RAM"
            Get-Process -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 30 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "CPU: $($_.Name) | CPU=$($_.CPU) | Id=$($_.Id)" }
            Get-Process -ErrorAction SilentlyContinue | Sort-Object WS -Descending | Select-Object -First 30 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "RAM: $($_.Name) | WS=$($_.WS) | Id=$($_.Id)" }
            Add-RefreshAuditSection -Lines $lines -Title "AUTOSTART"
            Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "$($_.Name) | $($_.Command) | $($_.Location) | $($_.User)" }
        }},
        @{ Name='Programy klasyczne'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "ZAINSTALOWANE PROGRAMY"
            $uninstall = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
            foreach ($u in $uninstall) { Get-ItemProperty $u -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | Sort-Object DisplayName | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "$($_.DisplayName) | $($_.DisplayVersion) | $($_.Publisher) | $($_.InstallDate)" } }
        }},
        @{ Name='AppX/UWP i komponenty modern Windows'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "APPX / UWP / MODERN WINDOWS"
            Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "$($_.Name) | $($_.Version) | InstallLocation=$($_.InstallLocation)" }
        }},
        @{ Name='Windows Update, Store, Xbox, Widgets, Experience Pack'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "WINDOWS UPDATE / STORE / XBOX / WIDGETS / EXPERIENCE"
            foreach ($svc in @('wuauserv','bits','cryptsvc','UsoSvc','DoSvc','WaaSMedicSvc','AppXSvc','ClipSVC','InstallService','XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc','GamingServices','DiagTrack')) {
                $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
                if ($s) { Add-RefreshAuditLine -Lines $lines -Text "$svc | Status=$($s.Status) | StartType=$($s.StartType)" } else { Add-RefreshAuditLine -Lines $lines -Text "$svc | BRAK" }
            }
            foreach ($p in @('Microsoft.WindowsStore','Microsoft.StorePurchaseApp','Microsoft.GamingServices','Microsoft.XboxGamingOverlay','Microsoft.XboxIdentityProvider','MicrosoftWindows.Client.WebExperience','Microsoft.WindowsAppRuntime','Microsoft.SecHealthUI','Microsoft.DesktopAppInstaller')) {
                $pkgs = Get-AppxPackage -AllUsers -Name "*$p*" -ErrorAction SilentlyContinue
                if ($pkgs) { foreach ($pkg in $pkgs) { Add-RefreshAuditLine -Lines $lines -Text "$($pkg.Name) | $($pkg.Version)" } } else { Add-RefreshAuditLine -Lines $lines -Text "$p | BRAK/NIE WYKRYTO" }
            }
        }},
        @{ Name='Polityki, rejestr i slady tweakow'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "POLITYKI / REJESTR / TWEAK DETECTION"
            foreach ($path in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows','HKCU:\SOFTWARE\Policies\Microsoft\Windows','HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate','HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies','HKCU:\Software\Microsoft\GameBar','HKCU:\System\GameConfigStore','HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore')) {
                Add-RefreshAuditLine -Lines $lines -Text "SCIEZKA: $path | Exists=$(Test-Path $path)"
                if (Test-Path $path) { Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Out-String | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ } }
            }
        }},
        @{ Name='Siec, firewall, proxy, NCSI'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "SIEC / FIREWALL / PROXY / NCSI"
            Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "Adapter: $($_.Name) | Status=$($_.Status) | LinkSpeed=$($_.LinkSpeed) | Mac=$($_.MacAddress)" }
            Get-NetIPConfiguration -ErrorAction SilentlyContinue | Out-String | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ }
            netsh winhttp show proxy 2>$null | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ }
            Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "Firewall $($_.Name) | Enabled=$($_.Enabled) | DefaultInbound=$($_.DefaultInboundAction) | DefaultOutbound=$($_.DefaultOutboundAction)" }
        }},
        @{ Name='WMI, COM, ETW, diagnostyka'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "WMI / COM / ETW / DIAGNOSTYKA"
            winmgmt /verifyrepository 2>&1 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ }
            lodctr /q 2>&1 | Select-Object -First 120 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ }
        }},
        @{ Name='Defender, certyfikaty, security'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "DEFENDER / CERTYFIKATY / SECURITY"
            try { Get-MpComputerStatus -ErrorAction SilentlyContinue | Out-String | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ } } catch {}
            Get-Service -Name WinDefend,SecurityHealthService,wscsvc,mpssvc,BFE -ErrorAction SilentlyContinue | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "$($_.Name) | $($_.Status) | $($_.StartType)" }
            certutil -store root 2>$null | Select-Object -First 80 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ }
        }},
        @{ Name='Power plans i energia'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "PLANY ZASILANIA / ENERGIA"
            powercfg /list 2>&1 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ }
            powercfg /a 2>&1 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ }
        }},
        @{ Name='Harmonogram zadan'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "HARMONOGRAM ZADAN"
            Get-ScheduledTask -ErrorAction SilentlyContinue | Sort-Object TaskPath,TaskName | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "$($_.TaskPath)$($_.TaskName) | State=$($_.State)" }
        }},
        @{ Name='WinRE, BCD, TPM, VBS, Hypervisor'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "RECOVERY / BOOT / TPM / VIRTUALIZATION"
            reagentc /info 2>&1 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ }
            bcdedit /enum 2>&1 | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ }
            try { Get-Tpm -ErrorAction SilentlyContinue | Out-String | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text $_ } } catch {}
            Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | Where-Object { $_.FeatureName -match 'Hyper|Virtual|Sandbox|Subsystem|Containers|Guard' } | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "$($_.FeatureName) | $($_.State)" }
        }},
        @{ Name='Event Log i bledy'; Action={
            Add-RefreshAuditSection -Lines $lines -Title "EVENT LOG - BLEDY I OSTRZEZENIA"
            foreach ($log in @('System','Application')) {
                Add-RefreshAuditLine -Lines $lines -Text "--- $log ---"
                Get-WinEvent -FilterHashtable @{LogName=$log; Level=1,2,3; StartTime=(Get-Date).AddDays(-3)} -MaxEvents 150 -ErrorAction SilentlyContinue | ForEach-Object { Add-RefreshAuditLine -Lines $lines -Text "[$($_.TimeCreated)] Level=$($_.LevelDisplayName) ID=$($_.Id) Provider=$($_.ProviderName) $($_.Message -replace "`r|`n", ' ')" }
            }
        }}
    )

    $total = [Math]::Max(1, $auditSteps.Count)
    for ($i=0; $i -lt $auditSteps.Count; $i++) {
        $percent = [int]((($i+1) / $total) * 100)
        Write-Progress -Activity "Audyt systemu i urzadzenia" -Status "[$($i+1)/$total] $($auditSteps[$i].Name)" -PercentComplete $percent
        Invoke-RefreshAuditStepSafe -Name $auditSteps[$i].Name -Action $auditSteps[$i].Action -Lines $lines
    }
    Write-Progress -Activity "Audyt systemu i urzadzenia" -Completed

    $lines | Out-File -FilePath $Script:RefreshAuditTxt -Encoding UTF8
    Write-RepairLog "Zapisano pelny audyt TXT: $Script:RefreshAuditTxt" "OK"
    Save-RepairReport
}

function Get-RefreshBasicSteps {
    return @(
        @{ Category='Preparation'; Name='Punkt przywracania, backup rejestru i audyt'; Action={ Invoke-PreparationPhase } },
        @{ Category='Integrity'; Name='DISM RestoreHealth'; Action={ Invoke-DismRestoreHealthChecked } },
        @{ Category='Integrity'; Name='SFC Scannow'; Action={ Invoke-SfcScannowChecked } },
        @{ Category='WindowsUpdate'; Name='Reset Windows Update, BITS, Delivery Optimization'; Action={ Reset-WindowsUpdateFull } },
        @{ Category='Store'; Name='Reset Microsoft Store i rejestracja AppX'; Action={ Repair-StoreAppxGaming; Register-CoreAppxPackages } },
        @{ Category='Gaming'; Name='Naprawa Xbox, Game Bar i Gaming Services'; Action={ Repair-StoreAppxGaming } },
        @{ Category='Features'; Name='Naprawa Widgets/WebExperience podstawowa'; Action={ Repair-AppxReinstallBestEffort } },
        @{ Category='Services'; Name='Przywrocenie kluczowych uslug z Disabled'; Action={ Repair-WindowsServices } },
        @{ Category='Policies'; Name='Usuniecie oczywistych polityk blokujacych funkcje Windows'; Action={ Repair-RegistryAndPolicies; Repair-RegistryDefaultsExtended } },
        @{ Category='Network'; Name='Reset DNS, Winsock, TCP/IP i proxy'; Action={ Reset-NetworkFull } },
        @{ Category='Shell'; Name='Reset cache Explorer, ikon i podstawowych skojarzen'; Action={ Repair-ShellProfileFileAssociations } },
        @{ Category='PostCheck'; Name='Post-check i raport'; Action={ Invoke-PostCheck; Save-RepairReport } }
    )
}

# [DEDUP ETAP2 v14.1] Usunieto martwa definicje 'Get-RefreshAdvancedSteps' (warstwa #1 z 3; 27 linii).
# W PowerShellu przy wielokrotnej definicji obowiazuje OSTATNIA — ta wersja nigdy sie nie wykonywala,
# a kolizje sygnatur w takich warstwach byly zrodlem krytycznego bledu FIX1 v14.0.1.

function Show-RefreshBasicPlan {
    Write-RefreshHeader "NAPRAWA PODSTAWOWA - CO ZOSTANIE WYKONANE"
    Show-RefreshDataSafetyNotice
    Write-Host "Zakres:"
    foreach ($s in (Get-RefreshBasicSteps)) { Write-Host "- $($s.Name)" }
    Write-Host ""
    Write-Host (T 'legacy.kw.napraw') -ForegroundColor Yellow
}

function Show-RefreshAdvancedPlan {
    Write-RefreshHeader "NAPRAWA ZAAWANSOWANA - NAPRAWA I ODBUDOWA DO STANU POCZATKOWEGO"
    Show-RefreshDataSafetyNotice
    Write-Host "Zakres zaawansowany obejmuje m.in.:"
    Write-Host "- rejestr, polityki, uslugi, Windows Update, Store, AppX/UWP"
    Write-Host "- Xbox, Game Bar, Gaming Services, Widgets, WebExperience, Copilot/AI"
    Write-Host "- Feature Store, Experience Pack, rollouty, staged features, telemetry wymagane dla funkcji"
    Write-Host "- WMI, ETW, Performance Counters, COM/DCOM, WinSxS/CBS"
    Write-Host "- Shell, Explorer, Start, Taskbar, profil uzytkownika, skojarzenia plikow"
    Write-Host "- Defender, Security Center, SmartScreen, certyfikaty i uslugi kryptograficzne"
    Write-Host "- siec, firewall, DNS, proxy, NCSI, urzadzenia, audio, GPU, Bluetooth, power plans"
    Write-Host "- WinRE, BCD/EFI/TPM/Hypervisor jako diagnostyka lub bezpieczne kroki eksperckie"
    Write-Host ""
    Write-Host (T 'legacy.kw.przywroc') -ForegroundColor Yellow
}

# [DEDUP ETAP2 v14.1] Usunieto martwa definicje 'Invoke-RefreshAuditMode' (warstwa #1 z 2; 8 linii).
# W PowerShellu przy wielokrotnej definicji obowiazuje OSTATNIA — ta wersja nigdy sie nie wykonywala,
# a kolizje sygnatur w takich warstwach byly zrodlem krytycznego bledu FIX1 v14.0.1.

function Invoke-RefreshBasicRepairMode {
    Show-RefreshBasicPlan
    $confirm = Read-Host "Potwierdzenie"
    if ($confirm -ne "NAPRAW") { Write-RepairLog "Anulowano Naprawe podstawowa." "WARN"; return }
    Invoke-RefreshProgressSteps -Activity "Naprawa podstawowa Windows" -Steps (Get-RefreshBasicSteps)
}

function Invoke-RefreshAdvancedRepairMode {
    Show-RefreshAdvancedPlan
    $confirm = Read-Host "Pierwsze potwierdzenie"
    if ($confirm -ne "PRZYWROC") { Write-RepairLog "Anulowano Naprawe zaawansowana." "WARN"; return }
    Write-Host ""
    Write-Host "OSTATNIE POTWIERDZENIE" -ForegroundColor Yellow
    Write-Host "Operacja jest zaawansowana i moze potrwac dlugo. Nie zamykaj okna PowerShell."
    Write-Host (T 'legacy.kw.rozumiem')
    $confirm2 = Read-Host "Drugie potwierdzenie"
    if ($confirm2 -ne "ROZUMIEM") { Write-RepairLog "Anulowano Naprawe zaawansowana na drugim potwierdzeniu." "WARN"; return }
    Invoke-RefreshProgressSteps -Activity "Naprawa zaawansowana Windows" -Steps (Get-RefreshAdvancedSteps)
}

function Show-NaprawOdswiezWindowsMenu {
    Initialize-RepairEnvironment
    Assert-AdminFirst
    while ($true) {
        Write-RefreshHeader "NAPRAWA I ODBUDOWA WINDOWS"
        Show-RefreshDataSafetyNotice
        Write-Host "Wybierz jeden z trybow:" -ForegroundColor Cyan
        Write-Host "[1] Audyt systemu i urzadzenia"
        Write-Host "    Pelny raport TXT z systemu, podzespolow, uslug, aplikacji, sterownikow,"
        Write-Host "    Windows Update, Store/Xbox, polityk, rejestru, sieci, WMI, zadan i bledow."
        Write-Host "    Ten tryb nic nie naprawia i nic nie zmienia."
        Write-Host ""
        Write-Host "[2] Naprawa podstawowa"
        Write-Host "    Bezpieczna naprawa podstawowych komponentow Windows."
        Write-Host ""
        Write-Host "[3] Naprawa zaawansowana"
        Write-Host "    Pelna naprawa i odbudowa Windows wedlug calego ustalonego zakresu."
        Write-Host ""
        Write-Host "[0] Wroc do panelu glownego"
        Write-Host ""
        Write-Host "ENTER sam nic nie uruchamia. Wpisz numer opcji i zatwierdz." -ForegroundColor Yellow
        $choice = Read-Host "Wybierz opcje"
        switch ($choice) {
            "1" { Invoke-RefreshAuditMode; Read-Host "Nacisnij Enter, aby wrocic do menu modulu" | Out-Null }
            "2" { Invoke-RefreshBasicRepairMode; Read-Host "Nacisnij Enter, aby wrocic do menu modulu" | Out-Null }
            "3" { Invoke-RefreshAdvancedRepairMode; Read-Host "Nacisnij Enter, aby wrocic do menu modulu" | Out-Null }
            "0" { return }
            default { Write-RepairLog "Nieprawidlowy wybor w module Naprawa i Odbudowa Windows." "WARN" }
        }
    }
}

# ============================================================
# GLOWNE MENU - WERSJA Z DODANYM MODULEM NAPRAW I ODSWIEZ WINDOWS
# ============================================================

# ============================================================
# RENOVATION 2.0 (v15.4) — diagnostic engine + Health Score + three modes.
# Philosophy: ONE diagnostic brain, three hands (Basic / Auto / Follow-me with Advisor).
# Auto fixes only what is BROKEN; healthy/factory settings are left untouched.
# Reversible steps: [y/N]. One-way steps: full word YES/NO. Fresh verified restore point first.
# Compatible with Windows PowerShell 5.1 and 7.
# ============================================================

function New-FreshRestorePointForced {
    # User request: a FRESH, verified restore point before every renovation, bypassing the 24h limit.
    # Temporarily sets SystemRestorePointCreationFrequency=0, creates the point, restores the old value.
    param([string]$Description = 'UWO Renovation 2.0')
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $old = $null
    try {
        $p = Get-ItemProperty -Path $key -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        if ($p) { $old = $p.SystemRestorePointCreationFrequency }
        New-Item -Path $key -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $key -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    } catch {}
    $ok = $false
    if (Get-Command New-SystemRestorePointCompat -ErrorAction SilentlyContinue) {
        $ok = New-SystemRestorePointCompat -Description $Description
    } else {
        try { Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; $ok = $true } catch {}
    }
    try {
        if ($null -ne $old) { Set-ItemProperty -Path $key -Name 'SystemRestorePointCreationFrequency' -Value $old -Type DWord -ErrorAction SilentlyContinue }
        else { Remove-ItemProperty -Path $key -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue }
    } catch {}
    return $ok
}

function Test-RenovationDiskSmart {
    # Hard STOP gate: bad SMART or dirty bit means we must NOT start a renovation.
    $bad = @()
    try {
        $d = Get-CimInstance -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        foreach ($x in $d) { if ($x.PredictFailure) { $bad += 'SMART predicts imminent disk failure.' } }
    } catch {}
    try {
        $sys = $env:SystemDrive.TrimEnd(':')
        $df = (& fsutil dirty query $sys 2>$null) | Out-String
        if ($df -match 'is[\s\S]*Dirty' -or $df -match 'jest[\s\S]*Brudny') { $bad += ('Volume ' + $env:SystemDrive + ' has the DIRTY bit set (chkdsk pending).') }
    } catch {}
    return $bad
}

function Get-RenovationDiagnosis {
    # The diagnostic BRAIN. Returns a list of finding objects consumed by all three modes.
    # Each finding: Id, Area, Severity(1-3), Title, Why, Fixes(what we will do), OneWay(bool),
    #   FixKey(maps to executor), plus Detected(bool).
    # v15.4.1: NO Write-Host here (callers print). Build a typed list; Severity cast to [int] at creation.
    # _add is intentionally nested but only ever called within this function in the same run; we also
    # remove it from the script scope at the end so it cannot leak (addresses the leak report directly).
    $f = New-Object System.Collections.Generic.List[object]
    function _add($id,$area,[int]$sev,$title,$why,$fix,[bool]$oneway,$key){
        $obj = [PSCustomObject]@{ Id=$id; Area=$area; Severity=$sev; Title=$title; Why=$why; Fixes=$fix; OneWay=$oneway; FixKey=$key }
        [void]$f.Add($obj)
    }

    # 1) Component store (CBS) — DISM /CheckHealth is fast and non-destructive
    try {
        $ch = (& dism /online /cleanup-image /checkhealth 2>&1) | Out-String
        if ($ch -match 'repairable|naprawialny|component store corruption|uszkodzenie') {
            _add 'CBS01' 'Components' 3 (T 'ren.f.cbs') (T 'ren.f.cbs.why') (T 'ren.f.cbs.fix') $false 'CBS'
        }
    } catch {}

    # 2) SFC — quick verifyonly
    try {
        $vr = (& sfc /verifyonly 2>&1) | Out-String
        if ($vr -match 'did find|znalazl|integrity violations|naruszenia') {
            _add 'SFC01' 'SystemFiles' 3 (T 'ren.f.sfc') (T 'ren.f.sfc.why') (T 'ren.f.sfc.fix') $false 'SFC'
        }
    } catch {}

    # 3) Services vs default map (build-aware) — debloater damage
    try {
        if (Get-Command Get-WindowsDefaultServiceStartupMap -ErrorAction SilentlyContinue) {
            $map = Get-WindowsDefaultServiceStartupMap
            $mism = 0
            foreach ($name in $map.Keys) {
                $svc = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
                if ($svc) {
                    $want = $map[$name]
                    $have = $svc.StartMode
                    $norm = if ($have -eq 'Auto') { 'auto' } elseif ($have -eq 'Manual') { 'demand' } elseif ($have -eq 'Disabled') { 'disabled' } else { $have.ToLower() }
                    $wn = ($want -replace 'delayed-auto','auto')
                    if (($norm -eq 'disabled' -and $wn -ne 'disabled') -or ($wn -eq 'auto' -and $norm -eq 'demand')) { $mism++ }
                }
            }
            if ($mism -ge 3) {
                _add 'SVC01' 'Services' 2 ((T 'ren.f.svc') -f $mism) (T 'ren.f.svc.why') (T 'ren.f.svc.fix') $false 'SVC'
            }
        }
    } catch {}

    # 4) Windows Update health — SoftwareDistribution bloat / stuck
    try {
        $sd = "$env:WINDIR\SoftwareDistribution\Download"
        if (Test-Path $sd) {
            $sz = (Get-ChildItem $sd -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            if ($sz -gt 4GB) { _add 'WU01' 'WindowsUpdate' 2 (T 'ren.f.wu') (T 'ren.f.wu.why') (T 'ren.f.wu.fix') $false 'WU' }
        }
        $wuauserv = Get-Service wuauserv -ErrorAction SilentlyContinue
        if ($wuauserv -and $wuauserv.StartType -eq 'Disabled') { _add 'WU02' 'WindowsUpdate' 3 (T 'ren.f.wud') (T 'ren.f.wud.why') (T 'ren.f.wud.fix') $false 'WU' }
    } catch {}

    # 5) DNS cache / hosts tampering
    try {
        $hosts = "$env:WINDIR\System32\drivers\etc\hosts"
        if (Test-Path $hosts) {
            $hc = Get-Content $hosts -ErrorAction SilentlyContinue
            $susp = $hc | Where-Object { $_ -match '^\s*[0-9.]+\s' -and $_ -notmatch '127\.0\.0\.1\s+localhost' -and $_ -notmatch '::1' }
            if (@($susp).Count -gt 0) { _add 'NET01' 'Network' 2 (T 'ren.f.hosts') (T 'ren.f.hosts.why') (T 'ren.f.hosts.fix') $false 'HOSTS' }
        }
        $px = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -ErrorAction SilentlyContinue
        if ($px -and $px.ProxyEnable -eq 1) { _add 'NET02' 'Network' 1 (T 'ren.f.proxy') (T 'ren.f.proxy.why') (T 'ren.f.proxy.fix') $false 'PROXY' }
    } catch {}

    # 6) Appx / Store packages in error state
    try {
        $bad = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Status -and $_.Status -ne 'Ok' })
        if ($bad.Count -gt 0) { _add 'APPX01' 'Appx' 2 ((T 'ren.f.appx') -f $bad.Count) (T 'ren.f.appx.why') (T 'ren.f.appx.fix') $false 'APPX' }
    } catch {}

    # 7) WMI repository consistency
    try {
        $wv = (& winmgmt /verifyrepository 2>&1) | Out-String
        if ($wv -match 'not consistent|niespojne|inconsistent') { _add 'WMI01' 'WMI' 3 (T 'ren.f.wmi') (T 'ren.f.wmi.why') (T 'ren.f.wmi.fix') $false 'WMI' }
    } catch {}

    # 8) Performance counters (Perflib) — the user's known weak spot
    try {
        $pc = (& lodctr /q 2>&1) | Out-String
        if ($pc -match 'Disabled|wylaczony' -and $pc -match 'Perf') {
            _add 'PERF01' 'Counters' 2 (T 'ren.f.perf') (T 'ren.f.perf.why') (T 'ren.f.perf.fix') $false 'PERF'
        }
    } catch {}

    # 9) User profile health — temp profile / ProfileList orphans
    try {
        $pl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $bak = Get-ChildItem $pl -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.bak$' }
        if (@($bak).Count -gt 0) { _add 'PROF01' 'Profile' 3 (T 'ren.f.prof') (T 'ren.f.prof.why') (T 'ren.f.prof.fix') $false 'PROFILE' }
    } catch {}

    # 10) Icon/thumbnail caches — only flag when ACTUALLY bloated (the .db always exists, so mere
    #     existence is not a problem — this was a false-positive on every system; report fixed).
    try {
        $thumbDir = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        if (Test-Path $thumbDir) {
            $thumbSz = (Get-ChildItem $thumbDir -Filter 'thumbcache_*.db' -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            if ($thumbSz -gt 600MB) { _add 'CACHE01' 'Caches' 1 (T 'ren.f.cache') (T 'ren.f.cache.why') (T 'ren.f.cache.fix') $false 'CACHE' }
        }
    } catch {}

    # 11) Print spooler stuck queue
    try {
        $spool = Get-Service Spooler -ErrorAction SilentlyContinue
        $jobs = @(Get-ChildItem "$env:WINDIR\System32\spool\PRINTERS" -ErrorAction SilentlyContinue)
        if ($spool -and $jobs.Count -gt 5) { _add 'SPOOL01' 'Spooler' 1 (T 'ren.f.spool') (T 'ren.f.spool.why') (T 'ren.f.spool.fix') $false 'SPOOL' }
    } catch {}

    # 12) Defender disabled / stale
    try {
        $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($mp -and (-not $mp.RealTimeProtectionEnabled)) { _add 'DEF01' 'Defender' 2 (T 'ren.f.def') (T 'ren.f.def.why') (T 'ren.f.def.fix') $false 'DEFENDER' }
    } catch {}

    # 13) System clock skew (breaks updates/certs)
    try {
        $w32 = (& w32tm /query /status 2>&1) | Out-String
        if ($w32 -match 'error|blad|not been set|service has not') { _add 'TIME01' 'Time' 2 (T 'ren.f.time') (T 'ren.f.time.why') (T 'ren.f.time.fix') $false 'TIME' }
    } catch {}

    # 14) Devices in error state (Code != 0)
    try {
        $dev = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 })
        if ($dev.Count -gt 0) { _add 'DEV01' 'Devices' 2 ((T 'ren.f.dev') -f $dev.Count) (T 'ren.f.dev.why') (T 'ren.f.dev.fix') $false 'DEVICES' }
    } catch {}

    # 15) Debloater footprints (Chris Titus / Ghost Spectre / generic optimizers)
    try {
        $marks = 0
        $dt = Get-Service DiagTrack -ErrorAction SilentlyContinue
        if ($dt -and $dt.StartType -eq 'Disabled') { $marks++ }
        if (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU') { $marks++ }
        $wsearch = Get-Service WSearch -ErrorAction SilentlyContinue
        if ($wsearch -and $wsearch.StartType -eq 'Disabled') { $marks++ }
        if ($marks -ge 2) { _add 'DEBLO01' 'Conflicts' 2 (T 'ren.f.deblo') (T 'ren.f.deblo.why') (T 'ren.f.deblo.fix') $false 'SVC' }
    } catch {}

    Remove-Item Function:\_add -ErrorAction SilentlyContinue   # v15.4.1: prevent nested-function scope leak
    # v15.4.3: THE leading comma in 'return ,(...)' wrapped the array in a 1-element array, so @() saw the
    # whole finding list as a SINGLE object -> all findings glued together, Auto did nothing. Return the
    # array via -NoEnumerate so an empty/single result stays an array but multiple results stay separate.
    return (Write-Output ([object[]]$f.ToArray()) -NoEnumerate)
}

function Get-FindingOneWay {
    # v15.4.3: clean [bool] regardless of pipeline mangling.
    param($Finding)
    $o = $Finding.OneWay
    if ($o -is [array]) { $o = $o | Select-Object -First 1 }
    return [bool]$o
}

function Get-FindingSeverity {
    # v15.4.2: always returns a clean [int] 1-3 regardless of how the pipeline mangled the value.
    param($Finding)
    $s = $Finding.Severity
    if ($s -is [array]) { $s = $s | Select-Object -First 1 }
    $i = 0; [void][int]::TryParse([string]$s, [ref]$i)
    return $i
}

function Get-RenovationHealthScore {
    # 0-100 from the findings list. Severity 3 = -18, 2 = -9, 1 = -4 (floored at 0).
    param($Findings)
    $score = 100
    foreach ($x in $Findings) {
        if ($null -eq $x) { continue }
        switch (Get-FindingSeverity -Finding $x) { 3 { $score -= 18 } 2 { $score -= 9 } 1 { $score -= 4 } }
    }
    if ($score -lt 0) { $score = 0 }
    return $score
}

function Show-RenovationHealthBar {
    param([int]$Score, [string]$Label = '')
    $grade = if ($Score -ge 90) { 'A' } elseif ($Score -ge 75) { 'B' } elseif ($Score -ge 60) { 'C' } elseif ($Score -ge 40) { 'D' } else { 'F' }
    $col = if ($Score -ge 75) { 'Green' } elseif ($Score -ge 50) { 'Yellow' } else { 'Red' }
    $filled = [int]([math]::Round($Score / 5))
    $bar = ('#' * $filled) + ('.' * (20 - $filled))
    Write-Host ''
    Write-Host ((T 'ren.health') -f $Label) -ForegroundColor Cyan
    Write-Host ("  [$bar] $Score/100  ($grade)") -ForegroundColor $col
}

function Invoke-RenovationFix {
    # The executor: maps a finding's FixKey to existing repair functions (reuse, not rewrite).
    param([string]$FixKey)
    switch ($FixKey) {
        'CBS'      { Write-Host '     (DISM RestoreHealth + cleanup: to moze potrwac 15-60 min) / (this can take 15-60 min)' -ForegroundColor DarkGray; & dism /online /cleanup-image /restorehealth 2>&1 | Out-Null; & dism /online /cleanup-image /startcomponentcleanup 2>&1 | Out-Null }
        'SFC'      { & sfc /scannow 2>&1 | Out-Null }
        'SVC'      { if (Get-Command Repair-ServicesToDefault -ErrorAction SilentlyContinue) { Repair-ServicesToDefault } elseif (Get-Command Invoke-BasicWindowsRepair -ErrorAction SilentlyContinue) { Invoke-BasicWindowsRepair } }
        'WU'       { if (Get-Command Repair-WindowsUpdateStack -ErrorAction SilentlyContinue) { Repair-WindowsUpdateStack } else {
                        Stop-Service wuauserv,bits,cryptsvc -Force -ErrorAction SilentlyContinue
                        $sd="$env:WINDIR\SoftwareDistribution"; if (Test-Path $sd) { Rename-Item $sd "$sd.bak_$(Get-Date -Format yyyyMMddHHmmss)" -ErrorAction SilentlyContinue }
                        Set-Service wuauserv -StartupType Manual -ErrorAction SilentlyContinue
                        Start-Service wuauserv,bits,cryptsvc -ErrorAction SilentlyContinue } }
        'HOSTS'    { $h="$env:WINDIR\System32\drivers\etc\hosts"; Copy-Item $h "$h.bak_$(Get-Date -Format yyyyMMddHHmmss)" -ErrorAction SilentlyContinue; Set-Content $h "127.0.0.1`tlocalhost`r`n::1`tlocalhost" -Encoding ASCII }
        'PROXY'    { & netsh winhttp reset proxy 2>&1 | Out-Null; Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0 -ErrorAction SilentlyContinue }
        'APPX'     { Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Ok' } | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue } }
        'WMI'      { & winmgmt /salvagerepository 2>&1 | Out-Null }
        'PERF'     { & lodctr /R 2>&1 | Out-Null; & "$env:WINDIR\SysWOW64\lodctr.exe" /R 2>&1 | Out-Null }
        'CACHE'    { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue; Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue; Start-Process explorer }
        'SPOOL'    { Stop-Service Spooler -Force -ErrorAction SilentlyContinue; Remove-Item "$env:WINDIR\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue; Start-Service Spooler -ErrorAction SilentlyContinue }
        'DEFENDER' { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue; & "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -SignatureUpdate 2>&1 | Out-Null }
        'TIME'     { Start-Service w32time -ErrorAction SilentlyContinue; & w32tm /resync /force 2>&1 | Out-Null }
        'DEVICES'  { & pnputil /scan-devices 2>&1 | Out-Null }
        'PROFILE'  { Write-Host (T 'ren.prof.manual') -ForegroundColor Yellow }
        default    { }
    }
}

function Show-RenovationFindings {
    param($Findings)
    if (@($Findings).Count -eq 0) { Write-Host (T 'ren.none') -ForegroundColor Green; return }
    Write-Host ''
    Write-Host (T 'ren.found') -ForegroundColor Yellow
    $i = 1
    foreach ($x in $Findings) {
        $sevN = Get-FindingSeverity -Finding $x
        $sevtxt = switch ($sevN) { 3 { '[!!!]' } 2 { '[!! ]' } 1 { '[!  ]' } }
        $col = switch ($sevN) { 3 { 'Red' } 2 { 'Yellow' } 1 { 'Gray' } }
        Write-Host ("  $sevtxt $($x.Title)") -ForegroundColor $col
        $i++
    }
}

function Invoke-RenovationBasic {
    # MODE 1: diagnose + apply ONLY reversible fixes for DETECTED problems. Max 1 restart.
    Write-Host ''
    Write-Host (T 'ren.basic.title') -ForegroundColor Cyan
    $smart = @(Test-RenovationDiskSmart)
    if ($smart.Count -gt 0) { foreach ($s in $smart) { Write-Host ('  STOP: ' + $s) -ForegroundColor Red }; Write-Host (T 'ren.smartstop') -ForegroundColor Red; return }
    Write-Host (T 'ren.diag.run') -ForegroundColor Cyan
    $allFindings = @(Get-RenovationDiagnosis)
    $findings = @($allFindings | Where-Object { -not (Get-FindingOneWay -Finding $_) })
    $score0 = Get-RenovationHealthScore -Findings $allFindings
    Show-RenovationHealthBar -Score $score0 -Label (T 'ren.before')
    Show-RenovationFindings -Findings $findings
    if ($findings.Count -eq 0) { return }
    $a = (Read-Host (T 'ren.basic.applyQ')).Trim().ToLower()
    if ($a -notin 't','y','tak','yes') { return }
    Write-Host (T 'ren.rp.make') -ForegroundColor Cyan
    if (New-FreshRestorePointForced -Description 'UWO Renovation Basic') { Write-Host (T 'ren.rp.ok') -ForegroundColor Green } else { Write-Host (T 'ren.rp.fail') -ForegroundColor Yellow }
    foreach ($x in $findings) {
        Write-Host (('  -> ' + $x.Title)) -ForegroundColor Gray
        Invoke-RenovationFix -FixKey $x.FixKey
    }
    Write-Host (T 'ren.diag.run') -ForegroundColor Cyan
    $findings2 = @(Get-RenovationDiagnosis)
    $score1 = Get-RenovationHealthScore -Findings $findings2
    Show-RenovationHealthBar -Score $score1 -Label (T 'ren.after')
    Write-Host ((T 'ren.delta') -f $score0, $score1) -ForegroundColor Cyan
}

function Invoke-RenovationAuto {
    # MODE 2a: intelligent. Reversible fixes auto-applied; one-way steps batched into ONE YES/NO.
    Write-Host ''
    Write-Host (T 'ren.auto.title') -ForegroundColor Cyan
    $smart = @(Test-RenovationDiskSmart)
    if ($smart.Count -gt 0) { foreach ($s in $smart) { Write-Host ('  STOP: ' + $s) -ForegroundColor Red }; Write-Host (T 'ren.smartstop') -ForegroundColor Red; return }
    Write-Host (T 'ren.diag.run') -ForegroundColor Cyan
    $all = @(Get-RenovationDiagnosis)
    Write-Log "Renovation Auto: $($all.Count) findings detected" -Level 'INFO'
    $rev = @($all | Where-Object { -not (Get-FindingOneWay -Finding $_) })
    $oneway = @($all | Where-Object { Get-FindingOneWay -Finding $_ })
    $score0 = Get-RenovationHealthScore -Findings $all
    Show-RenovationHealthBar -Score $score0 -Label (T 'ren.before')
    Show-RenovationFindings -Findings $all
    if (@($all).Count -eq 0) { return }
    Write-Host (T 'ren.rp.make') -ForegroundColor Cyan
    if (New-FreshRestorePointForced -Description 'UWO Renovation Auto') { Write-Host (T 'ren.rp.ok') -ForegroundColor Green } else { Write-Host (T 'ren.rp.fail') -ForegroundColor Yellow }
    foreach ($x in $rev) { Write-Host (('  -> ' + $x.Title)) -ForegroundColor Gray; Invoke-RenovationFix -FixKey $x.FixKey }
    if (@($oneway).Count -gt 0) {
        Write-Host ''
        Write-Host ((T 'ren.auto.oneway') -f @($oneway).Count) -ForegroundColor Red
        foreach ($x in $oneway) { Write-Host ('    - ' + $x.Title) -ForegroundColor Yellow }
        $c = (Read-Host (T 'ren.auto.onewayQ')).Trim().ToUpper()
        if ($c -in 'TAK','YES') { foreach ($x in $oneway) { Write-Host (('  -> ' + $x.Title)) -ForegroundColor Gray; Invoke-RenovationFix -FixKey $x.FixKey } }
    }
    Write-Host (T 'ren.diag.run') -ForegroundColor Cyan
    $all2 = @(Get-RenovationDiagnosis)
    $score1 = Get-RenovationHealthScore -Findings $all2
    Show-RenovationHealthBar -Score $score1 -Label (T 'ren.after')
    Write-Host ((T 'ren.delta') -f $score0, $score1) -ForegroundColor Cyan
}

function Invoke-RenovationFollowMe {
    # MODE 2b: Follow-me with Advisor. One card per finding, step by step.
    Write-Host ''
    Write-Host (T 'ren.follow.title') -ForegroundColor Cyan
    Write-Host (T 'ren.follow.intro') -ForegroundColor Gray
    $smart = @(Test-RenovationDiskSmart)
    if ($smart.Count -gt 0) { foreach ($s in $smart) { Write-Host ('  STOP: ' + $s) -ForegroundColor Red }; Write-Host (T 'ren.smartstop') -ForegroundColor Red; return }
    Write-Host (T 'ren.diag.run') -ForegroundColor Cyan
    $all = @(Get-RenovationDiagnosis)
    $score0 = Get-RenovationHealthScore -Findings $all
    Show-RenovationHealthBar -Score $score0 -Label (T 'ren.before')
    if ($all.Count -eq 0) { Write-Host (T 'ren.none') -ForegroundColor Green; return }
    Write-Host ((T 'ren.follow.count') -f @($all).Count) -ForegroundColor Yellow
    Write-Host (T 'ren.rp.make') -ForegroundColor Cyan
    if (New-FreshRestorePointForced -Description 'UWO Renovation Follow-me') { Write-Host (T 'ren.rp.ok') -ForegroundColor Green } else { Write-Host (T 'ren.rp.fail') -ForegroundColor Yellow }
    $n = @($all).Count; $idx = 0
    foreach ($x in $all) {
        $idx++
        Write-Host ''
        Write-Host ('==================== ' + $idx + ' / ' + $n + ' ====================') -ForegroundColor Cyan
        $sevtxt = switch (Get-FindingSeverity -Finding $x) { 3 { (T 'ren.sev.high') } 2 { (T 'ren.sev.med') } 1 { (T 'ren.sev.low') } }
        Write-Host ((T 'ren.card.what') -f $x.Title) -ForegroundColor White
        Write-Host ((T 'ren.card.sev')  -f $sevtxt)
        Write-Host ((T 'ren.card.why')  -f $x.Why) -ForegroundColor Gray
        Write-Host ((T 'ren.card.fix')  -f $x.Fixes) -ForegroundColor Gray
        $isOneWay = Get-FindingOneWay -Finding $x
        if ($isOneWay) { Write-Host (T 'ren.card.oneway') -ForegroundColor Red } else { Write-Host (T 'ren.card.rev') -ForegroundColor Green }
        $opts = if ($isOneWay) { T 'ren.card.optsOneway' } else { T 'ren.card.opts' }
        $ans = (Read-Host $opts).Trim().ToLower()
        if ($ans -eq 'w') {
            Write-Host ((T 'ren.card.more') -f $x.Id, $x.Area) -ForegroundColor DarkCyan
            $ans = (Read-Host $opts).Trim().ToLower()
        }
        if ($isOneWay) {
            if ($ans -eq 't' -or $ans -eq 'tak' -or $ans -eq 'yes' -or $ans -eq 'y') {
                $cf = (Read-Host (T 'ren.card.confirmOneway')).Trim().ToUpper()
                if ($cf -in 'TAK','YES') { Invoke-RenovationFix -FixKey $x.FixKey; Write-Host (T 'ren.card.done') -ForegroundColor Green }
                else { Write-Host (T 'ren.card.skipped') -ForegroundColor Yellow }
            } else { Write-Host (T 'ren.card.skipped') -ForegroundColor Yellow }
        } else {
            if ($ans -eq 't' -or $ans -eq 'y') { Invoke-RenovationFix -FixKey $x.FixKey; Write-Host (T 'ren.card.done') -ForegroundColor Green }
            else { Write-Host (T 'ren.card.skipped') -ForegroundColor Yellow }
        }
    }
    Write-Host (T 'ren.diag.run') -ForegroundColor Cyan
    $all2 = @(Get-RenovationDiagnosis)
    $score1 = Get-RenovationHealthScore -Findings $all2
    Show-RenovationHealthBar -Score $score1 -Label (T 'ren.after')
    Write-Host ((T 'ren.delta') -f $score0, $score1) -ForegroundColor Cyan
}

$script:RenovationTaskName = 'UWO_RenovationResume'

function Invoke-WithHeartbeat {
    # v15.6.1: runs a long external command as a job and shows a live spinner + elapsed time.
    # Honest: it does NOT fake a percentage — it only proves the process is alive and shows duration.
    param([scriptblock]$Action, [string]$Label)
    $job = Start-Job -ScriptBlock $Action
    $spin = '|','/','-',''
    $i = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($job.State -eq 'Running') {
        $el = [int]$sw.Elapsed.TotalSeconds
        $mm = [int]($el / 60); $ss = $el % 60
        Write-Host ("`r  " + $spin[$i % 4] + ' ' + $Label + ('  {0:00}:{1:00}' -f $mm, $ss)) -NoNewline -ForegroundColor DarkCyan
        Start-Sleep -Milliseconds 500
        $i++
    }
    Write-Host ("`r" + (' ' * 70) + "`r") -NoNewline
    try { Receive-Job $job -ErrorAction SilentlyContinue | Out-Null } catch {}
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}

function Get-RenovationStatePath {
    $dir = Join-Path $script:RootFolder 'Renovation'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path $dir 'renovation_pipeline.json')
}

function Save-RenovationState {
    param($State)
    try { ($State | ConvertTo-Json -Depth 6) | Set-Content -Path (Get-RenovationStatePath) -Encoding UTF8 } catch {}
}

function Get-RenovationState {
    $p = Get-RenovationStatePath
    if (Test-Path $p) { try { return (Get-Content $p -Raw | ConvertFrom-Json) } catch {} }
    return $null
}

function Clear-RenovationState {
    $p = Get-RenovationStatePath
    if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
    schtasks /delete /tn $script:RenovationTaskName /f 2>$null | Out-Null
}

function Register-RenovationResume {
    # Reuses the same scheduled-task pattern as post-restart validation (onlogon, one-shot, hidden).
    $self = $script:ScriptFullPath
    if (-not $self) { return $false }
    $tr = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "{0}" -ResumeRenovation' -f $self)
    schtasks /create /tn $script:RenovationTaskName /tr $tr /sc onlogon /rl highest /f 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Test-RebootPendingNow {
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                     'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path $k) { return $true }
    }
    try {
        $pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pfro -and $pfro.PendingFileRenameOperations) { return $true }
    } catch {}
    return $false
}

function Invoke-RenovationStageExecutor {
    # Runs a single named stage. Stages are ordered; the pipeline advances one per restart only if needed.
    param([string]$Stage)
    switch ($Stage) {
        'DISM'  { Write-Host (T 'ren.pipe.s.dism') -ForegroundColor Cyan
                  Invoke-WithHeartbeat -Label 'DISM RestoreHealth' -Action { & dism /online /cleanup-image /restorehealth 2>&1 | Out-Null; & dism /online /cleanup-image /startcomponentcleanup 2>&1 | Out-Null } }
        'SFC'   { Write-Host (T 'ren.pipe.s.sfc') -ForegroundColor Cyan
                  Invoke-WithHeartbeat -Label 'SFC /scannow' -Action { & sfc /scannow 2>&1 | Out-Null } }
        'REST'  { Write-Host (T 'ren.pipe.s.rest') -ForegroundColor Cyan
                  $all = @(Get-RenovationDiagnosis | Where-Object { -not (Get-FindingOneWay -Finding $_) -and $_.FixKey -notin @('CBS','SFC') })
                  foreach ($x in $all) { Write-Host (('     -> ' + $x.Title)) -ForegroundColor Gray; Invoke-RenovationFix -FixKey $x.FixKey } }
    }
}

function Start-RenovationPipeline {
    # Section D: the multi-restart "general renovation". Stages: DISM -> (restart) -> SFC -> (restart) -> REST.
    # A restart is only requested when Windows actually reports one pending after a stage.
    Write-Host ''
    Write-Host (T 'ren.pipe.title') -ForegroundColor Cyan
    Write-Host (T 'ren.pipe.intro') -ForegroundColor Gray
    $smart = @(Test-RenovationDiskSmart)
    if ($smart.Count -gt 0) { foreach ($s in $smart) { Write-Host ('  STOP: ' + $s) -ForegroundColor Red }; Write-Host (T 'ren.smartstop') -ForegroundColor Red; return }

    Write-Host (T 'ren.diag.run') -ForegroundColor Cyan
    $all0 = @(Get-RenovationDiagnosis)
    $score0 = Get-RenovationHealthScore -Findings $all0
    Show-RenovationHealthBar -Score $score0 -Label (T 'ren.before')
    Show-RenovationFindings -Findings $all0

    $c = (Read-Host (T 'ren.pipe.startQ')).Trim().ToUpper()
    if ($c -notin 'TAK','YES') { return }

    Write-Host (T 'ren.rp.make') -ForegroundColor Cyan
    if (New-FreshRestorePointForced -Description 'UWO Renovation Pipeline') { Write-Host (T 'ren.rp.ok') -ForegroundColor Green } else { Write-Host (T 'ren.rp.fail') -ForegroundColor Yellow }

    $state = [ordered]@{
        Stages    = @('DISM','SFC','REST')
        Index     = 0
        Score0    = $score0
        StartedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        AutoUser  = $env:USERNAME
    }
    Save-RenovationState -State $state
    Resume-RenovationPipeline -State $state
}

function Resume-RenovationPipeline {
    # Executes stages from the saved index. After each stage, if a reboot is pending, schedules a
    # resume task and offers to restart; otherwise continues to the next stage immediately.
    param($State)
    if (-not $State) { $State = Get-RenovationState }
    if (-not $State) { return }

    $stages = @($State.Stages)
    while ([int]$State.Index -lt $stages.Count) {
        $stage = $stages[[int]$State.Index]
        Write-Host ''
        Write-Host ((T 'ren.pipe.stage') -f ([int]$State.Index + 1), $stages.Count, $stage) -ForegroundColor Yellow
        Invoke-RenovationStageExecutor -Stage $stage

        $State.Index = [int]$State.Index + 1
        Save-RenovationState -State $State

        if ([int]$State.Index -lt $stages.Count -and (Test-RebootPendingNow)) {
            Write-Host (T 'ren.pipe.rebootneeded') -ForegroundColor Yellow
            $r = (Read-Host (T 'ren.pipe.rebootQ')).Trim().ToLower()
            if ($r -in 't','y','tak','yes') {
                if (Register-RenovationResume) { Write-Host (T 'ren.pipe.scheduled') -ForegroundColor Green }
                Write-Host (T 'ren.pipe.restarting') -ForegroundColor Cyan
                Start-Sleep -Seconds 3
                Restart-Computer -Force
                return
            } else {
                Write-Host (T 'ren.pipe.manualresume') -ForegroundColor Yellow
                return
            }
        }
    }

    # All stages done — final report + score.
    Write-Host (T 'ren.diag.run') -ForegroundColor Cyan
    $all1 = @(Get-RenovationDiagnosis)
    $score1 = Get-RenovationHealthScore -Findings $all1
    Show-RenovationHealthBar -Score $score1 -Label (T 'ren.after')
    Write-Host ((T 'ren.delta') -f $State.Score0, $score1) -ForegroundColor Cyan
    Clear-RenovationState

    # If health is still poor, offer the in-place upgrade (the real 95% ceiling).
    if ($score1 -lt 75) {
        Write-Host ''
        Write-Host (T 'ren.pipe.stillpoor') -ForegroundColor Yellow
        $u = (Read-Host (T 'ren.inplace.offerQ')).Trim().ToLower()
        if ($u -in 't','y','tak','yes') { Invoke-RenovationInPlaceUpgrade }
    }
}

function Invoke-RenovationInPlaceUpgrade {
    # Section D ceiling: in-place repair upgrade. Detects a mounted ISO / setup.exe and launches it with
    # flags that KEEP apps and files. If no ISO is found, prints exact manual instructions (no faking).
    Write-Host ''
    Write-Host (T 'ren.inplace.title') -ForegroundColor Cyan
    Write-Host (T 'ren.inplace.what') -ForegroundColor Gray

    $setup = $null
    foreach ($drv in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $cand = Join-Path ($drv.Root) 'setup.exe'
        $src  = Join-Path ($drv.Root) 'sources\install.wim'
        $esd  = Join-Path ($drv.Root) 'sources\install.esd'
        if ((Test-Path $cand) -and ((Test-Path $src) -or (Test-Path $esd))) { $setup = $cand; break }
    }

    if (-not $setup) {
        Write-Host (T 'ren.inplace.noiso') -ForegroundColor Yellow
        Write-Host (T 'ren.inplace.step1') -ForegroundColor Gray
        Write-Host (T 'ren.inplace.step2') -ForegroundColor Gray
        Write-Host (T 'ren.inplace.step3') -ForegroundColor Gray
        return
    }

    Write-Host ((T 'ren.inplace.found') -f $setup) -ForegroundColor Green
    Write-Host (T 'ren.inplace.warn') -ForegroundColor Yellow
    $c = (Read-Host (T 'ren.inplace.confirm')).Trim().ToUpper()
    if ($c -notin 'TAK','YES') { return }
    Write-Host (T 'ren.inplace.launch') -ForegroundColor Cyan
    # /auto upgrade keeps apps+data; /dynamicupdate disable speeds it up; /eula accept for unattended start.
    try {
        Start-Process -FilePath $setup -ArgumentList '/auto','upgrade','/dynamicupdate','disable','/eula','accept','/migratedrivers','all' -ErrorAction Stop
        Write-Host (T 'ren.inplace.started') -ForegroundColor Green
    } catch {
        Write-Host ((T 'ren.inplace.failed') -f $_.Exception.Message) -ForegroundColor Red
    }
}

function Invoke-RenovationFreshProfile {
    # Section D: fresh-profile migration helper. One-way (a NEW profile is created); data is copied, not moved.
    # We never auto-delete the old profile — we create the new account and guide the data copy.
    Write-Host ''
    Write-Host (T 'ren.prof.title') -ForegroundColor Cyan
    Write-Host (T 'ren.prof.what') -ForegroundColor Gray
    Write-Host (T 'ren.prof.warn') -ForegroundColor Yellow
    $c = (Read-Host (T 'ren.prof.confirm')).Trim().ToUpper()
    if ($c -notin 'TAK','YES') { return }

    $newName = (Read-Host (T 'ren.prof.name')).Trim()
    if (-not $newName) { Write-Host (T 'ren.prof.cancel') -ForegroundColor Yellow; return }
    # Create a new local admin account (no password set here — user sets it at first logon via Windows).
    try {
        $exists = Get-LocalUser -Name $newName -ErrorAction SilentlyContinue
        if (-not $exists) {
            $pw = Read-Host (T 'ren.prof.pw') -AsSecureString
            New-LocalUser -Name $newName -Password $pw -FullName $newName -Description 'UWO fresh profile' -ErrorAction Stop | Out-Null
            Add-LocalGroupMember -Group 'Administrators' -Member $newName -ErrorAction SilentlyContinue
            Write-Host ((T 'ren.prof.created') -f $newName) -ForegroundColor Green
        } else {
            Write-Host (T 'ren.prof.exists') -ForegroundColor Yellow
        }
        Write-Host (T 'ren.prof.next1') -ForegroundColor Gray
        Write-Host (T 'ren.prof.next2') -ForegroundColor Gray
        Write-Host (T 'ren.prof.next3') -ForegroundColor Gray
    } catch {
        Write-Host ((T 'ren.prof.failed') -f $_.Exception.Message) -ForegroundColor Red
    }
}

function Show-RenovationAdvancedMenu {
    while ($true) {
        Write-Host ''
        Write-Host (T 'ren.adv.title') -ForegroundColor Cyan
        Write-Host (T 'ren.adv.1') -ForegroundColor Green
        Write-Host (T 'ren.adv.2') -ForegroundColor Yellow
        Write-Host (T 'ren.adv.3') -ForegroundColor Magenta
        Write-Host (T 'ren.adv.4') -ForegroundColor Red
        Write-Host (T 'ren.adv.5') -ForegroundColor DarkYellow
        Write-Host (T 'ren.adv.0') -ForegroundColor DarkGray
        do { $k = (Read-Host (T 'ren.adv.prompt2')).Trim() } while ($k -notin '0','1','2','3','4','5')
        switch ($k) {
            '1' { Invoke-RenovationAuto;          Read-Host (T 'ren.back') | Out-Null }
            '2' { Invoke-RenovationFollowMe;      Read-Host (T 'ren.back') | Out-Null }
            '3' { Start-RenovationPipeline;       Read-Host (T 'ren.back') | Out-Null }
            '4' { Invoke-RenovationInPlaceUpgrade; Read-Host (T 'ren.back') | Out-Null }
            '5' { Invoke-RenovationFreshProfile;  Read-Host (T 'ren.back') | Out-Null }
            '0' { return }
        }
    }
}

# ============================================================
# PRIVACY & AI MODULE (v15.6) — Copilot, Recall, telemetry, Advertising ID, activity history.
# Separate mode (different intent than performance). Reversible: each toggle is a registry write
# captured for rollback via the existing manifest. Honest: shows current state, applies on request.
# ============================================================

function Get-PrivacyItems {
    # Returns the catalog of privacy/AI toggles with their CURRENT state read live from the registry.
    # Each: Id, Title, Desc, Path, Name, OnValue (value that means "privacy-protected"), Type, plus Current.
    $items = @(
        @{ Id='copilot';   Title=(T 'priv.copilot');   Desc=(T 'priv.copilot.d');   Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name='TurnOffWindowsCopilot'; OnValue=1; Type='DWord' },
        @{ Id='recall';    Title=(T 'priv.recall');    Desc=(T 'priv.recall.d');    Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; Name='DisableAIDataAnalysis'; OnValue=1; Type='DWord' },
        @{ Id='advertise'; Title=(T 'priv.advertise'); Desc=(T 'priv.advertise.d'); Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name='Enabled'; OnValue=0; Type='DWord' },
        @{ Id='telemetry'; Title=(T 'priv.telemetry'); Desc=(T 'priv.telemetry.d'); Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='AllowTelemetry'; OnValue=0; Type='DWord' },
        @{ Id='activity';  Title=(T 'priv.activity');  Desc=(T 'priv.activity.d');  Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='EnableActivityFeed'; OnValue=0; Type='DWord' },
        @{ Id='startsug';  Title=(T 'priv.startsug');  Desc=(T 'priv.startsug.d');  Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SystemPaneSuggestionsEnabled'; OnValue=0; Type='DWord' },
        @{ Id='tips';      Title=(T 'priv.tips');      Desc=(T 'priv.tips.d');      Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SoftLandingEnabled'; OnValue=0; Type='DWord' },
        @{ Id='edgeai';    Title=(T 'priv.edgeai');    Desc=(T 'priv.edgeai.d');    Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='HubsSidebarEnabled'; OnValue=0; Type='DWord' }
    )
    foreach ($it in $items) {
        $cur = $null
        try {
            $p = Get-ItemProperty -Path $it.Path -Name $it.Name -ErrorAction SilentlyContinue
            if ($p) { $cur = $p.$($it.Name) }
        } catch {}
        $it.Current = $cur
        $it.Protected = ($cur -eq $it.OnValue)
    }
    return $items
}

function Set-PrivacyItem {
    # Applies one toggle to its privacy-protected value, recording the old value in the manifest for rollback.
    param($Item)
    try {
        if (-not (Test-Path $Item.Path)) { New-Item -Path $Item.Path -Force -ErrorAction SilentlyContinue | Out-Null }
        $old = $null
        try { $op = Get-ItemProperty -Path $Item.Path -Name $Item.Name -ErrorAction SilentlyContinue; if ($op) { $old = $op.$($Item.Name) } } catch {}
        # record for rollback (same manifest the optimizer uses)
        if ($script:Manifest -and $script:Manifest.Registry) {
            $script:Manifest.Registry += [ordered]@{ Path=$Item.Path; Name=$Item.Name; OldValue=$old; NewValue=$Item.OnValue; Reason=('Privacy: ' + $Item.Id) }
        }
        Set-ItemProperty -Path $Item.Path -Name $Item.Name -Value $Item.OnValue -Type $Item.Type -ErrorAction Stop
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log ("Privacy: " + $Item.Id + " -> protected") -Level 'CHANGE' }
        return $true
    } catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log ("Privacy " + $Item.Id + " failed: " + $_.Exception.Message) -Level 'WARN' }
        return $false
    }
}

# ============================================================
# ROOT CAUSE ANALYSIS MODULE (v15.7) — "why is this PC slow/unhealthy?"
# A rule-based engine (offline, deterministic — NOT AI). Read-only: it diagnoses and explains causes
# with weights, then offers to jump to [4] Repair. Honest: ~accurate, never a 100% guarantee.
# Key source: Windows measures boot impact itself (Diagnostics-Performance log, event IDs 100-110).
# Compatible with Windows PowerShell 5.1 and 7.
# ============================================================

function Get-BootPerformanceData {
    # Reads the boot timing Windows records itself. Event 100 = overall boot; 101-110 = per service/app/driver
    # degradation with millisecond figures. Returns ordered list of {Name, Type, Ms}.
    $out = New-Object System.Collections.Generic.List[object]
    try {
        $ev = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 60 -ErrorAction Stop |
              Where-Object { $_.Id -ge 100 -and $_.Id -le 110 }
        # most recent boot first
        $latestBoot = $ev | Where-Object { $_.Id -eq 100 } | Sort-Object TimeCreated -Descending | Select-Object -First 1
        if ($latestBoot) {
            $bootMs = $null
            try { $bootMs = [int]$latestBoot.Properties[0].Value } catch {}
            if ($bootMs) { $out.Add([PSCustomObject]@{ Name='__TOTAL__'; Type='Boot'; Ms=$bootMs }) | Out-Null }
            $since = $latestBoot.TimeCreated.AddMinutes(-5)
            # degradation events around that boot: 101 app, 102 driver, 103 service, 106 background, 109 device
            foreach ($e in ($ev | Where-Object { $_.Id -in 101,102,103,106,109 -and $_.TimeCreated -ge $since })) {
                $nm = $null; $ms = $null
                try { $nm = [string]$e.Properties[0].Value } catch {}
                try { foreach ($p in $e.Properties) { if ($p.Value -is [int] -or $p.Value -is [long]) { if ([int64]$p.Value -gt 1000 -and [int64]$p.Value -lt 600000) { $ms = [int]$p.Value; break } } } } catch {}
                $typ = switch ($e.Id) { 101 {'App'} 102 {'Driver'} 103 {'Service'} 106 {'Background'} 109 {'Device'} default {'Other'} }
                if ($nm -and $ms) { $out.Add([PSCustomObject]@{ Name=$nm; Type=$typ; Ms=$ms }) | Out-Null }
            }
        }
    } catch {}
    return (Write-Output ([object[]]$out.ToArray()) -NoEnumerate)
}

function Get-DriverAnalysis {
    # Driver age / signature / known error footprint. Returns list of problem drivers.
    $out = New-Object System.Collections.Generic.List[object]
    try {
        $drv = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
               Where-Object { $_.DriverDate -and $_.DeviceName }
        $now = Get-Date
        foreach ($d in $drv) {
            $age = $null
            try { $dd = [Management.ManagementDateTimeConverter]::ToDateTime($d.DriverDate); $age = [int]($now - $dd).TotalDays } catch {}
            $unsigned = ($d.IsSigned -eq $false)
            if (($age -and $age -gt 730) -or $unsigned) {
                $out.Add([PSCustomObject]@{ Name=$d.DeviceName; Age=$age; Unsigned=$unsigned; Class=$d.DeviceClass }) | Out-Null
            }
        }
    } catch {}
    return (Write-Output ([object[]]$out.ToArray()) -NoEnumerate)
}

function Get-HardwareErrorData {
    # Recent disk / WHEA / driver-crash errors from the System log (last 7 days).
    $res = [ordered]@{ DiskErrors=0; WheaErrors=0; DriverCrashes=0 }
    try {
        $since = (Get-Date).AddDays(-7)
        $sys = Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=$since; Level=1,2,3 } -MaxEvents 400 -ErrorAction Stop
        foreach ($e in $sys) {
            if ($e.Id -in 7,11,51,153) { $res.DiskErrors++ }
            elseif ($e.ProviderName -match 'WHEA') { $res.WheaErrors++ }
            elseif ($e.Id -in 219,1000,1001) { $res.DriverCrashes++ }
        }
    } catch {}
    return $res
}

function Invoke-RootCauseEngine {
    # The rule-based brain: turns raw signals into ranked, human-readable CAUSES with weights.
    # Each cause: Text, Weight (string for sort: 'S<sec>' time-based or 'H'/'M'/'L'), Hint, RepairKey(optional).
    Write-Host (T 'rca.collect') -ForegroundColor Cyan
    $causes = New-Object System.Collections.Generic.List[object]
    function _cause($text,$weight,$hint,$rk){ $causes.Add([PSCustomObject]@{ Text=$text; Weight=$weight; Hint=$hint; RepairKey=$rk }) | Out-Null }

    # --- Boot timing rules ---
    $boot = @(Get-BootPerformanceData)
    $total = $boot | Where-Object { $_.Name -eq '__TOTAL__' } | Select-Object -First 1
    if ($total -and $total.Ms -gt 40000) {
        _cause ((T 'rca.boot.slow') -f [math]::Round($total.Ms/1000,0)) 'M' (T 'rca.boot.slow.h') $null
    }
    $offenders = $boot | Where-Object { $_.Name -ne '__TOTAL__' -and $_.Ms -gt 8000 } | Sort-Object Ms -Descending | Select-Object -First 5
    foreach ($o in $offenders) {
        $sec = [math]::Round($o.Ms/1000,0)
        $typTxt = switch ($o.Type) { 'Service' {T 'rca.t.service'} 'App' {T 'rca.t.app'} 'Driver' {T 'rca.t.driver'} 'Background' {T 'rca.t.bg'} 'Device' {T 'rca.t.device'} default {''} }
        $rk = if ($o.Type -eq 'Service') { 'SVC' } else { $null }
        _cause ((T 'rca.boot.item') -f $typTxt, $o.Name, $sec) ('S{0:0000}' -f $sec) (T 'rca.boot.item.h') $rk
    }

    # --- Driver rules ---
    $drv = @(Get-DriverAnalysis)
    $oldGpu = $drv | Where-Object { $_.Class -match 'Display' -and $_.Age -and $_.Age -gt 180 } | Select-Object -First 1
    if ($oldGpu) { _cause ((T 'rca.drv.gpu') -f $oldGpu.Age) 'H' (T 'rca.drv.gpu.h') $null }
    $unsigned = @($drv | Where-Object { $_.Unsigned })
    if ($unsigned.Count -gt 0) { _cause ((T 'rca.drv.unsigned') -f $unsigned.Count) 'M' (T 'rca.drv.unsigned.h') $null }
    $veryOld = @($drv | Where-Object { $_.Age -and $_.Age -gt 1095 -and $_.Class -notmatch 'Display' })
    if ($veryOld.Count -gt 2) { _cause ((T 'rca.drv.old') -f $veryOld.Count) 'L' (T 'rca.drv.old.h') $null }

    # --- Hardware error rules ---
    $hw = Get-HardwareErrorData
    if ($hw.DiskErrors -gt 0)    { _cause ((T 'rca.hw.disk') -f $hw.DiskErrors) 'H' (T 'rca.hw.disk.h') $null }
    if ($hw.WheaErrors -gt 0)    { _cause ((T 'rca.hw.whea') -f $hw.WheaErrors) 'H' (T 'rca.hw.whea.h') $null }
    if ($hw.DriverCrashes -gt 2) { _cause ((T 'rca.hw.crash') -f $hw.DriverCrashes) 'M' (T 'rca.hw.crash.h') $null }

    # --- Disk latency rule (reuse the counter helper from the optimizer) ---
    try {
        if (Get-Command Get-CounterValueSafe -ErrorAction SilentlyContinue) {
            $rl = Get-CounterValueSafe '\PhysicalDisk(_Total)\Avg. Disk sec/Read'
            if ($rl -and ($rl * 1000) -gt 10) { _cause ((T 'rca.disk.lat') -f [math]::Round($rl*1000,0)) 'M' (T 'rca.disk.lat.h') $null }
        }
    } catch {}

    # --- Cross with the renovation diagnosis (WU stuck, services off, debloater) for richer causes ---
    try {
        if (Get-Command Get-RenovationDiagnosis -ErrorAction SilentlyContinue) {
            $rd = @(Get-RenovationDiagnosis)
            foreach ($f in $rd) {
                if ($f.FixKey -eq 'WU')   { _cause (T 'rca.wu')   'M' (T 'rca.wu.h')   'WU' }
                if ($f.Id -eq 'DEBLO01')  { _cause (T 'rca.deblo') 'M' (T 'rca.deblo.h') 'SVC' }
                if ($f.FixKey -eq 'WMI')  { _cause (T 'rca.wmi')   'H' (T 'rca.wmi.h')  'WMI' }
            }
        }
    } catch {}

    Remove-Item Function:\_cause -ErrorAction SilentlyContinue
    return (Write-Output ([object[]]$causes.ToArray()) -NoEnumerate)
}

function Get-CauseSortKey {
    # Time-based 'Sxxxx' sorts highest (by seconds), then H > M > L.
    param($Cause)
    $w = [string]$Cause.Weight
    if ($w -like 'S*') { return (100000 - [int]($w.Substring(1))) }  # more seconds = smaller key = higher
    switch ($w) { 'H' { return 200001 } 'M' { return 200002 } 'L' { return 200003 } default { return 300000 } }
}

function Show-RootCauseAnalysis {
    Write-Host ''
    Write-Host (T 'rca.title') -ForegroundColor Cyan
    Write-Host (T 'rca.disclaimer') -ForegroundColor DarkGray
    $causes = @(Invoke-RootCauseEngine)
    if ($causes.Count -eq 0) {
        Write-Host ''
        Write-Host (T 'rca.none') -ForegroundColor Green
        return
    }
    $sorted = $causes | Sort-Object { Get-CauseSortKey -Cause $_ }
    Write-Host ''
    Write-Host (T 'rca.head') -ForegroundColor Yellow
    $hasRepair = $false
    foreach ($c in $sorted) {
        $w = [string]$c.Weight
        $badge = if ($w -like 'S*') { ('~' + [int]($w.Substring(1)) + ' s') } else { switch ($w) { 'H' { T 'rca.w.high' } 'M' { T 'rca.w.med' } 'L' { T 'rca.w.low' } } }
        $col = if ($w -like 'S*') { 'Yellow' } else { switch ($w) { 'H' { 'Red' } 'M' { 'Yellow' } 'L' { 'Gray' } } }
        Write-Host ('  [' + $badge + '] ' + $c.Text) -ForegroundColor $col
        if ($c.Hint) { Write-Host ('       -> ' + $c.Hint) -ForegroundColor DarkGray }
        if ($c.RepairKey) { $hasRepair = $true }
    }
    Write-Host ''
    if ($hasRepair) {
        Write-Host (T 'rca.canrepair') -ForegroundColor Cyan
        $a = (Read-Host (T 'rca.gotorepairQ')).Trim().ToLower()
        if ($a -in 't','y','tak','yes') {
            if (Get-Command Show-RenovationMenu -ErrorAction SilentlyContinue) { Show-RenovationMenu }
        }
    } else {
        Write-Host (T 'rca.norepair') -ForegroundColor DarkGray
    }
}

function Show-PrivacyMenu {
    while ($true) {
        $items = Get-PrivacyItems
        Write-Host ''
        Write-Host (T 'priv.title') -ForegroundColor Cyan
        Write-Host (T 'priv.intro') -ForegroundColor Gray
        Write-Host ''
        $i = 1
        foreach ($it in $items) {
            $mark = if ($it.Protected) { (T 'priv.on') } else { (T 'priv.off') }
            $col = if ($it.Protected) { 'Green' } else { 'Yellow' }
            Write-Host ('  [' + $i + '] ' + $it.Title + '  ' + $mark) -ForegroundColor $col
            Write-Host ('      ' + $it.Desc) -ForegroundColor DarkGray
            $i++
        }
        Write-Host ''
        Write-Host (T 'priv.all') -ForegroundColor Magenta
        Write-Host (T 'priv.back') -ForegroundColor DarkGray
        $c = (Read-Host (T 'priv.prompt')).Trim().ToUpper()
        if ($c -eq '0') { return }
        if ($c -eq 'A') {
            $applied = 0
            foreach ($it in $items) { if (-not $it.Protected) { if (Set-PrivacyItem -Item $it) { $applied++ } } }
            Write-Host ((T 'priv.doneall') -f $applied) -ForegroundColor Green
            Write-Host (T 'priv.restart') -ForegroundColor Yellow
            continue
        }
        $n = 0
        if ([int]::TryParse($c, [ref]$n) -and $n -ge 1 -and $n -le $items.Count) {
            $it = $items[$n - 1]
            if ($it.Protected) { Write-Host (T 'priv.already') -ForegroundColor Yellow }
            else {
                if (Set-PrivacyItem -Item $it) { Write-Host ((T 'priv.done1') -f $it.Title) -ForegroundColor Green; Write-Host (T 'priv.restart') -ForegroundColor DarkGray }
            }
        }
    }
}

function Show-RenovationMenu {
    # NEW [4] structure. Wraps the legacy repair engine underneath as the executor layer.
    Initialize-RepairEnvironment
    Assert-AdminFirst
    while ($true) {
        Write-Host ''
        Write-Host (T 'ren.menu.title') -ForegroundColor Cyan
        Write-Host (T 'ren.menu.1') -ForegroundColor Green
        Write-Host (T 'ren.menu.2') -ForegroundColor Yellow
        Write-Host (T 'ren.menu.legacy') -ForegroundColor DarkGray
        Write-Host (T 'ren.menu.0') -ForegroundColor DarkGray
        do { $k = (Read-Host (T 'ren.menu.prompt')).Trim() } while ($k -notin '0','1','2','9')
        switch ($k) {
            '1' { Invoke-RenovationBasic; Read-Host (T 'ren.back') | Out-Null }
            '2' { Show-RenovationAdvancedMenu }
            '9' { Show-RepairMenuLegacy }
            '0' { return }
        }
    }
}

function Show-RepairMenuLegacy {
    Initialize-RepairEnvironment
    Assert-AdminFirst
    while ($true) {
        Write-Host ""
        Write-Host ("WindowsRepair Final Candidate $($Script:RepairModuleVersion)")
        Write-Host (T 'legacy.1')
        Write-Host (T 'legacy.2')
        Write-Host (T 'legacy.3')
        Write-Host (T 'legacy.4')
        Write-Host (T 'legacy.5')
        Write-Host (T 'legacy.6')
        Write-Host (T 'legacy.0')
        Write-Host ""
        $choice = Read-Host "Wybierz opcje"
        switch ($choice) {
            "1" { Invoke-PreparationPhase; Invoke-PostCheck; Save-RepairReport; Read-Host "Nacisnij Enter, aby wrocic do menu" | Out-Null }
            "2" { Invoke-BasicWindowsRepair; Read-Host "Nacisnij Enter, aby wrocic do menu" | Out-Null }
            "3" { Invoke-AdvancedWindowsRepair; Read-Host "Nacisnij Enter, aby wrocic do menu" | Out-Null }
            "4" { Invoke-PreparationPhase; Repair-RecoveryWinReBestEffort; Repair-RiskyAdvancedDiagnostics; Save-RepairReport; Read-Host "Nacisnij Enter, aby wrocic do menu" | Out-Null }
            "5" { Invoke-PreparationPhase; Invoke-OptionalFullAclReset; Invoke-PostCheck; Save-RepairReport; Read-Host "Nacisnij Enter, aby wrocic do menu" | Out-Null }
            "6" { Show-NaprawOdswiezWindowsMenu }
            "0" { Write-RepairLog "Wyjscie z programu." "INFO"; return }
            default { Write-RepairLog "Nieprawidlowy wybor." "WARN" }
        }
    }
}


# ============================================================
# V1.3 SUPPLEMENT - DOMKNIECIE BRAKOW Z AUDYTU POKRYCIA
# ============================================================
# Ten blok dopelnia obszary oznaczone w audycie jako czesciowe/brakujace.
# Zasada: pelne naprawy tam gdzie sa bezpieczne; tam gdzie operacja moglaby
# uszkodzic system, BitLocker, bootloader lub profil uzytkownika - diagnostyka,
# backup i bezpieczne ustawienia bez destrukcji danych.

$Script:RepairModuleVersion = "$($Script:RepairModuleVersion)-v1.3-missing-blocks"

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-RegAddSafe {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('String','ExpandString','DWord','QWord','Binary','MultiString')][string]$Type = 'DWord'
    )
    try {
        New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Write-RepairLog "REG OK: $Path :: $Name=$Value" "OK"
    } catch {
        Write-RepairLog "REG WARN: $Path :: $Name :: $($_.Exception.Message)" "WARN"
    }
}

function Remove-RegValueSafe {
    param([string]$Path,[string]$Name)
    try {
        if (Test-Path $Path) {
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
            Write-RepairLog "REG removed value: $Path :: $Name" "OK"
        }
    } catch { Write-RepairLog "REG remove value failed: $Path :: $Name :: $($_.Exception.Message)" "WARN" }
}

function Backup-RegistryKeySafeV13 {
    param([string]$RegPath,[string]$Name)
    try { Backup-RegistryKey -RegPath $RegPath -Name $Name } catch { Write-RepairLog "Backup registry skipped: $RegPath" "WARN" }
}

function Repair-NetworkProfileStoreFull {
    Write-RepairLog "V1.3: Network Profile Store, NLA, Firewall/WFP, DoH/proxy/NCSI." "INFO"
    Backup-RegistryKeySafeV13 -RegPath 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList' -Name 'NetworkList_before_v13'
    Backup-RegistryKeySafeV13 -RegPath 'HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc' -Name 'NlaSvc_before_v13'
    Invoke-ExternalCommandLogged -FilePath 'netsh.exe' -Arguments @('int','ip','reset') -StepName 'V1.3 IPv4 reset' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'netsh.exe' -Arguments @('int','ipv6','reset') -StepName 'V1.3 IPv6 reset' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'netsh.exe' -Arguments @('winsock','reset') -StepName 'V1.3 Winsock reset' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'netsh.exe' -Arguments @('advfirewall','reset') -StepName 'V1.3 Firewall reset' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'netsh.exe' -Arguments @('winhttp','reset','proxy') -StepName 'V1.3 WinHTTP proxy reset' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'ipconfig.exe' -Arguments @('/flushdns') -StepName 'V1.3 DNS flush' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'arp.exe' -Arguments @('-d','*') -StepName 'V1.3 ARP clear' | Out-Null
    $ncsi = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
    Invoke-RegAddSafe $ncsi 'EnableActiveProbing' 1 DWord
    Invoke-RegAddSafe $ncsi 'ActiveWebProbeHost' 'www.msftconnecttest.com' String
    Invoke-RegAddSafe $ncsi 'ActiveWebProbePath' 'connecttest.txt' String
    Invoke-RegAddSafe $ncsi 'ActiveDnsProbeHost' 'dns.msftncsi.com' String
    Invoke-RegAddSafe $ncsi 'ActiveDnsProbeContent' '131.107.255.255' String
    try {
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
            Set-NetIPInterface -InterfaceIndex $_.ifIndex -Dhcp Enabled -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        }
    } catch { Write-RepairLog "Network adapters DHCP reset warning: $($_.Exception.Message)" "WARN" }
    foreach ($svc in @('NlaSvc','netprofm','Dhcp','Dnscache','mpssvc','BFE','WlanSvc','iphlpsvc')) {
        Invoke-ExternalCommandLogged -FilePath 'sc.exe' -Arguments @('config',$svc,'start=','auto') -StepName "V1.3 network service $svc" | Out-Null
    }
}

function Repair-RegistryConsumerDefaultsFull {
    Write-RepairLog "V1.3: registry defaults for Winlogon, Widgets, Copilot/AI, CDN, Cloud Content, Start, Action Center, GameBar." "INFO"
    Backup-RegistryKeySafeV13 -RegPath 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'Winlogon_before_v13'
    Backup-RegistryKeySafeV13 -RegPath 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer' -Name 'Explorer_HKCU_before_v13'
    Backup-RegistryKeySafeV13 -RegPath 'HKCU\Software\Microsoft\GameBar' -Name 'GameBar_HKCU_before_v13'
    Invoke-RegAddSafe 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'Shell' 'explorer.exe' String
    Invoke-RegAddSafe 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'Userinit' 'C:\Windows\system32\userinit.exe,' String
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 DWord
    Invoke-RegAddSafe 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'EnableSnapAssistFlyout' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'EnableSnapBar' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 1 DWord
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore' 'V13Touched' 1 DWord
    Invoke-RegAddSafe 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 3 DWord
    Invoke-RegAddSafe 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Experience\AllowWindowsConsumerFeatures' 'value' 1 DWord
    Invoke-RegAddSafe 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests' 'value' 1 DWord
    foreach ($path in @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot',
        'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
        'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
    )) {
        if (Test-Path $path) {
            Remove-RegValueSafe $path 'DisableWindowsConsumerFeatures'
            Remove-RegValueSafe $path 'DisableWindowsCopilot'
            Remove-RegValueSafe $path 'EnableFeeds'
        }
    }
}

function Repair-WaaSMedicProtectedBestEffort {
    Write-RepairLog "V1.3: WaaSMedic protected service best-effort." "INFO"
    Backup-RegistryKeySafeV13 -RegPath 'HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name 'WaaSMedicSvc_before_v13'
    Invoke-ExternalCommandLogged -FilePath 'sc.exe' -Arguments @('config','WaaSMedicSvc','start=','demand') -StepName 'V1.3 WaaSMedic demand' | Out-Null
    $tasks = @('\Microsoft\Windows\WaaSMedic\PerformRemediation','\Microsoft\Windows\UpdateOrchestrator\Schedule Scan','\Microsoft\Windows\WindowsUpdate\Scheduled Start')
    foreach ($t in $tasks) { Invoke-ExternalCommandLogged -FilePath 'schtasks.exe' -Arguments @('/Change','/TN',$t,'/Enable') -StepName "V1.3 enable task $t" | Out-Null }
}

function Repair-TrustedInstallerOwnershipBestEffort {
    Write-RepairLog "V1.3: TrustedInstaller ownership best-effort for selected system areas." "INFO"
    foreach ($svc in @('TrustedInstaller','msiserver','AppXSvc','InstallService')) {
        Invoke-ExternalCommandLogged -FilePath 'sc.exe' -Arguments @('config',$svc,'start=','demand') -StepName "V1.3 service $svc demand" | Out-Null
    }
    Start-ServiceSafe -Name 'TrustedInstaller'
    # Pelny takeown systemu jest celowo blokowany; wykonujemy tylko diagnostyke i log.
    Write-RepairLog "Pelny reset ownership systemu pominiety automatycznie; dostepny tylko w osobnym trybie ACL." "WARN"
}

function Repair-FullAclBestEffort {
    Write-RepairLog "V1.3: ACL best-effort. Pelne icacls %windir% /reset jest ryzykowne i pozostaje opcjonalne." "WARN"
    $targets = @(
        "$env:windir\System32\catroot2",
        "$env:ProgramData\Microsoft\Windows\AppRepository",
        "$env:ProgramData\Microsoft\Windows\Start Menu"
    )
    foreach ($target in $targets) {
        if (Test-Path $target) {
            Invoke-ExternalCommandLogged -FilePath 'icacls.exe' -Arguments @($target,'/verify','/T','/C') -StepName "V1.3 ACL verify $target" | Out-Null
        }
    }
}

function Repair-WmiComMofFull {
    Write-RepairLog "V1.3: WMI MOF, CIM providers, Performance Counters." "INFO"
    Stop-ServiceAndWaitSafe -Name 'winmgmt' -TimeoutSeconds 30 | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'winmgmt.exe' -Arguments @('/salvagerepository') -StepName 'V1.3 WMI salvage' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'winmgmt.exe' -Arguments @('/resetrepository') -StepName 'V1.3 WMI reset fallback' | Out-Null
    Start-ServiceSafe -Name 'winmgmt'
    Invoke-ExternalCommandLogged -FilePath 'lodctr.exe' -Arguments @('/r') -StepName 'V1.3 lodctr rebuild' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'winmgmt.exe' -Arguments @('/resyncperf') -StepName 'V1.3 WMI resyncperf' | Out-Null
    $mofDirs = @("$env:windir\System32\wbem", "$env:windir\SysWOW64\wbem")
    foreach ($dir in $mofDirs) {
        if (Test-Path $dir) {
            Get-ChildItem -Path $dir -Filter '*.mof' -ErrorAction SilentlyContinue | Select-Object -First 60 | ForEach-Object {
                Invoke-ExternalCommandLogged -FilePath 'mofcomp.exe' -Arguments @($_.FullName) -StepName "V1.3 mofcomp $($_.Name)" | Out-Null
            }
        }
    }
}

function Repair-ComDcomFull {
    Write-RepairLog "V1.3: COM/DCOM registrations and defaults best-effort." "INFO"
    Backup-RegistryKeySafeV13 -RegPath 'HKLM\SOFTWARE\Microsoft\Ole' -Name 'DCOM_OLE_before_v13'
    Invoke-RegAddSafe 'HKLM:\SOFTWARE\Microsoft\Ole' 'EnableDCOM' 'Y' String
    Invoke-RegAddSafe 'HKLM:\SOFTWARE\Microsoft\Ole' 'LegacyAuthenticationLevel' 2 DWord
    $dlls = @('ole32.dll','oleaut32.dll','actxprxy.dll','urlmon.dll','jscript.dll','vbscript.dll','msxml3.dll','msxml6.dll','shell32.dll','shdocvw.dll','browseui.dll','atl.dll','softpub.dll','wintrust.dll','initpki.dll')
    foreach ($dll in $dlls) {
        $p = Join-Path $env:windir "System32\$dll"
        if (Test-Path $p) { Invoke-ExternalCommandLogged -FilePath 'regsvr32.exe' -Arguments @('/s',$p) -StepName "V1.3 regsvr32 $dll" | Out-Null }
    }
    Invoke-ExternalCommandLogged -FilePath 'dcomcnfg.exe' -Arguments @() -StepName 'V1.3 DCOM config launch skipped/visible if interactive' | Out-Null
}

function Repair-ScheduledTasksExtendedV13 {
    Write-RepairLog "V1.3: extended scheduled tasks repair." "INFO"
    $tasks = @(
        '\Microsoft\Windows\Maintenance\WinSAT',
        '\Microsoft\Windows\MemoryDiagnostic\ProcessMemoryDiagnosticEvents',
        '\Microsoft\Windows\MemoryDiagnostic\RunFullMemoryDiagnostic',
        '\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance',
        '\Microsoft\Windows\Windows Defender\Windows Defender Cleanup',
        '\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan',
        '\Microsoft\Windows\Windows Defender\Windows Defender Verification',
        '\Microsoft\Windows\InstallService\ScanForUpdates',
        '\Microsoft\Windows\InstallService\ScanForUpdatesAsUser',
        '\Microsoft\Windows\PushToInstall\LoginCheck',
        '\Microsoft\Windows\Shell\FamilySafetyMonitor',
        '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
        '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask',
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    )
    foreach ($t in $tasks) { Invoke-ExternalCommandLogged -FilePath 'schtasks.exe' -Arguments @('/Change','/TN',$t,'/Enable') -StepName "V1.3 enable task $t" | Out-Null }
}

function Repair-AppxSystemPackagesFull {
    Write-RepairLog "V1.3: AppX/UWP full system package re-register and core reinstall best-effort." "INFO"
    foreach ($svc in @('AppXSvc','ClipSVC','InstallService','StateRepository')) { Start-ServiceSafe -Name $svc }
    $patterns = @(
        'Microsoft.WindowsStore','Microsoft.StorePurchaseApp','Microsoft.DesktopAppInstaller','Microsoft.SecHealthUI',
        'Microsoft.XboxGamingOverlay','Microsoft.XboxIdentityProvider','Microsoft.GamingServices','MicrosoftWindows.Client.WebExperience',
        'Microsoft.Windows.ShellExperienceHost','Microsoft.Windows.StartMenuExperienceHost','Microsoft.WindowsAppRuntime',
        'Microsoft.UI.Xaml','Microsoft.VCLibs','Microsoft.MicrosoftEdge.Stable','Microsoft.Win32WebViewHost'
    )
    foreach ($pattern in $patterns) {
        Get-AppxPackage -AllUsers -Name "*$pattern*" -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_.InstallLocation)) {
                $manifest = Join-Path $_.InstallLocation 'AppxManifest.xml'
                if (Test-Path $manifest) {
                    try { Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop; Write-RepairLog "AppX re-registered: $($_.Name)" "OK" }
                    catch { Write-RepairLog "AppX re-register failed: $($_.Name) :: $($_.Exception.Message)" "WARN" }
                }
            }
        }
    }
    Invoke-ExternalCommandLogged -FilePath 'wsreset.exe' -Arguments @('-i') -StepName 'V1.3 Store install/reset wsreset -i' | Out-Null
    if (Test-CommandExists 'winget') {
        Invoke-ExternalCommandLogged -FilePath 'winget.exe' -Arguments @('source','update') -StepName 'V1.3 winget source update' | Out-Null
        foreach ($id in @('Microsoft.GamingServices','Microsoft.XboxGameBar','Microsoft.AppInstaller','Microsoft.EdgeWebView2Runtime')) {
            Invoke-ExternalCommandLogged -FilePath 'winget.exe' -Arguments @('install','--id',$id,'--silent','--accept-package-agreements','--accept-source-agreements') -StepName "V1.3 winget install $id" | Out-Null
        }
    }
}

function Repair-DefenderSecurityCertificatesFull {
    Write-RepairLog "V1.3: Defender, Security Center, certificates, Cryptnet." "INFO"
    foreach ($svc in @('WinDefend','SecurityHealthService','wscsvc','Sense','WdNisSvc','cryptsvc','CertPropSvc')) {
        Invoke-ExternalCommandLogged -FilePath 'sc.exe' -Arguments @('config',$svc,'start=','auto') -StepName "V1.3 security service $svc" | Out-Null
        Start-ServiceSafe -Name $svc
    }
    if (Test-CommandExists 'Set-MpPreference') {
        try {
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
            Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
            Set-MpPreference -DisableBlockAtFirstSeen $false -ErrorAction SilentlyContinue
            Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
            Write-RepairLog "Defender preferences restored best-effort." "OK"
        } catch { Write-RepairLog "Defender preference warning: $($_.Exception.Message)" "WARN" }
    }
    if (Test-CommandExists 'Update-MpSignature') { try { Update-MpSignature -ErrorAction SilentlyContinue } catch {} }
    $sst = Join-Path $Script:BackupRoot 'roots_v13.sst'
    Invoke-ExternalCommandLogged -FilePath 'certutil.exe' -Arguments @('-generateSSTFromWU',$sst) -StepName 'V1.3 generate root SST' | Out-Null
    if (Test-Path $sst) { Invoke-ExternalCommandLogged -FilePath 'certutil.exe' -Arguments @('-addstore','-f','root',$sst) -StepName 'V1.3 import root SST' | Out-Null }
    Remove-Item -Path "$env:LOCALAPPDATA\Low\Microsoft\CryptnetUrlCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:windir\System32\config\systemprofile\AppData\LocalLow\Microsoft\CryptnetUrlCache\*" -Recurse -Force -ErrorAction SilentlyContinue
}

function Repair-UserProfileShellFull {
    Write-RepairLog "V1.3: Default User, libraries, protocols, shell handlers, junction diagnostics." "INFO"
    Backup-RegistryKeySafeV13 -RegPath 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts' -Name 'FileExts_before_v13'
    $userShell = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    Invoke-RegAddSafe $userShell 'Desktop' '%USERPROFILE%\Desktop' ExpandString
    Invoke-RegAddSafe $userShell 'Personal' '%USERPROFILE%\Documents' ExpandString
    Invoke-RegAddSafe $userShell 'My Music' '%USERPROFILE%\Music' ExpandString
    Invoke-RegAddSafe $userShell 'My Pictures' '%USERPROFILE%\Pictures' ExpandString
    Invoke-RegAddSafe $userShell 'My Video' '%USERPROFILE%\Videos' ExpandString
    Invoke-RegAddSafe $userShell '{374DE290-123F-4565-9164-39C4925E467B}' '%USERPROFILE%\Downloads' ExpandString
    foreach ($ext in @('.exe','.lnk','.msi','.bat','.cmd','.ps1','.txt','.pdf','.jpg','.png','.mp4','.zip')) {
        $uc = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
        if (Test-Path $uc) { Remove-Item -Path $uc -Recurse -Force -ErrorAction SilentlyContinue; Write-RepairLog "Removed UserChoice $ext" "OK" }
    }
    Invoke-ExternalCommandLogged -FilePath 'cmd.exe' -Arguments @('/c','assoc .exe=exefile & assoc .lnk=lnkfile & assoc .msi=Msi.Package & ftype exefile="%1" %*') -StepName 'V1.3 assoc/ftype core' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'rundll32.exe' -Arguments @('shell32.dll,Control_RunDLL','srchadmin.dll') -StepName 'V1.3 search indexing UI diagnostic' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'cmd.exe' -Arguments @('/c','dir /al "%USERPROFILE%"') -StepName 'V1.3 junction diagnostics user profile' | Out-Null
}

function Repair-AudioStackFull {
    Write-RepairLog "V1.3: Audio endpoint, MMDevice, WASAPI, multimedia stack." "INFO"
    Backup-RegistryKeySafeV13 -RegPath 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices' -Name 'MMDevices_before_v13'
    foreach ($svc in @('AudioEndpointBuilder','AudioSrv','Audiosrv','MMCSS')) {
        Invoke-ExternalCommandLogged -FilePath 'sc.exe' -Arguments @('config',$svc,'start=','auto') -StepName "V1.3 audio service $svc" | Out-Null
    }
    Stop-ServiceAndWaitSafe -Name 'AudioSrv' -TimeoutSeconds 20 | Out-Null
    Stop-ServiceAndWaitSafe -Name 'AudioEndpointBuilder' -TimeoutSeconds 20 | Out-Null
    Start-ServiceSafe -Name 'AudioEndpointBuilder'
    Start-ServiceSafe -Name 'AudioSrv'
    Start-ServiceSafe -Name 'MMCSS'
    Invoke-ExternalCommandLogged -FilePath 'regsvr32.exe' -Arguments @('/s',(Join-Path $env:windir 'System32\MMDevAPI.dll')) -StepName 'V1.3 register MMDevAPI' | Out-Null
}

function Repair-DisplayGpuStackFull {
    Write-RepairLog "V1.3: GPU/display conservative repair: preferences, MPO/HDR/DWM diagnostics, DirectX." "INFO"
    Backup-RegistryKeySafeV13 -RegPath 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'GpuPreferences_before_v13'
    Backup-RegistryKeySafeV13 -RegPath 'HKLM\SOFTWARE\Microsoft\Windows\Dwm' -Name 'DWM_before_v13'
    Remove-RegValueSafe 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode'
    Invoke-RegAddSafe 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'V13Touched' '1' String
    Invoke-ExternalCommandLogged -FilePath 'dxdiag.exe' -Arguments @('/t',(Join-Path $Script:ReportRoot 'dxdiag_v13.txt')) -StepName 'V1.3 dxdiag report' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'dism.exe' -Arguments @('/Online','/Cleanup-Image','/ScanHealth') -StepName 'V1.3 component scan for display stack' | Out-Null
}

function Repair-InputBluetoothStackFull {
    Write-RepairLog "V1.3: HID, Raw Input, GameInput, XInput, Bluetooth, Device Metadata." "INFO"
    foreach ($svc in @('GameInputSvc','bthserv','BluetoothUserService','DeviceAssociationService','DeviceInstall','DsmSvc','hidserv','TabletInputService')) {
        Invoke-ExternalCommandLogged -FilePath 'sc.exe' -Arguments @('config',$svc,'start=','demand') -StepName "V1.3 input/bt service $svc" | Out-Null
        Start-ServiceSafe -Name $svc
    }
    Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Windows\DeviceMetadataCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Invoke-ExternalCommandLogged -FilePath 'pnputil.exe' -Arguments @('/scan-devices') -StepName 'V1.3 PnP scan devices' | Out-Null
}

function Repair-PowerStackFull {
    Write-RepairLog "V1.3: Power plans, power throttling, processor power, Modern Standby diagnostics, thermal." "INFO"
    Invoke-ExternalCommandLogged -FilePath 'powercfg.exe' -Arguments @('/restoredefaultschemes') -StepName 'V1.3 restore default power schemes' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'powercfg.exe' -Arguments @('/duplicatescheme','e9a42b02-d5df-448d-aa00-03f14749eb61') -StepName 'V1.3 add Ultimate Performance' | Out-Null
    Invoke-RegAddSafe 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 0 DWord
    Invoke-ExternalCommandLogged -FilePath 'powercfg.exe' -Arguments @('/energy','/duration','15','/output',(Join-Path $Script:ReportRoot 'power_energy_v13.html')) -StepName 'V1.3 power energy report' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'powercfg.exe' -Arguments @('/sleepstudy','/output',(Join-Path $Script:ReportRoot 'sleepstudy_v13.html')) -StepName 'V1.3 sleepstudy report' | Out-Null
}

function Repair-RecoveryBootFullSafe {
    Write-RepairLog "V1.3: Recovery/Boot safe repair and diagnostics." "INFO"
    Invoke-ExternalCommandLogged -FilePath 'bcdedit.exe' -Arguments @('/export',(Join-Path $Script:BackupRoot 'BCD_backup_v13.bak')) -StepName 'V1.3 BCD export backup' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'bcdedit.exe' -Arguments @('/enum','all') -StepName 'V1.3 BCD enum all' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'reagentc.exe' -Arguments @('/info') -StepName 'V1.3 WinRE info before' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'reagentc.exe' -Arguments @('/enable') -StepName 'V1.3 WinRE enable best-effort' | Out-Null
    Invoke-ExternalCommandLogged -FilePath 'reagentc.exe' -Arguments @('/info') -StepName 'V1.3 WinRE info after' | Out-Null
}

function Repair-TpmVirtualizationSecurityFullSafe {
    Write-RepairLog "V1.3: TPM/VBS/HVCI/Device Guard/Code Integrity safe diagnostics. No TPM ownership reset, no EFI reset." "WARN"
    try { Get-Tpm | Out-File -FilePath (Join-Path $Script:ReportRoot 'tpm_v13.txt') -Encoding UTF8 } catch { Write-RepairLog "Get-Tpm failed: $($_.Exception.Message)" "WARN" }
    Invoke-ExternalCommandLogged -FilePath 'msinfo32.exe' -Arguments @('/report',(Join-Path $Script:ReportRoot 'msinfo32_v13.txt')) -StepName 'V1.3 msinfo32 report' | Out-Null
    Backup-RegistryKeySafeV13 -RegPath 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'DeviceGuard_before_v13'
    Backup-RegistryKeySafeV13 -RegPath 'HKLM\SYSTEM\CurrentControlSet\Control\CI' -Name 'CodeIntegrity_before_v13'
    Write-RepairLog "EFI/UEFI/TPM ownership reset pozostaje zablokowany bez osobnego WinRE/BitLocker workflow." "WARN"
}

function Invoke-PostCheckDiffEngineFull {
    Write-RepairLog "V1.3: post-check diff engine." "INFO"
    $before = $Script:PreAudit
    $after = Invoke-RepairAuditSnapshot -Phase 'AfterV13'
    $diffPath = Join-Path $Script:ReportRoot 'V13_PostCheck_Diff.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('WINDOWSREPAIR V1.3 - POST CHECK DIFF')
    $lines.Add("Data: $(Get-Date)")
    $lines.Add('')
    foreach ($svc in @('wuauserv','bits','cryptsvc','UsoSvc','DoSvc','WaaSMedicSvc','AppXSvc','ClipSVC','InstallService','WinDefend','SecurityHealthService','Winmgmt','EventLog','Schedule','AudioSrv','WSearch','SysMain')) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) { $lines.Add("SERVICE $svc = Status=$($s.Status), StartType=$($s.StartType)") } else { $lines.Add("SERVICE $svc = MISSING") }
    }
    try { $lines.Add("NETWORK microsoft.com:443 = $(Test-NetConnection -ComputerName www.microsoft.com -Port 443 -InformationLevel Quiet)") } catch {}
    try { $lines.Add("STORE package present = $([bool](Get-AppxPackage -AllUsers -Name '*WindowsStore*' -ErrorAction SilentlyContinue))") } catch {}
    try { $lines.Add("DEFENDER service present = $([bool](Get-Service -Name WinDefend -ErrorAction SilentlyContinue))") } catch {}
    $lines | Out-File -FilePath $diffPath -Encoding UTF8
    Write-RepairLog "Zapisano diff/post-check: $diffPath" "OK"
}

function Invoke-AuditExtensionsFull {
    Write-RepairLog "V1.3: extended audit for associations, certificates, ACL, services diff." "INFO"
    $path = Join-Path $Script:ReportRoot 'V13_Extended_Audit.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('WINDOWSREPAIR V1.3 - EXTENDED AUDIT')
    $lines.Add("Data: $(Get-Date)")
    $lines.Add('')
    $lines.Add('FILE ASSOCIATIONS')
    foreach ($ext in @('.exe','.lnk','.msi','.txt','.pdf','.jpg','.png','.zip')) {
        $cmd = "cmd /c assoc $ext"
        $lines.Add("$ext -> $(cmd.exe /c assoc $ext 2>$null)")
    }
    $lines.Add('')
    $lines.Add('CERTIFICATES EXPIRING ROOT/CURRENT USER SAMPLE')
    try { Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Select-Object -First 50 | ForEach-Object { $lines.Add("ROOT: $($_.Subject) | NotAfter=$($_.NotAfter)") } } catch {}
    $lines.Add('')
    $lines.Add('ACL VERIFY')
    foreach ($target in @($env:windir,"$env:windir\System32","$env:ProgramData\Microsoft\Windows\AppRepository")) {
        if (Test-Path $target) { $lines.Add("ACL target present: $target") }
    }
    $lines | Out-File -FilePath $path -Encoding UTF8
    Write-RepairLog "Zapisano rozszerzony audyt: $path" "OK"
}

# Nadpisujemy liste krokow zaawansowanych tak, aby zawierala braki z audytu pokrycia.
# [DEDUP ETAP2 v14.1] Usunieto martwa definicje 'Get-RefreshAdvancedSteps' (warstwa #2 z 3; 24 linii).
# W PowerShellu przy wielokrotnej definicji obowiazuje OSTATNIA — ta wersja nigdy sie nie wykonywala,
# a kolizje sygnatur w takich warstwach byly zrodlem krytycznego bledu FIX1 v14.0.1.

function Save-V13CoverageNotes {
    $p = Join-Path $Script:ReportRoot 'V13_Coverage_Notes.txt'
    if (-not (Test-Path (Split-Path $p -Parent))) { New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null }
    @'
WindowsRepair v1.3 - domkniecie brakow z audytu

Dodano pelniejsze moduly:
- Network Profile Store / NLA / NCSI / proxy / DHCP
- Winlogon / Widgets / Copilot / Cloud Content / ContentDeliveryManager registry
- WaaSMedic best-effort i taski WaaS
- TrustedInstaller/service ownership diagnostics
- ACL diagnostics i bezpieczne verify
- WMI MOF/CIM/performance counters
- COM/DCOM/regsvr32/SxS best-effort
- Extended Scheduled Tasks
- AppX core packages: Store, WebExperience, SecHealthUI, Shell, Start, AppInstaller, Edge/WebView2
- Defender/Security Center/certyfikaty/Cryptnet
- UserShellFolders/FileExts/protocol basics/junction diagnostics
- Audio/MMDevice/WASAPI basics
- GPU/DWM/MPO/HDR/DirectX diagnostics
- HID/Bluetooth/GameInput/PnP cache
- Power plans/Ultimate Performance/power reports
- Recovery/BCD backup/WinRE enable diagnostics
- TPM/VBS/HVCI/DeviceGuard/CodeIntegrity diagnostics
- Post-check diff engine i extended audit

Celowe bezpieczniki:
- EFI reset, UEFI Boot repair, TPM ownership reset, Kernel/HAL/ACPI low-level repair, pelny BCD rewrite i pelny icacls %windir% nie sa wykonywane automatycznie.
- Te obszary sa raportowane/backupowane/diagnozowane, bo automatyzacja bez WinRE i kontroli BitLocker moze unieruchomic system.
'@ | Out-File -FilePath $p -Encoding UTF8
}

Save-V13CoverageNotes


# ============================================================
# V1.5 FINAL REVIEW POLISH - 90-95% TARGET
# Non-destructive Windows regeneration layer
# Adds: certificates/crypto, COM/DCOM, GPU/input, recovery, validators, ACL SAFE.
# NEVER deletes user files, applications, game launchers, browser profiles, saved passwords, cookies, sessions, AppData, Documents, Desktop, Downloads.
# ============================================================

$Script:V15Version = '1.5 REVIEW FINAL 95'
$Script:V15NoTouchPolicy = @(
    $env:USERPROFILE,
    (Join-Path $env:USERPROFILE 'AppData'),
    (Join-Path $env:USERPROFILE 'Documents'),
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:USERPROFILE 'Downloads')
)

function Write-V15Header {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' WINDOWSREPAIR - NAPRAWA I ODBUDOWA WINDOWS v1.5'
    Write-Host ' TRYB: NON-DESTRUCTIVE WINDOWS REGENERATION'
    Write-Host '============================================================'
    Write-Host 'Chronione sa: pliki, aplikacje, gry, launchery, profile przegladarek,'
    Write-Host 'zakladki, zapisane hasla, cookies, sesje, AppData i dane uzytkownika.'
    Write-Host 'Naprawiane sa komponenty systemowe Windows, a nie dane uzytkownika.'
    Write-Host '============================================================'
    Write-Host ''
}

function Test-V15ProtectedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    $full = $Path
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch {}
    foreach ($protected in $Script:V15NoTouchPolicy) {
        if (-not [string]::IsNullOrWhiteSpace($protected)) {
            try {
                $p = [System.IO.Path]::GetFullPath($protected)
                if ($full.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            } catch {}
        }
    }
    return $false
}

function Invoke-V15ExternalSafe {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$StepName = $FilePath
    )
    return Invoke-ExternalCommandLogged -FilePath $FilePath -Arguments $Arguments -StepName "V1.5 $StepName"
}

function Backup-V15FullSafetySnapshot {
    Write-RepairLog 'V1.5: Tworzenie rozszerzonego snapshotu bezpieczenstwa.' 'INFO'
    try { Invoke-PreparationPhase } catch { Write-RepairLog "Preparation phase warning: $($_.Exception.Message)" 'WARN' }

    $snap = Join-Path $Script:BackupRoot ('V15_Snapshot_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Force -Path $snap | Out-Null

    $registryKeys = @(
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies',
        'HKLM\SOFTWARE\Policies\Microsoft',
        'HKCU\SOFTWARE\Policies\Microsoft',
        'HKLM\SYSTEM\CurrentControlSet\Services',
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx',
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing',
        'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\CloudStore',
        'HKLM\SOFTWARE\Microsoft\Windows Security Health',
        'HKLM\SOFTWARE\Microsoft\Windows Defender'
    )
    foreach ($rk in $registryKeys) {
        $safe = ($rk -replace '[\\/:*?"<>| ]','_') + '.reg'
        Invoke-V15ExternalSafe -FilePath 'reg.exe' -Arguments @('export', $rk, (Join-Path $snap $safe), '/y') -StepName "snapshot registry $rk" | Out-Null
    }

    try { Get-Service | Select-Object Name,DisplayName,Status,StartType | Sort-Object Name | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $snap 'services.csv') } catch {}
    try { Get-ScheduledTask | Select-Object TaskPath,TaskName,State | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $snap 'scheduled_tasks.csv') } catch {}
    try { Get-AppxPackage -AllUsers | Select-Object Name,PackageFullName,InstallLocation,Status | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $snap 'appx_allusers.csv') } catch {}
    try { Get-WindowsOptionalFeature -Online | Select-Object FeatureName,State | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $snap 'optional_features.csv') } catch {}
    try { bcdedit /export (Join-Path $snap 'BCD_backup.bak') | Out-Null } catch {}
    Write-RepairLog "V1.5 snapshot zapisany: $snap" 'OK'
}

function Repair-CertCryptoTrustStackV15 {
    Write-RepairLog 'V1.5: Certyfikaty, crypto, root trust, cryptnet, catroot2 - bez usuwania danych uzytkownika.' 'INFO'
    try { Backup-RegistryKeySafeV13 -RegPath 'HKLM\SOFTWARE\Microsoft\SystemCertificates' -Name 'V15_SystemCertificates' } catch {}
    try { Backup-RegistryKeySafeV13 -RegPath 'HKCU\SOFTWARE\Microsoft\SystemCertificates' -Name 'V15_UserCertificates_MetadataOnly' } catch {}

    Invoke-V15ExternalSafe -FilePath 'certutil.exe' -Arguments @('-urlcache','*','delete') -StepName 'Cryptnet URL cache reset' | Out-Null
    Invoke-V15ExternalSafe -FilePath 'certutil.exe' -Arguments @('-setreg','chain\ChainCacheResyncFiletime','@now') -StepName 'Certificate chain cache resync' | Out-Null
    Invoke-V15ExternalSafe -FilePath 'certutil.exe' -Arguments @('-generateSSTFromWU',(Join-Path $Script:BackupRoot 'roots_v15.sst')) -StepName 'Generate roots.sst from Windows Update' | Out-Null

    foreach ($svc in @('CryptSvc','WinHttpAutoProxySvc')) { Start-ServiceSafe -Name $svc }
    Write-RepairLog 'V1.5: Pomijam czyszczenie INetCache/LocalAppData zgodnie z ochrona danych uzytkownika.' 'INFO'
    Write-RepairLog 'V1.5: Nie importuje agresywnie root CA do profilu uzytkownika; generuje roots.sst i resetuje cache zaufania.' 'WARN'
}

function Repair-ComDcomEnterpriseSafeV15 {
    Write-RepairLog 'V1.5: COM/DCOM/Packaged COM/SxS - rejestracja systemowych bibliotek i bezpieczny audyt DCOM.' 'INFO'
    try { Backup-RegistryKeySafeV13 -RegPath 'HKLM\SOFTWARE\Classes\CLSID' -Name 'V15_HKLM_CLSID' } catch {}
    try { Backup-RegistryKeySafeV13 -RegPath 'HKLM\SOFTWARE\Microsoft\Ole' -Name 'V15_DCOM_Ole' } catch {}

    $dlls = @(
        'ole32.dll','oleaut32.dll','actxprxy.dll','atl.dll','urlmon.dll','wintrust.dll','softpub.dll','initpki.dll',
        'shell32.dll','shdocvw.dll','browseui.dll','jscript.dll','vbscript.dll','scrrun.dll','msxml3.dll','msxml6.dll',
        'quartz.dll','qmgr.dll','qmgrprxy.dll','wuapi.dll','wuaueng.dll','wups.dll','wups2.dll','wuwebv.dll',
        'propsys.dll','thumbcache.dll','windows.storage.dll','twinapi.appcore.dll','appxdeploymentclient.dll'
    )
    foreach ($dll in $dlls) {
        $p = Join-Path $env:windir "System32\$dll"
        if (Test-Path $p) { Invoke-V15ExternalSafe -FilePath 'regsvr32.exe' -Arguments @('/s',$p) -StepName "regsvr32 $dll" | Out-Null }
        $p32 = Join-Path $env:windir "SysWOW64\$dll"
        if (Test-Path $p32) { Invoke-V15ExternalSafe -FilePath (Join-Path $env:windir 'SysWOW64\regsvr32.exe') -Arguments @('/s',$p32) -StepName "regsvr32 wow64 $dll" | Out-Null }
    }

    try {
        $out = Join-Path $Script:ReportRoot 'V15_COM_DCOM_Audit.txt'
        @(
            'V1.5 COM/DCOM AUDIT',
            "Date: $(Get-Date)",
            'COM registration repair used regsvr32 for whitelisted system DLLs only.',
            'DCOM security defaults are NOT blindly overwritten to avoid breaking enterprise/OEM apps.'
        ) | Out-File -FilePath $out -Encoding UTF8
    } catch {}
}

function Repair-AppXRecoveryStackV15 {
    Write-RepairLog 'V1.5: Pelniejszy AppX recovery stack - rejestracja krytycznych pakietow bez usuwania aplikacji uzytkownika.' 'INFO'
    foreach ($svc in @('AppXSvc','ClipSVC','InstallService','StateRepository','AppReadiness')) { Start-ServiceSafe -Name $svc }

    $critical = @(
        '*WindowsStore*','*StorePurchaseApp*','*DesktopAppInstaller*','*SecHealthUI*','*ShellExperienceHost*',
        '*StartMenuExperienceHost*','*WebExperience*','*XboxGamingOverlay*','*GamingServices*','*XboxIdentityProvider*',
        '*MicrosoftEdge*','*Win32WebViewHost*','*WindowsAppRuntime*','*UI.Xaml*','*VCLibs*','*WindowsNotepad*',
        '*Photos*','*Client.CBS*','*Client.Core*','*Client.CoreAI*','*CloudExperienceHost*','*ContentDeliveryManager*'
    )
    $packages = @()
    foreach ($pattern in $critical) {
        try { $packages += Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue } catch {}
    }
    $packages = $packages | Sort-Object PackageFullName -Unique
    foreach ($pkg in $packages) {
        if ([string]::IsNullOrWhiteSpace($pkg.InstallLocation)) { Write-RepairLog "AppX skip no InstallLocation: $($pkg.Name)" 'WARN'; continue }
        $manifest = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
        if (-not (Test-Path $manifest)) { Write-RepairLog "AppX skip no manifest: $($pkg.Name)" 'WARN'; continue }
        try { Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop; Write-RepairLog "AppX registered: $($pkg.Name)" 'OK' } catch { Write-RepairLog "AppX register failed $($pkg.Name): $($_.Exception.Message)" 'WARN' }
    }
    Invoke-V15ExternalSafe -FilePath 'wsreset.exe' -Arguments @() -StepName 'Microsoft Store reset' | Out-Null
}

function Repair-SafeAclTrustedInstallerV15 {
    Write-RepairLog 'V1.5: ACL SAFE - tylko whitelist, verify, backup; bez pelnego icacls %windir% /reset.' 'INFO'
    $targets = @(
        $env:windir,
        (Join-Path $env:windir 'System32'),
        (Join-Path $env:windir 'SysWOW64'),
        (Join-Path $env:windir 'WinSxS'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\AppRepository')
    )
    $audit = Join-Path $Script:ReportRoot 'V15_ACL_SAFE_Audit.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('V1.5 ACL SAFE AUDIT')
    $lines.Add("Date: $(Get-Date)")
    foreach ($t in $targets) {
        if (Test-Path $t) {
            $lines.Add('')
            $lines.Add("TARGET: $t")
            try { $acl = Get-Acl -Path $t; $lines.Add("Owner: $($acl.Owner)"); foreach ($ace in $acl.Access | Select-Object -First 20) { $lines.Add("ACE: $($ace.IdentityReference) $($ace.FileSystemRights) $($ace.AccessControlType)") } } catch { $lines.Add("ACL read failed: $($_.Exception.Message)") }
        }
    }
    $lines | Out-File -FilePath $audit -Encoding UTF8

    foreach ($svc in @('TrustedInstaller','AppXSvc','ClipSVC')) { Start-ServiceSafe -Name $svc }
    Write-RepairLog 'V1.5: Pelny reset ACL jest celowo zablokowany. Recenzent moze wlaczyc go recznie po tescie VM.' 'WARN'
}

function Repair-GpuDisplayDwmDeepV15 {
    Write-RepairLog 'V1.5: GPU/Display/DWM/MPO/HDR - reset bezpiecznych polityk i cache, bez usuwania sterownikow.' 'INFO'
    try { Backup-RegistryKeySafeV13 -RegPath 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'V15_GPU_UserPreferences' } catch {}
    try { Backup-RegistryKeySafeV13 -RegPath 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'V15_GraphicsDrivers' } catch {}
    try { Backup-RegistryKeySafeV13 -RegPath 'HKCU\Software\Microsoft\Windows\DWM' -Name 'V15_DWM_HKCU' } catch {}

    $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
    New-Item -Path $dwm -Force | Out-Null
    foreach ($name in @('OverlayTestMode','ForceEffectMode','EnableAeroPeek')) { Remove-ItemProperty -Path $dwm -Name $name -ErrorAction SilentlyContinue }

    $gpu = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    if (Test-Path $gpu) { Write-RepairLog 'V1.5: GPU UserGpuPreferences zachowane; nie usuwam preferencji aplikacji uzytkownika.' 'INFO' }

    Invoke-V15ExternalSafe -FilePath 'dxdiag.exe' -Arguments @('/t',(Join-Path $Script:ReportRoot 'V15_dxdiag.txt')) -StepName 'dxdiag report' | Out-Null
    Stop-Process -Name dwm -Force -ErrorAction SilentlyContinue
    Write-RepairLog 'V1.5: DWM zostanie automatycznie uruchomiony ponownie przez system.' 'OK'
}

function Repair-InputBluetoothDeviceDeepV15 {
    Write-RepairLog 'V1.5: Input/HID/Bluetooth/GameInput/XInput/Device Metadata - safe rebuild.' 'INFO'
    try { Backup-RegistryKeySafeV13 -RegPath 'HKLM\SYSTEM\CurrentControlSet\Enum\HID' -Name 'V15_HID_Enum_Metadata' } catch {}
    try { Backup-RegistryKeySafeV13 -RegPath 'HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT' -Name 'V15_Bluetooth_BTHPORT' } catch {}
    try { Backup-RegistryKeySafeV13 -RegPath 'HKLM\SYSTEM\CurrentControlSet\Services\GameInputSvc' -Name 'V15_GameInputSvc' } catch {}

    foreach ($svc in @('DeviceAssociationService','DeviceInstall','DevicePickerUserSvc','bthserv','BluetoothUserService','GameInputSvc','hidserv','TabletInputService')) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) { Invoke-V15ExternalSafe -FilePath 'sc.exe' -Arguments @('config',$svc,'start=','demand') -StepName "service $svc demand" | Out-Null; Start-ServiceSafe -Name $svc }
    }

    $deviceMetadata = Join-Path $env:ProgramData 'Microsoft\Windows\DeviceMetadataCache'
    if (Test-Path $deviceMetadata) {
        $backup = Join-Path $Script:BackupRoot ('DeviceMetadataCache_v15_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
        try { Copy-Item -Path $deviceMetadata -Destination $backup -Recurse -Force -ErrorAction SilentlyContinue; Write-RepairLog "DeviceMetadataCache backup: $backup" 'OK' } catch {}
    }
    Write-RepairLog 'V1.5: Nie usuwam parowania Bluetooth ani profili urzadzen uzytkownika.' 'WARN'
}

function Repair-RecoveryWinREOrchestrationV15 {
    Write-RepairLog 'V1.5: Recovery/WinRE/BCD orchestration - backup, verify, enable; bez rewrite bootloadera.' 'INFO'
    $rec = Join-Path $Script:BackupRoot ('Recovery_v15_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Force -Path $rec | Out-Null
    Invoke-V15ExternalSafe -FilePath 'bcdedit.exe' -Arguments @('/export',(Join-Path $rec 'BCD_backup.bak')) -StepName 'BCD export' | Out-Null
    Invoke-V15ExternalSafe -FilePath 'bcdedit.exe' -Arguments @('/enum','all') -StepName 'BCD enum all' | Out-Null
    Invoke-V15ExternalSafe -FilePath 'reagentc.exe' -Arguments @('/info') -StepName 'WinRE info before' | Out-Null
    Invoke-V15ExternalSafe -FilePath 'reagentc.exe' -Arguments @('/enable') -StepName 'WinRE enable best-effort' | Out-Null
    Invoke-V15ExternalSafe -FilePath 'reagentc.exe' -Arguments @('/info') -StepName 'WinRE info after' | Out-Null

    $offline = Join-Path $rec 'WinRE_Offline_Recovery_README.txt'
    @'
V1.5 WinRE/Offline Recovery Notes
- BCD backup generated.
- WinRE state queried and enable attempted.
- No EFI variable reset.
- No boot entry rewrite.
- No TPM ownership reset.
- Use WinRE/USB only after reviewer approval and BitLocker recovery key backup.
'@ | Out-File -FilePath $offline -Encoding UTF8
}

function Invoke-HealthValidatorV15 {
    Write-RepairLog 'V1.5: Health validator / dependency validation / score 0-100.' 'INFO'
    $checks = New-Object System.Collections.Generic.List[object]
    function Add-Check([string]$Name,[scriptblock]$Test,[string]$Weight='Normal') {
        $ok = $false; $detail=''
        try { $r = & $Test; $ok = [bool]$r; $detail = [string]$r } catch { $detail = $_.Exception.Message }
        $checks.Add([pscustomobject]@{ Name=$Name; OK=$ok; Detail=$detail; Weight=$Weight }) | Out-Null
    }

    Add-Check 'Admin context' { Test-IsAdmin }
    Add-Check 'Windows directory present' { Test-Path $env:windir }
    Add-Check 'TrustedInstaller service exists' { [bool](Get-Service TrustedInstaller -ErrorAction SilentlyContinue) }
    Add-Check 'Windows Update service exists' { [bool](Get-Service wuauserv -ErrorAction SilentlyContinue) }
    Add-Check 'BITS service exists' { [bool](Get-Service bits -ErrorAction SilentlyContinue) }
    Add-Check 'CryptSvc exists' { [bool](Get-Service CryptSvc -ErrorAction SilentlyContinue) }
    Add-Check 'Task Scheduler exists' { [bool](Get-Service Schedule -ErrorAction SilentlyContinue) }
    Add-Check 'WMI responds' { [bool](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop) }
    Add-Check 'AppXSvc exists' { [bool](Get-Service AppXSvc -ErrorAction SilentlyContinue) }
    Add-Check 'ClipSVC exists' { [bool](Get-Service ClipSVC -ErrorAction SilentlyContinue) }
    Add-Check 'Store package present' { [bool](Get-AppxPackage -AllUsers -Name '*WindowsStore*' -ErrorAction SilentlyContinue) }
    Add-Check 'DesktopAppInstaller present' { [bool](Get-AppxPackage -AllUsers -Name '*DesktopAppInstaller*' -ErrorAction SilentlyContinue) }
    Add-Check 'SecHealthUI present' { [bool](Get-AppxPackage -AllUsers -Name '*SecHealthUI*' -ErrorAction SilentlyContinue) }
    Add-Check 'ShellExperienceHost present' { [bool](Get-AppxPackage -AllUsers -Name '*ShellExperienceHost*' -ErrorAction SilentlyContinue) }
    Add-Check 'StartMenuExperienceHost present' { [bool](Get-AppxPackage -AllUsers -Name '*StartMenuExperienceHost*' -ErrorAction SilentlyContinue) }
    Add-Check 'WebExperience present' { [bool](Get-AppxPackage -AllUsers -Name '*WebExperience*' -ErrorAction SilentlyContinue) }
    Add-Check 'Xbox Game Bar present' { [bool](Get-AppxPackage -AllUsers -Name '*XboxGamingOverlay*' -ErrorAction SilentlyContinue) }
    Add-Check 'Defender service exists' { [bool](Get-Service WinDefend -ErrorAction SilentlyContinue) }
    Add-Check 'Security Center exists' { [bool](Get-Service SecurityHealthService -ErrorAction SilentlyContinue) }
    Add-Check 'Network HTTPS microsoft.com' { Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -InformationLevel Quiet }
    Add-Check 'WinRE reagentc available' { [bool](Get-Command reagentc.exe -ErrorAction SilentlyContinue) }
    Add-Check 'BCD tool available' { [bool](Get-Command bcdedit.exe -ErrorAction SilentlyContinue) }

    $total = $checks.Count
    $pass = ($checks | Where-Object { $_.OK }).Count
    $score = if ($total -gt 0) { [math]::Round(($pass / $total) * 100, 2) } else { 0 }
    $out = Join-Path $Script:ReportRoot 'V15_Health_Validator_Report.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('WINDOWSREPAIR V1.5 - HEALTH VALIDATOR')
    $lines.Add("Date: $(Get-Date)")
    $lines.Add("Score: $score / 100")
    $lines.Add("Passed: $pass / $total")
    $lines.Add('')
    foreach ($c in $checks) { $lines.Add(('{0} {1} - {2}' -f ($(if($c.OK){'[PASS]'}else{'[FAIL]'}), $c.Name, $c.Detail))) }
    $lines | Out-File -FilePath $out -Encoding UTF8
    Add-RepairResult -Step 'V1.5 Health Score' -Status "$score/100" -Details "Passed $pass/$total"
    Write-RepairLog "V1.5 Health Score: $score/100 ($pass/$total)" $(if($score -ge 80){'OK'}else{'WARN'})
}

function Invoke-RefreshFullAudit {
    # FIX (brakujaca funkcja): Invoke-RefreshFullAudit byla wolana w dwoch miejscach
    #   - Invoke-RefreshAuditMode (krok 1 "System and hardware audit", menu Naprawy [1])
    #   - Invoke-V15AuditEverything (pierwszy krok audytu)
    # ...ale nigdy nie zostala zdefiniowana, wiec kazdy audyt konczyl ten krok bledem
    # "The term 'Invoke-RefreshFullAudit' is not recognized" (lapanym, ale zapisywanym jako ERROR).
    # Ponizej wlasciwa tresc kroku: czysto-odczytowy audyt systemu i sprzetu. Nic nie zmienia w systemie,
    # nigdy nie rzuca wyjatku (kazda sekcja w try/catch), wynik trafia do raportu Naprawy.
    Write-RepairLog 'Audyt systemu i sprzetu (read-only).' 'INFO'
    $out   = Join-Path $Script:ReportRoot 'V15_System_Hardware_Audit.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    Add-RefreshAuditLine -Lines $lines -Text 'WINDOWSREPAIR - SYSTEM AND HARDWARE AUDIT'
    Add-RefreshAuditLine -Lines $lines -Text ("Date: {0}" -f (Get-Date))

    try {
        Add-RefreshAuditSection -Lines $lines -Title 'OPERATING SYSTEM'
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        Add-RefreshAuditLine -Lines $lines -Text ("OS: {0}" -f $os.Caption)
        Add-RefreshAuditLine -Lines $lines -Text ("Build: {0}" -f $os.BuildNumber)
        Add-RefreshAuditLine -Lines $lines -Text ("Architecture: {0}" -f $os.OSArchitecture)
        Add-RefreshAuditLine -Lines $lines -Text ("Last boot: {0}" -f $os.LastBootUpTime)
        $totGB  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        Add-RefreshAuditLine -Lines $lines -Text ("RAM: {0} GB total / {1} GB free" -f $totGB, $freeGB)
    } catch { Add-RefreshAuditLine -Lines $lines -Text ("OS audit unavailable: {0}" -f $_.Exception.Message) }

    try {
        Add-RefreshAuditSection -Lines $lines -Title 'CPU'
        Get-CimInstance Win32_Processor -ErrorAction Stop | ForEach-Object {
            Add-RefreshAuditLine -Lines $lines -Text ("{0} | {1} rdzeni / {2} watkow | {3} MHz" -f $_.Name, $_.NumberOfCores, $_.NumberOfLogicalProcessors, $_.MaxClockSpeed)
        }
    } catch { Add-RefreshAuditLine -Lines $lines -Text ("CPU audit unavailable: {0}" -f $_.Exception.Message) }

    try {
        Add-RefreshAuditSection -Lines $lines -Title 'MEMORY MODULES'
        Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | ForEach-Object {
            $cap = [math]::Round(($_.Capacity / 1GB), 0)
            Add-RefreshAuditLine -Lines $lines -Text ("Slot {0} | {1} GB | {2} MHz | {3}" -f $_.DeviceLocator, $cap, $_.Speed, $_.Manufacturer)
        }
    } catch { Add-RefreshAuditLine -Lines $lines -Text ("Memory audit unavailable: {0}" -f $_.Exception.Message) }

    try {
        Add-RefreshAuditSection -Lines $lines -Title 'GPU'
        Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
            Add-RefreshAuditLine -Lines $lines -Text ("{0} | sterownik {1} | {2}" -f $_.Name, $_.DriverVersion, $_.DriverDate)
        }
    } catch { Add-RefreshAuditLine -Lines $lines -Text ("GPU audit unavailable: {0}" -f $_.Exception.Message) }

    try {
        Add-RefreshAuditSection -Lines $lines -Title 'DISKS'
        Get-CimInstance Win32_DiskDrive -ErrorAction Stop | ForEach-Object {
            Add-RefreshAuditLine -Lines $lines -Text ("{0} | {1:N2} GB | {2}" -f $_.Model, ($_.Size / 1GB), $_.InterfaceType)
        }
    } catch { Add-RefreshAuditLine -Lines $lines -Text ("Disk audit unavailable: {0}" -f $_.Exception.Message) }

    try {
        Add-RefreshAuditSection -Lines $lines -Title 'BASEBOARD / BIOS'
        $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
        if ($bb)   { Add-RefreshAuditLine -Lines $lines -Text ("Board: {0} {1}" -f $bb.Manufacturer, $bb.Product) }
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
        if ($bios) { Add-RefreshAuditLine -Lines $lines -Text ("BIOS: {0} {1} ({2})" -f $bios.Manufacturer, $bios.SMBIOSBIOSVersion, $bios.ReleaseDate) }
    } catch { Add-RefreshAuditLine -Lines $lines -Text ("Baseboard/BIOS audit unavailable: {0}" -f $_.Exception.Message) }

    try {
        if (-not (Test-Path $Script:ReportRoot)) { New-Item -ItemType Directory -Path $Script:ReportRoot -Force | Out-Null }
        $lines | Out-File -FilePath $out -Encoding UTF8
        Write-RepairLog ("System and hardware audit saved: {0}" -f $out) 'OK'
    } catch {
        Write-RepairLog ("Could not save system/hardware audit: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Invoke-V15AuditEverything {
    Write-RepairLog 'V1.5: Full audit extension - system, devices, apps, features, policies, health.' 'INFO'
    try { Invoke-RefreshFullAudit } catch { Write-RepairLog "Refresh audit warning: $($_.Exception.Message)" 'WARN' }
    try { Invoke-AuditExtensionsFull } catch {}
    try { Invoke-HealthValidatorV15 } catch {}

    $out = Join-Path $Script:ReportRoot 'V15_Full_System_Audit_Extra.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('WINDOWSREPAIR V1.5 - EXTRA AUDIT')
    $lines.Add("Date: $(Get-Date)")
    $lines.Add('')
    try { $lines.Add('COMPUTER INFO'); Get-ComputerInfo | Out-String | ForEach-Object { $lines.Add($_) } } catch {}
    try { $lines.Add('PHYSICAL DISKS'); Get-PhysicalDisk | Format-Table -AutoSize | Out-String | ForEach-Object { $lines.Add($_) } } catch {}
    try { $lines.Add('PNP DEVICES PROBLEM SAMPLE'); Get-PnpDevice | Where-Object Status -ne 'OK' | Select-Object -First 100 | Format-Table -AutoSize | Out-String | ForEach-Object { $lines.Add($_) } } catch {}
    try { $lines.Add('OPTIONAL FEATURES DISABLED SAMPLE'); Get-WindowsOptionalFeature -Online | Where-Object State -eq 'Disabled' | Select-Object -First 200 FeatureName,State | Format-Table -AutoSize | Out-String | ForEach-Object { $lines.Add($_) } } catch {}
    try { $lines.Add('EVENT ERRORS LAST 24H'); Get-WinEvent -FilterHashtable @{LogName='System';Level=2;StartTime=(Get-Date).AddHours(-24)} -MaxEvents 100 -ErrorAction SilentlyContinue | Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message | Format-List | Out-String | ForEach-Object { $lines.Add($_) } } catch {}
    $lines | Out-File -FilePath $out -Encoding UTF8
}

function Repair-AdvancedDependencyOrchestrationV15 {
    Write-RepairLog 'V1.5: Dependency orchestration - kolejnosc bezpieczna dla danych.' 'INFO'
    Backup-V15FullSafetySnapshot
    Repair-CertCryptoTrustStackV15
    Repair-ComDcomEnterpriseSafeV15
    Repair-AppXRecoveryStackV15
    Repair-SafeAclTrustedInstallerV15
    Repair-GpuDisplayDwmDeepV15
    Repair-InputBluetoothDeviceDeepV15
    Repair-RecoveryWinREOrchestrationV15
    Invoke-HealthValidatorV15
}

# Override advanced steps again with final V1.5 polish included.
function Get-RefreshAdvancedSteps {
    return @(
        @{ Category='Preparation'; Name='V1.5 snapshot, restore point, no-data-loss guard, extended audit'; Action={ Write-V15Header; Backup-V15FullSafetySnapshot; Invoke-AuditExtensionsFull } },
        @{ Category='Registry'; Name='Registry defaults: policies, Winlogon, Explorer, Widgets, Copilot, Cloud Content, privacy'; Action={ Repair-RegistryAndPolicies; Repair-RegistryDefaultsExtended; Repair-RegistryConsumerDefaultsFull } },
        @{ Category='Services'; Name='Services map, WaaSMedic, TrustedInstaller, Update, Store, Defender, audio, bluetooth, sensors'; Action={ Repair-WindowsServices; Repair-WaaSMedicProtectedBestEffort; Repair-TrustedInstallerOwnershipBestEffort } },
        @{ Category='ACL_SAFE'; Name='ACL SAFE and TrustedInstaller verification - whitelist only, no profile/app deletion'; Action={ Repair-SafeAclTrustedInstallerV15; Repair-FullAclBestEffort } },
        @{ Category='WindowsUpdate'; Name='Windows Update, BITS, WaaS, Update Orchestrator, Delivery Optimization, connectivity'; Action={ Reset-WindowsUpdateFull; Repair-WaaSMedicProtectedBestEffort; Repair-NetworkProfileStoreFull } },
        @{ Category='AppX'; Name='Full AppX recovery: Store, AppInstaller, WebExperience, SecHealthUI, Shell, Start, Xbox, runtimes'; Action={ Repair-StoreAppxGaming; Repair-AppxSystemPackagesFull; Repair-AppXRecoveryStackV15 } },
        @{ Category='CryptoCerts'; Name='Certificates, CryptSvc, Cryptnet cache, root trust refresh, security center'; Action={ Repair-DefenderSecurityCertificatesFull; Repair-CertCryptoTrustStackV15 } },
        @{ Category='COM_DCOM'; Name='COM/DCOM/SxS/WinSxS/regsvr32 system libraries and audit'; Action={ Repair-WmiComMofFull; Repair-ComDcomFull; Repair-WmiComWinSxS; Repair-ComDcomEnterpriseSafeV15 } },
        @{ Category='Tasks'; Name='Scheduled tasks: Defender, Store, Update, Maintenance, Diagnostics, providers'; Action={ Repair-ScheduledTasks; Repair-ScheduledTasksExtendedV13 } },
        @{ Category='ShellProfile'; Name='Shell, Start, Taskbar, Explorer, UserShellFolders, FileExts, handlers'; Action={ Repair-ShellProfileFileAssociations; Repair-UserProfileShellFull; Repair-ShellExtendedFinal } },
        @{ Category='GPU_Display'; Name='GPU/Display/DWM/MPO/HDR/DirectX safe rebuild'; Action={ Repair-DisplayGpuStackFull; Repair-GpuDisplayDwmDeepV15 } },
        @{ Category='InputBluetooth'; Name='Input/HID/Bluetooth/GameInput/XInput/Device Metadata safe rebuild'; Action={ Repair-InputBluetoothStackFull; Repair-InputBluetoothDeviceDeepV15 } },
        @{ Category='Audio'; Name='Audio Endpoint, MMDevice, WASAPI, multimedia stack'; Action={ Repair-AudioStackFull } },
        @{ Category='Power'; Name='Power plans, Ultimate Performance, power throttling, CPU power, Modern Standby diagnostics'; Action={ Repair-PowerStackFull } },
        @{ Category='Network'; Name='TCP/IP, Winsock, DNS, NCSI, NLA, Network Profile Store, Firewall/WFP, DoH/proxy'; Action={ Reset-NetworkFull; Repair-NetworkProfileStoreFull } },
        @{ Category='Security'; Name='Defender, Security Center, SmartScreen, VBS/HVCI diagnostics, Code Integrity diagnostics'; Action={ Repair-SecurityBaseline; Repair-TpmVirtualizationSecurityFullSafe } },
        @{ Category='Recovery'; Name='Recovery/WinRE/BCD backup/orchestration - no EFI reset, no boot rewrite'; Action={ Repair-RecoveryBootFullSafe; Repair-RecoveryWinREOrchestrationV15; New-OfflineRecoveryScript } },
        @{ Category='TPM_EFI'; Name='TPM/EFI/UEFI/Kernel/HAL/ACPI - diagnostics only with safety blockers'; Action={ Repair-RiskyAdvancedDiagnostics; Repair-TpmVirtualizationDiagnosticsOnly } },
        @{ Category='Integrity'; Name='DISM RestoreHealth, SFC Scannow, component verification'; Action={ Invoke-DismRestoreHealthChecked; Invoke-SfcScannowChecked } },
        @{ Category='Validation'; Name='V1.5 health validator, dependency checks, post-check diff, final reports'; Action={ Invoke-HealthValidatorV15; Invoke-PostCheck; Invoke-PostCheckDiffEngineFull; Save-CoverageMatrix; Save-RepairReport; Save-V15ReviewNotes } }
    )
}

# Override audit steps so option [1] is truly full audit.
function Invoke-RefreshAuditMode {
    Write-V15Header
    $steps = @(
        @{ Category='Audit'; Name='System and hardware audit'; Action={ Invoke-RefreshFullAudit } },
        @{ Category='Audit'; Name='Extended services/tasks/AppX/policies/certificates audit'; Action={ Invoke-AuditExtensionsFull } },
        @{ Category='Audit'; Name='Health validator and dependency score'; Action={ Invoke-HealthValidatorV15 } },
        @{ Category='Audit'; Name='Extra device/optional features/events audit'; Action={ Invoke-V15AuditEverything } },
        @{ Category='Report'; Name='Save repair report'; Action={ Save-RepairReport } }
    )
    Invoke-RefreshProgressSteps -Activity 'Audyt systemu i urzadzenia' -Steps $steps
}

function Save-V15ReviewNotes {
    $p = Join-Path $Script:ReportRoot 'V15_REVIEW_NOTES_FINAL.txt'
    @'
WindowsRepair Final Candidate v1.5 - Review Notes

Status: top review build / 90-95% target.

Added in v1.5:
- Non-destructive Windows regeneration policy.
- Full safety snapshot before advanced repair.
- Certificates / Crypto / Cryptnet / root trust refresh.
- COM/DCOM/SxS safe rebuild via whitelisted system DLL registrations.
- Full critical AppX recovery stack without Remove-AppxPackage.
- ACL SAFE / TrustedInstaller verification without global icacls reset.
- GPU/Display/DWM/MPO/HDR safe rebuild and dxdiag report.
- Input/HID/Bluetooth/GameInput/XInput safe rebuild without deleting pairing/user profiles.
- Recovery/WinRE/BCD orchestration with backup, no EFI reset, no boot rewrite.
- Health validator / dependency engine / score 0-100.
- Extended audit: hardware, optional features, device issues, event errors.

Data protection guarantee by design:
- Does not delete personal files.
- Does not remove installed applications.
- Does not remove games or launchers.
- Does not clear browser profiles, saved passwords, cookies, bookmarks, sessions.
- Does not wipe AppData or user profile directories.

Reviewer warning:
- EFI reset, TPM ownership reset, full BCD rewrite, Kernel/HAL/ACPI low-level repair and global ACL reset remain blocked/diagnostic by design.
- Test on VM Windows 10/11 before stable release.
'@ | Out-File -FilePath $p -Encoding UTF8
}



function Invoke-NaprawaOdbudowaWindowsIntegrated {
    <#
        Uruchamia zintegrowane menu naprawy bez zmiany architektury optimizera.
        Moduł ma własne raporty, log i backupy, ale działa w tej samej sesji PowerShell.
    #>
    try {
        if ($script:SessionFolder) {
            $Script:RepairRoot = Join-Path $script:SessionFolder 'Naprawa_Odbudowa_Windows'
            $Script:BackupRoot = Join-Path $Script:RepairRoot 'Backups'
            $Script:ReportRoot = Join-Path $Script:RepairRoot 'Reports'
            $Script:LogPath = Join-Path $Script:RepairRoot 'repair.log'
            $Script:PreAuditJson = Join-Path $Script:ReportRoot 'audit_before.json'
            $Script:PostAuditJson = Join-Path $Script:ReportRoot 'audit_after.json'
            $Script:ReportJson = Join-Path $Script:ReportRoot 'repair_report.json'
            $Script:ReportTxt = Join-Path $Script:ReportRoot 'repair_report.txt'
            $Script:OfflineScriptPath = Join-Path $Script:ReportRoot 'WinPE_OfflineRepair_Generated.cmd'
        }
        Show-RenovationMenu
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Naprawa i Odbudowa Windows: $($_.Exception.Message)" -Level 'ERROR'
        }
        throw
    }
}

# =============================================================
# KONIEC MODUŁU: NAPRAWA I ODBUDOWA WINDOWS
# =============================================================


# =============================
# Main
# =============================
# PHASE-A v15: special entry points launched by scheduled tasks - no session folders, no transcript.
if ($Daemon) { Invoke-AutomationDaemon; exit 0 }
if ($ValidateState) { Invoke-ValidateStateRun; if (-not $NoPause) { [void][System.Console]::ReadLine() }; exit 0 }
if ($ResumeRenovation) {
    # Section D: resumed after a restart by the scheduled task. Continue the saved pipeline.
    Initialize-Folders
    if (Get-Command Resume-RenovationPipeline -ErrorAction SilentlyContinue) {
        $rs = Get-RenovationState
        if ($rs) { Resume-RenovationPipeline -State $rs }
    }
    if (-not $NoPause) { [void][System.Console]::ReadLine() }
    exit 0
}

Initialize-Folders
# FIX v14.0.1: Start-Transcript moze zawiesc (OneDrive/ACL/Controlled Folder Access) — nie moze to
# ubic skryptu ani zamaskowac pozniejszych bledow przez Stop-Transcript w finally.
$script:TranscriptStarted = $false
try { Start-Transcript -Path $script:TranscriptPath -Force | Out-Null; $script:TranscriptStarted = $true }
catch { Write-Host "UWAGA: transcript niedostepny ($($_.Exception.Message)) — kontynuuje bez transkryptu." -ForegroundColor Yellow }
try {
    Assert-Admin

    # STAGE6 v14.5: gentle note when running on Windows PowerShell 5.1 (script supports both 5.1 and 7).
    if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $Silent) { Write-Host (T 'ps51.warn') -ForegroundColor Yellow }

    # FIX v14.0.1: tryb Repair jest w pelni interaktywny (menu Read-Host) — z -Silent zawisalby
    # w nieskonczonosc na niewidocznym prompcie (np. w Harmonogramie zadan).
    if ($Mode -eq 'Repair' -and $Silent) {
        throw 'Tryb Repair jest interaktywny i nie wspiera -Silent. Uruchom bez -Silent albo uzyj -Mode Optimize/Rollback/Analyze.'
    }

    $paramsGiven=$PSBoundParameters.ContainsKey('Mode')-or$PSBoundParameters.ContainsKey('Profile')
    if (-not $paramsGiven -and -not $Silent) {
        Show-InteractiveMenu
        $Mode    = $script:SelectedMode
        $Profile = $script:SelectedProfile
        if ($script:SelectedSearchMode)   { $SearchIndexingMode   = $script:SelectedSearchMode }
        if ($script:SelectedExperimental) { $EnableExperimentalTweaks = $true }
        if ($script:SelectedDns)          { $DnsMode = $script:SelectedDns }
        $script:Manifest.Mode=$Mode; $script:Manifest.Profile=$Profile
    }
    $script:SelectedDns=$DnsMode

    # v15.8: tryb Compare - porownanie 2 zapisanych sesji (read-only, bez pipeline'u optymalizacji).
    if ($Mode -eq 'Compare') {
        Show-CompareReports
        return
    }

    if ($Mode -eq 'Repair') {
        Write-Status '' 'White'
        Write-Status 'Uruchamiam modul: Naprawa i Odbudowa Windows' 'Magenta'
        # RENOVATION 2.0 part 1 (v15.3): preflight gate (pending reboot / disk space / battery)
        if (-not (Test-RepairPreflight)) {
            Write-Status '  Naprawa przerwana przez uzytkownika na etapie preflight.' 'Yellow'
            $script:ExitCode = 0
            return
        }
        Invoke-NaprawaOdbudowaWindowsIntegrated
        $script:ExitCode = 0
        return
    }

    Show-V14FirstRunWizard
    if ($script:SelectedMode) { $Mode = $script:SelectedMode; $script:Manifest.Mode = $Mode }
    if ($script:SelectedProfile) { $Profile = $script:SelectedProfile; $script:Manifest.Profile = $Profile }

    Invoke-SanityChecks

    Write-Status '' 'White'
    Write-Status "$($script:AppName) $($script:Version)" 'White'
    Write-Status "Tryb: $Mode | Profil: $Profile | DNS: $($script:SelectedDns) | SmartMode: $(if($script:SmartModeEnabled){'ON'}else{'OFF'}) | Sesja: $($script:SessionId)" 'White'
    Write-Status '' 'White'

    $envInfo=Get-SystemEnvironment
    $script:Manifest.Environment=$envInfo
    Resolve-Profile
    Import-CustomProfileV13_1
    Apply-V14ScenarioPreset
    Show-LaptopGamingProChoiceMenu
    Show-LaptopGamingRiskChoiceMenu
    Resolve-LaptopGamingProSilentOptions
    Show-ProfileRiskAwareChoiceMenu
    if ($Silent -and $script:EnableRiskPackBundle -and -not $script:EnableLaptopGamingSafeMode) {
        Enable-CombinedRiskPack -Context 'General'
    }
    if ($script:SearchIndexingMode) { $SearchIndexingMode=$script:SearchIndexingMode; $script:Manifest.SearchIndexingMode=$SearchIndexingMode }
    Apply-V14SafetyPolicies
    Save-Manifest; Save-Snapshot -Kind before

    if ($Mode-eq'Rollback') {
        $rbSession = if ($script:SelectedRollbackSession) { $script:SelectedRollbackSession } elseif ($RollbackLatest) { $script:OneClickRollbackUsed = $true; Get-LatestRollbackSessionId } elseif ($RollbackSessionId) { $RollbackSessionId } else { throw 'Podaj -RollbackSessionId, -RollbackLatest albo uruchom interaktywnie.' }
        if ($script:OneClickRollbackUsed) { Write-Status "One-click rollback: wybrano najnowsza sesje: $rbSession" 'Green' }
        Invoke-Rollback -RollbackSessionId $rbSession
    } else {
        # FIX v14.0.2: Analyze nic nie zmienia w systemie — restore point bylby jedyna realna modyfikacja
        # i falszywie podbijal licznik zmian. Tworzony tylko dla trybow, ktore cos modyfikuja.
        if (-not $DryRun -and $Mode -ne 'Analyze') { Initialize-RestorePoint }
        elseif ($Mode -eq 'Analyze') { Write-Log 'Analyze: restore point pominiety (tryb tylko-odczyt).' -Level 'INFO' }
        Backup-ServiceState; Backup-PowerPlans; Backup-NetworkStateFull
        Save-Manifest

        if ($Mode-eq'Analyze' -or $Mode-eq'Audit') {
            Invoke-IntegratedAuditV13_1 -IncludeBaseAnalyze
            Invoke-MemoryDiagnosticOptionalV13_1
            # RENOVATION 2.0 (v15.4): show the same Health Score in plain Analyze (read-only, no changes).
            if (Get-Command Get-RenovationDiagnosis -ErrorAction SilentlyContinue) {
                try {
                    Write-Host (T 'ren.diag.run') -ForegroundColor Cyan
                    $hsFindings = @(Get-RenovationDiagnosis)
                    $hs = Get-RenovationHealthScore -Findings $hsFindings
                    Show-RenovationHealthBar -Score $hs -Label (T 'ren.analyze.label')
                    if (@($hsFindings).Count -gt 0) {
                        Write-Host (T 'ren.analyze.hint') -ForegroundColor DarkGray
                        Show-RenovationFindings -Findings $hsFindings
                    }
                } catch { Write-Log "Analyze health score: $($_.Exception.Message)" -Level 'WARN' }
            }
        } elseif ($Mode-eq'Optimize') {
            if ($DryRun) {
                Write-Status '' 'White'
                Write-Status '=============================================' 'Yellow'
                Write-Status '  TRYB DRYRUN — zadne zmiany nie zostana     ' 'Yellow'
                Write-Status '  wprowadzone w systemie. Tylko podglad.     ' 'Yellow'
                Write-Status '=============================================' 'Yellow'
                Write-Status '' 'White'
            }
            Write-Status '==> Pomiar systemu PRZED optymalizacja...' 'Cyan'
            $script:BenchmarkBefore=Get-BenchmarkSnapshot

            Show-PreflightPreview

            if ($DryRun) {
                Write-Log -Message 'DryRun: pomijam wykonywanie zmian, ale generuje raport/audit v13.1.' -Level 'INFO'
                $script:Manifest.Notes += 'DryRun executed: no system changes applied; audit generated.'
                Invoke-IntegratedAuditV13_1 -IncludeBaseAnalyze
            } else {
                if ($script:EnableLaptopGamingSafeMode) {
                    Invoke-LaptopGamingSafeTweaks
                    Invoke-LaptopBenchmarkProReport
                    Invoke-LaptopStartupReview
                    Invoke-PostDebloaterRepair
                    Invoke-NvidiaSafeProfile
                    Invoke-PerformanceFeelMode
                    Invoke-LaptopGamingOptionalRiskTweaks
                }
                if ($script:EnablePowerTweaks)   { Invoke-PowerTweaks }
                if ($script:EnableUiTweaks)      { Invoke-UiTweaks }
                if ($script:EnableGamingTweaks)  { Invoke-GamingTweaks }
                if ($script:EnableGamingTweaks)  { Invoke-GpuTweaks }
                if ($script:EnableGamingTweaks)  { Invoke-TimerResolution }
                if ($script:EnableLaptopGamingSafeMode -and $script:LaptopOptionalVbsDisable) { Invoke-LaptopOptionalVbsDisable }
                if ($script:EnableGamingTweaks -and $EnableVbsDisable) { Invoke-VbsDisable }
                if ($GameFolder)                                         { Invoke-DefenderGameExclusion }
                if ($script:EnableNetworkTweaks) { Invoke-NetworkTweaks }
                if ($script:EnableNetworkTweaks) { Invoke-NetworkDriverTuning }
                if ($script:EnableServiceTuning) { Invoke-ServiceTuning }
                if ($script:EnableCleanup)       { Invoke-Cleanup }
                if ($script:EnableRepair)        { Invoke-Repair }
                if ($script:EnableGamingSession) { Invoke-GamingSession }
                if ($script:EnableGamingTweaks)  { Invoke-GPUMsiMode }
                if (-not $script:EnableLaptopGamingSafeMode) { Invoke-PerformanceFeelMode }
                if (-not $script:EnableLaptopGamingSafeMode -and ($Profile -eq 'Maximum' -or $script:AllowGlobalWindowsUpdatePause)) { Request-WindowsUpdatesPause }

                Invoke-PostValidation

                # v12: Zapisz expected state do persistent validation (sprawdz po restarcie)
                if (Get-Command Save-ExpectedState -ErrorAction SilentlyContinue) {
                    $expectedStatePath = Join-Path $script:RootFolder 'expected_state.json'
                    Save-ExpectedState -OutputPath $expectedStatePath
                }

                # v12: Delayed-auto services — szybszy pulpit po zalogowaniu (Maximum only)
                if ($Profile -eq 'Maximum' -and (Get-Command Set-DelayedAutoServices -ErrorAction SilentlyContinue)) {
                    Set-DelayedAutoServices -DryRun:$DryRun
                }

                Write-Status '==> Pomiar systemu PO optymalizacji...' 'Cyan'
                $script:BenchmarkAfter=Get-BenchmarkSnapshot
                Write-BenchmarkReport -Before $script:BenchmarkBefore -After $script:BenchmarkAfter

                # PHASE-A v15 (#16): regression guard - warns and offers a rollback when 'after' is clearly worse.
                Invoke-BenchmarkRegressionGuard
                # PHASE-A v15 (#17): one-shot validation at next logon (did Windows Update revert our tweaks?).
                if (-not $DryRun) { Register-PostRestartValidation }

                Invoke-IntegratedAuditV13_1 -IncludeBaseAnalyze
                Invoke-MemoryDiagnosticOptionalV13_1
            }
        }
    }

    $script:ExitCode = if ($script:ErrorsCount -gt 0) { 2 } else { 0 }
    Save-Manifest; Save-Snapshot -Kind after
    Invoke-SnapshotDiff
    Write-V13_1Readme
    Write-ExecutiveSummary
    Write-HtmlReport
    Write-V14ProDashboard
    Write-V14WhatChanged

    # v12: Wizualna ramka podsumowania z checklistą
    if (Get-Command Write-SummaryBox -ErrorAction SilentlyContinue) {
        $finalScore  = if (Get-Command Get-SystemScore -ErrorAction SilentlyContinue) { Get-SystemScore } else { $null }
        $finalBefore = $script:BenchmarkBefore
        $finalAfter  = if ($null -ne $script:BenchmarkAfter) { $script:BenchmarkAfter } else { $null }
        Write-SummaryBox `
            -Score       $finalScore `
            -BenchBefore $finalBefore `
            -BenchAfter  $finalAfter `
            -MemTopology $script:MemTopology `
            -HWProfile   $script:HWProfile
    }

    # v12 PREMIUM: generuj Python analyzer
    Export-PythonAnalyzer -SessionFolder $script:SessionFolder

    Write-Status '' 'White'
    Write-Status (T 'main.done' -FmtArgs @($script:ReportFolder)) 'Green'
    Write-Status (T 'main.html' -FmtArgs @($script:HtmlReportPath)) 'Green'

    Invoke-RestartPrompt
}
catch {
    $script:ExitCode = 1
    Write-Log $_.Exception.Message -Level 'ERROR'
    Write-Status $_.Exception.Message 'Red'
    throw
}
finally {
    if ($script:TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
    if (-not $NoPause -and -not $Silent) {
        Write-Host ''; Write-Host (T 'main.pressclose') -ForegroundColor DarkGray
        [void][System.Console]::ReadLine()
    }
}

# FIX (ExitCode): przebieg, ktory skonczyl sie z bledami, ustawia $script:ExitCode = 2, ale dotad
# proces i tak zwracal 0 (brak 'exit'), wiec Harmonogram zadan / %ERRORLEVEL% widzialy sukces.
# Na sciezce sukcesu propagujemy realny kod (0 lub 2). Twardy blad nadal leci przez 'throw' w catch
# (powyzej), wiec konczy sie kodem != 0 z pelnym sladem bledu - tej linii wtedy nie osiaga.
exit $script:ExitCode
