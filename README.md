# WinTunePro

EN: Windows tuning, diagnostics and recovery tools focused on gaming, system responsiveness and controlled changes with backup and rollback.

PL: Narzędzie do optymalizacji, diagnostyki i przywracania Windows, nastawione na gry, responsywność systemu oraz kontrolowane zmiany z kopią zapasową i rollbackiem.

Version / Wersja: 18.0.0 RC1
Status: Prerelease / Wydanie przedpremierowe
License / Licencja: MIT
Platform: Windows 10 / Windows 11
Runtime / Środowisko: Windows PowerShell 5.1 / PowerShell 7
Languages / Języki: English / Polski

## Download / Pobierz

EN: Download the complete release ZIP and extract it before running the tool. The package contains two editions:

- WinTunePro-PS7: requires PowerShell 7.
- WinTunePro-PS5: uses the built-in Windows PowerShell 5.1.

Both editions provide the same feature set. Keep the complete folder structure, including scripts, data and src. Do not launch individual scripts copied out of the package.

PL: Pobierz kompletne archiwum ZIP wydania i rozpakuj je przed uruchomieniem. Paczka zawiera dwie edycje:

- WinTunePro-PS7: wymaga PowerShell 7.
- WinTunePro-PS5: korzysta z wbudowanego Windows PowerShell 5.1.

Obie edycje oferują ten sam zestaw funkcji. Zachowaj całą strukturę katalogów, w tym scripts, data i src. Nie uruchamiaj pojedynczych skryptów wyjętych z paczki.

## How to run / Jak uruchomić

EN: Open the selected edition folder and double-click Run-Optimizer.bat. The launcher requests administrator permissions and checks package integrity.

PowerShell 7 installation is not automatic by default. If it is missing, install it yourself or explicitly allow installation by setting WTP_ALLOW_ONLINE_INSTALL=1.

PL: Otwórz folder wybranej edycji i kliknij dwukrotnie Run-Optimizer.bat. Launcher poprosi o uprawnienia administratora i sprawdzi spójność plików paczki.

PowerShell 7 nie jest domyślnie instalowany automatycznie. Jeśli go brakuje, zainstaluj go samodzielnie albo jawnie dopuść instalację przez ustawienie WTP_ALLOW_ONLINE_INSTALL=1.

EN: The main script is Pro-Universal-Windows-Optimizer-v18_0.ps1. The interface supports Polish and English, and the language selection is remembered between runs.

PL: Główny skrypt to Pro-Universal-Windows-Optimizer-v18_0.ps1. Interfejs obsługuje polski i angielski, a wybór języka jest zapamiętywany między uruchomieniami.

## What's new in v18 / Co nowego w v18

EN:

- Smart Analysis scans the computer before recommending a profile and explains recommendations, uncertainty and potential conflicts.
- Recommended Fix builds a plan from scan results.
- Actions are classified as Recommended, Optional, Deferred, NotRecommended or Blocked.
- The default Guarded path uses supported actions with saved initial state, a persistent transaction journal, read-back verification and rollback.
- Selective Apply lets you include or exclude specific actions.
- Recovery Center supports session recovery and rollback of individual actions.
- Advanced Recovery can generate a separate rollback script.
- Before/After reports, Change Receipt and Post-Optimize Verdict show actual results, skipped actions, errors and recovery coverage.
- Repair Center 2.0 and Windows Update Guard provide diagnostics and explicitly requested repair procedures.
- Profile Builder and Explain Mode help create and understand action plans.
- The Engineering Center at [23] now supports controlled execution and recovery. Unlike v17.2, Apply is no longer limited to writing a manifest.
- Power-plan management includes backup-folder import and removal of multiple selected plans.
- Improved profile mapping, laptop power handling, bilingual messages and reporting of partial failures.

PL:

- Smart Analysis skanuje komputer przed rekomendacją profilu i wyjaśnia zalecenia, niepewność oraz możliwe konflikty.
- Recommended Fix buduje plan na podstawie wyników skanowania.
- Działania otrzymują kategorię Recommended, Optional, Deferred, NotRecommended albo Blocked.
- Domyślna ścieżka Guarded wykonuje obsługiwane działania z zapisaniem stanu początkowego, trwałym dziennikiem transakcji, odczytem kontrolnym i rollbackiem.
- Selective Apply pozwala wskazać lub pominąć konkretne działania.
- Recovery Center obsługuje przywracanie sesji i cofanie pojedynczych akcji.
- Advanced Recovery umożliwia wygenerowanie osobnego skryptu rollbacku.
- Raporty Before/After, Change Receipt i Post-Optimize Verdict pokazują rzeczywiste wyniki, pominięcia, błędy i zakres możliwości przywracania.
- Repair Center 2.0 i Windows Update Guard oferują diagnostykę oraz procedury naprawcze uruchamiane na wyraźne polecenie.
- Profile Builder i Explain Mode pomagają tworzyć i rozumieć plany działań.
- Centrum inżynierskie [23] obsługuje teraz kontrolowane wykonanie i odzyskiwanie. W przeciwieństwie do v17.2 Apply nie ogranicza się już do zapisania manifestu.
- Zarządzanie planami zasilania obejmuje import z folderu kopii i usuwanie wielu wybranych planów.
- Poprawiono mapowanie profili, obsługę zasilania laptopów, komunikaty dwujęzyczne i raportowanie częściowych błędów.

