// mesmo ícone SVG dos outros apps Stevanini (o template do Keycloak fixa um favicon.ico)
(function(){var u=document.currentScript.src.replace(/js\/favicon-2\.js.*$/,"img/favicon.svg"),l=document.querySelector("link[rel~=icon]");if(!l){l=document.createElement("link");l.rel="icon";document.head.appendChild(l)}l.type="image/svg+xml";l.href=u})();

/* sem foco automático no 1º campo (igual aos outros apps) */
(function(){var u=0,n=0;["pointerdown","keydown"].forEach(function(e){addEventListener(e,function(){u=1},true)});var i=setInterval(function(){var a=document.activeElement;if(u||++n>30)return clearInterval(i);if(a&&a.tagName=="INPUT"){a.blur();clearInterval(i)}},100)})();
