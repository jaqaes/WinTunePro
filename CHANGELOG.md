# Changelog

## 17.2 — Ultra Debloat BETA, trwały rollback i stabilizacja (PS5 i PS7)

**PL — Główne wydanie.** Oba buildy — PowerShell 7 (zalecany) oraz Windows PowerShell 5.1 — mają identyczną funkcjonalność. Cały kod przeszedł pełny przegląd składni: statyczna analiza (Script Doctor v1.1) kończy się z wynikiem **0 błędów** w obu buildach.

### Bezpieczeństwo i odwracalność
- **Trwały restore Debloatu** — każda zmiana (typy startu usług, zatrzymane usługi, wyłączone zadania, wartości rejestru z typem, wpisy Run, przeniesione skróty Startup, usunięte Appx) jest od razu zapisywana do `%LOCALAPPDATA%\WinTunePro\debloat-restore.json`. Debloat **[4] Przywróć** cofa zmiany także po zamknięciu narzędzia i po restarcie; po udanym przywróceniu plik jest archiwizowany, a stan w pamięci sesji pozostaje jako fallback.
- **Rollback rejestru od najnowszego do najstarszego** — pełne importy klucza nie nakładają już z powrotem wcześniejszych tweaków z tego samego klucza; `reg import` weryfikuje kod wyjścia.
- Rollback czyta pola manifestu bezpiecznie (`Get-PropSafe`) — starsze wpisy Privacy bez `Type`/`BackupFile` nie wywracają rollbacku pod StrictMode; klucze utworzone przez skrypt są sprzątane przy cofaniu.
- **DryRun nie modyfikuje systemu** — sprawdzenie `-DryRun` wykonuje się przed utworzeniem klucza i przed eksportem backupu.
- **Privacy** przechodzi przez wspólną, bezpieczną warstwę rejestru (`Set-RegistryValueSafe`): spójny manifest, backup, DryRun i rollback.
- Debloat tworzy punkt przywracania przed pierwszą zmianą; `ScheduledDefrag` nie jest wyłączany (Windows używa go do retrim SSD).

