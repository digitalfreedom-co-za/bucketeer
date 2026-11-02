# Ayuda de Bucketeer

Bucketeer es una app para Mac de almacenamiento de objetos: Amazon S3, proveedores compatibles con S3 y Azure Blob Storage. Esta guía cubre todas las funciones, desde la primera cuenta hasta las unidades en el Finder y las sincronizaciones.

## Añadir una cuenta

- Haz clic en **+** en la cabecera de la barra lateral.
- Elige un proveedor: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj o Personalizado (MinIO y cualquier otro endpoint compatible con S3).
- Introduce un nombre, la región o el endpoint y tus credenciales (clave de acceso y secreto; en Azure, la clave de la cuenta de almacenamiento).
- Haz clic en **Probar conexión** y luego en **Guardar**.

Tus credenciales se guardan en el llavero de macOS en este Mac. Bucketeer no tiene servidor ni cuenta de usuario; se comunica directamente con los endpoints que configures.

## Editar una cuenta

El secreto está oculto cuando editas una cuenta. Haz clic en **Revelar credenciales guardadas** y confirma con Touch ID o con la contraseña del Mac para verlo. Si guardas sin tocar el secreto, el secreto guardado no cambia.

## Explorar buckets y objetos

- Haz clic en una cuenta de la barra lateral para ver sus buckets.
- Haz doble clic en un bucket o una carpeta para abrirlo. Usa la barra de ruta o la flecha hacia arriba para volver.
- Selecciona un archivo para ver sus detalles y una previsualización con Quick Look en el panel derecho.
- Usa el campo de búsqueda para filtrar la carpeta actual.

## Subir y descargar

- **Subida**: haz clic en el botón de subida o pulsa **⌘U**. También puedes arrastrar archivos desde el Finder a la lista de objetos o sobre un bucket.
- **Descarga**: haz clic con el botón derecho en un archivo y elige **Descargar…**.
- Los archivos grandes se transfieren en partes paralelas. Una subida interrumpida se reanuda donde se detuvo.
- Todas las transferencias aparecen en **Transferencias** en la barra lateral, con el progreso y un botón para cancelar.
- En **Ajustes → Transferencias** puedes limitar el ancho de banda total.

## Abrir archivos en otras apps

- Haz doble clic en un archivo, o haz clic derecho y elige **Abrir**, para abrirlo en su app predeterminada. **Abrir con** muestra otras apps que pueden abrirlo; con **Otra…** eliges cualquier app.
- Bucketeer descarga el archivo en una carpeta temporal y lo vigila. Poco después de cada guardado, el archivo se vuelve a subir por la cola de transferencias normal, así que el cifrado del lado del cliente también se aplica.
- Si el objeto se modificó o se eliminó en el servidor después de abrirlo, Bucketeer no lo sobrescribe. Tu versión se sube a su lado como «nombre (conflict fecha).ext» y Bucketeer muestra un aviso.
- La copia temporal se elimina cuando cierras la app en la que la editaste, cuando cierras Bucketeer o en el siguiente inicio.

## Gestionar objetos

- **Nueva carpeta**: botón de la barra de herramientas o **⇧⌘N**.
- **Renombrar…**: haz clic con el botón derecho en un objeto. Renombrar es una copia en el servidor seguida de una eliminación.
- **Eliminar**: selecciona uno o varios objetos, haz clic en el botón de la papelera y confirma.
- **Copiar enlace profundo**: copia un enlace `bucketeer://` al objeto, que lo abre en Bucketeer desde cualquier lugar de tu Mac.

## Enlaces para compartir

Haz clic con el botón derecho en un archivo y elige **Obtener enlace para compartir…**. Elige cuánto tiempo es válido el enlace y luego cópialo o compártelo. El enlace se firma en tu Mac con tus credenciales; cualquiera que lo tenga puede descargar el archivo hasta que caduque.

## Versiones

Haz clic con el botón derecho en un archivo y elige **Mostrar versiones…** para ver su historial de versiones. Puedes restaurar una versión anterior como la nueva copia más reciente o eliminar una sola versión. El bucket necesita tener activado el control de versiones en el proveedor.

## Metadatos y etiquetas

Haz clic con el botón derecho en un archivo y elige **Metadatos y etiquetas…** para editar cabeceras HTTP (tipo de contenido, control de caché y otras), metadatos de usuario y etiquetas, y para ver la clase de almacenamiento. Algunos proveedores no admiten todos los campos; Bucketeer te avisa cuando es así.

**Ajustes → Reglas** contiene las reglas de etiquetado automático: añaden etiquetas y metadatos a las nuevas subidas que coincidan con un patrón de nombre de archivo o con un tipo MIME.

## Panel del bucket

Haz clic en **Panel** en la barra de herramientas de un bucket abierto. Muestra el número de objetos, el tamaño total, los objetos más grandes, una estimación aproximada del coste mensual y las reglas de ciclo de vida, la configuración CORS y la política del bucket (solo lectura).

