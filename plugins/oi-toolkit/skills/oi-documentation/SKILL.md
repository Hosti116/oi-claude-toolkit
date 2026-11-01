---
name: oi-documentation
description: Use whenever a change to One Identity Manager or Safeguard (SPP/SPS) is designed, applied or tested, when a flow (process, sync, provisioning, access request, password rotation, session) must be documented or explained, when someone asks "what did we change / how does X work", and to regenerate the customization inventory and check that every customization is documented.
---

# Documentation of changes and flows (OIM / SPP / SPS)

Two audiences, one source: every page starts with a short plain-language part (for whoever needs to understand
what happens) and continues with the technical detail (for whoever must operate or change it).
Language: Italian. Evidence levels from CLAUDE.md ([VERIFICATO] / [DOC] / [DEDOTTO]) on every technical claim.

## Layout
```
docs/
  README.md                 ← entry point: what is where, links to indexes, how to read a flow page
  glossary.md               ← terms (change label, job chain, custom platform, entitlement, ...) in plain words
  changes/README.md         ← index table of all change records (newest first) — keep in sync
  changes/<YYYY>/CHG-<YYYY>-<NNN>-<slug>.md
  flows/README.md           ← index of flows by product/area
  flows/<oim|spp|sps|integration>/<slug>.md
  adr/                      ← decisions with alternatives (ECC skill architecture-decision-records)
  inventory/oim-custom-objects.md      ← GENERATED, never edited by hand
  inventory/spp-custom-objects.md      ← GENERATED, never edited by hand
```

## Change record — one per change applied to a system (template)
```markdown
# CHG-2026-001 — <titolo breve>
| Campo | Valore |
|---|---|
| Prodotto | OIM <versione> / SPP <versione> / SPS <versione> |
| Ambiente | <Nome dalla sezione Ambiente di CLAUDE.md> |
| Stato | bozza · applicato-<ambiente> · testato · rilasciato · annullato |
| Change label (OIM) / oggetto SPP | <nome> |
| Data · autore | |
| Flussi impattati | [link](../../flows/...) |
| Decisione (ADR) | [link] o "—" |

## In breve
2–3 frasi senza gergo: cosa cambia per utenti/amministratori e perché.

## Oggetti modificati
| Tipo | Nome | Azione (nuovo/modificato/eliminato) | File nel repo | Valore originale (per rollback) |

## Dettaglio tecnico
Cosa fa il codice/configurazione, parametri, dipendenze. Citare file:riga.

## Test ed evidenze
Piano di test con risultati attesi, esito reale, livello di evidenza.

## Rollback
Passi esatti per tornare indietro (es. ripristinare template originale, reimportare platform precedente).
```
Numbering: next free `NNN` in the year; never reuse a number. Update `changes/README.md` in the same edit.

## Flow page (template)
```markdown
# <Nome del flusso>
> **In breve** — 3 righe: cosa succede, quando, con quale risultato.

| Trigger | Sistemi | Owner | Frequenza | Ultima verifica |
|---|---|---|---|---|

## Schema
(Mermaid: `flowchart LR` for the big picture, `sequenceDiagram` when the order of calls between systems matters.
Max ~15 nodes per diagram; split larger flows. Node labels in plain words, technical names in the table below.)

## Passi
| # | Sistema | Componente / oggetto tecnico | Cosa fa | Config/parametri | Se fallisce |
|---|---|---|---|---|---|

## Dati
Mapping campo → campo (sync/provisioning), con trasformazioni.

## Configurazione
Config parameter, schedulazioni, policy, account di servizio (mai segreti).

## Monitoraggio e troubleshooting
Dove guardare (Job Queue Info, sync log, SPP task log, SPS log), errori noti e cosa fare.

## Limiti noti / punti aperti

## Storico
Elenco dei CHG che hanno toccato il flusso (link).
```

## Rules
- **Definition of done of every change** (any skill): change record created/updated + affected flow pages updated
  + indexes updated. A change without a record is not done.
- Document the **actual** behaviour, verified on the system or in code — not the intended one. If unverified, say so.
- Never put secrets, tokens, passwords, customer data or production identifiers in docs.
- Diagrams in Mermaid inside the Markdown (versioned, diffable); no binary images for flows.
- Keep pages short and linked: one flow per page, details in the tables, long code in the repo with a link.

## Inventory and drift check (read-only)
`tools/Export-OiInventory.ps1` regenerates `docs/inventory/*.md` from the live environment, read-only:
- OIM: objects with the `CCC_` prefix (scripts, tables/columns, processes, events, config parameters) and, if detectable,
  built-in objects modified locally. Discover table/column names first (INFORMATION_SCHEMA / `Get-Member`), do not guess.
- SPP: custom platforms (and their versions) via safeguard-ps Get-* cmdlets only.
Then list every inventory object **not mentioned in any change record** → "Customizzazioni non documentate".
Run it before a release and whenever asked "is everything documented?".