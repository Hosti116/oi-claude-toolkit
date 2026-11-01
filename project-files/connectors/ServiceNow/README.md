# Connettore PowerShell One Identity Manager per ServiceNow

Connettore generico PowerShell (formato `PowershellConnectorDefinition`) per la **Table API REST** di ServiceNow,
autenticazione **Basic**. Gira su **Windows PowerShell 5.1** (Identity Manager ≤ 9.2) e su **PowerShell 7**
(9.3 / 10.x).

**Livelli di evidenza** usati sotto:
- **[VERIFICATO]** eseguito davvero; si specifica sempre *dove*: *offline* (mock locale o sonda), *in OIM* (wizard del Synchronization Editor) o *su istanza* reale;
- **[DOC]** scritto nella documentazione ufficiale, non provato qui;
- **[DEDOTTO]** ragionamento, non confermato.

> Il toolkit contiene solo i sorgenti: XML, modulo e cache dello schema si generano nel workspace, online con
> `-InstanceUrl` o con `-Offline` se la cache esiste già.
>
> Le evidenze qui sotto risalgono allo sviluppo del generatore: ogni ambiente deve ripetere le prove. Quelle *in OIM* e *su istanza* citate
> sotto risalgono a **Identity Manager 9.2**; su 10.0 non è ancora stato provato nulla.

## File

| File | Ruolo |
|---|---|
| `New-ServiceNowConnectorXml.ps1` | **Sorgente di verità.** Legge lo schema (online, con cache) e genera l'XML |
| `ServiceNowSchema.json` | Cache dello schema per tabella (rigenerazione offline con `-Offline`) |
| `ServiceNowConnector.xml` | **Generato**, layout di riferimento: tutto il codice inline come `CustomCommands`. Non modificarlo a mano |
| `ServiceNowConnector.Module.xml` + `ServiceNowConnector.psm1` | **Generati** con `-UseModule`: variante con la logica in un modulo esterno (opzionale) |
| `Verify-ServiceNowConnector.ps1` | Verifica offline: mock HTTP locale + controlli funzionali. Carica le funzioni **dall'XML** |
| `Test-ServiceNowConnector.ps1` | Smoke test contro un'istanza reale **non di produzione** (scrive solo con `-WriteTests`) |

## Istanza: parametro obbligatorio, mai salvata

Nessuna istanza è predefinita e nessun file generato contiene l'URL di un'istanza.

