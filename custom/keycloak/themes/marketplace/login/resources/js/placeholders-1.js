// os templates do Keycloak não têm placeholder; preenche por id do campo (o de senha muda entre login e cadastro)
document.addEventListener("DOMContentLoaded",function(){
  var cadastro=!!document.getElementById("kc-register-form");
  var p={username:"seu@email.com",email:"seu@email.com",password:cadastro?"Crie uma senha":"Digite sua senha","password-new":"Crie uma senha","password-confirm":"Repita a senha",firstName:"Ex.: Maria",lastName:"Ex.: da Silva"};
  for(var id in p){var el=document.getElementById(id);if(el&&!el.placeholder)el.placeholder=p[id]}
});
