# Aiuto di Bucketeer

Bucketeer è un'app per Mac per l'archiviazione di oggetti: Amazon S3, provider compatibili con S3 e Azure Blob Storage. Questa guida copre tutte le funzioni, dal primo account alle unità nel Finder e ai job di sincronizzazione.

## Aggiungere un account

- Fai clic su **+** nell'intestazione della barra laterale.
- Scegli un provider: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj o Personalizzato (MinIO e qualsiasi altro endpoint compatibile con S3).
- Inserisci un nome, la regione o l'endpoint e le tue credenziali (chiave di accesso e segreto; per Azure la chiave dell'account di archiviazione).
- Fai clic su **Verifica connessione**, poi su **Salva**.

Le tue credenziali sono salvate nel portachiavi di macOS su questo Mac. Bucketeer non ha un server né un account utente; comunica direttamente con gli endpoint che configuri.

## Modificare un account

Il segreto è nascosto quando modifichi un account. Fai clic su **Rivela le credenziali salvate** e conferma con Touch ID o con la password del Mac per vederlo. Se salvi senza toccare il segreto, quello salvato resta invariato.

## Sfogliare bucket e oggetti

- Fai clic su un account nella barra laterale per elencarne i bucket.
- Fai doppio clic su un bucket o una cartella per aprirlo. Usa la barra del percorso o la freccia in su per tornare indietro.
- Seleziona un file per vederne i dettagli e un'anteprima Quick Look nel pannello di destra.
- Usa il campo di ricerca per filtrare la cartella corrente.

## Caricare e scaricare

- **Caricamento**: fai clic sul pulsante di caricamento o premi **⌘U**. Puoi anche trascinare file dal Finder nell'elenco degli oggetti o su un bucket.
- **Download**: fai clic con il tasto destro su un file e scegli **Scarica…**.
- I file grandi vengono trasferiti in parti parallele. Un caricamento interrotto riprende dal punto in cui si è fermato.
- Tutti i trasferimenti compaiono in **Trasferimenti** nella barra laterale, con l'avanzamento e un pulsante per annullare.
- In **Impostazioni → Trasferimenti** puoi limitare la larghezza di banda totale.

## Aprire file in altre app

- Fai doppio clic su un file, oppure clic destro e scegli **Apri**, per aprirlo nella sua app predefinita. **Apri con** elenca le altre app che possono aprirlo; con **Altro…** scegli qualsiasi app.
- Bucketeer scarica il file in una cartella temporanea e lo tiene d'occhio. Poco dopo ogni salvataggio il file viene ricaricato tramite la normale coda dei trasferimenti, quindi vale anche la crittografia lato client.
- Se l'oggetto è stato modificato o eliminato sul server dopo l'apertura, Bucketeer non lo sovrascrive. La tua versione viene caricata accanto come "nome (conflict data).ext" e Bucketeer mostra un messaggio.
- La copia temporanea viene eliminata non appena il server ha il tuo ultimo salvataggio. Se un salvataggio non è stato caricato (ad esempio senza connessione), Bucketeer conserva il file su questo Mac e ti propone **Carica di nuovo**, **Salva una copia…** o **Scarta modifica**, anche al successivo avvio, ad esempio dopo un arresto anomalo.

## Gestire gli oggetti

- **Nuova cartella**: pulsante nella barra degli strumenti o **⇧⌘N**.
- **Rinomina…**: fai clic con il tasto destro su un oggetto. Rinominare è una copia lato server seguita da un'eliminazione. Rinominare o eliminare una cartella vale per tutto il suo contenuto, e una ridenominazione non sostituisce mai un nome esistente.
- **Elimina**: seleziona uno o più oggetti, fai clic sul pulsante del cestino e conferma.
- **Copia link diretto**: copia un link `bucketeer://` all'oggetto, che lo apre in Bucketeer da qualsiasi punto del tuo Mac.

## Link di condivisione

Fai clic con il tasto destro su un file e scegli **Ottieni link di condivisione…**. Scegli per quanto tempo il link resta valido, poi copialo o condividilo. Il link viene firmato sul tuo Mac con le tue credenziali; chiunque lo abbia può scaricare il file fino alla scadenza.

## Versioni

Fai clic con il tasto destro su un file e scegli **Mostra versioni…** per vederne la cronologia delle versioni. Puoi ripristinare una versione precedente come nuova copia più recente o eliminare una singola versione. Il bucket deve avere il controllo delle versioni attivo presso il provider.

## Metadati e tag

Fai clic con il tasto destro su un file e scegli **Metadati e tag…** per modificare le intestazioni HTTP (tipo di contenuto, controllo della cache e altre), i metadati utente e i tag, e per vedere la classe di archiviazione. Alcuni provider non supportano tutti i campi; Bucketeer te lo segnala quando succede.

**Impostazioni → Regole** contiene le regole di tagging automatico: aggiungono tag e metadati ai nuovi caricamenti che corrispondono a uno schema di nome file o a un tipo MIME.

## Dashboard del bucket

Fai clic su **Dashboard** nella barra degli strumenti di un bucket aperto. Mostra il numero di oggetti, la dimensione totale, gli oggetti più grandi, una stima approssimativa del costo mensile e le regole del ciclo di vita, la configurazione CORS e la policy del bucket (sola lettura).

