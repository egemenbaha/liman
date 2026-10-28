# Liman yayın, kurulum ve test sonuçları

28 Ekim 2026. Kullanıcı GitHub'da yayımlama, bu bilgisayara kurma ve tüm testleri çalıştırma talimatı verdi. Önceki yalnızca yerel çalışma kısıtı bu talimatla değişti.

## Yayın ve kurulum

- Herkese açık bağımsız kaynak fork'u: https://github.com/egemenbaha/liman. Ana dal `main`; başlangıç Nashi revizyonu `295c74f79f0313e89ad1542fe39e8fd4c64c88b2`. MIT telifi ve üçüncü taraf bildirimleri korunuyor.
- Bu Mac'e `/Applications/Liman.app` kuruldu ve uygulamanın karşılama ekranı açıldı. Apple Silicon için yerel ad-hoc imzalı derleme; Apple noter onayı veya yayıncı sertifikası yok. Sistem güvenliği/izinleri gevşetilmedi. Güncelleyici kapalı; yeni yayın anahtarı oluşturulmadı.
- SHA-256 doğrulamalı medya/ofis araçları `~/Library/Application Support/Liman/Tools` altına kuruldu. ExifTool uygulama paketinde. Kurulu uygulamanın çalıştırılabilir dosyası ile test edilen derleme birebir aynı: `5a024f4c48c35c2af6f91db5868adb27e427089d3e2019e833133af3b375349c`.
- GitHub'da kaynak yayımlandı; imzalı/noter onaylı ikili sürüm veya otomatik güncelleme kanalı yayımlanmadı. Yerel `upstream` push adresi `DISABLED`.

## Doğrulama

Aşağıdaki sayılar farklı kapsamlara aittir; iç içe kontroller olduğu için tek toplam olarak toplanmamalıdır.

| Kapsam | Sonuç |
| --- | --- |
| Tam Swift/XCTest regresyonları | Son CI başarılı: 294 senaryo, 0 hata; canlı hizmet bağlantısı gerektiren iki opt-in senaryo yapılandırılmadı. Bu ikisi başarı sayılmadığında 292 çevrimdışı/yerel regresyon geçti. |
| Çekirdek güvenlik kontrolleri | 86 çevrimdışı kontrol geçti: özel IP/DNS/redirect politikası, IP sabitleme argümanları, çıktı/byte sınırları, arşiv saldırıları, SHA-256 bozulması ve süreç sınırları. |
| Güncelleyici izolasyonu | 15 politika kontrolü geçti. Bu, gerçek imzalı sürüm kurulumu testi değildir. |
| Fork yapılandırması | 4 test geçti: kimlik, MIT/bildirimler, eski güven anahtarlarının temizlenmesi ve yayımlama yetkisi olmayan CI. |
| Kurulu macOS uygulaması | Yerelde kurulu uygulamada ve CI paketinde 13 kontrol geçti: imza/kimlik, 27 araç kataloğu, PNG/JPEG/PDF, ZIP ve zararlı ZIP geri alma, FFmpeg WAV→MP3, Office RTF→PDF ve araç konumları. |
| Yerel macOS arayüzü | Yerelde ve son CI'da 40 görüntü, 26 arayüz koruması, 30 aralık/düzenleme ve 11 dosya görseli kontrolü geçti; parser/çıktı kontrolleri dahil. |
| Windows referans uygulaması | Son CI dahil 1.327 çekirdek/medya kontrolü, 331 WPF/masaüstü kontrolü ve 40/40 arayüz görüntüsü geçti. Güvenlik yamalı bir Liman Windows dağıtımı değildir. |
| Miras web demosu | 41 tarayıcı testi, 0 hata; 45 girdi/275 dönüşüm yolu ve mobil görünüm dahil. Ayrı geometri/katalog denetimi geçti. Site yayımlanmadı. |
| Yardımcı kontroller | Yerelleştirme üretimi (2.123 anahtar), 5 sahip-otomasyon modeli ve 6 PR-politika modeli testi geçti. Model testleri gerçek PR birleştirmedi. |
| Gerçek internet aktarımı | İlk aşamada example.com HTTPS; bu turda gerçek YouTube görselini inceleme ve 1280×720 indirme başarılı. Çerez/hesap kullanılmadı. |
| Gizlilik ve bağımlılık incelemesi | Yayın öncesi kaynak sınırı denetimi ve 152 commit'lik ilk gitleaks taraması ve son değişikliklerin sır taraması temiz; önceki 16 OSV sorgusunda eşleşme yok. Eksiksiz güvenlik/bağımlılık garantisi değildir. |

Test kanıtları: [`audit/publication/`](audit/publication/). İlk CI: https://github.com/egemenbaha/liman/actions/runs/40671369907. Bu denemede Windows tamamlandı; macOS, uzun süren medya testlerini incelemek amacıyla durduruldu. Günlüklerde testlerin ilerlediği görüldü. İkinci CI dört ayrı test süreci ve XML raporuyla çalıştırıldı: https://github.com/egemenbaha/liman/actions/runs/40673035448 (kod revizyonu `c94d92163dc7b6831e8b8d250145e2817ebf5a70`). Tek hata iptal testinin sabit 300 ms bekleme varsayımıydı. Üretim davranışını değiştirmeden test artık ilk encoder ilerlemesinde iptal eder; yerel üç tekrarda kaynak korunması ve çıktı temizliği doğrulandı. Son tam çalışma: https://github.com/egemenbaha/liman/actions/runs/40674286227 (`1a3b28c20c6e11e675675cd6392aa8385c3b2b74`); macOS ve Windows test adımlarının tamamı başarılı. Son belge/kanıt commit'i uygulama veya test kodunu değiştirmez; aynı uzun paketler bu belge commit'i için tekrar çalıştırılmaz.

Web testi, ilk menüde seçim olmamasını ve kırpma alanı seçilmeden dışa aktarmanın kapalı olmasını yanlış varsayıyordu. İki beklenti düzeltildi; korumalar kaldırılmadan 41 test yeniden geçti. Uygulama paket testi kurulu uygulamayı `--app` ve gerçek araçları `--with-tools` ile sınayacak şekilde genişletildi.

## Açık sınırlar

- yt-dlp'nin kendi alt bağlantıları henüz zorunlu IP sabitleme/işletim sistemi ağ izolasyonu altında değil. Doğrudan indirmelerdeki koruma bütün indiriciye genellenemez.
- Windows testleri mevcut işlevlerin regresyon kanıtıdır; Windows'a macOS ağ güvenlik yamaları aktarılmadı.
- Canlı Instagram galerisi için doğrulanmış güncel test bağlantısı verilmedi; isteğe bağlı testin atlanması başarı sayılmaz. YouTube canlı senaryosu üretim çekirdeğiyle bu Mac'te ayrıca doğrulandı.
- Eski `test-web-download-integration.py` özellikle loopback sunucudan başarılı indirme bekler; bu artık güvenlik politikasına aykırıdır. Bu eski senaryo geçer diye raporlanmadı. Özel adres reddi ve yeni aktarım regresyonları ayrı güvenlik paketinde sınanır; eski iptal/ilerleme uçtan uca senaryolarının güvenli test düzeneğine taşınması açık iştir.
- Gerçek imzalı güncellemenin iyi/bozuk imza ile kurulması, Apple noter onayı, parser süreç izolasyonu ve bütün platformlarda bütün dış hizmetlerin çalışması doğrulanmadı. Üretime hazır güvenli sürüm iddiası yoktur.

Ayrıntılı tehdit modeli ve ilk bulgular: [SECURITY-AUDIT.tr.md](SECURITY-AUDIT.tr.md).