## Latest RC1 fixes / Najnowsze poprawki RC1

EN:

- Boot autostart management respects DryRun before removing entries, moving Startup files or changing startup states.
- Fast Startup respects DryRun, saves the original registry state in the persistent Debloat backup and verifies the new value after writing.
- Fast Startup recovery uses [13] → [4], including after restarting the application.
- VBS/HVCI operations treat failed registry writes as errors. The enable success message requires both registry writes and their read-back checks to succeed.
- Additional fixes cover DryRun handling, DNS rollback, protected session storage, power-plan backups, Default profile recovery and failure reporting.
- Redundant historical reports and test logs were removed. The bilingual v18 change history is consolidated in CHANGELOG.md.

PL:

- Zarządzanie autostartem w Boot respektuje DryRun przed usuwaniem wpisów, przenoszeniem plików Startup i zmianą stanów autostartu.
- Fast Startup respektuje DryRun, zapisuje pierwotny stan rejestru w trwałej kopii Debloat i sprawdza nową wartość po zapisie.
- Przywracanie Fast Startup działa przez [13] → [4], również po ponownym uruchomieniu aplikacji.
- Operacje VBS/HVCI traktują nieudane zapisy rejestru jako błędy. Komunikat o udanym włączeniu wymaga poprawnego zapisu i odczytu kontrolnego obu wartości.
- Dodatkowe poprawki obejmują DryRun, rollback DNS, chronione przechowywanie sesji, kopie planów zasilania, przywracanie profilu Default i raportowanie błędów.
- Usunięto zbędne raporty historyczne i logi testów. Dwujęzyczna historia zmian v18 znajduje się w CHANGELOG.md.

## Main modules / Główne moduły

[1] Smart Analysis / Inteligentna analiza
[2] Optimization / Optymalizacja
[3] Restore / Przywracanie
[4] Windows Repair / Naprawa Windows
[5] Power Plans / Plany zasilania
[6] Automation / Automatyzacja
[7] App Packs / Paczki aplikacji
[8] Voice Assistant / Asystent głosowy
[9] Library and Session History / Biblioteka i historia sesji
[10] Privacy & AI / Prywatność i AI
[11] Root Cause Analysis / Analiza przyczyn
[12] Report Analysis / Analiza raportu
[13] Debloat
[14] Spec Sheet / Karta specyfikacji
[15] Boot and Startup / Rozruch i autostart
[16] Hardening
[17] OEM Preset / Preset OEM
[18] New Users / Nowi użytkownicy
[19] Backup / Kopia zapasowa
[20] Shell Cleanup / Czyszczenie powłoki
[21] Settings / Ustawienia
[22] Self-Test
[23] Engineering Center v18 / Centrum inżynierskie v18
[B] Guide / Przewodnik
[L] Language / Język

## Optimization and advanced modes / Optymalizacja i tryby zaawansowane

EN: Optimization provides profiles for gaming, workstations, low-memory systems, laptops, battery life and general responsiveness. The default Guarded path limits execution according to supported actions, policy checks and required consent.

Advanced exposes additional operations that require explicit permission, including selected network-adapter changes, Defender exclusions and Appx removal.

The v18 modes include Ultra Performance, Ultra Debloat and Comprehensive Controlled. Extreme Lab is intended for planning on virtual machines and test systems and has no active Apply path in this release.

PL: Optymalizacja udostępnia profile do gier, stacji roboczych, komputerów z małą ilością pamięci, laptopów, pracy na baterii i poprawy responsywności. Domyślna ścieżka Guarded ogranicza wykonanie zgodnie z obsługiwanymi akcjami, kontrolą zasad i wymaganymi zgodami.

Advanced udostępnia dodatkowe operacje wymagające jawnej zgody, w tym wybrane zmiany adaptera sieciowego, wykluczenia Defendera i usuwanie Appx.

