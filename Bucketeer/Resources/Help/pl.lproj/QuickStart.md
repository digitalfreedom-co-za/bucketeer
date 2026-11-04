# Pomoc Bucketeer

Bucketeer to aplikacja na Maca do obsługi magazynów obiektowych: Amazon S3, dostawców zgodnych z S3 oraz Azure Blob Storage. Ten przewodnik opisuje wszystkie funkcje, od pierwszego konta po dyski w Finderze i zadania synchronizacji.

## Dodawanie konta

- Kliknij **+** w nagłówku paska bocznego.
- Wybierz dostawcę: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj lub Custom (MinIO i każdy inny punkt końcowy zgodny z S3).
- Wprowadź nazwę, region lub punkt końcowy oraz swoje poświadczenia (klucz dostępu i klucz tajny; w przypadku Azure klucz konta magazynu).
- Kliknij **Testuj połączenie**, a następnie **Zapisz**.

Twoje poświadczenia są przechowywane w pęku kluczy macOS na tym Macu. Bucketeer nie ma serwera ani konta użytkownika; łączy się bezpośrednio z punktami końcowymi, które skonfigurujesz.

## Edycja konta

Podczas edycji konta klucz tajny jest ukryty. Kliknij **Pokaż zapisane poświadczenia** i potwierdź za pomocą Touch ID lub hasła Maca, aby go zobaczyć. Jeśli zapiszesz zmiany bez ruszania klucza tajnego, zapisany klucz pozostanie bez zmian.

## Przeglądanie bucketów i obiektów

- Kliknij konto na pasku bocznym, aby wyświetlić jego buckety.
- Kliknij dwukrotnie bucket lub folder, aby go otworzyć. Aby wrócić, użyj paska ścieżki lub strzałki w górę.
- Zaznacz plik, aby zobaczyć jego szczegóły i podgląd Quick Look w prawym panelu.
- Użyj pola wyszukiwania, aby filtrować bieżący folder.

## Wysyłanie i pobieranie

- **Wysłanie**: kliknij przycisk wysyłania lub naciśnij **⌘U**. Możesz też przeciągnąć pliki z Findera na listę obiektów lub na bucket.
- **Pobranie**: kliknij plik prawym przyciskiem i wybierz **Pobierz…**.
- Duże pliki są przesyłane w równoległych częściach. Przerwane wysyłanie zostaje wznowione od miejsca, w którym się zatrzymało.
- Wszystkie transfery są widoczne w sekcji **Transfery** na pasku bocznym, z postępem i przyciskiem anulowania.
- W **Ustawienia → Transfery** możesz ograniczyć łączną przepustowość.

## Otwieranie plików w innych aplikacjach

- Kliknij dwukrotnie plik albo kliknij go prawym przyciskiem i wybierz **Otwórz**, aby otworzyć go w domyślnej aplikacji. **Otwórz za pomocą** pokazuje inne aplikacje, które mogą go otworzyć; **Inna…** pozwala wybrać dowolną aplikację.
- Bucketeer pobiera plik do folderu tymczasowego i go obserwuje. Chwilę po każdym zapisie plik jest ponownie wysyłany przez zwykłą kolejkę transferów, więc obowiązuje też szyfrowanie po stronie klienta.
- Jeśli po otwarciu obiekt zmienił się na serwerze lub został usunięty, Bucketeer go nie nadpisze. Twoja wersja trafia obok jako „nazwa (conflict data).rozszerzenie”, a Bucketeer wyświetla komunikat.
- Kopia tymczasowa jest usuwana, gdy serwer ma już Twój ostatni zapis. Jeśli zapisu nie udało się wysłać (np. bez połączenia), Bucketeer zachowuje plik na tym Macu i proponuje **Wyślij ponownie**, **Zapisz kopię…** lub **Odrzuć zmianę** — także przy następnym uruchomieniu, np. po awarii.

## Zarządzanie obiektami

