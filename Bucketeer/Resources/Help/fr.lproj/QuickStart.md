# Aide Bucketeer

Bucketeer est une app Mac pour le stockage d’objets : Amazon S3, les fournisseurs compatibles S3 et Azure Blob Storage. Ce guide couvre toutes les fonctionnalités, du premier compte aux volumes Finder et aux tâches de synchronisation.

## Ajouter un compte

- Cliquez sur **+** dans l’en-tête de la barre latérale.
- Choisissez un fournisseur : AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj ou Custom (MinIO et tout autre point de terminaison compatible S3).
- Saisissez un nom, la région ou le point de terminaison, et vos identifiants (clé d’accès et secret ; pour Azure, la clé du compte de stockage).
- Cliquez sur **Tester la connexion**, puis sur **Enregistrer**.

Vos identifiants sont stockés dans le trousseau macOS sur ce Mac. Bucketeer n’a ni serveur ni compte utilisateur ; l’app communique directement avec les points de terminaison que vous configurez.

## Modifier un compte

Le secret est masqué lorsque vous modifiez un compte. Cliquez sur **Révéler les identifiants enregistrés** et confirmez avec Touch ID ou le mot de passe de votre Mac pour le voir. Si vous enregistrez sans toucher au secret, celui qui est enregistré reste inchangé.

## Parcourir les buckets et les objets

- Cliquez sur un compte dans la barre latérale pour afficher ses buckets.
- Double-cliquez sur un bucket ou un dossier pour l’ouvrir. Utilisez la barre de chemin ou la flèche vers le haut pour revenir en arrière.
- Sélectionnez un fichier pour voir ses détails et un aperçu Quick Look dans le panneau de droite.
- Utilisez le champ de recherche pour filtrer le dossier actuel.

## Téléverser et télécharger

- **Téléverser** : cliquez sur le bouton de téléversement ou appuyez sur **⌘U**. Vous pouvez aussi faire glisser des fichiers depuis le Finder dans la liste des objets ou sur un bucket.
- **Télécharger** : faites un clic droit sur un fichier et choisissez **Télécharger…**.
- Les fichiers volumineux sont transférés en plusieurs parties en parallèle. Un téléversement interrompu reprend là où il s’est arrêté.
- Tous les transferts apparaissent sous **Transferts** dans la barre latérale, avec leur progression et un bouton d’annulation.
- **Réglages → Transferts** vous permet de limiter la bande passante totale.

## Ouvrir des fichiers dans d’autres apps

- Double-cliquez sur un fichier, ou faites un clic droit dessus et choisissez **Ouvrir**, pour l’ouvrir dans son app par défaut. **Ouvrir avec** liste les autres apps capables de l’ouvrir ; **Autre…** permet de choisir n’importe quelle app.
- Bucketeer télécharge le fichier dans un dossier temporaire et le surveille. Peu après chaque enregistrement, le fichier est de nouveau téléversé via la file de transferts habituelle, donc le chiffrement côté client s’applique aussi.
- Si l’objet a été modifié ou supprimé sur le serveur après son ouverture, Bucketeer ne l’écrase pas. Votre version est téléversée à côté sous le nom « nom (conflict date).ext » et Bucketeer affiche un message.
- La copie temporaire est supprimée dès que le serveur a reçu votre dernier enregistrement. Si un enregistrement n’a pas pu être téléversé (par exemple hors connexion), Bucketeer conserve le fichier sur ce Mac et vous propose **Téléverser à nouveau**, **Enregistrer une copie…** ou **Abandonner la modification**, y compris au lancement suivant, par exemple après un plantage.

## Gérer les objets

- **Nouveau dossier** : bouton de la barre d’outils ou **⇧⌘N**.
- **Renommer…** : faites un clic droit sur un objet. Un renommage est une copie côté serveur suivie d’une suppression. Renommer ou supprimer un dossier s’applique à tout son contenu, et un renommage ne remplace jamais un nom existant.
- **Supprimer** : sélectionnez un ou plusieurs objets, cliquez sur le bouton corbeille et confirmez.
- **Copier le lien profond** : copie un lien `bucketeer://` vers l’objet, qui l’ouvre dans Bucketeer depuis n’importe où sur votre Mac.

## Liens de partage

Faites un clic droit sur un fichier et choisissez **Obtenir un lien de partage…**. Choisissez la durée de validité du lien, puis copiez-le ou partagez-le. Le lien est signé sur votre Mac avec vos identifiants ; toute personne qui le possède peut télécharger le fichier jusqu’à son expiration.

## Versions

Faites un clic droit sur un fichier et choisissez **Afficher les versions…** pour voir son historique de versions. Vous pouvez restaurer une ancienne version comme nouvelle copie la plus récente ou supprimer une seule version. Le versionnage doit être activé pour le bucket chez le fournisseur.

## Métadonnées et tags

Faites un clic droit sur un fichier et choisissez **Métadonnées et tags…** pour modifier les en-têtes HTTP (type de contenu, contrôle du cache et autres), les métadonnées utilisateur et les tags, et pour voir la classe de stockage. Certains fournisseurs ne prennent pas en charge tous les champs ; Bucketeer vous l’indique dans ce cas.

**Réglages → Règles** contient les règles de tags automatiques : elles ajoutent des tags et des métadonnées aux nouveaux téléversements qui correspondent à un modèle de nom de fichier ou à un type MIME.

## Tableau de bord du bucket

