<!-- doc-id: BUCKETEER_PRIVACY_POLICY | lang: de | area: app | version: 1.0.0 | valid-from: 2026-11-02 | translation-of: BUCKETEER_PRIVACY_POLICY en 1.0.0 (PRIVACY_POLICY.md) | review: not counsel-reviewed | owner: Marcel R. G. Berger -->
# Datenschutzerklärung

*Wie Bucketeer für macOS mit deinen Daten umgeht.*

**Anwendung** — Bucketeer für macOS, einschließlich seiner Finder-Erweiterung
("Bucketeer File Provider")
**Gültig ab** — 2. November 2026

**Verantwortlicher** — DigitalFreedom Global LLC (handelnd als DigitalFreedom),
30 N Gould St, Ste N, Sheridan, WY 82801, United States
**Kontakt für Datenschutz** — data-protection@digitalfreedom.co.za ·
Anfrageformular https://data-protection.digitalfreedom.co.za
**Allgemeiner Kontakt** — hello@digitalfreedom.co.za
**Website** — https://digitalfreedom.co.za

---

## 1. Zusammenfassung

- Es gibt **keinen Bucketeer-Server und kein Bucketeer-Konto**. Der
  Anbieter erhält weder deine Zugangsdaten noch deine Bucket-Listen noch
  den Inhalt deiner Dateien.
- Alles, was Bucketeer speichert, bleibt **auf deinem Mac**: Zugangsdaten
  und Verschlüsselungsschlüssel im macOS-Schlüsselbund, alles andere im
  lokalen Speicher der App.
- Bucketeer enthält **keine Analyse-, Tracking-, Werbe-, Absturzbericht-
  oder Attributions-SDKs**.
- Die App verbindet sich nur mit den **Speicher-Endpunkten, die du
  einrichtest** (S3-kompatible Anbieter und Azure Blob Storage), und mit
  **Apple** für den Kauf im App Store.
- Der Anbieter erhält personenbezogene Daten von dir nur, wenn **du uns
  schreibst**, zum Beispiel mit einer Support-Anfrage.

---

## 2. Weltweiter Geltungsbereich und DSGVO als Grundlage

Bucketeer wird über den Mac App Store in jedem Storefront vertrieben, den
Apple bedient. Diese Erklärung gilt für alle Nutzer, unabhängig davon, wo
sie leben. Der Anbieter wendet die EU-Datenschutz-Grundverordnung (DSGVO)
als **weltweiten Mindeststandard** an: Jeder Nutzer erhält mindestens den
hier beschriebenen Schutz. Wo das Recht deines Wohnsitzlandes einen
weitergehenden Schutz vorsieht, gilt dieses Recht.

---

## 3. Was die App auf deinem Mac speichert

Nichts davon wird an den Anbieter gesendet.