- **Nowy folder**: przycisk na pasku narzędzi lub **⇧⌘N**.
- **Zmień nazwę…**: kliknij obiekt prawym przyciskiem. Zmiana nazwy to kopia po stronie serwera, po której następuje usunięcie. Zmiana nazwy lub usunięcie folderu dotyczy całej jego zawartości, a zmiana nazwy nigdy nie zastępuje istniejącej nazwy.
- **Usuń**: zaznacz jeden lub więcej obiektów, kliknij przycisk kosza i potwierdź.
- **Kopiuj link bezpośredni**: kopiuje link `bucketeer://` do obiektu, który otwiera go w Bucketeer z dowolnego miejsca na Twoim Macu.

## Linki do udostępniania

Kliknij plik prawym przyciskiem i wybierz **Utwórz link do udostępnienia…**. Wybierz, jak długo link ma być ważny, a następnie skopiuj go lub udostępnij. Link jest podpisywany na Twoim Macu Twoimi poświadczeniami; każdy, kto go ma, może pobrać plik, dopóki link nie wygaśnie.

## Wersje

Kliknij plik prawym przyciskiem i wybierz **Pokaż wersje…**, aby zobaczyć historię jego wersji. Możesz przywrócić starszą wersję jako nową najnowszą kopię lub usunąć pojedynczą wersję. Bucket musi mieć włączone wersjonowanie u dostawcy.

## Metadane i tagi

Kliknij plik prawym przyciskiem i wybierz **Metadane i tagi…**, aby edytować nagłówki HTTP (typ zawartości, kontrola pamięci podręcznej i inne), metadane użytkownika i tagi oraz zobaczyć klasę magazynu. Niektórzy dostawcy nie obsługują wszystkich pól; Bucketeer poinformuje Cię, gdy tak jest.

**Ustawienia → Reguły** zawiera reguły automatycznego tagowania: dodają one tagi i metadane do nowo wysyłanych plików, które pasują do wzorca nazwy pliku lub typu MIME.

## Panel bucketu

Kliknij **Panel** na pasku narzędzi otwartego bucketu. Pokazuje on liczbę obiektów, łączny rozmiar, największe obiekty, przybliżony szacunek kosztów miesięcznych oraz reguły cyklu życia, konfigurację CORS i politykę bucketu (tylko do odczytu).

## Kosz

Gdy usuwasz obiekty, Bucketeer może zachować lokalną kopię na tym Macu (**Ustawienia → Transfery → Kosz**). Otwórz kosz za pomocą **Okno → Kosz** (**⇧⌘⌫**) i kliknij **Przywróć**, aby wysłać kopię z pamięci podręcznej z powrotem na jej pierwotne miejsce. Obiekt u dostawcy jest usuwany od razu; przywrócić można tylko lokalną kopię. Wpisy są usuwane automatycznie po upływie ustawionego przez Ciebie okresu przechowywania.

## Dziennik aktywności

**Okno → Dziennik aktywności** (**⌥⌘0**) zawiera wysłania, pobrania, usunięcia, przebiegi synchronizacji, linki do udostępniania i zmiany kont. Możesz filtrować i przeszukiwać listę oraz eksportować ją jako CSV. Wpisy są przechowywane na tym Macu przez 180 dni.

## Szyfrowanie po stronie klienta

W **Ustawienia → Szyfrowanie** możesz utworzyć klucz dla bucketu. Od tej chwili każdy plik wysyłany do tego bucketu jest szyfrowany na Twoim Macu (AES-256-GCM), zanim go opuści, a pobierane pliki są odszyfrowywane na bieżąco. Klucz jest przechowywany w pęku kluczy macOS wyłącznie na tym Macu.

Ważne: jeśli zgubisz klucz, nikt nie odszyfruje tych obiektów, także my. Zaszyfrowanych bucketów nie można zamontować w Finderze w tej wersji Bucketeer.

## Spotlight

**Ustawienia → Transfery → Spotlight** jest domyślnie wyłączone. Gdy to włączysz, nazwy przeglądanych obiektów stają się wyszukiwalne w Spotlight. Zawartość plików nigdy nie jest indeksowana, a indeks pozostaje na tym Macu.