| Dove | Come | Evidenza |
|---|---|---|
| Generatore, modalità online | Parameter set `Online`: `-InstanceUrl` e `-Username` obbligatori, vuoti rifiutati | **[VERIFICATO offline]** 5.1 e 7: senza `-InstanceUrl` → "missing mandatory parameters: InstanceUrl"; con `''` → "argument is null or empty" |
| Generatore, modalità offline | Parameter set `Offline`: non serve l'istanza, si usa la cache | **[VERIFICATO offline]** rigenerazione 2026-10-31 |
| Cache e XML generati | La chiave `Instance` non viene più scritta; il commento in testa all'XML cita solo la cache | **[VERIFICATO offline]** nessun hostname nei file della cartella |
| Connettore in OIM | `Connect-OneIMSnow -InstanceUrl` è `Mandatory` | **[DOC]** `ConnectionParameter` ammette solo `Name`, `Description`, `IsSensibleData`: non esiste un attributo "obbligatorio" (`vendor/IdentityManager.PoSh-Connector-Guide/README.md:234-241`). **[DEDOTTO]** un valore vuoto passato dal wizard fallisce al binding del parametro |
| Smoke test | `-InstanceUrl` e `-Username` obbligatori e non vuoti | **[VERIFICATO offline]** solo lettura del codice; non eseguito (richiede un'istanza) |

Formati accettati per l'istanza: nome (`<instance>`), host (`<instance>.service-now.com`) o URL completo.

## Classi di default

Solo tabelle **standard** di ServiceNow, nessun campo custom `u_` nella cache.

| Classe | Tabella | | Classe | Tabella |
|---|---|---|---|---|
| Company | `core_company` | | Schedule | `cmn_schedule` |
| BusinessUnit | `business_unit` | | LdapServer | `ldap_server_config` |
| Department | `cmn_department` | | LifeCycleStage | `life_cycle_stage` |
| CostCenter | `cmn_cost_center` | | LifeCycleStageStatus | `life_cycle_stage_status` |
| Location | `cmn_location` | | HrIntegrFwSource | `sn_hr_integr_fw_source` |
| Building | `cmn_building` | | HrIntegrationSource | `sn_hr_integrations_source` |
| User | `sys_user` | | Perspective | `sys_perspective` |
| Group | `sys_user_group` | | PhoneTerritory | `sys_phone_territory` |
| GroupMember | `sys_user_grmember` | | UiTheme | `sys_ui_theme` |
| Role | `sys_user_role` | | VendorType | `vendor_type` |
| UserRole | `sys_user_has_role` | | | |

- Le tabelle oltre a utenti/gruppi/ruoli servono perché i campi reference delle classi principali abbiano una
  `ReferenceTarget` **[VERIFICATO offline]** (generatore: nessun riferimento mancante).
- Una tabella assente sull'istanza (es. plugin HR non installato) non blocca la generazione online: warning e classe
  saltata **[DEDOTTO]** dal codice; il caso non è stato riprodotto.
- **Campi custom `u_` della propria istanza**: si ottengono rigenerando online con `-Refresh` (rilegge tutte le
  tabelle) **[DEDOTTO]**: sul 10.0 di questo laboratorio non c'è un'istanza da leggere.
- **Più classi sulla stessa tabella** (es. company fornitori/non fornitori) con `-Tables`, filtro sulla lista e default
  su Insert; esempio con il campo standard `core_company.vendor` nell'help del generatore. Il filtro vale solo per
  la lista, il singolo record si rilegge per `sys_id` **[VERIFICATO offline]** (URI e default).

Origine della cache: si legge da `sys_db_object` + `sys_dictionary` dell'istanza dell'ambiente
e non contiene l'URL. Prima di condividerla, togli i campi custom `u_`. **[DEDOTTO]** le
proprietà dei campi standard (etichette, obbligatorietà) riflettono quell'istanza e la sua versione di ServiceNow:
con un'istanza diversa conviene `-Refresh`.

## Comportamento

| Tema | Scelta | Evidenza |
|---|---|---|
| Schema | `sys_db_object` (ereditarietà) + `sys_dictionary` (tipi, reference, mandatory, display); senza permessi sul dizionario: un record di esempio, tutto String | Lettura reale **[VERIFICATO su istanza]**; ripiego "record di esempio" **[DEDOTTO]** |
| Tipi | `integer`→Int, `boolean`→Bool, `glide_date_time`/`glide_date`→DateTime UTC, resto String (decimali e valute inclusi) | **[VERIFICATO offline]** (`head_count` int, `sys_updated_on` UTC) |
| Campi esclusi | `journal*`, `collection`, `password*`, immagini/video, nomi riservati PowerShell | **[VERIFICATO offline]** warning in rigenerazione (es. `sys_user.user_password`, `photo`, `avatar`) |
| Sola lettura | campi `sys_*`; chiave `sys_id` `IsUniqueKey` + `IsMandatory` + `ReadOnly` | **[VERIFICATO in OIM 9.2]** |
| Lettura | lista con `PropertiesToRequest` leggero, paging a offset con `ORDERBYsys_id`, poi rilettura per `sys_id` | Paging **[VERIFICATO offline]**; **[VERIFICATO su istanza]** `core_company` con migliaia di record ≈ 20 s in lettura completa |
| Scrittura | POST / PATCH (solo i parametri passati, `$null` svuota) / DELETE (404 = già cancellato) | **[VERIFICATO offline]** |
| Retry | 429 e 5xx, 3 tentativi, backoff 2/4/8 s | **[VERIFICATO offline]** |
| Errori | status HTTP e **body JSON di ServiceNow** nel messaggio d'eccezione | **[VERIFICATO offline]** su entrambi i motori, vedi sotto |
| Output | `Set`/`Remove`/`Connect` non emettono nulla sull'output stream | **[VERIFICATO offline]** |

## Due motori: Windows PowerShell 5.1 e PowerShell 7

| Regola | Implementazione | Evidenza |
|---|---|---|
| Body degli errori HTTP | 1) `$_.ErrorDetails.Message`; 2) se vuoto e `Response` ha il metodo `GetResponseStream` (solo 5.1), lettura dello stream con reader chiuso in `finally` | **[VERIFICATO offline, sonda 2026-10-31]** vedi tabella sotto |
| Status HTTP | `[int]$response.StatusCode` con controllo null (nessuna `Response` su DNS/timeout) | **[VERIFICATO offline]** 401/404/429; caso senza risposta **[DEDOTTO]** |
| SecureString → testo | `Marshal.SecureStringToBSTR` + `ZeroFreeBSTR` in `finally` | **[VERIFICATO offline]** 5.1 e 7 |
| Body UTF-8 | `UTF8.GetBytes(json)` + `charset=utf-8` (5.1 codificherebbe le stringhe in ISO-8859-1) | **[VERIFICATO offline]** creazione con "Test àèù" su 5.1 e 7 |
| TLS 1.2 e `-UseBasicParsing` | impostati sempre (innocui su 7) | **[VERIFICATO offline]** nessun effetto collaterale sui test |
| Niente `-AsHashtable`, nomi parametro non riservati | iterazione su `.PSObject.Properties`; nomi riservati esclusi dal generatore | **[VERIFICATO offline]** |
| File UTF-8 con BOM | i tre `.ps1` e il `.psm1` | **[VERIFICATO]** byte `EF BB BF` |

