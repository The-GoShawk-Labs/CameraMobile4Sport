# Instrukcja Testowania na Sprzęcie Fizycznym (Device Testing Guide)
**Projekt:** CameraMobile4Sport (Sport Video Streaming System)  
**Docelowe urządzenia referencyjne:** 
- **Samsung Galaxy A53 5G** (`SM-A536B`, ID: `RZCT40DG2DK`, Android 16 / One UI)
- **Realme** (Android / Realme UI / ColorOS)

---

## 1. Wymagania Wstępne i Konfiguracja Smartfonów

Przed przystąpieniem do testów na obu smartfonach należy aktywować uprawnienia deweloperskie i połączenie USB.

### Krok po kroku na smartfonach:
1. **Włączenie Opcji Programisty:**
   - Wejdź w **Ustawienia** $\rightarrow$ **Informacje o telefonie** $\rightarrow$ **Wersja / Informacje o oprogramowaniu**.
   - Dotknij **Numer kompilacji** (Build number) **7 razy**, aż pojawi się komunikat: *„Jesteś teraz programistą”*.
2. **Aktywacja Debugowania USB:**
   - Wejdź w **Ustawienia** $\rightarrow$ **System / Dodatkowe ustawienia** $\rightarrow$ **Opcje programisty**.
   - Włącz:
     - **Debugowanie USB** (USB Debugging).
     - *(Wymagane szczególnie na Realme:)* **Instaluj przez USB** (Install via USB) oraz **Debugowanie USB (Ustawienia zabezpieczeń)**.
3. **Zatwierdzenie klucza komputera (Autoryzacja):**
   - Podłącz telefon kablem USB do komputera.
   - Na ekranie telefonu pojawi się okno z pytaniem: *„Zezwalać na debugowanie USB?”*.
   - Zaznacz: **„Zawsze zezwalaj z tego komputera”** i kliknij **Zezwól**.

---

## 2. Identyfikacja Urządzeń w Systemie

Ścieżka do narzędzia ADB w środowisku Windows:
```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
```

### Sprawdzenie podłączonych urządzeń:
Otwórz terminal w katalogu projektu (`c:\Users\kusoj\Desktop\Projekty\GoGoShawk\CameraMobile4Sport`) i wykonaj:

```powershell
flutter devices
```
lub bezpośrednio przez ADB:
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
```

**Przykładowy wynik:**
- Samsung Galaxy A53: `RZCT40DG2DK`
- Realme: `[ID_REALME]` (np. ciąg znaków alfanumerycznych)

---

## 3. Metody Budowy i Instalacji / Aktualizacji Aplikacji

### Sposób A: Błyskawiczna instalacja / aktualizacja plikiem APK (Rekomendowany)
Pozwala skompilować aplikację **tylko raz** i błyskawicznie wgrać ją na oba smartfony bez blokowania konsoli.

#### Krok 1: Budowa paczki APK:
```powershell
cd c:\Users\kusoj\Desktop\Projekty\GoGoShawk\CameraMobile4Sport
flutter build apk --debug
```
*Plik wyjściowy powstaje w lokalizacji:*  
`build\app\outputs\flutter-apk\app-debug.apk`

#### Krok 2: Instalacja na Samsungu:
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s RZCT40DG2DK install -r build\app\outputs\flutter-apk\app-debug.apk
```

