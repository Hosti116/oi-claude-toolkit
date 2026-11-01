# oi-claude-toolkit

Plugin Claude Code e file di progetto per i workspace One Identity Manager e Safeguard.

| Percorso | Contenuto |
|---|---|
| `.claude-plugin/marketplace.json` | Marketplace `oi-claude-toolkit` |
| `plugins/oi-toolkit/` | Plugin: skill, agenti e comandi |
| `project-files/` | File copiati nel workspace: regole, tool, modelli di documentazione, settings di base, connettori |
| `New-OiWorkspace.ps1` | Crea un workspace; il tipo predefinito è `PRODUZIONE` |
| `Update-OiWorkspace.ps1` | Aggiorna un workspace; i file modificati in locale restano e vengono segnalati |
| `tests/` | `Verify-OiWorkspace.ps1`, `Test-OiToolkit.ps1`, `Invoke-OiLeakScan.ps1` |

## Nuovo workspace

```powershell
pwsh -NoProfile -File New-OiWorkspace.ps1 -Path C:\oi-env-nome -EnvironmentType TEST `
    -MarketplaceRepo owner/oi-claude-toolkit -ReferenceRepoUrl https://github.com/owner/oi-reference
```

Compila `oi-env.psd1` e la sezione `## Ambiente` di `CLAUDE.md`, poi avvia `claude` nella cartella e accetta la richiesta di fiducia.
Senza una riga `Tipo` valida, l'ambiente è trattato come produzione.

## Nuova versione

1. Aggiorna `version` in `plugins/oi-toolkit/.claude-plugin/plugin.json`: senza questo, gli ambienti non ricevono le modifiche.
2. Esegui i test e la scansione:
   ```powershell
   pwsh -NoProfile -File tests/Verify-OiWorkspace.ps1
   pwsh -NoProfile -File tests/Test-OiToolkit.ps1
   pwsh -NoProfile -File tests/Invoke-OiLeakScan.ps1 -Path . -Allowlist tests/leakscan-allowlist.json
   ```
3. Crea il tag `v<versione>` e, in ogni workspace, esegui `Update-OiWorkspace.ps1`.
4. Nel workspace riallinea il plugin, poi riavvia Claude Code:
   ```powershell
   claude plugin marketplace add <owner>/oi-claude-toolkit@v<versione> --scope project
   claude plugin update oi-toolkit@oi-claude-toolkit --scope project
   ```
   Il solo `plugin update` senza il primo comando è risultato non sufficiente con la versione 2.1.316 della CLI.

Le regole rimosse da `settings.base.json` vanno tolte a mano dai workspace: l'aggiornamento aggiunge regole ma non ne rimuove.

## Licenze

I file elencati in `NOTICE` vengono da Everything Claude Code, licenza MIT.
I sample dell'SDK di Identity Manager sono proprietari: i workspace li leggono dal percorso locale e non vanno copiati in una repo.