Dove arriva il body di un errore (sonda con `Invoke-RestMethod -UseBasicParsing`, 404 con JSON):

| Risposta | 5.1.26100 | 7.6.9 |
|---|---|---|
| con `Content-Length` | `ErrorDetails.Message` = body | `ErrorDetails.Message` = body |
| chunked (come il mock) | `ErrorDetails.Message` **vuoto** → serve `GetResponseStream()` | `ErrorDetails.Message` = body |

Quindi sul 5.1 i controlli "error body read" passano **grazie al ripiego** sullo stream; sul 7 il ripiego non esiste
(`HttpResponseMessage` non ha `GetResponseStream`) e non serve. **[DEDOTTO]** se le risposte d'errore di
ServiceNow siano chunked o con `Content-Length`: il connettore gestisce entrambi i casi.

Motore effettivo in OIM: **[DEDOTTO]** 10.0 usa PowerShell 7. `Connect-OneIMSnow` scrive la versione nel log
(`Connected to ServiceNow instance … (PowerShell x.y)`): leggerla alla prima connessione dal wizard e
aggiornare questa riga a [VERIFICATO in OIM 10.0].

## Test

### Offline (`Verify-ServiceNowConnector.ps1`, mock su `localhost:18089`) — 2026-10-31

| Layout | Windows PowerShell 5.1.26100 | PowerShell 7.6.9 |
|---|---|---|
| `ServiceNowConnector.xml` (inline) | **20/20 PASS** | **20/20 PASS** |
| `ServiceNowConnector.Module.xml` + psm1 | **22/22 PASS** | **22/22 PASS** |

Controlli (inline): credenziali errate rifiutate; status 401 e **body 401** nel messaggio; connessione; paging (25
record, pagine da 10); retry su 429; DateTime UTC; campo mancante = null; lettura singola; Int tipizzato; creazione
con `sys_id` e accenti; update parziale; `$null` svuota; `Set` senza output; doppia cancellazione; 404 dopo la
cancellazione e **body 404** nel messaggio; disconnessione. Il layout a modulo aggiunge: modulo mancante → errore
chiaro; funzioni del modulo visibili globalmente.

