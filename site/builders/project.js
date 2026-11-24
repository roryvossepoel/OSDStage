const D = Deployment;
const h = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const byId = id => document.getElementById(id);
const storageKey = 'osdstage.deployment.preview.1';
const empty = () => ({base:null, parts:{}});
let project = empty(), appPicker, noticeTimer, lastEditorLink, pendingAddition;
try {
  const saved = JSON.parse(sessionStorage.getItem(storageKey));
  if (saved && saved.parts && Object.keys(saved.parts).every(k => k === 'apps' || D.types.includes(k))) project = D.onlineProject(saved);
} catch {}
const link = key => '#/' + key;
const clone = data => JSON.parse(JSON.stringify(data));
function persist() { try { sessionStorage.setItem(storageKey, JSON.stringify(project)); } catch {} }
function say(text) {
  byId('project-notice').textContent = text; clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => byId('project-notice').textContent = '', 3300);
}
function commit(key, state) {
  const before = new Set(D.selections(project).map(item=>item.key));
  if (key === 'base') {
    project.base = clone(state);
    rebuildApps();
  } else project.parts[key] = clone(state);
  persist();
  const added = D.selections(project).filter(item=>!before.has(item.key));
  if (added.length) pendingAddition = {added, trigger:document.querySelector('[data-route="'+key+'"]')};
  else say((key === 'base' ? 'Deployment settings' : D.title(key))+' saved.');
  location.hash = link('home');
}
function rebuildApps() {
  appPicker?.close();
  appPicker = mountApps();
}
function current() { return location.hash.startsWith('#/') ? location.hash.slice(2) : 'home'; }

