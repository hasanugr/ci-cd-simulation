# CI/CD Pipeline Kurulum Kilavuzu

## DummyProject + IIS (iisnode) + GitHub Actions

**Son Guncelleme:** DD.MM.YYYY

> **Onemli Not:** Deploy script her release icin **timestamp ekler** (orn: `qa-v0.1.0.1-20260212-143022`).
> Bu sayede ayni version'dan birden fazla deploy yapilabilir ve kilitli dosya sorunlari onlenir.

---

## Yol Haritasi ve Ilerleme Durumu

### Proje Hazirlik (Local)

- [ ] Branch olusturma (dev, qa, main)

### Sunucu Hazirlik (Windows Server - RDP)

- [ ] Git kurulumu (runner icin gerekli)
- [ ] IIS + iisnode kontrol (WebSocket, Static Content)
- [ ] QA klasor izinleri (`C:\inetpub\wwwroot\[site-name]\qa`)
- [ ] PowerShell execution policy ayari
- [ ] `.env` dosyasinin sunucuda mevcut oldugunu dogrulama

### GitHub Hazirlik

- [ ] Workflow permissions (Read and write + Allow PR creation)
- [ ] Fine-Grained Personal Access Token olusturma
- [ ] Repository Secret ekleme (`BYPASS_TOKEN`)
- [ ] Self-hosted runner kurulumu (Servis modunda)
- [ ] `git config core.longPaths true` ayari (runner kurulduktan sonra)
- [ ] Branch Protection kurulumu

### CI/CD Test

- [ ] QA deploy testi (ilk yesil tik)
- [ ] Versiyon etiketleme kontrolu
- [ ] Rollback testi

### PROD (Ileride)

- [ ] PROD ortam yapilandirmasi
- [ ] PROD deploy testi
- [ ] Rollback testi

---

## Proje Bilgileri

| Bilgi                   | Deger                                                    |
| ----------------------- | -------------------------------------------------------- |
| **Framework**           | Next.js 14.2.33 (SSR - App Router)                       |
| **Node.js**             | >= 24.13.0                                               |
| **Paket Yoneticisi**    | npm                                                      |
| **IIS Yaklasimi**       | iisnode + custom server.js                               |
| **QA Releases Path**    | `C:\inetpub\wwwroot\[site-name]\qa-releases\<version>`   |
| **QA IIS Site**         | `qa`                                                     |
| **QA URL**              | `https://qa.site.net`                                    |
| **PROD Releases Path**  | `C:\inetpub\wwwroot\[site-name]\prod-releases\<version>` |
| **PROD IIS Site**       | `site.com`                                               |
| **PROD URL**            | `https://site.com`                                       |
| **Deploy Stratejisi**   | Versioned Release (blue-green)                           |
| **Version Format**      | `{env}-v{major}.{minor}.{patch}.{build}-{timestamp}`     |
| **Timestamp Format**    | `yyyyMMdd-HHmmss`                                        |
| **Keep Releases**       | 3 (son 3 release saklanir)                               |
| **Branch Akisi**        | dev -> qa -> main                                        |
| **QA Runner Label**     | `qa-server`                                              |
| **PROD Runner Label**   | `prod-server`                                            |
| **GitHub Environments** | `QA`, `PROD` (deployment history tracking)               |

**Not:** QA ve PROD ayri makinelerdedir. Her makineye kendi label'i ile runner kurulur. Workflow'lar dogru makineyi label uzerinden hedefler.

**Version Ornegi:**

- **Git Tag**: `qa-v0.1.7.2` (qa ortami, versiyon 0.1.7, 2. build)
- **IIS Klasor**: `qa-v0.1.7.2-20260212-143022` (12 Subat 2026 saat 14:30:22)
- **Fark**: Deploy script git tag'e timestamp ekler, boylece ayni tag birden fazla deploy edilebilir

### Deploy Stratejisi: Versioned Release

Proje SSR modunda calistigindan, IIS uzerinde iisnode ile `server.js` calistirilir.
**Versioned Release** yaklasimi kullanilir: her deploy yeni bir versiyon klasoru olusturur,
IIS'in fiziksel yolu bu yeni klasore yonlendirilir, eski klasorler temizlenir.

Bu yaklasim, native DLL dosyalarinin (sharp vb.) iisnode tarafindan kilitlenmesi sorununu
tamamen ortadan kaldirir — yeni klasorde kilitli dosya olmaz.

```
PHASE 0: PRE-BUILD (Env Setup)
  - "qa-releases/config/.env" dosyasi workspace'e kopyalanir
  - Bu sayede NEXT_PUBLIC_ degiskenleri build sirasinda koda gomulebilir

PHASE 1: BUILD (Kesinti yok - mevcut site acik)
  - npm install (runner workspace icinde)
  - npm run build (.next klasoru olusur)

PHASE 2: PREPARE RELEASE FOLDER (Kesinti yok - site hala acik)
  - Yeni versiyon klasoru olusturulur (orn: qa-releases/qa-v0.1.0.3-20260212-143022)
  - Runtime dosyalari kopyalanir (server.js, .next, public, package files)
  - .env dosyası workspace'ten (Phase 0'da gelen) alınır.
  - web.config varsa aktif siteden, yoksa central config'den alınır.
  - npm install --omit=dev --ignore-scripts ile production bagimliliklari kurulur

PHASE 3: IIS PATH SWAP (Minimum kesinti < 2 saniye)
  - IIS site durdurulur (sadece qa.site.net, genel IIS degil)
  - IIS fiziksel yol (physicalPath) yeni klasore yonlendirilir
  - IIS site baslatilir

PHASE 4: CLEANUP
  - Son 3 release saklanir, eski klasorler silinir
```

