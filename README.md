# DDTank VN — iOS App (.ipa)

Ứng dụng iOS native (`Swift + WKWebView`) chạy full-screen tràn viền cho **DDTank 4.1 Việt Nam** (hỗ trợ cả màn hình ngang/dọc, Ruffle WebAssembly, âm thanh tự động, và **chạm 3 ngón bất kỳ lúc nào** để đổi link Server nếu link Cloudflare Tunnel thay đổi).

## Cách tự build file `DDTankVN.ipa` miễn phí 100% (không cần máy Mac)
1. Tạo 1 repository mới trên [GitHub](https://github.com/new) (để **Public** để chạy miễn phí không giới hạn phút).
2. Upload toàn bộ file trong thư mục này (giữ nguyên thư mục `.github/workflows/build-ipa.yml`).
3. Vào tab **Actions** → chọn **Build DDTank VN iOS (.ipa)** → bấm **Run workflow** (có thể dán link Cloudflare Tunnel mới vào ô `server_url`).
4. Đợi ~2–3 phút → bấm vào mục **Artifacts → `DDTankVN-iOS-IPA`** để tải file **`DDTankVN.ipa`**.
5. Cài **`DDTankVN.ipa`** lên iPhone bằng **Sideloadly**, **AltStore**, **SideStore**, **ESign**, hoặc **TrollStore**.
