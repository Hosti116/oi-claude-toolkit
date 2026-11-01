# Connettore ServiceNow — layout "modulo"

Connettore PowerShell per One Identity Manager diviso in due parti:
- **`ServiceNowTableApi.psm1`** contiene tutta la logica: chiamate REST, paging, autenticazione, retry, conversione dei
  tipi e l'elenco di classi e campi (il *manifest*). Può gestirlo una terza parte, secondo [CONTRACT.md](CONTRACT.md).
- **`ServiceNowModuleConnector.xml`** è la definizione caricata in OIM. **Si genera** dal manifest del modulo e non
  contiene logica: i comandi passano le chiamate al modulo.

Il connettore in `../ServiceNow/` (XML con tutto il codice inline) non è stato toccato.

Livelli di evidenza:
- **[VERIFICATO]** eseguito davvero, indicando *dove*: *offline* (mock locale), *in OIM* (Synchronization Editor) o
  *su istanza* ServiceNow reale;
- **[DOC]** scritto nella documentazione, non provato qui;
- **[DEDOTTO]** ragionamento, non confermato.

## Cosa si può cambiare senza toccare OIM

| Modifica | Serve un XML nuovo? | Evidenza |
|---|---|---|
| Logica di una chiamata (endpoint, filtro, paging, retry, autenticazione) | **No**: basta sostituire il `.psm1` sui Job server | **[VERIFICATO offline]** il modulo si ricarica a ogni connect (`Import-Module -Force`). **[DEDOTTO]** in OIM vale dalla connessione successiva |
| Nuova classe o nuovo campo | **Sì**, ma lo genera un comando, senza scrivere codice | **[DOC]** lo schema (classi, proprietà, comandi) sta nell'XML: guida `README.md:168-169` e `349-350` |
| Campo o classe rimossi o cambiati | **Sì**, e il connect si ferma finché l'XML non è allineato | **[VERIFICATO offline]** |

Un "aggiorna schema" nel Synchronization Editor **da solo non basta** per una classe o un campo nuovi, perché il
connettore PowerShell descrive lo schema solo tramite l'XML **[DOC]**. **[DEDOTTO]** L'XML viene salvato nella
connessione del progetto di sincronizzazione, quindi prima va caricato quello nuovo modificando la connessione, poi
si aggiorna lo schema. **Da provare sulla versione installata**, quando esiste un progetto di sincronizzazione
(controllo: una SELECT su `DPRShell`).

## File

| File | Chi lo mantiene | Ruolo |
|---|---|---|
| `ServiceNowTableApi.psm1` | autore del modulo (anche terza parte) | logica e manifest (contratto v1) |
| `CONTRACT.md` | noi | interfaccia che il modulo deve rispettare |
| `New-ConnectorXmlFromModule.ps1` | noi, non legato a ServiceNow | valida il manifest e genera l'XML; con `-Check` dice se l'XML è aggiornato |
| `ServiceNowModuleConnector.xml` | **generato** | definizione da caricare nel Synchronization Editor |
| `ServiceNowMock.ps1` | noi | mock della Table API per la verifica offline |
| `Verify-ServiceNowModuleConnector.ps1` | noi | controlli statici, di contratto e di runtime sul mock |
| `Test-ServiceNowModuleConnector.ps1` | noi | smoke test su un'istanza **non di produzione** (scrive solo con `-WriteTests`) |

## Parametri di connessione

| Parametro | Contenuto | Evidenza |
|---|---|---|
| `InstanceUrl` | **obbligatorio**: nome (`myinstance`), host o URL `https://`. `http` è ammesso solo per `localhost` (test) | **[VERIFICATO offline]** valore vuoto e `http` non locale rifiutati |
| `Username` / `Password` | utente e password per l'autenticazione Basic. `Password` è `IsSensibleData` | **[VERIFICATO offline]** 401 rifiutato con il body di ServiceNow nel messaggio |
| `Options` | `Nome=Valore;Nome=Valore`; vuoto = valori di default | **[VERIFICATO offline]** valori e opzioni non validi rifiutati |
| `ModuleLocation` | percorso completo del `.psm1`, con o senza estensione | **[VERIFICATO offline]** modulo assente → errore chiaro |

Il connettore non ha un attributo che renda obbligatorio un parametro di connessione (guida `README.md:236-240`):
l'obbligatorietà la controlla il modulo al connect.

Opzioni del modulo:

