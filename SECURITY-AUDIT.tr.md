# Liman ilk güvenlik denetimi

Bu rapor ilk yerel aşamanın kaydıdır. Sonraki GitHub yayını, kurulum ve kapsamlı test sonuçları [VERIFICATION.tr.md](VERIFICATION.tr.md) içinde güncellenir.

28 Ekim 2026. Temel kaynak: [orkunisitmak/nashi-app](https://github.com/orkunisitmak/nashi-app/tree/295c74f79f0313e89ad1542fe39e8fd4c64c88b2), revizyon `295c74f79f0313e89ad1542fe39e8fd4c64c88b2`.

**Yerel macOS fork'u ve ilk testli yamalar hazırdır. Bu çalışma tam güvenlik denetimi veya üretime hazır sürüm değildir.** Mevcut 27 araç kataloğu korunur; görüntü, PDF ve arşiv akışlarında örnek uygulama testleri geçti. Bütün araçların işlevsel eşdeğerliği doğrulanmadı. Windows için kaynak incelemesi yapıldı, yama ve çalışma zamanı testi yapılmadı.

## Doğrulanan sonuçlar

| Kontrol | Sonuç | Kanıt |
|---|---|---|
| Üretim çekirdeğini kullanan güvenlik kontrolleri | 86 çevrimdışı kontrol ve 1 gerçek HTTPS aktarımı geçti | `audit/security-checks.txt` |
| Üretim güncelleyicisi politika ve yapılandırma kontrolleri | 15 kontrol geçti | `audit/update-checks.txt` |
| Yapılandırma, telif ve iş akışı kontrolleri | 4 Python testi geçti | `audit/configuration-checks.txt` |
| Paketlenmiş uygulamanın yerel kontrolleri | 10 kontrol geçti | `audit/app-checks.txt` |
| Swift çekirdeği ve Liman uygulaması | Derlendi | `audit/build.txt`, `audit/package.txt` |
| Paket imzası | Yerel ad-hoc bütünlük denetimi geçti; yayıncı kimliği/noter onayı yok | `codesign --verify --deep --strict`, paket testleri |
| Standart upstream XCTest paketi | Çalıştırılamadı: ortamda XCTest yok | `audit/upstream-tests-blocked.txt` |
| Windows testleri ve NuGet restore | Çalıştırılmadı: .NET SDK yok | Kaynak/lockfile incelemesiyle sınırlı |
| GUI, gerçek sosyal medya, medya/ofis dönüşümleri | Uçtan uca doğrulanmadı | Uygulama arayüzü açılmadı; büyük runtime'lar indirilmedi |

Toplam 116 ek test/kontrol geçti. Bunlar tam upstream regresyon paketinin yerini almaz. Önceki sohbetin asistan yanıtı yalnızca içerik referansı olarak döndüğü için o incelemenin bulguları doğrulanmış kanıt kabul edilmedi.

## Uygulanan yamalar

### Web adresleri ve DNS rebinding

Başlangıç kodundaki macOS `WebDownloadEngine.link`, HTTP/HTTPS ve kullanıcı bilgisi kontrolleri yapıyor, özel ağ adreslerini engellemiyordu. İlk HEAD isteği otomatik yönlendirme yapan URLSession kullanıyordu. İndirme delegesi yönlendirmelerde yalnızca aynı sözdizimi kontrolünü tekrarlıyordu. Fotoğraf önizlemelerindeki SwiftUI `AsyncImage` de ayrı bir kontrolsüz yoldu.

`PublicWebPolicy.swift` IPv4 özel/loopback/link-local/CGNAT/ayrılmış aralıkları, IPv6 özel/yerel/mapped/transition aralıklarını, yerel adları, kimlik bilgisi ve zone-ID içeren URL'leri reddeder. Kısa/ondalık/sekizlik/onaltılık IPv4 gösterimleri de denetlenir. DNS cevabında tek bir yasak adres varsa tüm istek reddedilir. IPv6 özel amaçlı bazı global aralıklar ihtiyatlı biçimde engellenir.

`PublicWebTransfer.swift` her geçiş için yeni `/usr/bin/curl` süreci başlatır. `--resolve` doğrulanmış sayısal IP'yi sabitler; URL'nin asıl ana makine adı TLS sertifika doğrulaması için korunur. Proxy ve curl yapılandırması kapalıdır; otomatik yönlendirme, `--insecure` veya shell kullanılmaz. HTTP yönlendirmeleri uygulamada en fazla beş kez işlenir; her hedef yeniden doğrulanıp çözülür ve HTTPS→HTTP geçişi reddedilir. Bu tasarım [curl belgelerindeki bağlantı seçeneklerine](https://curl.se/docs/manpage.html) dayanır.

Başlıklar toplam 64 KiB ile sınırlıdır. Gövde sınırı, Content-Length olmasa da diske yazılmadan önce gerçek baytlar üzerinde uygulanır. Doğrudan medya sınırı 20 GiB, araç indirmeleri 400 MiB, önizlemeler 8 MiB'dir. TLS/HTTP hataları ve reddedilen HEAD yönlendirmeleri otomatik olarak yt-dlp'ye düşmez. Görsel önizlemeleri ve uygulama içi araç kurulumu da bu katmanı kullanır.

**Kalan sınır:** yt-dlp için ilk hedefin DNS ön kontrolü vardır; yt-dlp/ffmpeg/Deno'nun kendi sonraki bağlantıları bu IP sabitlemeli aktarımı kullanmaz. Bu nedenle sosyal medya indirmelerinde tam SSRF/DNS rebinding koruması sağlanmış değildir. Native araç ayrıştırıcıları da ağ/yerel dosya erişimi açısından ayrı tehdit modelidir. Proxy'nin kapatılması, yalnızca kurumsal proxy üzerinden internete çıkan ortamlarda bağlantıyı engelleyebilir. Sistem DNS çözümleme süresi uygulama tarafından ayrıca sınırlandırılmıyor.

### Arşiv traversal ve açılma sınırları

Mevcut libarchive katmanı mutlak yol, `..`, Windows sürücü yolu, özel dosya ve dışarı çıkan bağlantıları reddediyor; symlink ataları `lstat` ile kontrol ediyor; hard/symlink işlemlerini erteliyordu. Gerçek açılan baytlar için 20 GiB ve giriş sayısı için 100.000 sınırı zaten vardı. Bu kontroller korunmuştur.

Yeni sınırlar: 4.096 UTF-8 baytlık yol, 64 bileşenlik derinlik; toplam açılan veride `min(toplam sınır, max(16 MiB, sıkıştırılmış dosya boyutu × 1000))`. Sayaç diske yazmadan önce kontrol edilir, çarpım taşması yönetilir. Küçük çok sıkıştırılabilir belgeler için 16 MiB tolerans vardır; daha büyük olağan fakat çok yüksek sıkışmalı dosyalar reddedilebilir. Araç ZIP kurulumu ayrıca 1.000 giriş ve 512 MiB açılma sınırı kullanır.

Yeni klasörler `0700`, dosyalar en az sahip okuma/yazma izniyle oluşturulur. Arşivin grup/diğer kullanıcı izinleri aktarılmaz; sahibin çalıştırma biti korunur. Toplam boyut, oran, giriş sayısı, traversal ve mevcut symlink üzerine yazma kontrolleri gerçek arşivlerle denendi. Başarısız uygulama işlemi mevcut çıktıları ve orijinalleri koruyup staging alanını temizledi.

**Kalan sınır:** libarchive ayrıştırması aynı süreçtedir; bağımsız CPU, bellek ve süre kotası yoktur. Arşiv başlık/filtre ayrıştırıcı açıkları, tek C çağrısında uzun işlem ve aynı kullanıcı hesabındaki saldırgan süreçlerle yarışlar bu yamayla tamamen çözülmez. Windows arşiv katmanı için ayrı adversarial testler gerekir.

### Dış süreçler ve minimum izinler

Mevcut macOS işlemleri argv kullanıyor; shell üzerinden kullanıcı girdisi çalıştırmıyordu. Web indirme süreç grubu iptali ve ffmpeg/ffprobe yerel protokol listesi korunmuştur.

Yeni ortak ortam yalnızca HOME, USER, LOGNAME, TMPDIR, dil/saat değişkenlerini ve sabit sistem PATH'ini içerir. Ortamdaki bulut token'ları, proxy, Python ve dynamic-loader enjeksiyon değişkenleri çocuk sürece aktarılmaz. Güvenilir çağıranın açık ortam ekleri desteklenir. Standart giriş kapalıdır. Genel çalıştırıcı stdout için 64 MiB üst sınır, stderr için son 64 KiB tutma ve isteğe bağlı süre sınırı uygular. HTTP aktarımı bu API'nin akış çıkışını kullanır.

Global sürükleme ve pencere yönetimi varsayılanları kapalıdır; kullanıcı etkinleştirebilir. Bağımsız bundle kimliği, eski uygulamanın tercih/izin kimliğini kullanmaz. Yönetici/root işlemi veya sistem güvenliğini devre dışı bırakan komut çalıştırılmadı.

**Kalan sınır:** ana uygulama App Sandbox içinde değildir. Yalnızca klasör seçimini arayüzde sınırlandırmak işletim sistemi dosya erişim sınırı oluşturmaz. Genel ProcessRunner'ın süreç ağacı izolasyonu web çalıştırıcısı kadar güçlü değildir. Harici araçlara dosya bazlı izin, zorunlu ağ çıkış denetimi ve kaynak kotası sonraki mimari yamadır.

### Checksum, güncellemeler ve tedarik zinciri

Upstream'de uygulama içi araç kurulumu SHA-256 doğrulaması kullanıyordu. Bu denetim korunmuş, doğru `abc` vektörü ve değiştirilmiş içerikle test edilmiştir. ExifTool 13.59 arşivi sabit hash ile doğrulanarak yerel pakete eklenmiştir. FFmpeg/ffprobe paketinde doğrulama arşiv açıldıktan sonra ikili dosya üzerinde yapılır; tüm ZIP'in özgünlüğü ayrıştırmadan önce doğrulanmış değildir. Diğer sabit hash'lerin bağımsız yayıncı kaynağına karşı yeniden tasdiki bu turda tamamlanmadı.

Sparkle 2.10.0 commit'e sabittir. Upstream `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction` ve imza hatası zaman aşımını kapatan ayarlar içeriyordu. Bu gereklilikler [Sparkle güvenlik seçenekleriyle](https://sparkle-project.org/documentation/customization/) uyumludur ve korunur. Yerel fork'ta upstream feed ve Ed25519 güven anahtarı kaldırılmıştır. Güncelleyici varsayılan olarak ağ kontrolü, bağlantı kurma ve eski credential geri yükleme yapmaz. Yeni bir anahtar üretilmedi, Keychain'e yayın anahtarı yazılmadı.

Testler imza anahtarı biçimi, zorunlu doğrulama bayrakları ve güncelleyicinin kapalı kalmasını kapsar. Gerçek iyi/kötü imzalı Sparkle feed/uygulama arşivi yükleme testi yapılmadı; uygulama güncellemesi kurulmadı. Windows kodunda Ed25519 arşiv doğrulaması ve sürüm kontrolü görüldü; çalışma zamanı testi yapılmadı.

OSV toplu sorgusunda 11 sabit NuGet bileşeni, 3 npm bileşeni, yt-dlp PyPI sürümü ve Sparkle commit'i olmak üzere 16 sorgu için eşleşen kayıt dönmedi. [Ham kayıt](audit/dependency-advisories.json) sorgu zamanını, paketleri ve cevapları içerir. Bu sonuç danışma veritabanının kapsamadığı sürümleri, gömülü alt bileşenleri veya açıkları dışlamaz. Sistem curl/libarchive/framework'leri, FFmpeg, LibreOffice, ExifTool, Deno'nun tüm gömülü bağımlılıkları ve vendored JavaScript bağımlılık ağacı eksiksiz taranmış değildir. Sırf eşleşme yok diye bağımlılıkların güvenli olduğu veya güncel olduğu kabul edilmedi.

### Dosya gizliliği ve marka ayrımı

Ortak geçici alanlar ve staging alanları kullanıcıya özeldir. İndirilen dosyalar `0600`, yeni açılan klasörler `0700` ile başlar. Liman araçları `Application Support/Liman/Tools`, pano içeriği `Application Support/Liman/Imports` altında tutulur; eski Nashi klasörleri taşınmadı veya değiştirilmedi. Ana bundle kimliği `local.liman.filetoolkit`, ana ad ve yeni geometrik simge Liman'dır.

**Kalan sınır:** geçmişte dosya yolları ve pano içeriği kalıcı olarak saklanabilir. Otomatik saklama süresi, içerik şifreleme veya güvenli silme eklenmedi. Görsel/PDF metadata'sını bütün işlemlerde otomatik kaldırma yapılmadı; ilgili mevcut araçlar korunur. Aynı kullanıcı hesabındaki diğer süreçlere karşı klasör izinleri tek başına izolasyon sağlamaz. Bazı eski metin/yerelleştirme ve iç modül adları Nashi olarak kalır; Windows markası dönüştürülmedi.

MIT LICENSE ile ana telif ve üçüncü taraf bildirimleri değişmeden korunmuş, paket içine LICENSE kopyalanmıştır. Upstream açıklamaları `docs/UPSTREAM-*` altında saklanır. Fork'un upstream tarafından desteklendiği iddia edilmez. Büyük runtime'ların lisansları ayrı kalır.

## Öncelikli sonraki yamalar

1. **Yüksek öncelik:** yt-dlp ve alt süreçlerini zorunlu ağ sınırına almak. Yalnızca `--proxy` parametresi yeterli değildir; doğrudan çıkış da işletim sistemi düzeyinde engellenmeli. Playlist, fragment, redirect, DNS değişimi ve FFmpeg/Deno alt bağlantıları gerçek entegrasyon testleriyle denenmeli.
2. **Yüksek öncelik:** Windows HTTP/medya yolunu connection-time IP doğrulayan bir transport'a geçirmek; reparse point, arşiv ve güncelleme testlerini .NET/Windows üzerinde çalıştırmak. Mevcut `IsLoopback`/`.local` kontrolü tüm özel ağları kapsamaz.
3. **Yüksek öncelik:** tam Xcode üzerinde mevcut test paketi, GUI regresyonları ve tüm araç/format matrisi; mevcut ağ davranışı değişiklikleri için uyumluluk değerlendirmesi.
4. **Orta öncelik:** medya/ofis/arşiv parser'ları için süreç izolasyonu, kaynak kotaları; dependency SBOM ve platform danışma taraması; FFmpeg ZIP'ini açmadan önce arşiv checksum'u.
5. **Yayımdan önce:** marka metinlerinin tamamlanması, bağımsız güncelleme anahtarı ve feed, imza değiştirme/bozulma/rollback testleri, yayıncı imzası/noter onayı, lisans paketlemesi. GitHub depo oluşturma ve yayımlama için ayrıca kullanıcı talimatı gerekir.

## Yeniden çalıştırma

Komutlar README içinde verilmiştir. `scripts/test-liman-security.py` üretim `NashiCore` nesnelerini, `scripts/test-liman-updates.py` gerçek `NashiUpdates` modülünü ve sabit Sparkle framework'ünü kullanır; XCTest yerine sahte bir uygulama çekirdeği kullanılmaz. Ağsız DNS testlerinde resolver girdisi değiştirilebilir; üretim API'sinde özel IP'lere izin veren bir anahtar yoktur. Gerçek HTTPS testi isteğe bağlıdır ve example.com'a yapılır; kontrollü DNS sunucusuyla canlı rebinding saldırı testi yapılmış değildir.

Tüm değişiklikler yereldir; uzak depoya push, PR, release veya bildirim gönderilmedi. Uygulama `/Applications` içine kurulmadı ve GUI üzerinden izin istenmedi.