| Daten | Speicherort | Zweck |
|---|---|---|
| Konto-Metadaten (Name, Anbietertyp, Region, Endpunkt-URL, Konto-ID, Standard-Bucket, Path-Style-Einstellung, letzte Nutzung) und Definitionen von Sync-Aufträgen (Quelle, Ziel, Modus, Filter, Zeitplan, Zugriff auf lokale Ordner, letzter Lauf) | Lokale Datenbank im App-Group-Container `group.za.co.digitalfreedom.bucketeer`, gemeinsam genutzt mit der Bucketeer-Finder-Erweiterung | Verbindung zu deinen Speicherkonten herstellen und deine Sync-Aufträge ausführen |
| Zugangsdaten (S3 Access Key, Secret Key, optionales Session Token; Azure-Kontoname und -Schlüssel) | macOS-Schlüsselbund, gemeinsame Zugriffsgruppe der App und ihrer Finder-Erweiterung, nur verfügbar, solange der Mac entsperrt ist, nicht über iCloud synchronisiert | Anfragen an den von dir eingerichteten Endpunkt signieren |
| Aktivitätsprotokoll (Zeit, Vorgang, Status, Kontoname, Bucket, Objektschlüssel, Größe, Dauer, Fehlermeldung, Sync-Auftrag) | Lokale Datenbank im eigenen Container der App | Dir zeigen, was die App getan hat; optionaler CSV-Export. Einträge werden nach 180 Tagen automatisch gelöscht; du kannst das Protokoll jederzeit leeren |
| Papierkorb (Metadaten von Objekten, die du in Bucketeer gelöscht hast, und bis zu einer von dir festgelegten Größe eine lokale Kopie ihres Inhalts) | Lokale Datenbank und Cache-Ordner im eigenen Container der App | Dir ermöglichen, gelöschte Objekte wiederherzustellen. Einträge werden nach der von dir festgelegten Aufbewahrungsdauer entfernt (Standard 30 Tage) |
| Regeln für automatisches Tagging, Prüfpunkte für fortsetzbare Uploads | Lokale Datenbanken im eigenen Container der App | Deine Tagging-Regeln anwenden; unterbrochene Uploads fortsetzen |
| Verschlüsselungsschlüssel (nur wenn du für einen Bucket die clientseitige Verschlüsselung aktivierst) | Schlüsselmaterial im macOS-Schlüsselbund, Schlüsselbezeichnungen in einer lokalen Datenbank | Objekte auf deinem Mac ver- und entschlüsseln (siehe Abschnitt 6) |
| Einstellungen (Bandbreitenbegrenzung, Papierkorb- und Spotlight-Einstellungen, Menüleistenmodus, Vorschau für Hardware-Schlüssel) | Lokale Einstellungen der App | Deine Auswahl speichern |
| Vorschau-Cache | Temporärer Ordner der App, begrenzt auf 2 GiB | Vorschauen anzeigen, ohne erneut herunterzuladen |
| Dateien, die du mit einer anderen App öffnest (Öffnen / Öffnen mit) | Temporärer Ordner der App | Der anderen App die Bearbeitung ermöglichen und deine Speicherungen hochladen; gelöscht, sobald der Speicheranbieter deine letzte Speicherung erhalten hat |
| Änderungen, die nicht hochgeladen werden konnten (Öffnen / Öffnen mit) | Application-Support-Ordner der App | Deine nicht gesicherte Arbeit nach einem fehlgeschlagenen Upload oder einem Absturz erhalten; aufbewahrt, bis du sie in der App hochlädst, exportierst oder verwirfst |
| Heruntergeladene Dateien | Der von dir gewählte Ort | Deine Dateien, unter deiner Kontrolle |
| Bereitstellungsdateien für Finder-Laufwerke (nur für eingebundene Buckets) | Vom System verwalteter File-Provider-Speicher | Von macOS benötigt, um einen Bucket im Finder anzuzeigen |
| Letzte Auflistung der Ordner, die du im Finder geöffnet hast (Objektnamen und ETags, nur für eingebundene Buckets) | Eigener Container der Finder-Erweiterung | Änderungen auf dem Server im Finder anzeigen |

Durch das Deinstallieren der App werden nicht unbedingt alle diese Daten
von deinem Mac entfernt. Lösche zuerst die Konten in der App, wenn die
Zugangsdaten aus dem Schlüsselbund entfernt werden sollen; du kannst sie
auch in der Schlüsselbundverwaltung einsehen und löschen.

---

## 4. Netzwerkverbindungen

| Verbindung | Wann | Was gesendet wird | Empfänger |
|---|---|---|---|
| Deine Speicher-Endpunkte (AWS S3, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Civo, Storj, MinIO, ein eigener S3-Endpunkt, Azure Blob Storage) | Wenn du einen Bucket durchsuchst, überträgst, synchronisierst, einbindest oder seine Einstellungen änderst | Standardmäßige S3- oder Azure-Anfragen, auf deinem Mac signiert, einschließlich Objektnamen, Metadaten und von dir hochgeladener Dateiinhalte; der Endpunkt sieht außerdem deine IP-Adresse | Der von dir gewählte Speicheranbieter, im Rahmen deines eigenen Vertrags mit diesem Anbieter |
| Apple App Store (StoreKit) | Wenn du die Kaufseite öffnest, die Testphase startest, Bucketeer Pro kaufst oder wiederherstellst und wenn Apple eine Transaktion meldet | Apples eigene Kaufdaten; die App liest nur, ob Bucketeer Pro oder die Testphase aktiv ist und wann die Testphase begonnen hat | Apple, als eigenständiger Verantwortlicher |
| Links, die du öffnest (Website, Support-Formular, GitHub, Apples Erstattungsseite) | Nur wenn du sie anklickst | Anfrage deines Browsers | Der Betreiber der jeweiligen Seite |

