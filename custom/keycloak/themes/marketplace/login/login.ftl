<#import "template.ftl" as layout>
<#-- displayMessage=false: o aviso do template base ficaria acima do formulário; aqui ele aparece abaixo do "Entrar". -->
<@layout.registrationLayout displayInfo=social.displayInfo displayMessage=false; section>
    <#if section = "header">
        ${msg("doLogIn")}
    <#elseif section = "form">
        <div id="kc-form-wrapper">
            
            <#-- 1. SOCIAL LOGIN (GOOGLE) -->
            <#if realm.password && social.providers??>
                <div id="kc-social-providers">
                    <ul class="social-list">
                        <#list social.providers as p>
                            <li>
                                <a href="${p.loginUrl}" id="social-${p.alias}" class="btn-social">
                                    <#if p.alias == "google"><svg width="20" height="20" viewBox="0 0 48 48" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.9 2.4 30.4 0 24 0 14.6 0 6.5 5.4 2.6 13.2l7.9 6.1C12.4 13.6 17.7 9.5 24 9.5z"/><path fill="#4285F4" d="M46.5 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.7c-.6 3-2.3 5.5-4.8 7.2l7.6 5.9c4.4-4.1 7-10.1 7-17.6z"/><path fill="#FBBC05" d="M10.5 28.7A14.5 14.5 0 0 1 9.5 24c0-1.6.3-3.2.8-4.7l-7.9-6.1A24 24 0 0 0 0 24c0 3.9.9 7.5 2.6 10.8l7.9-6.1z"/><path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.6-5.9c-2.1 1.4-4.9 2.3-8.3 2.3-6.3 0-11.6-4.1-13.5-9.8l-7.9 6.1C6.5 42.6 14.6 48 24 48z"/></svg></#if><#if p.alias == "facebook"><svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true"><path fill="#1877F2" d="M24 12a12 12 0 1 0-13.9 11.9v-8.4H7.1V12h3V9.4c0-3 1.8-4.7 4.5-4.7 1.3 0 2.7.2 2.7.2v3h-1.5c-1.5 0-2 .9-2 1.9V12h3.4l-.5 3.5h-2.9v8.4A12 12 0 0 0 24 12z"/><path fill="#fff" d="M16.7 15.5l.5-3.5h-3.4V9.8c0-1 .5-1.9 2-1.9h1.5v-3s-1.4-.2-2.7-.2c-2.7 0-4.5 1.7-4.5 4.7V12h-3v3.5h3v8.4a12 12 0 0 0 3.7 0v-8.4h2.9z"/></svg></#if>
                                    <#if p.alias == "apple"><svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M16.37 12.63c-.02-2.2 1.8-3.26 1.88-3.31-1.02-1.5-2.62-1.7-3.19-1.73-1.36-.14-2.65.8-3.34.8-.69 0-1.75-.78-2.88-.76-1.48.02-2.85.86-3.61 2.19-1.54 2.67-.39 6.63 1.1 8.8.73 1.06 1.6 2.25 2.74 2.21 1.1-.04 1.52-.71 2.85-.71 1.33 0 1.7.71 2.86.69 1.18-.02 1.93-1.08 2.65-2.15.84-1.23 1.18-2.42 1.2-2.48-.03-.01-2.3-.88-2.26-3.55zM14.2 6.12c.6-.73 1.01-1.74.9-2.75-.87.04-1.92.58-2.54 1.31-.56.65-1.05 1.68-.92 2.67.97.07 1.96-.49 2.56-1.23z"/></svg></#if>
                                    <span><#if p.alias == "apple">Entrar com Apple<#else>${p.displayName}</#if></span>
                                </a>
                            </li>
                        </#list>
                    </ul>
                </div>
            </#if>

            <#-- 2. BOTÃO "ENTRAR COM E-MAIL": o formulário só aparece ao clicar (ou se voltou com erro) -->
            <button type="button" id="open-email-login" class="btn-social" aria-controls="kc-form-login" aria-expanded="false">
                <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="#F0CC7A" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/></svg>
                <span>Entrar com e-mail</span>
            </button>

            <#-- Voltar: ocupa o lugar das redes sociais enquanto o formulário está aberto -->
            <div id="close-email-login" class="back-link"><a href="#">&larr; Entrar de outra forma</a></div>

            <#-- 3. LOGIN FORM -->
            <form id="kc-form-login" action="${url.loginAction}" method="post">
                <div class="form-field">
                    <label for="username">Endereço de e-mail</label>
                    <input id="username" name="username" type="text" placeholder="seu@email.com" autofocus autocomplete="off" />
                </div>
                
                <div class="form-field">
                    <label for="password">Senha</label>
                    <input id="password" name="password" type="password" placeholder="Digite sua senha" autocomplete="current-password" />
                </div>

                <div class="form-options">
                    <div class="remember-me">
                        <input id="rememberMe" name="rememberMe" type="checkbox">
                        <label for="rememberMe">Mantenha-me conectado</label>
                    </div>
                    
                    <#if realm.resetPasswordAllowed>
                        <div class="forgot-pwd">
                            <a href="${url.loginResetCredentialsUrl}">Esqueceu sua senha?</a>
                        </div>
                    </#if>
                </div>

                <div class="action-btn">
                    <button type="submit" id="kc-login" name="login">Entrar</button>
                </div>

                <#if message?has_content && message.type != 'warning'>
                    <div class="alert alert-${message.type} form-message" role="alert">${kcSanitize(message.summary)?no_esc}</div>
                </#if>
            </form>
            <script>
            (function(){var w=document.getElementById("kc-form-wrapper"),b=document.getElementById("open-email-login");
            function open(){w.classList.add("email-open");b.setAttribute("aria-expanded","true");var u=document.getElementById("username");if(u&&matchMedia("(pointer:fine)").matches)u.focus()}
            b.addEventListener("click",open);
            document.querySelector("#close-email-login a").addEventListener("click",function(e){e.preventDefault();w.classList.remove("email-open");b.setAttribute("aria-expanded","false")});
            <#if message?has_content || (login.username)!?has_content>open();</#if>})();
            </script>

            <#-- 4. FOOTER -->
            <#if realm.registrationAllowed>
                <div class="form-footer">
                    <span>Novo usuário?</span>
                    <a href="${url.registrationUrl}">Cadastre-se</a>
                </div>
            </#if>
        </div>
    </#if>
</@layout.registrationLayout>