## Skróty i Siri

Bucketeer dodaje akcje do aplikacji Skróty: wyświetlanie listy bucketów, wysyłanie pliku, tworzenie linku do udostępniania i uruchamianie zadania synchronizacji. Używaj ich we własnych skrótach lub poproś Siri.

## Funkcje Pro

Te funkcje wymagają Bucketeer Pro:

- **Zamontuj jako dysk**: kliknij bucket prawym przyciskiem i wybierz **Zamontuj jako dysk**, aby używać go w Finderze jak dysku. Zamontowane dyski są widoczne w sekcji **Zamontowane dyski** na pasku bocznym; kliknij prawym przyciskiem, aby wybrać **Odmontuj**. Bucketów z szyfrowaniem po stronie klienta nie można zamontować. Zmiany na serwerze pojawiają się w Finderze po odświeżeniu bucketu w Bucketeer. Jeśli plik edytowany w Finderze zmienił się w międzyczasie na serwerze, Twoja wersja zostaje zapisana obok jako kopia konfliktu.
- **Zadania synchronizacji**: w sekcji **Synchronizacja** utwórz zadanie, które kopiuje, przenosi lub tworzy kopię lustrzaną między dwoma bucketami, także między kontami i dostawcami, albo między lokalnym folderem a bucketem. Uruchamiaj je ręcznie, przy uruchomieniu aplikacji, co N minut lub gdy zmieni się lokalny folder.
- **Foldery obserwowane**: **Nowy folder obserwowany…** wysyła każdy nowy plik z lokalnego folderu do bucketu.
- **Kopiuj na inne konto…**: kopiuje obiekty na inne konto lub do innego dostawcy. Jeśli obie strony na to pozwalają, kopiowanie odbywa się po stronie serwera, a dane nie przechodzą przez Twojego Maca.
- **Tryb paska menu**: **Ustawienia → Ogólne** pozwala Bucketeer działać na pasku menu, dzięki czemu dyski i zadania synchronizacji pozostają aktywne po zamknięciu głównego okna.

Wszystko inne jest dostępne w wersji bezpłatnej.

## Bucketeer Pro, okres próbny i zakup

Bucketeer Pro to jednorazowy zakup w aplikacji przez App Store, bez subskrypcji. Otwórz **Ustawienia → Pro** lub dowolną funkcję Pro, aby zobaczyć cenę w swojej walucie i dokonać zakupu.

Bucketeer Pro możesz wypróbować bezpłatnie przez 14 dni. Przed rozpoczęciem strona zakupu pokazuje długość okresu próbnego, co dzieje się potem i cenę Pro na zawsze; następnie kliknij **Rozpocznij okres próbny**. Po zakończeniu okresu próbnego Bucketeer działa dalej w wersji bezpłatnej i nic nie jest pobierane. Okres próbny można rozpocząć raz na Apple ID, a przywrócenie zakupów przywraca trwający okres próbny także na innym Macu.

- **Przywróć zakup** przywraca Pro na innym Macu lub po ponownej instalacji.
- **Zrealizuj kod** otwiera okno Apple do realizacji kodów ofert.

## Skróty klawiszowe

- **⌘U**: Wyślij pliki
- **⇧⌘N**: Nowy folder
- **⌥⌘0**: Dziennik aktywności
- **⇧⌘⌫**: Kosz
- **⌘?**: Pomoc Bucketeer
- **⌘,**: Ustawienia

## Prywatność

Bucketeer nie zbiera danych analitycznych i nie zawiera mechanizmów śledzenia. Twoje konta, klucze i dzienniki pozostają na tym Macu. Ruch sieciowy trafia wyłącznie do skonfigurowanych przez Ciebie dostawców magazynu oraz do Apple w przypadku zakupów. Szczegóły: **Pomoc → Polityka prywatności…**

## Potrzebujesz pomocy?

- Zgłoś problem: **Pomoc → Zgłoś problem…** lub <https://support.apps.digitalfreedom.co.za/>
- Strona internetowa: <https://digitalfreedom.co.za>
