# WinTunePro 19.0.0

**EN:** Windows analysis, optimization, diagnostics and recovery toolkit with gaming features, controlled changes and rollback.

**PL:** Narzędzie do analizy, optymalizacji, diagnostyki i przywracania Windows, z funkcjami gamingowymi, kontrolowanym wprowadzaniem zmian i możliwością ich cofania.

**Version / Wersja:** 19.0.0  
**Release status / Status:** Unsigned release; live Windows validation pending / Wydanie niepodpisane; pełne testy na Windows w toku  
**License / Licencja:** MIT  
**Platform / System:** Windows 11 24H2/25H2; Windows 10 LTSC or with ESU / Windows 10 LTSC lub z ESU  
**Runtime / Środowisko:** Windows PowerShell 5.1 / PowerShell 7  
**Languages / Języki:** Polski / English

## Download / Pobierz

**EN:** Download the complete WinTunePro 19.0.0 ZIP, extract it to a writable folder and retain the entire directory structure (`scripts`, `data`, `src`, etc.). This is **one package** with launchers for PowerShell 5.1 and PowerShell 7, not two separate editions. Do not run individual scripts removed from the package.

**PL:** Pobierz pełne archiwum ZIP WinTunePro 19.0.0, rozpakuj je do folderu z prawem zapisu i zachowaj całą strukturę (`scripts`, `data`, `src` itd.). Jest to **jedna paczka** z plikami uruchamiającymi dla PowerShell 5.1 i 7, a nie dwie osobne edycje. Nie uruchamiaj pojedynczych skryptów wyjętych z paczki.

## How to run / Jak uruchomić

| File / Plik | Purpose / Przeznaczenie |
| --- | --- |
| `Run-Optimizer.bat` | Main optimizer, PowerShell 5.1; administrator permission requested / Główny program, wymagane uprawnienia administratora |
| `Run-Optimizer-PS7.bat` | Main optimizer in PowerShell 7 / Główny program w PowerShell 7 |
| `TRYB-GRY.bat` / `TRYB-GRY-PS7.bat` | Game Mode without administrator rights / Tryb gry bez uprawnień administratora |
| `Run-Games-and-Measurements.bat` / `Run-Games-and-Measurements-PS7.bat` | Games and diagnostic measurements / Gry i pomiary diagnostyczne |

**EN:** The welcome animation can be skipped with any key; press **Enter** to continue. The main script is `Pro-Universal-Windows-Optimizer-v19_0.ps1`. PowerShell 7 is optional and must be installed separately when needed. Launchers use a process-only execution-policy override; organizational policy may still prevent execution.

**PL:** Animację powitalną można pominąć dowolnym klawiszem; naciśnij **Enter**, aby kontynuować. Główny skrypt to `Pro-Universal-Windows-Optimizer-v19_0.ps1`. PowerShell 7 jest opcjonalny i w razie potrzeby trzeba zainstalować go osobno. Launchery zmieniają politykę wykonywania wyłącznie w swoim procesie; polityka organizacji może nadal blokować uruchomienie.

## What's new in v19 / Co nowego w v19

### 🇵🇱 Polski

- **Smart Analysis:** krótkie podsumowanie na początku, szczegóły na żądanie, oceny profili 0–100 oraz wyjaśnienia i ostrzeżenia w obu językach.
- **Gaming Mode:** wybór uruchomionej gry, zmiana jej priorytetu, opcjonalna zmiana planu zasilania oraz próba automatycznego cofnięcia zmian po zakończeniu gry lub awarii dzięki dziennikowi sesji.
- **Biblioteka gier:** wykrywanie uruchomionych aplikacji oraz gier ze Steam, Epic i Windows.
- **Game Profiles:** preferencje GPU dla konkretnych plików `.exe` i obsługiwane modyfikacje konfiguracji wybranych gier, z kopią zapasową, SHA-256, kontrolą zapisu i przywracaniem.
- **Nowe pomiary:** DNS z rekomendacją bez automatycznej zmiany ustawień, stabilność połączenia, bufferbloat, gotowość do gry i analiza autostartu.
- **FPS Benchmark:** średni FPS, 1% low i 0,1% low przed i po zmianach za pomocą opcjonalnego PresentMon, którego nie dołączono do paczki.
- **Bezpieczeństwo:** weryfikacja integralności SHA-256 przed ładowaniem modułów, kontrolowane wywołania narzędzi Windows i weryfikacja podpisu Microsoft przed naprawą systemu w miejscu.
- **Silnik i interfejs:** poprawki kontroli stanu dysku, diagnostyki obrazu Windows, obsługi błędów, raportów, menu, animacji startowej i launcherów.
- **Zgodność:** wspólna paczka dla PowerShell 5.1/7 oraz rozbudowana obsługa PL/EN.

### 🇬🇧 English

