# Kit per i temi di brand del Web Portal (OIM 10.0) — design

Data: 2026-11-15 · Stato: da approvare (approccio A scelto, migrazione Pilota inclusa) · Origine: temi "Pilota chiaro/scuro" del workspace lab (CHG-<n>)

## 1. Intento e perché

Ogni volta che serve brandizzare il Web Portal di un cliente, l'operatore fornisce **brand identity e loghi** e ottiene,
con poca spesa di token, **lo stesso risultato dei temi Pilota**: due temi (chiaro e scuro) integrati nel portale, tutti i
componenti coerenti con il brand, nessun blu/arancio One Identity residuo, e "Device theme" che sceglie
automaticamente tra i due temi del cliente. Le regole e le insidie scoperte con Pilota diventano codice, script e
controlli automatici: non si riscoprono a ogni cliente.

## 2. Obiettivi

1. Input: brand book (PDF o immagini) e loghi (PNG/SVG). Output: **pacchetto pronto per il Software Loader**, con:
   - tema chiaro e tema scuro (logo in testata e login, palette del cliente, scope corretto);
   - plugin `ccc` con il supporto runtime (ricolorazione dei colori fissi OOTB, `eui-dark-theme`, mappatura Device theme);
   - `imx-plugin-config.json`, `imx-theme-config.json`, portale ricompilato con i CSS dei temi dentro;
   - `CUSTOMIZATIONS.md`, change record e pagina di flusso (skill `oi-documentation`).
2. Dopo l'import (fatto dall'operatore) e il riciclo del pool: **verifiche automatiche in Chrome** con report sintetico.
3. Istruzioni e comportamenti documentati nel dettaglio, riutilizzabili per ogni cliente e situazione futura.
4. Costo basso per tema: l'agente esegue script e legge report JSON brevi; non esplora il codice upstream.

## 3. Non-obiettivi

