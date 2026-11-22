# Bucketeer-Hilfe

Bucketeer ist eine Mac-App für Objektspeicher: Amazon S3, S3-kompatible Anbieter und Azure Blob Storage. Diese Anleitung beschreibt alle Funktionen, vom ersten Konto bis zu Finder-Laufwerken und Sync-Aufträgen.

## Konto hinzufügen

- Klicke auf **+** im Kopf der Seitenleiste.
- Wähle einen Anbieter: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj oder Custom (MinIO und jeder andere S3-kompatible Endpunkt).
- Gib einen Namen, die Region oder den Endpunkt und deine Zugangsdaten ein (Access Key und Secret; bei Azure den Schlüssel des Speicherkontos).
- Darf dein Schlüssel nur auf einen Bucket zugreifen (bei Civo üblich), gib dessen Namen unter **Bucket** ein; das Konto zeigt dann nur diesen Bucket. Civo-Schlüssel gelten nur in der Region, in der sie erstellt wurden.
- Klicke auf **Verbindung testen** und dann auf **Speichern**.

Deine Zugangsdaten werden im macOS-Schlüsselbund auf diesem Mac gespeichert. Bucketeer hat keinen Server und kein Benutzerkonto; die App spricht direkt mit den Endpunkten, die du einrichtest.

## Konto bearbeiten

Beim Bearbeiten eines Kontos ist das Secret verborgen. Klicke auf **Gespeicherte Zugangsdaten anzeigen** und bestätige mit Touch ID oder deinem Mac-Passwort, um es zu sehen. Wenn du speicherst, ohne das Secret anzufassen, bleibt das gespeicherte unverändert.

## Buckets und Objekte durchsuchen

- Klicke auf ein Konto in der Seitenleiste, um seine Buckets aufzulisten.
- Doppelklicke auf einen Bucket oder Ordner, um ihn zu öffnen. Mit der Pfadleiste oder dem Pfeil nach oben gehst du zurück.
- Wähle eine Datei aus, um ihre Details und eine Quick Look-Vorschau im rechten Bereich zu sehen.
- Mit dem Suchfeld filterst du den aktuellen Ordner.

## Hochladen und herunterladen

- **Hochladen**: Klicke auf die Taste zum Hochladen oder drücke **⌘U**. Du kannst Dateien auch aus dem Finder in die Objektliste oder auf einen Bucket ziehen.
- **Herunterladen**: Klicke mit der rechten Maustaste auf eine Datei und wähle **Herunterladen…**.
- Große Dateien werden in parallelen Teilen übertragen. Ein unterbrochener Upload wird dort fortgesetzt, wo er angehalten hat.
- Alle Übertragungen erscheinen unter **Übertragungen** in der Seitenleiste, mit Fortschritt und einer Taste zum Abbrechen.
- Unter **Einstellungen → Übertragungen** kannst du die gesamte Bandbreite begrenzen.

## Dateien in anderen Apps öffnen

- Doppelklicke auf eine Datei oder wähle nach einem Rechtsklick **Öffnen**, um sie in ihrer Standard-App zu öffnen. **Öffnen mit** listet weitere Apps, die sie öffnen können; mit **Andere …** wählst du eine beliebige App.
- Bucketeer lädt die Datei in einen temporären Ordner und beobachtet sie. Kurz nach jedem Sichern wird sie über die normale Übertragungsliste wieder hochgeladen, die clientseitige Verschlüsselung gilt also auch hier.
- Wurde das Objekt nach dem Öffnen auf dem Server geändert oder gelöscht, überschreibt Bucketeer es nicht. Deine Version wird daneben als „Name (conflict Datum).Endung“ hochgeladen, und Bucketeer zeigt dir einen Hinweis.
- Die temporäre Kopie wird gelöscht, sobald der Server deine letzte Sicherung hat. Konnte eine Sicherung nicht hochgeladen werden (etwa ohne Verbindung), behält Bucketeer die Datei auf diesem Mac und bietet dir **Erneut hochladen**, **Kopie sichern …** oder **Änderung verwerfen** an — auch beim nächsten Start, etwa nach einem Absturz.

## Objekte verwalten

