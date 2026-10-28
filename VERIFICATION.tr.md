# Liman yayın ve doğrulama durumu

28 Ekim 2026. Kullanıcı GitHub'da yayımlama, bu Mac'e kurma ve tüm testleri çalıştırma talimatı verdi.

Depo: https://github.com/egemenbaha/liman — herkese açık bağımsız fork. Üretim güvenliği iddiası yoktur; [bilinen güvenlik sınırları](SECURITY-AUDIT.tr.md) devam eder. Özellikle yt-dlp alt bağlantıları ve Windows ağ katmanı macOS doğrudan aktarım korumasıyla eşdeğer değildir.

## Bu turda doğrulananlar

- Yayın öncesi kaynak gizliliği kontrolü: 427 dosya, 45 girdi formatı ve 27 araç kataloğu doğrulandı.
- Git geçmişi ve çalışma farkı gitleaks ile tarandı; sır eşleşmesi bulunmadı.
- Yerel arayüz denetimi geçti: 40 ekran görüntüsü, 26 arayüz denetimi, 30 aralık/düzenleme kontrolü ve 11 dosya görseli kontrolü; parser/çıktı korumaları dahil. Kullanıcının gerçek dosyaları kullanılmadı.

## Devam eden doğrulama

Tam Swift paketi için bu Mac'te bulunmayan Xcode/XCTest, GitHub macOS ortamında kullanılacak. Windows derleme, çekirdek medya testleri ve WPF testleri Windows ortamında çalıştırılacak. Sabit checksum'lu medya ve ofis araçlarının kurulumu sürüyor. Sonuçlar tamamlandıkça bu dosya güncellenecek; henüz bütün testler geçmiş sayılmaz.

Bu çalışma özel yayın anahtarı oluşturmaz, sistem güvenliğini kapatmaz ve upstream uygulamanın imza kimliğini kullanmaz. Yerel uygulama ad-hoc imzalıdır.
