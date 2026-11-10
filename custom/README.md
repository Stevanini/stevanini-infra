# Customizações Stevanini (login igual em Photos, Documents, Document Editor e Auth)

Padrão visual: o login do Paperless (`documents.stevanini.com.br`). Fonte única: **Google Sans** (`shared/GoogleSans.ttf`).

## Publicar no servidor
```bash
./deploy.sh              # tudo
./deploy.sh keycloak     # ou: paperless | stirling | immich
SERVER=usuario@host ./deploy.sh   # outro servidor (padrão server@192.168.0.200)
```
Edite os arquivos desta pasta e rode de novo. O script copia os arquivos, injeta a fonte e reinicia só o container do app publicado.

## O que há em cada pasta
| Pasta | App | Arquivo principal | Como a marca entra |
|---|---|---|---|
| `keycloak/themes/stevanini` | Auth (Keycloak) | `login/resources/css/stevanini-auth-N.css` | tema `login` + tema `admin` (título/ícone da aba); montado em `/opt/keycloak/themes/stevanini` |
| `paperless` | Documents | `stevanini-paperless.css` | proxy nginx `paperless-brand` injeta CSS/JS/favicon (`nginx.conf`) |
| `stirling-pdf` | Document Editor | `stevanini-doc.css` | proxy nginx `stirling-brand` (`nginx.conf`) |
| `immich` | Photos | `stevanini.css`, `patch.js` | `patch.js` roda no start do `immich-server` e injeta CSS/fonte no `index.html` |
| `*/docker-compose.diff` | — | — | o que foi acrescentado ao compose de cada app (proxy `*-brand`, volumes, `command`) |

No servidor os arquivos ficam em `~/workspace/<app>/stevanini/` (Keycloak: `~/infra/themes/stevanini/`).

## Cuidados ao ajustar
- **Cache:** o navegador guarda o CSS. No Keycloak, troque o nome do arquivo (`stevanini-auth-N.css`) e o `styles=` em `theme.properties`. No Paperless/Stirling, aumente o `?v=N` do CSS no `nginx.conf`. No Photos o `patch.js` já versiona pelo hash.
- **Medidas do card (alvo):** 416px de largura, raio 24px, campos 42px com raio 10px, rótulo 14px/500, texto do campo 14px/400, botão 15,744px/600; cores `#211f1a` (fundo), `#2b2923` (card), `#4a4639` (borda do campo), degradê `#f8b62d → #f69702`.
- **Título/pássaro:** o título é texto real em Google Sans (SVG como imagem não carrega fonte externa); o pássaro é `stevanini-favicon.svg`.
- **Keycloak:** realm `master` com `loginTheme`/`adminTheme=stevanini`, `displayName="Stevanini Auth"`, idioma pt-BR (rótulo "E-mail" vem de `messages/messages_pt_BR.properties`).
- `docker-compose.infra.yml` (raiz do repo) já monta o tema do Keycloak em `./custom/keycloak/themes/stevanini`; o instalador `install-infra.sh` ainda NÃO instala o tema — rode `./deploy.sh keycloak` depois dele.

## Keycloak: tema da tela de conta (account)
O tema `stevanini` tem `login`, `admin` e `account`. O realm só usa o `account` se o campo estiver preenchido
(na UI: Realm settings → Themes → Account theme). Sem acesso à UI, direto no banco, depois reiniciar o Keycloak:
`update realm set account_theme='stevanini' where name in ('master','movimenta');`
