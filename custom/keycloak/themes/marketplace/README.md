# Tema de login do Keycloak (Marketplace)

Publicado por `stevanini-infra/custom/deploy.sh keycloak` em `~/infra/themes/marketplace` e montado em `docker-compose.infra.yml`; o realm usa `loginTheme=marketplace`. Cores: espelham `mr/app/src/constants/theme.ts`.

O Cloudflare guarda CSS/imagens por 30 dias. Ao alterar `marketplace-N.css` ou `logo-N.svg`, **incremente o N** no nome (e em `theme.properties`/CSS) e reinicie o Keycloak (`docker compose restart keycloak`).
