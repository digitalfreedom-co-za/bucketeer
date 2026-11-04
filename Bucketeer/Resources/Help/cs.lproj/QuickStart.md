# Nápověda Bucketeer

Bucketeer je aplikace pro Mac pro objektová úložiště: Amazon S3, poskytovatele kompatibilní s S3 a Azure Blob Storage. Tento průvodce popisuje všechny funkce, od prvního účtu po disky ve Finderu a synchronizační úlohy.

## Přidání účtu

- Klikněte na **+** v záhlaví postranního panelu.
- Vyberte poskytovatele: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj nebo Custom (MinIO a jakýkoli jiný koncový bod kompatibilní s S3).
- Zadejte název, region nebo koncový bod a své přihlašovací údaje (přístupový klíč a tajný klíč; u Azure klíč účtu úložiště).
- Pokud má váš klíč přístup jen k jednomu bucketu (u Civo běžné), zadejte jeho název do pole **Bucket**; účet pak zobrazí jen tento bucket. Klíče Civo fungují jen v oblasti, ve které byly vytvořeny.
- Klikněte na **Otestovat připojení** a potom na **Uložit**.

Vaše přihlašovací údaje se ukládají do klíčenky macOS na tomto Macu. Bucketeer nemá žádný server ani uživatelský účet; komunikuje přímo s koncovými body, které nastavíte.

## Úprava účtu

Při úpravě účtu je tajný klíč skrytý. Klikněte na **Zobrazit uložené přihlašovací údaje** a potvrďte pomocí Touch ID nebo hesla k Macu, abyste ho viděli. Pokud uložíte, aniž byste tajný klíč změnili, uložený klíč zůstane beze změny.

## Procházení bucketů a objektů

- Klikněte na účet v postranním panelu, zobrazí se jeho buckety.
- Dvojitým kliknutím otevřete bucket nebo složku. Zpět se dostanete pomocí navigační lišty nebo šipky nahoru.
- Vyberte soubor a v pravém panelu uvidíte jeho podrobnosti a náhled Quick Look.
- Pole hledání filtruje aktuální složku.

## Nahrávání a stahování

- **Nahrát**: klikněte na tlačítko nahrávání nebo stiskněte **⌘U**. Soubory můžete také přetáhnout z Finderu do seznamu objektů nebo na bucket.
- **Stáhnout**: klikněte na soubor pravým tlačítkem a vyberte **Stáhnout…**.
- Velké soubory se přenášejí v paralelních částech. Přerušené nahrávání pokračuje tam, kde se zastavilo.
- Všechny přenosy se zobrazují v sekci **Přenosy** v postranním panelu s průběhem a tlačítkem pro zrušení.
- V **Nastavení → Přenosy** můžete omezit celkovou šířku pásma.

## Otevírání souborů v jiných aplikacích

- Dvakrát klikněte na soubor nebo na něj klikněte pravým tlačítkem a zvolte **Otevřít**; otevře se ve výchozí aplikaci. **Otevřít v aplikaci** nabízí další aplikace, které ho umí otevřít; **Jiná…** umožní vybrat libovolnou aplikaci.
- Bucketeer soubor stáhne do dočasné složky a sleduje ho. Chvíli po každém uložení se soubor nahraje zpět přes běžnou frontu přenosů, takže platí i šifrování na straně klienta.
- Pokud se objekt po otevření na serveru změnil nebo byl smazán, Bucketeer ho nepřepíše. Vaše verze se nahraje vedle něj jako „název (conflict datum).přípona“ a Bucketeer zobrazí zprávu.
- Dočasná kopie se smaže, jakmile má server vaše poslední uložení. Pokud se uložení nepodařilo nahrát (například bez připojení), Bucketeer soubor ponechá v tomto Macu a nabídne **Nahrát znovu**, **Uložit kopii…** nebo **Zahodit úpravu** — také při dalším spuštění, například po pádu aplikace.