#### Krok 3: Instalacja na Realme:
*(Zastąp `ID_REALME` identyfikatorem z polecenia `flutter devices`)*
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s ID_REALME install -r build\app\outputs\flutter-apk\app-debug.apk
```

> **Uwaga:** Parametr `-r` oznacza *reinstall* – instaluje nową wersję bez czyszczenia danych aplikacji ani konfiguracji.

---

### Sposób B: Uruchomienie z Live Debugging (Flutter Run)
Wygodne przy testowaniu logów na żywo i korzystaniu z Hot Reload (`r`) oraz Hot Restart (`R`).

- **Dla Samsung Galaxy A53:**
  ```powershell
  flutter run -d RZCT40DG2DK
  ```
- **Dla Realme:**
  ```powershell
  flutter run -d ID_REALME
  ```
- **Dla obu smartfonów jednocześnie:**
  Otwórz dwa niezależne okna PowerShell i w każdym uruchom powyższe polecenie z odpowiednim ID urządzenia.

---

### Sposób C: Dystrybucja bezprzewodowa (Bez kabla USB)
1. Po zbudowaniu APK plik znajduje się w:
   `c:\Users\kusoj\Desktop\Projekty\GoGoShawk\CameraMobile4Sport\build\app\outputs\flutter-apk\app-debug.apk`
2. Możesz przesłać ten plik bezpośrednio z komputera na telefon lub między telefonami za pomocą:
   - **Quick Share** / Udostępnianie w pobliżu (Windows $\rightarrow$ Android lub Samsung $\rightarrow$ Realme).
   - Dysku Google / kabla MTP (przesyłanie plików).
3. Na telefonie kliknij pobrany plik `app-debug.apk` i wybierz **Zainstaluj / Aktualizuj**.

---

## 4. Scenariusze Testowe (Krok po Kroku)

### Scenariusz 1: Test Widoku Kamery (Phone A – `PhoneACameraScreen`)
**Cel:** Sprawdzenie responsywności, ergonomii i braku nachodzenia na siebie elementów w pionie i poziomie.

1. Uruchom aplikację i wybierz tryb **Phone A (Kamera)**.
2. **Orientacja Pionowa (Portrait):**
   - Sprawdź górny pasek telemetryczny: przyciski `MENU`, `SĘDZIA`, `STATYSTYKI`, `KADR` muszą być duże i łatwe do kliknięcia.
   - Sprawdź drugi wiersz: `REC: GOTOWY`, `1080p | 60 FPS | 8M`, `OFFLINE`, wskaźnik baterii.
   - Wciśnij przycisk **`KADR`** – upewnij się, że wszystkie kontrolki znikają, odsłaniając pełny podgląd strumienia z tablicą wyników, a ponowne dotknięcie ekranu przywraca kontrolki.
   - Sprawdź dolny pasek: duży, świecący przycisk `START TRANSMISJI / REC`, wskaźnik VU meter oraz przełączniki obiektywów (`0.5x`, `1x`, `2x`).
3. **Orientacja Pozioma (Landscape):**
   - Obróć smartfon do poziomu.
   - Upewnij się, że górny pasek nie nachodzi na wycięcie aparatu (punch-hole) ani na prawą krawędź ekranu.
   - Sprawdź boczne przyciski: `EV`, `1.0x`, `AF AUTO`, `AE AUTO` – czy tekst jest idealnie wyśrodkowany i czytelny.
   - Upewnij się, że tablica wyników ([`ScoreboardOverlay`]) znajduje się pod paskiem telemetrii z bezpiecznym odstępem.

---

### Scenariusz 2: Test Pulpitu Sędziego (Phone B – `PhoneBScorerScreen`)
**Cel:** Sprawdzenie wprowadzania punktacji i sterowania tablicą.

1. Na drugim telefonie uruchom aplikację i wybierz tryb **Phone B (Pulpit sędziego)**.
2. Sprawdź 2-rzędowy nagłówek:
   - Rząd 1: `MENU`, `PODGLĄD / KOKPIT`, ikony narzędzi (`tune`, tryb słoneczny, blokada, bateria).
   - Rząd 2: Duże przyciski `START LIVE`, `START REC` oraz pigułka połączenia `Phone A`.
3. Przetestuj przycisk **`PODGLĄD / KOKPIT`**:
   - Przełącz w tryb podglądu – sprawdź, czy kadr kamery jest w pełni widoczny bez zasłaniania przez przyciski punktacji.
   - Przełącz w tryb kokpitu – sprawdź responsywność przycisków dodawania punktów dla obu drużyn.

---

### Scenariusz 3: Test Połączenia Dwutelefonowego (WebRTC / Hotspot P2P)
**Cel:** Weryfikacja synchronizacji tablicy i transmisji wideo między telefonami.

1. Połącz oba telefony z tą samą siecią Wi-Fi lub utwórz **Hotspot Wi-Fi** na jednym z nich i podłącz drugi.
2. Uruchom Phone A w trybie kamery i wyświetl kod parowania / oczekuj na połączenie.
3. Na Phone B wybierz połączenie z Phone A.
4. Zmień wynik na Phone B $\rightarrow$ zweryfikuj natychmiastową zmianę na tablicy wyników na Phone A.
5. Sprawdź opóźnienie (latencję) wskazywaną na pigułce telemetrycznej `Phone A (XXms)`.

---

## 5. Narzędzia Diagnostyczne i Zrzuty Ekranu

Do zdalnej weryfikacji widoku smartfona z poziomu komputera służą poniższe polecenia:

### Pobieranie zrzutu ekranu z podłączonego telefonu:
```powershell
# Zrzut z Samsunga:
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s RZCT40DG2DK exec-out screencap -p > zrzut_samsung.png

# Zrzut z Realme:
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s ID_REALME exec-out screencap -p > zrzut_realme.png
```

### Podgląd logów na żywo (tylko z aplikacji):
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s RZCT40DG2DK logcat -s flutter
```

### Sprawdzenie stanu baterii i temperatury urządzenia:
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s RZCT40DG2DK shell dumpsys battery
```

---

## 6. Rozwiązywanie Problemów (Troubleshooting)

| Problem | Przyczyna | Rozwiązanie |
|---|---|---|
| `adb : The term 'adb' is not recognized` | Brak ADB w zmiennej PATH środowiska Windows | Używaj pełnej ścieżki: `& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"` |
| Status urządzenia `unauthorized` w `adb devices` | Brak potwierdzenia autoryzacji RSA na telefonie | Odblokuj smartfon i kliknij „Zezwalaj na debugowanie z tego komputera” |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Konflikt podpisów z poprzednią wersją aplikacji | Odinstaluj starą aplikację poleceniem: `adb uninstall com.example.camera_mobile4sport` lub z poziomu ekranu telefonu |
| Realme blokuje instalację przez USB | Włączone zabezpieczenia ColorOS / Realme UI | W opcjach programisty na Realme włącz opcję: **Instaluj przez USB** (wymaga logowania do konta HeyTap/Realme) |
| Błędy `RenderFlex overflowed` na ekranie | Zbyt mała przestrzeń na kontrolki w danym modelu | Użyj widżetów `FittedBox` i elastycznych wierszy (patrz `walkthrough.md`) |
