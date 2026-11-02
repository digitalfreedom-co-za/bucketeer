# Bucketeer Hjälp

Bucketeer är en Mac-app för objektlagring: Amazon S3, S3-kompatibla leverantörer och Azure Blob Storage. Den här guiden går igenom alla funktioner, från det första kontot till Finder-enheter och synkjobb.

## Lägg till ett konto

- Klicka på **+** överst i sidofältet.
- Välj en leverantör: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj eller Custom (MinIO och alla andra S3-kompatibla slutpunkter).
- Ange ett namn, regionen eller slutpunkten och dina inloggningsuppgifter (åtkomstnyckel och hemlig nyckel; för Azure lagringskontots nyckel).
- Klicka på **Testa anslutning** och sedan på **Spara**.

Dina inloggningsuppgifter sparas i macOS-nyckelringen på den här datorn. Bucketeer har ingen server och inget användarkonto; appen kommunicerar direkt med de slutpunkter du konfigurerar.

## Redigera ett konto

Den hemliga nyckeln är dold när du redigerar ett konto. Klicka på **Visa sparade inloggningsuppgifter** och bekräfta med Touch ID eller ditt Mac-lösenord för att se den. Om du sparar utan att röra den hemliga nyckeln förblir den sparade oförändrad.

## Bläddra bland buckets och objekt

- Klicka på ett konto i sidofältet för att visa dess buckets.
- Dubbelklicka på en bucket eller mapp för att öppna den. Använd sökvägsfältet eller uppåtpilen för att gå tillbaka.
- Markera en fil för att se dess information och en Snabbtitt-förhandsvisning i den högra panelen.
- Använd sökfältet för att filtrera den aktuella mappen.

## Ladda upp och hämta

- **Ladda upp**: klicka på uppladdningsknappen eller tryck på **⌘U**. Du kan också dra filer från Finder till objektlistan eller till en bucket.
- **Hämta**: högerklicka på en fil och välj **Hämta…**.
- Stora filer överförs i parallella delar. En avbruten uppladdning fortsätter där den stannade.
- Alla överföringar visas under **Överföringar** i sidofältet med förlopp och en avbryt-knapp.
- Under **Inställningar → Överföringar** kan du begränsa den totala bandbredden.

## Öppna filer i andra appar

- Dubbelklicka på en fil, eller högerklicka och välj **Öppna**, för att öppna den i standardappen. **Öppna med** visar andra appar som kan öppna den; med **Annat …** väljer du valfri app.
- Bucketeer hämtar filen till en tillfällig mapp och bevakar den. Strax efter varje sparning laddas filen upp igen via den vanliga överföringskön, så klientsidig kryptering gäller även här.
- Om objektet ändrades eller raderades på servern efter att du öppnade det skriver Bucketeer inte över det. Din version laddas upp bredvid som ”namn (conflict datum).filändelse” och Bucketeer visar ett meddelande.
- Den tillfälliga kopian raderas när du avslutar appen du redigerade i, när du avslutar Bucketeer eller vid nästa start.

## Hantera objekt

- **Ny mapp**: knappen i verktygsfältet eller **⇧⌘N**.
- **Byt namn…**: högerklicka på ett objekt. Ett namnbyte är en kopia på servern följd av en radering.
- **Radera**: markera ett eller flera objekt, klicka på papperskorgsknappen och bekräfta.
- **Kopiera djuplänk**: kopierar en `bucketeer://`-länk till objektet som öppnar det i Bucketeer var som helst på din Mac.

## Delningslänkar

Högerklicka på en fil och välj **Hämta delningslänk…**. Välj hur länge länken ska gälla och kopiera eller dela den. Länken signeras på din Mac med dina inloggningsuppgifter; alla som har den kan hämta filen tills den löper ut.

## Versioner

Högerklicka på en fil och välj **Visa versioner…** för att se versionshistoriken. Du kan återställa en äldre version som ny aktuell kopia eller radera en enskild version. Versionshantering måste vara aktiverad för bucketen hos leverantören.

## Metadata och taggar

Högerklicka på en fil och välj **Metadata och taggar…** för att redigera HTTP-rubriker (innehållstyp, cache control med flera), användarmetadata och taggar samt för att se lagringsklassen. Alla leverantörer stöder inte alla fält; Bucketeer talar om när så är fallet.

**Inställningar → Regler** innehåller regler för automatisk taggning: de lägger till taggar och metadata på nya uppladdningar som matchar ett filnamnsmönster eller en MIME-typ.

## Bucket-översikt

Klicka på **Översikt** i verktygsfältet för en öppen bucket. Den visar antal objekt, total storlek, de största objekten, en grov uppskattning av månadskostnaden samt bucketens livscykelregler, CORS-konfiguration och bucket-policy (skrivskyddat).

## Papperskorg

