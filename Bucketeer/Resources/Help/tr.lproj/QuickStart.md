# Bucketeer Yardım

Bucketeer, nesne depolama için bir Mac uygulamasıdır: Amazon S3, S3 uyumlu sağlayıcılar ve Azure Blob Storage. Bu kılavuz ilk hesaptan Finder sürücülerine ve eşitleme işlerine kadar tüm özellikleri anlatır.

## Hesap ekle

- Kenar çubuğu başlığındaki **+** düğmesini tıkla.
- Bir sağlayıcı seç: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj ya da Özel (MinIO ve diğer tüm S3 uyumlu uç noktalar).
- Bir ad, bölgeyi ya da uç noktayı ve kimlik bilgilerini gir (erişim anahtarı ve gizli anahtar; Azure için depolama hesabı anahtarı).
- Anahtarın yalnızca tek bir bucket'a erişebiliyorsa (Civo'da sık görülür), bucket'ın adını **Bucket** alanına gir; hesap bu durumda yalnızca o bucket'ı gösterir. Civo anahtarları yalnızca oluşturuldukları bölgede çalışır.
- **Bağlantıyı Sına**'yı, ardından **Kaydet**'i tıkla.

Kimlik bilgilerin bu Mac'te, macOS Anahtar Zinciri'nde saklanır. Bucketeer'ın sunucusu ve kullanıcı hesabı yoktur; doğrudan yapılandırdığın uç noktalarla konuşur.

## Hesabı düzenle

Bir hesabı düzenlerken gizli anahtar gizlenir. Görmek için **Kayıtlı kimlik bilgilerini göster**'i tıkla ve Touch ID ya da Mac parolanla onayla. Gizli anahtara dokunmadan kaydedersen kayıtlı anahtar değişmeden kalır.

## Bucket'ları ve nesneleri gez

- Bucket'larını listelemek için kenar çubuğunda bir hesabı tıkla.
- Bir bucket'ı ya da klasörü açmak için çift tıkla. Geri dönmek için yol çubuğunu ya da yukarı okunu kullan.
- Ayrıntılarını ve Hızlı Bakış önizlemesini sağdaki bölmede görmek için bir dosya seç.
- Geçerli klasörü süzmek için arama alanını kullan.

## Yükle ve indir

- **Yükle**: yükleme düğmesini tıkla ya da **⌘U** tuşlarına bas. Dosyaları Finder'dan nesne listesine ya da bir bucket'ın üzerine de sürükleyebilirsin.
- **İndir**: bir dosyayı sağ tıkla ve **İndir…**'i seç.
- Büyük dosyalar paralel parçalar hâlinde aktarılır. Yarıda kalan bir yükleme kaldığı yerden sürer.
- Tüm aktarımlar, ilerleme durumu ve iptal düğmesiyle birlikte kenar çubuğundaki **Aktarımlar** altında görünür.
- **Ayarlar → Aktarımlar** ile toplam bant genişliğini sınırlayabilirsin.

## Dosyaları başka uygulamalarda aç

- Bir dosyayı varsayılan uygulamasında açmak için çift tıkla ya da sağ tıklayıp **Aç**'ı seç. **Birlikte Aç**, dosyayı açabilen diğer uygulamaları listeler; **Diğer…** ile herhangi bir uygulamayı seçebilirsin.
- Bucketeer dosyayı geçici bir klasöre indirir ve izler. Her kaydetmeden kısa bir süre sonra dosya normal aktarım kuyruğu üzerinden geri yüklenir, böylece istemci tarafı şifreleme de uygulanır.
- Nesne, sen açtıktan sonra sunucuda değiştirildiyse ya da silindiyse Bucketeer onun üzerine yazmaz. Senin sürümün yanına "ad (çakışma tarihi).uzantı" olarak yüklenir ve Bucketeer bir ileti gösterir.
- Sunucu son kaydettiğin hâli aldıktan sonra geçici kopya silinir. Bir kaydetme yüklenemediyse (örneğin çevrimdışıyken), Bucketeer dosyayı bu Mac'te tutar ve **Yeniden Yükle**, **Kopyasını Kaydet…** ya da **Düzenlemeyi At** seçeneklerini sunar; bunu bir sonraki açılışta, örneğin bir çökmeden sonra da yapar.

## Nesneleri yönet