| Opzione | Default | Ammessi | Effetto |
|---|---|---|---|
| `AuthType` | `Basic` | `Basic` | altri metodi (es. OAuth) si aggiungono nel modulo, senza cambiare l'XML |
| `PageSize` | 500 | 1–10000 | record per pagina nel listing |
| `TimeoutSec` | 100 | 1–600 | timeout di ogni chiamata |
| `MaxRetries` | 4 | 0–10 | nuovi tentativi su 429 e 5xx, con attesa di 2, 4, 8… secondi |
| `CacheSeconds` | 300 | 0–3600 | per quanto tempo il listing serve le riletture dei singoli oggetti; 0 = disattivato |

## Classi (manifest 1.0.0)

Ogni classe ha `sys_id` come chiave (sola lettura) e `sys_updated_on` come revisione.

| Classe | Tabella | Operazioni | Note |
|---|---|---|---|
| `Company` | `core_company` | Insert, Update, Delete | |
| `Department` | `cmn_department` | Insert, Update, Delete | |
| `Location` | `cmn_location` | Insert, Update, Delete | `full_name` in sola lettura |
| `CostCenter` | `cmn_cost_center` | Insert, Update, Delete | |
| `User` | `sys_user` | Insert, Update, Delete | nessun campo password; `name` e `last_login_time` in sola lettura |
| `Group` | `sys_user_group` | Insert, Update, Delete | |
| `GroupMember` | `sys_user_grmember` | Insert, Delete | `user` e `group` scritti solo alla creazione |
| `Role` | `sys_user_role` | nessuna | sola lettura |
| `UserRole` | `sys_user_has_role` | Insert, Delete | listing filtrato su `inherited=false`, perché le righe ereditate le gestisce ServiceNow |

**[DEDOTTO]** I nomi e i tipi dei campi vengono dalla cache dello schema di un'istanza reale
(`../ServiceNow/ServiceNowSchema.json`, letta da `sys_dictionary`). Nel modulo ci sono solo campi standard, nessun
campo `u_`. Il filtro `inherited=false` e la scrittura su `sys_user_grmember` e `sys_user_has_role` non sono stati
provati su un'istanza.

## Comportamento

| Aspetto | Implementazione | Evidenza |
|---|---|---|
| Lettura | il listing restituisce tutti i campi con paging a offset su `ORDERBYsys_id`; i campi di riferimento sono restituiti come `sys_id` (`sysparm_exclude_reference_link=true`) | **[VERIFICATO offline]** 25 record con pagine da 10 |
| Rilettura per oggetto | servita dalla cache del listing, senza una chiamata per oggetto | **[VERIFICATO offline]** nessuna richiesta in più. **[VERIFICATO in OIM 9.2]**: senza cache una sincronizzazione completa fa una chiamata per oggetto |
| Scrittura | Insert = POST, Update = PATCH con i soli campi modificati (`$null` svuota il campo), Delete = DELETE; un secondo delete dà solo un warning | **[VERIFICATO offline]** |
| Campi non scrivibili | il modulo rifiuta le scritture su campi `Read`, e su campi `InsertOnly` in Update | **[VERIFICATO offline]** |
| Tipi | `Int`, `Bool`, `DateTime` (UTC); un campo vuoto o assente diventa `$null` | **[VERIFICATO offline]**. **[DOC]** ServiceNow restituisce le date in UTC con `sysparm_display_value=false` |
| Errori HTTP | 429 sempre ritentato; 5xx ritentato tranne che sui POST, perché il record potrebbe essere già stato creato e si avrebbe un duplicato. Negli altri casi il messaggio contiene il codice di stato e il body di ServiceNow | **[VERIFICATO offline]** 429 e body su entrambi i motori. L'esclusione dei POST è verificata solo leggendo il codice: il mock non simula un 5xx |
| Campi obbligatori | l'Insert senza una proprietà `Mandatory` viene rifiutato prima della chiamata | **[VERIFICATO offline]** |
| Controllo modulo ↔ XML | al connect il manifest del modulo viene confrontato con lo schema per cui è stato generato l'XML: una rimozione o modifica blocca il connect, un'aggiunta produce un warning | **[VERIFICATO offline]** con un modulo modificato in una cartella temporanea |
| Paging | **[DEDOTTO]** se la tabella cambia durante il listing, il paging a offset può saltare o ripetere un record: la sincronizzazione successiva lo recupera | — |

## Due motori PowerShell

