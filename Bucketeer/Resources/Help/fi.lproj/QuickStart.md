# Bucketeer-ohje

Bucketeer on Mac-appi objektitallennukseen: Amazon S3, S3-yhteensopivat palveluntarjoajat ja Azure Blob Storage. Tämä opas käy läpi kaikki ominaisuudet ensimmäisestä tilistä Finder-asemiin ja synkronointitehtäviin.

## Lisää tili

- Klikkaa **+** sivupalkin yläosassa.
- Valitse palveluntarjoaja: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj tai Custom (MinIO ja mikä tahansa muu S3-yhteensopiva päätepiste).
- Anna nimi, alue tai päätepiste sekä tunnistetietosi (käyttöavain ja salainen avain; Azuressa tallennustilin avain).
- Klikkaa **Testaa yhteys** ja sitten **Tallenna**.

Tunnistetietosi tallennetaan tämän Macin macOS-avainnippuun. Bucketeerilla ei ole palvelinta eikä käyttäjätiliä; se on yhteydessä suoraan määrittämiisi päätepisteisiin.

## Muokkaa tiliä

Salainen avain on piilotettu, kun muokkaat tiliä. Klikkaa **Näytä tallennetut tunnistetiedot** ja vahvista Touch ID:llä tai Macin salasanalla nähdäksesi sen. Jos tallennat koskematta salaiseen avaimeen, tallennettu avain pysyy ennallaan.

## Selaa bucketeja ja objekteja

- Klikkaa tiliä sivupalkissa nähdäksesi sen bucketit.
- Avaa bucket tai kansio kaksoisklikkaamalla. Palaa takaisin polkupalkin tai ylänuolen avulla.
- Valitse tiedosto nähdäksesi sen tiedot ja Pikakatselu-esikatselun oikeassa paneelissa.
- Suodata nykyistä kansiota hakukentällä.

## Lähetä ja lataa

- **Lähetä**: klikkaa lähetyspainiketta tai paina **⌘U**. Voit myös vetää tiedostoja Finderista objektiluetteloon tai bucketin päälle.
- **Lataa**: klikkaa tiedostoa hiiren oikealla painikkeella ja valitse **Lataa…**.
- Suuret tiedostot siirretään rinnakkaisina osina. Keskeytynyt lähetys jatkuu siitä, mihin se jäi.
- Kaikki siirrot näkyvät sivupalkin kohdassa **Siirrot** edistymisen ja peruutuspainikkeen kanssa.
- Kohdassa **Asetukset → Siirrot** voit rajoittaa kokonaiskaistanleveyttä.

## Hallitse objekteja

- **Uusi kansio**: työkalupalkin painike tai **⇧⌘N**.
- **Nimeä uudelleen…**: klikkaa objektia hiiren oikealla painikkeella. Uudelleennimeäminen on palvelimella tehtävä kopio, jota seuraa poisto.
- **Poista**: valitse yksi tai useampi objekti, klikkaa roskakoripainiketta ja vahvista.
- **Kopioi syvälinkki**: kopioi objektiin `bucketeer://`-linkin, joka avaa sen Bucketeerissa mistä tahansa Macillasi.

## Jakolinkit

Klikkaa tiedostoa hiiren oikealla painikkeella ja valitse **Hae jakolinkki…**. Valitse, kuinka kauan linkki on voimassa, ja kopioi tai jaa se. Linkki allekirjoitetaan Macillasi tunnistetiedoillasi; kuka tahansa, jolla linkki on, voi ladata tiedoston, kunnes linkki vanhenee.

## Versiot

Klikkaa tiedostoa hiiren oikealla painikkeella ja valitse **Näytä versiot…** nähdäksesi versiohistorian. Voit palauttaa vanhemman version uudeksi uusimmaksi kopioksi tai poistaa yksittäisen version. Bucketille on oltava otettu käyttöön versiointi palveluntarjoajalla.

## Metatiedot ja tunnisteet

Klikkaa tiedostoa hiiren oikealla painikkeella ja valitse **Metatiedot ja tunnisteet…** muokataksesi HTTP-otsakkeita (sisältötyyppi, cache control ja muut), käyttäjän metatietoja ja tunnisteita sekä nähdäksesi tallennusluokan. Kaikki palveluntarjoajat eivät tue kaikkia kenttiä; Bucketeer kertoo, kun näin on.

**Asetukset → Säännöt** sisältää automaattisen tunnisteiden lisäämisen säännöt: ne lisäävät tunnisteita ja metatietoja uusiin lähetyksiin, jotka vastaavat tiedostonimen mallia tai MIME-tyyppiä.

## Bucketin koontinäyttö

Klikkaa **Koontinäyttö** avoimen bucketin työkalupalkissa. Se näyttää objektien määrän, kokonaiskoon, suurimmat objektit, karkean arvion kuukausikustannuksista sekä bucketin elinkaarisäännöt, CORS-määritykset ja bucket-käytännön (vain luku).

## Roskakori

Kun poistat objekteja, Bucketeer voi säilyttää paikallisen kopion tällä Macilla (**Asetukset → Siirrot → Roskakori**). Avaa roskakori valitsemalla **Ikkuna → Roskakori** (**⇧⌘⌫**) ja klikkaa **Palauta** lähettääksesi tallennetun kopion takaisin alkuperäiseen paikkaansa. Palveluntarjoajalla oleva objekti poistetaan heti; vain paikallinen kopio voidaan palauttaa. Merkinnät poistetaan automaattisesti asettamasi säilytysajan jälkeen.

