# Bucketeer súgó

A Bucketeer egy Mac-alkalmazás objektumtároláshoz: Amazon S3, S3-kompatibilis szolgáltatók és Azure Blob Storage. Ez az útmutató minden funkciót bemutat, az első fióktól a Finder-meghajtókig és a szinkronizálási feladatokig.

## Fiók hozzáadása

- Kattints a **+** gombra az oldalsáv fejlécében.
- Válassz szolgáltatót: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj vagy Custom (MinIO és bármely más S3-kompatibilis végpont).
- Add meg a nevet, a régiót vagy a végpontot, valamint a hitelesítő adataidat (hozzáférési kulcs és titkos kulcs; Azure esetén a tárfiók kulcsa).
- Kattints a **Kapcsolat tesztelése**, majd a **Mentés** gombra.

A hitelesítő adataid a macOS-kulcskarikában tárolódnak ezen a Macen. A Bucketeernek nincs szervere és nincs felhasználói fiókja; közvetlenül a beállított végpontokkal kommunikál.

## Fiók szerkesztése

Fiók szerkesztésekor a titkos kulcs rejtve van. Kattints a **Mentett hitelesítő adatok felfedése** gombra, és erősítsd meg Touch ID-val vagy a Mac jelszavaddal a megtekintéshez. Ha a titkos kulcs érintése nélkül mentesz, a tárolt kulcs változatlan marad.

## Bucketek és objektumok böngészése

- Kattints egy fiókra az oldalsávban a bucketjei megjelenítéséhez.
- Egy bucket vagy mappa megnyitásához kattints rá duplán. A visszalépéshez használd az útvonalsávot vagy a felfelé nyilat.
- Jelölj ki egy fájlt a részletei és egy Gyors körbenézés előnézet megjelenítéséhez a jobb oldali panelen.
- A keresőmezővel szűrheted az aktuális mappát.

## Feltöltés és letöltés

- **Feltöltés**: kattints a feltöltés gombra, vagy nyomd meg a **⌘U** billentyűkombinációt. Fájlokat a Finderből is behúzhatsz az objektumlistába vagy egy bucketre.
- **Letöltés**: kattints jobb gombbal egy fájlra, és válaszd a **Letöltés…** lehetőséget.
- A nagy fájlok párhuzamos részekben kerülnek átvitelre. A megszakadt feltöltés ott folytatódik, ahol abbamaradt.
- Minden átvitel megjelenik az oldalsáv **Átvitelek** részében a folyamat állapotával és egy megszakítás gombbal.
- A **Beállítások → Átvitelek** alatt korlátozhatod a teljes sávszélességet.

## Objektumok kezelése

- **Új mappa**: az eszközsor gombja vagy **⇧⌘N**.
- **Átnevezés…**: kattints jobb gombbal egy objektumra. Az átnevezés egy szerveroldali másolás, amelyet törlés követ.
- **Törlés**: jelölj ki egy vagy több objektumot, kattints a kuka gombra, és erősítsd meg.
- **Deep link másolása**: egy `bucketeer://` linket másol az objektumhoz, amely a Mac bármely pontjáról megnyitja azt a Bucketeerben.

## Megosztási linkek

Kattints jobb gombbal egy fájlra, és válaszd a **Megosztási link lekérése…** lehetőséget. Válaszd ki, meddig legyen érvényes a link, majd másold vagy oszd meg. A linket a Maced írja alá a hitelesítő adataiddal; bárki, akinél megvan, letöltheti a fájlt, amíg a link le nem jár.

## Verziók

Kattints jobb gombbal egy fájlra, és válaszd a **Verziók megjelenítése…** lehetőséget a verzióelőzmények megtekintéséhez. Egy régebbi verziót visszaállíthatsz új legfrissebb példányként, vagy törölhetsz egyetlen verziót. Ehhez a bucketen engedélyezve kell lennie a verziókezelésnek a szolgáltatónál.

## Metaadatok és címkék

Kattints jobb gombbal egy fájlra, és válaszd a **Metaadatok és címkék…** lehetőséget a HTTP-fejlécek (tartalomtípus, cache control és mások), a felhasználói metaadatok és a címkék szerkesztéséhez, valamint a tárolási osztály megtekintéséhez. Nem minden szolgáltató támogat minden mezőt; a Bucketeer jelzi, ha ez a helyzet.

A **Beállítások → Szabályok** az automatikus címkézési szabályokat tartalmazza: ezek címkéket és metaadatokat adnak azokhoz az új feltöltésekhez, amelyek megfelelnek egy fájlnévmintának vagy MIME-típusnak.

## Bucket irányítópult

Kattints az **Irányítópult** gombra egy megnyitott bucket eszközsorában. Megjeleníti az objektumok számát, a teljes méretet, a legnagyobb objektumokat, a havi költség durva becslését, valamint a bucket életciklus-szabályait, CORS-beállításait és bucket-szabályzatát (csak olvasható).

## Kuka

Objektumok törlésekor a Bucketeer megtarthat egy helyi másolatot ezen a Macen (**Beállítások → Átvitelek → Kuka**). Nyisd meg a kukát az **Ablak → Kuka** menüponttal (**⇧⌘⌫**), és kattints a **Visszaállítás** gombra, hogy egy tárolt másolatot visszatölts az eredeti helyére. A szolgáltatónál lévő objektum azonnal törlődik; csak a helyi másolat állítható vissza. A bejegyzések a beállított megőrzési idő után automatikusan törlődnek.

