# Bucketeer súgó

A Bucketeer egy Mac-alkalmazás objektumtároláshoz: Amazon S3, S3-kompatibilis szolgáltatók és Azure Blob Storage. Ez az útmutató minden funkciót bemutat, az első fióktól a Finder-meghajtókig és a szinkronizálási feladatokig.

## Fiók hozzáadása

- Kattintson a **+** gombra az oldalsáv fejlécében.
- Válasszon szolgáltatót: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj vagy Custom (MinIO és bármely más S3-kompatibilis végpont).
- Adja meg a nevet, a régiót vagy a végpontot, valamint a hitelesítő adatait (hozzáférési kulcs és titkos kulcs; Azure esetén a tárfiók kulcsa).
- Kattintson a **Kapcsolat tesztelése**, majd a **Mentés** gombra.

A hitelesítő adatai a macOS-kulcskarikában tárolódnak ezen a Macen. A Bucketeernek nincs szervere és nincs felhasználói fiókja; közvetlenül a beállított végpontokkal kommunikál.

## Fiók szerkesztése

Fiók szerkesztésekor a titkos kulcs rejtve van. Kattintson a **Mentett hitelesítő adatok felfedése** gombra, és erősítse meg Touch ID-val vagy a Mac jelszavával a megtekintéshez. Ha a titkos kulcs érintése nélkül ment, a tárolt kulcs változatlan marad.

## Bucketek és objektumok böngészése

- Kattintson egy fiókra az oldalsávban a bucketjei megjelenítéséhez.
- Egy bucket vagy mappa megnyitásához kattintson rá duplán. A visszalépéshez használja az útvonalsávot vagy a felfelé nyilat.
- Jelöljön ki egy fájlt a részletei és egy Gyors körbenézés előnézet megjelenítéséhez a jobb oldali panelen.
- A keresőmezővel szűrheti az aktuális mappát.

## Feltöltés és letöltés

- **Feltöltés**: kattintson a feltöltés gombra, vagy nyomja meg a **⌘U** billentyűkombinációt. Fájlokat a Finderből is behúzhat az objektumlistába vagy egy bucketre.
- **Letöltés**: kattintson jobb gombbal egy fájlra, és válassza a **Letöltés…** lehetőséget.
- A nagy fájlok párhuzamos részekben kerülnek átvitelre. A megszakadt feltöltés ott folytatódik, ahol abbamaradt.
- Minden átvitel megjelenik az oldalsáv **Átvitelek** részében a folyamat állapotával és egy megszakítás gombbal.
- A **Beállítások → Átvitelek** alatt korlátozhatja a teljes sávszélességet.

## Fájlok megnyitása más appokban

- Kattintson duplán egy fájlra, vagy kattintson rá jobb gombbal, és válassza a **Megnyitás** lehetőséget, hogy az alapértelmezett appban nyíljon meg. A **Megnyitás ezzel** további appokat sorol fel, amelyek meg tudják nyitni; az **Egyéb…** bármely app kiválasztását engedi.
- A Bucketeer letölti a fájlt egy ideiglenes mappába, és figyeli. Minden mentés után nem sokkal a fájl a szokásos átviteli soron át visszakerül a szerverre, így a kliensoldali titkosítás is érvényes.
- Ha az objektum a megnyitás után megváltozott vagy törölték a szerveren, a Bucketeer nem írja felül. Az Ön verziója mellé kerül fel „név (conflict dátum).kiterjesztés” néven, és a Bucketeer üzenetet jelenít meg.
- Az ideiglenes másolat törlődik, amint a szerveren megvan a legutóbbi mentése. Ha egy mentést nem sikerült feltölteni (például kapcsolat nélkül), a Bucketeer megtartja a fájlt ezen a Macen, és felajánlja a **Feltöltés újra**, a **Másolat mentése…** vagy a **Módosítás elvetése** lehetőséget – a következő indításkor is, például egy összeomlás után.

