# Kerst Lootjes 🎁

Lootjes trekken voor de familie, volledig op GitHub:

- **`kerst`** (deze repo, openbaar): de website via GitHub Pages.
- **`kerst-data`** (privé repo): de gegevens: `draws.json` (wie heeft wie) en `members/<Naam>.json` (verlanglijstje + foto).

| Bestand | Wat |
|---|---|
| `index.html` | De hele app |
| `config.js` | Naam van de data-repo. Leeg = demo-modus |
| `users.json` | Per persoon de GitHub-token, versleuteld met diens wachtwoord |
| `tools/maak-accounts.mjs` | Maakt `users.json` en `wachtwoorden.txt` |
| `wachtwoorden.txt` | Wachtwoorden per persoon. **Niet committen** (staat in `.gitignore`) |
| `kerst.html` | Je oorspronkelijke demo |

## Eenmalig instellen

1. **Data-repo:** maak op https://github.com/new een **privé** repo `kerst-data` en vink **Add a README** aan.
2. **Token:** ga naar https://github.com/settings/personal-access-tokens/new
   - Expiration: bijvoorbeeld eind januari 2027
   - Repository access: **Only select repositories → kerst-data**
   - Permissions → Repository → **Contents: Read and write**
   - Generate, en kopieer de token (`github_pat_...`)
3. **Accounts maken:**
   ```bash
   cd ~/Desktop/kerst
   node tools/maak-accounts.mjs      # plak de token als erom gevraagd wordt
   git add users.json && git commit -m "accounts" && git push
   ```
   De wachtwoorden staan daarna in `wachtwoorden.txt`.
4. **Pages:** in de repo `kerst` ga je naar **Settings → Pages → Branch: main / (root) → Save**.
   De site komt op https://bjeltinks-lab.github.io/kerst/

Opnieuw draaien met een nieuwe token houdt dezelfde wachtwoorden en laat de trekkingen staan.

## Hoe het werkt
- **Inloggen:** de browser probeert met je wachtwoord jouw stukje uit `users.json` te ontsleutelen (PBKDF2 + AES-GCM). Lukt dat, dan heb je de token en kan de app in `kerst-data` lezen en schrijven. Een fout wachtwoord ontsleutelt niets.
- **Tegelijk trekken:** elke schrijfactie stuurt de versie mee die de app gelezen heeft. Heeft iemand anders intussen geschreven, dan weigert GitHub. De app leest dan opnieuw en kiest opnieuw. Twee mensen kunnen dus nooit dezelfde naam krijgen. Getest met 10 mensen tegelijk.
- De laatste persoon kan nooit alleen zichzelf overhouden.
- **Opnieuw trekken:** je oude naam gaat terug in de pot en je krijgt een andere. Is er geen andere naam meer over, dan houd je je oude naam.
- Minimaal aantal wensen: `MIN_WISHES` bovenin het script in `index.html` (nu 5 van de 10).

## Beheer (in de repo `kerst-data` op github.com)
- **Wie heeft wie (spoiler!):** open `draws.json`.
- **Iemand opnieuw laten trekken:** bewerk `draws.json` en haal diens regel weg.
- **Alles resetten:** zet `draws.json` op `{"draws": {}}`.
- **Iemand uitsluiten:** maak een nieuwe token en draai `maak-accounts.mjs` opnieuw. De oude token trek je in op GitHub.

## Eerlijk is eerlijk
Iedereen die inlogt heeft technisch gezien de sleutel tot `kerst-data`. Een familielid dat handig is met ontwikkelaarstools zou dus kunnen spieken of sjoemelen. Voor normaal gebruik zie je niets van de anderen.
