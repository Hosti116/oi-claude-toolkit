# Brand theme — checks in Chrome after the import

Run after the operator imported the package with the Software Loader and `<API Server app pool>` was recycled (with OK).
Tools: Claude in Chrome (`javascript_tool`, `computer`, `read_network_requests`, `read_console_messages`).
Scanner: `scripts/brand-check.js` (inject the whole file; it defines `window.__brandCheck`). Read-only.
The theme choice is a **user setting kept on the server** ("User interface settings"; the portal overwrites
`localStorage` with it after login): the operator selects the theme to check, or the agent does it in the dialog
after the operator's explicit OK (account setting). Note the starting choice and restore it at the end.

## 1. Fresh portal
1. Open `<API Server>/html/qer-app-portal/` in a new tab of the session group; the operator logs in if needed.
2. Ctrl+Shift+R (browsers keep the previous portal in cache after a deployment).
3. Inject `brand-check.js`; `__brandCheck.scan()`:
   - `mainScript` must equal the `main-*.js` of the package (`index.html` in `custom\Html_qer-app-portal.zip`);
     a different name = old portal from the cache: reload again before judging anything;
   - `brandContract` = the light class of the brand; `themeCssLoaded` = two numbers > 0 (rules of the two CSS files).
4. Console: `read_console_messages` with pattern `CCC` → "CCC loaded" / "CCC initialized".

## 2. Tour per theme
For each theme — `<id>-light-theme`, `<id>-dark-theme`, `eui-light-theme` (standard, must stay One Identity):
1. Select the theme in "User interface settings" (see above), reload, inject `brand-check.js` again.
2. `await __brandCheck.tour(null, [...])` with at most 4 pages per call (the tool stops a call after 45 s):
   `#/dashboard`, `#/newrequest/allProducts`, `#/shoppingcart`, `#/requesthistory`, `#/itshop/approvals`,
   `#/attestation/decision`, `#/compliance/rules`, `#/myresponsibilities`, `#/admin/dataexplorer`,
   `#/statistics`, `#/profile`.
3. Expected for the brand themes: `logo` true, `oobColors` {}, `lowContrast` {}, `fontErrors` 0, `pluginEffect` true;
   dark theme: masthead per layout, `accentText` only the dark accent (and the amber of warnings).
   Expected for the standard theme: `oobColors` not empty (One Identity blue), `brandContract` still declared, no
   brand logo — the brand CSS must not change it.
4. Side panel: on `#/admin/dataexplorer` open the first identity (screenshot first), `scan()`, close with Escape.

## 3. Device theme
Select "Device theme", reload, inject again, `scan()`: `bodyClasses` contains the brand class for the current device
mode (`<id>-light-theme`, or `<id>-dark-theme` + `eui-dark-theme`), unless the brand declares `deviceTheme: standard`.
The other device mode is covered by the BrandThemeService unit tests (a browser cannot switch it from a script).

## 4. Login (guided)
The operator logs out; check both steps (username, then password with "Forgot password?") with `scan()` and a
screenshot, for the brand light and dark themes; the operator logs in again. Never type credentials.

## 5. Report and cleanup
- Restore the operator's starting theme choice in "User interface settings" (if the agent changed it).
- Report: one table pages × themes with ok / anomaly, then only the anomalies in detail
  (`oobColors`, `lowContrast` entries with the element, screenshot path). A new kind of anomaly is a new rule for the
  kit: stop and describe it instead of patching the customer's theme by hand.
- Not checkable in a lab without computed statistics: chart colors.
