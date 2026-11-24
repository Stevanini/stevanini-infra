// O app abre o login com ?ui_theme=light|dark (o tema que o usuário está usando). Guarda na aba para as próximas páginas do fluxo
// (cadastro, esqueci a senha, erro de senha) e aplica antes de pintar; sem o parâmetro, o CSS segue o tema do sistema.
(function(){var t=null;try{var m=/[?&]ui_theme=(light|dark)/.exec(location.search);if(m){t=m[1];sessionStorage.setItem("ui_theme",t)}else t=sessionStorage.getItem("ui_theme")}catch(e){}
if(t)document.documentElement.setAttribute("data-theme",t)})();
