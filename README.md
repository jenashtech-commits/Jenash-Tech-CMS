# Jenash Tech CMS

A church management system — members, attendance, tithes & finances, events, departments, communication, and reports. Runs as a single static site backed by [Supabase](https://supabase.com).

## 1. Create the Supabase project

1. Go to [supabase.com](https://supabase.com) → sign up (free tier is enough) → **New Project**.
2. Pick a name, a database password (save it somewhere safe), and a region close to you.
3. Once it's ready, open **SQL Editor** → **New query**, paste the entire contents of `supabase-schema.sql`, and click **Run**. This creates all the tables (members, attendance, finances, events, departments, announcements, settings) plus the admin login system, and locks every table down so only a logged-in admin can reach it.
4. Go to **Settings → API**. Copy:
   - **Project URL**
   - **anon public** key

## 2. Create your 5 admins (one-time, in Supabase)

Access is name + PIN — no email, no signup screen, and no "add admin" button anywhere in the app. The only way an admin account is ever created is by running SQL directly in Supabase, and a hard limit in the database blocks a 6th admin from ever being added — even by someone running SQL later.

1. Open **SQL Editor** in Supabase again.
2. At the bottom of `supabase-schema.sql` there's a commented block like this — uncomment it, fill in your 5 real names and PINs (4–6 digits), and run it **once**:
   ```sql
   insert into admins (name, pin_hash) values
     ('Emmanuel Ofosu Yeboah', crypt('1234', gen_salt('bf'))),
     ('Admin Two',             crypt('2345', gen_salt('bf'))),
     ('Admin Three',           crypt('3456', gen_salt('bf'))),
     ('Admin Four',            crypt('4567', gen_salt('bf'))),
     ('Admin Five',            crypt('5678', gen_salt('bf')));
   ```
3. PINs are stored as one-way bcrypt hashes (`pin_hash`) — never in plain text, and never sent back to the browser. If someone forgets their PIN, you reset it in SQL Editor with:
   ```sql
   update admins set pin_hash = crypt('NEW_PIN', gen_salt('bf')) where name = 'Their Name';
   ```

## 3. Connect the app to Supabase

1. Open `config.js` in this folder.
2. Paste your Project URL and anon key:
   ```js
   window.JENASH_CONFIG = {
     SUPABASE_URL: "https://xxxxxxxx.supabase.co",
     SUPABASE_ANON_KEY: "eyJhbGciOi...",
   };
   ```
3. Save the file.

Open `index.html` in a browser to test — you should land on a name + PIN sign-in screen. Log in with one of the 5 admins you created.

## 4. Push to GitHub

```bash
git init
git add .
git commit -m "Jenash Tech CMS"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/jenash-tech-cms.git
git push -u origin main
```

(Create the empty repo on GitHub first if you haven't already — no README/license needed there, this folder already has one.)

## 4. Deploy on Vercel

1. Go to [vercel.com](https://vercel.com) → sign in with GitHub.
2. **Add New → Project** → import the `jenash-tech-cms` repo.
3. Framework preset: choose **Other** (it's a static site, no build step needed).
4. Leave build/output settings blank and click **Deploy**.
5. Vercel gives you a live URL (e.g. `jenash-tech-cms.vercel.app`) — that's your church management system, live on the internet.

Every time you `git push` a change, Vercel redeploys automatically.

## Security note

- Only the 5 named admins can sign in, using name + PIN. PINs are stored as bcrypt hashes, never in plain text.
- Every table (members, attendance, finances, events, departments, announcements, settings) is locked at the database level — the public anon key alone cannot read or write anything. All access goes through server-side functions that first check for a valid, unexpired login session.
- There is no in-app way to add a 6th admin — none exists in the interface, and the database itself rejects a 6th `admins` row even if someone tries via SQL.
- A login session lasts 12 hours, then that admin is asked to sign in again. Use **Log out** in the sidebar to end a session early (e.g. on a shared device).
- If you ever need to change who the 5 admins are, that's done directly in Supabase's SQL Editor (update a name/PIN, or delete a row and — since deleting frees a slot — insert a replacement). This is deliberately kept out of the app itself.

## Backing up your data

The app has CSV export buttons on every section (Members, Attendance, Finances, Events, Departments, Communication), plus a **"Export All Data"** button on the Settings page. Use these for regular backups regardless of where the data lives.

## File overview

| File | Purpose |
|---|---|
| `index.html` | The entire app (UI + logic) |
| `config.js` | Your Supabase URL + anon key (edit this) |
| `supabase-schema.sql` | Run once in Supabase to create tables |
| `README.md` | This file |
