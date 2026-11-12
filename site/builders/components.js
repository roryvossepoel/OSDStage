/* Website-only component definitions and generation. No deployment runtime code. */
const BuilderComponents=(()=>{
 const C=typeof BuilderCore!=='undefined'?BuilderCore:require('./core.js');
 const definitions={
  wifi:{title:'Wi-Fi',icon:'wifi',catalogId:'WiFiProfiles',description:'Use your XML profile or enter network settings.',keys:['wifi','wifiMode','wifiPath','wifiSSID','wifiSecurity','wifiConnection','wifiHidden','wifiProfileName']},
  registry:{title:'Registry',icon:'registry',catalogId:'RegistrySettings',description:'Machine keys and typed values, always under HKLM.',keys:['registry']},
  certificates:{title:'Certificates',icon:'certificates',catalogId:'Certificates',description:'Public CA certificates from files or your repository.',keys:['certificates','certificateSource','repositoryIds','repositorySkipRefresh']},
  variables:{title:'Environment variables',icon:'variables',catalogId:'EnvironmentVariables',description:'Set machine variables or append directories to PATH.',keys:['variables','appendPath']},
  filesystem:{title:'Files & folders',icon:'filesystem',catalogId:'FileSystem',description:'Copy or write files. Create or remove folders.',keys:['files','directories']},
  services:{title:'Services',icon:'services',catalogId:'Services',description:'Choose service startup types and running states.',keys:['services']},
  desktop:{title:'Start & taskbar',icon:'desktop',catalogId:'DesktopSettings',description:'Set your Start menu and taskbar pins.',keys:['startEnabled','startMode','startJson','startPins','taskbarEnabled','taskbarPins']},
  associations:{title:'Default associations',icon:'associations',catalogId:'DefaultAssociations',description:'Associate file types and protocols with your apps.',keys:['associations','associationXml']},
  features:{title:'Windows features',icon:'windowsfeatures',catalogId:'WindowsFeatures',description:'Enable or disable optional Windows features.',keys:['featuresEnable','featuresDisable']},
  capabilities:{title:'Windows capabilities',icon:'capabilities',catalogId:'WindowsCapabilities',description:'Add or remove Features on Demand by capability name.',keys:['capabilitiesAdd','capabilitiesRemove']},
  inbox:{title:'Inbox app cleanup',icon:'inboxcleanup',catalogId:'WindowsInboxCleanup',description:'Remove selected inbox apps or inspect the cleanup plan.',keys:['inboxEnabled','inboxMode','inboxRemove','inboxDiagnose']},
  updates:{title:'Windows Update',icon:'windowsupdate',catalogId:'WindowsUpdate',description:'Install updates, include drivers or run a scan only.',keys:['updates','drivers','driverClasses','scanOnly','updateTimeout']},
  fonts:{title:'Fonts',icon:'fonts',repositoryType:'Font',description:'Stage font packages from your own catalog.',keys:['repositoryIds','repositorySkipRefresh']},
  drivers:{title:'Driver packages',icon:'drivers',repositoryType:'Driver',description:'Stage driver packages from your own catalog.',keys:['repositoryIds','repositorySkipRefresh']},
  scripts:{title:'Scripts',icon:'script',repositoryType:'Script',description:'Stage script packages from your own catalog.',keys:['repositoryIds','repositorySkipRefresh']}
 };
 function state(type,input){
  if(!Object.hasOwn(definitions,type))throw Error('Unknown configuration builder.');
  const s={...C.defaults(),certificateSource:'files',repositoryIds:'',repositorySkipRefresh:false};
  for(const k of definitions[type].keys)if(Object.hasOwn(input,k))s[k]=input[k];
  if(type==='wifi')s.wifi=true;if(type==='updates')s.updates=true;if(type==='inbox')s.inboxEnabled=true;
  if(isRepository(type,s)){s.baseOnly=true;s.certificates=[];}
  return s;
 }
 function isRepository(type,s){return !!definitions[type]?.repositoryType||(type==='certificates'&&s.certificateSource==='repository');}
 function validate(type,input){
  const s=state(type,input),e=C.validate(s,[]).map(x=>x.message==='Select at least one app, update or setting.'?{step:3,message:'Add at least one configuration item.'}:x);
  const add=message=>e.push({step:3,message});
  if(type==='certificates'&&!['files','repository'].includes(s.certificateSource))add('Choose certificate files or repository packages.');
  if(isRepository(type,s)){
   const ids=C.list(s.repositoryIds);
   if(!ids.length||ids.some(id=>!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id)))add('Enter package IDs from your catalog, one per line (letters, numbers, dots, underscores and hyphens).');
   if(new Set(ids.map(id=>id.toLowerCase())).size!==ids.length)add('Each repository package ID must be unique.');
  }
  if(s.variables.some(r=>!['Set','Remove'].includes(r.action)))add('Choose Set or Remove for each variable.');
  if(s.startEnabled&&!['pins','json'].includes(s.startMode))add('Choose a Start JSON file or individual pins.');
  if(s.startEnabled&&s.startMode==='json'&&!s.startJson.toLowerCase().endsWith('.json'))add('Supply a Start layout .json file.');
  if(s.associationXml&&!s.associationXml.toLowerCase().endsWith('.xml'))add('Supply a default-associations .xml file.');
  if(s.inboxEnabled&&!['preset','custom'].includes(s.inboxMode))add('Choose the cleanup preset or a custom list.');
  return e;
 }
 function commands(type,input){
  const s=state(type,input);
  if(!isRepository(type,s))return C.commands(s,[],'stage');
  const ids=C.list(s.repositoryIds),names={fonts:'Add-OSDStageFont',drivers:'Add-OSDStageDriver',certificates:'Add-OSDStageCertificate'};
  return [{name:'Test-OSDStageRepositoryAvailability',params:{Name:ids,ThrowOnFailure:true}},
   ...(type==='scripts'?[{name:'Add-OSDStage',params:{Name:ids,SkipCacheRefresh:s.repositorySkipRefresh}}]:ids.map(Id=>({name:names[type],params:{Id,SkipCacheRefresh:s.repositorySkipRefresh}})))];
 }
 function generate(type,input){
  const s=state(type,input),errors=validate(type,input);if(errors.length)throw Error(errors.map(x=>x.message).join('\n'));const a=[];
  if(type==='wifi'&&s.wifiMode==='settings'&&s.wifiSecurity!=='Open')a.push("$wifiPassword = Read-Host 'Wi-Fi password' -AsSecureString");
  a.push(...commands(type,input).map(c=>C.line(c)));return a.join('\r\n')+'\r\n';
 }
 return {definitions,state,validate,generate,commands,isRepository};
})();if(typeof module!=='undefined'&&module.exports)module.exports=BuilderComponents;
