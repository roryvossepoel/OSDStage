/* Pure component generation. Components cannot change the base deployment. */
const BuilderComponents=(()=>{
 const C=typeof BuilderCore!=='undefined'?BuilderCore:require('./core.js');
 const definitions={
  wifi:{title:'Wi-Fi',description:'Add a network profile from your own XML file or network settings.',keys:['wifi','wifiMode','wifiPath','wifiSSID','wifiSecurity','wifiConnection','wifiHidden','wifiProfileName']},
  registry:{title:'Registry',description:'Create machine registry keys and typed values. HKEY_LOCAL_MACHINE is fixed.',keys:['registry']},
  certificates:{title:'Certificates',description:'Import your public root or intermediate CA certificates into the computer store.',keys:['certificates']}
 };
 function state(type,input){if(!definitions[type])throw Error('Unknown configuration builder.');const s=C.defaults();for(const k of definitions[type].keys)if(Object.hasOwn(input,k))s[k]=input[k];if(type==='wifi')s.wifi=true;return s;}
 function validate(type,input){const s=state(type,input);return C.validate(s,[]).map(x=>x.message==='Select at least one app, update or setting.'?{step:3,message:'Add at least one '+(type==='registry'?'registry entry':'certificate')+'.'}:x);}
 function generate(type,input){const s=state(type,input),errors=validate(type,input);if(errors.length)throw Error(errors.map(x=>x.message).join('\n'));const q=C.commands(s,[],'stage'),files=C.requiredFiles(s,[]);
 const a=[`# --- OSDStage ${definitions[type].title} component ---`,'# Paste at: # === ADD YOUR CONFIGURATION COMPONENTS HERE ===','# The base script imports OSDStage and defines $destination.',"if (-not (Get-Variable -Name destination -ErrorAction SilentlyContinue)) {", "    throw 'Paste this component into the Deployment Builder base script, after $destination is defined.'",'}','# Verify module support before this component changes staging.'];
 for(const cmd of q){a.push(`$componentCommand = Get-Command -Name ${C.ps(cmd.name)} -Module OSDStage -ErrorAction Stop`);for(const param of Object.keys(cmd.params).concat('WindowsPath'))a.push(`if (-not $componentCommand.Parameters.ContainsKey(${C.ps(param)})) { throw ${C.ps('This module does not support '+cmd.name+' -'+param+'. Use a compatible module build.')} }`);}
 if(files.length){a.push('function Resolve-OSDStageComponentFile([string]$Path) {','    if ([IO.Path]::IsPathRooted($Path)) { return $Path }',"    if (-not $PSScriptRoot) { throw 'Save the combined script as a .ps1 file when using relative Files paths.' }",'    return (Join-Path $PSScriptRoot $Path)','}','# Supply these files yourself, next to your saved base script.');for(const f of files)a.push(`$componentFile = Resolve-OSDStageComponentFile ${C.ps(f.path)}`,`if (-not (Test-Path -LiteralPath $componentFile -PathType Leaf)) { throw "Required file missing: $componentFile" }`);}
 if(type==='wifi'&&s.wifiMode==='settings'&&s.wifiSecurity!=='Open')a.push("$wifiPassword = Read-Host 'Wi-Fi password' -AsSecureString");
 a.push(...q.map(c=>C.line(c).replaceAll('Resolve-BuilderFile','Resolve-OSDStageComponentFile')),`# --- End ${definitions[type].title} component ---`);return a.join('\r\n')+'\r\n';
 }
 return {definitions,state,validate,generate};
})();if(typeof module!=='undefined'&&module.exports)module.exports=BuilderComponents;