Cliquez sur **Tableau de bord** dans la barre d’outils d’un bucket ouvert. Il affiche le nombre d’objets, la taille totale, les plus gros objets, une estimation approximative du coût mensuel, ainsi que les règles de cycle de vie, la configuration CORS et la politique du bucket (en lecture seule).

## Corbeille

Lorsque vous supprimez des objets, Bucketeer peut conserver une copie locale sur ce Mac (**Réglages → Transferts → Corbeille**). Ouvrez la corbeille avec **Fenêtre → Corbeille** (**⇧⌘⌫**) et cliquez sur **Restaurer** pour téléverser une copie en cache à son emplacement d’origine. L’objet chez le fournisseur est supprimé immédiatement ; seule la copie locale peut être restaurée. Les entrées sont supprimées automatiquement après la durée de conservation que vous avez définie.

## Journal d’activité

**Fenêtre → Journal d’activité** (**⌥⌘0**) liste les téléversements, téléchargements, suppressions, synchronisations, liens de partage et modifications de compte. Vous pouvez filtrer la liste, y faire une recherche et l’exporter au format CSV. Les entrées sont conservées sur ce Mac pendant 180 jours.

## Chiffrement côté client

Dans **Réglages → Chiffrement**, vous pouvez créer une clé pour un bucket. Dès lors, chaque téléversement vers ce bucket est chiffré sur votre Mac (AES-256-GCM) avant de le quitter, et les téléchargements sont déchiffrés à la volée. La clé est stockée uniquement dans le trousseau macOS sur ce Mac.

Important : si vous perdez la clé, personne ne peut déchiffrer ces objets, pas même nous. Les buckets chiffrés ne peuvent pas être montés dans le Finder dans cette version de Bucketeer.

## Spotlight

**Réglages → Transferts → Spotlight** est désactivé par défaut. Lorsque vous l’activez, les noms des objets que vous parcourez deviennent consultables dans Spotlight. Le contenu des fichiers n’est jamais indexé, et l’index reste sur ce Mac.

## Raccourcis et Siri

Bucketeer ajoute des actions à l’app Raccourcis : lister les buckets, téléverser un fichier, créer un lien de partage et lancer une tâche de synchronisation. Utilisez-les dans vos propres raccourcis ou demandez à Siri.

## Fonctionnalités Pro

Ces fonctionnalités nécessitent Bucketeer Pro :

- **Monter comme volume** : faites un clic droit sur un bucket et choisissez **Monter comme volume** pour l’utiliser dans le Finder comme un disque. Les volumes montés apparaissent sous **Volumes montés** dans la barre latérale ; faites un clic droit pour **Démonter**. Les buckets avec chiffrement côté client ne peuvent pas être montés. Les modifications faites sur le serveur apparaissent dans le Finder quand vous actualisez le bucket dans Bucketeer. Si un fichier que vous modifiez dans le Finder a changé entre-temps sur le serveur, votre version est enregistrée à côté comme copie en conflit.
- **Tâches de synchronisation** : dans la section **Synchronisation**, créez une tâche qui copie, déplace ou met en miroir entre deux buckets, entre comptes et fournisseurs, ou entre un dossier local et un bucket. Lancez-la manuellement, au démarrage, toutes les N minutes ou lorsque le dossier local change.
- **Dossiers surveillés** : **Nouveau dossier surveillé…** téléverse chaque nouveau fichier d’un dossier local vers un bucket.
- **Copier vers un autre compte…** : copie des objets vers un autre compte ou fournisseur. Lorsque les deux côtés le permettent, la copie s’effectue côté serveur et les données ne passent pas par votre Mac.
- **Mode barre des menus** : **Réglages → Général** maintient Bucketeer dans la barre des menus pour que les volumes et les tâches de synchronisation restent actifs lorsque la fenêtre principale est fermée.

Tout le reste est disponible dans la version gratuite.

## Bucketeer Pro, essai et achat

Bucketeer Pro est un achat intégré unique via l’App Store, sans abonnement. Ouvrez **Réglages → Pro** ou n’importe quelle fonctionnalité Pro pour voir le prix dans votre devise et acheter.

Vous pouvez essayer Bucketeer Pro gratuitement pendant 14 jours. Avant de commencer, la page d’achat indique la durée de l’essai, ce qui se passe ensuite et le prix de Pro à vie ; cliquez ensuite sur **Démarrer l'essai**. À la fin de l’essai, Bucketeer continue en version gratuite et rien n’est facturé. L’essai peut être démarré une fois par identifiant Apple, et la restauration des achats rétablit aussi un essai en cours sur un autre Mac.

- **Restaurer l'achat** rétablit Pro sur un autre Mac ou après une réinstallation.
- **Utiliser un code** ouvre la fenêtre d’Apple pour les codes d’offre.

## Raccourcis clavier

- **⌘U** : Téléverser des fichiers
- **⇧⌘N** : Nouveau dossier
- **⌥⌘0** : Journal d’activité
- **⇧⌘⌫** : Corbeille
- **⌘?** : Aide Bucketeer
- **⌘,** : Réglages

## Confidentialité

Bucketeer ne collecte aucune donnée d’analyse et ne contient aucun pistage. Vos comptes, clés et journaux restent sur ce Mac. Le trafic réseau va uniquement aux fournisseurs de stockage que vous configurez et à Apple pour les achats. Détails : **Aide → Politique de confidentialité…**

## Besoin d’aide ?

- Signaler un problème : **Aide → Signaler un problème…** ou <https://support.apps.digitalfreedom.co.za/>
- Site web : <https://digitalfreedom.co.za>
