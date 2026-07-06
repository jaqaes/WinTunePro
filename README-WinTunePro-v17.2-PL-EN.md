 WinTunePro v17.2 Ultra   
 WinTunePro v17.2 Ultra 

> **PL:** Największa aktualizacja WinTunePro przygotowana dla DEV / BETA / TESTERÓW.  
> **EN:** The biggest WinTunePro update prepared for DEV / BETA / TESTER users.

---

## 🇵🇱 Polski

# WinTunePro v17.2 Ultra 

**WinTunePro v17.2 Ultra  to największa aktualizacja projektu przygotowana dla **DEV / BETA / TESTERÓW**.  
Wersja 17.2 wprowadza osobne buildy dla PowerShell 5.1 i PowerShell 7, nowy opcjonalny interfejs BIOS UI, rozbudowany rollback, trwalsze cofanie Debloatu, Self-Test, raporty błędów oraz najmocniejszy publiczny profil **Ultra Debloat BETA**.

Projekt został uporządkowany tak, aby zachować klasyczny panel WinTunePro jako główny interfejs, a nowe funkcje v17.2 zintegrować jako część programu, a nie jako osobny techniczny projekt.

---

## Najważniejsze informacje

| Element | Opis |
|---|---|
| Wersja | WinTunePro v17.2 Ultra |
| Status | DEV / BETA / TESTER release |
| Buildy | Osobno PowerShell 5.1 i PowerShell 7 |
| Domyślny interfejs | Klasyczny panel WinTunePro |
| Nowy interfejs | Opcjonalny BIOS UI / panel konsolowy |
| Najmocniejszy profil | Ultra Debloat BETA |
| Diagnostyka | Self-Test + osobne narzędzie ScriptDoctor / Scan Detector |
| Rollback | Rozbudowany, trwalszy i bezpieczniejszy |
| Launcher | `Run-Optimizer.bat` |

---

## Dostępne paczki

| Paczka | Dla kogo | Zalecenie |
|---|---|---|
| `WinTunePro-PS5-v17.2` | Użytkownicy Windows PowerShell 5.1 | Dla zwykłych użytkowników i kompatybilności z wbudowanym PowerShellem |
| `WinTunePro-PS7-v17.2` | Użytkownicy PowerShell 7 | Zalecane dla DEV / BETA / TESTERÓW |
| `WinTunePro-ScriptDoctor` | Testerzy i autorzy projektu | Osobne narzędzie do skanowania błędów |

**Dla użytkowników DEV zalecane jest pozostanie na wersji PS7**, ponieważ będzie ona rozwijana najmocniej.  
Wersja PS5 będzie otrzymywać rzadsze aktualizacje, głównie związane z kompatybilnością, zmianami w buildach Windows oraz poprawkami struktury plików.

---

## Co nowego w v17.2

### Nowy interaktywny interfejs BIOS UI

Dodano nowy opcjonalny interfejs wyboru w stylu BIOS / panelu konsolowego.

| Funkcja | Status |
|---|---|
| Poruszanie się po menu strzałkami | Dodano |
| Podświetlany pasek aktywnej pozycji | Dodano |
| Obsługa Enter | Dodano |
| Obsługa Esc | Dodano |
| Obsługa Spacji | Dodano |
| Obsługa strzałek ← → ↑ ↓ | Dodano |
| Krótka instrukcja sterowania w menu | Dodano |
| Pasek pomocy ze skrótami klawiszowymi | Dodano |
| Mniejsze migotanie ekranu | Poprawiono |
| Ukrywanie cyfr i liter w BIOS UI | Dodano |
| Klasyczne wybieranie cyferkami | Zachowano |

Użytkownik może wybrać tryb interfejsu:

| Tryb | Opis |
|---|---|
| Classic UI | Klasyczne wybieranie opcji cyferkami |
| BIOS UI / Interactive Panel | Poruszanie się paskiem, strzałkami i klawiszami |