## Objektumok kezelése

- **Új mappa**: az eszközsor gombja vagy **⇧⌘N**.
- **Átnevezés…**: kattintson jobb gombbal egy objektumra. Az átnevezés egy szerveroldali másolás, amelyet törlés követ.
- **Törlés**: jelöljön ki egy vagy több objektumot, kattintson a kuka gombra, és erősítse meg.
- **Deep link másolása**: egy `bucketeer://` linket másol az objektumhoz, amely a Mac bármely pontjáról megnyitja azt a Bucketeerben.

## Megosztási linkek

Kattintson jobb gombbal egy fájlra, és válassza a **Megosztási link lekérése…** lehetőséget. Válassza ki, meddig legyen érvényes a link, majd másolja vagy ossza meg. A linket a Mac az Ön hitelesítő adataival írja alá; bárki, akinél megvan, letöltheti a fájlt, amíg a link le nem jár.

## Verziók

Kattintson jobb gombbal egy fájlra, és válassza a **Verziók megjelenítése…** lehetőséget a verzióelőzmények megtekintéséhez. Egy régebbi verziót visszaállíthat új legfrissebb példányként, vagy törölhet egyetlen verziót. Ehhez a bucketen engedélyezve kell lennie a verziókezelésnek a szolgáltatónál.

## Metaadatok és címkék

Kattintson jobb gombbal egy fájlra, és válassza a **Metaadatok és címkék…** lehetőséget a HTTP-fejlécek (tartalomtípus, cache control és mások), a felhasználói metaadatok és a címkék szerkesztéséhez, valamint a tárolási osztály megtekintéséhez. Nem minden szolgáltató támogat minden mezőt; a Bucketeer jelzi, ha ez a helyzet.

A **Beállítások → Szabályok** az automatikus címkézési szabályokat tartalmazza: ezek címkéket és metaadatokat adnak azokhoz az új feltöltésekhez, amelyek megfelelnek egy fájlnévmintának vagy MIME-típusnak.

## Bucket irányítópult

Kattintson az **Irányítópult** gombra egy megnyitott bucket eszközsorában. Megjeleníti az objektumok számát, a teljes méretet, a legnagyobb objektumokat, a havi költség durva becslését, valamint a bucket életciklus-szabályait, CORS-beállításait és bucket-szabályzatát (csak olvasható).

## Kuka

Objektumok törlésekor a Bucketeer megtarthat egy helyi másolatot ezen a Macen (**Beállítások → Átvitelek → Kuka**). Nyissa meg a kukát az **Ablak → Kuka** menüponttal (**⇧⌘⌫**), és kattintson a **Visszaállítás** gombra, hogy egy tárolt másolatot visszatöltsön az eredeti helyére. A szolgáltatónál lévő objektum azonnal törlődik; csak a helyi másolat állítható vissza. A bejegyzések a beállított megőrzési idő után automatikusan törlődnek.

## Tevékenységnapló

Az **Ablak → Tevékenységnapló** (**⌥⌘0**) felsorolja a feltöltéseket, letöltéseket, törléseket, szinkronizálási futásokat, megosztási linkeket és fiókváltozásokat. A listát szűrheti, kereshet benne, és exportálhatja CSV-ként. A bejegyzések 180 napig maradnak meg ezen a Macen.

## Ügyféloldali titkosítás

A **Beállítások → Titkosítás** alatt kulcsot hozhat létre egy buckethez. Ettől kezdve minden, abba a bucketbe történő feltöltés az Ön Macén titkosítódik (AES-256-GCM), mielőtt elhagyná azt, a letöltések pedig menet közben visszafejtődnek. A kulcs kizárólag ezen a Macen, a macOS-kulcskarikában tárolódik.

Fontos: ha elveszíti a kulcsot, senki sem tudja visszafejteni ezeket az objektumokat, mi sem. A titkosított bucketek a Bucketeer ezen verziójában nem csatolhatók a Finderbe.

