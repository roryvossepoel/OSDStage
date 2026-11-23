function mountBase(){
'use strict';
const C=BuilderCore,S=BuilderScopes,$=id=>document.getElementById(id),esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const initial=S.baseState({});
let s=S.baseState(project.base || {}),advancedOpen=false;
const advancedKeys=['cache','cleanup','preventSleep','logPath','resultPath'];
function helpLink(url,label){return `<a href="${url}" target="_blank" rel="noopener">${label} →</a>`;}
function fieldShell(label,key,control,hint='',badge=false){return `<div class="base-field"><div class="field-heading"><label for="base-${key}">${label}</label>${badge?`<span class="default-tag" data-default-state="${key}">${s[key]===initial[key]?'Default':'Custom'}</span>`:''}${hint?`<button type="button" class="field-help-toggle" aria-label="Help: ${label}" aria-expanded="false" aria-controls="help-${key}">Help</button>`:''}</div>${control}${hint?`<div class="field-explanation" id="help-${key}" hidden>${hint}</div>`:''}</div>`;}
function field(label,key,hint='',placeholder='',badge=false){return fieldShell(label,key,`<input id="base-${key}" type="text" data-key="${key}" value="${esc(s[key])}" placeholder="${esc(placeholder)}">`,hint,badge);}
function select(label,key,options,hint=''){return fieldShell(label,key,`<select id="base-${key}" data-key="${key}">${options.map(([v,l])=>`<option value="${v}" ${String(s[key])===v?'selected':''}>${l}</option>`).join('')}</select>`,hint);}
function versionField(){return fieldShell('Module version','version-choice',`<select id="base-version-choice"><option value="current" ${s.moduleVersion==='current'?'selected':''}>Current — latest stable (default)</option><option value="specific" ${s.moduleVersion!=='current'?'selected':''}>Specific version</option></select>`,'Current installs the latest stable Gallery release when the script runs.')+(s.moduleVersion==='current'?'':field('Exact module version','moduleVersion','Use a published version.','1.0.0'));}
function render(){
 const openHelp=new Set([...$('base-form').querySelectorAll('.field-help-toggle[aria-expanded="true"]')].map(el=>el.getAttribute('aria-controls')));
 $('base-form').innerHTML=select('Module source','moduleSource',[['gallery','PowerShell Gallery'],['local','Local module']])+(s.moduleSource==='gallery'?versionField():field('Module manifest','modulePath','Use the OSDStage.psd1 path on your prepared USB drive.','Files\\OSDStage\\OSDStage.psd1'))+
 select('Built-in apps','enableBuiltIns',[['true','Enabled (default)'],['false','Disabled']],'Show the built-in collection in the deployment builder.')+
 select('Own repository','source',[['builtin','Disabled (builder default)'],['both','Enabled']],'Add packages from your own catalog. The module default is enabled; this builder starts with it disabled until you provide a catalog. '+helpLink('../guides.html#repository','Repository setup guide'))+
 (s.source!=='builtin'?field('Catalog URL','catalog','Configure once here. Repository components use this catalog.','https://example.org/catalog.json'):'')+
 select('Final action','final',[['None','None — leave running (default)'],['Reboot','Reboot'],['Shutdown','Shutdown']],'Runs after successful completion and finalization. Required restarts can still be needed to activate Windows or firmware updates.')+
 `<details id="base-advanced" class="base-advanced" ${advancedOpen?'open':''}><summary><span>Advanced settings</span><span id="advanced-status" class="default-tag"></span></summary><div class="advanced-fields">`+

 field('USB cache volume label','cache','Used only when a matching USB drive is connected. Default: <code>OSDCloud</code>. '+helpLink('../guides.html#cache','How caching works'),'',true)+
 select('Staged files after success','cleanup',[['OnSuccess','Clean up (default)'],['Never','Keep for inspection']])+
 field('Log file path','logPath','Default: <code>%ProgramData%\\OSDStage\\Logs\\Runtime.log</code>. Path on the deployed Windows installation. Leave empty to keep the module setting. '+helpLink('https://github.com/roryvossepoel/OSDStage/blob/main/docs/runtime.md#logging','Log locations and troubleshooting'),'',true)+
 field('Result file path','resultPath','Default: <code>%ProgramData%\\OSDStage\\Results\\Latest.json</code>. JSON result on the deployed Windows installation. Leave empty to keep the module setting. The HTML report (<code>DeliveryReport.html</code>) is saved in the same folder. '+helpLink('../report.html#open-report','Report location')+' · '+helpLink('../examples/DeliveryReport.html','View example HTML report'),'',true)+
 `<label class="inlinecheck"><input type="checkbox" data-key="preventSleep" ${s.preventSleep?'checked':''}>Keep the device awake <span class="default-tag">Default: on</span></label>`+
 '</div></details>';
 $('base-advanced').addEventListener('toggle',e=>{advancedOpen=e.target.open;});
 $('base-form').querySelectorAll('[data-key]').forEach(el=>{el[el.tagName==='SELECT'||el.type==='checkbox'?'onchange':'oninput']=()=>{s[el.dataset.key]=el.type==='checkbox'?el.checked:el.dataset.key==='enableBuiltIns'?el.value==='true':el.value;if(['source','moduleSource'].includes(el.dataset.key))render();else{$('base-form').querySelectorAll('[data-default-state]').forEach(tag=>{const key=tag.dataset.defaultState;tag.textContent=s[key]===initial[key]?'Default':s[key]===''?'Module setting':'Custom';});output();}};});
 $('base-form').querySelectorAll('.field-help-toggle').forEach(button=>{const detail=$(button.getAttribute('aria-controls'));if(openHelp.has(detail.id)){detail.hidden=false;button.setAttribute('aria-expanded','true');}button.onclick=()=>{detail.hidden=!detail.hidden;button.setAttribute('aria-expanded',String(!detail.hidden));};});
 $('base-version-choice')?.addEventListener('change',e=>{s.moduleVersion=e.target.value==='current'?'current':'1.0.0';render();});
 output();
}

function output(){
 const changed=advancedKeys.filter(k=>s[k]!==initial[k]).length;
 $('advanced-status').textContent=changed?changed+' changed':'Defaults';
 const errors=S.validateBase(s);
 $('base-errors').innerHTML=errors.map(e=>'<p class="validation">'+esc(e.message)+'</p>').join('');
 $('commit').disabled=!!errors.length;$('commit').textContent='Save base settings';
 $('commit').onclick=()=>{if(!S.validateBase(s).length)commit('base',s)};
}
render();

}
