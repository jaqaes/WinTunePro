# Changelog

## 17.2 - WinTunePro PS5/PS7 Ultra Debloat BETA

**Główne wydanie.** WinTunePro v17.2 to wspólne wydanie dla dwóch paczek programu:

- WinTunePro PS5 v17.2 Ultra Debloat BETA
- WinTunePro PS7 v17.2 Ultra Debloat BETA

Wersja 17.2 scala zmiany przygotowywane wcześniej jako etap roboczy 17.0. Nie jest tu traktowana jako osobna główna wersja. Ten changelog opisuje finalny zakres wydania 17.2: rozdzielenie buildów, podział projektu na moduły, stabilizację Debloatu, poprawki interfejsu, raportowanie błędów i przygotowanie programu pod dalszy rozwój.

## Buildy i struktura projektu

- Rozdzielono program na osobne buildy dla Windows PowerShell 5.1 i PowerShell 7.
- Build PS5 został przygotowany pod Windows PowerShell 5.1.
- Build PS7 pozostaje wersją dla PowerShell 7.
- Podzielono funkcje programu na osobne moduły i pojedyncze pliki.
- Ograniczono zależność od jednej dużej monolitycznej struktury.
- Przy błędzie ładowania modułu łatwiej ustalić plik, linię i miejsce problemu.
- Nowe funkcje v17.2 zostały wpięte w stary panel zamiast działania jako osobny projekt techniczny.
- Głównym launcherem pozostaje `Run-Optimizer.bat`.

## Interfejs

- Zachowano Classic UI jako domyślny sposób obsługi programu.
- Dodano opcjonalny BIOS UI jako interaktywny panel konsolowy.
- Dodano sterowanie strzałkami i podświetlany pasek aktywnej pozycji.
- Dodano obsługę `Enter`, `Esc`, `Spacja`, `←`, `→`, `↑`, `↓`.
- W Classic UI podmenu i profile można wybierać cyferkami.
- W BIOS UI cyfry i litery mogą być ukrywane, żeby menu wyglądało czyściej.
- Zmieniono menu języka na rozwijane menu interfejsu z wyborem Polski / English.
- Dodano krótką instrukcję sterowania i pasek pomocy ze skrótami klawiszowymi.
- Poprawiono migotanie ekranu podczas poruszania się po menu.
- Poprawiono strukturę menu tak, żeby główne moduły zostały na pierwszym poziomie.
- Usunięto sztuczne podmoduły i zachowano logikę starego panelu.

## Czytelność i oznaczenia agresywności

- Uproszczono nazwy profili, modułów, komunikatów i poziomów Debloatu.
- Wprowadzono kolorystykę według agresywności działania.
- Tryby bezpieczne, umiarkowane, mocne i testowe są łatwiejsze do odróżnienia.
- Doprecyzowano znaczenie poziomów:
 - Maksymalny = bardzo mocny profil.
 - Ultra = najbardziej agresywny profil publiczny, przeznaczony do testów.

## Self-Test i raporty błędów

- Dodano Self-Test / Diagnostykę testera.
- Self-Test sprawdza parser PowerShell, ładowanie modułów oraz błędy z informacją o pliku, linii i kolumnie.
- Dodano raport TXT generowany na pulpicie.
- Przy twardym błędzie program tworzy automatyczny raport na pulpicie.
- Raport zawiera między innymi miejsce błędu, plik, linię, treść błędu, wersję WinTunePro, wersję PowerShell i wersję Windows.
- Tester może opublikować wygenerowany raport w sekcji Zgłoś błąd bez przepisywania błędu z konsoli.

## Debloat, restore i rollback

- Dodano Ultra Debloat BETA jako najmocniejszy profil publiczny.
- Ultra Debloat bazuje na Maximum Debloat i mocniej ogranicza tło systemu, autostart, zadania, aplikacje oraz elementy konsumenckie.
- Profil wymaga kilku potwierdzeń przed wykonaniem.
- Celem Ultra Debloat jest ograniczenie liczby procesów w tle oraz zmniejszenie użycia RAM i CPU bez tworzenia niestabilnego custom Windowsa.
- Ultra Debloat celowo nie usuwa ani nie wyłącza krytycznych składników Windows: Defender, Windows Update core, Microsoft Store core, Explorer / Start, audio, sieć, GPU, mechanizmy odzyskiwania, powłoka systemowa i anticheat.
- Wprowadzono trwały restore Debloatu zapisywany do:

```txt
%LOCALAPPDATA%\WinTunePro\debloat-restore.json
```

- Cofanie działa po zamknięciu programu i po ponownym uruchomieniu systemu.
- Debloat `[4] Przywróć wszystko` nie jest już zależny tylko od bieżącej sesji.
- Rollback rejestru wykonuje cofanie od najnowszych wpisów do najstarszych.
- Dodano mocniejsze zabezpieczenia cofania dla Debloat i Ultra Debloat.

## DryRun, Privacy, Repair i Optimize