### Nowe funkcje
- **Debloat [8] ULTRA Debloat BETA** — najbardziej agresywny, testowy poziom zbudowany na Maksymalnym: dodatkowo ogranicza usługi per‑user/synchronizacji, więcej zadań, wpisów rejestru, pakietów Appx i autostartu. Wymaga trzech potwierdzeń (`YES` → `ULTRA` → `YES ULTRA`) z pełnym podglądem read‑only przed pierwszym. Świadomie nie rusza Defendera, rdzenia Windows Update i Store, powłoki, audio, sieci, sterowników GPU ani anticheata; usługi zawsze Manual, nigdy Disabled. Cofanie: Debloat [4] + punkt przywracania. Szczegóły: `ULTRA-DEBLOAT.md`.
- **[23] Narzędzia inżynierskie** — raporty Preflight/Analyze/DryRun z katalogów `data/catalog/*.json` do folderu `runs\`. **Apply w tym wydaniu zapisuje wyłącznie manifest — nie wykonuje zmian w systemie.**
- **Ostrzeżenie HKCU** — gdy elewacja UAC idzie na inne konto administratora niż zalogowany użytkownik pulpitu, narzędzie o tym informuje (tweaki HKCU trafiłyby do profilu konta elewowanego).

### Poprawność i stabilność
- **Pełna zgodność składni z PowerShell 5.1 i 7.x** — usunięte konstrukcje wywracające parser (niedomknięte bloki i cudzysłowy, nawiasy wewnątrz interpolacji, zwarte operatory typu `$x-eq'y'`), przepisane wielolinijkowe wyrażenia `if` w przypisaniach i wewnątrz hashtable. Build 5.1 nie zawiera żadnej składni tylko‑PS7 (ternary `?:`, `??`, `?.`).
- **Wszystkie pliki `.ps1`/`.psm1` zapisane jako UTF‑8 z BOM** — poprawne polskie znaki i ramki interfejsu pod Windows PowerShell 5.1.
- Ultra Debloat: naprawiony crash podglądu/wykonania spowodowany niespójną nazwą zmiennej listy Appx (`DebloatUltraApps` vs `DebloatUltraAppx`); dodany alias zgodności, więc starsze odwołania nie wywracają się pod `Set-StrictMode -Version Latest`.
- Ujednolicona inicjalizacja zmiennych skryptowych (m.in. `$Script:BeforeAudit` w silniku porównań przed/po naprawie) — koniec z błędami typu „variable has not been set" pod StrictMode.
- Repair: `Userinit` i ścieżka logu Sysprep budowane z `$env:SystemRoot` (koniec z hardkodowanym `C:\Windows`); usunięta no‑opowa pętla ConsentStore/`Deny`.
- Optimize: usunięty martwy kod `$hasAnyRisk`; poprawiona numeracja menu ryzyka — VBS/Memory Integrity to punkt `5)`.
- Usunięta pseudo‑walidacja z auto‑rollbackiem dla `GameDVR_Enabled` i `Win32PrioritySeparation` (pojedyncza próbka RAM/CPU po kilku sekundach mierzyła szum, nie efekt tweaka) — tweaki stosują się normalnie, cofanie zapewnia manifest.
- Nowy helper `Write-CatchWarn` w krytycznych ścieżkach zmieniających stan (restore Debloatu, rollback, zapisy Repair) — błędy nie znikają już w pustych `catch`.
- System Score rozdzielony: **HealthScore** (realne sygnały kondycji: XMP, wiek sterownika GPU, RAM pressure) i **AdoptionScore** (zgodność z tweakami narzędzia) — świeży Windows nie jest już karany za samo nieużycie narzędzia.
- Interfejs: `Esc` zawsze bezpiecznie wraca (nie uruchamia domyślnej pozycji); ustawienia UI mają awaryjny zapis w pamięci sesji, gdy pliku ustawień nie da się zapisać; profil sprzętowy ma fallback przy problemach WMI/CIM/Storage.
- Czytelniejsze opisy poziomów Debloatu: Maksymalny = „bardzo mocny", Ultra = „najbardziej agresywny / testowy"; doprecyzowane komunikaty potwierdzeń.

### Wydanie
- `Run-Optimizer.bat`: samo‑elewacja UAC działa także przy uruchomieniu **bez argumentów** (wcześniej pusty `-ArgumentList` blokował podniesienie uprawnień przy zwykłym dwukliku); argumenty przekazywane przez zmienne środowiskowe, odpornie na cudzysłowy.
- Self‑Test: lista wymaganych plików wskazuje `v17_0.ps1` (koniec z fałszywym FAIL o brakującym starszym loaderze).
- `data/catalog/services.json`: wpisy `Disabled` zamienione na `Manual` — spójnie z zasadą narzędzia.
- Menu `[23]`: etykiety Apply mówią wprost „TYLKO manifest (bez zmian w systemie)".
- Numer wersji ujednolicony do `17.2` (skrypt, nagłówek UI, changelog); dokumentacja przeniesiona z luźnych plików `.txt` do `README.md`, `CHANGELOG.md` i `ULTRA-DEBLOAT.md`.

---

**EN — Main release.** Both builds — PowerShell 7 (recommended) and Windows PowerShell 5.1 — are functionally identical. The whole codebase went through a full syntax pass: static analysis (Script Doctor v1.1) finishes with **0 errors** on both builds.

### Safety and reversibility
- **Persistent Debloat restore** — every change (service startup types, stopped services, disabled tasks, typed registry values, Run entries, moved Startup shortcuts, removed Appx) is written immediately to `%LOCALAPPDATA%\WinTunePro\debloat-restore.json`. Debloat **[4] Restore** undoes changes even after closing the tool or rebooting; after a successful restore the file is archived, with the in‑session state kept as a fallback.
- **Registry rollback newest‑to‑oldest** — full‑key imports no longer re‑apply earlier tweaks from the same key; `reg import` exit codes are verified.
- Rollback reads manifest fields safely (`Get-PropSafe`) — older Privacy entries without `Type`/`BackupFile` no longer break rollback under StrictMode; keys created by the script are cleaned up on undo.
- **DryRun makes no system changes** — the `-DryRun` check runs before key creation and before backup export.
- **Privacy** goes through the shared safe registry layer (`Set-RegistryValueSafe`): consistent manifest, backup, DryRun and rollback.
- Debloat creates a restore point before the first change; `ScheduledDefrag` is not disabled (Windows uses it for SSD retrim).

### New features
- **Debloat [8] ULTRA Debloat BETA** — the most aggressive, test‑grade tier built on Maximum: additionally limits per‑user/sync services, more scheduled tasks, registry entries, Appx packages and autostart entries. Requires three confirmations (`YES` → `ULTRA` → `YES ULTRA`) with a full read‑only preview before the first one. Deliberately never touches Defender, Windows Update core, Store core, the shell, audio, network, GPU drivers or anticheat; services always Manual, never Disabled. Undo: Debloat [4] + restore point. Details: `ULTRA-DEBLOAT.md`.
- **[23] Engineering tools** — Preflight/Analyze/DryRun reports from `data/catalog/*.json` into the `runs\` folder. **Apply in this release writes a manifest only — it makes no system changes.**
- **HKCU warning** — when UAC elevation lands on a different administrator account than the logged‑in desktop user, the tool says so (HKCU tweaks would go to the elevated account's profile).

### Correctness and stability
- **Full syntax compatibility with PowerShell 5.1 and 7.x** — removed parser‑breaking constructs (unclosed blocks and quotes, parentheses inside interpolations, compact operators like `$x-eq'y'`), rewrote multi‑line `if` expressions used in assignments and inside hashtables. The 5.1 build contains no PS7‑only syntax (ternary `?:`, `??`, `?.`).
- **All `.ps1`/`.psm1` files saved as UTF‑8 with BOM** — correct Polish characters and UI box‑drawing under Windows PowerShell 5.1.
- Ultra Debloat: fixed the preview/apply crash caused by an inconsistent Appx‑list variable name (`DebloatUltraApps` vs `DebloatUltraAppx`); a compatibility alias keeps older references safe under `Set-StrictMode -Version Latest`.
- Unified script‑scope variable initialization (incl. `$Script:BeforeAudit` in the before/after repair diff engine) — no more "variable has not been set" errors under StrictMode.
- Repair: `Userinit` and the Sysprep log path are built from `$env:SystemRoot` (no more hard‑coded `C:\Windows`); removed the no‑op ConsentStore/`Deny` loop.
- Optimize: removed dead `$hasAnyRisk` code; fixed risk‑menu numbering — VBS/Memory Integrity is item `5)`.
- Removed the pseudo‑validation with auto‑rollback for `GameDVR_Enabled` and `Win32PrioritySeparation` (a single RAM/CPU sample after a few seconds measured noise, not the tweak's effect) — tweaks apply normally, undo is guaranteed by the manifest.
- New `Write-CatchWarn` helper on critical state‑changing paths (Debloat restore, rollback, Repair writes) — errors no longer vanish in empty `catch` blocks.
- System Score split: **HealthScore** (real condition signals: XMP, GPU driver age, RAM pressure) and **AdoptionScore** (alignment with the tool's tweaks) — a fresh Windows install is no longer penalized just for not using the tool.
- Interface: `Esc` always returns safely (never launches the default item); UI settings fall back to in‑session memory when the settings file can't be written; the hardware profile has a fallback for WMI/CIM/Storage failures.
- Clearer Debloat tier labels: Maximum = "very strong", Ultra = "most aggressive / test tier"; confirmation prompts clarified.

### Release
- `Run-Optimizer.bat`: UAC self‑elevation also works when launched **with no arguments** (an empty `-ArgumentList` used to block elevation on a plain double‑click); arguments are forwarded through environment variables, quote‑safe.
- Self‑Test: the required‑files list points at `v17_0.ps1` (no more false FAIL about a missing older loader).
- `data/catalog/services.json`: `Disabled` entries changed to `Manual` — consistent with the tool's policy.
- Menu `[23]`: Apply labels state plainly "manifest ONLY (no system changes)".
- Version number unified to `17.2` (script, UI header, changelog); documentation moved from loose `.txt` files into `README.md`, `CHANGELOG.md` and `ULTRA-DEBLOAT.md`.

## 17.0 — WinTunePro (PowerShell 5.1 + PowerShell 7)

**PL — Pełne wydanie.** Ta wersja scala wszystkie wcześniejsze aktualizacje robocze w jedną, dopracowaną całość. Najważniejsze zmiany od ostatniego publicznego wydania:

### Interfejs
- **Nowy interfejs BIOS UI** — nawigacja strzałkami ↑/↓, podświetlany pasek pokazuje aktualną pozycję, rozwijanie pod-modułów `Spacja`/`→`, zwijanie `←`, wejście `Enter`, `F1` = pomoc, `Esc` = bezpieczny powrót (nie uruchamia przypadkowo domyślnej pozycji).
- **Dwa tryby w Ustawieniach:** BIOS UI (pasek + strzałki) oraz Classic UI (klasyczne cyferki). Wybór jest globalny — w Classic UI podmenu, wybór profilu i Self-Test też działają cyferkami.
- Najgłębsze akcje w modułach (potwierdzenia, YES/NO, wybór typu) zostają cyfrowe w obu trybach.

### Nowe funkcje
- **Self-Test / Diagnostyka** — osobna pozycja menu. Szybki test wykrywa błędy parsera PowerShell z plikiem, linią, kolumną i fragmentem kodu. Pełny test sprawdza dodatkowo środowisko Windows, zapis na pulpicie, WMI/CIM, winget, DISM i SFC. Raport zapisuje się na pulpicie jako `WinTunePro-SELFTEST-*.txt`. Tylko do odczytu — nie zmienia systemu.
- **Raport błędu na pulpit** — przy twardym błędzie tworzy się `WinTunePro-BLAD-*.txt` z modułem, linią, treścią błędu, śladem stosu i wersjami, i otwiera się automatycznie. Tester tylko przeciąga plik.

### Poprawki i czytelność
- **Naprawiony crash przy wykrywaniu GPU** („empty pipe element") oraz cała klasa błędów `.Count` na pojedynczym obiekcie pod StrictMode.
- **Czytelniejsze nazwy profili** — dziwne CamelCase zamienione na proste 1–2 słowa (Laptop Gaming, Laptop Max, Biuro, Mało RAM, Bateria, Płynny, Auto Pełny).
- **Kolory wg agresywności** — zielony = bezpieczne, żółty = umiarkowane, czerwony = agresywne/maksymalne.
- **Podział na moduły** — kod w folderze `scripts\`, jeden `Run-Optimizer.bat` jako administrator; przy błędzie ładowania modułu wiadomo dokładnie który plik i linia.
- **Naprawiony launcher `.bat`** — zawsze uruchamia właściwy plik obok siebie, także po podniesieniu uprawnień.
- **Samonaprawa startu** — usuwa/przerejestrowuje zepsute zadania po starszych wersjach, co likwiduje czerwony błąd „#requires PowerShell 7.0" przy każdym starcie.

### Wersje uruchomieniowe
- **PowerShell 5.1** — działa na **wbudowanym** Windows PowerShell 5.1, bez instalowania czegokolwiek. Wymuszony UTF-8 dla polskich znaków i ramek BIOS UI; launcher zadań działa też bez PowerShell 7.
- **PowerShell 7** — wersja główna, zalecana (szybsza, aktywnie rozwijana).

---

**EN — Full release.** This version consolidates all previous working updates into one polished whole. Key changes since the last public release:

### Interface
- **New BIOS UI** — arrow navigation ↑/↓, a highlight bar shows the current position, expand sub-modules with `Space`/`→`, collapse with `←`, open with `Enter`, `F1` = help, `Esc` = safe back (won't accidentally launch the default item).
- **Two modes in Settings:** BIOS UI (bar + arrows) and Classic UI (numeric). The choice is global — in Classic UI, submenus, profile selection and Self-Test also use numbers.
- The deepest in-module actions (confirmations, YES/NO, type selection) stay numeric in both modes.

### New features
- **Self-Test / Diagnostics** — a separate menu item. The quick test detects PowerShell parser errors with file, line, column and code snippet. The full test also checks the Windows environment, Desktop write access, WMI/CIM, winget, DISM and SFC. The report is saved to the Desktop as `WinTunePro-SELFTEST-*.txt`. Read-only — makes no system changes.
- **Desktop crash report** — on a hard error, `WinTunePro-BLAD-*.txt` is created with the module, line, error message, stack trace and versions, and opens automatically. Testers just drag the file.

### Fixes & readability
- **Fixed the GPU-detection crash** ("empty pipe element") and the whole `.Count`-on-single-object class under StrictMode.
- **Clearer profile names** — odd CamelCase replaced with plain 1–2 word labels (Laptop Gaming, Laptop Max, Office, Low RAM, Battery, Snappy, Auto Full).
- **Aggression-based colors** — green = safe, yellow = moderate, red = aggressive/maximum.
- **Modular layout** — code in a `scripts\` folder, one `Run-Optimizer.bat` as admin; on a module load error you know exactly which file and line.
- **Fixed the `.bat` launcher** — always runs the correct file next to it, even after elevation.
- **Startup self-repair** — removes/re-registers broken tasks from older versions, eliminating the red "#requires PowerShell 7.0" error at every boot.

### Runtime builds
- **PowerShell 5.1** — runs on the **built-in** Windows PowerShell 5.1, no install needed. UTF-8 forced for Polish characters and BIOS UI box-drawing; the task launcher works without PowerShell 7 too.
- **PowerShell 7** — primary, recommended (faster, actively developed).

> ⚠️ BETA — use at your own risk. Back up before Maximum and Repair. / BETA — na własną odpowiedzialność. Przed trybem Maksymalnym i Naprawą zalecany backup.

---

## 16.9.6 (audit from user/community reviews)

**EN**
Reviewed against several external code reviews. Confirmed which findings were real and which were false alarms; fixed the real ones, left the false ones untouched (with proof), and re-scanned the whole file.

**Fixed (real):**
- **Parameter `$Profile` renamed to `$OptimizerProfile`.** `$Profile` is a PowerShell automatic variable (path to the user's profile script); the optimizer not only shadowed it but Smart Mode reassigned it mid-run. Renamed everywhere (45 references) with no collateral changes to `$profileMap`, `$wprProfile` or object `.Profile` reads.
- **`Export-StartLayout` guarded.** It is deprecated on Windows 11 and can be absent; the Win10 Start-reset path now checks `Get-Command` first (matching the existing `Import-StartLayout` guard) so a missing cmdlet can't throw.
- **`Import-StartLayout` .xml restore path guarded.** The restore branch used `-ErrorAction Stop` with no availability check; now wrapped in a `Get-Command` guard with a clean skip message.

**Verified FALSE ALARMS (left untouched, with proof):**
- "Missing closing braces at 7431/13567" - brace parity is a clean (26,0); nothing missing. (The reviewers who rejected this were correct.)
- "`_add` name collision (7611 vs 12286)" - both are LOCAL functions inside different parent functions, so they live in separate scopes and never collide.
- "`Start-Process @spArgs` with Hidden + redirect crashes" - already inside try/catch with conditional splatting (FIX v14.0.1).
- "`Set-ServiceStartupSafe` vs `Set-RepairServiceStartup` param mixing" - every call site uses the correct parameter (`-StartupType` vs `-Mode` respectively); no mismatch.
- Reviewer fears about `Get-Service`, `Get-Counter`, DISM and property reads are already handled by the v16.9.3-v16.9.5 safe helpers (`Get-ServiceListSafe`, `Get-CounterValueSafe`, `Get-OptionalFeatureStateSafe`, `Get-PropSafe`).

**PL**
Przejrzano wzgledem kilku zewnetrznych recenzji kodu. Potwierdzono, ktore uwagi byly realne, a ktore falszywym alarmem; realne naprawiono, falszywe zostawiono (z dowodem), caly plik przeskanowano ponownie.

**Naprawione (realne):**
- **Parametr `$Profile` przemianowany na `$OptimizerProfile`.** `$Profile` to automatyczna zmienna PowerShell (sciezka do skryptu profilu uzytkownika); optymalizator nie tylko ja przeslanial, ale Smart Mode nadpisywal ja w trakcie dzialania. Przemianowano wszedzie (45 odwolan) bez zmian w `$profileMap`, `$wprProfile` ani odczytach `.Profile` obiektow.
- **`Export-StartLayout` zabezpieczony.** Jest deprecated na Windows 11 i moze nie istniec; sciezka resetu Start dla Win10 sprawdza teraz najpierw `Get-Command` (jak istniejacy guard `Import-StartLayout`), wiec brak cmdletu nie rzuci bledem.
- **Sciezka restore .xml `Import-StartLayout` zabezpieczona.** Galaz restore uzywala `-ErrorAction Stop` bez sprawdzenia dostepnosci; teraz owinieta guardem `Get-Command` z czytelnym komunikatem pominiecia.

**Potwierdzone FALSZYWE ALARMY (zostawione, z dowodem):**
- "Brakujace klamry w 7431/13567" - parytet nawiasow to czyste (26,0); nic nie brakuje. (Recenzenci, ktorzy to odrzucili, mieli racje.)
- "Kolizja nazw `_add` (7611 vs 12286)" - obie to funkcje LOKALNE wewnatrz roznych funkcji nadrzednych, wiec sa w osobnych zakresach i nigdy nie koliduja.
- "`Start-Process @spArgs` z Hidden + redirect wywala sie" - juz jest w try/catch z warunkowym splattingiem (FIX v14.0.1).
- "Mieszanie parametrow `Set-ServiceStartupSafe` vs `Set-RepairServiceStartup`" - kazde wywolanie uzywa poprawnego parametru (`-StartupType` vs `-Mode`); brak niezgodnosci.
- Obawy recenzentow o `Get-Service`, `Get-Counter`, DISM i odczyty wlasciwosci sa juz obsluzone przez bezpieczne helpery z v16.9.3-v16.9.5 (`Get-ServiceListSafe`, `Get-CounterValueSafe`, `Get-OptionalFeatureStateSafe`, `Get-PropSafe`).

## 16.9.5 (crash fix from live BETA testing)

**EN**
- **FIXED: optimization aborted with "Attempted to perform an unauthorized operation" at New-ItemProperty.** Some HKLM registry keys are owned by TrustedInstaller or otherwise ACL-locked, so writing a value throws even for an administrator - and with no error handling it killed the whole optimization run. The registry write is now wrapped in try/catch: a protected key is logged as SKIPPED (with a yellow on-screen note) and the run continues instead of crashing.

**PL**
- **NAPRAWIONE: optymalizacja przerywala z bledem "Attempted to perform an unauthorized operation" przy New-ItemProperty.** Niektore klucze rejestru HKLM sa wlasnoscia TrustedInstaller lub maja zablokowany ACL, wiec zapis wartosci rzuca wyjatek nawet dla administratora - a bez obslugi bledu wywalalo to caly przebieg optymalizacji. Zapis do rejestru jest teraz w try/catch: chroniony klucz jest logowany jako POMINIETY (z zoltym komunikatem na ekranie), a przebieg leci dalej zamiast sie wywalic.

## 16.9.4 (crash fix from live BETA testing)

**EN**
- **FIXED: script aborted with "Service 'WaaSMedicSvc' cannot be queried ... PermissionDenied".** On Windows 11 some services (notably WaaSMedicSvc) have an ACL that blocks reading their StartType even for Administrators. Any bare `Get-Service | Select ...` enumeration that touched that property threw and killed the whole run (it happened in the before/after snapshot, the service audit and the anti-cheat scan). New helper **Get-ServiceListSafe** reads the service names first (never throws), then queries each service individually inside try/catch, marking denied ones as `AccessDenied` and moving on. All full-list enumerations now use it.
- **Also hardened:** the Get-Process snapshot pipelines (TopCpu/TopRam) and Get-ServiceAudit per-service reads are now wrapped so a single protected process/service can't abort the snapshot.

**PL**
- **NAPRAWIONE: skrypt przerywal z bledem "Service 'WaaSMedicSvc' cannot be queried ... PermissionDenied".** Na Windows 11 niektore uslugi (zwlaszcza WaaSMedicSvc) maja ACL blokujaca odczyt ich StartType nawet dla Administratora. Kazde zwykle `Get-Service | Select ...` dotykajace tej wlasciwosci rzucalo wyjatek i wywalalo caly przebieg (dzialo sie to w migawce przed/po, audycie uslug i skanie anticheata). Nowy helper **Get-ServiceListSafe** czyta najpierw nazwy uslug (nie rzuca), potem pyta o kazda usluge osobno w try/catch, oznacza odmowione jako `AccessDenied` i idzie dalej. Wszystkie pelne enumeracje korzystaja teraz z niego.
- **Dodatkowo zabezpieczone:** potoki migawki Get-Process (TopCpu/TopRam) oraz odczyty per-usluga w Get-ServiceAudit sa teraz owiniete, wiec pojedynczy chroniony proces/usluga nie przerwie migawki.

## 16.9.3 (crash fixes from live BETA testing)

**EN**
- **FIXED: script aborted with "The property 'EnableVirtualizationBasedSecurity' cannot be found on this object".** Under Set-StrictMode -Version Latest, reading a registry property that does not exist throws instead of returning null. On machines without a VBS/DeviceGuard value (common on Windows 11 Home) this killed the whole run at the Spec Sheet / environment scan. All such reads (DeviceGuard VBS x3, BitLocker ProtectionStatus x2, SMB1 EnableSMB1Protocol) now go through a StrictMode-safe helper (Get-PropSafe).
- **FIXED: "Class not registered" from Get-WindowsOptionalFeature (Hyper-V/WSL/SMB1 checks).** That cmdlet comes from the DISM module, which PowerShell 7 loads through a compatibility bridge that fails on some machines - and -ErrorAction SilentlyContinue does NOT suppress it, so the script crashed. All DISM optional-feature calls now go through a real try/catch wrapper (Get-OptionalFeatureStateSafe) that falls back to dism.exe text and otherwise returns null without crashing.
- **Restore point reliability:** the creator now auto-retries once while temporarily bypassing the built-in 24h limit (SystemRestorePointCreationFrequency=0, then restored) - the #1 reason a restore point silently failed to appear on repeat runs.
- **Cleanup:** removed the stale "Universal Windows Optimizer v13.0 + Naprawa i Odbudowa" header label (now just "WinTunePro").
- Confirmed already correct (no change needed): Maximum debloat is PERSISTENT (passes -Persist, disables autostart + telemetry tasks + provisioned Appx, saves JSON state), reversible via [13] -> [4].

**PL**
- **NAPRAWIONE: skrypt przerywal z bledem "The property 'EnableVirtualizationBasedSecurity' cannot be found on this object".** Przy Set-StrictMode -Version Latest odczyt nieistniejacej wartosci rejestru rzuca wyjatek zamiast zwrocic null. Na maszynach bez wpisu VBS/DeviceGuard (czeste na Windows 11 Home) to wywalalo caly przebieg przy Karcie specyfikacji / skanie srodowiska. Wszystkie takie odczyty (VBS DeviceGuard x3, BitLocker ProtectionStatus x2, SMB1 EnableSMB1Protocol) ida teraz przez bezpieczny helper (Get-PropSafe).
- **NAPRAWIONE: "Class not registered" z Get-WindowsOptionalFeature (sprawdzenia Hyper-V/WSL/SMB1).** Ten cmdlet pochodzi z modulu DISM, ktory PowerShell 7 laduje przez warstwe zgodnosci zawodzaca na czesci maszyn - a -ErrorAction SilentlyContinue tego NIE tlumi, wiec skrypt sie wywalal. Wszystkie wywolania DISM ida teraz przez prawdziwy try/catch (Get-OptionalFeatureStateSafe), z fallbackiem na tekst dism.exe, a w razie porazki zwracaja null bez crashu.
- **Niezawodnosc punktu przywracania:** tworzenie ponawia teraz probe raz, tymczasowo pomijajac wbudowany limit 24h (SystemRestorePointCreationFrequency=0, potem przywracany) - to glowna przyczyna cichego braku punktu przy powtornych uruchomieniach.
- **Porzadki:** usunieto nieaktualny naglowek "Universal Windows Optimizer v13.0 + Naprawa i Odbudowa" (teraz po prostu "WinTunePro").
- Potwierdzone jako juz poprawne (bez zmian): Maksymalny debloat jest TRWALY (przekazuje -Persist, wylacza autostart + zadania telemetrii + provisioned Appx, zapisuje stan JSON), odwracalny przez [13] -> [4].

## 16.9.2 (code audit - fixes on top of 16.9.1-dev)

**EN**
- Reviewed the whole script as a fresh reader (security + Windows + engineering). The hand-added [H]/[O]/[N]/[K]/[P] modules are well-built: brace parity intact, 379 functions with no duplicates, 417/417 language keys symmetric, every module backs up and restores, services go Manual (never Disabled). Four real issues were fixed; nothing was removed.
- **FIX (PS 5.1 safety):** the only ternary `?:` in the codebase (Sysprep readiness report) is now a plain if/else.
- **FIX (Hardening restore correctness):** restore previously wrote hard-coded "Windows defaults" (e.g. AutoRun=145). Since `Set-RegistryValueSafe` already records the real pre-change value in the manifest, restore now reads that value back (`Restore-RegistryFromManifest`) and only falls back to a default when no backup exists - so it can't clobber a value the user had set themselves.
- **FIX (Windows 11 Start reset):** `Import-StartLayout`/`Export-StartLayout` are deprecated on Windows 11 and have no effect there; the Win10 branch is now guarded (`Get-Command` check) so a missing cmdlet can't throw, with an honest message. The Win11 start2.bin branch was already correct.
- **FIX (managed-image safety):** disabling VBS/Memory Integrity is now skipped under `-Silent` unless the operator explicitly passes the new `-ForceRiskyInSilent` switch - prevents a surprise HVCI-off on corporate/domain images that run unattended with a broad flag set.
- Not changed (by design, tracked for later): split into .psm1 modules, Authenticode signing, winget/ARM64 fallbacks, extra preflight checks (disk space, pending reboot, BitLocker/EDR detection). These are enhancements, not bugs.

**PL**
- Przejrzano caly skrypt "swiezym okiem" (bezpieczenstwo + Windows + inzynieria). Dodane recznie moduly [H]/[O]/[N]/[K]/[P] sa dobrze zrobione: parytet nawiasow zachowany, 379 funkcji bez duplikatow, klucze jezykowe 417/417 symetryczne, kazdy modul ma backup i restore, uslugi ida na Manual (nigdy Disabled). Naprawiono cztery realne bledy; nic nie usunieto.
- **FIX (zgodnosc z PS 5.1):** jedyny ternary `?:` w kodzie (raport gotowosci Sysprep) zamieniony na if/else.
- **FIX (poprawnosc restore Hardeningu):** restore wpisywal wczesniej zaszyte "domyslne Windows" (np. AutoRun=145). Poniewaz `Set-RegistryValueSafe` juz zapisuje realna wartosc sprzed zmiany do manifestu, restore czyta teraz ta wartosc (`Restore-RegistryFromManifest`) i wraca do domyslnej tylko gdy backupu brak - wiec nie nadpisze wartosci, ktora uzytkownik ustawil sam.
- **FIX (reset Start na Windows 11):** `Import-StartLayout`/`Export-StartLayout` sa deprecated na Windows 11 i nie dzialaja tam; galaz Win10 jest teraz zabezpieczona (sprawdzenie `Get-Command`), zeby brak cmdletu nie rzucil bledem, z uczciwym komunikatem. Galaz Win11 (start2.bin) byla juz poprawna.
- **FIX (bezpieczenstwo obrazow zarzadzanych):** wylaczenie VBS/Memory Integrity jest teraz pomijane w `-Silent`, chyba ze operator poda nowy przelacznik `-ForceRiskyInSilent` - zapobiega niespodziewanemu HVCI-off na obrazach firmowych/domenowych uruchamianych bezobslugowo z szerokim zestawem flag.
- Bez zmian (swiadomie, na pozniej): podzial na moduly .psm1, podpis Authenticode, fallbacki winget/ARM64, dodatkowe preflight checks (miejsce na dysku, oczekujacy restart, wykrywanie BitLocker/EDR). To ulepszenia, nie bledy.

## 16.9.1-dev (scalone do wydan 16.9.x)

**EN**
- **NEW mode [H] Hardening** - security baseline, separate from Optimize/Debloat. `[1] Recommended` (low risk: WDigest plaintext-creds off, AutoRun off, Windows Script Host off, LLMNR off, PowerShell script-block logging on, Guest account disabled). `[2] Strict` (SMBv1 off, LSA Protection/RunAsPPL, required SMB signing - double-YES, warns about old NAS/AV compatibility). `[3]` VBS/Memory Integrity gated ON/OFF switch (double-YES to disable; **new** `Invoke-VbsEnable` finally lets you turn it back ON, which no existing mode did). `[4]` Restore.
- **NEW mode [O] OEM Preset** - detects the manufacturer (`Win32_ComputerSystem`) and offers ASUS/MSI/HP/Dell/Lenovo vendor-bloat cleanup, reusing the existing Debloat engine (`Invoke-DebloatRun`, Manual+stop, never Disabled). Only acts on services/apps actually found on the machine; undo via the existing **[13] Debloat -> [4] Restore**.
- **NEW mode [N] New Users / Sysprep.** `[1]` applies the current user's Explorer/UI tweaks to the **Default** profile hive so new local accounts inherit them - using the Microsoft-supported technique (load `NTUSER.DAT`, copy specific keys) instead of `sysprep /generalize /CopyProfile`, which Microsoft does not support for cloning a live user profile. `[2]` a read-only Sysprep readiness check (pending reboot, pending Windows Update, low disk space, Appx-provisioning errors) - it deliberately does **not** run `sysprep.exe` itself, since that's a one-way, non-reversible operation, same policy as the Repair module's stance on EFI/TPM/BCD. `[3]` restores the Default hive from backup.
- **NEW mode [K] Backup** - backs up the current user's Desktop/Documents/Pictures/Downloads/Favorites to a chosen folder/drive via `robocopy` (additive, no `/MIR`, nothing deleted at the destination) with a JSON manifest, and restores/migrates from an existing backup into a (possibly new) profile.
- **NEW mode [P] Shell Cleanup (EXPERIMENTAL, needs live testing on real Win10 and Win11 builds before wider release)** - clears Explorer/Quick-Access history, resets pinned taskbar items (Taskband key, backed up first), and resets the Start layout (Win11: removes `start2.bin` so Windows regenerates the default; Win10: `Import-StartLayout` with a minimal layout) with a `[4]` restore path. Always restarts Explorer after a change; always asks for a typed `YES` first.
- All five new modes are purely additive: no existing function bodies were modified, and every write goes through the existing `Set-RegistryDwordSafe` / `Set-ServiceStartupSafe` / manifest / restore-point machinery, so the general **[3] Rollback** safety net covers them too, on top of each module's own `[4]`/`[3]` restore option.

**PL**
- **NOWY tryb [H] Hardening** - warstwa bezpieczenstwa, oddzielna od Optymalizacji/Debloatu. `[1] Zalecane` (niskie ryzyko: WDigest plaintext-creds off, AutoRun off, Windows Script Host off, LLMNR off, logowanie script-block PowerShell on, konto Gosc wylaczone). `[2] Scisle` (SMBv1 off, LSA Protection/RunAsPPL, wymagane podpisywanie SMB - podwojne YES, ostrzega o kompatybilnosci ze starym NAS/AV). `[3]` bramkowany przelacznik VBS/Memory Integrity ON/OFF (podwojne YES do wylaczenia; **nowa** funkcja `Invoke-VbsEnable` w koncu pozwala wlaczyc go z powrotem, czego zaden istniejacy tryb nie robil). `[4]` Przywroc.
- **NOWY tryb [O] Preset OEM** - wykrywa producenta (`Win32_ComputerSystem`) i oferuje czyszczenie bloatu ASUS/MSI/HP/Dell/Lenovo, korzystajac z istniejacego silnika Debloat (`Invoke-DebloatRun`, Manual+stop, nigdy Disabled). Dziala tylko na tym, co faktycznie znaleziono na komputerze; cofniecie przez istniejace **[13] Debloat -> [4] Przywroc**.
- **NOWY tryb [N] Nowi uzytkownicy / Sysprep.** `[1]` stosuje tweaki Explorera/UI biezacego uzytkownika do hywu profilu **Default**, wiec nowe konta lokalne je odziedzicza - metoda wspierana przez Microsoft (zaladowanie `NTUSER.DAT`, skopiowanie konkretnych kluczy) zamiast `sysprep /generalize /CopyProfile`, ktorego Microsoft nie wspiera do klonowania zywego profilu uzytkownika. `[2]` test gotowosci do Sysprep tylko do odczytu (oczekujacy restart, oczekujacy Windows Update, malo miejsca na dysku, bledy provisioningu Appx) - celowo **nie** uruchamia `sysprep.exe` samemu, bo to operacja jednokierunkowa, nieodwracalna - taka sama polityka jak podejscie modulu Repair do EFI/TPM/BCD. `[3]` przywraca hyw Default z kopii.
- **NOWY tryb [K] Kopia zapasowa** - robi kopie Desktop/Dokumenty/Obrazy/Pobrane/Ulubione biezacego uzytkownika do wskazanego folderu/dysku przez `robocopy` (dodawanie, bez `/MIR`, nic nie usuwane w celu) z manifestem JSON, oraz przywraca/migruje z istniejacej kopii do (mozliwe nowego) profilu.
- **NOWY tryb [P] Czyszczenie powloki (EKSPERYMENTALNE, wymaga testow na zywo na prawdziwym Win10 i Win11 przed szerszym wydaniem)** - czysci historie Eksploratora/Szybkiego dostepu, resetuje przypiete elementy paska zadan (klucz Taskband, najpierw kopiowany), i resetuje uklad Start (Win11: usuwa `start2.bin`, Windows odtwarza domyslny; Win10: `Import-StartLayout` z minimalnym ukladem) z opcja przywrocenia `[4]`. Zawsze restartuje Explorer po zmianie; zawsze pyta o wpisanie `YES`.
- Wszystkie piec nowych trybow jest czysto addytywnych: zadna istniejaca funkcja nie zostala zmieniona, a kazdy zapis idzie przez istniejaca maszynerie `Set-RegistryDwordSafe` / `Set-ServiceStartupSafe` / manifest / punkt przywracania, wiec ogolna siatka bezpieczenstwa **[3] Przywracanie** tez je obejmuje, oprocz wlasnej opcji przywracania `[4]`/`[3]` kazdego modulu.

## 16.9.0 (Boot module + vendor services + Appx selection + update resilience)

**EN**
- **NEW mode [15] Boot.** (1) Real boot-time history straight from the Windows event log (Diagnostics-Performance Id 100): total / MainPath (to desktop) / PostBoot (background warm-up) per boot, plus the degradation events (Id 101-110) that name the exact app/driver/service that slowed a boot down. (2) A **numbered autostart list** (Run keys HKCU+HKLM+32-bit, both Startup folders, Store StartupTasks) with ON/off state and **disable-by-number** - using the very same reversible mechanisms as Debloat (backups + StartupApproved markers), so **[13] -> [4] undoes it**. (3) **Fast Startup toggle** (HiberbootEnabled, backed up, reversible). Honest note included: below a certain floor the disk and board POST decide, not a script.
- **Debloat [5] Vendor services (opt-in).** The 21-service reality from real machines, grouped (NVIDIA extras, MSI, Nahimic, Realtek, Intel graphics/mgmt, Logitech, Thrustmaster, PACE) with a plain warning per group about what stops working (RGB, overlay, audio FX, HDCP-protected video, iLok licenses). Pick groups by number, type YES, services go Manual+stop through the existing persist machinery - **[4] restores them**. NVDisplay.ContainerLocalSystem (the GPU display container) is deliberately absent.
- **Debloat [6] Appx removal with selection.** The curated catalog with numbers plus presets: **[S]afe** (basic bloat), **[G]aming** (everything listed), **[M]inimal** (Bing+Copilot only). Shows only what's actually installed; removes package + provisioned copy; Store-reinstallable.
- **Debloat [7] Re-apply + JSON export/import (update resilience).** Big Windows updates like to revert tweaks and reinstall Appx. Maximum now auto-saves its state to `%LOCALAPPDATA%\WinTunePro\maximum-state.json`; [7] re-applies the tasks/registry/Appx layer from that file (or built-in lists), and can import a state file copied from another PC.
- **[B] renamed to Guide (Przewodnik)** - resolves the long-standing name collision with mode [9] Library (recipes/history). The Guide screen also gained rows for [15] Boot and itself.

**PL**
- **NOWY tryb [15] Boot.** (1) Prawdziwa historia czasu startu prosto z dziennika zdarzen Windows (Diagnostics-Performance Id 100): total / MainPath (do pulpitu) / PostBoot (dogrzewanie tla) per rozruch, plus zdarzenia degradacji (Id 101-110) wskazujace KONKRETNA aplikacje/sterownik/usluge, ktora spowolnila start. (2) **Numerowana lista autostartu** (klucze Run HKCU+HKLM+32-bit, oba foldery Startup, StartupTaski Sklepu) ze stanem ON/off i **wylaczaniem po numerach** - na tych samych odwracalnych mechanizmach co Debloat (backupy + znaczniki StartupApproved), wiec **[13] -> [4] to cofa**. (3) **Przelacznik Fast Startup** (HiberbootEnabled, z backupem, odwracalny). W komplecie uczciwa uwaga: ponizej pewnego progu decyduje dysk i POST plyty, nie skrypt.
- **Debloat [5] Uslugi producentow (opt-in).** Realia 21 uslug z prawdziwych maszyn, pogrupowane (NVIDIA extras, MSI, Nahimic, Realtek, Intel graphics/mgmt, Logitech, Thrustmaster, PACE) z jasnym ostrzezeniem per grupa, co przestanie dzialac (RGB, overlay, efekty audio, chronione wideo HDCP, licencje iLok). Wybierasz grupy numerami, wpisujesz YES, uslugi ida na Manual+stop przez istniejaca maszynerie trwalosci - **[4] je przywraca**. NVDisplay.ContainerLocalSystem (kontener wyswietlania GPU) celowo nieobecny.
- **Debloat [6] Usuwanie Appx z wyborem.** Wyselekcjonowany katalog z numerami plus presety: **[S]afe** (podstawowy bloat), **[G]aming** (wszystko z listy), **[M]inimal** (tylko Bing+Copilot). Pokazuje tylko to, co realnie zainstalowane; usuwa pakiet + kopie provisioned; do przywrocenia ze Sklepu.
- **Debloat [7] Re-apply + eksport/import JSON (odpornosc na aktualizacje).** Duze aktualizacje Windows lubia cofac tweaki i przywracac Appx. Maksymalny zapisuje teraz automatycznie swoj stan do `%LOCALAPPDATA%\WinTunePro\maximum-state.json`; [7] naklada ponownie warstwe zadan/rejestru/Appx z tego pliku (lub list wbudowanych) i umie zaimportowac plik stanu skopiowany z innego PC.
- **[B] przemianowane na Przewodnik (Guide)** - rozwiazuje stara kolizje nazw z trybem [9] Biblioteka (przepisy/historia). Ekran Przewodnika dostal tez wiersze dla [15] Boot i samego siebie.

## 16.8.0 (pre-run preview + build-signature binding)

**EN**
- **"Show what you'll do" preview.** Before the YES confirmation, Aggressive and Maximum now print a read-only scan of exactly what will happen on THIS machine: which listed services are actually running, which apps are open, which telemetry tasks are enabled, which curated Appx are installed, every registry tweak with its target value, and every matched autostart entry (Run keys, Startup shortcuts, vendor tasks, Store StartupTasks). Nothing is changed during the preview - it exists so nobody has to type YES blind.
- **One source of truth for Maximum.** The curated lists (tasks/Appx/registry/autostart tokens) moved to script scope, shared by the preview and the executor - they can never drift apart.
- **Build-signature binding.** The author signature is now part of the program logic, not a comment: a build id and its checksum are verified at startup, at debloat entry, in Maximum and in the Spec Sheet (which also gets an author footer). Removing or editing the signature stops the script with a clear message pointing to the original repository. Honest scope: this stops casual copy-strippers, not a determined expert - the MIT license remains the legal protection.

**PL**
- **Podglad "co dokladnie zrobie".** Przed potwierdzeniem YES Agresywny i Maksymalny wypisuja teraz skan (tylko odczyt) tego, co faktycznie stanie sie na TEJ maszynie: ktore uslugi z listy realnie dzialaja, ktore aplikacje sa otwarte, ktore zadania telemetrii sa wlaczone, ktore Appx z listy sa zainstalowane, kazdy tweak rejestru z wartoscia docelowa i kazdy dopasowany wpis autostartu (klucze Run, skroty Startup, zadania producentow, StartupTaski Sklepu). Podglad niczego nie zmienia - istnieje po to, zeby nikt nie wpisywal YES w ciemno.
- **Jedno zrodlo prawdy dla Maksymalnego.** Listy (zadania/Appx/rejestr/tokeny autostartu) przeniesione do zakresu skryptu, wspolne dla podgladu i wykonania - nie moga sie rozjechac.
- **Zwiazanie sygnatury builda.** Podpis autora jest teraz czescia logiki programu, nie komentarzem: identyfikator builda i jego suma kontrolna sa weryfikowane przy starcie, przy wejsciu w debloat, w Maksymalnym i w Karcie specyfikacji (ktora dostaje tez stopke autora). Usuniecie lub edycja podpisu zatrzymuje skrypt z czytelnym komunikatem wskazujacym oryginalne repozytorium. Uczciwie: to zatrzymuje przypadkowych kopiujacych, nie zdeterminowanego eksperta - ochrona prawna pozostaje licencja MIT.

## 16.7.0 (critical startup-error fix + autostart hardening)

**EN**
- **FIXED: red PowerShell error at every system startup.** Older versions registered logon tasks (automation daemon, post-restart validation, renovation resume) using `powershell.exe` — Windows PowerShell 5.1 — while the script requires PowerShell 7, producing *"cannot be run because it contained a #requires statement for Windows PowerShell 7.0"* at each logon, often pointing at an old script filename. All our scheduled tasks now launch via **pwsh.exe** (resolved automatically), and a new **self-repair** runs once at startup: it removes or re-registers broken `UWO_*` tasks, cleans Run-key entries and Startup shortcuts that reference this optimizer with a missing file or PS 5.1. Run the new version once as admin and the boot error is gone.
- **Autostart disable now uses Windows' own OFF switch.** Removing a Run entry wasn't always enough — apps can re-create it. Maximum now also writes the **StartupApproved** "disabled" marker (the exact switch you see in Settings → Apps → Startup / Task Manager → Startup), with original bytes backed up and restored by [4].
- **Store-app startup tasks covered.** Packaged (UWP) apps like Spotify or Teams autostart through `AppModel` StartupTasks invisible to Run keys — Maximum now disables a curated set (originals backed up, [4] restores).
- **Startup folder scan covers all file types** (previously .lnk only) and the vendor/app token list grew: Ubisoft/UPC, Rockstar, Overwolf, Telegram/WhatsApp/Slack, and browser auto-launch entries (Edge/Chrome/Brave/Opera/Vivaldi).
- **Fresh-eyes code audit (full file):** language tables verified 411/411 keys, EN/PL fully symmetric, zero duplicates, zero missing T-keys; 350 functions, zero duplicate definitions; no calls to undefined functions (the two `Repair-*` candidates are properly guarded optional calls); all task-launched parameters (`-Daemon`, `-ValidateState`, `-ResumeRenovation`, `-NoPause`) present.
- Honest note: tray apps spawned by vendor **services** (NVIDIA Container, MSI services, LGHUB agent) still return — services are deliberately untouched until the opt-in "Vendor Services" module (Stage 2), because disabling them breaks RGB/overlay/audio features.

**PL**
- **NAPRAWIONE: czerwony błąd PowerShell przy każdym starcie systemu.** Starsze wersje rejestrowały zadania logowania (demon automatyzacji, walidacja po restarcie, wznowienie renowacji) przez `powershell.exe` — Windows PowerShell 5.1 — a skrypt wymaga PowerShell 7, co dawało przy każdym logowaniu *"cannot be run because it contained a #requires statement for Windows PowerShell 7.0"*, często ze starą nazwą pliku. Wszystkie nasze zadania startują teraz przez **pwsh.exe** (wykrywany automatycznie), a nowa **samonaprawa** uruchamia się raz przy starcie: usuwa lub przerejestrowuje zepsute zadania `UWO_*`, czyści wpisy Run i skróty Startup wskazujące na ten optymalizator z brakującym plikiem albo PS 5.1. Uruchom nową wersję raz jako administrator — błąd przy starcie znika.
- **Wyłączanie autostartu używa teraz własnego wyłącznika Windows.** Usunięcie wpisu Run nie zawsze wystarczało — aplikacje potrafią go odtworzyć. Maksymalny zapisuje teraz też znacznik "wyłączone" w **StartupApproved** (dokładnie ten przełącznik, który widzisz w Ustawienia → Aplikacje → Autostart / Menedżer zadań → Autostart), z backupem oryginalnych bajtów i przywracaniem przez [4].
- **Objęte zadania startowe aplikacji ze Sklepu.** Aplikacje pakietowe (UWP) jak Spotify czy Teams startują przez StartupTaski w `AppModel`, niewidoczne dla kluczy Run — Maksymalny wyłącza teraz wyselekcjonowany zestaw (oryginały backupowane, [4] przywraca).
- **Skan folderu Startup obejmuje wszystkie typy plików** (wcześniej tylko .lnk), a lista tokenów urosła: Ubisoft/UPC, Rockstar, Overwolf, Telegram/WhatsApp/Slack i wpisy auto-launch przeglądarek (Edge/Chrome/Brave/Opera/Vivaldi).
- **Świeży audyt całego kodu:** tablice językowe 411/411 kluczy, pełna symetria EN/PL, zero duplikatów, zero brakujących kluczy T; 350 funkcji, zero zduplikowanych definicji; brak wywołań nieistniejących funkcji (dwa kandydackie `Repair-*` to poprawnie zabezpieczone wywołania opcjonalne); wszystkie parametry zadań (`-Daemon`, `-ValidateState`, `-ResumeRenovation`, `-NoPause`) obecne.
- Uczciwie: aplikacje tray odpalane przez **usługi** producentów (NVIDIA Container, usługi MSI, agent LGHUB) nadal wracają — usługi celowo nieruszane do czasu modułu opt-in "Usługi producentów" (Etap 2), bo ich wyłączenie psuje RGB/overlay/audio.

## 16.6.0 (Stage 1 of 2 — code structure, no GUI yet)

**EN**
- **Maximum debloat is stronger again.** New scheduled tasks: Office telemetry (if Office is installed), Family Safety monitor/refresh (if unused). New reversible registry tweaks: Windows consumer features off (no auto-installed suggested apps/games), tailored diagnostic-data experiences off, Start recommendations off. All backed up and restored via [4], same as everything else Maximum touches.
- **Console cleanup:** removed a leftover blank-line gap that broke up the main menu list between items [9] and [10].
- **Library polish:** the [2] Optimize description no longer duplicates the profile-name list (profiles have their own dedicated section); the [13] Debloat description now reflects the real 4-tier structure; added the [14] Spec Sheet row, which was missing from the Library entirely.
- **README overhaul:** every mode now has a real what/how/why writeup (not just a one-liner), plus a shared "Safety model" section up top. Noted a naming collision worth fixing before public release: mode [9] and shortcut [B] are both called "Library" but do different things.
- Next (Stage 2): a checkbox-based "Vendor Services" module (NVIDIA/MSI/Realtek/Intel/Logitech, opt-in, per-service warnings) and Appx removal with checkboxes + presets (Safe/Gaming/Minimal), replacing Maximum's fixed list.

**PL**
- **Maksymalny debloat znów mocniejszy.** Nowe zaplanowane zadania: telemetria Office (jeśli zainstalowany), monitor/odświeżanie Family Safety (jeśli nieużywane). Nowe odwracalne tweaki rejestru: treści konsumenckie Windows off (brak auto-instalowanych sugerowanych apek/gier), spersonalizowane doświadczenia diagnostyczne off, rekomendacje Start off. Wszystko backupowane i przywracane przez [4], tak jak reszta Maksymalnego.
- **Porządek w konsoli:** usunięta zbędna pusta linia rozrywająca listę menu głównego między pozycją [9] a [10].
- **Porządek w Bibliotece:** opis [2] Optymalizacja nie dubluje już listy nazw profili (profile mają własną, dedykowaną sekcję); opis [13] Debloat odzwierciedla teraz realną strukturę 4 poziomów; dodany wiersz [14] Karta specyfikacji, którego w Bibliotece w ogóle brakowało.
- **Przebudowa README:** każdy tryb ma teraz realny opis co/jak/po co (nie jednolinijkowiec), plus wspólna sekcja „Model bezpieczeństwa" na górze. Odnotowana kolizja nazw warta poprawienia przed publicznym wydaniem: tryb [9] i skrót [B] nazywają się oba „Biblioteka", ale robią co innego.
- Dalej (Etap 2): moduł „Usługi producentów" z checkboxami (NVIDIA/MSI/Realtek/Intel/Logitech, opt-in, ostrzeżenia per usługa) i usuwanie Appx z checkboxami + presetami (Safe/Gaming/Minimal), zamiast sztywnej listy w Maksymalnym.

## 16.5.0

**EN**
- **Maximum debloat now PERSISTS across reboot.** The previous Maximum only *closed* background apps, so vendor tools (NVIDIA App, MSI Center, launchers, etc.) relaunched on the next boot. Maximum now also **disables their autostart** — matching curated vendor/app tokens in:
  - **Run keys** (HKCU + HKLM, incl. 32-bit) — matched entries are backed up and removed.
  - **Startup folders** (.lnk) — matched shortcuts are moved to `%LOCALAPPDATA%\WinTunePro\StartupBackup`.
  - **Vendor scheduled tasks** — matched by EXE path (so Windows tasks in system32 are never touched) and disabled.
- **Provisioned Appx removal** added, so removed apps don't return after Windows updates or for new users.
- **[4] Restore** now also restores Run-key entries, moves Startup shortcuts back, and re-enables the disabled tasks. (Removed Appx is still reinstalled from the Store.)
- **Honest limits (unchanged stance):** it still never touches the shell, Store/Edge/Terminal, Defender or VBS, uses Manual (not Disabled) for services, and does NOT auto-disable vendor *services* (e.g. NVIDIA Container, MSI services) because that can break GPU/hardware features. Windows Input Experience (TextInputHost) is a shell/input component, not bloat, and is left alone.

**PL**
- **Maksymalny debloat TERAZ przetrwa restart.** Poprzedni Maksymalny tylko *zamykał* aplikacje tła, więc narzędzia producentów (NVIDIA App, MSI Center, launchery itd.) wracały przy następnym starcie. Maksymalny teraz dodatkowo **wyłącza ich autostart** — dopasowując wyselekcjonowane tokeny w:
  - **kluczach Run** (HKCU + HKLM, też 32-bit) — dopasowane wpisy są backupowane i usuwane,
  - **folderach Startup** (.lnk) — dopasowane skróty przenoszone do `%LOCALAPPDATA%\WinTunePro\StartupBackup`,
  - **zadaniach producentów** — dopasowanych po ścieżce EXE (więc zadania Windows w system32 nietknięte) i wyłączanych.
- Dodane **usuwanie provisioned Appx**, żeby usunięte aplikacje nie wracały po aktualizacjach Windows ani dla nowych użytkowników.
- **[4] Przywróć** teraz też przywraca wpisy Run, przenosi skróty Startup z powrotem i włącza wyłączone zadania. (Usunięte Appx nadal ze Sklepu.)
- **Uczciwe granice (bez zmian):** nadal nie rusza powłoki, Store/Edge/Terminala, Defendera ani VBS, używa Manual (nie Disabled), i NIE wyłącza automatem *usług* producentów (np. NVIDIA Container, usługi MSI), bo to psuje funkcje GPU/sprzętu. „Środowisko wprowadzania danych" (TextInputHost) to komponent powłoki/wprowadzania, nie bloat — zostaje nietknięte.

## 16.4.0

**EN**
- **Maximum debloat is now much stronger - and still reversible.** On top of the persistent service/app stop, the Maximum tier ([13] → [3], double-YES) now also:
  - **Disables curated telemetry/maintenance scheduled tasks** (Compatibility Appraiser, ProgramDataUpdater, Consolidator, UsbCeip, WinSAT, ScheduledDefrag, DiskDiagnostic, Feedback/Siuf, QueueReporting, etc.) — per community guidance this is the single biggest idle-CPU lever, since Windows re-wakes work via Task Scheduler even after services are stopped.
  - **Removes a curated safe bloatware Appx list** (Bing News/Weather, GetHelp, Get Started, Solitaire, People, To Do, Feedback Hub, Maps, Zune Music/Video, Clipchamp, consumer Teams, Power Automate, Office Hub, Mail/Calendar, Copilot). All reinstallable from the Microsoft Store.
  - **Applies reversible registry tweaks** (Game DVR off, background apps off, Delivery Optimization off).
- **[4] Restore** now also re-enables the disabled scheduled tasks and restores the registry tweaks; removed Appx apps are listed so you can reinstall them from the Store.
- **Hard safety line (honest):** Maximum never removes the Store/Edge/Terminal/shell/framework packages, never disables VBS/HVCI/Defender or Windows Update core, and uses Manual (not Disabled) for services. Below-100 processes is attempted but not guaranteed; truly forcing it would require removing shell/Appx components that can brick the system, which is out of scope. FPS is unaffected; the wins are RAM, boot time and fewer idle CPU spikes.

**PL**
- **Maksymalny debloat jest dużo mocniejszy - i nadal odwracalny.** Poza trwałym zatrzymaniem usług/aplikacji, tryb Maksymalny ([13] → [3], podwójne YES) teraz dodatkowo:
  - **Wyłącza wyselekcjonowane zadania telemetrii/utrzymania** (Compatibility Appraiser, ProgramDataUpdater, Consolidator, UsbCeip, WinSAT, ScheduledDefrag, DiskDiagnostic, Feedback/Siuf, QueueReporting itd.) — wg społeczności to największy pojedynczy lewar na idle CPU, bo Windows budzi pracę przez Harmonogram nawet po wyłączeniu usług.
  - **Usuwa wyselekcjonowaną, bezpieczną listę bloatware Appx** (Bing News/Weather, GetHelp, Get Started, Saper/Solitaire, People, To Do, Feedback Hub, Mapy, Zune Music/Video, Clipchamp, konsumencki Teams, Power Automate, Office Hub, Poczta/Kalendarz, Copilot). Wszystko do przywrócenia ze Sklepu.
  - **Stosuje odwracalne tweaki rejestru** (Game DVR off, aplikacje w tle off, Delivery Optimization off).
- **[4] Przywróć** teraz też włącza z powrotem wyłączone zadania i przywraca tweaki rejestru; usunięte aplikacje Appx są wypisane do przywrócenia ze Sklepu.
- **Twarda granica bezpieczeństwa (uczciwie):** Maksymalny nigdy nie usuwa Store/Edge/Terminala/powłoki/frameworków, nie wyłącza VBS/HVCI/Defendera ani rdzenia Windows Update, i używa Manual (nie Disabled). Poniżej 100 procesów jest próbowane, ale niegwarantowane; realne wymuszenie tego wymagałoby usuwania komponentów powłoki/Appx, co może zabić system — to poza zakresem. FPS się nie zmienia; zysk to RAM, czas bootu i mniej skoków CPU w idle.

## 16.3.0

**EN**
- **New module [14] Spec Sheet.** One press exports a full device specification to a dated text file on your Desktop (`WinTunePro_DeviceSpec_YYYYMMDD_HHMMSS.txt`) and opens it — no questions. Read-only, not analysis: OS + DisplayVersion, motherboard/BIOS, system model (laptop/desktop), CPU, GPU(s), RAM modules, storage + volumes, active network adapters. Made to send to an IT person, and to re-export after a Windows update to compare.
- **Debloat Maximum tier.** Mode [13] now has [1] Standard, [2] Aggressive, [3] **Maximum** and [4] Restore. Maximum is the strongest **persistent** debloat (sets the most safe services to Manual and closes the most apps), gated behind a **double YES** and an "only if you know what you are doing" warning. It tries to push process count below 100 on bloated systems but does not guarantee it, and stays shell-safe (Manual, never Disabled; never touches Explorer/Start/taskbar, game, anticheat, GPU or core services). The Standard tier was widened (more safe background/UWP apps closed).

**PL**
- **Nowy moduł [14] Karta specyfikacji.** Jedno wciśnięcie eksportuje pełną specyfikację urządzenia do datowanego pliku tekstowego na pulpicie (`WinTunePro_DeviceSpec_RRRRMMDD_GGMMSS.txt`) i otwiera go — bez pytań. Tylko do odczytu, nie analiza: system + DisplayVersion, płyta główna/BIOS, model (laptop/desktop), CPU, GPU, moduły RAM, dyski + woluminy, aktywne karty sieciowe. Do wysłania informatykowi i do ponownego eksportu po aktualizacji w celu porównania.
- **Tryb Maksymalny w Debloacie.** Tryb [13] ma teraz [1] Standardowy, [2] Agresywny, [3] **Maksymalny** i [4] Przywróć. Maksymalny to najmocniejszy **trwały** debloat (najwięcej bezpiecznych usług na Manual i najwięcej zamkniętych aplikacji), za **podwójnym YES** i ostrzeżeniem „tylko jeśli wiesz co robisz". Próbuje zejść poniżej 100 procesów na zabloatowanych systemach, ale tego nie gwarantuje; pozostaje bezpieczny dla powłoki (Manual, nigdy Disabled; nie rusza Explorera/Start/paska, gry, anticheata, GPU ani usług krytycznych). Standardowy poszerzony (więcej bezpiecznych aplikacji tła/UWP).

## 16.2.0

**EN**
- **Aggressive Debloat tier.** Mode [13] now has [1] Game debloat (temporary, safe), [2] **Aggressive debloat** and [3] Restore everything. Aggressive asks **Permanent or Temporary**, then requires typing **YES** to confirm, then closes a much larger set of launchers/vendor helpers/UWP helpers and limits more services. Persistent uses **Manual (not Disabled)** and stays shell-safe (never touches Explorer/Start/taskbar, game, anticheat, GPU or core/audio/network/security). Fully reversible via [3] + the automatic restore point. Realistic cut is largest on bloated systems (250+ processes); a clean ~90-process system has little to trim.
- **Menu keys remapped:** Language is now **[L]** (logical), Library is now **[B]**, and **[J] was removed**. Applies to the main menu and the profile screen; the old silent `B`=back alias was dropped (back is `[0]`).

**PL**
- **Tryb agresywnego Debloatu.** Tryb [13] ma teraz [1] Debloat dla gier (tymczasowy, bezpieczny), [2] **Agresywny debloat** i [3] Przywróć wszystko. Agresywny pyta **Stała czy Tymczasowa**, potem wymaga wpisania **YES**, następnie zamyka znacznie większy zestaw launcherów/helperów producentów/UWP i ogranicza więcej usług. Trwały używa **Manual (nie Disabled)** i jest bezpieczny dla powłoki (nie rusza Explorera/Start/paska, gry, anticheata, GPU ani usług krytycznych). W pełni odwracalny przez [3] + automatyczny punkt przywracania. Realny spadek jest największy na zabloatowanych systemach (250+ procesów); czysty ~90‑procesowy nie ma czego ścinać.
- **Przemapowane klawisze:** Language to teraz **[L]** (na logikę), Biblioteka to **[B]**, a **[J] usunięty**. Dotyczy menu głównego i ekranu profilu; stary cichy alias `B`=wstecz usunięty (wstecz to `[0]`).

## 16.1.0

**EN**
- **Stronger, still-reversible Debloat [13].** Larger curated safe service/app lists; new **[3] Persistent boot debloat** that sets safe services to Manual so they don't auto-start (faster boot, lower idle) — fully reversible via **[4] Restore everything** (restarts services + restores original startup types). Shows process count **and RAM used** before/after.
- **[L] Library shortcut** in the main menu **and on the profile-selection screen** (two entry points) — opens plain-language descriptions of every mode **and every optimization profile** (documentation only, changes nothing). Both the mode menu and the profile menu are trimmed to 2–3 words per entry; full descriptions live behind [L] and in `PROFILES.md`.
- Author tag added in the script (`jaqøæs`) + repo URL.

**PL**
- **Mocniejszy, wciąż odwracalny Debloat [13].** Większe wyselekcjonowane bezpieczne listy usług/aplikacji; nowy **[3] Trwały debloat startu** ustawiający bezpieczne usługi na Manual, by nie startowały z systemem (szybszy boot, niższy idle) — w pełni cofalny przez **[4] Przywróć wszystko** (uruchamia usługi + przywraca oryginalny typ startu). Pokazuje liczbę procesów **i zużycie RAM** przed/po.
- **Skrót [L] Biblioteka** w menu głównym **i na ekranie wyboru profilu** (dwa wejścia) — otwiera opisy każdego trybu **oraz każdego profilu optymalizacji** po ludzku (tylko dokumentacja, nic nie zmienia). Menu trybów i menu profili skrócone do 2–3 słów; pełne opisy są pod [L] i w `PROFILES.md`.
- Dodany podpis autora w skrypcie (`jaqøæs`) + URL repo.

## 16.0.0

**EN**
- New mode **[13] Debloat** — a reversible, anticheat-safe "background trim for gaming". It creates an automatic System Restore point, then stops a curated SAFE set of services and closes known background apps; everything is undone via the in-mode **[3] Restore**. It never touches the game, anticheat, GPU driver or core services, and stops only services from an explicit safe list (no kill-all). Includes a safe tier [1] and an opt-in aggressive tier [2] (extra confirmation; also closes launchers).
- **English is now the default UI language** (global-facing). Force Polish with `-Language pl`; `-Language auto` still detects from the system UI culture.

**PL**
- Nowy tryb **[13] Debloat** — odwracalne, bezpieczne dla anticheata „odciążenie tła pod gry". Tworzy automatyczny punkt przywracania, potem zatrzymuje wyselekcjonowany BEZPIECZNY zestaw usług i zamyka znane aplikacje w tle; wszystko cofa się przez **[3] Przywróć** w trybie. Nigdy nie rusza gry, anticheata, sterownika GPU ani usług krytycznych, a zatrzymuje wyłącznie usługi z jawnej, bezpiecznej listy (bez „kill-all"). Zawiera tryb bezpieczny [1] i opcjonalny agresywny [2] (dodatkowe potwierdzenie; zamyka też launchery).
- **Angielski jest teraz domyślnym językiem UI** (pod widownię globalną). Polski wymusisz przez `-Language pl`; `-Language auto` nadal wykrywa język z interfejsu systemu.

## 15.9.0

**EN**
- Shorter startup menu: every mode description trimmed to a one‑liner; full descriptions moved to `PROFILES.md` and the in‑app Library.
- Fixed the mode prompt label `[1-11]` → `[1-12]` (input validation already accepted 1–12; only the label was wrong).
- Automatic language: the interactive language question was removed. Language is detected from the system UI culture (`Get-UICulture`) and can still be forced with `-Language PL|EN`.
- Disk benchmark rewritten: writes random data and flushes to the physical device on the system drive, so SSD compression or a `%TEMP%` on another drive no longer skews the throughput number.
- Added a bilingual `Run-Optimizer.bat` launcher (self‑elevates, finds the `.ps1`, ensures PowerShell 7, runs the script).
- Repo files added: `README.md`, `PROFILES.md`, `LICENSE`, this `CHANGELOG.md`.

**PL**
- Krótsze menu startowe: każdy opis trybu skrócony do jednej linii; pełne opisy przeniesione do `PROFILES.md` i Biblioteki w aplikacji.
- Poprawiona etykieta promptu `[1-11]` → `[1-12]` (walidacja i tak przyjmowała 1–12; błędna była tylko etykieta).
- Automatyczny język: usunięto interaktywne pytanie o język. Język wykrywany z języka interfejsu systemu (`Get-UICulture`), nadal można wymusić przez `-Language PL|EN`.
- Przepisany benchmark dysku: zapis losowych danych i flush na fizyczny nośnik na dysku systemowym, więc kompresja SSD ani `%TEMP%` na innym dysku nie zakłamują wyniku.
- Dodany dwujęzyczny launcher `Run-Optimizer.bat` (sam podnosi uprawnienia, znajduje `.ps1`, sprawdza PowerShell 7, uruchamia skrypt).
- Dodane pliki repo: `README.md`, `PROFILES.md`, `LICENSE`, ten `CHANGELOG.md`.

> Not in this release / Poza tym wydaniem: the aggressive background‑process / "Game Focus" module (still in design) and the full English‑comment translation pass.