## Tapahtumaloki

**Ikkuna → Tapahtumaloki** (**⌥⌘0**) luettelee lähetykset, lataukset, poistot, synkronointiajot, jakolinkit ja tilimuutokset. Voit suodattaa, hakea ja viedä luettelon CSV-tiedostona. Merkinnät säilytetään tällä Macilla 180 päivää.

## Asiakaspuolen salaus

Kohdassa **Asetukset → Salaus** voit luoda avaimen bucketille. Siitä lähtien jokainen kyseiseen bucketiin lähetettävä tiedosto salataan Macillasi (AES-256-GCM) ennen lähettämistä, ja lataukset puretaan lennossa. Avain tallennetaan vain tämän Macin macOS-avainnippuun.

Tärkeää: jos kadotat avaimen, kukaan ei voi purkaa näiden objektien salausta, emme mekään. Salattuja bucketeja ei voi liittää Finderiin tässä Bucketeerin versiossa.

## Spotlight

**Asetukset → Siirrot → Spotlight** on oletuksena pois päältä. Kun otat sen käyttöön, selaamiesi objektien nimet tulevat haettaviksi Spotlightissa. Tiedostojen sisältöä ei koskaan indeksoida, ja indeksi pysyy tällä Macilla.

## Pikakomennot ja Siri

Bucketeer lisää toimintoja Pikakomennot-appiin: bucketien luettelointi, tiedoston lähettäminen, jakolinkin luominen ja synkronointitehtävän suorittaminen. Käytä niitä omissa pikakomennoissasi tai pyydä Siriä.

## Pro-ominaisuudet

Nämä ominaisuudet edellyttävät Bucketeer Prota:

- **Liitä asemaksi**: klikkaa bucketia hiiren oikealla painikkeella ja valitse **Liitä asemaksi**, niin voit käyttää sitä Finderissa kuin levyä. Vaatii macOS 14.1:n tai uudemman. Liitetyt asemat näkyvät sivupalkin kohdassa **Liitetyt asemat**; klikkaa hiiren oikealla painikkeella ja valitse **Poista liitos**. Bucketeja, joissa on asiakaspuolen salaus, ei voi liittää.
- **Synkronointitehtävät**: luo osiossa **Synkronointi** tehtävä, joka kopioi, siirtää tai peilaa kahden bucketin välillä, tilien ja palveluntarjoajien välillä tai paikallisen kansion ja bucketin välillä. Suorita se käsin, käynnistyksen yhteydessä, N minuutin välein tai kun paikallinen kansio muuttuu.
- **Valvotut kansiot**: **Uusi valvottu kansio…** lähettää jokaisen paikallisen kansion uuden tiedoston bucketiin.
- **Kopioi toiselle tilille…**: kopioi objekteja toiselle tilille tai palveluntarjoajalle. Kun molemmat osapuolet sallivat sen, kopiointi tapahtuu palvelimella eikä data kulje Macisi kautta.
- **Valikkorivitila**: **Asetukset → Yleiset** pitää Bucketeerin käynnissä valikkorivillä, jotta asemat ja synkronointitehtävät pysyvät aktiivisina, kun pääikkuna on suljettu.

Kaikki muu on käytettävissä Free-tasolla.

## Bucketeer Pro, kokeilujakso ja osto

Bucketeer Pro on kertaluonteinen appin sisäinen osto App Storen kautta, ilman tilausta. Avaa **Asetukset → Pro** tai mikä tahansa Pro-ominaisuus nähdäksesi hinnan omassa valuutassasi ja ostaaksesi.

Jos kopiollesi tarjotaan kokeilujaksoa, maksuikkuna ja **Asetukset → Pro** näyttävät, kuinka kauan se kestää. Kun se päättyy, Bucketeer jatkaa Free-tasolla eikä mitään veloiteta.

- **Palauta ostos** palauttaa Pron toisella Macilla tai uudelleenasennuksen jälkeen.
- **Lunasta koodi** (macOS 15 tai uudempi) avaa Applen ikkunan tarjouskoodeille.

## Näppäinoikotiet

- **⌘U**: Lähetä tiedostoja
- **⇧⌘N**: Uusi kansio
- **⌥⌘0**: Tapahtumaloki
- **⇧⌘⌫**: Roskakori
- **⌘?**: Bucketeer-ohje
- **⌘,**: Asetukset

## Tietosuoja

Bucketeer ei kerää analytiikkatietoja eikä sisällä seurantaa. Tilisi, avaimesi ja lokisi pysyvät tällä Macilla. Verkkoliikenne kulkee vain määrittämillesi tallennuspalveluntarjoajille ja ostoissa Applelle. Lisätietoja: **Ohjeet → Tietosuojakäytäntö…**

## Tarvitsetko apua?

- Ilmoita ongelmasta: **Ohjeet → Ilmoita ongelmasta…** tai <https://support.apps.digitalfreedom.co.za/>
- Verkkosivusto: <https://digitalfreedom.co.za>
