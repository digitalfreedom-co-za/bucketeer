# Bucketeer-help

Bucketeer is een Mac-app voor objectopslag: Amazon S3, S3-compatibele aanbieders en Azure Blob Storage. Deze handleiding behandelt alle functies, van het eerste account tot volumes in de Finder en synchronisaties.

## Een account toevoegen

- Klik op **+** in de kop van de navigatiekolom.
- Kies een aanbieder: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj of Aangepast (MinIO en elk ander S3-compatibel endpoint).
- Voer een naam, de regio of het endpoint en je inloggegevens in (toegangssleutel en geheim; voor Azure de sleutel van het opslagaccount).
- Klik op **Verbinding testen** en daarna op **Opslaan**.

Je inloggegevens worden in de sleutelhanger van macOS op deze Mac bewaard. Bucketeer heeft geen server en geen gebruikersaccount; de app communiceert rechtstreeks met de endpoints die je instelt.

## Een account wijzigen

Het geheim is verborgen als je een account wijzigt. Klik op **Toon opgeslagen referenties** en bevestig met Touch ID of je Mac-wachtwoord om het te zien. Als je bewaart zonder het geheim aan te raken, blijft het opgeslagen geheim ongewijzigd.

## Buckets en objecten bekijken

- Klik op een account in de navigatiekolom om de buckets ervan te tonen.
- Klik dubbel op een bucket of map om die te openen. Gebruik de padbalk of de pijl omhoog om terug te gaan.
- Selecteer een bestand om de details en een Quick Look-voorvertoning in het rechterpaneel te zien.
- Gebruik het zoekveld om de huidige map te filteren.

## Uploaden en downloaden

- **Upload**: klik op de uploadknop of druk op **⌘U**. Je kunt ook bestanden vanuit de Finder naar de objectlijst of op een bucket slepen.
- **Download**: klik met de rechtermuisknop op een bestand en kies **Downloaden…**.
- Grote bestanden worden in parallelle delen overgedragen. Een onderbroken upload gaat verder waar hij stopte.
- Alle overdrachten verschijnen onder **Overdrachten** in de navigatiekolom, met de voortgang en een knop om te annuleren.
- Met **Instellingen → Overdrachten** kun je de totale bandbreedte beperken.

## Objecten beheren

- **Nieuwe map**: knop in de knoppenbalk of **⇧⌘N**.
- **Hernoem…**: klik met de rechtermuisknop op een object. Hernoemen is een kopie op de server, gevolgd door een verwijdering.
- **Verwijder**: selecteer een of meer objecten, klik op de prullenbakknop en bevestig.
- **Diep-link kopiëren**: kopieert een `bucketeer://`-link naar het object, die het object vanaf elke plek op je Mac in Bucketeer opent.

## Deelkoppelingen

Klik met de rechtermuisknop op een bestand en kies **Deelkoppeling ophalen…**. Kies hoe lang de koppeling geldig blijft en kopieer of deel hem daarna. De koppeling wordt op je Mac met je inloggegevens ondertekend; iedereen die hem heeft, kan het bestand downloaden tot hij verloopt.

## Versies

Klik met de rechtermuisknop op een bestand en kies **Versies tonen…** om de versiegeschiedenis te zien. Je kunt een oudere versie terugzetten als nieuwe nieuwste kopie of een afzonderlijke versie verwijderen. Voor de bucket moet versiebeheer bij de aanbieder zijn ingeschakeld.

## Metadata en tags

Klik met de rechtermuisknop op een bestand en kies **Metadata & tags…** om HTTP-headers (contenttype, cachebeheer en andere), gebruikersmetadata en tags te wijzigen en de opslagklasse te zien. Niet elke aanbieder ondersteunt elk veld; Bucketeer laat het je weten als dat zo is.

**Instellingen → Regels** bevat regels voor automatisch taggen: ze voegen tags en metadata toe aan nieuwe uploads die overeenkomen met een bestandsnaampatroon of een MIME-type.

## Bucketdashboard

Klik op **Dashboard** in de knoppenbalk van een geopende bucket. Je ziet het aantal objecten, de totale grootte, de grootste objecten, een ruwe schatting van de maandelijkse kosten en de levenscyclusregels, de CORS-configuratie en het bucketbeleid (alleen-lezen).

## Prullenbak

Als je objecten verwijdert, kan Bucketeer een lokale kopie op deze Mac bewaren (**Instellingen → Overdrachten → Prullenbak**). Open de prullenbak via **Venster → Prullenbak** (**⇧⌘⌫**) en klik op **Herstellen** om een kopie uit de cache terug te uploaden naar de oorspronkelijke plek. Het object bij de aanbieder wordt meteen verwijderd; alleen de lokale kopie kan worden hersteld. Onderdelen worden automatisch verwijderd na de bewaartermijn die je instelt.