- Import con il Software Loader (resta all'operatore, GUI) e deploy in produzione.
- Branding completo degli altri applicativi (Manager, Password Reset): caricano i CSS ma non il plugin `ccc`.
- Colori dei grafici delle statistiche (non verificabili senza statistiche calcolate).
- Controllo di conformità al brand book oltre a colori e loghi (font, spaziature, tono).

## 4. Anti-obiettivi (fallimento anche se "funziona")

- Nomi di clienti o identificativi di ambienti nel toolkit (la leak scan deve restare verde).
- Temi che cambiano l'aspetto dei temi standard o dell'altro tema del cliente (perdita di scope).
- Modifiche a file upstream oltre all'unico punto `CCC-CUSTOM` già noto per caricare `ccc`.
- Testo sotto 3:1 introdotto dal tema (soglia del controllo; obiettivo 4.5:1 dove la palette lo consente).
- Un agente che, per un nuovo cliente, riscrive a mano il plugin o rifà le indagini di CHG-<n>.

## 5. Vincoli (verificati con Pilota, CHG-<n>)

| Vincolo | Conseguenza nel kit |
|---|---|
| L'API Server 10.0 pubblica `/html/<cartella>` solo per le app in `QBMHtmlApp`: `Html_<tema>.zip` → 404 | CSS dei temi dentro il pacchetto del portale (`html/qer-app-portal/<id>/<tema>.css`), `Urls` = `../qer-app-portal/<id>/<tema>.css` |
| Il portale carica i CSS di **tutti** i temi custom; `theme.theme()` di ElementalUI emette i token Material su `html` | mixin scoped `:where(body.<tema>)`; controllo automatico: 0 dichiarazioni non scoped diverse tra i due CSS |
| `EuiThemeService` mette una sola classe sul body; le regole dark dei componenti sono sotto `.eui-dark-theme` | il plugin aggiunge `eui-dark-theme` al tema scuro |
| ~290 usi di `$color-blue-*`/`$color-orange-*` upstream, regole incapsulate `[_ngcontent]` | ricolorazione runtime **sul posto** (stessa regola, stessa specificità), reversibile |
| `classList.add/remove` riscrivono sempre l'attributo → loop dell'observer | modifiche alle classi solo se necessarie (test di regressione) |
| Partial dei font (`cadence`, `material_icons`, `source_sans_pro`) → `@font-face` con path inesistenti (503) | esclusi dalla base; controllo: 0 `@font-face` nei CSS |
| Nx non considera `dist/ccc` input del portale | build del portale con `--skip-nx-cache` |
| Logo unico `CompanyLogoUrl` per tutti i temi | logo disegnato dal CSS del tema; prerequisito `CompanyLogoUrl` vuoto (controllato) |
| `login-theme` di `imx-theme.theme()` rende bianco il testo della card di login | override nel tema chiaro (testo scuro nella card, chiaro sulla barra) |
| Regole di produzione del workspace (`Tipo` non LAB/TEST/DEMO = produzione) | in produzione l'agente si ferma al pacchetto; copia in `bin` e riciclo pool sempre con OK esplicito |

## 6. Approcci considerati

| Approccio | Pro | Contro | Scelta |
|---|---|---|---|
| **A. Kit con plugin generico configurato dal tema** | codice del plugin identico per ogni cliente (scritto e testato una volta); per cliente si generano solo SCSS e config; meno token, meno variabilità | va generalizzato il plugin di Pilota e scritto il generatore | **scelto dall'operatore** |
| B. Kit con plugin generato per cliente | più semplice da costruire oggi | codice diverso per cliente da compilare e testare; più controlli a ogni upgrade | scartato |
| C. Solo skill dettagliata, senza template | poco lavoro iniziale | molti token e risultati variabili per tema; contrario all'obiettivo | scartato |

## 7. Design (approccio A)

### 7.1 Componenti nel toolkit (`plugins/oi-toolkit/`)

| Componente | Percorso | Contenuto |
|---|---|---|
| Skill | `skills/oneidentity-imx-brand-theme/SKILL.md` | flusso completo, regole colore, prerequisiti, checklist, cosa chiedere all'operatore; rimanda a `oneidentity-imx` per l'architettura |
| Riferimento | `skills/oneidentity-imx-brand-theme/reference.md` | le insidie della tabella §5 con sintomo, causa, controllo; procedura Software Loader e ruoli |
| Template SCSS | `skills/oneidentity-imx-brand-theme/templates/scss/` | `_brand-base`, `_brand-scoped-theme`, `_brand-branding`, `brand-light.scss`, `brand-dark.scss` con segnaposto |
| Template plugin | `skills/oneidentity-imx-brand-theme/templates/ccc/brand-theme/` | `BrandThemeService`, remap, colori OOTB e relativi spec (generalizzazione di quelli di Pilota) |
| Script | `skills/oneidentity-imx-brand-theme/scripts/` | `New-ImxBrandTheme.ps1`, `Build-ImxBrandTheme.ps1`, `New-ImxBrandDeployPackage.ps1`, `brand-check.js` |
| Schema | `skills/oneidentity-imx-brand-theme/brand.schema.json` | schema di `brand.json` |
| Agente | `agents/imx-brand-theme-builder.md` | `model: sonnet`; esegue la skill; strumenti: Read, Write, Edit, Bash, Glob, Grep, strumenti Chrome |

Nessun nome di cliente: esempi con id fittizio (`acme`). Versione del plugin incrementata.

### 7.2 Input: `brand.json` (nel workspace, `oim/webportal/brand/<id>/brand.json`)

L'agente legge il brand book e i loghi e **propone** il file; l'operatore conferma. Campi:

- `id` (kebab-case, es. `acme`) → classi `<id>-light-theme`, `<id>-dark-theme`; `displayName.light|dark` (es. "Acme chiaro").
- `colors.primary` (hex del brand book, obbligatorio); facoltativi `accentNeutral`, `warn` (default ambra come Pilota),
  `dark.accent`, `dark.fill` (se assenti: calcolati, §7.4).
- `logos.onBrand` (logo per fondo colorato, es. bianco), `logos.onDark` (logo per fondo scuro, es. a colori);
  facoltativi `logos.onLight`, `loginLogoHeight`, `mastheadLogoHeight` (default 52/120 px come Pilota).
- `layout.lightMasthead`: `brand` (default: testata del colore primario) | `light`; `layout.darkMasthead`: `surface-with-line`
  (default: `#1e1e1e` con linea del primario) | `brand`.
- `deviceTheme`: `brand` (default: Device theme → temi del cliente) | `standard`.
- `notes`: deviazioni dal brand book decise con il cliente (finiscono in `CUSTOMIZATIONS.md`).

### 7.3 Generatore (`New-ImxBrandTheme.ps1 -Brand <brand.json>`)

1. Valida `brand.json` contro lo schema; verifica prerequisiti del workspace (submodule imx, `ccc` presente o da creare,
   `node_modules`, `CompanyLogoUrl` vuoto — lettura via API o DB in sola lettura, se non verificabile lo segnala).
2. Calcola la palette (§7.4) e stampa una **tabella di contrasto** compatta (colore, sfondo, rapporto, esito).
3. Logo: ritaglio dei margini, ridimensionamento, data URI (come `New-LegacyLogoAssets.ps1`, generalizzato).
4. Scrive in `imxweb/custom-theme/<id>/` i file SCSS dai template (marcati "GENERATED by oi-toolkit <versione>").
5. Copia/aggiorna il plugin generico in `projects/ccc/src/lib/brand-theme/` (identico al template; marcato GENERATED) e
   registra `BrandThemeService.start()` in `InitService` se manca. Se `ccc` non esiste: crea la libreria dallo scheletro
   del toolkit e applica il punto `CCC-CUSTOM` documentato (unica modifica upstream).
6. Scrive `imx-theme-config.json` e aggiorna la sezione del tema in `CUSTOMIZATIONS.md` (blocco delimitato e rigenerabile).
7. Idempotente: rieseguirlo con lo stesso `brand.json` non cambia nulla; con modifiche locali ai file GENERATED si ferma.

### 7.4 Regole colore (ricavate dalle decisioni Pilota, applicate al primario del cliente)

- Palette primaria 50–900 generata dal primario (500 = colore del brand); neutro antracite (grigio leggermente tinto
  o neutro puro, a scelta del generatore) e warn ambra.
- **Tema chiaro**: blu OOTB → primario (60→500, 80→700, 85→800, 90→900); azzurri chiari (10–40) → neutro chiaro; arancio → warn.
- **Tema scuro**:
  - un solo **accento** per testo, link, icone, indicatori: la tonalità più satura con contrasto ≥ 4.0:1 su `#444647`
    (card) e ≥ 4.5:1 su `#1e1e1e` (pagina); con Pilota: `#f69097`;
  - un **riempimento** per pulsanti pieni, FAB, badge, chip/date selezionate, barre titolo (side panel, card di login):
    la tonalità vicina al primario con testo bianco ≥ 7:1; con Pilota: `#a4262c` (scelto dall'operatore);
  - superfici blu scure OOTB → antracite; nei riempimenti blu-40 il testo scuro della stessa regola diventa bianco.
- Valori in `brand.json` (`dark.accent`, `dark.fill`) sovrascrivono il calcolo; il generatore avvisa se scendono sotto soglia.

### 7.5 Plugin generico (`BrandThemeService`, nel `ccc` del workspace)

Generalizzazione di `LegacyThemeService` (stessi algoritmi e test), senza costanti di cliente:

- **Configurazione dal CSS dei temi**: ogni CSS di tema dichiara, identiche nei due file (quindi senza perdita di scope),
  le variabili su `:root`: `--ccc-brand-light-class`, `--ccc-brand-dark-class`, `--ccc-brand-device-theme`; e nello scope
  del proprio tema le mappe: `--ccc-brand-map-<shade>` (chiaro), `--ccc-brand-dark-fg-<shade>`, `--ccc-brand-dark-surface-<shade>`,
  `--ccc-brand-dark-fill`, `--ccc-brand-on-dark-fill`. Il servizio le legge con `getComputedStyle` quando cambia la classe.
- Comportamenti (identici a Pilota): `eui-dark-theme` con il tema scuro; ricolorazione sul posto e ripristino; nuovi stili in
  `<head>` osservati; Device theme → temi del cliente (se `--ccc-brand-device-theme: brand`); classi toccate solo se serve.
- Più brand nello stesso portale non sono previsti (un cliente per workspace); il servizio usa la prima coppia trovata.
- Test Karma del template (gli attuali 43 adattati, con CSS di prova che dichiarano le variabili).

### 7.6 Build e pacchetto

- `Build-ImxBrandTheme.ps1`: sass → `dist/<id>/<tema>.css` + `imx-theme-config.json`; **controlli bloccanti**:
  0 dichiarazioni non scoped diverse tra i due CSS (postcss), 0 `@font-face`, variabili `--ccc-brand-*` presenti,
  dimensione CSS sotto soglia. Output finale: una riga JSON con l'esito.
- `New-ImxBrandDeployPackage.ps1`: test `ccc` (Karma), build `qer-app-portal --configuration production --skip-nx-cache`,
  staging datato che rispecchia `bin\imxweb` (`custom\Html_qer-app-portal.zip`, `Html_ccc\imx-plugin-config.json`,
  `Html_<id>-light-theme\imx-theme-config.json`), verifica che il bundle contenga il plugin e i CSS, confronto hash con
  quanto già in `bin` (indica quali file vanno reimportati). Output: tabella file/ruolo/da importare.
- Copia in `bin\imxweb` con backup e riciclo di `<API Server app pool>`: solo con OK esplicito, mai in produzione.

### 7.7 Verifiche automatiche in Chrome (dopo l'import)

- `brand-check.js`: scanner iniettato con `javascript_tool`; restituisce JSON breve per pagina: logo presente, colore
  testata, blu/arancio OOTB residui, testo sotto 3:1 (esclusi i casi standard noti), rossi/accenti usati, CSS caricati,
  plugin caricato, font in errore.
- Giro fisso: dashboard, shop, carrello, storico richieste, approvazioni, attestazioni, compliance, responsabilità,
  data explorer + side panel, statistiche, profilo, "User interface settings"; per tema chiaro, scuro e tema standard
  (deve restare invariato); Device theme simulato (chiaro/scuro) controllando la classe applicata.
- Login: guidato (l'operatore fa logout/login; l'agente controlla i due passi).
- Prima della verifica: Ctrl+Shift+R (cache del portale). Report finale: tabella pagine × temi con esito, solo le
  anomalie in dettaglio.

### 7.8 Agente `imx-brand-theme-builder`

- `model: sonnet`, prompt breve che rimanda alla skill; fasi: (1) brand.json proposto → conferma operatore;
  (2) generatore + build + pacchetto → riepilogo con tabella dei file da importare; (3) attesa import;
  (4) riciclo pool (OK) + verifiche Chrome → report; (5) documentazione (`oi-documentation`).
- Regole di economia: leggere solo gli output JSON degli script; niente esplorazione di `node_modules`/upstream salvo
  errore non coperto dalla skill; in caso di anomalia nuova, fermarsi e riportare (diventa una regola nuova del kit).

### 7.9 Migrazione di Pilota (prima istanza del kit) — inclusa (decisione dell'operatore)

**Criterio di completamento del kit**: rigenera Pilota identico al deploy attuale. Il workspace lab passa da `LegacyThemeService`/`pilota-*.scss` al kit: `brand.json` con i valori attuali
(`#eb212e`, accento `#f69097`, riempimento `#a4262c`, layout attuali), generazione, confronto visivo e con gli scanner
rispetto al deploy attuale (deve risultare identico), nuovo change record. Serve da collaudo del kit.

## 8. Scelte fatte senza l'operatore (da rivedere)

- Algoritmo della palette e neutro lasciati al builder, con il vincolo di riprodurre i valori di Pilota.
- Un cliente per workspace: il plugin usa la prima coppia chiaro/scuro trovata.
- Import con il Software Loader e deploy in produzione fuori dall'agente; copia in `bin` e riciclo del pool sempre con OK.
- Soglia accento scuro 4.0:1 sulle card (Pilota accettato a ~4.2:1), 4.5:1 sulla pagina.

## 9. Lasciato al builder

- Algoritmo esatto della palette 50–900 e del neutro (purché rispetti le soglie di §7.4 e riproduca Pilota entro piccole differenze).
- Nomi interni di funzioni e file dei template, struttura dei test PowerShell nel toolkit (`tests/`).
- Come leggere `CompanyLogoUrl` in sola lettura (API o DB) — se non c'è un modo affidabile, controllo manuale guidato.
- Soglia di dimensione del CSS e formato esatto dei report JSON.
