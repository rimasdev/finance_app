# Takings

Personal and business budget tracker for iPhone and Android. The phone app talks to the API on the Alphabet VPS at `https://api.takings.alphabet.lk`. Bank SMS is parsed on the server and filed against the account whose last 4 digits match.

Sign-in is email and password, Google, or Apple (iPhone). Apple and Google accounts that share an email are the same person.

## What you can do

- Cash, bank, debit card, and credit card accounts
- Personal and business accounts, and a business filter on the timeline
- Categories, monthly budgets, and a spending breakdown
- Add transactions by hand, or from a bank SMS
- Export everything to CSV

## Bank messages

Android can file alerts on its own:

1. Sign in, then open Explore → Auto-track.
2. Allow notification access. That is how most bank alerts arrive.
3. SMS access is optional, for texts that never show a notification.
4. On each bank or card account, save the last 4 digits and the sender name (for example `COMBANK`).

Only messages that look like a debit or credit are uploaded. One-time passwords are left on the phone. If a message names an account you have not added, it waits under “needs an account” instead of being guessed.

iPhone cannot read SMS. Copy the message and paste it from Explore → Paste a bank SMS. You can also share a text into the Android app.

Google Play restricts SMS access. For your own phone, install the Android build directly. Notification access is the path that does not require Takings to be the default messaging app.

## Run the API on this computer

```bash
cd api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 3120
```

The API uses a SQLite file in `data/` until you set `DATABASE_URL`.

```bash
cd mobile
flutter pub get
flutter run
```

The app opens against `https://api.takings.alphabet.lk`. On the sign-in screen you can point it at a local API:

- iPhone simulator and this computer: `http://127.0.0.1:3120`
- Android emulator: `http://10.0.2.2:3120`

## Run it on the VPS

The live host is the same machine as Tanren: SSH host `alphabet-vps`, Postgres on the host, PM2, and Caddy in front of the API. Full steps are in `docs/DEPLOY.md`.

```bash
bash scripts/push.sh
```

Bundle id for Apple and Google is `lk.alphabet.takings`.
