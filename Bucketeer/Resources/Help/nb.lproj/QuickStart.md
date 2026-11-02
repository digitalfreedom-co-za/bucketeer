# Bucketeer-hjelp

Bucketeer er en Mac-app for objektlagring: Amazon S3, S3-kompatible leverandører og Azure Blob Storage. Denne veiledningen går gjennom alle funksjoner, fra den første kontoen til Finder-disker og synkroniseringsjobber.

## Legg til en konto

- Klikk på **+** øverst i sidepanelet.
- Velg en leverandør: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj eller Custom (MinIO og alle andre S3-kompatible endepunkter).
- Skriv inn et navn, regionen eller endepunktet og påloggingsinformasjonen din (tilgangsnøkkel og hemmelig nøkkel; for Azure lagringskontonøkkelen).
- Klikk på **Test tilkobling** og deretter på **Lagre**.

Påloggingsinformasjonen din lagres i macOS-nøkkelringen på denne Macen. Bucketeer har ingen server og ingen brukerkonto; appen kommuniserer direkte med endepunktene du konfigurerer.

## Rediger en konto

Den hemmelige nøkkelen er skjult når du redigerer en konto. Klikk på **Vis lagret påloggingsinformasjon** og bekreft med Touch ID eller Mac-passordet ditt for å se den. Lagrer du uten å røre den hemmelige nøkkelen, forblir den lagrede uendret.

## Bla gjennom buckets og objekter

- Klikk på en konto i sidepanelet for å vise bucketene.
- Dobbeltklikk på en bucket eller mappe for å åpne den. Bruk banelinjen eller pil opp for å gå tilbake.
- Marker en fil for å se detaljene og en Quick Look-forhåndsvisning i høyre rute.
- Bruk søkefeltet for å filtrere gjeldende mappe.

## Last opp og last ned

- **Last opp**: klikk på opplastingsknappen eller trykk **⌘U**. Du kan også dra filer fra Finder til objektlisten eller til en bucket.
- **Last ned**: høyreklikk på en fil og velg **Last ned…**.
- Store filer overføres i parallelle deler. En avbrutt opplasting fortsetter der den stoppet.
- Alle overføringer vises under **Overføringer** i sidepanelet med fremdrift og en avbryt-knapp.
- Under **Innstillinger → Overføringer** kan du begrense den totale båndbredden.

## Administrer objekter

- **Ny mappe**: knappen i verktøylinjen eller **⇧⌘N**.
- **Gi nytt navn…**: høyreklikk på et objekt. Et navnebytte er en kopi på serveren etterfulgt av en sletting.
- **Slett**: marker ett eller flere objekter, klikk på papirkurv-knappen og bekreft.
- **Kopier dyplenke**: kopierer en `bucketeer://`-lenke til objektet som åpner det i Bucketeer fra hvor som helst på Macen.

## Delingslenker

Høyreklikk på en fil og velg **Hent delingslenke…**. Velg hvor lenge lenken skal være gyldig, og kopier eller del den. Lenken signeres på Macen din med påloggingsinformasjonen din; alle som har den kan laste ned filen til den utløper.

## Versjoner

Høyreklikk på en fil og velg **Vis versjoner…** for å se versjonshistorikken. Du kan gjenopprette en eldre versjon som ny gjeldende kopi eller slette en enkelt versjon. Versjonering må være slått på for bucketen hos leverandøren.

## Metadata og tagger

Høyreklikk på en fil og velg **Metadata og tagger…** for å redigere HTTP-hoder (innholdstype, cache control og andre), brukermetadata og tagger, og for å se lagringsklassen. Ikke alle leverandører støtter alle felt; Bucketeer sier fra når det er tilfellet.

**Innstillinger → Regler** inneholder regler for automatisk tagging: de legger til tagger og metadata på nye opplastinger som samsvarer med et filnavnmønster eller en MIME-type.

## Bucket-dashbord

Klikk på **Dashbord** i verktøylinjen til en åpen bucket. Det viser antall objekter, total størrelse, de største objektene, et grovt anslag over månedlige kostnader og bucketens livssyklusregler, CORS-konfigurasjon og bucket-policy (skrivebeskyttet).

## Papirkurv

Når du sletter objekter, kan Bucketeer beholde en lokal kopi på denne Macen (**Innstillinger → Overføringer → Papirkurv**). Åpne papirkurven med **Vindu → Papirkurv** (**⇧⌘⌫**) og klikk på **Gjenopprett** for å laste opp en lagret kopi til den opprinnelige plasseringen. Objektet hos leverandøren slettes med en gang; bare den lokale kopien kan gjenopprettes. Oppføringer fjernes automatisk etter lagringstiden du har valgt.

