# Pro Universal Windows Optimizer

A deep, **reversible** Windows tuner focused on gaming performance, low latency, diagnostics and one‑click rollback.
Głęboki, **odwracalny** optymalizator Windows nastawiony na wydajność w grach, niskie opóźnienia, diagnostykę i rollback jednym kliknięciem.

---

## ⚠️ Disclaimer / Zastrzeżenie

**EN:** This tool runs as Administrator and makes system‑level changes (registry, services, power plans, network). All changes are designed to be reversible (restore point + per‑session backups), but you use it at your own risk. Review the script before running it.

**PL:** Narzędzie działa jako administrator i wprowadza zmiany systemowe (rejestr, usługi, plany zasilania, sieć). Zmiany są zaprojektowane jako odwracalne (punkt przywracania + kopie per‑sesja), ale używasz na własną odpowiedzialność. Przejrzyj skrypt przed uruchomieniem.

---

## Requirements / Wymagania

- Windows 10 22H2+ or Windows 11 (23H2 / 24H2)
- **PowerShell 7** (`pwsh`) — the launcher installs it for you if missing
- Administrator rights / uprawnienia administratora

---

## How to run / Jak uruchomić

**EN — recommended:** put `Run-Optimizer.bat` in the same folder as `Pro-Universal-Windows-Optimizer-*.ps1`, then double‑click `Run-Optimizer.bat`. It elevates to admin, checks PowerShell 7 and launches the script.

**PL — zalecane:** umieść `Run-Optimizer.bat` w tym samym folderze co `Pro-Universal-Windows-Optimizer-*.ps1`, a następnie kliknij dwukrotnie `Run-Optimizer.bat`. Sam podniesie uprawnienia, sprawdzi PowerShell 7 i uruchomi skrypt.