- **Smart Analysis:** one-sentence overview followed by optional details, 0–100 profile scores and bilingual reasons and warnings.
- **Gaming Mode:** select a running game, adjust its process priority, optionally change the power plan and attempt automatic restoration after exit or a crash using a persistent session journal.
- **Game discovery:** lists running applications and installed games from Steam, Epic and Windows.
- **Game Profiles:** per-`.exe` GPU preferences and supported game configuration edits with backup, SHA-256, read-back verification and restore.
- **New measurements:** read-only DNS recommendations, connection stability, bufferbloat, gaming readiness and startup analysis.
- **FPS Benchmark:** average FPS, 1% low and 0.1% low before/after via optional PresentMon, which is not bundled.
- **Security:** SHA-256 integrity checks before module loading, controlled Windows tool invocation and Microsoft signature verification before in-place repair.
- **Engine and interface:** disk-state and Windows image diagnostics fixes, improved error handling, reports, menus, startup animation and launchers.
- **Compatibility:** a combined PowerShell 5.1/7 package with expanded Polish/English support.

## Existing functionality / Funkcje zachowane z v18

**EN:** Version 19 retains Smart Analysis recommendations, Recommended Fix, Guarded and Advanced execution, Selective Apply, Recovery Center, action-level rollback, Before/After reports, Change Receipt, Repair Center 2.0, Windows Update Guard, Profile Builder, Explain Mode, Debloat, power-plan management and Classic/BIOS interfaces. Extreme Lab remains intended for planning and testing, not normal system-wide Apply.

**PL:** Wersja 19 zachowuje rekomendacje Smart Analysis, Recommended Fix, tryby Guarded i Advanced, Selective Apply, Recovery Center, cofanie pojedynczych akcji, raporty Before/After, Change Receipt, Repair Center 2.0, Windows Update Guard, Profile Builder, Explain Mode, Debloat, zarządzanie planami zasilania oraz interfejsy Classic/BIOS. Extreme Lab nadal służy do planowania i testów, a nie zwykłego wykonywania zmian w systemie.

## Safety and limitations / Bezpieczeństwo i ograniczenia

**EN:** Features that modify Windows settings require appropriate administrator rights and explicit confirmation. Game Mode and ordinary diagnostic measurements can run without elevation; PresentMon FPS capture additionally requires administrator privileges or membership in **Performance Log Users**. DryRun previews supported operations but may create reports and session files. SHA-256 detects file changes but does **not** authenticate the publisher. Backups, restore points and rollback cannot guarantee recovery in every situation and do not replace an independent full backup. Fewer background processes do not guarantee higher FPS.

**PL:** Funkcje zmieniające ustawienia Windows wymagają odpowiednich uprawnień administratora i świadomego potwierdzenia. Tryb gry i zwykłe pomiary diagnostyczne mogą działać bez podwyższenia uprawnień; przechwytywanie FPS przez PresentMon wymaga dodatkowo uprawnień administratora albo członkostwa w grupie **Performance Log Users**. DryRun pokazuje planowane operacje, ale może tworzyć raporty i pliki sesji. SHA-256 wykrywa zmiany plików, lecz **nie** potwierdza tożsamości wydawcy. Kopie, punkty przywracania i rollback nie gwarantują pełnego odzyskania stanu i nie zastępują osobnej kopii danych. Zmniejszenie liczby procesów w tle nie gwarantuje wzrostu FPS.

## Verification and release status / Weryfikacja i status wydania

**EN:** The package includes isolated and automated tests, but a complete live Windows test matrix covering UAC, elevated Apply, restart, interruption, actual games, system changes and rollback has **not** been completed. This package is **not digitally signed**. Do not interpret mocked tests as proof of successful recovery on a real machine. Create a restore point and back up important data before major changes.

**PL:** Paczka zawiera testy automatyczne i izolowane, ale **nie ukończono** pełnych testów na rzeczywistym Windows obejmujących UAC, Apply z uprawnieniami administratora, restart, przerwanie pracy, prawdziwe gry, zmiany systemowe i rollback. Paczka **nie jest podpisana cyfrowo**. Testy z atrapami nie dowodzą skutecznego odzyskiwania na prawdziwym komputerze. Przed większymi zmianami utwórz punkt przywracania i kopię ważnych danych.

## Documentation / Dokumentacja

- `README.md` – instructions and requirements / instrukcje i wymagania.
- `CHANGELOG.md` and `RELEASE-NOTES.md` – version history / historia zmian.
- `PROFILES.md` and `ULTRA-DEBLOAT.md` – optimization profiles / profile optymalizacji.
- `docs/v19/QUICKSTART.md` and `docs/v19/TESTY.md` – quick start and manual testing / szybki start i testy ręczne.
- `docs/KNOWN_LIMITATIONS.md` – known limitations / znane ograniczenia.
- `CREDITS.md` and `LICENSE` – acknowledgments and MIT license / podziękowania i licencja MIT.