När du raderar objekt kan Bucketeer spara en lokal kopia på den här datorn (**Inställningar → Överföringar → Papperskorg**). Öppna papperskorgen med **Fönster → Papperskorg** (**⇧⌘⌫**) och klicka på **Återställ** för att ladda upp en sparad kopia till dess ursprungliga plats. Objektet hos leverantören raderas direkt; bara den lokala kopian kan återställas. Poster tas bort automatiskt efter den lagringstid du har valt.

## Aktivitetslogg

**Fönster → Aktivitetslogg** (**⌥⌘0**) listar uppladdningar, hämtningar, raderingar, synkkörningar, delningslänkar och kontoändringar. Du kan filtrera, söka och exportera listan som CSV. Posterna sparas på den här datorn i 180 dagar.

## Kryptering på klientsidan

Under **Inställningar → Kryptering** kan du skapa en nyckel för en bucket. Från och med då krypteras varje uppladdning till den bucketen på din Mac (AES-256-GCM) innan den skickas, och hämtningar dekrypteras direkt. Nyckeln sparas endast i macOS-nyckelringen på den här datorn.

Viktigt: om du förlorar nyckeln kan ingen dekryptera objekten, inte heller vi. Krypterade buckets kan inte monteras i Finder i den här versionen av Bucketeer.

## Spotlight

**Inställningar → Överföringar → Spotlight** är avstängt som standard. När du slår på det blir namnen på objekt du bläddrar bland sökbara i Spotlight. Filinnehåll indexeras aldrig, och indexet stannar på den här datorn.

## Genvägar och Siri

Bucketeer lägger till åtgärder i appen Genvägar: lista buckets, ladda upp en fil, skapa en delningslänk och köra ett synkjobb. Använd dem i dina egna genvägar eller fråga Siri.

## Pro-funktioner

Dessa funktioner kräver Bucketeer Pro:

- **Montera som enhet**: högerklicka på en bucket och välj **Montera som enhet** för att använda den i Finder som en disk. Kräver macOS 14.1 eller senare. Monterade enheter visas under **Monterade enheter** i sidofältet; högerklicka för att **Avmontera**. Buckets med kryptering på klientsidan kan inte monteras. Ändringar på servern visas i Finder när du uppdaterar bucketen i Bucketeer. Om en fil som du redigerar i Finder har ändrats på servern under tiden sparas din version bredvid som en konfliktkopia.
- **Synkjobb**: i avsnittet **Synkronisering** skapar du ett jobb som kopierar, flyttar eller speglar mellan två buckets, mellan konton och leverantörer, eller mellan en lokal mapp och en bucket. Kör det manuellt, vid start, var N:e minut eller när den lokala mappen ändras.
- **Bevakade mappar**: **Ny bevakad mapp…** laddar upp varje ny fil i en lokal mapp till en bucket.
- **Kopiera till annat konto…**: kopierar objekt till ett annat konto eller en annan leverantör. När båda sidor tillåter det sker kopieringen på servern och data passerar inte genom din Mac.
- **Menyradsläge**: **Inställningar → Allmänt** håller Bucketeer igång i menyraden så att enheter och synkjobb förblir aktiva när huvudfönstret är stängt.

Allt annat finns i Free-nivån.

## Bucketeer Pro, provperiod och köp

Bucketeer Pro är ett engångsköp i appen via App Store, utan prenumeration. Öppna **Inställningar → Pro** eller en Pro-funktion för att se priset i din valuta och köpa.

Du kan prova Bucketeer Pro gratis i 14 dagar. Innan du startar visar köpsidan provperiodens längd, vad som händer efteråt och priset för Pro Livstid; klicka sedan på **Starta provperiod**. När provperioden är slut fortsätter Bucketeer i gratisversionen och inget debiteras. Provperioden kan startas en gång per Apple-ID, och när du återställer köp kommer en pågående provperiod tillbaka även på en annan Mac.

- **Återställ köp** ger dig Pro igen på en annan Mac eller efter en ominstallation.
- **Lös in kod** (macOS 15 eller senare) öppnar Apples fönster för erbjudandekoder.

## Kortkommandon

- **⌘U**: Ladda upp filer
- **⇧⌘N**: Ny mapp
- **⌥⌘0**: Aktivitetslogg
- **⇧⌘⌫**: Papperskorg
- **⌘?**: Bucketeer Hjälp
- **⌘,**: Inställningar

## Integritet

Bucketeer samlar inte in analysdata och innehåller ingen spårning. Dina konton, nycklar och loggar stannar på den här datorn. Nätverkstrafik går bara till de lagringsleverantörer du konfigurerar och till Apple vid köp. Mer information: **Hjälp → Integritetspolicy…**

## Behöver du hjälp?

- Rapportera ett problem: **Hjälp → Rapportera ett problem…** eller <https://support.apps.digitalfreedom.co.za/>
- Webbplats: <https://digitalfreedom.co.za>
