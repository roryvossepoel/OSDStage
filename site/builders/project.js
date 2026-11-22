const D = Deployment;
const h = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const byId = id => document.getElementById(id);
const storageKey = 'osdstage.deployment.preview.1';
const empty = () => ({base:null, parts:{}});
let project = empty(), unmountApps, noticeTimer, lastEditorLink;
try {
  const saved = JSON.parse(sessionStorage.getItem(storageKey));
  if (saved && saved.parts && Object.keys(saved.parts).every(k => k === 'apps' || D.types.includes(k))) project = saved;
} catch {}
const link = key => '#/' + key;
const clone = data => JSON.parse(JSON.stringify(data));
function persist() { try { sessionStorage.setItem(storageKey, JSON.stringify(project)); } catch {} }
function say(text) {
  byId('project-notice').textContent = text; clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => byId('project-notice').textContent = '', 3300);
}
function commit(key, state) {
  if (key === 'base') {
    project.base = clone(state);
    rebuildApps();
  } else project.parts[key] = clone(state);
  persist();
  location.hash = link('home');
  say((key === 'base' ? 'Base settings' : D.title(key)) + ' saved to your deployment.');
}
function rebuildApps() {
  unmountApps?.();
  unmountApps = mountApps();
}
function current() { return location.hash.startsWith('#/') ? location.hash.slice(2) : 'home'; }
function countParts() { const n = Object.keys(project.parts).length; return n + (n === 1 ? ' component' : ' components'); }
function sidebar() {
  const el = byId('project-summary'); if (!el) return;
  const b = BuilderScopes.baseState(project.base || {}), rows = D.rows(project);
  const row = (key, name, desc, removable) => '<li><a href="'+link(key)+'" class="'+(current() === key ? 'current' : '')+'" aria-label="Edit '+h(name)+'"><strong>'+h(name)+'</strong><small>'+h(desc)+'</small></a>'+(removable ? '<button class="part-remove" data-drop="'+key+'" title="Remove '+h(name)+'" aria-label="Remove '+h(name)+'">×</button>' : '')+'</li>';
  el.innerHTML = '<h3>Your deployment</h3><p class="summary-count">'+countParts()+'</p><ul class="project-list">'+row('base','Base settings', (b.moduleSource === 'local' ? 'Local module' : b.moduleVersion === 'current' ? 'Latest stable' : 'v'+b.moduleVersion)+' · '+(b.final === 'None' ? 'Leave running' : b.final),false)+rows.map(([k,v])=>row(k,D.title(k),D.detail(k,v),true)).join('')+'</ul>'+
  (!rows.length?'<p>Choose a component to add it here.</p>':'')+
  (current() === 'review' ? '<a class="action-link" href="#/home">Choose components</a>' : '<a class="action-link" href="#/review">Review deployment →</a>');
  el.querySelectorAll('[data-drop]').forEach(btn=>btn.onclick=()=>{
    const k=btn.dataset.drop; delete project.parts[k]; persist();
    if (k === 'apps') rebuildApps();
    if (k === current() && k !== 'apps') location.hash=link('home');
    sidebar(); updateCards(); renderReview();
    say(D.title(k)+' removed.');
  });
}
function updateCards() {
  for (const card of document.querySelectorAll('.builder-card[data-route]')) {
    const added = Object.hasOwn(project.parts,card.dataset.route);
    const tag = card.querySelector('.project-badge');
    if (!added) tag?.remove();
    if (added && !tag) {
      const badge=document.createElement('span'); badge.className='project-badge';badge.textContent='Added to deployment';card.querySelector('div').append(badge);
    }
  }
}
function renderReview() {
  if (!byId('review-output')) return;
  const out=D.build(project), files=out.files;
  const feedback=byId('review-help');
  feedback.replaceChildren();
  byId('review-output').hidden = !!out.issues.length;
  if (out.issues.length) {
    feedback.innerHTML='<div class="notice">'+out.issues.map(x=>'<p>'+h(x)+'</p>').join('')+'</div>';
    byId('review-output').hidden=true; return;
  }
  if(files.length) {
    feedback.innerHTML='<div class="notice"><strong>Files to supply</strong><ul>'+files.map(f=>'<li>'+h(f.purpose)+' · <code>'+h(f.path)+'</code></li>').join('')+'</ul><p>For relative paths, paste from the folder containing Files, or save the script beside that folder.</p></div>';
  }
  if (project.parts.apps?.mode === 'offline') feedback.insertAdjacentHTML('beforeend','<div class="notice">Prepare the matching USB content on a full Windows PC before offline staging.</div>');
  BuilderCodeView.render(byId('review-code'),out.code);
  byId('copy-script').onclick=async()=>{
    try { await navigator.clipboard.writeText(out.code); say('WinPE script copied.'); }
    catch {
      const t=document.createElement('textarea');t.value=out.code;byId('main').append(t);t.select();
      let copied=false;try{ copied=document.execCommand('copy'); }catch{}t.remove();
      if(copied) say('WinPE script copied.');else{const r=document.createRange();r.selectNodeContents(byId('review-code'));const sel=getSelection();sel.removeAllRanges();sel.addRange(r);say('Press Ctrl+C to copy the selected script.');}
    }
  };
  byId('download-script').onclick=()=>{
    const url=URL.createObjectURL(new Blob(['\uFEFF',out.code],{type:'text/plain;charset=utf-8'})),a=document.createElement('a');
    a.href=url;a.download='Stage-OSDStage.ps1';a.click();setTimeout(()=>URL.revokeObjectURL(url),1200);
  };
}
function show(scroll = true) {
  const k=current();
  const previous = byId('inline-editor');
  previous?.remove();
  document.querySelectorAll('[data-route][aria-expanded]').forEach(a=>a.setAttribute('aria-expanded','false'));
  updateCards(); sidebar();
  let focusTarget;
  if (k === 'apps') {
    focusTarget=byId('inline-apps');
  } else if (k === 'base' || k === 'review' || D.types.includes(k)) {
    const editor=document.createElement('section');
    editor.id='inline-editor';
    editor.className='panel inline-editor '+(k==='review'?'project-review':k==='base'?'deployment-builder':'');
    editor.tabIndex=-1;
    const trigger=document.querySelector('[data-route="'+k+'"]');
    if (k === 'base') trigger.closest('.builder-foundation').after(editor);
    else if (k === 'review') document.querySelector('.builder-component-groups').append(editor);
    else {
      const rowTop = trigger.offsetTop;
      const row = Array.from(trigger.parentElement.children).filter(card => card.offsetTop === rowTop);
      row.at(-1).after(editor);
    }
    trigger?.setAttribute('aria-expanded','true');
    editor.innerHTML=inlineEditors[k==='base'||k==='review'?k:'component'];
    if (k==='base') mountBase(); else if(k==='review') renderReview(); else mountComponent(k);
    lastEditorLink=trigger || document.querySelector('.project-summary .action-link');
    focusTarget=editor;
  } else {
    focusTarget=lastEditorLink?.isConnected ? lastEditorLink : null;
    lastEditorLink=null;
  }
  if (k !== 'base' && !D.types.includes(k)) document.title='Configuration builders · OSDStage';
  if (scroll && focusTarget) {
    focusTarget.focus({preventScroll:true});
    focusTarget.scrollIntoView({block:focusTarget.offsetHeight >= window.innerHeight ? 'start' : 'nearest'});
  }
}
document.querySelector('.skip-link').addEventListener('click', event => {
  event.preventDefault();
  byId('main').focus();
});
window.addEventListener('hashchange',()=>show());
rebuildApps();
show(!!location.hash);
