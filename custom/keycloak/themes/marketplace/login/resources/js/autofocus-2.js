// celular: o Keycloak põe autofocus no 1º campo e o teclado abre sozinho. Até o usuário tocar/teclar, todo foco
// automático em campo é desfeito (tirar o atributo não adianta: o Chrome já registrou o candidato). No computador mantém.
if(matchMedia("(pointer:coarse)").matches){
  var tocou=false,marca=function(){tocou=true};
  ["pointerdown","touchstart","keydown"].forEach(function(t){document.addEventListener(t,marca,true)});
  document.addEventListener("focusin",function(e){if(!tocou&&/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName))e.target.blur()},true);
}