| Regola | Dove | Evidenza |
|---|---|---|
| Body degli errori: prima `ErrorDetails.Message`, poi lo stream della risposta solo se esiste `GetResponseStream` | `Get-SnowErrorBody` | **[VERIFICATO offline]** il mock risponde in chunked: su 5.1 il body arriva dallo stream, su 7 da `ErrorDetails` |
| `SecureString` decodificato con BSTR e azzerato in `finally` | `ConvertTo-SnowPlainText` | **[VERIFICATO offline]** |
| Body in byte UTF-8, `-UseBasicParsing`, TLS 1.2 | `Invoke-SnowRequest` | **[VERIFICATO offline]** nome accentato creato e riletto su 5.1 |
| Niente `-AsHashtable`; proprietà lette con `.PSObject.Properties` | modulo e mock | **[VERIFICATO offline]** |
| Script con BOM; `$PSScriptRoot` mai usato nei default dei parametri (su 5.1 è vuoto) | tutti gli script | **[VERIFICATO offline]** errore riprodotto su 5.1, poi corretto |

## Verifica offline

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Verify-ServiceNowModuleConnector.ps1
pwsh -NoProfile -File .\Verify-ServiceNowModuleConnector.ps1
```

| Gruppo | Controlli | `powershell.exe` 5.1.26100 | `pwsh` 7.6.9 |
|---|---|---|---|
| Statici: XML aggiornato, BOM, CDATA, comandi, `Map`, chiave e display, attributi vietati | 10 | 10/10 | 10/10 |
| Contratto: funzioni esportate, versione, classi | 3 | 3/3 | 3/3 |
| Runtime sul mock: modulo, parametri, lettura, cache, scrittura, errori, disconnect | 35 | 35/35 | 35/35 |
| **Totale** | **48** | **48/48 PASS** | **48/48 PASS** |

**[VERIFICATO offline]**, 31/10/2026. Il primo giro su 5.1 ha trovato un bug che anche su 7 avrebbe rotto la
lettura degli errori: la variabile `$body` coincideva con il parametro `[IDictionary]$Body`, perché in PowerShell le
variabili non distinguono le maiuscole. È corretto.

## Messa in produzione (nessun passo si salta)

1. Verifica offline sui due motori (sopra).
2. Smoke test in sola lettura su un'istanza **non di produzione**:
   `.\Test-ServiceNowModuleConnector.ps1 -InstanceUrl <istanza dev> -Username <utente integrazione>`.
3. Copia di `ServiceNowTableApi.psm1` nello **stesso percorso** su ogni Job server e su ogni client di amministrazione.
   **[DOC]** Con execution policy `RemoteSigned`, un file scaricato da Internet viene bloccato: va sbloccato con
   `Unblock-File` oppure firmato.
4. Synchronization Editor (operatore): nuovo progetto con il connettore PowerShell, caricando
   `ServiceNowModuleConnector.xml`. Gli errori del wizard arrivano come screenshot.
5. Sincronizzazione **in sola lettura** in un ambiente non di produzione, prima simulata.
6. Solo dopo, provisioning: una classe alla volta.

## Regole del wizard (da riconfermare su 10.0)

- **[VERIFICATO in OIM 9.2]** Il wizard rifiuta `Description` su `<Class>`/`<Property>` e `IsAutofill`: il
  generatore non li produce, e la verifica lo controlla.
- **[VERIFICATO in OIM 9.2]** Il layout della guida (`Import-Module` nella sequenza di Connect e funzioni in
  `PredefinedCommands`) fallisce nel wizard. Qui `Import-Module` è **dentro** un custom command e
  `PredefinedCommands` è vuoto: **[DEDOTTO]** dovrebbe evitare il problema, ma **non è mai stato provato nel wizard**.
- **[DOC]** `ListingCommand` senza `SetParameter`, `AccessConstraint="ReadAndInsertOnly"` e `ReferenceTargets` su
  proprietà a valore singolo non sono mai stati provati in OIM.

## Punti aperti

1. Primo caricamento nel wizard su 10.0: è la prova decisiva del layout modulo.
2. Come si sostituisce l'XML di una connessione esistente e se basta poi "aggiorna schema" **[DEDOTTO]**.
3. Verificare nel log NLog che la cache del listing eviti davvero le riletture per oggetto in una sincronizzazione completa.
4. Prova su istanza reale del filtro `inherited=false` e delle scritture su `GroupMember` e `UserRole`.
5. Se serve OAuth: va implementato nel modulo come `AuthType`, l'XML resta uguale. ServiceNow richiede client id,
   client secret e a volte anche utente e password: va deciso come passarli con un solo parametro sensibile.
