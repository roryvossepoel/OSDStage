for (const link of document.querySelectorAll('main [data-route]')) {
  link.setAttribute('href', '#/' + link.dataset.route);
}

const saveBar = '<div class="project-savebar"><a href="#/home">Cancel</a><button type="button" class="btn primary" id="commit"></button></div>';
const inlineEditors = {
  base: '<div class="content" id="base-form"></div><div class="project-messages" id="base-errors"></div>' + saveBar,
  component: '<div class="content"><div class="component-title-line"><img id="component-icon" alt="" width="28" height="28"><h3 id="component-title"></h3></div><p id="component-description"></p><div id="component-form"></div></div><div class="project-messages" id="component-errors"></div>' + saveBar,
  review: `<div class="content"><h2>Review your WinPE script.</h2>
    <p>Run this script in WinPE after Windows has been applied and before the first reboot.</p>
    <div id="review-help"></div><div id="review-output">
    <div class="codebox"><div class="codebar"><span>Stage-OSDStage.ps1</span><button id="copy-script">Copy WinPE script</button></div>
    <pre id="review-code" tabindex="0"></pre></div><div class="actions"><button class="btn" id="download-script">Download .ps1</button></div></div></div>`
};
