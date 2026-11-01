# Contratto del modulo connettore — versione 1

Questo documento è l'interfaccia tra chi scrive il modulo PowerShell (anche una terza parte) e chi lo integra in
One Identity Manager. Se il modulo rispetta il contratto, l'integrazione in OIM **non richiede sviluppo**:
basta copiare il file e, solo se cambiano classi o campi, rigenerare l'XML con un comando.

Il modulo di riferimento è `ServiceNowTableApi.psm1`. Il generatore `New-ConnectorXmlFromModule.ps1` non è legato a
ServiceNow: funziona con qualsiasi modulo che rispetti questo contratto.

## 1. Consegna

- **Un solo file** `.psm1`, in UTF-8 **con BOM**.
- Deve funzionare su **Windows PowerShell 5.1** (Identity Manager ≤ 9.2) **e** su **PowerShell 7** (9.3 / 10.0).
- Il file viene caricato con `Import-Module -Global -Force` a ogni connessione, dal percorso indicato nel parametro di
  connessione `ModuleLocation`. Il percorso deve essere lo stesso su ogni Job server e su ogni client di amministrazione.
- Il modulo deve esportare **esattamente** le 7 funzioni elencate sotto (`Export-ModuleMember`). Le funzioni
  di supporto restano interne.

## 2. Funzioni

| Funzione | Parametri | Output |
|---|---|---|
| `Get-OneIMConnectorManifest` | nessuno | il manifest (§3) |
| `Connect-OneIMConnectorSession` | `-InstanceUrl [string]` `-Username [string]` `-Password [SecureString]` `-Options [string]` | **nulla** |
| `Disconnect-OneIMConnectorSession` | nessuno | **nulla** |
| `Get-OneIMConnectorObject` | `-Class [string]` `[-Key [string]]` | senza `-Key`: **tutti** gli oggetti della classe; con `-Key`: **un** oggetto, oppure un errore se non esiste |
| `New-OneIMConnectorObject` | `-Class [string]` `-Values [IDictionary]` | l'oggetto creato, chiave compresa |
| `Set-OneIMConnectorObject` | `-Class [string]` `-Key [string]` `-Values [IDictionary]` | **nulla** |
| `Remove-OneIMConnectorObject` | `-Class [string]` `-Key [string]` | **nulla**; se l'oggetto non esiste già più, non è un errore |

Regole valide per tutte le funzioni:
- **Output stream:** contiene solo gli oggetti indicati sopra, perché il connettore legge tutto ciò che ci finisce.
  Le funzioni che non restituiscono nulla usano `$null = ...`.
- **Log:** con `Write-Host` (informazioni), `Write-Verbose` e `Write-Warning`, che finiscono nel log NLog di OIM.
  Mai segreti, header di autenticazione o token nei log.
- **Errori:** si lanciano con `throw`, con un messaggio comprensibile. Per gli errori HTTP il messaggio contiene il
  codice di stato e il body della risposta.
- **Oggetti:** ogni oggetto restituito ha **tutte** le proprietà della classe nel manifest, con il tipo dichiarato:
  `String` → `[string]`, `Int` → `[int]`, `Bool` → `[bool]`, `DateTime` → `[datetime]` in UTC. Un valore assente
  o vuoto vale `$null`.
- **`Values`:** contiene solo le proprietà da scrivere. Un valore `$null` svuota il campo. L'eventuale chiave in
  `Values` va ignorata. Una proprietà sconosciuta, o non scrivibile in quell'operazione (§3), va rifiutata con `throw`.
- **`Options`:** testo libero che arriva dal parametro di connessione. Formato e opzioni li decide il modulo.
  Un'opzione sconosciuta o non valida va rifiutata con `throw`.
- **Autenticazione:** la decide il modulo. I parametri `Username`, `Password` e `Options` sono generici, quindi si
  può cambiare metodo, per esempio da Basic a OAuth, senza toccare l'XML.

## 3. Manifest

