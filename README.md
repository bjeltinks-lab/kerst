# Kerst Lootjes 🎁

Lootjes trekken voor de familie. Statische site (GitHub Pages) + Supabase (gratis database).

| Bestand | Wat |
|---|---|
| `index.html` | De hele app |
| `config.js` | Supabase-URL en key. Leeg = demo-modus |
| `supabase/setup.sql` | Tabellen + functies (veilig om te committen) |
| `supabase/wachtwoorden.sql` | Familieleden + wachtwoorden. **Niet committen** (staat in `.gitignore`) |
| `kerst.html` | Je oorspronkelijke demo |

## Online zetten

### 1. Supabase (± 5 min)
1. Maak een gratis account op https://supabase.com en een nieuw project (regio: Frankfurt/EU).
2. Ga naar **SQL Editor** → plak de inhoud van `supabase/setup.sql` → **Run**.
3. Plak daarna `supabase/wachtwoorden.sql` → **Run**. Bovenin dat bestand staan de wachtwoorden per persoon.
4. Ga naar **Project Settings → API** en kopieer de **Project URL** en de **anon / publishable key**.
5. Zet ze in `config.js`.

### 2. GitHub Pages
```bash
git init && git add . && git commit -m "Kerst lootjes"
git branch -M main
git remote add origin https://github.com/<jouw-naam>/kerst.git
git push -u origin main
```
Daarna op GitHub: **Settings → Pages → Branch: main / (root) → Save**.
De site komt op `https://<jouw-naam>.github.io/kerst/`.

> Check vóór het pushen met `git status` dat `supabase/wachtwoorden.sql` er **niet** tussen staat.

## Hoe het werkt
- De browser kan de tabellen niet lezen. Hij kan alleen de `kerst_*` functies aanroepen, en die controleren je inlog-token. Niemand kan dus via de browser zien wie wie heeft.
- Trekken gebeurt op de server, één persoon tegelijk (lock). Twee mensen kunnen nooit dezelfde naam krijgen.
- De server voorkomt dat de laatste persoon alleen zichzelf nog kan trekken.
- **Opnieuw trekken:** je oude naam gaat terug in de pot en je krijgt een andere naam uit de ongetrokken namen. Is er geen andere naam meer over, dan houd je je oude naam en krijg je een melding.
- Profielfoto's worden in de browser verkleind (320×320) en in de database opgeslagen.
- Minimaal aantal wensen: `MIN_WISHES` bovenin het script in `index.html` (nu 5 van de 10).

## Handige SQL (Supabase → SQL Editor)
```sql
-- Hoeveel mensen hebben al getrokken? (zonder spoilers)
select count(*) from draws;

-- Wie heeft wie? (SPOILER!)
select drawer, drawn, drawn_at from draws order by drawn_at;

-- Iemand opnieuw laten beginnen met trekken
delete from draws where drawer = 'Dino';

-- Alles resetten (alle trekkingen weg; profielen blijven)
delete from draws;

-- Eén wachtwoord wijzigen
update members set pass_hash = extensions.crypt('nieuw-wachtwoord', extensions.gen_salt('bf')) where name = 'Dino';

-- Iedereen uitloggen
delete from sessions;
```

## Let op
- Een gratis Supabase-project **pauzeert na 7 dagen zonder verkeer**. Open het dashboard vlak voordat je de link naar de familie stuurt, of herstart het daar met één klik.
- Lokaal testen: zet `config.js` leeg en open `index.html` via een lokale server (`python3 -m http.server`). In demo-modus werkt elke familienaam met elk wachtwoord.
