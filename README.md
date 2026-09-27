# PortfolioTracker

Natywna aplikacja **macOS** (Swift/SwiftUI) do ręcznego monitorowania portfela inwestycyjnego:
akcje, ETF-y, obligacje (w tym skarbowe EDO), gotówka, kryptowaluty, złoto i srebro.
Ceny akcji/ETF-ów/krypto oraz złota i srebra są pobierane automatycznie z darmowego,
nieoficjalnego API Yahoo Finance przy uruchomieniu programu i na żądanie.

## Wymagania

- macOS **15.6** lub nowszy (Deployment Target aplikacji w `PortfolioTracker.xcodeproj`),
- Xcode z obsługą Swift Testing (projekt jest tworzony i testowany w aktualnym Xcode).

## Struktura projektu

```
PortfolioTracker.xcodeproj           // gotowy projekt Xcode (targety: PortfolioTracker, PortfolioTrackerTests)
Resources/
└── PortfolioTracker.entitlements    // App Sandbox + połączenia wychodzące (Yahoo, obligacjeskarbowe.pl)
PortfolioTracker/
├── PortfolioTrackerApp.swift        // punkt wejścia aplikacji
├── Models/
│   ├── Asset.swift                  // pojedyncza pozycja w portfelu
│   ├── AssetType.swift              // klasy aktywów
│   └── PortfolioSnapshot.swift      // punkt historii wartości portfela
├── Services/
│   ├── PriceService.swift           // pobieranie cen i kursów walut z Yahoo Finance
│   ├── BondRateService.swift        // oprocentowanie serii obligacji EDO z obligacjeskarbowe.pl
│   ├── AssetColorStore.swift        // kolory klas aktywów (zmieniane przez użytkownika)
│   └── PortfolioStore.swift         // logika biznesowa + zapis/odczyt danych (JSON)
└── Views/
    ├── ContentView.swift            // zakładki główne
    ├── SummaryView.swift            // podsumowanie + wykres kołowy
    ├── AllocationChartView.swift    // wykres kołowy alokacji + wybór kolorów
    ├── HistoryChartView.swift       // wykres liniowy wartości w czasie
    ├── AssetsView.swift             // lista aktywów
    └── AddAssetView.swift           // formularz dodawania/edycji
PortfolioTrackerTests/               // testy jednostkowe (Swift Testing)
```

## Jak uruchomić

1. Otwórz `PortfolioTracker.xcodeproj` w Xcode.
2. Wybierz schemat **PortfolioTracker** i cel **My Mac**.
3. Uruchom: **⌘R**. Przy pierwszym uruchomieniu Xcode może poprosić o wybór zespołu
   do podpisywania (Signing & Capabilities). Do lokalnego uruchomienia wystarczy „Sign to Run Locally”.

Z terminala:

```sh
xcodebuild build -project PortfolioTracker.xcodeproj -scheme PortfolioTracker -destination 'platform=macOS'
```

## Testy

W Xcode: **⌘U**. Z terminala:

```sh
xcodebuild test -project PortfolioTracker.xcodeproj -scheme PortfolioTracker -destination 'platform=macOS'
```

Testy nie korzystają z sieci. Obejmują parsowanie stron serii EDO, zgodność wsteczną `assets.json`
oraz wycenę pozycji (ceny ręczne, waluta zakupu, domyślne kolory).

## Jak to działa

- **Dodawanie aktywów**: w zakładce „Aktywa” → przycisk „+”. Dla akcji/ETF-ów/krypto podajesz
  ticker (np. `AAPL`, `VOO`, `BTC`, `CDR.WA`). Dla obligacji i gotówki ticker nie jest potrzebny.
  Cenę zakupu podajesz w wybranej walucie zakupu, a aplikacja przelicza ją na USD
  (wewnętrzna waluta bazowa) po kursie z Yahoo (`PLNUSD=X` itp.).
- **Cena ręczna**: dla akcji, ETF-ów, krypto, złota i srebra możesz wpisać aktualną cenę
  (w walucie zakupu). Jest używana, gdy aplikacja nie ma pobranej ceny, np. offline albo przy błędnym tickerze.
  Dla obligacji to samo pole oznacza aktualną wartość jednej obligacji.
- **Edycja i usuwanie**: kliknij pozycję, żeby ją edytować. Usunąć ją możesz przyciskiem „Usuń” w edycji
  albo gestem przesunięcia na liście. W obu przypadkach aplikacja najpierw prosi o potwierdzenie.
- **Pobieranie cen**: raz przy starcie aplikacji (i na żądanie, przyciskiem „Odśwież ceny”)
  aplikacja odpytuje `query1.finance.yahoo.com/v8/finance/chart/{TICKER}` — to publiczny,
  darmowy, ale nieoficjalny endpoint Yahoo Finance (nie wymaga klucza API). Jeśli pobranie
  ceny dla danego tickera się nie powiedzie, portfel pokaże ostatnią znaną cenę (lub cenę
  zakupu), a błąd pojawi się w podsumowaniu. Złoto i srebro są wyceniane według kontraktów
  `GC=F` i `SI=F` (USD za uncję), a gotówka według kursu waluty do USD.
- **Obligacje skarbowe EDO**: przy klasie „Obligacje” zaznacz „Obligacje skarbowe EDO” i podaj
  serię (np. `EDO0936` = sprzedaż we wrześniu 2026, wykup we wrześniu 2036 — przycisk
  „Z daty zakupu” wylicza ją automatycznie). Przycisk „Pobierz oprocentowanie” pobiera ze strony
  serii na `obligacjeskarbowe.pl` oprocentowanie w 1. roku oraz marżę (starsze serie nie podają
  marży na stronie — wtedy wpisz ją ręcznie z listu emisyjnego). Od 2. roku oprocentowanie =
  marża + inflacja, którą wpisujesz ręcznie. Wszystkie pola można też wypełnić ręcznie (np. offline).
  Pobrane stawki są zapamiętywane, bo oprocentowanie ogłoszonej serii się nie zmienia.
- **Kolory**: kliknij kolor klasy w legendzie wykresu kołowego, żeby wybrać inny z palety.
- **Dane lokalne**: aktywa i historia wartości portfela są zapisywane jako pliki JSON w
  `~/Library/Application Support/PortfolioTracker/` (bez chmury, bez konta — wszystko lokalnie).
- **Wykres liniowy**: jeden punkt historii jest zapisywany przy każdym odświeżeniu cen
  (nadpisywany, jeśli w danym dniu już istnieje) — więc wykres nabierze kształtu po kilku
  dniach regularnego uruchamiania aplikacji.

## Możliwe rozszerzenia na przyszłość

- Wyświetlanie wartości portfela w innej walucie niż USD (np. PLN).
- Import transakcji z pliku CSV z biura maklerskiego.
- Powiadomienia o dużych zmianach wartości portfela.
- Migracja z plików JSON na SQLite, jeśli liczba pozycji bardzo urośnie (dla kilkudziesięciu/kilkuset pozycji obecne rozwiązanie w zupełności wystarczy).