I due controlli sul body cercano il frammento JSON `"message": "…"`, non il testo dello status: "404 (Not Found)"
di PowerShell 7 non basta a farli passare.

```powershell
powershell.exe -NoProfile -File .\Verify-ServiceNowConnector.ps1
pwsh -NoProfile -File .\Verify-ServiceNowConnector.ps1
# variante modulo
powershell.exe -NoProfile -File .\Verify-ServiceNowConnector.ps1 -XmlFile ServiceNowConnector.Module.xml
pwsh -NoProfile -File .\Verify-ServiceNowConnector.ps1 -XmlFile ServiceNowConnector.Module.xml
```

**Limite del mock [DEDOTTO]:** simula solo `cmn_department` e non riproduce ACL, formati reali dei reference,
limiti di rate né il comportamento di `sysparm_*` della specifica versione di ServiceNow.

### Rigenerazione
```powershell
.\New-ServiceNowConnectorXml.ps1 -Offline                 # XML inline dalla cache
.\New-ServiceNowConnectorXml.ps1 -Offline -UseModule      # variante modulo + psm1
.\New-ServiceNowConnectorXml.ps1 -InstanceUrl <instance> -Username <user> [-Refresh]   # online
```
Il generatore salva il file precedente come `.bak`: i `.bak` non vanno versionati.

## Regole OIM apprese (Identity Manager 9.2 — da riconfermare sulla versione installata)

- **[VERIFICATO in OIM 9.2]** il wizard rifiuta `Description` su `<Class>`/`<Property>` e l'attributo `IsAutofill`,
  benché la guida li documenti; le descrizioni sono commenti XML. `Description` su `<PowershellConnectorDefinition>`
  e `<ConnectionParameter>` è accettato.
- **[VERIFICATO in OIM 9.2]** il layout "da guida" (`Import-Module` nel Connect + funzioni in `PredefinedCommands`)
  fallisce con `The term 'Connect-OneIMSnow' is not recognized` in `PageShell03_ConnectionTargetView`: per questo
  il layout di riferimento ha **tutto inline** come `CustomCommands`.
- **[VERIFICATO in OIM 9.2]** XML inline: connessione e lettura dei department funzionanti; XML v2.0 generato online
  (6 tabelle organizzative) caricato e funzionante. Le classi aggiunte dopo (utenti, gruppi, ruoli, tabelle
  referenziate) **non** sono mai state caricate nel wizard.
- **Variante modulo**: mai provata nel wizard. Il psm1 va copiato allo stesso percorso su ogni Job server e client
  admin; con `RemoteSigned` un file scaricato può essere bloccato (`Unblock-File`) **[DEDOTTO]**.

## Rollout (non saltare passi)

| # | Passo | Stato su 10.0 |
|---|---|---|
| 1 | Mock offline + controlli statici, su 5.1 e 7 | **fatto** (2026-10-31) |
| 2 | Smoke test in sola lettura su istanza **non di produzione** (`Test-ServiceNowConnector.ps1`) | da fare: manca un'istanza di laboratorio |
| 3 | Caricamento dell'XML nel wizard del Synchronization Editor (operatore) | da fare |
| 4 | Sincronizzazione in sola lettura, prima in simulazione | da fare |
| 5 | Provisioning, una classe alla volta | da fare |

## Punti aperti

1. **Nessuna prova su 10.0** né in OIM né su istanza: tutte le evidenze "in OIM" sono di 9.2.
2. **`sys_user`**: nel dizionario nessun campo è obbligatorio; in pratica servono `user_name` (univoco),
   `first_name`, `last_name`, `email`. Data Policy e Business Rule dell'istanza possono imporre altri obblighi che il
   dizionario non mostra **[DEDOTTO]**.
3. **Autenticazione Basic**: la password è in chiaro in memoria per costruire l'header; l'utente ServiceNow deve avere
   i soli permessi necessari. OAuth non implementato.
4. **Prestazioni**: una lettura completa fa una chiamata per oggetto dopo la lista; sulle tabelle grandi filtrare la lista
   o restituire tutti i campi nel listing.