Die App sendet keine Daten an den Anbieter. Anfragen an deine
Speicher-Endpunkte gehen direkt von deinem Mac zum Endpunkt; der Anbieter
ist an diesem Weg nicht beteiligt. Die eingebauten Anbieteradressen werden
über TLS (https) erreicht. Wenn du selbst eine Endpunktadresse eingibst
(eigenes S3, MinIO oder eine Endpunkt-Überschreibung) und diese mit
http:// beginnt, zum Beispiel ein Server in deinem eigenen Netzwerk,
verbindet sich die App wie gewünscht ohne TLS: Objektnamen, Metadaten,
Dateiinhalte und die signierten Anfragen werden dann unverschlüsselt
übertragen und können auf dem Netzwerkweg mitgelesen werden. Die App
zeigt eine Warnung, wenn du eine solche Adresse eingibst.

---

## 5. Funktionen mit besonderer Datenschutzrelevanz

**Finder-Laufwerk (File-Provider-Erweiterung).** Wenn du einen Bucket als
Laufwerk einbindest, liest die Bucketeer-Erweiterung die Konto-Metadaten
aus dem App-Group-Container und die Zugangsdaten aus der gemeinsamen
Schlüsselbundgruppe. Sie greift nur auf Buckets zu, die du eingebunden
hast. Buckets mit clientseitiger Verschlüsselung können in dieser Version
nicht eingebunden werden.

**Vorsignierte Links.** Teilbare Links werden auf deinem Mac erzeugt,
indem eine URL mit deinen Zugangsdaten signiert wird. Kein Server des
Anbieters ist daran beteiligt. Jeder, der den Link hat, kann das Objekt
herunterladen, bis der Link abläuft. Teile Links daher mit Bedacht.

**Spotlight.** Standardmäßig aus. Wenn du es einschaltest, werden
Dateinamen sowie Bucket- und Kontonamen der Ordner, die du durchsuchst,
dem lokalen macOS-Spotlight-Index auf deinem Mac hinzugefügt.
Dateiinhalte werden nicht indexiert. Ausschalten oder das Löschen eines
Kontos entfernt die Einträge.

**Kurzbefehle und bucketeer://-Links.** App Intents und Deep Links laufen
lokal auf deinem Mac und wirken nur auf Konten, die du eingerichtet hast.

**Überwachte Ordner und lokale Sync-Ordner.** Die App greift nur auf
lokale Ordner zu, die du selbst ausgewählt hast; der Zugriff wird als
Security-Scoped Bookmark in der lokalen Datenbank gespeichert.

**Touch ID und Hardware-Schlüssel.** Das Anzeigen eines gespeicherten
Geheimnisses erfordert die Authentifizierung als Gerätebesitzer (Touch ID
oder dein Mac-Passwort). Die App erhält von macOS nur ein Ja/Nein-Ergebnis,
niemals biometrische Daten. Die optionale Vorschau für Hardware-Schlüssel
in den Einstellungen listet nur die an deinen Mac angeschlossenen
Smartcard-Lesegeräte auf und ob eine Karte oder ein Token eingesteckt ist;
sie liest keine auf der Karte gespeicherten Daten.

---

## 6. Clientseitige Verschlüsselung (optional)

Wenn du die Verschlüsselung für einen Bucket aktivierst, erzeugt die App
auf deinem Mac einen zufälligen 256-Bit-Schlüssel und speichert ihn im
macOS-Schlüsselbund. Objekte werden vor dem Upload auf deinem Mac mit
AES-256-GCM verschlüsselt und nach dem Download auf deinem Mac
entschlüsselt. Dein Speicheranbieter erhält nur die verschlüsselten Daten.

