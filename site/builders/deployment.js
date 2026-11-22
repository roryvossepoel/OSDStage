function mountApps() {
 const C = BuilderCore, S = BuilderScopes, $ = byId, esc = h;
 const base = S.baseState(project.base || {});
 const catalog = base.source !== 'builtin' ? base.catalog.trim() : '';
 let s = D.appsForBase(project.parts.apps || {}, base);
 let catalogRows = s.repoItems.slice(), activeRequest, closed = false, importVersion = 0;
 let status = '';
const categories={Microsoft365Apps:'Productivity',MicrosoftTeams:'Productivity',AdobeAcrobatUnified:'Productivity',GoogleChromeEnterprise:'Browsers',MozillaFirefoxEnterprise:'Browsers',CiscoWebex:'Productivity',ZoomWorkplace:'Productivity',MicrosoftCompanyPortal:'Utilities',VisualStudioCode:'Utilities',CMTraceOpen:'Utilities','7Zip':'Utilities',VisualCRedist:'Runtimes',DotNetRuntime:'Runtimes'};
const descriptions={Microsoft365Apps:'Office applications',MicrosoftTeams:'Work and school',AdobeAcrobatUnified:'PDF reader & licensed Acrobat',GoogleChromeEnterprise:'Enterprise browser',MozillaFirefoxEnterprise:'Rapid or ESR channel',CiscoWebex:'Meetings & collaboration',ZoomWorkplace:'Meetings & collaboration',MicrosoftCompanyPortal:'Company Portal',VisualStudioCode:'System-wide code editor',CMTraceOpen:'Deployment log viewer','7Zip':'File compression',VisualCRedist:'Visual C++ v14 prerequisites',DotNetRuntime:'Runtime, Desktop Runtime or both'};
function get(path){return path.split('.').reduce((o,k)=>o[k],s)}function set(path,value){let p=path.split('.'),k=p.pop(),o=p.reduce((o,k)=>o[k],s);o[k]=value}
function field(label,path,type='text',hint='',placeholder=''){const id='f-'+path.replaceAll('.','-');return `<label class="field" for="${id}">${label}<input id="${id}" data-field="${path}" type="${type}" value="${esc(get(path))}" placeholder="${esc(placeholder)}" ${type==='number'?'min="1" max="300"':''}>${hint?`<small>${hint}</small>`:''}</label>`}
function area(label,path,hint=''){const id='f-'+path.replaceAll('.','-');return `<label class="field" for="${id}">${label}<textarea id="${id}" data-field="${path}" rows="2">${esc(get(path))}</textarea>${hint?`<small>${hint}</small>`:''}</label>`}
function select(label,path,options){return `<label class="field">${label}<select data-field="${path}" aria-label="${label}">${options.map(x=>{const [v,t]=Array.isArray(x)?x:[x,x];return `<option value="${esc(v)}" ${String(get(path))===String(v)?'selected':''}>${esc(t)}</option>`}).join('')}</select></label>`}
function toggle(path,title,text='',disabled=false){return `<label class="option ${disabled?'disabled':''}"><input type="checkbox" data-field="${path}" ${get(path)?'checked':''} ${disabled?'disabled':''}><div><strong>${title}</strong>${text?`<p>${text}</p>`:''}</div></label>`}

 function bind(root) {
   for (const el of root.querySelectorAll('[data-field]')) {
     const change = el.tagName === 'SELECT' || el.type === 'checkbox';
     el[change ? 'onchange' : 'oninput'] = () => {
       const key = el.dataset.field;
       set(key, el.type === 'checkbox' ? el.checked : el.type === 'number' ? Number(el.value) : el.value);
       if (['officeMode','officeVisio','officeProject'].includes(key)) renderAppSettings();
       saveSelection();
     };
   }
 }
function renderAppSettings(){const ids=APPS.filter(a=>s.selected.includes(a.Id)).map(a=>a.Id);let h='';
 if(ids.includes('Microsoft365Apps'))h+=`<details class="appdetail" open><summary><img src="${APPS.find(a=>a.Id==='Microsoft365Apps').IconData}" alt="">Microsoft 365 preferences</summary>
 ${select('Language configuration','officeMode',[['manual','Choose Office languages'],['matchos','Follow target Windows language'],['xml','Use my own Office XML']])}
 ${s.officeMode==='xml'?field('Office configuration XML','officeXmlPath','text','Supply this file yourself; its settings replace the Office options below.','Files\\Office.xml'):`<div class="fields">${select('Update channel','officeChannel',['MonthlyEnterprise','Current','SemiAnnual','CurrentPreview','SemiAnnualPreview','BetaChannel'])}${select('Product','officeProduct',[['O365ProPlusRetail','Microsoft 365 Apps for enterprise'],['O365BusinessRetail','Microsoft 365 Apps for business']])}${select('Office architecture','officeArchitecture',['x64','x86'])}</div>
 ${s.officeMode==='matchos'?`<div class="notice">Office follows Windows on the <strong>target device</strong>. Office content is downloaded during SetupComplete, so internet is required there. USB preparation does not download Office in this mode.</div>${select('Fallback language','officeFallback',C.LANGUAGES)}`:`<div class="language-box"><div class="rowhead"><strong>Office languages</strong><span class="pill">${s.officeLanguages.length} selected</span></div><input type="search" id="languageSearch" aria-label="Search Office languages" placeholder="Search all ${C.LANGUAGES.length} languages…"><div class="language-list" id="languageList">${languageChoices('')}</div><div class="fields">${select('Primary language','officePrimary',s.officeLanguages.map(id=>[id,C.LANGUAGES.find(x=>x[0]===id)?.[1]||id]))}</div><p class="small muted">Primary language is written first in the configuration. <a href="https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/overview-deploying-languages-microsoft-365-apps#languages-culture-codes-and-companion-proofing-languages" target="_blank" rel="noopener">Microsoft language list</a></p></div>`}
 <div class="inlineoptions">${[['officeShared','Shared computer licensing'],['officeDevice','Device-based licensing'],['officeUpdates','Office updates enabled'],['officeVisio','Include Visio'],['officeProject','Include Project']].map(([k,t])=>`<label><input type="checkbox" data-field="${k}" ${s[k]?'checked':''}>${t}</label>`).join('')}</div>
 ${s.officeVisio||s.officeProject?select('Visio / Project language','officeAddonLanguage',C.LANGUAGES.filter(x=>!['en-gb','fr-ca','es-mx'].includes(x[0]))):''}
 <details class="advanced"><summary>Exclude individual Office apps</summary><div class="chips">${['Access','Excel','Groove','Lync','OneDrive','OneNote','Outlook','OutlookForWindows','PowerPoint','Publisher','Teams','Word'].map(v=>`<label><input type="checkbox" data-exclude="${v}" ${s.officeExclude.includes(v)?'checked':''}>${esc(v)}</label>`).join('')}</div></details><p class="small muted">The generated Office XML accepts the Office licence terms.</p>`}</details>`;
 if(ids.includes('MozillaFirefoxEnterprise'))h+=`<details class="appdetail"><summary>Firefox preferences</summary><div class="fields">${select('Firefox channel','firefoxChannel',[['ESR','Extended Support Release'],['Rapid','Rapid release']])}${field('Firefox language','firefoxLanguage')}</div></details>`;
 if(ids.includes('DotNetRuntime'))h+=`<details class="appdetail" open><summary>.NET preferences</summary><p class="small muted">Select either runtime or both. Each variant uses its own module cache and package ID.</p><div class="twocol">${toggle('dotnetRuntime','.NET Runtime')}${toggle('dotnetDesktop','.NET Desktop Runtime')}</div>${select('.NET channel','dotnetChannel',['10.0','9.0','8.0'])}</details>`;
 h+=APPS.filter(a=>s.selected.includes(a.Id)).map(app=>appAdvanced(app)).join('');$('appsettings').innerHTML=h;bind($('appsettings'));bindLanguages();
 if($('languageSearch'))$('languageSearch').oninput=e=>{$('languageList').innerHTML=languageChoices(e.target.value);bindLanguages()};
 $('appsettings').querySelectorAll('[data-exclude]').forEach(el=>el.onchange=()=>{s.officeExclude=el.checked?[...s.officeExclude,el.dataset.exclude]:s.officeExclude.filter(x=>x!==el.dataset.exclude);saveSelection()});
}
function appAdvanced(app){const defs=C.APP_OPTIONS[app.Id]||[];if(!defs.length)return '';return `<details class="appdetail"><summary>${esc(app.DisplayName)} · advanced</summary><p class="small muted">Optional installation settings. Blank custom URLs use the module source. Target: x64 Windows.</p><div class="fields">${defs.map(d=>{const path='appOptions.'+app.Id+'.'+d.key;return d.kind==='boolean'?toggle(path,d.label):d.values?select(d.label,path,d.values.map(v=>[v,v||'Module default'])):['json','lines'].includes(d.kind)?area(d.label,path):field(d.label,path,d.kind==='number'?'number':d.kind==='url'?'url':'text')}).join('')}</div></details>`}
function languageChoices(query){return C.LANGUAGES.filter(x=>x.join(' ').toLowerCase().includes(query.toLowerCase())).map(([id,name])=>`<label><input type="checkbox" data-lang="${id}" ${s.officeLanguages.includes(id)?'checked':''}><span>${esc(name)}<small>${id}</small></span></label>`).join('')||'<p class="muted">No matching languages.</p>'}
function bindLanguages(){document.querySelectorAll('[data-lang]').forEach(el=>el.onchange=()=>{s.officeLanguages=el.checked?[...s.officeLanguages,el.dataset.lang]:s.officeLanguages.filter(x=>x!==el.dataset.lang);const search=$('languageSearch')?.value||'';renderAppSettings();$('languageSearch').value=search;$('languageList').innerHTML=languageChoices(search);bindLanguages();saveSelection()});const primary=document.querySelector('[data-field="officePrimary"]');if(primary){primary.value=s.officeLanguages[0]||'';primary.onchange=()=>{s.officeLanguages=[primary.value,...s.officeLanguages.filter(x=>x!==primary.value)];saveSelection()}}}

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
   const cache = $('cache-guidance');
   cache.replaceChildren();
   if (s.mode === 'offline' && chosen && !errors.length) {
     const note=document.createElement('p'), code=document.createElement('pre');
     note.textContent='Prepare the app cache on full Windows after importing and configuring OSDStage.';
     code.textContent=S.appCode(project.parts.apps,APPS,'prepare'); cache.append(note,code);
   }
   persist(); sidebar();
   if (current() === 'review') renderReview();
 }

 function card(id, name, subtitle, icon, selected, source) {
   const image = icon ? '<img class="realicon" src="'+esc(icon)+'" alt="">' : '<span class="repoicon" aria-hidden="true">▦</span>';
   return '<label class="app'+(selected ? ' selected' : '')+'">'+image+'<span><strong>'+esc(name)+'</strong><small>'+
     esc(subtitle)+'</small></span><input type="checkbox" data-source="'+source+'" value="'+esc(id)+'" aria-label="'+esc(name)+'"'+(selected?' checked':'')+'></label>';
 }
 function builtins() {
   $('builtin-section').hidden = !base.enableBuiltIns;
   if (!base.enableBuiltIns) return;
   builtinCards();
   renderAppSettings();
 }
 function builtinCards() {
   const query = $('builtin-search').value.toLowerCase().trim(), filter = $('builtin-filter').value;
   const matched = APPS.filter(a => {
     const inCategory = !filter || (filter === 'selected' ? s.selected.includes(a.Id) : categories[a.Id] === filter);
     return inCategory && [a.Id,a.DisplayName,a.Vendor].join(' ').toLowerCase().includes(query);
   });
   $('builtin-cards').innerHTML = matched.map(a=>card(a.Id,a.DisplayName,descriptions[a.Id]||a.Vendor,a.IconData,s.selected.includes(a.Id),'builtin')).join('') || '<p class="small muted">No matching built-in apps.</p>';
 }
 function repository() {
   const query = $('repo-search').value.toLowerCase().trim();
   const selectable = catalogRows.filter(AppCatalog.selectable);
   const matched = selectable.filter(p=>(p.id+' '+p.name).toLowerCase().includes(query));
   $('repo-search').hidden = !selectable.length && !query;
   $('repo-cards').innerHTML = matched.map(p=>card(p.id,p.name,p.status==='index' ? p.id+' · Catalog ID (type unverified)' : [p.id,p.version,p.architecture].join(' · '),'',s.repoSelected.includes(p.id),'repository')).join('');
   $('repo-status').textContent = status || (query && !matched.length ? 'No matching repository apps.' : selectable.length ? selectable.length+' available' : 'No selectable apps in this catalog.');
   const missing = s.repoSelected.filter(id=>!selectable.some(p=>p.id===id));
   const failed = catalogRows.filter(p=>p.blocked || ['error','incompatible'].includes(p.status));
   $('repo-unavailable').innerHTML = missing.map(id=>'<button class="btn" type="button" data-forget="'+esc(id)+'">Remove unavailable selection · '+esc(id)+'</button>').join('')+
     (failed.length ? '<details><summary>Unavailable packages ('+failed.length+')</summary><ul>'+failed.map(p=>'<li>'+esc(p.id)+' · '+esc(p.blocked?'Reserved built-in ID':p.error)+'</li>').join('')+'</ul></details>' : '');
   $('repo-unavailable').querySelectorAll('[data-forget]').forEach(b=>b.onclick=()=>{
     s.repoSelected=s.repoSelected.filter(id=>id!==b.dataset.forget); repository(); saveSelection();
   });
 }
 function selectApp(event) {
   const input=event.target;
   if (!input.matches('input[data-source]')) return;
   const builtIn=input.dataset.source==='builtin', key=builtIn?'selected':'repoSelected';
   s[key]=s[key].filter(id=>id!==input.value);
   if (input.checked) s[key].push(input.value);
   input.closest('label').classList.toggle('selected',input.checked);
   if (builtIn) {
     if ($('builtin-filter').value === 'selected') builtinCards();
     renderAppSettings();
   }
   saveSelection();
 }
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
        repository(); saveSelection();
     }
   }
 }
 function render() {
   builtins();
   $('repo-section').hidden=!catalog;
   $('skip-refresh-field').hidden=!catalog;
   $('app-mode').value=s.mode; $('skip-refresh').checked=s.skipRefresh;
   if (catalog) repository();
   saveSelection();
 }
 $('builtin-cards').onchange=selectApp; $('repo-cards').onchange=selectApp;
 $('builtin-search').oninput=builtinCards; $('builtin-filter').onchange=builtinCards;
 $('repo-search').oninput=repository;
 $('refresh-repo').onclick=()=>loadCatalog();
 $('import-repo').onclick=()=>$('catalog-file').click();
 $('catalog-file').onchange=e=>{const f=e.target.files[0];e.target.value='';if(f)loadCatalog(f);};
 $('app-mode').onchange=e=>{s.mode=e.target.value;saveSelection();};
 $('skip-refresh').onchange=e=>{s.skipRefresh=e.target.checked;saveSelection();};
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
     if(incoming.repoSelected.length && (!catalog || incoming.catalog.trim()!==catalog)) throw Error('Set the matching repository URL in Base settings first.');
     if(incoming.selected.length && !base.enableBuiltIns) throw Error('Enable built-in apps in Base settings first.');
     s=D.appsForBase(incoming,base); render(); say('App selections restored.');
   } catch (error) {if(!closed)say(error.message);}
 };
 render();
 if(catalog)loadCatalog();
 return ()=>{ closed=true;activeRequest?.abort(); };
}
