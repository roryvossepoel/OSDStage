const catalogHome = document.getElementById("main").cloneNode(true);
for (const link of catalogHome.querySelectorAll("[data-route]")) {
  link.setAttribute("href", "#/" + link.dataset.route);
}
const screenTemplates = {
  home: catalogHome.innerHTML,
  base: `<div class="builder-context">
<nav aria-label="Builder navigation">
<a href="#/home">← All builders</a>
</nav>
<span class="badge">Deployment preview</span>
</div>
<div class="intro">
<div>
<div class="eyebrow">Your foundation</div>
<h1>Set up OSDStage.</h1>
<p>Configure the module once for this deployment.</p>
</div>
</div>
<div class="component-layout project-columns">
<section class="panel">
<div class="content" id="base-form">
</div>
<div class="project-messages" id="base-errors">
</div>
<div class="project-savebar">
<a href="#/home">Cancel</a>
<button type="button" class="btn primary" id="commit">
</button>
</div>
</section>
<aside class="project-aside">
<section id="project-summary" class="project-summary" aria-label="Your deployment">
</section>
</aside>
</div>`,
  component: `<div class="builder-context">
<nav aria-label="Builder navigation">
<a href="#/home">← All builders</a>
</nav>
<span class="badge">Deployment preview</span>
</div>
<div class="intro">
<div>
<div class="eyebrow">Configuration builder</div>
<div class="component-title-line">
<img id="component-icon" alt="" width="36" height="36">
<h1 id="component-title">
</h1>
</div>
<p id="component-description">
</p>
</div>
</div>
<div class="component-layout project-columns">
<section class="panel">
<div class="content" id="component-form">
</div>
<div class="project-messages" id="component-errors">
</div>
<div class="project-savebar">
<a href="#/home">Cancel</a>
<button type="button" class="btn primary" id="commit">
</button>
</div>
</section>
<aside class="project-aside">
<section id="project-summary" class="project-summary" aria-label="Your deployment">
</section>
</aside>
</div>`,
  apps: `<div class="builder-context">
<nav aria-label="Builder navigation">
<a href="#/home">← All builders</a>
</nav>
<span class="badge">Deployment preview</span>
</div>
<div class="intro">
<div>
<div class="eyebrow">Optional · Apps component</div>
<h1>Choose your apps.</h1>
<p>Select the built-in apps and repository packages to add to your deployment.</p>
</div>
<div class="headtools">
<button class="btn" id="loadSettings">Open selections</button>
<button class="btn" id="saveSettings">Save selections</button>
<button class="reset" id="reset">↺ Reset</button>
<input id="settingsFile" type="file" accept=".json,application/json" hidden>
</div>
</div>
<div class="shell">
<aside>
<nav class="steps" id="steps" aria-label="Builder steps">
</nav>
</aside>
<section class="panel" aria-label="App selection">
<div class="content" id="content" tabindex="-1">
</div>
<div class="navfoot">
<button class="btn" id="back">← Back</button>
<span class="small muted" id="position">
</span>
<button class="btn primary" id="next">Continue →</button>
</div>
</section>
<aside class="right">
<aside class="project-aside">
<section id="project-summary" class="project-summary" aria-label="Your deployment">
</section>
</aside>
</aside>
</div>`,
  review: `<div class="builder-context">
<nav aria-label="Builder navigation">
<a href="#/home">← All builders</a>
</nav>
<span class="badge">Deployment preview</span>
</div>
<div class="intro">
<div>
<div class="eyebrow">Your deployment</div>
<h1>Review your WinPE script.</h1>
<p>Run this block in WinPE after Windows has been applied and before the first reboot.</p>
</div>
</div>
<div class="component-layout project-columns">
<section class="panel">
<div class="content">
<h2>Staging script</h2>
<div id="review-help">
</div>
<div id="review-output">
<div class="codebox">
<div class="codebar">
<span>Stage-OSDStage.ps1</span>
<button id="copy-script">Copy WinPE script</button>
</div>
<pre id="review-code" tabindex="0">
</pre>
</div>
<div class="actions">
<button class="btn" id="download-script">Download .ps1</button>
</div>
</div>
</div>
</section>
<aside class="project-aside">
<section id="project-summary" class="project-summary" aria-label="Your deployment">
</section>
</aside>
</div>`
};