Nowy interfejs jest opcjonalny.  
Klasyczny panel pozostaje dostępny i nadal jest głównym trybem działania programu.

---

## Menu i struktura programu

W v17.2 zachowano zgodność ze starym panelem WinTunePro.

Najważniejsze zmiany:

- zachowano 20 głównych modułów na pierwszym poziomie,
- usunięto sztuczne podmoduły,
- uproszczono logikę menu,
- poprawiono numerację opcji,
- dodano ustawienia interfejsu w module Settings / Interfejs,
- dodano rozwijane menu języka:
  - Polski,
  - English,
- w trybie Classic UI podmenu i profile można wybierać cyferkami,
- w trybie BIOS UI cyfry i litery są ukrywane, aby panel wyglądał czyściej.

Dodano również moduł:

```text
[23] Narzędzia inżynierskie v17.2
```

Funkcje inżynierskie v17.2 są teraz normalną częścią starego menu, a nie osobnym programem obok głównego panelu.

---

## Ultra Debloat BETA

Dodano **Ultra Debloat BETA** jako najmocniejszy publiczny profil Debloatu.

Ultra Debloat:

- bazuje na Maximum Debloat,
- mocniej ogranicza procesy w tle,
- mocniej ogranicza autostart,
- mocniej ogranicza zadania harmonogramu,
- mocniej ogranicza aplikacje konsumenckie,
- wymaga kilku potwierdzeń,
- jest przeznaczony dla zaawansowanych użytkowników i testerów.

### Czego Ultra Debloat celowo nie usuwa

Ultra Debloat nie usuwa i nie wyłącza krytycznych składników Windows:

| Składnik | Status |
|---|---|
| Microsoft Defender | Zachowany |
| Windows Update core | Zachowany |
| Microsoft Store core | Zachowany |
| Explorer / Start | Zachowany |
| Audio | Zachowane |
| Sieć | Zachowana |
| GPU | Zachowane |
| Mechanizmy odzyskiwania | Zachowane |

Celem Ultra Debloat jest zmniejszenie liczby procesów w tle oraz ograniczenie użycia RAM / CPU, ale bez robienia z systemu niestabilnego custom Windowsa.

---

## Debloat Restore i rollback

Wprowadzono trwalsze cofanie zmian Debloatu.

Zmiany Debloatu są zapisywane do:

```text
%LOCALAPPDATA%\WinTunePro\debloat-restore.json
```

Dzięki temu:

- cofanie działa także po zamknięciu programu,
- cofanie działa po ponownym uruchomieniu,
- opcja Debloat `[4] Przywróć wszystko` nie jest już zależna wyłącznie od bieżącej sesji.

Poprawiono również rollback rejestru:

- cofanie odbywa się od najnowszych wpisów do najstarszych,
- zmniejsza to ryzyko ponownego nakładania wcześniejszych tweaków podczas przywracania,
- agresywne zmiany mają mieć możliwość cofnięcia.

---

## DryRun i bezpieczeństwo zmian

Poprawiono tryb DryRun.

Tryb symulacji:

- nie powinien już tworzyć pustych kluczy rejestru,
- ma działać jako prawdziwy podgląd zmian,
- nie powinien modyfikować systemu,
- pozwala lepiej ocenić, co zrobi dany moduł przed faktycznym wykonaniem.

Moduł Privacy został przepięty przez bezpieczniejszą warstwę zapisu rejestru:

- spójny manifest,
- backup,
- zgodność z rollbackiem,
- mniejsze ryzyko błędów pod StrictMode.

---

## Self-Test i diagnostyka testera

Dodano Self-Test / Diagnostykę testera.

Self-Test obejmuje:

| Test | Opis |
|---|---|
| Parser PowerShell | Wykrywa błędy składni |
| Ładowanie modułów | Sprawdza problemy z importem / dot-source |
| Plik / linia / kolumna | Raportuje dokładne miejsce błędu |
| Raport TXT | Tworzy raport dla testera |
| Raport błędów na pulpit | Tester nie musi przepisywać błędów z konsoli |