Der Schlüssel wird nicht mit anderen Geräten synchronisiert, und der
Anbieter hat keine Kopie. Wenn du den Schlüssel löschst oder den Zugriff
auf den Schlüsselbund dieses Macs verlierst, können die verschlüsselten
Objekte nicht entschlüsselt werden, und der Anbieter kann sie nicht
wiederherstellen. Objektnamen und Metadaten werden nicht verschlüsselt.

---

## 7. Dein Kontakt mit uns

Wenn du uns schreibst (E-Mail, Support-Formular, Datenschutzformular),
verarbeiten wir deinen Namen, deine E-Mail-Adresse, den Inhalt deiner
Nachricht und etwaige Anhänge, um dir zu antworten. Rechtsgrundlage:
Art. 6 Abs. 1 lit. b DSGVO, soweit deine Anfrage deinen Kauf oder deine
Nutzung der App betrifft, ansonsten Art. 6 Abs. 1 lit. f DSGVO (unser
Interesse, Anfragen zu beantworten). Die Bearbeitung von
Support-Anfragen, die beteiligten Helpdesk-Anbieter und deren
Speicherfristen sind in den Datenschutzhinweisen des Helpdesks
beschrieben, die im Support-Portal unter
https://support.apps.digitalfreedom.co.za angezeigt werden.

---

## 8. Rechtsgrundlage der lokalen Verarbeitung

Die App verarbeitet deine Daten auf deinem Mac, um die Funktionen
bereitzustellen, die du nutzt (Art. 6 Abs. 1 lit. b DSGVO). Das Speichern
von Informationen auf deinem Mac und deren Auslesen ist für diese
Funktionen unbedingt erforderlich (§ 25 Abs. 2 Nr. 2 TDDDG, Art. 5 Abs. 3
Richtlinie 2002/58/EG). Der Anbieter hat keinen Zugriff auf diese Daten.

---

## 9. Dritte

**Speicheranbieter.** Jeder Speicheranbieter, den du verbindest, ist ein
eigenständiger Verantwortlicher für die Daten, die du dort speicherst. Es
gelten dessen Datenschutzerklärungen. Der Anbieter hat im Zusammenhang mit
deiner Nutzung der App keinen Vertrag mit ihnen.

