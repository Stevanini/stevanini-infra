# Backup – marca Stevanini (Photos / Document Editor / Documents)

Servidor: 192.168.0.200 (ssh server@192.168.0.200), pastas ~/workspace/<app>.

| App | Nome | Pasta | Como funciona |
|---|---|---|---|
| Immich | Stevanini Photos | immich/ | bind mount `./stevanini:/stevanini:ro` + `command` roda `patch.js` a cada start (injeta CSS/ícone/título/olho de senha no index.html) |
| Stirling-PDF | Stevanini Document Editor | stirling-pdf/ | serviço `stirling-brand` (nginx, porta 8080) faz proxy e injeta CSS/JS/ícone/título |
| Paperless-ngx | Stevanini Documents | paperless/ | serviço `brand` (nginx, porta 8000) faz proxy e injeta CSS/JS/ícone/título; `PAPERLESS_APP_TITLE`/`APP_LOGO` no compose |

## Restaurar
1. Copie `<app>/stevanini/` e `<app>/docker-compose.yml` para `~/workspace/<app>/` no servidor.
2. Paperless: aplique as variáveis de `paperless/env-vars-alteradas.txt` no `.env` (o `.env` completo não foi copiado: tem senhas).
3. `docker compose up -d` em cada pasta (Immich: o `patch.js` reaplica a marca a cada start).
4. Cloudflare guarda CSS ~4h: aumente o `?v=` no nginx.conf/CSS ou faça Ctrl+Shift+R.

`*.bak-stevanini` = compose original antes das alterações.
Imagens do Immich por trás: logos são SVGs embutidos (base64) em stevanini.css, gerados do `local/logo-marca.png`.
`local/`: logo original, autostart do EasyEffects (atrasado 15s) e scripts usados para tirar prints (Firefox + Marionette).

## Estado final (resumo do que foi feito)
- **Logins iguais** nos 3 apps: card 26rem/raio 24px, logo vertical (pássaro + nome) 20,6rem, rótulos acima, campos 42px cor creme, botão laranja "Entrar", olhinho de senha em todos, fundo liso, tema claro/escuro.
- **Abas**: Stevanini Photos / Stevanini Document Editor / Stevanini Documents + favicon do pássaro (scripts mantêm o ícone mesmo se o app tentar trocar).
- **Dentro dos apps**: Immich barra = pássaro + "Photos"; Stirling = pássaro + "Document Editor" (alinhado à esquerda na lateral, `wm-*.svg`); Paperless = barra nas cores Stevanini, só o pássaro + "Documents".
- Paperless atende `documents.stevanini.com.br`, `localhost:8000` e `192.168.0.200:8000` (ver `env-vars-alteradas.txt`).
- Cloudflare guarda CSS ~4h: ao mudar CSS suba o `?v=` (nginx.conf / patch.js faz isso sozinho no Immich).
- Não coberto: ícones PNG (apple-touch/PWA), e-mails e links compartilhados do Immich.

## Ícones PNG (pássaro)
Gerados do SVG com `local/gerar-icones-png.py` (canvas no Firefox). Ficam em `<app>/stevanini/png/`:
- Immich: `patch.js` copia para `/build/www` a cada start (apple-icon-180, favicon-*, manifest-icon-*). O `manifest.json` do Immich é servido pelo próprio servidor e continua com o nome "Immich".
- Stirling: nginx serve `/modern-logo/logo192.png`, `logo512.png`, `favicon.png` e um `/manifest.json` próprio.
- Paperless: nginx serve `apple-touch-icon.png`, `icon-192/512(.maskable).png` e `manifest.webmanifest` próprio.