Dodano automatyczne raporty błędów, aby łatwiej zgłaszać problemy podczas testów.

---

## WinTunePro ScriptDoctor / Scan Detector

Oprócz programu dodano osobne narzędzie diagnostyczne:

```text
WinTunePro-ScriptDoctor
```

ScriptDoctor / Scan Detector jest przeznaczony dla testerów i autora projektu.

Narzędzie służy do:

- skanowania błędów parsera PowerShell,
- wykrywania błędów typu plik / linia / kolumna,
- sprawdzania ładowania modułów,
- wykrywania problemów ze zmiennymi,
- sprawdzania zgodności PS5 / PS7,
- generowania raportów TXT / CSV,
- szybkiego wykrywania błędów, które mogłyby wywalić skrypt.

ScriptDoctor jest publikowany jako osobna paczka, aby nie kolidował z głównym programem.

Zalecany zestaw publikacyjny:

```text
WinTunePro-PS5-v17.2.zip
WinTunePro-PS7-v17.2.zip
WinTunePro-ScriptDoctor-v1.1.zip
```

---

## Ważne poprawki techniczne

| Obszar | Zmiana |
|---|---|
| Parser PowerShell | Naprawiono błędy składni i ładowania modułów |
| Folder `runs` | Naprawiono tworzenie katalogu, aby moduł inżynierski się nie wywalał |
| Repair | Usunięto hardkodowane `C:\Windows` |
| Repair | Ścieżki używają teraz `$env:SystemRoot` |
| Sysprep | Poprawiono ścieżki związane z Sysprep |
| ConsentStore | Usunięto błędną pętlę ConsentStore / Deny |
| ScheduledDefrag | Usunięto ryzykowne wyłączanie z agresywnego Debloatu |
| Launcher BAT | Poprawiono przekazywanie argumentów przy podnoszeniu uprawnień |
| Write-CatchWarn | Dodano lepsze logowanie krytycznych błędów |
| HealthScore | Rozdzielono ocenę realnej kondycji systemu |
| AdoptionScore | Rozdzielono zgodność systemu z tweakami WinTunePro |
| HKCU warning | Dodano ostrzeżenie, gdy program działa na innym koncie administratora niż użytkownik pulpitu |
| Nazewnictwo | Uporządkowano główny plik do wersji `v17_0` |

---

## Zmiany w optymalizacji

Poprawiono logikę menu i numerację w module optymalizacji.

Usunięto martwy kod związany z wykrywaniem ryzyka profilu.

Usunięto pseudo-walidację z wybranych tweaków, która mierzyła szum zamiast realnego efektu:

- `GameDVR_Enabled`,
- `Win32PrioritySeparation`.

Poprawiono stabilność działania modułów Debloat, Repair i Rollback.

---

## Rekomendowany sposób uruchomienia

Głównym launcherem pozostaje:

```text
Run-Optimizer.bat
```

Dla zwykłego użytkownika:

1. Pobierz odpowiednią paczkę PS5 albo PS7.
2. Rozpakuj ZIP.
3. Uruchom `Run-Optimizer.bat`.
4. Wybierz tryb interfejsu:
   - Classic UI,
   - BIOS UI.
5. Przed agresywnymi zmianami wykonaj punkt przywracania systemu.

---

## PS5 czy PS7?

| Wersja | Opis |
|---|---|
| PS5 | Wersja dla Windows PowerShell 5.1, wbudowanego w system |
| PS7 | Wersja dla PowerShell 7, zalecana dla DEV / BETA / TESTERÓW |

Rekomendacja:

- zwykły użytkownik: PS5 lub PS7,
- tester: PS7,
- DEV: PS7,
- starsze środowiska: PS5.

---

## Bezpieczeństwo

