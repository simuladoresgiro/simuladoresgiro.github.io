/* =====================================================================
   MENU LATERAL COMPARTILHADO — Central de Simuladores Capital de Giro
   ---------------------------------------------------------------------
   Para usar em uma página, basta incluir no <head>:
       <script src="menu.js"></script>
   O menu é inserido automaticamente à esquerda e o link da página atual
   fica destacado. Para incluir, renomear ou remover simuladores, altere
   SOMENTE a lista MENU_SIMULADORES abaixo.

   Opcional: se o nome do arquivo não corresponder a um item do menu
   (ex.: versão de teste), indique qual item destacar no <body>:
       <body data-menu-ativo="SimuladorPEAC.html">
   ===================================================================== */

const MENU_SIMULADORES = [
    { titulo: null, itens: [
        { nome: "Início", arquivo: "./" }
    ]},
    { titulo: "Novas operações", itens: [
        { nome: "PEAC FGI", arquivo: "SimuladorPEAC.html" },
        { nome: "PRONAMPE / PROCRED", arquivo: "SimuladorPRONAMPE.html" },
        { nome: "Prefixado (SAC / PRICE)", arquivo: "SimuladorPREFIXADO.html" },
        { nome: "SAC (CDI+ST / %CDI)", arquivo: "SimuladorSAC.html" }
    ]},
    { titulo: "Histórico", itens: [
        { nome: "PEAC FGI", arquivo: "SimuladorPEACHist.html" },
        { nome: "PRONAMPE / PROCRED", arquivo: "SimuladorPRONAMPEHist.html" },
        { nome: "SAC (CDI+ST / %CDI)", arquivo: "SimuladorSACHist.html" }
    ]},
    { titulo: "Prorrogações", itens: [
        { nome: "PEAC FGI", arquivo: "SimuladorPEACProrrog.html" },
        { nome: "PRONAMPE / PROCRED", arquivo: "SimuladorPRONAMPEProrrog.html" }
    ]},
    { titulo: "Amortizações", itens: [
        { nome: "PEAC FGI", arquivo: "SimuladorPEACAmort.html" },
        { nome: "PRONAMPE / PROCRED", arquivo: null, tag: "EM BREVE" },
        { nome: "Prefixado (SAC / PRICE)", arquivo: null, tag: "EM BREVE" },
        { nome: "SAC (CDI+ST / %CDI)", arquivo: null, tag: "EM BREVE" }
    ]}
];

const MENU_RODAPE = "Desenvolvido por F3421879 - Guerreiro · v1.0";