- **Yeni Klasör**: araç çubuğu düğmesi ya da **⇧⌘N**.
- **Yeniden Adlandır…**: bir nesneyi sağ tıkla. Yeniden adlandırma, sunucu tarafında bir kopyalama ve ardından bir silmedir. Bir klasörü yeniden adlandırmak ya da silmek içindeki her şeye uygulanır ve yeniden adlandırma hiçbir zaman var olan bir adın yerine geçmez.
- **Sil**: bir ya da daha fazla nesne seç, çöp sepeti düğmesini tıkla ve onayla.
- **Derin Bağlantıyı Kopyala**: nesneye giden bir `bucketeer://` bağlantısını kopyalar; bu bağlantı nesneyi Mac'inin her yerinden Bucketeer'da açar.

## Paylaşım bağlantıları

Bir dosyayı sağ tıkla ve **Paylaşım bağlantısı al…**'ı seç. Bağlantının ne kadar süre geçerli kalacağını seç, sonra kopyala ya da paylaş. Bağlantı, kimlik bilgilerinle senin Mac'inde imzalanır; bağlantıya sahip olan herkes, süresi dolana kadar dosyayı indirebilir.

## Sürümler

Bir dosyanın sürüm geçmişini görmek için dosyayı sağ tıkla ve **Sürümleri Göster…**'i seç. Eski bir sürümü yeni güncel kopya olarak geri yükleyebilir ya da tek bir sürümü silebilirsin. Bucket'ta sağlayıcı tarafında sürümleme açık olmalıdır.

## Meta veri ve etiketler

HTTP başlıklarını (içerik türü, önbellek denetimi ve diğerleri), kullanıcı meta verisini ve etiketleri düzenlemek ve depolama sınıfını görmek için bir dosyayı sağ tıkla ve **Meta Veri ve Etiketler…**'i seç. Bazı sağlayıcılar her alanı desteklemez; bu durumda Bucketeer sana bildirir.

**Ayarlar → Kurallar** otomatik etiketleme kurallarını içerir: bu kurallar, bir dosya adı deseniyle ya da bir MIME türüyle eşleşen yeni yüklemelere etiket ve meta veri ekler.

## Bucket panosu

Açık bir bucket'ın araç çubuğunda **Pano**'yu tıkla. Pano; nesne sayısını, toplam boyutu, en büyük nesneleri, kabaca bir aylık maliyet tahminini ve bucket'ın yaşam döngüsü kurallarını, CORS yapılandırmasını ve bucket politikasını (salt okunur) gösterir.

## Çöp sepeti

Nesneleri sildiğinde Bucketeer bu Mac'te yerel bir kopya tutabilir (**Ayarlar → Aktarımlar → Çöp Sepeti**). Çöp sepetini **Pencere → Çöp Sepeti** (**⇧⌘⌫**) ile aç ve önbellekteki bir kopyayı özgün yerine geri yüklemek için **Geri Yükle**'yi tıkla. Sağlayıcıdaki nesne hemen silinir; yalnızca yerel kopya geri yüklenebilir. Kayıtlar, belirlediğin saklama süresinden sonra otomatik olarak kaldırılır.

## Etkinlik günlüğü

**Pencere → Etkinlik Günlüğü** (**⌥⌘0**) yüklemeleri, indirmeleri, silmeleri, eşitleme çalıştırmalarını, paylaşım bağlantılarını ve hesap değişikliklerini listeler. Listeyi süzebilir, içinde arama yapabilir ve CSV olarak dışa aktarabilirsin. Kayıtlar bu Mac'te 180 gün saklanır.

## İstemci tarafı şifreleme

**Ayarlar → Şifreleme** içinde bir bucket için anahtar oluşturabilirsin. Bundan sonra o bucket'a yapılan her yükleme, Mac'inden çıkmadan önce şifrelenir (AES-256-GCM) ve indirmelerin şifresi anında çözülür. Anahtar yalnızca bu Mac'te, macOS Anahtar Zinciri'nde saklanır.

Yalnızca dosya içerikleri şifrelenir. Nesne adları, yollar ve boyutlar depolama sağlayıcın tarafından okunabilir kalır. Şifreli nesneler `application/octet-stream` olarak saklanır, böylece kayıtlı içerik türleri özgün dosya türünü ele vermez.

Önemli: anahtarı kaybedersen, biz dahil hiç kimse bu nesnelerin şifresini çözemez. Bucketeer'ın bu sürümünde şifreli bucket'lar Finder'da bağlanamaz.

## Spotlight

**Ayarlar → Aktarımlar → Spotlight** varsayılan olarak kapalıdır. Açtığında, gezdiğin nesnelerin adları Spotlight'ta aranabilir olur. Dosya içerikleri asla dizinlenmez ve dizin bu Mac'te kalır.