WinTunePro wykonuje zmiany systemowe, dlatego przed użyciem agresywnych funkcji zaleca się:

- utworzyć punkt przywracania systemu,
- przeczytać opis wybranego profilu,
- użyć DryRun, jeśli jest dostępny,
- nie uruchamiać Ultra Debloat bez zrozumienia skutków,
- zachować raporty testowe w przypadku zgłaszania błędów.

Ultra Debloat BETA jest przeznaczony dla osób, które wiedzą, że wybierają najmocniejszy profil publiczny.

---

## Status projektu

WinTunePro v17.2 jest dużo bliżej wersji publicznej niż wcześniejsze buildy.

| Element | Status |
|---|---|
| Osobne buildy PS5 / PS7 | Gotowe |
| Rollback Debloatu | Rozbudowany |
| Self-Test | Dodany |
| Raporty błędów | Dodane |
| ScriptDoctor / Scan Detector | Dostępny jako osobne narzędzie |
| Stary panel jako domyślny | Zachowany |
| BIOS UI | Dodany opcjonalnie |
| Moduł inżynierski v17.2 | Zintegrowany z menu |
| Ultra Debloat BETA | Dodany |
| Dokumentacja | Zaktualizowana |

---

## Podsumowanie

WinTunePro v17.2 Ultra  to największa aktualizacja projektu.

Wprowadza:

- osobne paczki PS5 i PS7,
- nowy opcjonalny interfejs BIOS UI,
- klasyczny panel jako domyślny tryb,
- Ultra Debloat BETA,
- trwalszy rollback,
- Self-Test,
- automatyczne raporty błędów,
- ScriptDoctor / Scan Detector jako osobne narzędzie diagnostyczne,
- stabilniejszy Debloat,
- poprawiony Repair,
- lepszą strukturę projektu,
- pełniejszą integrację modułów.

Ta wersja jest przeznaczona przede wszystkim dla testerów, użytkowników zaawansowanych i osób, które chcą pomóc w dopracowaniu WinTunePro przed szerszą publikacją.

---

---

## 🇬🇧 English

# WinTunePro v17.2 Ultra 

**WinTunePro v17.2 Ultra ** is the biggest update of the project, prepared for **DEV / BETA / TESTER** users.  
Version 17.2 introduces separate builds for PowerShell 5.1 and PowerShell 7, a new optional BIOS-style UI, improved rollback, persistent Debloat restore, Self-Test, error reports, and the strongest public profile: **Ultra Debloat BETA**.

The project has been reorganized so that the classic WinTunePro panel remains the main interface, while the new v17.2 features are integrated into the program instead of being a separate technical side-project.

---

## Key information

| Item | Description |
|---|---|
| Version | WinTunePro v17.2 Ultra Debloat BETA |
| Status | DEV / BETA / TESTER release |
| Builds | Separate PowerShell 5.1 and PowerShell 7 builds |
| Default interface | Classic WinTunePro panel |
| New interface | Optional BIOS UI / console panel |
| Strongest profile | Ultra Debloat BETA |
| Diagnostics | Self-Test + separate ScriptDoctor / Scan Detector tool |
| Rollback | Extended, more persistent and safer |
| Launcher | `Run-Optimizer.bat` |

---

## Available packages

| Package | Target user | Recommendation |
|---|---|---|
| `WinTunePro-PS5-v17.2` | Windows PowerShell 5.1 users | For regular users and built-in Windows PowerShell compatibility |
| `WinTunePro-PS7-v17.2` | PowerShell 7 users | Recommended for DEV / BETA / TESTER users |
| `WinTunePro-ScriptDoctor` | Testers and project authors | Separate error scanning tool |

**DEV users are recommended to stay on the PS7 version**, because it will receive the most active development.  
The PS5 version will receive less frequent updates, mostly focused on compatibility, Windows build changes, and file structure fixes.

---

## What is new in v17.2

### New interactive BIOS UI

A new optional BIOS-style / console-panel interface has been added.