(function(){
    const CSS = `
    :root { --menu-largura:248px; }
    body.com-menu { padding-left:var(--menu-largura); }
    .menu-lateral {
        position:fixed; inset:0 auto 0 0; width:var(--menu-largura); z-index:50;
        background:linear-gradient(180deg, #003366 0%, #002244 100%); color:#dbe6f3;
        display:flex; flex-direction:column; font-family:"Segoe UI", system-ui, Arial, sans-serif;
        transition:transform .25s ease; box-sizing:border-box;
    }
    .menu-lateral * { box-sizing:border-box; }
    .menu-marca { display:flex; align-items:center; gap:10px; padding:20px 18px 16px; text-decoration:none; color:#fff; border-bottom:1px solid rgba(255,255,255,0.08); }
    .menu-marca .menu-logo { width:34px; height:34px; border-radius:9px; background:#fcd116; color:#003366; display:grid; place-items:center; font-weight:800; font-size:0.95rem; flex:0 0 auto; }
    .menu-marca strong { display:block; font-size:0.98rem; }
    .menu-marca small { display:block; font-size:0.72rem; color:#9fb6d1; }
    .menu-lateral nav { flex:1; overflow-y:auto; padding:10px 10px 16px; }
    .menu-grupo { margin-top:14px; }
    .menu-grupo:first-child { margin-top:4px; }
    .menu-titulo { font-size:0.68rem; font-weight:700; letter-spacing:0.08em; text-transform:uppercase; color:#8fa8c6; padding:6px 10px; }
    .menu-link { display:flex; align-items:center; gap:10px; padding:8px 10px; margin:2px 0; border-radius:8px; color:#dbe6f3; text-decoration:none; font-size:0.88rem; border-left:3px solid transparent; transition:background .15s ease; }
    .menu-link:hover { background:rgba(255,255,255,0.07); color:#fff; }
    .menu-link.ativo { background:rgba(255,255,255,0.12); color:#fff; font-weight:600; border-left-color:#fcd116; }
    .menu-link .menu-ponto { width:6px; height:6px; border-radius:50%; background:currentColor; opacity:0.5; flex:0 0 auto; }
    .menu-link.ativo .menu-ponto { background:#fcd116; opacity:1; }
    .menu-link.desativado { opacity:0.45; pointer-events:none; }
    .menu-link .menu-tag { margin-left:auto; font-size:0.62rem; font-weight:700; padding:2px 6px; border-radius:999px; background:rgba(255,255,255,0.1); color:#b8cbe2; white-space:nowrap; }
    .menu-rodape { padding:12px 18px 16px; font-size:0.72rem; color:#8fa8c6; border-top:1px solid rgba(255,255,255,0.08); }
    .menu-botao { display:none; position:fixed; top:12px; left:12px; z-index:45; width:38px; height:38px; border-radius:8px; border:1px solid #dde5ef; background:#fff; color:#003366; cursor:pointer; place-items:center; box-shadow:0 2px 8px rgba(0,0,0,0.08); }
    .menu-fundo { display:none; }
    @media (max-width: 900px) {
        body.com-menu { padding-left:0; }
        .menu-lateral { transform:translateX(-100%); }
        body.menu-aberto .menu-lateral { transform:none; box-shadow:0 0 40px rgba(0,0,0,0.3); }
        body.menu-aberto .menu-fundo { display:block; position:fixed; inset:0; background:rgba(0,20,40,0.4); z-index:40; }
        .menu-botao { display:grid; }
    }
    @media print {
        body.com-menu { padding:0 !important; }
        .menu-lateral, .menu-botao, .menu-fundo { display:none !important; }
    }`;

    function montar(){
        const estilo = document.createElement("style");
        estilo.textContent = CSS;
        document.head.appendChild(estilo);

        const atual = (document.body.dataset.menuAtivo || location.pathname.split("/").pop() || "index.html").toLowerCase();
        const emTesteV2 = /_v2\.html$/i.test(location.pathname);

        const grupos = MENU_SIMULADORES.map(grupo => {
            const titulo = grupo.titulo ? `<div class="menu-titulo">${grupo.titulo}</div>` : "";
            const itens = grupo.itens.map(item => {
                const tag = item.tag ? `<span class="menu-tag">${item.tag}</span>` : "";
                if(!item.arquivo){
                    return `<span class="menu-link desativado"><span class="menu-ponto"></span>${item.nome}${tag}</span>`;
                }
                const ativo = item.arquivo.toLowerCase() === atual;
                // Em páginas de teste (_v2), os links levam às versões _v2 dos simuladores
                const destino = emTesteV2 && /^Simulador.*\.html$/i.test(item.arquivo)
                    ? item.arquivo.replace(/\.html$/i, "_v2.html")
                    : item.arquivo;
                return `<a class="menu-link${ativo ? " ativo" : ""}" href="./${destino}"${ativo ? ' aria-current="page"' : ""}><span class="menu-ponto"></span>${item.nome}${tag}</a>`;
            }).join("");
            return `<div class="menu-grupo">${titulo}${itens}</div>`;
        }).join("");

        const aside = document.createElement("aside");
        aside.className = "menu-lateral";
        aside.innerHTML = `
            <a class="menu-marca" href="./index.html">
                <span class="menu-logo">BB</span>
                <span><strong>Capital de Giro</strong><small>Central de Simuladores</small></span>
            </a>
            <nav aria-label="Simuladores">${grupos}</nav>
            <div class="menu-rodape">${MENU_RODAPE}</div>`;

        const fundo = document.createElement("div");
        fundo.className = "menu-fundo";
        fundo.addEventListener("click", () => alternarMenu(false));

        const botao = document.createElement("button");
        botao.type = "button";
        botao.className = "menu-botao";
        botao.setAttribute("aria-label", "Abrir menu");
        botao.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h16"/></svg>';
        botao.addEventListener("click", () => alternarMenu());

        document.body.prepend(aside, fundo, botao);
        document.body.classList.add("com-menu");
    }

    window.alternarMenu = function(abrir){
        const aberto = typeof abrir === "boolean" ? abrir : !document.body.classList.contains("menu-aberto");
        document.body.classList.toggle("menu-aberto", aberto);
    };

    if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", montar);
    else montar();
})();