## Spotlight

A **Beállítások → Átvitelek → Spotlight** alapértelmezés szerint ki van kapcsolva. Ha bekapcsolja, a böngészett objektumok nevei kereshetővé válnak a Spotlightban. A fájlok tartalma soha nem kerül indexelésre, és az index ezen a Macen marad.

## Parancsok és Siri

A Bucketeer műveleteket ad a Parancsok apphoz: bucketek listázása, fájl feltöltése, megosztási link létrehozása és szinkronizálási feladat futtatása. Használja őket a saját parancsaiban, vagy kérje meg Sirit.

## Pro funkciók

Ezekhez a funkciókhoz Bucketeer Pro szükséges:

- **Csatolás meghajtóként**: kattintson jobb gombbal egy bucketre, és válassza a **Csatolás meghajtóként** lehetőséget, hogy a Finderben lemezként használja. macOS 14.1 vagy újabb szükséges. A csatolt meghajtók az oldalsáv **Csatolt meghajtók** részében jelennek meg; jobb gombbal kattintva válassza a **Leválasztás** lehetőséget. Az ügyféloldali titkosítással rendelkező bucketek nem csatolhatók. A szerveren végzett módosítások akkor jelennek meg a Finderben, amikor frissíti a bucketet a Bucketeerben. Ha egy Finderben szerkesztett fájl közben megváltozott a szerveren, az Ön verziója mellé kerül ütközési másolatként.
- **Szinkronizálási feladatok**: a **Szinkronizálás** részben olyan feladatot hozhat létre, amely két bucket között másol, áthelyez vagy tükröz, fiókok és szolgáltatók között is, vagy egy helyi mappa és egy bucket között. Futtathatja kézzel, indításkor, N percenként vagy amikor a helyi mappa megváltozik.
- **Figyelt mappák**: az **Új figyelt mappa…** egy helyi mappa minden új fájlját feltölti egy bucketbe.
- **Másolás másik fiókba…**: objektumokat másol egy másik fiókba vagy szolgáltatóhoz. Ha mindkét oldal engedi, a másolás szerveroldalon fut, és az adatok nem haladnak át az Ön Macén.
- **Menüsor mód**: a **Beállítások → Általános** alatt a Bucketeer a menüsorban fut tovább, így a meghajtók és a szinkronizálási feladatok aktívak maradnak a főablak bezárása után is.

Minden más elérhető az ingyenes verzióban.

## Bucketeer Pro, próbaidőszak és vásárlás

A Bucketeer Pro egyszeri, alkalmazáson belüli vásárlás az App Store-on keresztül, előfizetés nélkül. Nyissa meg a **Beállítások → Pro** lapot vagy bármelyik Pro funkciót, hogy lássa az árat a saját pénznemében, és megvásárolja.

A Bucketeer Pro 14 napig ingyen kipróbálható. Indítás előtt a vásárlási oldal mutatja a próbaidőszak hosszát, azt, hogy mi történik utána, és a Pro örök licenc árát; ezután kattintson a **Próbaidőszak indítása** gombra. A próbaidőszak végén a Bucketeer az ingyenes verzióval működik tovább, és semmit sem kell fizetni. A próbaidőszak Apple ID-nként egyszer indítható, a vásárlások visszaállítása pedig egy futó próbaidőszakot egy másik Macen is visszahoz.

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

A Bucketeer nem gyűjt elemzési adatokat, és nem tartalmaz követést. A fiókjai, kulcsai és naplói ezen a Macen maradnak. A hálózati forgalom csak az Ön által beállított tárhelyszolgáltatókhoz, vásárláskor pedig az Apple-höz irányul. Részletek: **Súgó → Adatvédelmi irányelvek…**

## Segítségre van szüksége?

- Hiba bejelentése: **Súgó → Hiba bejelentése…** vagy <https://support.apps.digitalfreedom.co.za/>
- Weboldal: <https://digitalfreedom.co.za>
