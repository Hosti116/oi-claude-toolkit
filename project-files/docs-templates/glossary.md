# Glossario

Termini usati nella documentazione, in parole semplici. Tra parentesi il nome tecnico, quando serve.

## Generali

| Termine | Significato |
|---|---|
| **ADR** (Architecture Decision Record) | Pagina in `adr/` che registra una decisione, le alternative scartate e le conseguenze |
| **Change record** | Pagina in `changes/` che descrive una modifica a un sistema: cosa, perché, come si prova, come si torna indietro |
| **Livello di evidenza** | Quanto è sicura un'affermazione: [VERIFICATO], [DOC] o [DEDOTTO] (vedi [README](README.md)) |
| **Prefisso `CCC_`** | Prefisso obbligatorio di tutti gli oggetti custom, per distinguerli da quelli forniti da One Identity |
| **Rollback** | Procedura per tornare alla situazione precedente una modifica |

## Identity Manager (OIM)

| Termine | Significato |
|---|---|
| **Identità** (Person) | Una persona gestita da OIM: dipendente, esterno, account di servizio |
| **Account centrale** (CentralAccount) | Il nome utente "di riferimento" di un'identità. Da qui OIM deriva i nomi degli account nei sistemi collegati |
| **Account** | L'utenza di un'identità in un sistema collegato, per esempio un utente di Active Directory |
| **Sistema collegato** (target system) | Un sistema in cui OIM crea o legge account e gruppi: Active Directory, Entra ID, ServiceNow… |
| **Entitlement** (diritto) | Un permesso in un sistema collegato, per esempio l'appartenenza a un gruppo |
| **Business role** (Org) | Raggruppamento di identità a cui si assegnano diritti in blocco |
| **IT Shop** | Il "negozio" in cui gli utenti chiedono accessi; le richieste passano da un'approvazione |
| **Designer** | Lo strumento di amministrazione con cui si modificano schema, script, template e processi di OIM |
| **Change label** | "Etichetta" del Designer che raccoglie le modifiche fatte insieme, per tracciarle e trasportarle in un altro database |
| **Template** (di colonna) | Codice VB.NET che calcola il valore di un campo quando cambiano i campi da cui dipende |
| **Script library** | Raccolta di funzioni VB.NET riusabili da template, processi e altri script |
| **Database Compiler** | Compila script e template dopo una modifica: senza compilazione la modifica non è attiva |
| **Processo** (job chain) | Sequenza di passi eseguiti dal Job server in risposta a un evento (per esempio "crea l'account in AD") |
| **Evento** | Segnale che fa partire un processo (inserimento, modifica, eliminazione o un evento custom) |
| **Job server / Job Queue Info** | Il servizio che esegue i processi / lo strumento per seguirne l'esecuzione e gli errori |
| **Parametro di configurazione** (config parameter) | Impostazione del sistema organizzata ad albero, per esempio `QER\Person\DefaultMailDomain` |
| **Application Server** | Servizio web attraverso cui strumenti e script PowerShell si collegano al database |
| **Synchronization Editor / progetto di sincronizzazione** | Strumento e configurazione che leggono e scrivono i dati di un sistema collegato |
| **Connettore PowerShell** | Connettore generico di sincronizzazione: un file XML che descrive classi e comandi PowerShell |
| **Matching rule** | Regola che collega un account esistente a un'identità (per esempio CentralAccount = SAMAccountName) |

## Safeguard (SPP / SPS)

| Termine | Significato |
|---|---|
| **SPP** (Safeguard for Privileged Passwords) | Cassaforte delle password privilegiate: le conserva, le controlla e le cambia |
| **SPS** (Safeguard for Privileged Sessions) | Registra e controlla le sessioni privilegiate (RDP, SSH, web) |
| **Asset** | Un sistema gestito da SPP (server, applicazione, appliance) |
| **Account gestito** | Un account di un asset la cui password è gestita da SPP |
| **Service account** (Func) | L'account con cui SPP si collega all'asset per controllare o cambiare le password degli account gestiti |
| **Platform / custom platform** | La "ricetta" che dice a SPP come parlare con un tipo di asset. La custom platform è uno script JSON scritto da noi |
| **CheckSystem / CheckPassword / ChangePassword** | Le operazioni di una platform: provare la connessione, verificare una password, cambiarla |
| **Task log** | Il registro dettagliato di un'operazione di SPP: è il primo posto dove guardare se un'operazione fallisce |
| **Author-only** | Lavoro sulla custom platform solo in locale (scrittura e validazione dello schema), senza importarla nell'appliance |
