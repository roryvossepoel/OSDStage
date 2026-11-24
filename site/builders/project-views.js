for (const link of document.querySelectorAll('main [data-route]')) {
  link.setAttribute('href', '#/' + link.dataset.route);
  link.setAttribute('aria-haspopup', 'dialog');
}

const closeEditor = '<button type="button" class="dialog-close" aria-label="Close settings">×</button></div>';
const saveBar = '<div class="dialog-actions"><a class="btn" href="#/home">Cancel</a><button type="button" class="btn primary" id="commit"></button></div>';
const inlineEditors = {
  base: '<div class="dialog-head"><h2 tabindex="-1" id="editor-title">Deployment settings</h2>'+closeEditor+
    '<div class="dialog-body"><div id="base-form"></div><div class="project-messages" id="base-errors"></div></div>' + saveBar,
  component: '<div class="dialog-head"><img id="component-icon" alt="" width="32" height="32"><h2 tabindex="-1" id="component-title"></h2>'+closeEditor+
    '<div class="dialog-body"><p id="component-description"></p><div id="component-form"></div><div class="project-messages" id="component-errors"></div></div>' + saveBar,
  review: `<div class="content"><h2>Review your WinPE script.</h2>
    <p>Run this script in WinPE after Windows has been applied and before the first reboot.</p>
    <div id="review-help"></div><div id="review-output">
    <div class="codebox"><div class="codebar"><span>Stage-OSDStage.ps1</span><button id="copy-script">Copy WinPE script</button></div>
    <pre id="review-code" tabindex="0"></pre></div><div class="actions"><button class="btn" id="download-script">Download .ps1</button></div></div></div>`
};