- Poprawiono DryRun tak, aby podgląd nie modyfikował systemu i nie tworzył pustych kluczy rejestru.
- Moduł Privacy został przepięty przez bezpieczniejszą warstwę zapisu rejestru z manifestem, backupem i zgodnością z rollbackiem.
- Poprawiono moduł Repair.
- Usunięto hardkodowane `C:\Windows`; ścieżki systemowe korzystają teraz z `$env:SystemRoot`.
- Poprawiono ścieżki związane z Sysprep.
- Usunięto błędną pętlę ConsentStore / Deny.
- Poprawiono logikę menu i numerację opcji w module Optimize.
- Usunięto martwy kod związany z wykrywaniem ryzyka profilu.
- Usunięto pseudo-walidację dla `GameDVR_Enabled` i `Win32PrioritySeparation`, ponieważ mierzyła szum zamiast realnego efektu.
- Usunięto ryzykowne wyłączanie `ScheduledDefrag` z agresywnego Debloatu, ponieważ Windows używa tego zadania między innymi do retrim SSD.

## Narzędzia inżynierskie v17.2

- Dodano moduł `[23] Narzędzia inżynierskie v17.2`.
- Moduł został dodany do starego menu jako normalna część programu.
- Dodano raporty Preflight, Analyze i DryRun.
- Raporty korzystają z katalogów `data/catalog/*.json`.
- Raporty są zapisywane do folderu `runs`.
- Naprawiono tworzenie folderu `runs`, żeby moduł nie wywalał się na braku katalogu.
- Apply w tym wydaniu zapisuje wyłącznie manifest i nie wykonuje zmian w systemie.

## Stabilność, logowanie i ocena systemu

- Naprawiono błędy parsera PowerShell.
- Naprawiono problemy z ładowaniem modułów.
- Poprawiono zgodność składni z PowerShell 5.1 i PowerShell 7.
- Build PS5 nie powinien zawierać składni dostępnej tylko w PowerShell 7.
- Pliki skryptów zapisano jako UTF-8 z BOM dla lepszej zgodności z Windows PowerShell 5.1.
- Naprawiono błąd Ultra Debloat związany z niespójną nazwą zmiennej listy Appx.
- Ujednolicono inicjalizację zmiennych skryptowych.
- Ograniczono błędy typu `variable has not been set` pod StrictMode.
- Dodano lepsze logowanie krytycznych błędów przez `Write-CatchWarn`.
- Błędy w rollbacku, debloacie i repair nie powinny znikać po cichu.
- Rozdzielono ocenę systemu na `HealthScore` i `AdoptionScore`.
- `HealthScore` pokazuje realną kondycję systemu.
- `AdoptionScore` pokazuje zgodność z tweakami WinTunePro.

## Launcher, HKCU i dokumentacja

- Poprawiono `Run-Optimizer.bat`, żeby nie gubił argumentów przy podnoszeniu uprawnień.
- Uproszczono uruchamianie programu.
- Dodano ostrzeżenie HKCU, gdy program działa na innym koncie administratora niż użytkownik pulpitu.
- Uporządkowano nazewnictwo głównego pliku na `v17_0`.
- Skrócono komentarz wersji w skrypcie.
- Pełna historia zmian jest teraz w `CHANGELOG.md`.
- Zaktualizowano `README.md`, `CHANGELOG.md`, pliki informacyjne i opisy dla testerów.
- Dodano i poprawiono pliki informacyjne dla integracji v17.2 oraz Ultra Debloat.

## Podsumowanie wydania 17.2

WinTunePro v17.2 jest głównym wydaniem porządkującym projekt po dużej przebudowie. Najważniejszy kierunek tej wersji to stabilność, czytelność, odwracalność zmian, osobne buildy PS5/PS7, lepsze raportowanie błędów i bezpieczniejszy Debloat.

## 17.2 - WinTunePro PS5/PS7 Ultra Debloat BETA (EN)

**Main release.** WinTunePro v17.2 is a shared release for two separate program packages:

- WinTunePro PS5 v17.2 Ultra Debloat BETA
- WinTunePro PS7 v17.2 Ultra Debloat BETA

Version 17.2 merges the changes previously prepared as the 17.0 work stage. It is not treated here as a separate main release. This changelog describes the final scope of the 17.2 release: separated builds, modular project structure, Debloat stabilization, interface improvements, error reporting and preparation for further development.

## Builds and project structure

- Split the program into separate builds for Windows PowerShell 5.1 and PowerShell 7.
- The PS5 build was prepared for Windows PowerShell 5.1.
- The PS7 build remains the version for PowerShell 7.
- Program functions were split into separate modules and individual files.
- Reduced dependency on one large monolithic structure.
- When a module loading problem occurs, it is easier to identify the file, line and place of the issue.
- New v17.2 functions were integrated into the old panel instead of running as a separate technical project.
- The main launcher remains `Run-Optimizer.bat`.

## Interface

