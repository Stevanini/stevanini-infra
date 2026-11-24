// Data de nascimento: o <input type="date"> abre um calendário que obriga a rolar décadas; vira texto DD/MM/AAAA
// com teclado numérico e máscara (igual a src/lib/birth-date.ts do app). O Keycloak (html5-date) recebe AAAA-MM-DD.
(function(){
  function mask(t){var d=t.replace(/\D/g,"").slice(0,8);return [d.slice(0,2),d.slice(2,4),d.slice(4)].filter(Boolean).join("/")}
  function parse(t,today){
    var m=/^(\d{2})\/(\d{2})\/(\d{4})$/.exec(t);if(!m)return null;
    var dt=new Date(Date.UTC(+m[3],+m[2]-1,+m[1]));
    if(dt.getUTCDate()!==+m[1]||dt.getUTCMonth()!==+m[2]-1)return null; // 31/02 vira março no Date
    if(dt.getTime()>=today.getTime()||+m[3]<today.getFullYear()-120)return null;
    return m[3]+"-"+m[2]+"-"+m[1];
  }
  if(typeof module!=="undefined"){module.exports={mask:mask,parse:parse};return}
  document.addEventListener("DOMContentLoaded",function(){
    var el=document.getElementById("birthdate");if(!el)return;
    var iso=/^(\d{4})-(\d{2})-(\d{2})$/.exec(el.value); // volta preenchido quando o cadastro dá erro
    el.type="text";el.inputMode="numeric";el.autocomplete="bday";el.maxLength=10;el.placeholder="DD/MM/AAAA";
    if(iso)el.value=iso[3]+"/"+iso[2]+"/"+iso[1];
    function check(){el.setCustomValidity(!el.value||parse(el.value,new Date())?"":"Data inválida. Use DD/MM/AAAA, ex.: 25/08/1970")}
    el.addEventListener("input",function(){el.value=mask(el.value);check()});
    el.form.addEventListener("submit",function(e){
      var v=parse(el.value,new Date());
      if(el.value&&!v){e.preventDefault();check();el.reportValidity();return}
      if(v)el.value=v;
    });
  });
})();