Tryby v18 obejmują Ultra Performance, Ultra Debloat i Comprehensive Controlled. Extreme Lab służy do planowania na maszynach wirtualnych i stanowiskach testowych. W tym wydaniu nie ma aktywnej ścieżki Apply.

## Debloat and recovery / Debloat i przywracanie

EN: Debloat can reduce background activity by managing selected applications, services, scheduled tasks and startup entries. More aggressive options require additional confirmation.

Recovery uses saved state. Closing an application does not restore its unsaved work, and removed Appx packages may require manual reinstallation. Appx Reinstall Center can attempt recovery when the required package source is available. Guarded blocks Appx removal.

PL: Debloat może ograniczać aktywność w tle przez zarządzanie wybranymi aplikacjami, usługami, zadaniami harmonogramu i autostartem. Bardziej agresywne opcje wymagają dodatkowych potwierdzeń.

Przywracanie korzysta z zapisanego stanu. Ponowne uruchomienie aplikacji nie odzyskuje niezapisanej pracy, a usunięte pakiety Appx mogą wymagać ręcznej reinstalacji. Appx Reinstall Center może podjąć próbę odzyskania, jeśli dostępne jest wymagane źródło pakietu. Guarded blokuje usuwanie Appx.

## Interface / Interfejs

EN: Choose Classic UI or BIOS UI in Settings. Classic uses numeric selection. BIOS UI uses a highlighted selection with keyboard navigation. Some confirmations remain text-based or numeric. Interface preferences are stored outside the extracted package.

PL: W Ustawieniach wybierz Classic UI albo BIOS UI. Classic korzysta z wyboru numerami. BIOS UI używa podświetlanej pozycji i nawigacji klawiaturą. Część potwierdzeń pozostaje tekstowa lub numeryczna. Preferencje interfejsu są zapisywane poza rozpakowaną paczką.

## Safety and limitations / Bezpieczeństwo i ograniczenia

EN: WinTunePro can modify system settings with administrator privileges. Review the plan before applying changes and keep an independent backup of important files. Restore points and rollback mechanisms do not replace a full backup.

DryRun previews supported operations without applying their system changes, but may create reports and session files.

SHA-256 manifests check file integrity. They are not a publisher signature.

Fewer processes or services do not guarantee higher FPS. Results depend on hardware, Windows configuration and workload.

PL: WinTunePro może zmieniać ustawienia systemowe z uprawnieniami administratora. Przejrzyj plan przed wykonaniem i zachowaj niezależną kopię ważnych plików. Punkty przywracania i rollback nie zastępują pełnej kopii zapasowej.

DryRun pokazuje obsługiwane operacje bez wykonywania ich zmian systemowych, ale może tworzyć raporty i pliki sesji.

Manifesty SHA-256 sprawdzają spójność plików. Nie są podpisem wydawcy.

Mniejsza liczba procesów lub usług nie gwarantuje wyższego FPS. Efekty zależą od sprzętu, konfiguracji Windows i obciążenia.

## Verification and release status / Weryfikacja i status wydania

EN: RC1 passed automated package checks, syntax checks, PSScriptAnalyzer error checks and isolated regression tests. The latest Boot and VBS verification passed 34 scenarios in PowerShell 5.1 and 34 in PowerShell 7, covering Polish and English messages.

Mutating system operations were mocked in those tests. Full elevated Apply, Rollback, reboot and interruption testing on test Windows installations remains necessary before declaring a stable release.

PL: RC1 przeszedł automatyczne kontrole paczki, składni, błędów PSScriptAnalyzer i izolowane testy regresji. Ostatnia weryfikacja Boot i VBS zakończyła się wynikiem 34 scenariuszy w PowerShell 5.1 i 34 w PowerShell 7, z uwzględnieniem komunikatów polskich i angielskich.

Operacje zmieniające system zastąpiono w tych testach atrapami. Przed ogłoszeniem stabilnego wydania nadal potrzebne są pełne próby administracyjnego Apply, Rollback, restartu i przerwania działania na testowych instalacjach Windows.

## Documentation / Dokumentacja

- README.md: instructions / instrukcja.
- CHANGELOG.md: implemented v18 changes and RC1 fixes / wdrożone zmiany v18 i poprawki RC1.
- PROFILES.md: optimization profiles / profile optymalizacji.
- ULTRA-DEBLOAT.md: Ultra Debloat details / szczegóły Ultra Debloat.
- docs/v18: engine, recovery, limitations and testing documentation / dokumentacja silnika, odzyskiwania, ograniczeń i testowania.
- CREDITS.md: acknowledgements / autorstwo i podziękowania.
- LICENSE: MIT license / licencja MIT.