## Activiteitenlog

**Venster → Activiteitenlog** (**⌥⌘0**) toont uploads, downloads, verwijderingen, synchronisaties, deelkoppelingen en accountwijzigingen. Je kunt de lijst filteren, doorzoeken en als CSV exporteren. Onderdelen blijven 180 dagen op deze Mac bewaard.

## Versleuteling aan de clientzijde

In **Instellingen → Versleuteling** kun je een sleutel voor een bucket aanmaken. Vanaf dat moment wordt elke upload naar die bucket op je Mac versleuteld (AES-256-GCM) voordat hij vertrekt, en downloads worden direct ontsleuteld. De sleutel wordt alleen op deze Mac in de sleutelhanger van macOS bewaard.

Belangrijk: als je de sleutel kwijtraakt, kan niemand die objecten ontsleutelen, ook wij niet. In deze versie van Bucketeer kunnen versleutelde buckets niet in de Finder worden gekoppeld.

## Spotlight

**Instellingen → Overdrachten → Spotlight** staat standaard uit. Als je het inschakelt, worden de namen van objecten die je bekijkt doorzoekbaar in Spotlight. De inhoud van bestanden wordt nooit geïndexeerd en de index blijft op deze Mac.

## Opdrachten en Siri

Bucketeer voegt taken toe aan de Opdrachten-app: buckets weergeven, een bestand uploaden, een deelkoppeling aanmaken en een synchronisatie uitvoeren. Gebruik ze in je eigen opdrachten of vraag het aan Siri.

## Pro-functies

Voor deze functies heb je Bucketeer Pro nodig:

- **Koppelen als volume**: klik met de rechtermuisknop op een bucket en kies **Koppelen als volume** om hem in de Finder als schijf te gebruiken. Vereist macOS 14.1 of nieuwer. Gekoppelde volumes verschijnen onder **Gekoppelde volumes** in de navigatiekolom; klik met de rechtermuisknop om te **Ontkoppelen**. Buckets met versleuteling aan de clientzijde kunnen niet worden gekoppeld.
- **Synchronisaties**: maak in het gedeelte **Synchronisatie** een taak aan die kopieert, verplaatst of spiegelt tussen twee buckets, over accounts en aanbieders heen, of tussen een lokale map en een bucket. Voer hem handmatig uit, bij het opstarten, elke N minuten of wanneer de lokale map verandert.
- **Bewaakte mappen**: **Nieuwe bewaakte map…** uploadt elk nieuw bestand in een lokale map naar een bucket.
- **Naar ander account kopiëren…**: kopieert objecten naar een ander account of een andere aanbieder. Als beide kanten het toestaan, gebeurt de kopie op de server en gaan de gegevens niet via je Mac.
- **Menubalkmodus**: **Instellingen → Algemeen** houdt Bucketeer actief in de menubalk, zodat volumes en synchronisaties actief blijven als het hoofdvenster gesloten is.

Al het andere is beschikbaar in de gratis versie.

## Bucketeer Pro, proefperiode en aankoop

Bucketeer Pro is een eenmalige aankoop in de app via de App Store, zonder abonnement. Open **Instellingen → Pro** of een willekeurige Pro-functie om de prijs in je valuta te zien en te kopen.

Als er voor jouw exemplaar een proefperiode wordt aangeboden, tonen het aankoopscherm en **Instellingen → Pro** hoe lang die duurt. Als die afloopt, gaat Bucketeer verder in de gratis versie en wordt er niets in rekening gebracht.

- **Aankoop herstellen** haalt Pro terug op een andere Mac of na een herinstallatie.
- **Code inwisselen** (macOS 15 of nieuwer) opent het venster van Apple voor aanbiedingscodes.

## Toetscombinaties

- **⌘U**: Bestanden uploaden
- **⇧⌘N**: Nieuwe map
- **⌥⌘0**: Activiteitenlog
- **⇧⌘⌫**: Prullenbak
- **⌘?**: Bucketeer-help
- **⌘,**: Instellingen

## Privacy

Bucketeer verzamelt geen analysegegevens en bevat geen tracking. Je accounts, sleutels en logs blijven op deze Mac. Netwerkverkeer gaat alleen naar de opslagaanbieders die je instelt en naar Apple voor aankopen. Details: **Help → Privacybeleid…**

## Hulp nodig?

- Een probleem melden: **Help → Probleem melden…** of <https://support.apps.digitalfreedom.co.za/>
- Website: <https://digitalfreedom.co.za>
