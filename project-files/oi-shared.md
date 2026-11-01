# Regole condivise One Identity

Questo file arriva da `oi-claude-toolkit`. Non modificarlo qui: i fatti dell'ambiente stanno nel `CLAUDE.md` del workspace.

## Tipo di ambiente
- La sezione `## Ambiente` di `CLAUDE.md` è l'unica fonte. Solo `Tipo: LAB`, `TEST` o `DEMO` valgono come non produzione.
- **Sezione o riga assente, valore ambiguo o qualsiasi altro valore: l'ambiente è PRODUZIONE.**
- Non dedurre mai il tipo da hostname, memoria o conversazione.

## Regole
- Sul DB di Identity Manager: SOLO query SELECT con il login di sola lettura indicato in `## Ambiente`.
  Mai UPDATE/DELETE/INSERT diretti: le modifiche passano da Designer / Object Browser / API.
- Oggetti custom con prefisso CCC_.
- Script di Identity Manager: VB.NET (script library). DLL custom: C# in oim/dotnet.
- SPP: PowerShell con il modulo safeguard-ps, o API REST v4.
- SPS: plugin Python, API REST.
- Mai scrivere credenziali nei file: usare variabili d'ambiente o secrets/.

## Struttura
oim/ = Identity Manager, spp/ = Safeguard SPP, sps/ = Safeguard SPS, sync/ = connettori, docs/ = contesto,
docs/reference/ = submodule oi-reference, vendor/ = submodule upstream, oi-env.psd1 = impostazioni dell'ambiente senza segreti.

## Metodo
Per attività non banali: prima `/oi-toolkit:plan`, poi implementazione, poi `/oi-toolkit:code-review`.
- Skill, agenti e comandi vengono dal plugin `oi-toolkit` (nomi con prefisso `oi-toolkit:`).
- Livelli di evidenza in ogni risposta: [VERIFICATO] provato sul sistema · [DOC] documentato, non provato · [DEDOTTO] ragionamento.
- Prima verificare sulla fonte (file:riga, oggetto nel DB, sample ufficiale), poi scrivere. Mai inventare formati o API senza un esempio reale.
- Connettori sync: skill oneidentity-im-sync-connector.

## Identity Manager via PowerShell
- Modulo: vendor/IdentityManager.PoSh/PSIdentityManagerUtils (leggi il sorgente in Public/ se hai dubbi).
- Connessione: SEMPRE tramite tools/Connect-OIM.ps1, mai credenziali in chiaro.
- Riferimento dei cmdlet: docs/reference/oim-posh-cmdlets.md.
- Le funzioni Get-* si possono usare liberamente. Per New-/Set-/Remove-*, Save-UnitOfWork,
  Invoke-ImEvent e Invoke-IdentityManagerScript: scrivi prima lo script in oim/scripts/, mostramelo e aspetta l'ok.
- Preferisci la generazione con UnitOfWork per le modifiche multiple.
- Gli script si eseguono SOLO con `pwsh -NoProfile -File <script>` (PowerShell 7.6+), mai con powershell.exe.

## Safeguard SPP
- Custom platform: usa SEMPRE la skill spp-custom-platform (che rimanda a vendor/SafeguardCustomPlatform/AGENTS.md).
- Login: Connect-Safeguard -DeviceCode. Mai -Username/-Password negli script.
- Token di sessione solo in .sg-state/ (gitignored). Mai nei log o in chat.
- safeguard-ps >= 8.4.3, sempre con pwsh.

## Web Portal (IdentityManager.Imx)
- Usa la skill oneidentity-imx. Fork, branch e versione API stanno nel `CLAUDE.md` del workspace.
- Mai fare rebase/merge su commit upstream che richiedono una versione di Identity Manager superiore a quella installata.

## Designer
- Personalizzazioni Designer (script, template, processi): skill oneidentity-im-designer. Claude scrive in oim/designer/, l'operatore applica nel Designer con change label.

## Documentazione
- Ogni modifica applicata a OIM/SPP/SPS → change record in docs/changes + flussi aggiornati (skill oi-documentation). Senza record la modifica non è finita.
