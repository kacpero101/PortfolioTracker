# PortfolioTracker

Natywna aplikacja macOS (Swift/SwiftUI) do ręcznego monitorowania portfela inwestycyjnego:
akcje, ETF-y, obligacje, gotówka, krypto. Ceny akcji/ETF-ów/krypto pobierane są automatycznie
z darmowego, nieoficjalnego API Yahoo Finance przy uruchomieniu programu.

## Struktura projektu

```
PortfolioTracker/
├── PortfolioTrackerApp.swift        // punkt wejścia aplikacji
├── Models/
│   ├── Asset.swift                  // pojedyncza pozycja w portfelu
│   ├── AssetType.swift              // klasy aktywów (akcja/ETF/obligacja/gotówka/krypto)
│   └── PortfolioSnapshot.swift      // punkt historii wartości portfela
├── Services/
│   ├── PriceService.swift           // pobieranie cen z Yahoo Finance
│   └── PortfolioStore.swift         // logika biznesowa + zapis/odczyt danych (JSON)
├── Views/
│   ├── ContentView.swift            // zakładki główne
│   ├── SummaryView.swift            // podsumowanie + wykres kołowy
│   ├── AllocationChartView.swift    // wykres kołowy alokacji
│   ├── HistoryChartView.swift       // wykres liniowy wartości w czasie
│   ├── AssetsView.swift             // lista aktywów
│   └── AddAssetView.swift           // formularz dodawania/edycji
└── Resources/
    └── PortfolioTracker.entitlements
```

## Jak uruchomić w Xcode (krok po kroku)

1. **Utwórz nowy projekt**: Xcode → File → New → Project → **macOS → App**.
   - Product Name: `PortfolioTracker`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - odznacz „Use Core Data” i „Include Tests” (niepotrzebne)

2. **Usuń wygenerowane pliki**, które Xcode stworzył automatycznie:
   - `PortfolioTrackerApp.swift` (domyślny)
   - `ContentView.swift` (domyślny)

3. **Przeciągnij foldery `Models`, `Services`, `Views`, `Resources` oraz plik
   `PortfolioTrackerApp.swift`** z pobranego archiwum do nawigatora projektu w Xcode
   (przeciągnij na nazwę projektu w lewym panelu). W oknie, które się pojawi,
   zaznacz **„Copy items if needed”** oraz upewnij się, że pliki są dodane do targetu
   `PortfolioTracker`.

4. **Podłącz plik entitlements**:
   - Kliknij na projekt w nawigatorze → zakładka **Signing & Capabilities** targetu `PortfolioTracker`.
   - Kliknij **„+ Capability”** → dodaj **App Sandbox** (jeśli nie ma).
   - W sekcji App Sandbox zaznacz **„Outgoing Connections (Client)”** — to jest dokładnie to,
     co znajduje się w pliku `PortfolioTracker.entitlements`. Xcode powinien sam podłączyć
     plik entitlements do targetu (sprawdź w Build Settings → „Code Signing Entitlements”,
     czy wskazuje na `Resources/PortfolioTracker.entitlements`).

5. **Minimalny system**: w Build Settings ustaw **macOS Deployment Target na 13.0** lub wyżej
   (potrzebne dla frameworka Swift Charts używanego do wykresów).

6. Zbuduj i uruchom (**⌘R**).

## Jak to działa

- **Dodawanie aktywów**: w zakładce „Aktywa” → przycisk „+”. Dla akcji/ETF-ów/krypto podajesz
  ticker (np. `AAPL`, `VOO`, `BTC`) — dla obligacji i gotówki ticker nie jest potrzebny,
  a aktualną wartość wpisujesz ręcznie.
- **Pobieranie cen**: przy starcie aplikacji (i na żądanie, przyciskiem „Odśwież ceny”)
  aplikacja odpytuje `query1.finance.yahoo.com/v8/finance/chart/{TICKER}` — to publiczny,
  darmowy, ale nieoficjalny endpoint Yahoo Finance (nie wymaga klucza API). Jeśli pobranie
  ceny dla danego tickera się nie powiedzie, portfel pokaże ostatnią znaną cenę (lub cenę
  zakupu), a błąd pojawi się w podsumowaniu.
- **Dane lokalne**: aktywa i historia wartości portfela są zapisywane jako pliki JSON w
  `~/Library/Application Support/PortfolioTracker/` (bez chmury, bez konta — wszystko lokalnie).
- **Wykres liniowy**: jeden punkt historii jest zapisywany przy każdym odświeżeniu cen
  (nadpisywany, jeśli w danym dniu już istnieje) — więc wykres nabierze kształtu po kilku
  dniach regularnego uruchamiania aplikacji.

## Możliwe rozszerzenia na przyszłość

- Wsparcie dla wielu walut (obecnie wszystko liczone jest tak, jak zwraca je Yahoo — zwykle USD).
- Import transakcji z pliku CSV z biura maklerskiego.
- Powiadomienia o dużych zmianach wartości portfela.
- Migracja z plików JSON na SQLite, jeśli liczba pozycji bardzo urośnie (dla kilkudziesięciu/kilkuset pozycji obecne rozwiązanie w zupełności wystarczy).
