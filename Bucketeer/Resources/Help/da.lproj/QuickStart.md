# Bucketeer-hjælp

Bucketeer er en Mac-app til objektlagring: Amazon S3, S3-kompatible udbydere og Azure Blob Storage. Denne vejledning gennemgår alle funktioner, fra den første konto til Finder-drev og synkroniseringsjob.

## Tilføj en konto

- Klik på **+** øverst i sidepanelet.
- Vælg en udbyder: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj eller Custom (MinIO og alle andre S3-kompatible endpoints).
- Angiv et navn, regionen eller endpointet og dine adgangsoplysninger (adgangsnøgle og hemmelig nøgle; for Azure lagerkontonøglen).
- Hvis din nøgle kun har adgang til én bucket (almindeligt hos Civo), så indtast dens navn under **Bucket**; kontoen viser så kun den bucket. Civo-nøgler virker kun i den region, de blev oprettet i.
- Klik på **Test forbindelse** og derefter på **Gem**.

Dine adgangsoplysninger gemmes i macOS-nøgleringen på denne Mac. Bucketeer har ingen server og ingen brugerkonto; appen taler direkte med de endpoints, du konfigurerer.

## Redigér en konto

Den hemmelige nøgle er skjult, når du redigerer en konto. Klik på **Vis gemte adgangsoplysninger**, og bekræft med Touch ID eller din Mac-adgangskode for at se den. Gemmer du uden at røre den hemmelige nøgle, forbliver den gemte uændret.

## Gennemse buckets og objekter

- Klik på en konto i sidepanelet for at se dens buckets.
- Dobbeltklik på en bucket eller mappe for at åbne den. Brug stien øverst eller pil op for at gå tilbage.
- Vælg en fil for at se dens detaljer og et Quick Look-eksempel i højre rude.
- Brug søgefeltet til at filtrere den aktuelle mappe.

## Upload og download

- **Upload**: klik på upload-knappen, eller tryk på **⌘U**. Du kan også trække filer fra Finder ind i objektlisten eller over på en bucket.
- **Download**: højreklik på en fil, og vælg **Download…**.
- Store filer overføres i parallelle dele. En afbrudt upload fortsætter, hvor den stoppede.
- Alle overførsler vises under **Overførsler** i sidepanelet med fremskridt og en annullér-knap.
- Under **Indstillinger → Overførsler** kan du begrænse den samlede båndbredde.

## Åbn filer i andre apps

- Dobbeltklik på en fil, eller højreklik og vælg **Åbn**, for at åbne den i standardappen. **Åbn med** viser andre apps, der kan åbne den; med **Andet…** kan du vælge en vilkårlig app.
- Bucketeer henter filen til en midlertidig mappe og holder øje med den. Kort efter hver gemning uploades filen igen via den normale overførselskø, så klientsidekryptering også gælder her.
- Hvis objektet blev ændret eller slettet på serveren, efter du åbnede det, overskriver Bucketeer det ikke. Din version uploades ved siden af som "navn (conflict dato).endelse", og Bucketeer viser en besked.
- Den midlertidige kopi slettes, så snart serveren har din seneste lagring. Hvis en lagring ikke kunne uploades (f.eks. offline), beholder Bucketeer filen på denne Mac og tilbyder **Upload igen**, **Gem en kopi…** eller **Kassér ændring** — også ved næste start, f.eks. efter et nedbrud.

## Administrér objekter

- **Ny mappe**: knappen i værktøjslinjen eller **⇧⌘N**.
- **Omdøb…**: højreklik på et objekt. En omdøbning er en kopi på serveren efterfulgt af en sletning. Omdøbning eller sletning af en mappe gælder alt i den, og en omdøbning erstatter aldrig et eksisterende navn.
- **Slet**: vælg et eller flere objekter, klik på papirkurv-knappen, og bekræft.
- **Kopiér deeplink**: kopierer et `bucketeer://`-link til objektet, som åbner det i Bucketeer hvor som helst på din Mac.

## Delingslinks

Højreklik på en fil, og vælg **Hent delingslink…**. Vælg, hvor længe linket skal være gyldigt, og kopiér eller del det. Linket signeres på din Mac med dine adgangsoplysninger; alle, der har det, kan downloade filen, indtil det udløber.

## Versioner

Højreklik på en fil, og vælg **Vis versioner…** for at se dens versionshistorik. Du kan gendanne en ældre version som den nye aktuelle kopi eller slette en enkelt version. Versionering skal være slået til for bucketen hos udbyderen.

## Metadata og tags

Højreklik på en fil, og vælg **Metadata og tags…** for at redigere HTTP-headere (indholdstype, cache control m.fl.), brugermetadata og tags og for at se lagerklassen. Ikke alle udbydere understøtter alle felter; Bucketeer fortæller dig, når det er tilfældet.

**Indstillinger → Regler** indeholder regler for automatisk tagging: de tilføjer tags og metadata til nye uploads, der matcher et filnavnsmønster eller en MIME-type.

## Bucket-dashboard

Klik på **Dashboard** i værktøjslinjen i en åben bucket. Det viser antal objekter, samlet størrelse, de største objekter, et groft skøn over de månedlige omkostninger samt bucketens livscyklusregler, CORS-konfiguration og bucket-politik (skrivebeskyttet).

