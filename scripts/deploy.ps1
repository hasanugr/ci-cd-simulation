param(
    [string]$environment # "QA" veya "PROD" parametresi gelecek
)

# 1. Hata olursa scripti durdur
$ErrorActionPreference = "Stop"

Write-Host "🚀 Deploy baslatiliyor... Hedef: $environment" -ForegroundColor Green

# 2. Hedef Klasörü Belirle
$targetFolder = "C:\inetpub\wwwroot\Simulation_$environment"
Write-Host "📂 Hedef Klasor: $targetFolder"

# 3. Bağımlılıkları Yükle (Corepack enable diyerek pnpm'i garantiye alıyoruz)
Write-Host "📦 Bagimliliklar yukleniyor..."
cmd /c "corepack enable"
cmd /c "pnpm install --no-frozen-lockfile"

# 4. Projeyi Build Et
Write-Host "🔨 Build aliniyor..."
cmd /c "pnpm build"

# 5. Dosyaları Kopyala (Robocopy kullanıyoruz, Windows'un en hizli kopyalama aracidir)
Write-Host "🚚 Dosyalar kopyalaniyor..."

# Eğer klasör yoksa oluştur
if (!(Test-Path -Path $targetFolder)) {
    New-Item -ItemType Directory -Force -Path $targetFolder
}

# 'out' klasörünü hedef klasöre ayna (Mirror) gibi kopyala
# /MIR: Kaynakta olmayan dosyaları hedefte de siler (Temizlik yapar)
# /XD: .git gibi klasörleri hariç tutar
robocopy .\out $targetFolder /MIR /NFL /NDL /NJH /NJS /nc /ns /np

# Robocopy hata kodu 1 (başarılı kopyalama) dışındaysa uyarı ver ama scripti patlatma
if ($LASTEXITCODE -gt 7) {
    Write-Error "❌ Kopyalama sirasinda hata olustu. Robocopy Exit Code: $LASTEXITCODE"
    exit 1
}

Write-Host "✅ Deploy Basariyla Tamamlandi!" -ForegroundColor Cyan