- Kept Classic UI as the default way to use the program.
- Added optional BIOS UI as an interactive console panel.
- Added arrow-key navigation and a highlighted active selection bar.
- Added support for `Enter`, `Esc`, `Space`, `←`, `→`, `↑`, `↓`.
- In Classic UI, submenus and profiles can still be selected with numbers.
- In BIOS UI, numbers and letters can be hidden to make the menu look cleaner.
- Changed the language menu into an expandable interface menu with Polish / English selection.
- Added a short control guide and a keyboard shortcut help bar.
- Reduced screen flickering while moving through the menu.
- Improved the menu structure so the main modules remain on the first level.
- Removed artificial submodules while preserving the old panel logic.

## Readability and aggression labels

- Simplified names of profiles, modules, messages and Debloat levels.
- Added colors based on action aggressiveness.
- Safe, moderate, strong and test modes are now easier to distinguish.
- Clarified level meanings:
 - Maximum = very strong profile.
 - Ultra = the most aggressive public profile, intended for testing.

## Self-Test and error reports

- Added Self-Test / tester diagnostics.
- Self-Test checks the PowerShell parser, module loading and errors with file, line and column information.
- Added TXT report generation on the Desktop.
- On a hard error, the program creates an automatic report on the Desktop.
- The report includes, among other things, the error location, file, line, error message, WinTunePro version, PowerShell version and Windows version.
- The tester can publish the generated report in the Report bug section without copying the error manually from the console.

## Debloat, restore and rollback

- Added Ultra Debloat BETA as the strongest public profile.
- Ultra Debloat is based on Maximum Debloat and more strongly limits background activity, autostart, tasks, apps and consumer components.
- The profile requires several confirmations before execution.
- The goal of Ultra Debloat is to reduce the number of background processes and lower RAM/CPU usage without turning Windows into an unstable custom build.
- Ultra Debloat deliberately does not remove or disable critical Windows components: Defender, Windows Update core, Microsoft Store core, Explorer / Start, audio, network, GPU, recovery mechanisms, system shell and anticheat.
- Added persistent Debloat restore saved to:

```txt
%LOCALAPPDATA%\WinTunePro\debloat-restore.json
```

- Restore works after closing the program and after restarting the system.
- Debloat `[4] Restore everything` is no longer dependent only on the current session.
- Registry rollback restores entries from newest to oldest.
- This reduces the risk of reapplying earlier tweaks during restore.
- Added stronger restore safeguards for Debloat and Ultra Debloat.

## DryRun, Privacy, Repair and Optimize

- Improved DryRun so the preview does not modify the system and does not create empty registry keys.
- The Privacy module was moved to a safer registry write layer with a manifest, backup and rollback compatibility.
- Improved the Repair module.
- Removed hardcoded `C:\Windows`; system paths now use `$env:SystemRoot`.
- Fixed Sysprep-related paths.
- Removed the incorrect ConsentStore / Deny loop.
- Improved menu logic and option numbering in the Optimize module.
- Removed dead code related to profile risk detection.
- Removed pseudo-validation for `GameDVR_Enabled` and `Win32PrioritySeparation` because it measured noise instead of real effect.
- Removed risky `ScheduledDefrag` disabling from aggressive Debloat because Windows uses this task, among other things, for SSD retrim.

## Engineering tools v17.2

- Added `[23] Engineering tools v17.2`.
- The module was added to the old menu as a normal part of the program.
- Added Preflight, Analyze and DryRun reports.
- Reports use catalogs from `data/catalog/*.json`.
- Reports are saved to the `runs` folder.
- Fixed `runs` folder creation so the module does not crash when the directory is missing.
- Apply in this release writes only the manifest and does not make system changes.

## Stability, logging and system score

- Fixed PowerShell parser errors.
- Fixed module loading problems.
- Improved syntax compatibility with PowerShell 5.1 and PowerShell 7.
- The PS5 build should not contain syntax available only in PowerShell 7.
- Script files were saved as UTF-8 with BOM for better compatibility with Windows PowerShell 5.1.
- Fixed Ultra Debloat issue caused by an inconsistent Appx list variable name.
- Unified script variable initialization.
- Reduced `variable has not been set` errors under StrictMode.
- Added better critical error logging through `Write-CatchWarn`.
- Errors in rollback, Debloat and Repair should no longer disappear silently.
- Split system scoring into `HealthScore` and `AdoptionScore`.
- `HealthScore` shows the real condition of the system.
- `AdoptionScore` shows alignment with WinTunePro tweaks.

## Launcher, HKCU and documentation

- Fixed `Run-Optimizer.bat` so it does not lose arguments during elevation.
- Simplified program startup.
- Added an HKCU warning when the program runs under a different administrator account than the desktop user.
- Cleaned up the main file naming to `v17_0`.
- Shortened the version comment inside the script.
- Full history is now stored in `CHANGELOG.md`.
- Updated `README.md`, `CHANGELOG.md`, information files and tester descriptions.
- Added and improved information files for v17.2 integration and Ultra Debloat.

## 17.2 release summary

WinTunePro v17.2 is the main release that organizes the project after a large rebuild. The main direction of this version is stability, readability, reversibility of changes, separate PS5/PS7 builds, better error reporting and safer Debloat.

# Archiwum poprzednich wersji

Zmiany z wersji roboczej 17.0 zostały włączone do głównego wydania 17.2, dlatego nie są powtarzane jako osobna pełna sekcja.

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