function announceAddition(added, trigger) {
  const first = added[0];
  const message = added.length === 1 ? first.name : added.length+' items';
  say(message+' added to your deployment.');
  const list=byId('selection-list');
  const addedKeys=new Set(added.map(item=>item.key));
  const targets=Array.from(list.children).filter(row=>addedKeys.has(row.dataset.selection));
  if (!targets.length || matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  // If the summary is outside the viewport, animate the originating card instead.
  const row=targets[0], listBox=list.getBoundingClientRect();
  const summaryVisible = listBox.bottom>0 && listBox.top<innerHeight;
  const highlight = element => element.animate([
    {backgroundColor:'var(--wash)',boxShadow:'inset 3px 0 var(--accent)'},
    {backgroundColor:'transparent',boxShadow:'inset 0 0 transparent'}
  ],{duration:900,easing:'ease-out'});
  if (!summaryVisible) { if (trigger?.isConnected) highlight(trigger); return; }
  const oldBox=row.getBoundingClientRect();
  if (oldBox.top<listBox.top || oldBox.bottom>listBox.bottom) list.scrollTop+=oldBox.top-listBox.top;
  targets.forEach(highlight);
  const end=row.getBoundingClientRect(), start=trigger?.getBoundingClientRect();
  if (!start || start.bottom<0 || start.top>innerHeight || end.top<0 || end.top>innerHeight) return;
  const x=start.right-22, y=start.top+start.height/2;
  const dx=end.left+12-x, dy=end.top+end.height/2-y;
  const mark=document.createElement('span');
  mark.className='selection-flight'; mark.textContent='✓'; mark.setAttribute('aria-hidden','true');
  mark.style.left=x+'px'; mark.style.top=y+'px'; document.body.append(mark);
  const flight=mark.animate([
    {transform:'translate(-50%, -50%) scale(.8)',opacity:0},
    {offset:.18,opacity:1},
    {transform:'translate(calc(-50% + '+dx+'px), calc(-50% + '+dy+'px)) scale(.55)',opacity:0}
  ],{duration:480,easing:'ease-in-out'});
  flight.finished.then(()=>mark.remove(),()=>mark.remove());
}
let lastSelections='';
function sidebar() {
  const items=D.selections(project), list=byId('selection-list');
  const review=byId('selection-review'), reviewing=current()==='review';
  review.href=link(reviewing?'home':'review');
  review.textContent=reviewing?'Choose components':'Review deployment';
  const signature=JSON.stringify(items);
  if (lastSelections===signature) return;
  lastSelections=signature;
  byId('selection-count').textContent=items.length+' '+(items.length===1?'item':'items');
  list.hidden=!items.length;
  byId('selection-empty').hidden=!!items.length;
  const scrollTop=list.scrollTop;
  list.innerHTML=items.map((item,i)=>{
    const label='<strong>'+h(item.name)+'</strong><small>'+h(item.detail)+'</small>';
    const edit=item.editable ? '<button type="button" class="selection-edit" data-edit="'+i+'" aria-haspopup="dialog" aria-label="Edit '+h(item.name)+'">'+label+'</button>' : '<div class="selection-label">'+label+'</div>';
    return '<li data-selection="'+h(item.key)+'">'+edit+'<button type="button" class="part-remove" data-remove-item="'+i+'" aria-label="Remove '+h(item.name)+'" title="Remove '+h(item.name)+'">×</button></li>';
  }).join('');
  list.scrollTop=scrollTop;
  list.onclick=event=>{
    const button=event.target.closest('button');
    if (!button) return;
    const editing=button.hasAttribute('data-edit');
    const index=Number(editing?button.dataset.edit:button.dataset.removeItem), item=items[index];
    const isApp=item.type==='builtin' || item.type==='repo';
    if (editing) {
      if (isApp) appPicker.open(item.type,item.id,button);
      else location.hash=link(item.type);
      return;
    }
    if (isApp) appPicker.remove(item.type,item.id);
    else {
      D.removeComponent(project.parts,item);
      persist(); sidebar(); updateCards(); renderReview();
    }
    say(item.name+' removed.');
    const next=list.children[Math.min(index,list.children.length-1)]?.querySelector('.part-remove');
    (next || review).focus({preventScroll:true});
  };
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
  if (previous?.open) previous.close();
  previous?.remove();
  if (byId('app-dialog').open) byId('app-dialog').close();
  updateCards(); sidebar();
  let focusTarget;
  if (k === 'apps') {
    focusTarget=byId('inline-apps');
  } else if (k === 'review') {
    const review=document.createElement('section');
    review.id='inline-editor';
    review.className='panel inline-editor project-review';
    review.tabIndex=-1;
    review.innerHTML=inlineEditors.review;
    document.querySelector('.builder-component-groups').append(review);
    renderReview();
    focusTarget=review;
    lastEditorLink=byId('inline-apps');
  } else if (k === 'base' || D.types.includes(k)) {
    const isBase=k==='base', titleId=isBase?'editor-title':'component-title';
    const editor=document.createElement('dialog');
    editor.id='inline-editor';
    editor.className='builder-dialog'+(isBase?' deployment-builder':'');
    editor.setAttribute('aria-labelledby',titleId);
    editor.innerHTML=inlineEditors[isBase?'base':'component'];
    byId('main').append(editor);
    if (isBase) mountBase(); else mountComponent(k);
    const cancel=()=>{location.hash=link('home');};
    editor.oncancel=event=>{event.preventDefault();cancel();};
    editor.querySelector('.dialog-close').onclick=cancel;
    lastEditorLink=document.querySelector('[data-route="'+k+'"]');
    editor.showModal();
    byId(titleId).focus();
  } else {
    focusTarget=lastEditorLink?.isConnected ? lastEditorLink : null;
    lastEditorLink=null;
  }
  if (pendingAddition && k==='home') {
    const {added,trigger}=pendingAddition; pendingAddition=null;
    requestAnimationFrame(()=>announceAddition(added,trigger));
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
const selectionToggle = byId('selection-toggle');
selectionToggle.hidden = false;
selectionToggle.addEventListener('click', () => {
  const expanded = selectionToggle.getAttribute('aria-expanded') === 'true';
  selectionToggle.setAttribute('aria-expanded', String(!expanded));
});
window.addEventListener('hashchange',()=>show());
rebuildApps();
show(!!location.hash);