## Kestirmeler ve Siri

Bucketeer, Kestirmeler uygulamasına eylemler ekler: bucket'ları listele, dosya yükle, paylaşım bağlantısı oluştur ve eşitleme işi çalıştır. Bunları kendi kestirmelerinde kullan ya da Siri'ye sor.

## Pro özellikleri

Bu özellikler için Bucketeer Pro gerekir:

- **Sürücü Olarak Bağla**: bir bucket'ı Finder'da disk gibi kullanmak için sağ tıkla ve **Sürücü Olarak Bağla**'yı seç. Bağlı sürücüler kenar çubuğunda **Bağlı Sürücüler** altında görünür; **Bağlantıyı Kes** için sağ tıkla. İstemci tarafı şifreleme kullanan bucket'lar bağlanamaz. Sunucuda yapılan değişiklikler, bucket'ı Bucketeer'da yenilediğinde Finder'da görünür. Finder'da düzenlediğin bir dosya bu arada sunucuda değiştirildiyse, senin sürümün yanına çakışma kopyası olarak kaydedilir.
- **Eşitleme işleri**: **Eşitleme** bölümünde, iki bucket arasında (hesaplar ve sağlayıcılar arasında da) ya da yerel bir klasörle bir bucket arasında kopyalama, taşıma veya aynalama yapan bir iş oluştur. İşi elle, uygulama açılırken, N dakikada bir ya da yerel klasör değiştiğinde çalıştır. Yerel bir klasörden taşıma, her kaynak dosyayı kopyalandıktan sonra Çöp Sepeti'ne koyar; böylece son anda yapılan bir düzenleme asla kaybolmaz.
- **İzlenen klasörler**: **Yeni İzlenen Klasör…**, yerel bir klasöre gelen her yeni dosyayı bir bucket'a yükler.
- **Başka hesaba kopyala…**: nesneleri başka bir hesaba ya da sağlayıcıya kopyalar. İki taraf da izin verdiğinde kopyalama sunucu tarafında yapılır ve veriler Mac'inden geçmez.
- **Menü çubuğu modu**: **Ayarlar → Genel**, Bucketeer'ı menü çubuğunda çalışır tutar; böylece ana pencere kapalıyken de sürücüler ve eşitleme işleri etkin kalır.

Diğer her şey Ücretsiz pakette kullanılabilir.

## Bucketeer Pro, deneme ve satın alma

Bucketeer Pro, App Store üzerinden yapılan tek seferlik bir uygulama içi satın almadır; abonelik yoktur. Fiyatı kendi para biriminde görmek ve satın almak için **Ayarlar → Pro**'yu ya da herhangi bir Pro özelliğini aç.

Bucketeer Pro'yu 14 gün ücretsiz deneyebilirsin. Başlamadan önce satın alma ekranı denemenin süresini, sonrasında ne olacağını ve Ömür Boyu Pro'nun fiyatını gösterir; ardından **Denemeyi başlat**'ı tıkla. Deneme bittiğinde Bucketeer Ücretsiz paketle devam eder ve hiçbir ücret alınmaz. Deneme her Apple Kimliği için bir kez başlatılabilir; satın alımları geri yüklemek, süren bir denemeyi başka bir Mac'e de getirir.

- **Satın alımı geri yükle**, Pro'yu başka bir Mac'te ya da yeniden kurulumdan sonra geri getirir.
- **Kodu Kullan**, teklif kodları için Apple'ın penceresini açar.

## Klavye kestirmeleri

- **⌘U**: Dosya yükle
- **⇧⌘N**: Yeni klasör
- **⌥⌘0**: Etkinlik Günlüğü
- **⇧⌘⌫**: Çöp Sepeti
- **⌘?**: Bucketeer Yardım
- **⌘,**: Ayarlar

## Gizlilik

Bucketeer analiz verisi toplamaz ve hiçbir izleme içermez. Hesapların, anahtarların ve günlüklerin bu Mac'te kalır. Ağ trafiği yalnızca yapılandırdığın depolama sağlayıcılarına ve satın almalar için Apple'a gider. Ayrıntılar: **Yardım → Gizlilik Politikası…**

## Yardım mı lazım?

- Bir sorun bildir: **Yardım → Sorun Bildir…** ya da <https://support.apps.digitalfreedom.co.za/>
- Web sitesi: <https://digitalfreedom.co.za>
