function mountApps() {
 const C = BuilderCore, S = BuilderScopes, $ = byId, esc = h;
 const base = S.baseState(project.base || {});
 const catalog = base.source !== 'builtin' ? base.catalog.trim() : '';
 let s = D.appsForBase(project.parts.apps || {}, base);
 let catalogRows = s.repoItems.slice(), activeRequest, closed = false, importVersion = 0;
 let status = '';
const categories={Microsoft365Apps:'Productivity',MicrosoftTeams:'Productivity',AdobeAcrobatUnified:'Productivity',GoogleChromeEnterprise:'Browsers',MozillaFirefoxEnterprise:'Browsers',CiscoWebex:'Productivity',ZoomWorkplace:'Productivity',MicrosoftCompanyPortal:'Utilities',VisualStudioCode:'Utilities',CMTraceOpen:'Utilities','7Zip':'Utilities',VisualCRedist:'Runtimes',DotNetRuntime:'Runtimes'};
const descriptions={Microsoft365Apps:'Office applications',MicrosoftTeams:'Work and school',AdobeAcrobatUnified:'PDF reader & licensed Acrobat',GoogleChromeEnterprise:'Enterprise browser',MozillaFirefoxEnterprise:'Rapid or ESR channel',CiscoWebex:'Meetings & collaboration',ZoomWorkplace:'Meetings & collaboration',MicrosoftCompanyPortal:'Company Portal',VisualStudioCode:'System-wide code editor',CMTraceOpen:'Deployment log viewer','7Zip':'File compression',VisualCRedist:'Visual C++ v14 prerequisites',DotNetRuntime:'Runtime, Desktop Runtime or both'};
 function saveSelection() {
   // The generator's source describes the selected workloads. The base controls which catalogs are shown.
   s.source = s.repoSelected.length ? (s.selected.length ? 'both' : 'repository') : 'builtin';
   const chosen = s.selected.length + s.repoSelected.length;
   if (chosen) {
     project.parts.apps = {...s, repoItems:catalogRows.filter(p => s.repoSelected.includes(p.id) && AppCatalog.selectable(p))};
   } else {
     delete project.parts.apps;
   }
   const unknown = s.selected.filter(id=>!APPS.some(a=>a.Id===id));
   const errors = chosen ? S.validateApps(project.parts.apps, APPS) : [];
   $('app-errors').innerHTML = errors.map(e => '<p class="validation">'+esc(e.message)+'</p>').join('');
   for (const id of unknown) {
     const button = document.createElement('button');
     button.type='button'; button.className='btn'; button.textContent='Remove unavailable app · '+id;
     button.onclick=()=>{s.selected=s.selected.filter(value=>value!==id);saveSelection();};
     $('app-errors').append(button);
   }
   persist(); sidebar();
   if (current() === 'review') renderReview();
 }

 const previewCount = 6;
 const expanded = {builtin:false, repo:false};
 const dialog = $('app-dialog');
 let activeApp = null;
 const fields = {builtin:'selected', repo:'repoSelected'};

 function visibleApps(source, items) {
   const more = $(source+'-more');
   more.hidden = items.length <= previewCount;
   if (more.hidden) return items;
   more.setAttribute('aria-expanded', String(expanded[source]));
   more.textContent = expanded[source] ? 'Show fewer apps' : 'Show '+(items.length-previewCount)+' more apps';
   return expanded[source] ? items : items.slice(0,previewCount);
 }
 function card(id, name, subtitle, icon, selected, source) {
   const image = icon ? '<img class="realicon" src="'+esc(icon)+'" alt="">' : '<span class="repoicon" aria-hidden="true">▦</span>';
   return '<button type="button" class="app deployment-card'+(selected ? ' selected' : '')+'" data-source="'+source+'" value="'+esc(id)+'" aria-haspopup="dialog" aria-label="'+
     esc((selected ? 'Edit ' : 'Configure ')+name)+'"><span class="catalog-icon" aria-hidden="true">'+image+'</span><span><strong>'+esc(name)+'</strong><small>'+
     esc(subtitle)+'</small></span><span class="app-mark" aria-hidden="true">'+(selected?'✓':'+')+'</span></button>';
 }
 function builtins() {
   $('builtin-section').hidden = !base.enableBuiltIns;
   if (base.enableBuiltIns) builtinCards();
 }
 function builtinCards() {
   const query = $('builtin-search').value.toLowerCase().trim(), filter = $('builtin-filter').value;
   const matched = APPS.filter(a => {
     const inCategory = !filter || (filter === 'selected' ? s.selected.includes(a.Id) : categories[a.Id] === filter);
     return inCategory && [a.Id,a.DisplayName,a.Vendor].join(' ').toLowerCase().includes(query);
   });
   $('builtin-cards').innerHTML = visibleApps('builtin',matched).map(a=>card(a.Id,a.DisplayName,descriptions[a.Id]||a.Vendor,a.IconData,s.selected.includes(a.Id),'builtin')).join('') || '<p class="small muted">No matching built-in apps.</p>';
 }
 function repository() {
   const query = $('repo-search').value.toLowerCase().trim();
   const selectable = catalogRows.filter(AppCatalog.selectable);
   const matched = selectable.filter(p=>(p.id+' '+p.name).toLowerCase().includes(query));
   $('repo-search').hidden = !selectable.length && !query;
   $('repo-cards').innerHTML = visibleApps('repo',matched).map(p=>card(p.id,p.name,p.status==='index' ? p.id+' · Catalog ID (type unverified)' : [p.id,p.version,p.architecture].join(' · '),'',s.repoSelected.includes(p.id),'repo')).join('');
   $('repo-status').textContent = status || (query && !matched.length ? 'No matching repository apps.' : selectable.length ? selectable.length+' available' : 'No selectable apps in this catalog.');
   const missing = s.repoSelected.filter(id=>!selectable.some(p=>p.id===id));
   const failed = catalogRows.filter(p=>p.blocked || ['error','incompatible'].includes(p.status));
   $('repo-unavailable').innerHTML = missing.map(id=>'<button class="btn" type="button" data-forget="'+esc(id)+'">Remove unavailable selection · '+esc(id)+'</button>').join('')+
     (failed.length ? '<details><summary>Unavailable packages ('+failed.length+')</summary><ul>'+failed.map(p=>'<li>'+esc(p.id)+' · '+esc(p.blocked?'Reserved built-in ID':p.error)+'</li>').join('')+'</ul></details>' : '');
   $('repo-unavailable').querySelectorAll('[data-forget]').forEach(b=>b.onclick=()=>{
     s.repoSelected=s.repoSelected.filter(id=>id!==b.dataset.forget); repository(); saveSelection();
   });
 }
 function validateDialog() {
   if (!activeApp) return;
   const {source,id,options} = activeApp;
   const errors = options ? options.errors() : [];
   if (source==='repo' && !catalogRows.some(p=>p.id===id && AppCatalog.selectable(p))) {
     errors.push({message:'This package is no longer available in the catalog.'});
   }
   $('app-dialog-errors').textContent=errors.map(e=>e.message).join(' ');
   $('app-save').disabled=errors.length>0;
 }
 function openApp(source,id,trigger) {
   if (dialog.open) return;
   const builtin=source==='builtin';
   const item=builtin ? APPS.find(a=>a.Id===id) : catalogRows.find(p=>p.id===id && AppCatalog.selectable(p));
   if (!item) return;
   const selected=s[fields[source]].includes(id);
   activeApp={source,id,trigger,options:null};
   $('app-dialog-title').textContent=builtin ? item.DisplayName : item.name;
   const icon=$('dialog-app-icon'); icon.hidden=!builtin;
   if (builtin) {
     icon.src=item.IconData;
     activeApp.options=editAppOptions(item,s,validateDialog);
   } else {
     const lines=[['Package ID',item.id],['Version',item.version],['Architecture',item.architecture]];
     $('appsettings').innerHTML='<p>Installation settings come from your repository package.</p><dl class="repo-details">'+
       lines.filter(([,v])=>v).map(([k,v])=>'<dt>'+k+'</dt><dd>'+esc(v)+'</dd>').join('')+'</dl>';
   }
   $('app-save').textContent=selected?'Save changes':'Add to deployment';
   $('app-remove').hidden=!selected;
   validateDialog();
   dialog.showModal();
   $('app-dialog-title').focus();
 }
 function drawSelection(source) {
   if (source==='builtin') builtinCards(); else repository();
   saveSelection();
 }
 function removeApp(source,id) {
   const key=fields[source];
   s[key]=s[key].filter(value=>value!==id);
   drawSelection(source);
 }
 function finishApp(remove) {
   const {source,id,options,trigger} = activeApp;
   const name=$('app-dialog-title').textContent;
   const key=fields[source], adding=!s[key].includes(id);
   if (remove) {
     removeApp(source,id);
     say(name+' removed.');
   } else {
     validateDialog();
     if ($('app-save').disabled) return;
     options?.apply(s);
     if (adding) s[key]=[...s[key],id];
     drawSelection(source);
     if (!adding) say(name+' saved.');
   }
   dialog.close();
   if (adding && !remove) {
     const card=Array.from($(source+'-cards').children).find(el=>el.value===id);
     requestAnimationFrame(()=>announceAddition([{key:source+':'+id,name}],card || trigger));
   }
 }
 dialog.onclose=()=>{
   if (!activeApp) return;
   const {source,id,trigger}=activeApp;
   activeApp=null;
   $('appsettings').replaceChildren();
   const replacement=Array.from($(source+'-cards').querySelectorAll('button')).find(b=>b.value===id);
   (trigger.isConnected ? trigger : replacement || $(source+'-search')).focus({preventScroll:true});
 };
 dialog.querySelector('.dialog-close').onclick=() => dialog.close();
 $('app-cancel').onclick=() => dialog.close();
 $('app-save').onclick=() => finishApp(false);
 $('app-remove').onclick=() => finishApp(true);
 async function loadCatalog(file) {
   activeRequest?.abort();
   const request=new AbortController(); activeRequest=request;
   status='Loading repository apps…'; repository();
   try {
     if (file && file.size>5000000) throw Error('Choose a catalog smaller than 5 MB.');
     const index=file ? JSON.parse(await file.text()) : null;
     const rows=await AppCatalog.load(catalog,request.signal,undefined,index);
     if (request.signal.aborted) return;
     catalogRows=rows; status='';
   } catch (error) {
     if (request.signal.aborted) return;
     status='Could not load catalog. '+error.message+' Refresh or open the catalog JSON from your computer.';
     // A previous result must not silently authorize packages from a failed refresh.
     catalogRows=[];
   } finally {
     if (!request.signal.aborted) {
        repository(); saveSelection(); validateDialog();
     }
   }
 }
 function render() {
   builtins();
   $('repo-section').hidden=!catalog;
   if (catalog) repository();
   saveSelection();
 }
 for (const [source,draw] of [['builtin',builtinCards],['repo',repository]]) {
   $(source+'-cards').onclick=event=>{
     const card=event.target.closest('button[data-source]');
     if (card) openApp(source,card.value,card);
   };
   $(source+'-more').onclick=()=>{
     expanded[source]=!expanded[source];
     draw();
     if (expanded[source]) $(source+'-cards').children[previewCount]?.focus();
   };
   $(source+'-search').oninput=()=>{expanded[source]=false;draw();};
 }
 $('builtin-filter').onchange=()=>{expanded.builtin=false;builtinCards();};
 $('refresh-repo').onclick=()=>loadCatalog();
 $('import-repo').onclick=()=>$('catalog-file').click();
 $('catalog-file').onchange=e=>{const f=e.target.files[0];e.target.value='';if(f)loadCatalog(f);};
 $('saveSettings').onclick=()=>{
   const value=JSON.stringify({builder:'apps',settings:{...s,repoItems:catalogRows.filter(p=>s.repoSelected.includes(p.id))}},null,2);
   const url=URL.createObjectURL(new Blob([value],{type:'application/json'})), a=document.createElement('a');
   a.href=url;a.download='OSDStage-builder-settings.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1200);
 };
 $('loadSettings').onclick=()=>$('settingsFile').click();
 $('settingsFile').onchange=async e=>{
   const f=e.target.files[0], version=++importVersion; e.target.value=''; if(!f)return;
   try {
     if(f.size>5000000)throw Error('Choose a file smaller than 5 MB.');
     const data=JSON.parse(await f.text());
     if(closed || version!==importVersion)return;
     if(data.builder!=='apps')throw Error('Choose an Apps Builder selections file.');
     const imported=C.importSettings(data.settings,APPS);
     if(C.configCount(imported))throw Error('Choose a selections file containing only app settings.');
     const incoming=S.appState(imported);
     if(incoming.repoSelected.length && (!catalog || incoming.catalog.trim()!==catalog)) throw Error('Set the matching repository URL in Deployment settings first.');
     if(incoming.selected.length && !base.enableBuiltIns) throw Error('Enable built-in apps in Deployment settings first.');
     s=D.appsForBase(incoming,base); render(); say('App selections restored.');
   } catch (error) {if(!closed)say(error.message);}
 };
 render();
 if(catalog)loadCatalog();
 return {open:openApp, remove:removeApp, close(){closed=true;activeRequest?.abort();if (dialog.open) dialog.close();}};
}