- **Neuer Ordner**: Taste in der Symbolleiste oder **⇧⌘N**.
- **Umbenennen…**: Klicke mit der rechten Maustaste auf ein Objekt. Umbenennen ist eine serverseitige Kopie mit anschließendem Löschen. Umbenennen oder Löschen eines Ordners gilt für alles darin, und Umbenennen ersetzt nie einen vorhandenen Namen.
- **Löschen**: Wähle ein oder mehrere Objekte aus, klicke auf die Papierkorb-Taste und bestätige.
- **Deep-Link kopieren**: Kopiert einen `bucketeer://`-Link zum Objekt, der es von überall auf deinem Mac in Bucketeer öffnet.

## Links teilen

Klicke mit der rechten Maustaste auf eine Datei und wähle **Teilen-Link erstellen…**. Lege fest, wie lange der Link gültig bleibt, und kopiere oder teile ihn dann. Der Link wird auf deinem Mac mit deinen Zugangsdaten signiert; jeder, der ihn hat, kann die Datei herunterladen, bis er abläuft.

## Versionen

Klicke mit der rechten Maustaste auf eine Datei und wähle **Versionen anzeigen…**, um ihren Versionsverlauf zu sehen. Du kannst eine ältere Version als neue aktuelle Kopie wiederherstellen oder eine einzelne Version löschen. Für den Bucket muss beim Anbieter die Versionierung aktiviert sein.

## Metadaten und Tags

Klicke mit der rechten Maustaste auf eine Datei und wähle **Metadaten & Tags…**, um HTTP-Header (Content-Type, Cache-Control und andere), Benutzer-Metadaten und Tags zu bearbeiten und die Speicherklasse zu sehen. Manche Anbieter unterstützen nicht jedes Feld; Bucketeer sagt dir, wenn das der Fall ist.

**Einstellungen → Regeln** enthält Regeln für automatisches Taggen: Diese Regeln fügen neuen Uploads, die zu einem Dateinamenmuster oder einem MIME-Typ passen, Tags und Metadaten hinzu.

## Bucket-Dashboard

Klicke in der Symbolleiste eines geöffneten Buckets auf **Dashboard**. Es zeigt die Anzahl der Objekte, die Gesamtgröße, die größten Objekte, eine grobe Schätzung der monatlichen Kosten sowie die Lifecycle-Regeln, die CORS-Konfiguration und die Bucket-Policy des Buckets (nur lesend).

## Papierkorb

Wenn du Objekte löschst, kann Bucketeer eine lokale Kopie auf diesem Mac behalten (**Einstellungen → Übertragungen → Papierkorb**). Öffne den Papierkorb mit **Fenster → Papierkorb** (**⇧⌘⌫**) und klicke auf **Wiederherstellen**, um eine zwischengespeicherte Kopie an ihren ursprünglichen Ort hochzuladen. Das Objekt beim Anbieter wird sofort gelöscht; nur die lokale Kopie kann wiederhergestellt werden. Einträge werden nach der von dir festgelegten Aufbewahrungsdauer automatisch entfernt.

## Aktivitätsprotokoll

**Fenster → Aktivitätsprotokoll** (**⌥⌘0**) listet Uploads, Downloads, Löschvorgänge, Sync-Läufe, Teilen-Links und Kontoänderungen auf. Du kannst die Liste filtern, durchsuchen und als CSV exportieren. Einträge bleiben 180 Tage auf diesem Mac gespeichert.

## Clientseitige Verschlüsselung

Unter **Einstellungen → Verschlüsselung** kannst du einen Schlüssel für einen Bucket erstellen. Ab dann wird jeder Upload in diesen Bucket auf deinem Mac verschlüsselt (AES-256-GCM), bevor er ihn verlässt, und Downloads werden beim Laden entschlüsselt. Der Schlüssel wird nur im macOS-Schlüsselbund auf diesem Mac gespeichert.

Verschlüsselt wird nur der Dateiinhalt. Objektnamen, Pfade und Größen bleiben für deinen Speicheranbieter lesbar. Verschlüsselte Objekte werden als `application/octet-stream` gespeichert, damit der gespeicherte Inhaltstyp den ursprünglichen Dateityp nicht verrät.

Wichtig: Wenn du den Schlüssel verlierst, kann niemand diese Objekte entschlüsseln, auch wir nicht. Verschlüsselte Buckets können in dieser Version von Bucketeer nicht im Finder eingebunden werden.

## Spotlight

**Einstellungen → Übertragungen → Spotlight** ist standardmäßig aus. Wenn du es einschaltest, werden die Namen der Objekte, die du durchsuchst, in Spotlight auffindbar. Dateiinhalte werden nie indexiert, und der Index bleibt auf diesem Mac.

