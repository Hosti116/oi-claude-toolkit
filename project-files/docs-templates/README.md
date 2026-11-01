# Documentazione

Ambiente One Identity: tipo e versioni nella sezione `## Ambiente` di `CLAUDE.md`.
Qui trovi cosa è stato cambiato nei sistemi, come funzionano i flussi e perché sono state prese certe decisioni.

## Dove trovare cosa

| Cartella | Contenuto | Indice |
|---|---|---|
| `changes/` | Un **change record** per ogni modifica applicata (o preparata) su OIM, SPP o SPS | [changes/README.md](changes/README.md) |
| `flows/` | Una pagina per **flusso**: cosa succede, in che ordine, dove guardare se si rompe | [flows/README.md](flows/README.md) |
| `adr/` | **Decisioni** con le alternative scartate | [adr/README.md](adr/README.md) |
| `inventory/` | Elenco degli oggetti custom letto dai sistemi. **Generato** da `tools/Export-OiInventory.ps1`, non si modifica a mano | [inventory/oim-custom-objects.md](inventory/oim-custom-objects.md) |
| `reference/` | Riferimenti tecnici generati (cmdlet PowerShell). Esclusi dal sito MkDocs | — |
| [glossary.md](glossary.md) | I termini usati nelle pagine, in parole semplici | — |

## Come si legge una pagina

Ogni pagina ha due parti:
1. **In breve**: poche righe senza gergo, per chi deve solo capire cosa succede.
2. **Dettaglio tecnico**: tabelle, oggetti, parametri, per chi deve gestire o modificare.

Le affermazioni tecniche hanno un **livello di evidenza**:

| Livello | Significato |
|---|---|
| **[VERIFICATO]** | Provato sul sistema (OIM, SPP) o letto direttamente dal database |
| **[DOC]** | Scritto nella documentazione ufficiale, non provato qui |
| **[DEDOTTO]** | Ragionamento, non ancora confermato |

### Pagina di flusso
- La tabella in alto dice **cosa avvia** il flusso, quali sistemi tocca, chi ne è responsabile e quando è stato verificato l'ultima volta.
- Lo **schema** (Mermaid) mostra il percorso in parole semplici; i nomi tecnici stanno nella tabella *Passi*.
- La colonna *Se fallisce* della tabella *Passi* e la sezione *Monitoraggio* dicono dove guardare.
- *Storico* elenca i change record che hanno modificato il flusso.

### Change record
Stato: `bozza` (preparato, non applicato) · `applicato-<ambiente>` · `testato` · `rilasciato` · `annullato`.
Ogni record ha la sezione **Rollback**, con il valore originale degli oggetti modificati.

## Regole

- Una modifica a OIM, SPP o SPS **non è finita** finché non ha il suo change record, le pagine di flusso aggiornate e gli indici aggiornati.
- Si documenta il comportamento **reale**, verificato; se non è verificato si dice.
- Mai segreti, token, password, dati di clienti o identificativi di produzione nelle pagine.
- Prima di un rilascio, o alla domanda "è tutto documentato?":
  `pwsh -NoProfile -File tools/Export-OiInventory.ps1 | Where-Object { -not $_.Documented }`

## Sito

`mkdocs serve` dalla radice del repo (tema Material, schemi Mermaid abilitati in `mkdocs.yml`).