```powershell
[PSCustomObject]@{
    ContractVersion = 1                      # obbligatorio, sempre 1 per questo contratto
    Id              = 'ServiceNow'           # [A-Za-z][A-Za-z0-9]*: diventa il prefisso dei comandi (OneIMServiceNow…)
    Version         = '1.0.0'                # versione del modulo
    Description     = '...'
    Classes         = @(
        [PSCustomObject]@{
            Name       = 'Department'        # [A-Za-z][A-Za-z0-9]*: nome della classe di schema in OIM
            Key        = 'sys_id'            # proprietà chiave: Type String, Access Read
            Display    = 'name'              # proprietà mostrata in OIM
            Revision   = 'sys_updated_on'    # opzionale: proprietà che cresce a ogni modifica
            Operations = @('Insert', 'Update', 'Delete')   # sottoinsieme; vuoto = classe in sola lettura
            Properties = @(
                [PSCustomObject]@{ Name = 'name'; Type = 'String'; Access = 'ReadWrite'; Mandatory = $true; Reference = $null }
                [PSCustomObject]@{ Name = 'parent'; Type = 'String'; Access = 'ReadWrite'; Mandatory = $false; Reference = 'Department' }
            )
        }
    )
}
```

| Campo della proprietà | Valori |
|---|---|
| `Name` | `[A-Za-z_][A-Za-z0-9_]*`, unico nella classe. Diventa un parametro PowerShell, quindi non può essere una variabile automatica (`input`, `args`, `host`, `error`, `matches`, `event`, …) né un parametro comune (`Verbose`, `Debug`, `ErrorAction`, …) |
| `Type` | `String`, `Int`, `Bool`, `DateTime`: sono i tipi ammessi dal connettore |
| `Access` | `Read` (mai scritta), `ReadWrite` (scritta in Insert e Update), `InsertOnly` (scritta solo in Insert) |
| `Mandatory` | `$true` se l'Insert la richiede |
| `Reference` | nome di un'altra classe del manifest, se il valore è la chiave di un suo oggetto |

Il generatore controlla tutte queste regole e, se il manifest non è valido, si ferma con l'elenco degli errori.

## 4. Cosa richiede ogni tipo di modifica

| Modifica nel modulo | Esempio | Lato OIM |
|---|---|---|
| Solo logica | endpoint, filtro, paging, retry, autenticazione, conversioni | copiare il `.psm1` sui Job server: vale dalla connessione successiva |
| Classe o proprietà **aggiunta** | nuovo campo `u_cost_code` | il modulo funziona anche con il vecchio XML (al connect compare un warning). Per **usare** il campo: rigenerare l'XML, caricarlo nella connessione, aggiornare lo schema e aggiungere il mapping |
| Classe o proprietà **rimossa o cambiata** (tipo, accesso, chiave, operazioni) | `head_count` da `Int` a `String` | **il connect si ferma** con l'elenco delle differenze. Rigenerare l'XML, caricarlo, aggiornare lo schema e correggere i mapping che usavano quel campo |
| Contratto diverso da 1 | — | il connect si ferma: serve un generatore aggiornato |

Il blocco del connect sulle modifiche incompatibili è voluto. Un campo sparito dal modulo arriverebbe a OIM come
`$null`, e la sincronizzazione potrebbe svuotare i valori corrispondenti nel database.

## 5. Accettazione di una nuova versione del modulo

1. `New-ConnectorXmlFromModule.ps1 -ModulePath <nuovo.psm1> -Check`: dice se serve un XML nuovo.
2. Copia del modulo nella cartella del connettore, e rigenerazione dell'XML se il passo 1 lo richiede.
3. `Verify-ServiceNowModuleConnector.ps1` con `powershell.exe` **e** con `pwsh`: tutti i controlli devono passare.
   I controlli di runtime usano un mock della Table API di ServiceNow. Un modulo per un altro sistema ha bisogno di
   un proprio mock e di una propria verifica.
4. Smoke test in sola lettura su un'istanza **non di produzione**: `Test-ServiceNowModuleConnector.ps1`.
5. In OIM: copia del modulo su tutti i Job server; se l'XML è cambiato, caricarlo nella connessione e aggiornare lo
   schema. Prima una sincronizzazione simulata, poi quella reale.