## Správa objektů

- **Nová složka**: tlačítko na panelu nástrojů nebo **⇧⌘N**.
- **Přejmenovat…**: klikněte na objekt pravým tlačítkem. Přejmenování je kopie na straně serveru, po které následuje smazání. Přejmenování nebo smazání složky se týká všeho, co obsahuje, a přejmenování nikdy nenahradí existující název.
- **Smazat**: vyberte jeden nebo více objektů, klikněte na tlačítko koše a potvrďte.
- **Kopírovat deep link**: zkopíruje odkaz `bucketeer://` na objekt, který ho odkudkoli na vašem Macu otevře v aplikaci Bucketeer.

## Odkazy ke sdílení

Klikněte na soubor pravým tlačítkem a vyberte **Získat odkaz ke sdílení…**. Zvolte, jak dlouho má odkaz platit, a potom ho zkopírujte nebo sdílejte. Odkaz se podepisuje na vašem Macu vašimi přihlašovacími údaji; kdokoli, kdo ho má, může soubor stáhnout, dokud platnost odkazu nevyprší.

## Verze

Klikněte na soubor pravým tlačítkem a vyberte **Zobrazit verze…**, zobrazí se historie jeho verzí. Starší verzi můžete obnovit jako novou nejnovější kopii nebo smazat jednotlivou verzi. Bucket musí mít u poskytovatele zapnuté verzování.

## Metadata a štítky

Klikněte na soubor pravým tlačítkem a vyberte **Metadata a štítky…**. Můžete upravit hlavičky HTTP (typ obsahu, řízení mezipaměti a další), uživatelská metadata a štítky a zobrazit třídu úložiště. Někteří poskytovatelé nepodporují všechna pole; Bucketeer vás na to upozorní.

**Nastavení → Pravidla** obsahuje pravidla automatického štítkování: přidávají štítky a metadata k novým nahraným souborům, které odpovídají vzoru názvu souboru nebo typu MIME.

## Přehled bucketu

Klikněte na **Přehled** na panelu nástrojů otevřeného bucketu. Zobrazí se počet objektů, celková velikost, největší objekty, přibližný odhad měsíčních nákladů a pravidla životního cyklu, konfigurace CORS a zásady bucketu (pouze pro čtení).

## Koš

Když mažete objekty, Bucketeer může ponechat místní kopii na tomto Macu (**Nastavení → Přenosy → Koš**). Koš otevřete pomocí **Okno → Koš** (**⇧⌘⌫**) a kliknutím na **Obnovit** nahrajete kopii z mezipaměti zpět na její původní místo. Objekt u poskytovatele se smaže okamžitě; obnovit lze pouze místní kopii. Položky se automaticky odstraní po uplynutí doby uchování, kterou nastavíte.

## Protokol aktivity

**Okno → Protokol aktivity** (**⌥⌘0**) zobrazuje nahrávání, stahování, mazání, běhy synchronizace, odkazy ke sdílení a změny účtů. Seznam můžete filtrovat, prohledávat a exportovat jako CSV. Záznamy se na tomto Macu uchovávají 180 dní.

## Šifrování na straně klienta

V **Nastavení → Šifrování** můžete pro bucket vytvořit klíč. Od té chvíle se každý soubor nahrávaný do tohoto bucketu zašifruje na vašem Macu (AES-256-GCM) dříve, než ho opustí, a stahované soubory se průběžně dešifrují. Klíč se ukládá do klíčenky macOS pouze na tomto Macu.

Důležité: pokud klíč ztratíte, nikdo tyto objekty nedešifruje, ani my. Zašifrované buckety nelze v této verzi aplikace Bucketeer připojit ve Finderu.

## Spotlight

**Nastavení → Přenosy → Spotlight** je ve výchozím stavu vypnuté. Když ho zapnete, názvy objektů, které procházíte, budou vyhledatelné ve Spotlightu. Obsah souborů se nikdy neindexuje a index zůstává na tomto Macu.