## Kurzbefehle und Siri

Bucketeer fügt der Kurzbefehle-App Aktionen hinzu: Buckets auflisten, eine Datei hochladen, einen Teilen-Link erstellen und einen Sync-Auftrag ausführen. Nutze sie in deinen eigenen Kurzbefehlen oder frag Siri.

## Pro-Funktionen

Diese Funktionen brauchen Bucketeer Pro:

- **Als Laufwerk einbinden**: Klicke mit der rechten Maustaste auf einen Bucket und wähle **Als Laufwerk einbinden**, um ihn im Finder wie eine Festplatte zu nutzen. Eingebundene Laufwerke erscheinen unter **Eingebundene Laufwerke** in der Seitenleiste; mit einem Rechtsklick wählst du **Auswerfen**. Buckets mit clientseitiger Verschlüsselung können nicht eingebunden werden. Änderungen auf dem Server erscheinen im Finder, wenn du den Bucket in Bucketeer aktualisierst. Wurde eine Datei, die du im Finder bearbeitest, inzwischen auf dem Server geändert, wird deine Version daneben als Konfliktkopie gesichert.
- **Sync-Aufträge**: Erstelle im Bereich **Sync** einen Auftrag, der zwischen zwei Buckets kopiert, verschiebt oder spiegelt, auch über Konten und Anbieter hinweg, oder zwischen einem lokalen Ordner und einem Bucket. Starte ihn von Hand, beim Programmstart, alle N Minuten oder wenn sich der lokale Ordner ändert. Beim Verschieben aus einem lokalen Ordner landet jede Quelldatei nach dem Kopieren im Papierkorb, sodass eine Änderung in letzter Sekunde nie verloren geht.
- **Beobachtete Ordner**: **Neuer beobachteter Ordner…** lädt jede neue Datei in einem lokalen Ordner in einen Bucket hoch.
- **In anderes Konto kopieren…**: Kopiert Objekte in ein anderes Konto oder zu einem anderen Anbieter. Wenn beide Seiten es erlauben, läuft die Kopie serverseitig, und die Daten gehen nicht über deinen Mac.
- **Menüleisten-Modus**: **Einstellungen → Allgemein** lässt Bucketeer in der Menüleiste weiterlaufen, damit Laufwerke und Sync-Aufträge aktiv bleiben, wenn das Hauptfenster geschlossen ist.

Alles andere ist in der kostenlosen Stufe enthalten.

## Bucketeer Pro, Testphase und Kauf

Bucketeer Pro ist ein einmaliger In-App-Kauf über den App Store, ohne Abo. Öffne **Einstellungen → Pro** oder eine beliebige Pro-Funktion, um den Preis in deiner Währung zu sehen und zu kaufen.

Du kannst Bucketeer Pro 14 Tage lang kostenlos testen. Vor dem Start zeigt die Kaufseite die Dauer der Testphase, was danach passiert und den Preis von Pro für immer; dann klickst du auf **Testphase starten**. Wenn die Testphase endet, läuft Bucketeer in der kostenlosen Stufe weiter, und es wird nichts berechnet. Die Testphase lässt sich einmal pro Apple-ID starten, und beim Wiederherstellen von Käufen kommt eine laufende Testphase auch auf einem anderen Mac zurück.

- **Kauf wiederherstellen** holt Pro auf einem anderen Mac oder nach einer Neuinstallation zurück.
- **Code einlösen** öffnet Apples Fenster für Angebotscodes.

## Tastaturkurzbefehle

- **⌘U**: Dateien hochladen
- **⇧⌘N**: Neuer Ordner
- **⌥⌘0**: Aktivitätsprotokoll
- **⇧⌘⌫**: Papierkorb
- **⌘?**: Bucketeer-Hilfe
- **⌘,**: Einstellungen

## Datenschutz

Bucketeer erhebt keine Analysedaten und enthält kein Tracking. Deine Konten, Schlüssel und Protokolle bleiben auf diesem Mac. Netzwerkverkehr geht nur an die Speicheranbieter, die du einrichtest, und für Käufe an Apple. Details: **Hilfe → Datenschutzerklärung…**

## Brauchst du Hilfe?

- Ein Problem melden: **Hilfe → Fehler melden…** oder <https://support.apps.digitalfreedom.co.za/>
- Website: <https://digitalfreedom.co.za>