| Feature | Status |
|---|---|
| Arrow-key menu navigation | Added |
| Highlighted active menu bar | Added |
| Enter support | Added |
| Esc support | Added |
| Space support | Added |
| ← → ↑ ↓ arrow support | Added |
| Short control instructions in menu | Added |
| Keyboard shortcut help bar | Added |
| Reduced screen flickering | Improved |
| Hidden numbers and letters in BIOS UI | Added |
| Classic number-based selection | Preserved |

The user can choose the interface mode:

| Mode | Description |
|---|---|
| Classic UI | Classic number-based menu selection |
| BIOS UI / Interactive Panel | Navigation using highlight bar, arrows, and keyboard keys |

The new interface is optional.  
The classic panel remains available and is still the main operating mode of the program.

---

## Menu and program structure

Version 17.2 preserves compatibility with the old WinTunePro panel.

Main changes:

- 20 main modules remain on the first menu level,
- artificial submodules were removed,
- menu logic was simplified,
- option numbering was improved,
- interface settings were added to Settings / Interface,
- a language dropdown was added:
  - Polish,
  - English,
- in Classic UI, submenus and profiles can still be selected by numbers,
- in BIOS UI, numbers and letters are hidden to make the panel cleaner.

A new module was also added:

```text
[23] Engineering Tools v17.2
```

The v17.2 engineering features are now a normal part of the old menu, not a separate program next to the main panel.

---

## Ultra Debloat BETA

**Ultra Debloat BETA** has been added as the strongest public Debloat profile.

Ultra Debloat:

- is based on Maximum Debloat,
- reduces background processes more aggressively,
- limits startup items more strongly,
- limits scheduled tasks more strongly,
- limits consumer apps more strongly,
- requires multiple confirmations,
- is intended for advanced users and testers.

### What Ultra Debloat intentionally does not remove

Ultra Debloat does not remove or disable critical Windows components:

| Component | Status |
|---|---|
| Microsoft Defender | Preserved |
| Windows Update core | Preserved |
| Microsoft Store core | Preserved |
| Explorer / Start | Preserved |
| Audio | Preserved |
| Network | Preserved |
| GPU | Preserved |
| Recovery mechanisms | Preserved |

The goal of Ultra Debloat is to reduce background processes and RAM / CPU usage, without turning the system into an unstable custom Windows build.

---

## Debloat Restore and rollback

Persistent Debloat restore has been introduced.

Debloat changes are saved to:

```text
%LOCALAPPDATA%\WinTunePro\debloat-restore.json
```

This means:

- restore works after closing the program,
- restore works after restarting the program,
- Debloat option `[4] Restore everything` is no longer dependent only on the current session.

Registry rollback was also improved:

- rollback is performed from newest entries to oldest,
- this reduces the risk of reapplying earlier tweaks during restore,
- aggressive changes are expected to remain reversible.

---

## DryRun and change safety

DryRun mode has been improved.

Simulation mode:

- should no longer create empty registry keys,
- should behave as a true preview of changes,
- should not modify the system,
- helps users understand what a module will do before actually running it.

The Privacy module has been routed through a safer registry write layer:

- consistent manifest,
- backup,
- rollback compatibility,
- lower risk of StrictMode errors.

---

## Self-Test and tester diagnostics

Self-Test / Tester Diagnostics has been added.

Self-Test includes:

| Test | Description |
|---|---|
| PowerShell parser | Detects syntax errors |
| Module loading | Checks import / dot-source issues |
| File / line / column | Reports the exact error location |
| TXT report | Creates a report for the tester |
| Desktop error report | The tester does not need to copy errors from the console manually |

Automatic error reports were added to make bug reporting easier during testing.

---

## WinTunePro ScriptDoctor / Scan Detector

A separate diagnostic tool is available:

```text
WinTunePro-ScriptDoctor
```

ScriptDoctor / Scan Detector is intended for testers and project authors.

The tool is used for:

- scanning PowerShell parser errors,
- detecting file / line / column errors,
- checking module loading,
- detecting variable issues,
- checking PS5 / PS7 compatibility,
- generating TXT / CSV reports,
- quickly detecting errors that could crash the script.

ScriptDoctor is published as a separate package to avoid conflicts with the main program.

Recommended release package set:

```text
WinTunePro-PS5-v17.2.zip
WinTunePro-PS7-v17.2.zip
WinTunePro-ScriptDoctor-v1.1.zip
```

---

## Important technical fixes

| Area | Change |
|---|---|
| PowerShell parser | Fixed syntax and module loading errors |
| `runs` folder | Fixed directory creation so the engineering module does not crash |
| Repair | Removed hardcoded `C:\Windows` |
| Repair | Paths now use `$env:SystemRoot` |
| Sysprep | Fixed Sysprep-related paths |
| ConsentStore | Removed incorrect ConsentStore / Deny loop |
| ScheduledDefrag | Removed risky disabling from aggressive Debloat |
| BAT launcher | Improved argument passing when elevating privileges |
| Write-CatchWarn | Added better logging for critical errors |
| HealthScore | Separated real system health evaluation |
| AdoptionScore | Separated WinTunePro tweak adoption evaluation |
| HKCU warning | Added warning when the program runs under a different admin account than the desktop user |
| Naming | Main file naming was organized around `v17_0` |

---

## Optimization changes

Optimization menu logic and option numbering were improved.

Dead code related to profile risk detection was removed.

Pseudo-validation was removed from selected tweaks that measured noise instead of real effect:

- `GameDVR_Enabled`,
- `Win32PrioritySeparation`.

Debloat, Repair, and Rollback stability was improved.

---

## Recommended launch method

The main launcher remains:

```text
Run-Optimizer.bat
```

For a regular user:

1. Download the correct PS5 or PS7 package.
2. Extract the ZIP.
3. Run `Run-Optimizer.bat`.
4. Choose the interface mode:
   - Classic UI,
   - BIOS UI.
5. Create a system restore point before aggressive changes.

---

## PS5 or PS7?

| Version | Description |
|---|---|
| PS5 | Version for Windows PowerShell 5.1 built into Windows |
| PS7 | Version for PowerShell 7, recommended for DEV / BETA / TESTER users |

Recommendation:

- regular user: PS5 or PS7,
- tester: PS7,
- DEV: PS7,
- older environments: PS5.

---

## Safety

WinTunePro performs system-level changes, so before using aggressive functions it is recommended to:

- create a system restore point,
- read the description of the selected profile,
- use DryRun if available,
- avoid running Ultra Debloat without understanding the consequences,
- keep test reports when reporting bugs.

Ultra Debloat BETA is intended for users who understand that they are choosing the strongest public profile.

---

## Project status

WinTunePro v17.2 is much closer to a public-ready release than previous builds.

| Item | Status |
|---|---|
| Separate PS5 / PS7 builds | Ready |
| Debloat rollback | Extended |
| Self-Test | Added |
| Error reports | Added |
| ScriptDoctor / Scan Detector | Available as a separate tool |
| Classic panel as default | Preserved |
| BIOS UI | Added as optional |
| Engineering Tools v17.2 | Integrated into the menu |
| Ultra Debloat BETA | Added |
| Documentation | Updated |

---

## Summary

WinTunePro v17.2 Ultra Debloat BETA is the biggest update of the project.

It introduces:

- separate PS5 and PS7 packages,
- new optional BIOS UI,
- classic panel as the default mode,
- Ultra Debloat BETA,
- persistent rollback,
- Self-Test,
- automatic error reports,
- ScriptDoctor / Scan Detector as a separate diagnostic tool,
- more stable Debloat,
- improved Repair,
- better project structure,
- fuller module integration.

This version is intended mainly for testers, advanced users, and people who want to help polish WinTunePro before a wider public release.
