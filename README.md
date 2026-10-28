# Liman yerel güvenlik fork'u

Liman, [Nashi](https://github.com/orkunisitmak/nashi-app) kaynaklarından başlayan bağımsız bir yerel geliştirme fork'udur. Orkun Işıtmak, Nashi, Tangerine veya LEAP STUDIO tarafından yayımlanmaz ve desteklenmez. “Liman” bu çalışma için kullanılan geçici addır.

**Durum: ilk macOS güvenlik yamaları uygulanmış ve yerel testlerden geçmiştir; üretime hazır güvenli sürüm değildir.** Özellikle yt-dlp'nin alt bağlantıları ve Windows tarafı henüz aynı korumaya sahip değildir. Ayrıntılar ve kalan işler: [güvenlik denetimi](SECURITY-AUDIT.tr.md).

Başlangıç revizyonu: `295c74f79f0313e89ad1542fe39e8fd4c64c88b2` (Nashi 0.7.10). Yerel dal: `security/liman-local`. Kaynak deposu kullanıcı talimatıyla [egemenbaha/liman](https://github.com/egemenbaha/liman) altında herkese açık fork olarak oluşturuldu. Genişletilmiş test ve kurulum durumu [VERIFICATION.tr.md](VERIFICATION.tr.md) içinde izlenir. `upstream` uzak adresi yalnızca kaynak okumak için bırakıldı; push adresi `DISABLED` olarak ayarlandı. Bu bir yerel yanlışlık önlemidir, erişim kontrolü değildir.

## Neler değişti

- macOS doğrudan web indirmeleri, HEAD istekleri, görsel önizlemeleri ve uygulama içi araç indirmeleri ortak ağ denetiminden geçer. Özel/ayrılmış IPv4 ve IPv6 hedefleri reddedilir; tüm DNS cevapları denetlenir; bağlantı onaylanan IP'ye sabitlenir. Yönlendirmeler tek tek denetlenir, en fazla beş geçiş ve HTTPS düşürme yasağı uygulanır.
- Arşivlerde mevcut traversal, bağlantı ve toplam boyut kontrollerine açılma oranı, yol uzunluğu/derinliği ve kullanıcıya özel izinler eklendi.
- Alt süreçlere yalnızca gerekli ortam değişkenleri aktarılır; genel çalıştırıcıda çıktı belleği sınırlandı ve süre sınırı desteği eklendi.
- Ayrı uygulama kimliği, Liman simgesi ve veri klasörleri kullanılır. Global sürükleme/pencere kısayolları başlangıçta kapalıdır; ayarlardan açılabilir.
- Orijinal güncelleme kanalı ve güven anahtarı kaldırıldı; yerel fork'ta güncellemeler ve GitHub bağlantısı kapalıdır. İmzalı güncelleme doğrulama kodu korunur; yeni kanal ayrı anahtar ve testler olmadan etkinleştirilmez.

## Yerel derleme ve test

macOS, Apple Silicon ve Swift 6 gerekir. Standart `swift test` için tam Xcode/XCTest gereklidir; ek güvenlik kontrolleri Command Line Tools ile de çalışır.

```sh
swift build --product Liman
python3 scripts/test-liman-security.py
python3 scripts/test-liman-updates.py
python3 scripts/test-liman-configuration.py
# İsteğe bağlı, yalnızca example.com üzerinde gerçek HTTPS aktarım denemesi:
LIMAN_LIVE_TEST=1 python3 scripts/test-liman-security.py
```

Uygulama paketi hazırlama:

```sh
scripts/setup-exiftool.sh
NASHI_SIGNING_MODE=ad-hoc scripts/build-app.sh debug
python3 scripts/test-liman-app.py
```

Çıktı: `build/Liman.app`. Paket yerel ad-hoc imzalıdır; Apple noter onayı ve yayıncı kimliği yoktur. İlk paket yerel olarak oluşturulup doğrulandı; bilgisayara kurulumun güncel sonucu VERIFICATION.tr.md içindedir. Medya/ofis araçları paket içinde değildir. İlgili işlevler için uygulamanın araç kurulum ekranı veya uygun yerel araçlar gerekir.

Tam Xcode bulunan ortamda mevcut regresyon paketi:

```sh
swift test --filter 'ArchiveLinkBoundaryTests|ArchiveResourceLimitsTests|NashiUpdatesTests'
```

Bağımlılık danışma kaydı üretmek için `python3 scripts/audit-liman-dependencies.py` kullanılabilir. Bu komut yalnızca sabit paket adlarını/sürümlerini ve Sparkle commit'ini OSV'ye sorgular; paket kurmaz.

## Lisans ve kapsam

[MIT LICENSE](LICENSE) içindeki Orkun Işıtmak ve Nashi katkıcıları telifi değiştirilmeden korunmuştur ve uygulama paketine eklenir. [Üçüncü taraf bildirimleri](Resources/THIRD-PARTY-NOTICES.txt), `Resources/licenses/` ve Windows bildirimleri korunur. Harici araçların lisansları MIT olmak zorunda değildir.

İç Swift modül adları ve bazı eski arayüz/yerelleştirme metinleri upstream ile birleştirmeyi kolaylaştırmak için henüz Nashi adını taşır. Ana uygulama kimliği ve çalışma markası Liman'dır. Windows kaynakları bu turda incelenmiş upstream referansıdır; güvenlik yaması uygulanmış Liman Windows sürümü değildir.

Orijinal açıklamalar [upstream README](docs/UPSTREAM-README.md) içinde saklanır. Oradaki indirme, otomatik güncelleme ve yayın iddiaları Liman için geçerli değildir. Eski yayın/otomatik birleştirme iş akışları `.github/upstream-workflows/*.disabled` altında pasiftir. Yeni iş akışı yalnızca okuma izinleriyle tam macOS Swift ve Windows .NET/WPF testlerini çalıştırır. Otomatik yayımlama veya birleştirme yapmaz.