## Aktivitetslogg

**Vindu → Aktivitetslogg** (**⌥⌘0**) viser opplastinger, nedlastinger, slettinger, synkroniseringskjøringer, delingslenker og kontoendringer. Du kan filtrere, søke og eksportere listen som CSV. Oppføringene lagres på denne Macen i 180 dager.

## Kryptering på klientsiden

Under **Innstillinger → Kryptering** kan du opprette en nøkkel for en bucket. Fra da av krypteres hver opplasting til den bucketen på Macen din (AES-256-GCM) før den sendes, og nedlastinger dekrypteres underveis. Nøkkelen lagres bare i macOS-nøkkelringen på denne Macen.

Viktig: Mister du nøkkelen, kan ingen dekryptere disse objektene, heller ikke vi. Krypterte buckets kan ikke monteres i Finder i denne versjonen av Bucketeer.

## Spotlight

**Innstillinger → Overføringer → Spotlight** er slått av som standard. Når du slår det på, blir navnene på objektene du blar gjennom, søkbare i Spotlight. Filinnhold indekseres aldri, og indeksen blir på denne Macen.

## Snarveier og Siri

Bucketeer legger til handlinger i Snarveier-appen: vis buckets, last opp en fil, opprett en delingslenke og kjør en synkroniseringsjobb. Bruk dem i dine egne snarveier eller spør Siri.

## Pro-funksjoner

Disse funksjonene krever Bucketeer Pro:

- **Monter som disk**: høyreklikk på en bucket og velg **Monter som disk** for å bruke den i Finder som en disk. Krever macOS 14.1 eller nyere. Monterte disker vises under **Monterte disker** i sidepanelet; høyreklikk for å **Avmonter**. Buckets med kryptering på klientsiden kan ikke monteres.
- **Synkroniseringsjobber**: i delen **Synkronisering** oppretter du en jobb som kopierer, flytter eller speiler mellom to buckets, på tvers av kontoer og leverandører, eller mellom en lokal mappe og en bucket. Kjør den manuelt, ved oppstart, hvert N. minutt eller når den lokale mappen endres.
- **Overvåkede mapper**: **Ny overvåket mappe…** laster opp hver nye fil i en lokal mappe til en bucket.
- **Kopier til annen konto…**: kopierer objekter til en annen konto eller leverandør. Når begge sider tillater det, skjer kopieringen på serveren, og dataene går ikke gjennom Macen din.
- **Menylinjemodus**: **Innstillinger → Generelt** holder Bucketeer i gang i menylinjen, slik at disker og synkroniseringsjobber forblir aktive når hovedvinduet er lukket.

Alt annet er tilgjengelig i Free-nivået.

## Bucketeer Pro, prøveperiode og kjøp

Bucketeer Pro er et engangskjøp i appen via App Store, uten abonnement. Åpne **Innstillinger → Pro** eller en Pro-funksjon for å se prisen i din valuta og kjøpe.

Hvis det tilbys en prøveperiode for ditt eksemplar, viser betalingsvinduet og **Innstillinger → Pro** hvor lenge den varer. Når den er over, fortsetter Bucketeer på Free-nivået, og ingenting belastes.

- **Gjenopprett kjøp** gir deg Pro tilbake på en annen Mac eller etter en ny installasjon.
- **Løs inn kode** (macOS 15 eller nyere) åpner Apples vindu for tilbudskoder.

## Tastatursnarveier

- **⌘U**: Last opp filer
- **⇧⌘N**: Ny mappe
- **⌥⌘0**: Aktivitetslogg
- **⇧⌘⌫**: Papirkurv
- **⌘?**: Bucketeer-hjelp
- **⌘,**: Innstillinger

## Personvern

Bucketeer samler ikke inn analysedata og inneholder ingen sporing. Kontoene, nøklene og loggene dine blir på denne Macen. Nettverkstrafikk går bare til lagringsleverandørene du konfigurerer, og til Apple ved kjøp. Detaljer: **Hjelp → Personvernerklæring…**

## Trenger du hjelp?

- Rapporter et problem: **Hjelp → Rapporter et problem…** eller <https://support.apps.digitalfreedom.co.za/>
- Nettsted: <https://digitalfreedom.co.za>
