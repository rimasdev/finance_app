# Takings API — VPS deploy

Same Alphabet VPS layout as Tanren (`fitness_app/server/docs/DEPLOY.md`).

## Stack
- Python 3.12 FastAPI on port **3120** (Tanren uses 3110)
- Postgres database `takings` on the VPS
- PM2 process `takings-api`
- Caddy TLS reverse proxy

## 1. DNS
Create an A record:
```
api.takings.alphabet.lk  →  72.61.224.8
```

## 2. Postgres on the VPS
```bash
ssh alphabet-vps
sudo -u postgres psql <<'SQL'
CREATE USER takings WITH PASSWORD 'STRONG_PASSWORD_HERE';
CREATE DATABASE takings OWNER takings;
GRANT ALL PRIVILEGES ON DATABASE takings TO takings;
SQL
```

## 3. App dir and env
```bash
ssh alphabet-vps
mkdir -p /var/www/takings
nano /var/www/takings/.env
```

Copy keys from `.env.example`:
- `DATABASE_URL` — `postgresql+psycopg://takings:PASSWORD@127.0.0.1:5432/takings`
- `JWT_SECRET` — long random string
- `GOOGLE_CLIENT_IDS` — web client, plus the new iOS and Android client IDs
- `APPLE_CLIENT_IDS=lk.alphabet.takings`
- `PORT=3120`

## 4. Caddy
Append to `/etc/caddy/Caddyfile`:
```
api.takings.alphabet.lk {
  reverse_proxy 127.0.0.1:3120
}
```
Then:
```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

## 5. Push from the laptop
```bash
bash scripts/push.sh
```

## 6. Google Sign-In
Use the same Google Cloud project as Tanren (`tanren-bbd3b`).

1. Credentials → Create OAuth client:
   - **iOS** → bundle `lk.alphabet.takings`
   - **Android** → package `lk.alphabet.takings` + SHA-1
   - The existing **Web** client is already the `serverClientId` in the app
2. Put every client ID into the VPS `.env` as `GOOGLE_CLIENT_IDS=web...,ios...,android...`
3. After the iOS client exists, add its reversed client ID as a URL scheme in Xcode (Google Sign-In on iPhone).

Android SHA-1:
```bash
cd mobile/android && ./gradlew signingReport
```

## 7. Apple Sign-In
1. Apple Developer → Identifiers → App ID `lk.alphabet.takings` → enable **Sign In with Apple**
2. The Xcode project already has the Sign in with Apple entitlement
3. App Store Connect app is Takings

## 8. App API URL
The phone app defaults to `https://api.takings.alphabet.lk`.
The sign-in screen still has a server field if you need the emulator:
`http://10.0.2.2:3120` (Android) or `http://127.0.0.1:3120` (iPhone simulator).

## Health check
```bash
curl https://api.takings.alphabet.lk/health
```