**Manual / Ręcznie:**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ".\Pro-Universal-Windows-Optimizer-v16_9_2.ps1"
```

Language is detected automatically from the system UI culture (Polish system → Polish, otherwise English).
Język wykrywany jest automatycznie z języka interfejsu systemu (system polski → polski, w innym wypadku angielski).

---

## Safety model / Model bezpieczeństwa

**EN:** Every mode that changes the system follows the same rules: an automatic restore point before the first change, session backups of anything modified (registry values, service startup types, scheduled-task state, Run-key entries, Startup-folder shortcuts), and a matching **Restore/Rollback** path to undo it. Services are set to **Manual, never Disabled**. The shell (Explorer/Start/taskbar), the active game process, anticheat, GPU drivers, Store/Edge/Terminal, Defender, VBS/HVCI and core audio/network/security services are never touched by any automated mode.

**EN (preview before consent):** Aggressive and Maximum print a read-only preview of exactly what will be touched on your machine (running services, open apps, enabled tasks, installed Appx, registry values, matched autostart entries) *before* asking you to type YES.

**PL (podglad przed zgoda):** Agresywny i Maksymalny wypisuja podglad (tylko odczyt) dokladnie tego, co zostanie ruszone na Twojej maszynie (dzialajace uslugi, otwarte aplikacje, wlaczone zadania, zainstalowane Appx, wartosci rejestru, dopasowane wpisy autostartu) *zanim* poprosza o wpisanie YES.

**EN (authorship):** The build signature (`jaqoaes`) is bound into the program logic and verified at runtime; the project is MIT-licensed - see `LICENSE`.

**PL (autorstwo):** Sygnatura builda (`jaqoaes`) jest wpleciona w logike programu i weryfikowana w trakcie dzialania; projekt na licencji MIT - patrz `LICENSE`.

**EN (startup hygiene):** On launch the tool self-repairs its own footprint from older versions: logon tasks, Run entries or Startup shortcuts that point at a missing script file or at Windows PowerShell 5.1 are removed or re-registered via `pwsh` — this permanently fixes the *"#requires PowerShell 7.0"* red error some users saw at every boot.

**PL (higiena startu):** Przy uruchomieniu narzędzie samo naprawia własne ślady po starszych wersjach: zadania logowania, wpisy Run i skróty Startup wskazujące na brakujący plik skryptu albo na Windows PowerShell 5.1 są usuwane lub przerejestrowywane przez `pwsh` — to trwale usuwa czerwony błąd *"#requires PowerShell 7.0"*, który u części użytkowników pojawiał się przy każdym starcie.

**PL:** Każdy tryb zmieniający system trzyma się tych samych zasad: automatyczny punkt przywracania przed pierwszą zmianą, kopie per-sesja wszystkiego co modyfikowane (wartości rejestru, typy startu usług, stan zadań, wpisy Run, skróty Startup) oraz odpowiadająca ścieżka **Przywracania/Rollbacku**. Usługi ustawiane są na **Manual, nigdy Disabled**. Powłoka (Explorer/Start/pasek), aktywny proces gry, anticheat, sterowniki GPU, Store/Edge/Terminal, Defender, VBS/HVCI oraz krytyczne usługi audio/sieci/bezpieczeństwa nie są ruszane przez żaden zautomatyzowany tryb.

---

## Modes / Tryby — quick reference / szybki przegląd

| # | Mode (EN) | Tryb (PL) | What it does / Co robi |
|---|-----------|-----------|------------------------|
| 1 | Analysis | Analiza | Diagnostics only, no changes / Diagnostyka, zero zmian |
| 2 | Optimization | Optymalizacja | 15-profile tweak engine with effect preview / Silnik 15 profili z podglądem efektu |
| 3 | Restore | Przywracanie | Undo the last optimization / Cofnij ostatnią optymalizację |
| 4 | Repair Windows | Naprawa Windows | Audit and repair the system (SFC/DISM + registry/task defaults) / Audyt i naprawa (SFC/DISM + domyślne wartości rejestru/zadań) |
| 5 | Power plans | Plany zasilania | Goal‑based plans + backup/reset / Plany pod cel + backup/reset |
| 6 | Automation | Automatyzacja | Background rules (game→gaming, battery→eco) / Reguły w tle (gra→gaming, bateria→eco) |
| 7 | App packs | Paczki aplikacji | Install a winget app set / Instalacja zestawu winget |
| 8 | Voice assistant | Asystent głosowy | Experimental, offline / Eksperymentalny, offline |
| 9 | Library (recipes) | Biblioteka (przepisy) | Saved tweak recipes + full session history with rollback / Zapisane przepisy tweaków + pełna historia sesji z rollbackiem |
| 10 | Privacy & AI | Prywatność i AI | Disable Copilot, Recall, telemetry (reversible) / Wyłącz Copilot, Recall, telemetrię (odwracalne) |
| 11 | Root‑cause | Analiza przyczyn | Why the PC is slow, per service/driver/disk / Dlaczego komputer jest wolny, per usługa/sterownik/dysk |
| 12 | Report analysis | Analiza raportu | Session verdict: success / partial / fail, with % / Ocena sesji: udana / częściowa / nieudana, z % |
| 13 | Debloat | Debloat | 4 tiers: Standard/Aggressive/Maximum/Restore — see below / 4 poziomy: Standardowy/Agresywny/Maksymalny/Przywróć — patrz niżej |
| 14 | Spec Sheet | Karta specyfikacji | One press → dated hardware-spec file for IT, no questions asked / Jedno wciśnięcie → datowany plik specyfikacji dla informatyka, bez pytań |
| 15 | Boot | Boot | Boot-time history + numbered autostart with disable + Fast Startup / Historia czasu startu + numerowany autostart z wyłączaniem + Fast Startup |
| B | Guide | Przewodnik | Plain-language description of every mode/profile — changes nothing / Opis każdego trybu i profilu po ludzku — nic nie zmienia |
| L | Language | Język | Switch console language PL/EN at runtime / Przełącz język konsoli PL/EN w trakcie działania |

> Naming note: the old collision is resolved — **[9] Library** is the recipes/session-history system, while the plain-language glossary is now called **[B] Guide**.
> Uwaga o nazwach: stara kolizja rozwiązana — **[9] Biblioteka** to system przepisów/historii sesji, a słownik opisów po ludzku nazywa się teraz **[B] Przewodnik**.

---

## How each mode works, in detail / Jak działa każdy tryb, szczegółowo

### [1] Analyze / Analiza
**EN:** Read-only scan of running processes, services, startup impact, disk health, drivers and Windows Update state. Produces a report of what's likely slowing the system down. Zero changes — safe to run anytime, including as a before/after baseline.
**PL:** Skan tylko do odczytu: procesy, usługi, wpływ autostartu, stan dysku, sterowniki, stan Windows Update. Daje raport co prawdopodobnie spowalnia system. Zero zmian — bezpieczny o każdej porze, także jako punkt odniesienia przed/po.

### [2] Optimize / Optymalizacja
**EN:** The actual tweak engine. Choose one of 15 profiles — Safe, Balanced, Maximum, Gaming, Workstation, LowEnd, Laptop, LaptopGamingSafe, GamingLaptop, OfficeLaptop, LowRAM, BatterySaver, Performance Feel Mode, Auto/Safe Recommended, AutoSmart — or build a custom one. Each profile is a curated set of registry/service/power tweaks with an honest effect estimate shown before you commit, and always creates a restore point first. Full profile descriptions live in the Library ([B]) and in `PROFILES.md`.
**PL:** Właściwy silnik tweaków. Wybierz jeden z 15 profili — Safe, Balanced, Maximum, Gaming, Workstation, LowEnd, Laptop, LaptopGamingSafe, GamingLaptop, OfficeLaptop, LowRAM, BatterySaver, Performance Feel Mode, Auto/Safe Recommended, AutoSmart — albo złóż własny. Każdy profil to wyselekcjonowany zestaw tweaków rejestru/usług/zasilania z uczciwym szacunkiem efektu przed zatwierdzeniem, zawsze najpierw tworzy punkt przywracania. Pełne opisy profili są w Bibliotece ([B]) i w `PROFILES.md`.

### [3] Rollback / Przywracanie
**EN:** Reverts the changes made by the last Optimize session in a single choice, using the session backup Optimize created automatically.
**PL:** Cofa zmiany z ostatniej sesji Optymalizacji jednym wyborem, korzystając z kopii sesji utworzonej automatycznie przez Optymalizację.

### [4] Windows Repair / Naprawa Windows
**EN:** Basic tier runs SFC and DISM health checks/repairs. Advanced tier additionally restores Windows-default registry values and re-enables scheduled tasks that may have been disabled — by this tool, another debloat script, or manual edits — acting as a safety net independent from Debloat's own [4] Restore.
**PL:** Tryb podstawowy uruchamia SFC i DISM (sprawdzenie/naprawa kondycji). Tryb zaawansowany dodatkowo przywraca domyślne wartości rejestru Windows i włącza z powrotem zadania, które mogły zostać wyłączone — przez to narzędzie, inny skrypt debloatujący, albo ręczne zmiany — działając jako siatka bezpieczeństwa niezależna od własnego [4] Przywróć w Debloacie.

### [5] Power Plans / Plany zasilania
**EN:** Goal-based power plans built from real Windows power schemes (not fake placeholders), with backup, restore and reset.
**PL:** Plany zasilania pod konkretny cel, zbudowane na realnych schematach Windows (nie atrapach), z backupem, przywracaniem i resetem.

### [6] Automation / Automatyzacja
**EN:** Background rules that react to context: launching a game switches to the Gaming power plan, dropping onto battery switches to Eco, and a watchdog keeps a log of what triggered.
**PL:** Reguły w tle reagujące na kontekst: odpalenie gry przełącza na plan Gaming, przejście na baterię przełącza na Eco, a watchdog prowadzi log tego, co się wyzwoliło.

### [7] App Packs / Paczki aplikacji
**EN:** Installs a curated set of applications via `winget` in one go, or exports your own current app set as a reusable pack — useful for setting up a new PC or replicating a config across machines.
**PL:** Instaluje wyselekcjonowany zestaw aplikacji przez `winget` za jednym razem, albo eksportuje Twój aktualny zestaw jako paczkę do ponownego użycia — przydatne przy stawianiu nowego PC albo powielaniu configu na kilku maszynach.

### [8] Voice Assistant / Asystent głosowy
**EN:** Experimental, fully offline. Recognizes a small, fixed set of voice commands to trigger common actions. Not a general-purpose assistant.
**PL:** Eksperymentalny, w pełni offline. Rozpoznaje mały, stały zestaw komend głosowych do typowych akcji. To nie ogólny asystent.

### [9] Library (recipes) / Biblioteka (przepisy)
**EN:** Save a specific combination of tweaks as a named "recipe" to re-run later, and browse the full history of past sessions with the ability to roll back any of them by number. (Not to be confused with [B] — see the naming note above.)
**PL:** Zapisz konkretną kombinację tweaków jako nazwany "przepis" do ponownego uruchomienia, i przeglądaj pełną historię sesji z możliwością cofnięcia którejkolwiek po numerze. (Nie mylić z [B] — patrz uwaga o nazewnictwie wyżej.)

### [10] Privacy & AI / Prywatność i AI
**EN:** Disables Copilot, Recall, telemetry collection, the advertising ID and various suggestion surfaces — all reversible.
**PL:** Wyłącza Copilot, Recall, zbieranie telemetrii, ID reklamowe i różne powierzchnie sugestii — wszystko odwracalne.

### [11] Root Cause / Analiza przyczyn
**EN:** Goes beyond "the PC is slow" and explains *why* — pinpointing the specific service, driver or disk behavior responsible, using a rule-based engine plus a driver analyzer.
**PL:** Idzie dalej niż "komputer jest wolny" i tłumaczy *dlaczego* — wskazuje konkretną usługę, sterownik lub zachowanie dysku odpowiedzialne, przy pomocy silnika regułowego i analizatora sterowników.

### [12] Report Analysis / Analiza raportu
**EN:** Reads saved session reports and gives an honest verdict — SUCCESS / PARTIAL / FAILED with a percentage — based on validation checks and a before/after benchmark, not just "it ran without errors."
**PL:** Czyta zapisane raporty sesji i daje uczciwy werdykt — UDANA / CZĘŚCIOWA / NIEUDANA z procentem — na bazie walidacji i benchmarku przed/po, nie tylko "wykonało się bez błędów."

### [13] Debloat
**EN:** NOT optimization — this trims background load, in four tiers:
- **Standard** *(temporary)* — closes common background apps (browsers, chat, cloud sync, Xbox/Widgets helpers) and stops ~14 curated safe services for the session.
- **Aggressive** *(permanent or temporary, requires typing YES)* — adds game launchers and vendor helper apps, plus ~10 more services.
- **Maximum** *(persistent, requires typing YES twice, "only if you know what you are doing")* — everything Aggressive does, **plus**: disables telemetry/maintenance scheduled tasks (compatibility telemetry, CEIP, disk diagnostics, error reporting, Office telemetry if Office is installed, Family Safety tasks if unused), removes a curated safe bloatware Appx list (reinstallable from the Microsoft Store), disables the autostart of matched vendor apps (Run keys **plus the Windows StartupApproved OFF switch** — the one Settings → Apps → Startup shows — Startup-folder shortcuts of any file type, vendor scheduled tasks, and **Store-app startup tasks** like Spotify/Teams — so closed apps do not relaunch on reboot), and applies reversible registry tweaks (Game DVR off, background apps off, Delivery Optimization off, Windows consumer features off, tailored diagnostic-data experiences off, Start recommendations off).
- **Restore** — undoes everything: restarts stopped services, restores original startup types, re-enables disabled tasks, restores registry values and Run-key entries, moves Startup shortcuts back. Removed Appx apps are listed for manual reinstall from the Store (the one step that isn't automatic).
- **[5] Vendor services** *(opt-in)* — grouped hardware-helper services (NVIDIA extras, MSI, Nahimic, Realtek, Intel graphics/mgmt, Logitech, Thrustmaster, PACE), each with a plain warning about what stops working (RGB, overlay, audio FX, HDCP video, iLok licenses). Selected groups go Manual+stop; [4] restores them. The GPU display container is never listed.
- **[6] Appx removal with selection** — the curated catalog with numbers plus Safe/Gaming/Minimal presets; shows only installed apps; removes the package and its provisioned copy; Store-reinstallable.
- **[7] Re-apply + JSON export/import** — big Windows updates revert tweaks and reinstall Appx; Maximum auto-saves its state to `%LOCALAPPDATA%\WinTunePro\maximum-state.json`, and [7] re-applies the tasks/registry/Appx layer from it (or imports a state file from another PC).

It never touches the shell, the game process, anticheat, GPU drivers, Store/Edge/Terminal, Defender, VBS/HVCI, or core audio/network/security services, and uses Manual startup type rather than Disabled. An automatic restore point is created before every run.

Honest limit: process/service count is not FPS. The measurable wins are RAM, boot time and fewer idle CPU spikes — not raw frame rate. Going below ~100 processes is attempted by Maximum on a sufficiently bloated system but is not guaranteed.

**PL:** TO NIE optymalizacja — ścina obciążenie w tle, cztery poziomy:
- **Standardowy** *(tymczasowy)* — zamyka popularne aplikacje tła (przeglądarki, czat, chmura, helpery Xbox/Widgets) i zatrzymuje ~14 wyselekcjonowanych bezpiecznych usług na czas sesji.
- **Agresywny** *(stały lub tymczasowy, wymaga wpisania YES)* — dokłada launchery gier i aplikacje producentów, plus ~10 kolejnych usług.
- **Maksymalny** *(trwały, wymaga dwukrotnego wpisania YES, „tylko jeśli wiesz co robisz")* — wszystko co Agresywny, **plus**: wyłącza zaplanowane zadania telemetrii/utrzymania (telemetria zgodności, CEIP, diagnostyka dysku, raportowanie błędów, telemetria Office jeśli zainstalowany, zadania Family Safety jeśli nieużywane), usuwa wyselekcjonowaną, bezpieczną listę bloatware Appx (do przywrócenia ze Sklepu), wyłącza autostart dopasowanych aplikacji producentów (klucze Run **plus systemowy wyłącznik StartupApproved** — ten z Ustawienia → Aplikacje → Autostart — skróty Startup dowolnego typu, zadania producentów oraz **zadania startowe aplikacji ze Sklepu** jak Spotify/Teams — więc zamknięte aplikacje nie wracają po restarcie), i stosuje odwracalne tweaki rejestru (Game DVR off, aplikacje w tle off, Delivery Optimization off, treści konsumenckie Windows off, spersonalizowane doświadczenia diagnostyczne off, rekomendacje Start off).
- **Przywróć** — cofa wszystko: uruchamia zatrzymane usługi, przywraca oryginalny typ startu, włącza wyłączone zadania, przywraca wartości rejestru i wpisy Run, przenosi skróty Startup z powrotem. Usunięte aplikacje Appx są wypisane do ręcznej reinstalacji ze Sklepu (jedyny krok nieautomatyczny).
- **[5] Usługi producentów** *(opt-in)* — pogrupowane usługi-pomocnicy sprzętu (NVIDIA extras, MSI, Nahimic, Realtek, Intel graphics/mgmt, Logitech, Thrustmaster, PACE), każda grupa z jasnym ostrzeżeniem, co przestanie działać (RGB, overlay, efekty audio, wideo HDCP, licencje iLok). Wybrane grupy idą na Manual+stop; [4] je przywraca. Kontener wyświetlania GPU nigdy nie jest na liście.
- **[6] Usuwanie Appx z wyborem** — wyselekcjonowany katalog z numerami plus presety Safe/Gaming/Minimal; pokazuje tylko zainstalowane; usuwa pakiet i kopię provisioned; do przywrócenia ze Sklepu.
- **[7] Re-apply + eksport/import JSON** — duże aktualizacje Windows cofają tweaki i przywracają Appx; Maksymalny zapisuje automatycznie stan do `%LOCALAPPDATA%\WinTunePro\maximum-state.json`, a [7] nakłada ponownie warstwę zadań/rejestru/Appx (lub importuje plik stanu z innego PC).

Nigdy nie rusza powłoki, procesu gry, anticheatu, sterowników GPU, Store/Edge/Terminala, Defendera, VBS/HVCI ani krytycznych usług audio/sieci/bezpieczeństwa, i używa typu startu Manual zamiast Disabled. Automatyczny punkt przywracania przed każdym uruchomieniem.

Uczciwie: liczba procesów/usług to nie FPS. Mierzalne zyski to RAM, czas startu i mniej skoków CPU w bezczynności — nie surowe klatki. Zejście poniżej ~100 procesów jest próbowane przez Maksymalny na dostatecznie zabloatowanym systemie, ale niegwarantowane.

### [14] Spec Sheet / Karta specyfikacji
**EN:** One press, no questions asked — exports a dated `.txt` file to your Desktop with OS + build, motherboard/BIOS, CPU, GPU(s), RAM modules, storage + volumes and active network adapters, then opens it. Read-only, not analysis — built to hand to an IT person, or to re-export after a Windows update to compare against the last one.
**PL:** Jedno wciśnięcie, bez pytań — eksportuje datowany plik `.txt` na pulpit z systemem + wersją, płytą główną/BIOS, CPU, GPU, modułami RAM, dyskami + woluminami i aktywnymi kartami sieciowymi, po czym go otwiera. Tylko odczyt, nie analiza — do przekazania informatykowi albo ponownego eksportu po aktualizacji Windows w celu porównania.

### [15] Boot
**EN:** Three tools in one place. Boot-time history read straight from the Windows event log (Diagnostics-Performance Id 100) — total / MainPath / PostBoot seconds per boot — plus the degradation events (Id 101-110) that name the exact app, driver or service that slowed a boot down. A numbered autostart list (Run keys, Startup folders, Store StartupTasks) with ON/off state and disable-by-number, built on the same reversible mechanisms as Debloat, so [13] → [4] undoes it. And a Fast Startup toggle (backed up, reversible). Honest limit stated in-app: below a certain floor the disk and board POST decide the boot time, not a script.
**PL:** Trzy narzędzia w jednym miejscu. Historia czasu startu czytana wprost z dziennika zdarzeń Windows (Diagnostics-Performance Id 100) — sekundy total / MainPath / PostBoot per rozruch — plus zdarzenia degradacji (Id 101-110) wskazujące konkretną aplikację, sterownik lub usługę, która spowolniła start. Numerowana lista autostartu (klucze Run, foldery Startup, StartupTaski Sklepu) ze stanem ON/off i wyłączaniem po numerach, na tych samych odwracalnych mechanizmach co Debloat, więc [13] → [4] to cofa. Oraz przełącznik Fast Startup (z backupem, odwracalny). Uczciwa granica napisana w aplikacji: poniżej pewnego progu o czasie startu decyduje dysk i POST płyty, nie skrypt.

### [B] Guide / Przewodnik
**EN:** A plain-language glossary of every mode and every Optimize profile, reachable from the main menu and from the profile-selection screen. Changes nothing — pure documentation, kept deliberately short elsewhere (2–3 words per menu line) so the full explanations live here instead.
**PL:** Słownik po ludzku każdego trybu i każdego profilu Optymalizacji, dostępny z menu głównego i z ekranu wyboru profilu. Nic nie zmienia — czysta dokumentacja, celowo krótka gdzie indziej (2–3 słowa w menu), pełne wyjaśnienia są właśnie tutaj.

### [L] Language / Język
**EN:** Switches the console's display language between Polish and English immediately, for the rest of the session. The startup default is English (`-Language pl` forces Polish; `-Language auto` follows the Windows UI language).
**PL:** Przełącza język wyświetlania konsoli między polskim a angielskim natychmiast, do końca sesji. Domyślny język startowy to angielski (`-Language pl` wymusza polski; `-Language auto` idzie za językiem interfejsu Windows).

---

## License / Licencja

See [`LICENSE`](LICENSE). MIT is a suggested default — change it if you prefer.
Zobacz [`LICENSE`](LICENSE). MIT to sugerowane ustawienie domyślne — zmień, jeśli wolisz inaczej.