## Zkratky a Siri

Bucketeer přidává do aplikace Zkratky akce: výpis bucketů, nahrání souboru, vytvoření odkazu ke sdílení a spuštění synchronizační úlohy. Použijte je ve vlastních zkratkách nebo požádejte Siri.

## Funkce Pro

Tyto funkce vyžadují Bucketeer Pro:

- **Připojit jako disk**: klikněte na bucket pravým tlačítkem a vyberte **Připojit jako disk**, abyste ho mohli používat ve Finderu jako disk. Připojené disky se zobrazují v sekci **Připojené disky** v postranním panelu; odpojíte je kliknutím pravým tlačítkem a volbou **Odpojit**. Buckety se šifrováním na straně klienta nelze připojit. Změny na serveru se ve Finderu objeví, když bucket v Bucketeeru obnovíte. Pokud se soubor, který upravujete ve Finderu, mezitím na serveru změnil, vaše verze se uloží vedle něj jako konfliktní kopie.
- **Synchronizační úlohy**: v sekci **Synchronizace** vytvořte úlohu, která kopíruje, přesouvá nebo zrcadlí mezi dvěma buckety, napříč účty a poskytovateli, nebo mezi místní složkou a bucketem. Spouštějte ji ručně, při spuštění aplikace, každých N minut nebo při změně místní složky.
- **Sledované složky**: **Nová sledovaná složka…** nahraje každý nový soubor z místní složky do bucketu.
- **Kopírovat do jiného účtu…**: zkopíruje objekty do jiného účtu nebo k jinému poskytovateli. Pokud to obě strany umožňují, kopie probíhá na straně serveru a data neprocházejí vaším Macem.
- **Režim řádku nabídek**: **Nastavení → Obecné** nechá Bucketeer běžet v řádku nabídek, takže disky a synchronizační úlohy zůstanou aktivní i po zavření hlavního okna.

Vše ostatní je k dispozici v bezplatné verzi.

## Bucketeer Pro, zkušební verze a nákup

Bucketeer Pro je jednorázový nákup v aplikaci přes App Store, bez předplatného. Otevřete **Nastavení → Pro** nebo kteroukoli funkci Pro, zobrazí se cena ve vaší měně a můžete nakoupit.

Bucketeer Pro si můžete 14 dní zdarma vyzkoušet. Před spuštěním ukáže nabídka délku zkušební verze, co se stane potom a cenu Pro doživotně; pak klikněte na **Spustit zkušební verzi**. Po skončení zkušební verze Bucketeer pokračuje v bezplatné verzi a nic se neúčtuje. Zkušební verzi lze spustit jednou na Apple ID a obnovení nákupů vrátí běžící zkušební verzi i na jiném Macu.

- **Obnovit nákup** obnoví Pro na jiném Macu nebo po přeinstalaci.
- **Uplatnit kód** otevře dialog Apple pro kódy nabídek.

## Klávesové zkratky

- **⌘U**: Nahrát soubory
- **⇧⌘N**: Nová složka
- **⌥⌘0**: Protokol aktivity
- **⇧⌘⌫**: Koš
- **⌘?**: Nápověda Bucketeer
- **⌘,**: Nastavení

## Soukromí

Bucketeer neshromažďuje analytická data a neobsahuje žádné sledování. Vaše účty, klíče a protokoly zůstávají na tomto Macu. Síťový provoz směřuje pouze k poskytovatelům úložiště, které nastavíte, a ke společnosti Apple kvůli nákupům. Podrobnosti: **Nápověda → Zásady ochrany soukromí…**

## Potřebujete pomoc?

- Nahlásit problém: **Nápověda → Nahlásit problém…** nebo <https://support.apps.digitalfreedom.co.za/>
- Web: <https://digitalfreedom.co.za>