## Tevékenységnapló

Az **Ablak → Tevékenységnapló** (**⌥⌘0**) felsorolja a feltöltéseket, letöltéseket, törléseket, szinkronizálási futásokat, megosztási linkeket és fiókváltozásokat. A listát szűrheted, kereshetsz benne, és exportálhatod CSV-ként. A bejegyzések 180 napig maradnak meg ezen a Macen.

## Ügyféloldali titkosítás

A **Beállítások → Titkosítás** alatt kulcsot hozhatsz létre egy buckethez. Ettől kezdve minden, abba a bucketbe történő feltöltés a Maceden titkosítódik (AES-256-GCM), mielőtt elhagyná azt, a letöltések pedig menet közben visszafejtődnek. A kulcs kizárólag ezen a Macen, a macOS-kulcskarikában tárolódik.

Fontos: ha elveszíted a kulcsot, senki sem tudja visszafejteni ezeket az objektumokat, mi sem. A titkosított bucketek a Bucketeer ezen verziójában nem csatolhatók a Finderbe.

## Spotlight

A **Beállítások → Átvitelek → Spotlight** alapértelmezés szerint ki van kapcsolva. Ha bekapcsolod, a böngészett objektumok nevei kereshetővé válnak a Spotlightban. A fájlok tartalma soha nem kerül indexelésre, és az index ezen a Macen marad.

## Parancsok és Siri

A Bucketeer műveleteket ad a Parancsok apphoz: bucketek listázása, fájl feltöltése, megosztási link létrehozása és szinkronizálási feladat futtatása. Használd őket a saját parancsaidban, vagy kérd meg Sirit.

## Pro funkciók

Ezekhez a funkciókhoz Bucketeer Pro szükséges:

- **Csatolás meghajtóként**: kattints jobb gombbal egy bucketre, és válaszd a **Csatolás meghajtóként** lehetőséget, hogy a Finderben lemezként használd. macOS 14.1 vagy újabb szükséges. A csatolt meghajtók az oldalsáv **Csatolt meghajtók** részében jelennek meg; jobb gombbal kattintva válaszd a **Leválasztás** lehetőséget. Az ügyféloldali titkosítással rendelkező bucketek nem csatolhatók.
- **Szinkronizálási feladatok**: a **Szinkronizálás** részben olyan feladatot hozhatsz létre, amely két bucket között másol, áthelyez vagy tükröz, fiókok és szolgáltatók között is, vagy egy helyi mappa és egy bucket között. Futtathatod kézzel, indításkor, N percenként vagy amikor a helyi mappa megváltozik.
- **Figyelt mappák**: az **Új figyelt mappa…** egy helyi mappa minden új fájlját feltölti egy bucketbe.
- **Másolás másik fiókba…**: objektumokat másol egy másik fiókba vagy szolgáltatóhoz. Ha mindkét oldal engedi, a másolás szerveroldalon fut, és az adatok nem haladnak át a Maceden.
- **Menüsor mód**: a **Beállítások → Általános** alatt a Bucketeer a menüsorban fut tovább, így a meghajtók és a szinkronizálási feladatok aktívak maradnak a főablak bezárása után is.

Minden más elérhető a Free csomagban.

## Bucketeer Pro, próbaidőszak és vásárlás

A Bucketeer Pro egyszeri, alkalmazáson belüli vásárlás az App Store-on keresztül, előfizetés nélkül. Nyisd meg a **Beállítások → Pro** lapot vagy bármelyik Pro funkciót, hogy lásd az árat a saját pénznemedben, és megvásárold.

Ha a példányodhoz próbaidőszak érhető el, a vásárlási ablak és a **Beállítások → Pro** megmutatja, meddig tart. Amikor lejár, a Bucketeer a Free csomaggal működik tovább, és semmit nem számolunk fel.

- A **Vásárlás visszaállítása** egy másik Macen vagy újratelepítés után visszaadja a Pro funkciókat.
- A **Kód beváltása** (macOS 15 vagy újabb) megnyitja az Apple ajánlati kódokhoz tartozó ablakát.

## Billentyűparancsok

- **⌘U**: Fájlok feltöltése
- **⇧⌘N**: Új mappa
- **⌥⌘0**: Tevékenységnapló
- **⇧⌘⌫**: Kuka
- **⌘?**: Bucketeer súgó
- **⌘,**: Beállítások

## Adatvédelem

A Bucketeer nem gyűjt elemzési adatokat, és nem tartalmaz követést. A fiókjaid, kulcsaid és naplóid ezen a Macen maradnak. A hálózati forgalom csak az általad beállított tárhelyszolgáltatókhoz, vásárláskor pedig az Apple-höz irányul. Részletek: **Súgó → Adatvédelmi irányelvek…**

## Segítségre van szükséged?

- Hiba bejelentése: **Súgó → Hiba bejelentése…** vagy <https://support.apps.digitalfreedom.co.za/>
- Weboldal: <https://digitalfreedom.co.za>