## Cestino

Quando elimini degli oggetti, Bucketeer può conservarne una copia locale su questo Mac (**Impostazioni → Trasferimenti → Cestino**). Apri il cestino con **Finestra → Cestino** (**⇧⌘⌫**) e fai clic su **Ripristina** per ricaricare una copia in cache nella sua posizione originale. L'oggetto presso il provider viene eliminato subito; si può ripristinare solo la copia locale. Le voci vengono rimosse automaticamente dopo il periodo di conservazione che imposti.

## Registro attività

**Finestra → Registro attività** (**⌥⌘0**) elenca caricamenti, download, eliminazioni, sincronizzazioni, link di condivisione e modifiche agli account. Puoi filtrare, cercare ed esportare l'elenco come CSV. Le voci restano su questo Mac per 180 giorni.

## Crittografia lato client

In **Impostazioni → Crittografia** puoi creare una chiave per un bucket. Da quel momento ogni caricamento in quel bucket viene crittografato sul tuo Mac (AES-256-GCM) prima di uscire, e i download vengono decrittografati al volo. La chiave è salvata nel portachiavi di macOS solo su questo Mac.

Importante: se perdi la chiave, nessuno può decrittografare quegli oggetti, nemmeno noi. In questa versione di Bucketeer i bucket crittografati non possono essere montati nel Finder.

## Spotlight

**Impostazioni → Trasferimenti → Spotlight** è disattivato per impostazione predefinita. Quando lo attivi, i nomi degli oggetti che sfogli diventano ricercabili in Spotlight. Il contenuto dei file non viene mai indicizzato e l'indice resta su questo Mac.

## Comandi rapidi e Siri

Bucketeer aggiunge azioni all'app Comandi rapidi: elencare i bucket, caricare un file, creare un link di condivisione ed eseguire un job di sincronizzazione. Usale nei tuoi comandi rapidi o chiedi a Siri.

## Funzioni Pro

Queste funzioni richiedono Bucketeer Pro:

- **Monta come unità**: fai clic con il tasto destro su un bucket e scegli **Monta come unità** per usarlo nel Finder come un disco. Richiede macOS 14.1 o versioni successive. Le unità montate compaiono in **Unità montate** nella barra laterale; fai clic con il tasto destro per **Smonta**. I bucket con crittografia lato client non possono essere montati. Le modifiche fatte sul server compaiono nel Finder quando aggiorni il bucket in Bucketeer. Se un file che modifichi nel Finder è cambiato nel frattempo sul server, la tua versione viene salvata accanto come copia in conflitto.
- **Job di sincronizzazione**: nella sezione **Sincronizzazione**, crea un job che copia, sposta o replica tra due bucket, tra account e provider, oppure tra una cartella locale e un bucket. Eseguilo manualmente, all'avvio, ogni N minuti o quando la cartella locale cambia.
- **Cartelle sorvegliate**: **Nuova cartella sorvegliata…** carica in un bucket ogni nuovo file di una cartella locale.
- **Copia in un altro account…**: copia oggetti in un altro account o provider. Quando entrambe le parti lo consentono, la copia avviene lato server e i dati non passano dal tuo Mac.
- **Modalità barra dei menu**: **Impostazioni → Generale** mantiene Bucketeer in esecuzione nella barra dei menu, così le unità e i job di sincronizzazione restano attivi quando la finestra principale è chiusa.

Tutto il resto è disponibile nel livello gratuito.

## Bucketeer Pro, prova e acquisto

Bucketeer Pro è un acquisto in-app una tantum tramite l'App Store, senza abbonamento. Apri **Impostazioni → Pro** o una qualsiasi funzione Pro per vedere il prezzo nella tua valuta e acquistare.

Puoi provare Bucketeer Pro gratis per 14 giorni. Prima di iniziare, la pagina di acquisto mostra la durata della prova, cosa succede dopo e il prezzo di Pro a vita; poi fai clic su **Inizia la prova**. Alla fine della prova Bucketeer continua nella versione gratuita e non viene addebitato nulla. La prova si può avviare una volta per ID Apple, e il ripristino degli acquisti riporta una prova in corso anche su un altro Mac.

- **Ripristina acquisto** riattiva Pro su un altro Mac o dopo una reinstallazione.
- **Riscatta codice** (macOS 15 o versioni successive) apre il pannello di Apple per i codici promozionali.

## Abbreviazioni da tastiera

- **⌘U**: Carica file
- **⇧⌘N**: Nuova cartella
- **⌥⌘0**: Registro attività
- **⇧⌘⌫**: Cestino
- **⌘?**: Aiuto di Bucketeer
- **⌘,**: Impostazioni

## Privacy

Bucketeer non raccoglie dati analitici e non contiene tracciamento. I tuoi account, le chiavi e i registri restano su questo Mac. Il traffico di rete va solo ai provider di archiviazione che configuri e ad Apple per gli acquisti. Dettagli: **Aiuto → Informativa sulla privacy…**

## Serve aiuto?

- Segnalare un problema: **Aiuto → Segnala un problema…** oppure <https://support.apps.digitalfreedom.co.za/>
- Sito web: <https://digitalfreedom.co.za>