**Apple.** Apple vertreibt die App und verarbeitet den Kauf von
Bucketeer Pro als eigenständiger Verantwortlicher nach seiner eigenen
Datenschutzrichtlinie (https://www.apple.com/legal/privacy/). In der
EU/im EWR, im Vereinigten Königreich, in der Schweiz und in der Türkei
verkauft Apple im eigenen Namen, anderswo als Vertreter des Anbieters.
Der Anbieter erhält Verkaufs- und Auszahlungsberichte aus App Store
Connect, nicht deine Zahlungsdaten.

Der Anbieter verkauft oder teilt keine personenbezogenen Daten.

---

## 10. Internationale Übermittlungen

Die App übermittelt keine Daten an den Anbieter. Anfragen an deine
Speicher-Endpunkte können je nach gewähltem Anbieter und gewählter Region
Grenzen überschreiten; diese Übermittlung findet zwischen dir und deinem
Anbieter statt. Wenn du uns schreibst, wird deine Nachricht von der
DigitalFreedom Global LLC in den Vereinigten Staaten und von den in den
Datenschutzhinweisen des Helpdesks genannten Helpdesk-Anbietern
verarbeitet.

---

## 11. Speicherdauer

Daten auf deinem Mac bleiben erhalten, bis du sie in der App, im Finder
oder in der Schlüsselbundverwaltung löschst, mit diesen automatischen
Grenzen: Aktivitätsprotokoll 180 Tage, Papierkorbeinträge nach der von
dir festgelegten Aufbewahrungsdauer (Standard 30 Tage), Vorschau-Cache
begrenzt auf 2 GiB. Der Anbieter hat von keinen dieser Daten eine Kopie.
Support-Korrespondenz wird so lange aufbewahrt, wie in den
Datenschutzhinweisen des Helpdesks angegeben.

---

## 12. Deine Rechte

Wo immer du lebst, hast du mindestens die Rechte nach der DSGVO: Auskunft
(Art. 15), Berichtigung (Art. 16), Löschung (Art. 17), Einschränkung der
Verarbeitung (Art. 18), Datenübertragbarkeit (Art. 20) und Widerspruch
(Art. 21).

Da die App nichts an den Anbieter sendet, betreffen diese Rechte nur
Daten, die du uns selbst geschickt hast, zum Beispiel eine
Support-Anfrage. Für Daten, die bei deinem Speicheranbieter oder bei
Apple gespeichert sind, wende dich direkt an diese.

Um deine Rechte auszuüben, schreibe an data-protection@digitalfreedom.co.za
oder nutze https://data-protection.digitalfreedom.co.za. Wir antworten
innerhalb eines Monats (Art. 12 Abs. 3 DSGVO) oder innerhalb der kürzeren
Frist, die dein lokales Recht vorschreibt.

**Beschwerden.** Du kannst dich bei einer Aufsichtsbehörde beschweren,
insbesondere in dem Land deines gewöhnlichen Aufenthalts, deines
Arbeitsplatzes oder des Orts des mutmaßlichen Verstoßes (Art. 77 DSGVO).
Der Anbieter hat keine Niederlassung in der EU, daher gibt es keine
federführende Aufsichtsbehörde. Im Vereinigten Königreich ist die
Behörde das Information Commissioner's Office, in der Schweiz der
Eidgenössische Datenschutz- und Öffentlichkeitsbeauftragte.

**Kalifornien.** Der Anbieter verkauft oder teilt keine personenbezogenen
Informationen und nutzt sie nicht für zielgerichtete Werbung. Einwohner
Kaliforniens haben das Recht auf Auskunft, Löschung und Berichtigung und
werden wegen der Ausübung dieser Rechte nicht benachteiligt.

---

## 13. Kinder

Bucketeer ist ein Werkzeug zur Verwaltung von Cloud-Speicher und richtet
sich nicht an Kinder. Die App erhebt keine personenbezogenen Daten für den
Anbieter und verarbeitet daher nicht wissentlich personenbezogene Daten
von Kindern.

---

## 14. Sicherheit

- Die App und ihre Finder-Erweiterung laufen in der macOS App Sandbox.
- Zugangsdaten und Verschlüsselungsschlüssel werden im macOS-Schlüsselbund
  aufbewahrt, sind nur verfügbar, solange der Mac entsperrt ist, und
  werden nicht über iCloud synchronisiert. Sie werden weder in
  Protokolldateien geschrieben noch in Fehlermeldungen angezeigt.
- Verbindungen zu Speicher-Endpunkten nutzen TLS, ausgenommen eine
  Endpunktadresse, die du selbst mit http:// eingibst (siehe Abschnitt 4).
  Anfragen werden auf deinem Mac signiert (AWS Signature Version 4 oder
  Azure Shared Key); der geheime Schlüssel selbst wird nie gesendet.

Keine Software ist fehlerfrei. Bitte melde Sicherheitsprobleme an
security@digitalfreedom.co.za.

---

## 15. Änderungen

Wenn sich diese Erklärung ändert, ändert sich das Datum "Gültig ab" oben,
und die App-Store-Versionshinweise der betreffenden Version weisen darauf
hin.

---

## 16. Kontakt

DigitalFreedom Global LLC (handelnd als DigitalFreedom)
30 N Gould St, Ste N
Sheridan, WY 82801
United States

Datenschutz: data-protection@digitalfreedom.co.za
Datenschutz-Anfrageformular: https://data-protection.digitalfreedom.co.za
Allgemeine Anfragen: hello@digitalfreedom.co.za
Website: https://digitalfreedom.co.za

---

© 2026 DigitalFreedom Global LLC. Alle Rechte vorbehalten.
