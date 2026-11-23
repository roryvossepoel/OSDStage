// Edits belong to the dialog until the user applies them.
function editAppOptions(app, saved, validate) {
 const C=BuilderCore, $=byId, esc=h;
 const s=clone(saved);
function get(path){return path.split('.').reduce((o,k)=>o[k],s)}function set(path,value){let p=path.split('.'),k=p.pop(),o=p.reduce((o,k)=>o[k],s);o[k]=value}
function field(label,path,type='text',hint='',placeholder=''){const id='f-'+path.replaceAll('.','-');return `<label class="field" for="${id}">${label}<input id="${id}" data-field="${path}" type="${type}" value="${esc(get(path))}" placeholder="${esc(placeholder)}" ${type==='number'?'min="1" max="120"':''}>${hint?`<small>${hint}</small>`:''}</label>`}
function area(label,path,hint=''){const id='f-'+path.replaceAll('.','-');return `<label class="field" for="${id}">${label}<textarea id="${id}" data-field="${path}" rows="2">${esc(get(path))}</textarea>${hint?`<small>${hint}</small>`:''}</label>`}
function select(label,path,options){return `<label class="field">${label}<select data-field="${path}" aria-label="${label}">${options.map(x=>{const [v,t]=Array.isArray(x)?x:[x,x];return `<option value="${esc(v)}" ${String(get(path))===String(v)?'selected':''}>${esc(t)}</option>`}).join('')}</select></label>`}
function toggle(path,title,text='',disabled=false){return `<label class="option ${disabled?'disabled':''}"><input type="checkbox" data-field="${path}" ${get(path)?'checked':''} ${disabled?'disabled':''}><div><strong>${title}</strong>${text?`<p>${text}</p>`:''}</div></label>`}

 function bind(root) {
   for (const el of root.querySelectorAll('[data-field]')) {
     const change = el.tagName === 'SELECT' || el.type === 'checkbox';
     el[change ? 'onchange' : 'oninput'] = () => {
       const key = el.dataset.field;
       set(key, el.type === 'checkbox' ? el.checked : el.type === 'number' ? Number(el.value) : el.value);
       if (['officeMode','officeVisio','officeProject'].includes(key)) {
         renderAppSettings();
         root.querySelector('[data-field="'+key+'"]')?.focus();
       }
       validate();
     };
   }
 }
function renderAppSettings(){let h='';
 if(app.Id==='Microsoft365Apps')h+=`<section class="app-preferences">
 ${select('Language configuration','officeMode',[['manual','Choose Office languages'],['matchos','Follow target Windows language'],['xml','Use my own Office XML']])}
 ${s.officeMode==='xml'?field('Office configuration XML','officeXmlPath','text','Supply this file yourself; its settings replace the Office options below.','Files\\Office.xml'):`<div class="fields">${select('Update channel','officeChannel',['MonthlyEnterprise','Current','SemiAnnual','CurrentPreview','SemiAnnualPreview','BetaChannel'])}${select('Product','officeProduct',[['O365ProPlusRetail','Microsoft 365 Apps for enterprise'],['O365BusinessRetail','Microsoft 365 Apps for business']])}${select('Office architecture','officeArchitecture',['x64','x86'])}</div>
 ${s.officeMode==='matchos'?`<div class="notice">Office follows Windows on the <strong>target device</strong>. Office content is downloaded during SetupComplete, so internet is required there. USB preparation does not download Office in this mode.</div>${select('Fallback language','officeFallback',C.LANGUAGES)}`:`<div class="language-box"><div class="rowhead"><strong>Office languages</strong><span class="pill">${s.officeLanguages.length} selected</span></div><input type="search" id="languageSearch" aria-label="Search Office languages" placeholder="Search all ${C.LANGUAGES.length} languages…"><div class="language-list" id="languageList">${languageChoices('')}</div><div class="fields">${select('Primary language','officePrimary',s.officeLanguages.map(id=>[id,C.LANGUAGES.find(x=>x[0]===id)?.[1]||id]))}</div><p class="small muted">Primary language is written first in the configuration. <a href="https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/overview-deploying-languages-microsoft-365-apps#languages-culture-codes-and-companion-proofing-languages" target="_blank" rel="noopener">Microsoft language list</a></p></div>`}
 <div class="inlineoptions">${[['officeShared','Shared computer licensing'],['officeDevice','Device-based licensing'],['officeUpdates','Office updates enabled'],['officeVisio','Include Visio'],['officeProject','Include Project']].map(([k,t])=>`<label><input type="checkbox" data-field="${k}" ${s[k]?'checked':''}>${t}</label>`).join('')}</div>
 ${s.officeVisio||s.officeProject?select('Visio / Project language','officeAddonLanguage',C.LANGUAGES.filter(x=>!['en-gb','fr-ca','es-mx'].includes(x[0]))):''}
 <details class="advanced"><summary>Exclude individual Office apps</summary><div class="chips">${['Access','Excel','Groove','Lync','OneDrive','OneNote','Outlook','OutlookForWindows','PowerPoint','Publisher','Teams','Word'].map(v=>`<label><input type="checkbox" data-exclude="${v}" ${s.officeExclude.includes(v)?'checked':''}>${esc(v)}</label>`).join('')}</div></details><p class="small muted">The generated Office XML accepts the Office licence terms.</p>`}</section>`;
 if(app.Id==='MozillaFirefoxEnterprise')h+=`<section class="app-preferences"><div class="fields">${select('Firefox channel','firefoxChannel',[['ESR','Extended Support Release'],['Rapid','Rapid release']])}${field('Firefox language','firefoxLanguage')}</div></section>`;
 if(app.Id==='DotNetRuntime')h+=`<section class="app-preferences"><p class="small muted">Select either runtime or both. Each variant uses its own module cache and package ID.</p><div class="twocol">${toggle('dotnetRuntime','.NET Runtime')}${toggle('dotnetDesktop','.NET Desktop Runtime')}</div>${select('.NET channel','dotnetChannel',['10.0','9.0','8.0'])}</section>`;
 h+=appAdvanced(app, Boolean(h));$('appsettings').innerHTML=h;bind($('appsettings'));bindLanguages();
 if($('languageSearch'))$('languageSearch').oninput=e=>{$('languageList').innerHTML=languageChoices(e.target.value);bindLanguages()};
 $('appsettings').querySelectorAll('[data-exclude]').forEach(el=>el.onchange=()=>{s.officeExclude=el.checked?[...s.officeExclude,el.dataset.exclude]:s.officeExclude.filter(x=>x!==el.dataset.exclude);validate()});
}
function appAdvanced(app, hasPreferences){const defs=C.APP_OPTIONS[app.Id]||[];if(!defs.length)return '';return `${hasPreferences ? '<details class="appdetail"><summary>Advanced settings</summary>' : '<section>'}<p class="small muted">Optional installation settings. Blank custom URLs use the module source. Target: x64 Windows.</p><div class="fields">${defs.map(d=>{const path='appOptions.'+app.Id+'.'+d.key;return d.kind==='boolean'?toggle(path,d.label):d.values?select(d.label,path,d.values.map(v=>[v,v||'Module default'])):['json','lines'].includes(d.kind)?area(d.label,path):field(d.label,path,d.kind==='number'?'number':d.kind==='url'?'url':'text')}).join('')}</div>${hasPreferences ? '</details>' : '</section>'}`}
function languageChoices(query){return C.LANGUAGES.filter(x=>x.join(' ').toLowerCase().includes(query.toLowerCase())).map(([id,name])=>`<label><input type="checkbox" data-lang="${id}" ${s.officeLanguages.includes(id)?'checked':''}><span>${esc(name)}<small>${id}</small></span></label>`).join('')||'<p class="muted">No matching languages.</p>'}
function bindLanguages(){$('appsettings').querySelectorAll('[data-lang]').forEach(el=>el.onchange=()=>{s.officeLanguages=el.checked?[...s.officeLanguages,el.dataset.lang]:s.officeLanguages.filter(x=>x!==el.dataset.lang);const search=$('languageSearch')?.value||'';renderAppSettings();$('languageSearch').value=search;$('languageList').innerHTML=languageChoices(search);bindLanguages();$('languageList').querySelector('[data-lang="'+el.dataset.lang+'"]')?.focus();validate()});const primary=$('appsettings').querySelector('[data-field="officePrimary"]');if(primary){primary.value=s.officeLanguages[0]||'';primary.onchange=()=>{s.officeLanguages=[primary.value,...s.officeLanguages.filter(x=>x!==primary.value)];validate()}}}


 renderAppSettings();
 return {
   errors() {
     return BuilderScopes.validateApps({...s, source:'builtin', selected:[app.Id], repoSelected:[], repoItems:[]}, APPS);
   },
   apply(target) {
     const group={Microsoft365Apps:'office', MozillaFirefoxEnterprise:'firefox', DotNetRuntime:'dotnet'}[app.Id];
     if (group) {
       for (const key of Object.keys(s)) if (key.startsWith(group)) target[key]=s[key];
     }
     target.appOptions[app.Id]=s.appOptions[app.Id];
   }
 };
}