## Papirkurv

Når du sletter objekter, kan Bucketeer beholde en lokal kopi på denne Mac (**Indstillinger → Overførsler → Papirkurv**). Åbn papirkurven med **Vindue → Papirkurv** (**⇧⌘⌫**), og klik på **Gendan** for at uploade en gemt kopi tilbage til dens oprindelige placering. Objektet hos udbyderen slettes med det samme; kun den lokale kopi kan gendannes. Poster fjernes automatisk efter den opbevaringsperiode, du har valgt.

## Aktivitetslog

**Vindue → Aktivitetslog** (**⌥⌘0**) viser uploads, downloads, sletninger, synkroniseringskørsler, delingslinks og kontoændringer. Du kan filtrere, søge og eksportere listen som CSV. Posterne gemmes på denne Mac i 180 dage.

## Kryptering på klientsiden

Under **Indstillinger → Kryptering** kan du oprette en nøgle til en bucket. Fra da af krypteres hver upload til den bucket på din Mac (AES-256-GCM), før den sendes, og downloads dekrypteres undervejs. Nøglen gemmes kun i macOS-nøgleringen på denne Mac.

Vigtigt: Mister du nøglen, kan ingen dekryptere disse objekter, heller ikke vi. Krypterede buckets kan ikke monteres i Finder i denne version af Bucketeer.

## Spotlight

**Indstillinger → Overførsler → Spotlight** er slået fra som standard. Slår du det til, bliver navnene på de objekter, du gennemser, søgbare i Spotlight. Filindhold indekseres aldrig, og indekset bliver på denne Mac.

## Genveje og Siri

Bucketeer tilføjer handlinger til appen Genveje: vis buckets, upload en fil, opret et delingslink og kør et synkroniseringsjob. Brug dem i dine egne genveje, eller spørg Siri.

## Pro-funktioner

Disse funktioner kræver Bucketeer Pro:

- **Montér som drev**: højreklik på en bucket, og vælg **Montér som drev** for at bruge den i Finder som en disk. Monterede drev vises under **Monterede drev** i sidepanelet; højreklik, og vælg **Afmontér** for at fjerne dem. Buckets med kryptering på klientsiden kan ikke monteres. Ændringer på serveren vises i Finder, når du opdaterer bucketen i Bucketeer. Hvis en fil, du redigerer i Finder, er blevet ændret på serveren i mellemtiden, gemmes din version ved siden af som en konfliktkopi.
- **Synkroniseringsjob**: i sektionen **Synkronisering** opretter du et job, der kopierer, flytter eller spejler mellem to buckets, på tværs af konti og udbydere, eller mellem en lokal mappe og en bucket. Kør det manuelt, ved opstart, hvert N. minut eller når den lokale mappe ændres. Ved flytning fra en lokal mappe lægges hver kildefil i papirkurven, når den er kopieret, så en ændring i sidste øjeblik aldrig går tabt.
- **Overvågede mapper**: **Ny overvåget mappe…** uploader hver ny fil i en lokal mappe til en bucket.
- **Kopiér til anden konto…**: kopierer objekter til en anden konto eller udbyder. Når begge sider tillader det, kører kopieringen på serveren, og dataene passerer ikke gennem din Mac.
- **Menulinjetilstand**: **Indstillinger → Generelt** holder Bucketeer kørende i menulinjen, så drev og synkroniseringsjob forbliver aktive, når hovedvinduet er lukket.

Alt andet er tilgængeligt i gratisversionen.

## Bucketeer Pro, prøveperiode og køb

Bucketeer Pro er et engangskøb i appen via App Store, uden abonnement. Åbn **Indstillinger → Pro** eller en Pro-funktion for at se prisen i din valuta og købe.

Du kan prøve Bucketeer Pro gratis i 14 dage. Før du starter, viser købssiden prøveperiodens længde, hvad der sker bagefter, og prisen på Pro Livstid; klik derefter på **Start prøveperiode**. Når prøveperioden slutter, fortsætter Bucketeer i gratisversionen, og der opkræves intet. Prøveperioden kan startes én gang pr. Apple-id, og gendannelse af køb henter også en igangværende prøveperiode tilbage på en anden Mac.

- **Gendan køb** henter Pro tilbage på en anden Mac eller efter en geninstallation.
- **Indløs kode** åbner Apples vindue til tilbudskoder.

## Tastaturgenveje

- **⌘U**: Upload filer
- **⇧⌘N**: Ny mappe
- **⌥⌘0**: Aktivitetslog
- **⇧⌘⌫**: Papirkurv
- **⌘?**: Bucketeer-hjælp
- **⌘,**: Indstillinger

## Privatliv

Bucketeer indsamler ingen analysedata og indeholder ingen sporing. Dine konti, nøgler og logs bliver på denne Mac. Netværkstrafik går kun til de lagerudbydere, du konfigurerer, og til Apple ved køb. Detaljer: **Hjælp → Privatlivspolitik…**

## Brug for hjælp?

- Rapportér et problem: **Hjælp → Rapportér et problem…** eller <https://support.apps.digitalfreedom.co.za/>
- Websted: <https://digitalfreedom.co.za>