## Papelera

Cuando eliminas objetos, Bucketeer puede conservar una copia local en este Mac (**Ajustes → Transferencias → Papelera**). Abre la papelera con **Ventana → Papelera** (**⇧⌘⌫**) y haz clic en **Restaurar** para volver a subir una copia en caché a su ubicación original. El objeto en el proveedor se elimina de inmediato; solo se puede restaurar la copia local. Las entradas se eliminan automáticamente tras el periodo de retención que definas.

## Registro de actividad

**Ventana → Registro de actividad** (**⌥⌘0**) muestra subidas, descargas, eliminaciones, sincronizaciones, enlaces para compartir y cambios de cuentas. Puedes filtrar, buscar y exportar la lista como CSV. Las entradas se conservan en este Mac durante 180 días.

## Cifrado del lado del cliente

En **Ajustes → Cifrado** puedes crear una clave para un bucket. A partir de entonces, cada subida a ese bucket se cifra en tu Mac (AES-256-GCM) antes de salir, y las descargas se descifran sobre la marcha. La clave se guarda en el llavero de macOS solo en este Mac.

Importante: si pierdes la clave, nadie puede descifrar esos objetos, ni siquiera nosotros. En esta versión de Bucketeer, los buckets cifrados no se pueden montar en el Finder.

## Spotlight

**Ajustes → Transferencias → Spotlight** está desactivado por omisión. Cuando lo activas, los nombres de los objetos que exploras se pueden buscar en Spotlight. El contenido de los archivos nunca se indexa y el índice se queda en este Mac.

## Atajos y Siri

Bucketeer añade acciones a la app Atajos: listar buckets, subir un archivo, crear un enlace para compartir y ejecutar una sincronización. Úsalas en tus propios atajos o pídeselo a Siri.

## Funciones Pro

Estas funciones requieren Bucketeer Pro:

- **Montar como unidad**: haz clic con el botón derecho en un bucket y elige **Montar como unidad** para usarlo en el Finder como un disco. Requiere macOS 14.1 o posterior. Las unidades montadas aparecen en **Unidades montadas** en la barra lateral; haz clic con el botón derecho para **Desmontar**. Los buckets con cifrado del lado del cliente no se pueden montar. Los cambios hechos en el servidor aparecen en el Finder cuando actualizas el bucket en Bucketeer. Si un archivo que editas en el Finder cambió mientras tanto en el servidor, tu versión se guarda a su lado como copia en conflicto.
- **Sincronizaciones**: en la sección **Sincronización**, crea una tarea que copie, mueva o refleje entre dos buckets, entre cuentas y proveedores, o entre una carpeta local y un bucket. Ejecútala manualmente, al abrir la app, cada N minutos o cuando cambie la carpeta local.
- **Carpetas vigiladas**: **Nueva carpeta vigilada…** sube a un bucket cada archivo nuevo de una carpeta local.
- **Copiar a otra cuenta…**: copia objetos a otra cuenta u otro proveedor. Cuando ambos lados lo permiten, la copia se hace en el servidor y los datos no pasan por tu Mac.
- **Modo barra de menús**: **Ajustes → General** mantiene Bucketeer en ejecución en la barra de menús para que las unidades y las sincronizaciones sigan activas cuando la ventana principal está cerrada.

Todo lo demás está disponible en el nivel gratuito.

## Bucketeer Pro, prueba y compra

Bucketeer Pro es una compra única dentro de la app a través del App Store, sin suscripción. Abre **Ajustes → Pro** o cualquier función Pro para ver el precio en tu moneda y comprarlo.

Puedes probar Bucketeer Pro gratis durante 14 días. Antes de empezar, la página de compra muestra la duración de la prueba, qué pasa después y el precio de Pro de por vida; luego haz clic en **Iniciar prueba**. Cuando termina la prueba, Bucketeer sigue en la versión gratuita y no se cobra nada. La prueba se puede iniciar una vez por Apple ID, y al restaurar las compras también vuelve una prueba en curso en otro Mac.

- **Restaurar compra** recupera Pro en otro Mac o tras reinstalar.
- **Canjear código** (macOS 15 o posterior) abre la hoja de Apple para códigos de oferta.

## Atajos de teclado

- **⌘U**: Subir archivos
- **⇧⌘N**: Nueva carpeta
- **⌥⌘0**: Registro de actividad
- **⇧⌘⌫**: Papelera
- **⌘?**: Ayuda de Bucketeer
- **⌘,**: Ajustes

## Privacidad

Bucketeer no recopila datos analíticos ni contiene rastreo. Tus cuentas, claves y registros se quedan en este Mac. El tráfico de red solo va a los proveedores de almacenamiento que configures y a Apple para las compras. Detalles: **Ayuda → Política de privacidad…**

## ¿Necesitas ayuda?

- Informar de un problema: **Ayuda → Informar de un problema…** o <https://support.apps.digitalfreedom.co.za/>
- Sitio web: <https://digitalfreedom.co.za>