**Avantajlar:**

- DLL lock problemi **YOK** (yeni klasor = kilitli dosya yok)
- Minimum downtime (yalnizca IIS path switch aninda, < 2 saniye)
- Anlik rollback imkani (eski klasor hala mevcut)
- Diger uygulamalara **sifir etki** (process kill yok)

### Config Dosyalarinin Yonetimi

Build ve Runtime sirasinda ihtiyac duyulan `.env` ve `web.config` dosyalari, sunucuda sabit bir klasorde tutulur.
Deploy scripti her calistiginda dosyalari **qa/prod-release altindaki config** klasorunden alir.

| Dosya        | Aciklama                                      | Kaynak Onceligi                                                |
| ------------ | --------------------------------------------- | -------------------------------------------------------------- |
| `.env`       | Ortam degiskenleri (API URL, secret key, vb.) | 1. `config/.env` (Phase 0'da workspace'e) → 2. Release klasoru |
| `web.config` | IIS + iisnode yapilandirmasi                  | 1. Aktif IIS path → 2. `config/web.config` → 3. Atla           |

**Config Dosyalari Akisi:**

1. **Phase 0**: `.env` dosyasi `{env}-releases/config/.env` yolundan workspace root'a kopyalanir (build icin gerekli)
2. **Phase 2**:
   - `.env` workspace'ten (Phase 0'da gelen) yeni release klasorune kopyalanir
   - `web.config` once aktif IIS fiziksel yolundan alinmaya calisilir (mevcut ayarlari korumak icin)
   - Aktif site yoksa (ilk deploy) `config/web.config` kullanilir
   - Her ikisi de yoksa skip edilir (web.config proje icinde varsa git'ten gelir)

---

## 1. On Gereksinimler ve Sunucu Ayarlari

### A. Git Kurulumu (Sunucu)

Runner'in calismasi icin sunucuda Git kurulu olmalidir.

1. https://git-scm.com/download/win adresinden Git for Windows indirin
2. Kurulumu varsayilan ayarlarla tamamlayin
3. Kurulum sonrasi PowerShell'i kapatip acin
4. Dogrulayin:

```powershell
git --version   # git version 2.x.x gelmeli
```

5. Long path sorununu onleyin (Yonetici PowerShell):

```powershell
git config --system core.longPaths true
```

### B. IIS Klasor Izinleri

Runner servis hesabinin (veya `Users` grubunun) release klasorlerine yazma izni olmali:

```
C:\inetpub\wwwroot\[site-name]\qa-releases  -> Users grubuna Modify izni
C:\inetpub\wwwroot\[site-name]\prod-releases -> Users grubuna Modify izni (PROD kurulumunda)
```

> **Not:** Bu klasorler ilk deploy'da script tarafindan otomatik olusturulur.
> Ancak ust klasor (`C:\inetpub\wwwroot\[site-name]`) uzerinde yazma izni olmalidir.

**Adimlar:**

1. `C:\inetpub\wwwroot\[site-name]` klasorune sag tikla > Properties > Security tab
2. Edit > Add > `Users` yaz > Check Names > OK
3. `Modify` kutucugunu isaretle > Apply > OK
4. Alt klasorlere otomatik inherit eder

### C. IIS Ozellikleri ve iisnode

Sunucuda asagidaki IIS ozelliklerinin aktif oldugunu dogrulayin:

- **Common HTTP Features > Static Content** (Zorunlu)
- **Application Development Features > WebSocket Protocol** (Onerilen)
- **iisnode** modulu kurulu olmali (Node.js'i IIS uzerinde calistirmak icin)

**Kontrol:**

- IIS Manager > Sites > `qa` sitesinin mevcut QA klasorune isaret ettigini dogrulayin
  (ilk deploy sonrasi IIS otomatik olarak `qa-releases\qa-v0.1.0.X-YYYYMMDD-HHMMSS` klasorune yonlendirilir)
- Site bindings'de dogru hostname/port ayarlarini kontrol edin (orn: qa.site.net)
- Handler Mappings'de `iisnode` handler'in `server.js` icin tanimli oldugunu dogrulayin

**iisnode Kontrol (Opsiyonel - Sadece Okuma Yapar):**

Bu komutlar sadece iisnode'un kurulu olup olmadigini **kontrol eder**, hicbir ayari degistirmez ve calisan uygulamalari etkilemez. Yonetici PowerShell'e yapistiriniz:

```powershell
# Yontem 1: iisnode handler tanimli mi?
Get-WebHandler -Name "iisnode" -ErrorAction SilentlyContinue
# Sonuc donerse iisnode aktif demektir. Hata veya bos donerse kurulu degil.

# Yontem 2: iisnode dosyasi mevcut mu?
Test-Path "$env:ProgramFiles\iisnode\iisnode.dll"
# True donerse kurulu, False donerse kurulu degil.
```

**Not:** Proje zaten IIS uzerinde iisnode ile calisiyor, buyuk ihtimalle her iki komut da olumlu sonuc donecektir. Bu adim sadece dogrulama icindir, atlanabilir.

### D. PowerShell Izinleri

Windows varsayilan olarak PowerShell script calistirmayi engeller. Deploy scriptimizin calisabilmesi icin bu izni acmamiz gerekir.

**Yonetici PowerShell** acin (sag tik > Run as Administrator) ve asagidaki komutu yapistiriniz:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

Onay sorusu gelecektir:

```
Execution Policy Change
Do you want to change the execution policy?
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help
```

**`A` (Yes to All)** yazip Enter'a basin.

**Ne yapar:** Sadece internetten indirilen imzasiz scriptlerin calismasini engeller. Lokalde olusturulan scriptler (bizim deploy.ps1 gibi) sorunsuz calisir.

### E. Node.js Kontrolu

Sunucuda Node.js 24.x kurulu olmali:

```powershell
node --version   # v20.20.x (LTS) veya uzeri olmali (v24.13.0 (LTS) tavsiye edilir)
npm --version    # npm versiyonu
```

**Onemli:** `web.config` icindeki `nodeProcessCommandLine` Node.js yolunu isaret eder:

```xml
nodeProcessCommandLine="&quot;%programfiles%\nodejs\node.exe&quot;"
```

Bu yolun gecerli oldugunu dogrulayin.

### F. GitHub Workflow Izinleri

GitHub Actions'in PR olusturup merge edebilmesi icin:

1. **Repo Settings** > **Actions** > **General**
2. Sayfanin en altina scroll: **"Workflow permissions"**
3. **Read and write permissions** sec
4. **Allow GitHub Actions to create and approve pull requests** kutucugunu isaretle
5. **Save**

### G. Fine-Grained Personal Access Token Olusturma

Branch protection kurallarini bypass edebilmek icin admin yetkisine sahip bir token gerekir.

**Adimlar:**

1. **GitHub Profil** > **Settings** > **Developer settings** > **Personal access tokens** > **Fine-grained tokens**
2. **Generate new token**
3. **Ayarlar:**
   - **Name:** `BYPASS_TOKEN_DUMMYPROJECT` (veya istediginiz isim)
   - **Expiration:** `90 days` (duzenli yenileme oneriler)
   - **Repository access:** `Only select repositories` > Ilgili repo'yu secin
4. **Repository Permissions:**
   - **Contents:** `Read and write` (Merge, push, tag icin)
   - **Metadata:** `Read-only` (Otomatik gelir)
5. **Generate token** > Token'i kopyalayin (tekrar gosterilmez!)
6. **Repo Settings** > **Secrets and variables** > **Actions** > **New repository secret**
   - **Name:** `BYPASS_TOKEN`
   - **Secret:** Kopyaladiginiz token
   - **Add secret**

**Not:** Token suresi dolunca yenisini olusturup secret'i guncellemelisiniz.

### H. Config Klasorunun Olusturulmasi (Merkezi Yapi)

Deploy scriptinin `.env` dosyasini bulabilmesi icin releases klasoru icinde sabit bir `config` klasoru olusturmaniz gerekir.

**QA Icin Adimlar:**

1. Klasoru olusturun:
   `C:\inetpub\wwwroot\[site-name]\qa-releases\config`

2. Calisan `.env` dosyanizi bu klasore kopyalayin.

3. Calisan `web.config` dosyanizi bu klasore kopyalayin.

**Klasor Yapisi Soyle Gorunmeli:**

```text
C:\inetpub\wwwroot\[site-name]\qa-releases\
    ├── config\
    │     ├── .env
    │     └── web.config
    ├── qa-v0.1.0.1-20260210-120000\ (varsa eski versiyonlar)
    ├── qa-v0.1.0.2-20260211-150000\ (varsa)
    └── ...
```

> **Uyari:** Bu klasorun olmamasi durumunda deploy islemi "Phase 0" asamasinda hata vererek durur.

### I. GitHub Self-Hosted Runner Kurulumu (Servis Modu)

Runner, IIS sunucusunda Windows Servisi olarak calisir. Sunucu yeniden basladiginda otomatik baslar.

**Her iki sunucuya da (QA ve PROD) ayri ayri runner kurulmalidir.**

> **Not:** Runner'in calisma klasoru (`_work`) build dosyalarini icerir.
> Deploy scripti bu workspace'teki build ciktisini yeni release klasorune kopyalar.

GitHub sayfasindaki adimlari takip edin:
**Repo > Settings > Actions > Runners > New self-hosted runner > Windows / x64**

#### Download

GitHub sayfasinda `mkdir actions-runner; cd actions-runner` komutuyla klasor olusturmanizi ister.
Biz proje bazli isimlendirme kullandigimiz icin bu ilk adimi atlayip kendi klasorumuzu olusturuyoruz:

```powershell
# Proje bazli klasor olustur (ayni makinede birden fazla proje runner'i olacaksa karismaz)
mkdir C:\actions-runner-site; cd C:\actions-runner-site
```

Sonraki download ve extract komutlarini GitHub sayfasindan oldugu gibi kopyalayip calistirin:

```powershell
# Runner paketini indir (versiyonu GitHub sayfasindan kopyalayin, asagidaki ornektir)
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-win-x64-2.331.0.zip -OutFile actions-runner-win-x64-2.331.0.zip
```

```powershell
# Opsiyonel: Hash dogrulamasi (GitHub sayfasindaki hash ile karsilastirin)
if((Get-FileHash -Path actions-runner-win-x64-2.331.0.zip -Algorithm SHA256).Hash.ToUpper() -ne 'GITHUB_SAYFASINDAKI_HASH'.ToUpper()){ throw 'Computed checksum did not match' }
```

```powershell
# Arsivden cikart
Add-Type -AssemblyName System.IO.Compression.FileSystem ;
[System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD/actions-runner-win-x64-2.331.0.zip", "$PWD")
```

> **Not:** Versiyon numaralari ve hash degerleri zamanla degisir. Her zaman GitHub sayfasindaki guncel komutlari kopyalayin.

#### Configure

```cmd
# Runner'i yapilandir (GitHub sayfasindaki --url ve --token degerlerini kopyalayin)
.\config.cmd --url https://github.com/<ORG_NAME>/<REPO_NAME> --token GITHUB_SAYFASINDAKI_TOKEN
```

Konfigurasyon sirasinda interaktif sorular sorulacak:

| Soru              | QA Sunucusu                | PROD Sunucusu              |
| ----------------- | -------------------------- | -------------------------- |
| Runner group      | Enter (varsayilan)         | Enter (varsayilan)         |
| Runner name       | `QA-Deployer`              | `PROD-Deployer`            |
| Additional labels | `qa-server`                | `prod-server`              |
| Work folder       | Enter (varsayilan `_work`) | Enter (varsayilan `_work`) |
| Run as service?   | **Y** (Evet)               | **Y** (Evet)               |
| Service account   | Enter (varsayilan)         | Enter (varsayilan)         |

> **Kritik:** Label degerleri workflow dosyalarindaki `runs-on: [self-hosted, qa-server]` ile birebir esmeli!

> **Servis sorusu:** Son adimda `Would you like to run the runner as service? (Y/N)` diye sorar — **Y** deyin. Bu, runner'i otomatik olarak Windows Servisi kaydeder ve baslatir. Sunucu restart olsa bile runner otomatik ayaga kalkar. `run.cmd` kullanmayin — terminali kapatinca runner durur.

#### Dogrulama

1. **Sunucuda:** `services.msc` > "GitHub Actions Runner (...)" bul
   - Status: **Running**
   - Startup Type: **Automatic**
2. **GitHub'da:** Repo > Settings > Actions > Runners — runner **Idle** durumda gorunmeli

#### Runner Servis Hesabi Yetki Ayari

Runner bir Windows Servisi olarak calisir ve belirli bir kullanici hesabi altinda islem yapar (varsayilan: `Network Service`).
Deploy sirasinda runner su islemleri yapar:

- Dosyalari hedef klasore kopyalar (klasor yazma izni gerekir)
- `appcmd` ile IIS sitesini durdurup baslatir (IIS yonetim yetkisi gerekir)

`appcmd` komutu IIS konfigurasyon dosyalarini (`redirection.config` vb.) okumak icin **Administrators** grubunda olmak ister.
Klasor izni tek basina yetmez — IIS site yonetimi icin de yetki sart. Bu yuzden servis hesabini Administrators grubuna ekliyoruz.

**Yonetici PowerShell acin ve su komutlari calistirin:**

```powershell
# Runner servis hesabini Administrators grubuna ekle
net localgroup Administrators "NT AUTHORITY\NETWORK SERVICE" /add

# Runner servisini yeniden baslat (degisiklik etkili olsun)
Restart-Service *actions*
```

**Dogrulama:**

```powershell
# Hesabin grupta olup olmadigini kontrol edin
net localgroup Administrators
# Listede "NT AUTHORITY\NETWORK SERVICE" gorunmeli
```

> **Not:** Servis hesabi farkli olabilir. `services.msc` > "GitHub Actions Runner (...)" > **Log On** sekmesinden kontrol edin.
> Eger farkli bir hesap goruyorsaniz, o hesabi ekleyin.

---

## 2. Proje Yapilandirmasi

### A. server.js & web.config

**server.js** - Custom Node.js HTTP sunucusu:

```javascript
// iisnode bu dosyayi calistirir
// PORT env degiskeni iisnode tarafindan otomatik ayarlanir (named pipe)
const port = process.env.PORT || 3000;
```

**web.config** - IIS + iisnode yapilandirmasi:

- iisnode handler `server.js`'i calistirir
- URL rewrite kurallari tum istekleri server.js'e yonlendirir
- Static content MIME type tanimlari mevcut
- **Bu dosya deploy sirasinda DEGISMEZ** (sunucuda ortama ozel kalir)

### B. .env Dosyalari

Sunucudaki `.env` dosyasi su degiskenleri icermelidir:

```dotenv
NODE_ENV=production
NEXT_PUBLIC_SITE_URL=https://qa.site.net
NEXT_PUBLIC_API_URL=https://qa-api.site.net   # QA API adresi
...
```

**Onemli:** `.env` dosyasi deploy sirasinda uzerine yazilmaz. Ilk kurulumda elle olusturulmalidir.

---

## 3. Otomasyon Dosyalari

Tum dosyalar proje icinde olusturulmustur:

```
DummyProject/
  scripts/
    deploy.ps1                    # PowerShell deploy scripti
  .github/
    workflows/
      deploy-qa.yml               # QA deploy workflow
      deploy-prod.yml             # PROD deploy workflow
      rollback-prod.yml           # PROD rollback workflow (QA rollback yok)
```

### A. Deploy Script (`scripts/deploy.ps1`)

Bu script **Versioned Release** yaklasimi ile deploy eder.
Her deploy yeni bir versiyon klasoru olusturur, IIS path swap ile yayinlar.

**Script Parametreleri ve Ayarlari:**

| Parametre/Ayar        | Deger                              | Aciklama                                   |
| --------------------- | ---------------------------------- | ------------------------------------------ |
| `-environment`        | `qa` veya `prod`                   | Deployment ortami (zorunlu parametre)      |
| `$env:FULL_VERSION`   | `{env}-v{X.Y.Z.B}`                 | Git tag (workflow tarafindan set edilir)   |
| `$timestamp`          | `yyyyMMdd-HHmmss`                  | Script tarafindan otomatik generate edilir |
| `$uniqueVersionName`  | `{FULL_VERSION}-{timestamp}`       | Final klasor adi                           |
| `$keepReleases`       | `3`                                | Saklanacak eski release sayisi             |
| `$appcmd`             | `C:\Windows\System32\...\...`      | IIS yonetim araci                          |
| QA `ReleasesFolder`   | `C:\...\[site-name]\qa-releases`   | QA release'lerin tutuldugu klasor          |
| QA `SiteName`         | `qa`                               | IIS site adi (QA)                          |
| PROD `ReleasesFolder` | `C:\...\[site-name]\prod-releases` | PROD release'lerin tutuldugu klasor        |
| PROD `SiteName`       | `site.com`                         | IIS site adi (PROD)                        |

**Hata Yonetimi:**

- `ErrorActionPreference = "Stop"` — Herhangi bir hata deploy'u durdurur
- npm komutlarinda `ErrorActionPreference = "Continue"` (stderr warn mesajlari hata sayilmaz)
- Basarili bitis: `exit 0` — Hata durumunda: `exit 1`

**Fazlar:**

0. **PHASE 0: PRE-BUILD** — `.env` dosyasini central config'den workspace'e kopyala (build oncesi gerekli)
1. **PHASE 1: BUILD** — `npm install` + `npm run build` (runner workspace, site acik)
2. **PHASE 2: PREPARE** — Yeni timestamped klasor olustur, runtime dosyalarini kopyala, `npm install --omit=dev --ignore-scripts` calistir
3. **PHASE 3: SWAP** — IIS stop > physicalPath degistir > IIS start (< 2 saniye kesinti)
4. **PHASE 4: CLEANUP** — CreationTime'a gore siralama, son 3 release saklanir, eski klasorler silinir (config klasoru exclude edilir)

**Kullanim:**

```powershell
# Gerekli: FULL_VERSION env var (workflow tarafindan set edilir)
# NOT: Timestamp deploy script tarafindan otomatik eklenir
$env:FULL_VERSION = "qa-v0.1.0.1"
.\scripts\deploy.ps1 -environment "qa"
# Sonuc: C:\inetpub\wwwroot\[site-name]\qa-releases\qa-v0.1.0.1-20260212-143022\

.\scripts\deploy.ps1 -environment "prod"
```

**Klasor Yapisi:**

```
C:\inetpub\wwwroot\[site-name]\
  qa-releases\              # QA release'leri
    config\                 # Merkezi config klasoru (.env, web.config)
    qa-v0.1.0.1-20260210-120000\   # Eski release (temizlenecek)
    qa-v0.1.0.2-20260211-150000\   # Onceki release
    qa-v0.1.0.3-20260212-143022\   # <-- IIS su an buraya bakar
  prod-releases\            # PROD release'leri
    config\                 # Merkezi config klasoru
    prod-v0.1.0.1-20260212-160000\ # <-- IIS su an buraya bakar
```

**Kopyalanan Runtime Dosyalari (workspace -> release folder):**

- `server.js` — iisnode giris noktasi
- `package.json`, `package-lock.json` — npm install icin
- `next.config.js` — Next.js runtime config
- `.next/` — derlenenmis build ciktisi (**cache klasoru exclude edilir - robocopy /XD cache**)
- `public/` — statik dosyalar (images, icons, robots vs.)
- `.env` — workspace'teki .env (Phase 0'da central config'den gelen)

**Kopyalanmayan (build-time only, runtime'da gerekmez):**

- `src/` — kaynak kod (zaten .next icinde derlenmis)
- `node_modules/` — release klasorunde tekrar kurulur
- `tsconfig.json`, `tailwind.config.ts`, `postcss.config.js` — derleme araclari

**NPM Install Flags:**

- `--omit=dev` — Sadece production bagimliliklari kurulur (devDependencies atlanir)
- `--ignore-scripts` — postinstall/prepare scriptleri atlanir (git config, husky vb. hata vermez)

**IIS Site Yonetimi:**

- `appcmd list site /site.name:"qa" /text:state` — Site durumunu kontrol eder (Started/Stopped)
- `appcmd stop site /site.name:"qa"` — Sadece bu siteyi durdurur (eger zaten Started ise)
- `appcmd set vdir /vdir.name:"qa/" /physicalPath:"yeni-yol"` — Fiziksel yolu degistirir
- `appcmd start site /site.name:"qa"` — Siteyi baslatir
- Genel IIS servisi ETKILENMEZ, diger siteler calismaya devam eder

**Onemli:** Runner servis hesabinin IIS yonetim yetkisi olmali (`Administrators` grubunda), yoksa appcmd komutlari hata verir.

### B. QA Workflow (`.github/workflows/deploy-qa.yml`)

**Tetikleme:** Manuel (`workflow_dispatch`)
**Akis:** DEV -> QA branch merge + Build + Deploy + Tag

**Versiyon Hesaplama Mantigi:**

1. `package.json`'dan app version okunur (orn: `0.1.7`)
2. Mevcut `qa-v0.1.7.*` tagları sayilir
3. En yuksek build numarasi bulunur ve +1 artirilir
4. Final tag: `qa-v{app_version}.{build_number}` (orn: `qa-v0.1.7.3`)
5. Deploy script bu tag'e timestamp ekler (klasor: `qa-v0.1.7.3-20260212-143022`)

Adimlar:

1. QA branch checkout (BYPASS_TOKEN ile)
2. DEV branch'ini QA'ya merge (`--allow-unrelated-histories --no-edit`)
3. Versiyon hesaplama (yukaridaki mantik)
4. Merge commit'i version bilgisiyle amend et ve push
5. Node.js 24 setup
6. Deploy script calistir (timestamp otomatik eklenir)
7. Git tag olustur ve push (orn: `qa-v0.1.0.1`)
8. Ozet raporu (GitHub Actions summary)

### C. PROD Workflow (`.github/workflows/deploy-prod.yml`)

**Tetikleme:** Manuel (`workflow_dispatch`)
**Akis:** QA -> MAIN branch merge + Build + Deploy + Tag

**Versiyon Turemi:**

1. Tum `qa-v*` taglari semantik versiyona gore siralanir
2. En yeni QA tag'i secilir (orn: `qa-v0.1.7.2`)
3. PROD tag'i QA tag'inden turetilir: `qa-v0.1.7.2` → `prod-v0.1.7.2`
4. Deploy script bu tag'e timestamp ekler (klasor: `prod-v0.1.7.2-20260212-160000`)

Adimlar:

1. MAIN branch checkout (BYPASS_TOKEN ile)
2. Son QA tag'inden versiyon oku (yukaridaki mantik)
3. QA branch'ini MAIN'e merge (`--allow-unrelated-histories --no-edit`)
4. Merge commit'i version bilgisiyle push
5. Node.js 24 setup
6. Deploy script calistir (timestamp otomatik eklenir)
7. PROD tag olustur ve push (orn: `prod-v0.1.0.1`)
8. Ozet raporu (GitHub Actions summary)

### D. Rollback Workflow (`.github/workflows/rollback-prod.yml`)

**Tetikleme:** Manuel (`workflow_dispatch` + onay kutusu)

**Rollback Modlari:**

1. **AUTO_PREVIOUS (Otomatik)**
   - Tum `prod-v*` taglari semantik versiyona gore siralanir
   - En az 2 tag gerekli (mevcut + onceki)
   - Ikinci siradaki tag secilir (bir onceki versiyon)

2. **MANUAL_TAG (Manuel)**
   - Kullanici spesifik tag girebilir (orn: `prod-v0.1.0.1`)
   - Tag'in repository'de var oldugu dogrulanir

**Rollback Islemi:**

1. Hedef tag checkout edilir (orn: `prod-v0.1.0.1`)
2. Deploy script normal sekilde calisir
3. Yeni timestamped klasor olusturulur (`prod-v0.1.0.1-20260212-173000`)
4. IIS bu yeni klasore yonlendirilir
5. Git tag EKLENMEZ (mevcut tag kullanilir, yeni tag olusturulmaz)

**Guvenlik:** `confirm_action` checkbox'i zorunlu (false ise workflow baslamadan hata verir)

---

## 4. Branch Protection Kurulumu

> **Not:** "Rulesets" ozelligi private repo'larda sadece GitHub Team (ucretli) planla calisir.
> Asagida ucretsiz planda da calisan **Branch protection rules** kullanilmaktadir.

### A. Main Branch Protection

1. **Repo Settings** > **Branches** > **Add branch protection rule**
2. **Branch name pattern:** `main`
3. Sadece su secenegi isaretleyin:
   - [x] **Require a pull request before merging**
     - Required approvals: **0**
4. Geri kalan tum secenekleri oldugu gibi birakin (bos)
5. **Create**

> **Bu neden yeterli?** "Require PR" aktif olunca dogrudan push ve force push otomatik engellenir.
> Approval sayisi 0 oldugu icin PR acilabilir ama onay beklemez — CI/CD workflow'u bu sekilde
> admin yetkili `BYPASS_TOKEN` ile merge islemini sorunsuz yapabilir.

### B. QA Branch Protection (Opsiyonel)

1. **Repo Settings** > **Branches** > **Add branch protection rule**
2. **Branch name pattern:** `qa`
3. Sadece su secenegi isaretleyin:
   - [x] **Require a pull request before merging**
     - Required approvals: **0**
4. Geri kalan tum secenekleri oldugu gibi birakin (bos)
5. **Create**

### C. Bypass Yaklasimi

Workflow'lar `BYPASS_TOKEN` (admin yetkili PAT) kullanarak branch protection kurallarini bypass eder.
Admin yetkisine sahip token'lar koruma kurallarindan muaftir, bu sayede CI/CD akisi kesintisiz calisir.

---

## 5. Ilk Kurulum Adim Adim (QA)

Asagidaki adimlari sirasyila takip edin:

### Adim 1: Local Hazirlik

```bash
# 1. Build test
npm install
npm run build

# 2. CI/CD dosyalarini commit'le
git add scripts/ .github/
git commit -m "ci: add CI/CD pipeline (deploy, rollback workflows)"
```

### Adim 2: Branch Olusturma

```bash
# dev branch'iniz yoksa
git checkout -b dev
git push origin dev

# qa branch'i olustur
git checkout -b qa
git push origin qa

# main branch'e geri don
git checkout main
```

### Adim 3: Degisiklikleri Push

```bash
git push origin main

# dev ve qa branch'lerine de push
git checkout dev && git merge main && git push origin dev
git checkout qa && git merge main && git push origin qa
```

### Adim 4: GitHub Ayarlari

Bu adimlari **sunucuya girmeden once** GitHub web arayuzunden tamamlayin:

1. Workflow permissions ayarla (Bolum 1.F)
2. Fine-Grained PAT olustur (Bolum 1.G)
3. `BYPASS_TOKEN` secret ekle (Bolum 1.G, Adim 6)
4. Branch Protection kurallari olustur (Bolum 4)

### Adim 5: Sunucu Hazirlik (RDP)

QA sunucusuna RDP ile baglanin ve asagidakileri sirayla yapin:

1. **Git kur** (yoksa): https://git-scm.com/download/win (Bolum 1.A)
2. **Long paths fix**: `git config --system core.longPaths true`
3. **PowerShell**: `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine`
4. **Klasor izinleri**: `C:\inetpub\wwwroot\[site-name]` icin Users > Modify (alt klasorlere inherit eder)
5. **IIS kontrol**: `qa` sitesinin mevcut QA klasorune isaret ettigini dogrulayin
6. **Config Klasörü Hazırlığı**:
   - `C:\inetpub\wwwroot\[site-name]\qa-releases\config` klasörünü oluşturun.
   - Çalışan `.env` ve `web.config` dosyalarınızı bu klasörün içine koyun.
   - **Not:** Bu adım yapılmazsa deploy işlemi Phase 0 aşamasında hata verir.

### Adim 6: Runner Kurulumu (Sunucuda)

Git ve PowerShell hazirlandiktan sonra, **ayni RDP oturumunda** runner kurun:

1. QA sunucusuna self-hosted runner kur, label: `qa-server` (Bolum 1.H)
2. Runner servisinin **Running** ve **Automatic** oldugunu dogrulayin (`services.msc`)
3. GitHub > Repo > Settings > Actions > Runners'da runner'in **Idle** gorundugunü dogrulayin

### Adim 7: Ilk Deploy Testi

1. GitHub > Actions > "Deploy to QA" > Run workflow
2. Workflow loglarini takip edin
3. Yesil tik alindiktan sonra `https://qa.site.net` adresini kontrol edin

---

## 6. Karsilasilan Hatalar ve Cozumleri

| Hata                                           | Cozum                                                                                   |
| ---------------------------------------------- | --------------------------------------------------------------------------------------- |
| Running scripts is disabled                    | `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine`                                  |
| Filename too long                              | `git config --system core.longPaths true`                                               |
| Access Denied (IIS klasoru)                    | Klasor izinlerinde Users > Modify izni verin                                            |
| Access Denied (appcmd)                         | Runner servis hesabini Administrators grubuna ekleyin                                   |
| Could not read IIS site state                  | Runner hesabi IIS yonetim yetkisi olmali (Administrators grubu)                         |
| Process exit code 1 (basarili olmasina ragmen) | Script sonunda `exit 0` (Robocopy exit code 1 = basarili)                               |
| PowerShell Encoding Error                      | YAML/Script icinde emoji kullanmayin, ASCII karakterler kullanin                        |
| Resource not accessible by integration         | Workflow permissions > Read and write + Allow PR creation                               |
| Runner stops after closing CMD                 | `.\svc.cmd install` ile Windows Servisi olarak kurun                                    |
| Protected ref cannot update                    | `actions/checkout` icine `token: ${{ secrets.BYPASS_TOKEN }}` ekleyin                   |
| Merge conflict in workflow                     | Workflow durur, conflict'i elle cozup tekrar tetikleyin                                 |
| IIS site won't stop                            | `appcmd list site` ile site adini dogrulayin                                            |
| Build fails but old site runs                  | Build workspace'te olur, IIS etkilenmez — site calismaya devam eder                     |
| FULL_VERSION env var not set                   | Workflow'da FULL_VERSION duzgun set edildigini kontrol edin                             |
| appcmd set vdir fails                          | vdir name formatini kontrol edin: `siteName/` (slash ile bitmeli)                       |
| [FAIL] Central .env file not found             | `{env}-releases\config` klasorunu olusturun ve icine `.env` koyun                       |
| [FAIL] .next copy failed                       | Build basarili mi kontrol edin, .next klasoru mevcut olmali                             |
| npm install failed in release folder           | package.json ve package-lock.json kopyalandigini dogrulayin                             |
| Eski release klasoru silinemedi                | Kilitli dosyalar olabilir (normal), script devam eder, sonraki deploy'da tekrar denenir |

---

## 7. PROD Kurulumu (Ileride)

PROD ortami kurulurken asagidaki adimlari tamamlayin:

1. **Sunucuda `C:\inetpub\wwwroot\[site-name]` klasoru** olusturun ve Users > Modify izni verin
   (prod-releases alt klasoru ilk deploy'da otomatik olusur)

2. **PROD Config Klasörünü Oluşturun:**
   - `C:\inetpub\wwwroot\[site-name]\prod-releases\config` klasörünü oluşturun.
   - Production için geçerli `.env` ve `web.config` dosyalarını buraya koyun.

3. **IIS'te PROD sitesini** kontrol edin: `site.com` sitesi mevcut klasore isaret etmeli

4. **PROD sunucusuna runner kurun** - Label: `prod-server` (Bolum 1.H)

5. **Branch Protection** kuralini PROD branch'i icin de ekleyin (opsiyonel, Bolum 4.B ile ayni)

6. **Ilk PROD deploy testini** yapin: Actions > "Deploy to PROD" > Run workflow
   - Script mevcut IIS path'ten `.env` ve `web.config` dosyalarini otomatik kopyalar
   - IIS path yeni release klasorune yonlendirilir
   - Eski klasor silinmez (son 3 release saklanir)

---

## 8. Mimari Ozet

```
Developer (Local)
    |
    | git push
    v
GitHub (dev branch)
    |
    | [Deploy to QA] workflow tetiklenir (manuel)
    | 1. dev -> qa merge (--allow-unrelated-histories)
    | 2. Version calculation (package.json + tag count)
    | 3. QA Runner uzerinde build (workspace)
    | 4. Phase 0: .env central config'den workspace'e
    | 5. Phase 1: npm install + build
    | 6. Phase 2: Yeni timestamped klasor (qa-v0.1.0.X-20260212-143022)
    | 7. Phase 3: IIS path swap (< 2 sn)
    | 8. Phase 4: Cleanup (son 3 release sakla)
    | 9. Git tag push (qa-v0.1.0.X)
    v
QA Server (https://qa.site.net) [runner: qa-server]
    |
    | [Deploy to PROD] workflow tetiklenir (manuel)
    | 1. Son QA tag'i bul (semantik siralama)
    | 2. qa -> main merge
    | 3. PROD Runner uzerinde build (workspace)
    | 4. Phase 0-4 ayni sekilde calisir
    | 5. Yeni timestamped klasor (prod-v0.1.0.X-20260212-160000)
    | 6. Git tag push (prod-v0.1.0.X)
    v
PROD Server (https://site.com) [runner: prod-server]

    Acil durum:
    [Rollback PROD] -> Eski release klasorune geri doner
```

**Runner Konumu:** Her IIS sunucusunda kendi runner'i calisir (self-hosted). QA runner'i `qa-server`, PROD runner'i `prod-server` label'i ile tanimlidir. Build ve deploy ayni makinada gerceklesir. Dosya kopyalama local disk uzerinde yapilir (ag transferi yok).

**Versioned Release Klasor Yapisi:**

```
C:\inetpub\wwwroot\[site-name]\
  qa-releases\
    config\                         # Merkezi config (.env, web.config)
    qa-v0.1.0.1-20260210-120000\   # eski (3'ten fazla ise temizlenir)
    qa-v0.1.0.2-20260211-150000\   # onceki
    qa-v0.1.0.3-20260212-143022\   # <-- IIS buraya bakar (en yeni)
  prod-releases\
    config\                         # Merkezi config
    prod-v0.1.0.1-20260212-160000\ # <-- IIS buraya bakar
```

**Not:** Her release klasoru ismine timestamp eklenir (`yyyyMMdd-HHmmss` formatinda).
Bu sayede ayni version'dan birden fazla deploy yapilabilir ve dosya kilitleme sorunlari onlenir.
