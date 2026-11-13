/* Website-only separation between module setup and optional app components. */
const BuilderScopes=(()=>{
 const C=typeof BuilderCore!=='undefined'?BuilderCore:require('./core.js');
 const baseKeys=['mode','moduleSource','moduleVersion','modulePath','cache','windowsPath','source','catalog','final','cleanup','preventSleep','enableBuiltIns','logPath','resultPath'];
 const appKeys=['mode','source','catalog','repoSelected','repoItems','selected','skipRefresh','appOptions','officeMode','officeFallback','officeXmlPath','officeDevice','officeUpdates','officeArchitecture','officeAddonLanguage','officeChannel','officeProduct','officeLanguages','officeShared','officeVisio','officeProject','officeExclude','firefoxChannel','firefoxLanguage','dotnetType','dotnetChannel','dotnetRuntime','dotnetDesktop'];
 function pick(input,keys){const s=C.defaults();for(const k of keys)if(Object.hasOwn(input,k))s[k]=input[k];return s;}
 function baseState(input){return {...pick({moduleVersion:'current',logPath:'%ProgramData%\\OSDStage\\Logs\\Runtime.log',resultPath:'%ProgramData%\\OSDStage\\Results\\Latest.json',...input},baseKeys),baseOnly:true};}
 function appState(input){return pick(input,appKeys);}
 function validateBase(input){const s=baseState(input),errors=C.validate({...s,source:'builtin'},[]);if(typeof s.enableBuiltIns!=='boolean')errors.push({step:0,message:'Choose whether built-in apps are enabled.'});if(!s.enableBuiltIns&&s.source==='builtin')errors.push({step:0,message:'Keep at least one app source enabled: built-in apps or your own repository.'});if(!['builtin','both','repository'].includes(s.source))errors.push({step:0,message:'Choose a supported repository setting.'});if(s.source!=='builtin')try{C.url(s.catalog)}catch{errors.push({step:0,message:'Enter the HTTPS catalog URL used by your repository components.'})}return errors;}
 function validateApps(input,apps){const s=appState(input);return C.validate(s.mode==='offline'?{...s,moduleSource:'local',modulePath:'Files\\OSDStage\\OSDStage.psd1'}:s,apps);}
 function checked(errors){if(errors.length)throw Error(errors.map(e=>e.message).join('\n'));}
 function baseCode(input,phase='stage'){const s=baseState(input);checked(validateBase(s));return C.renderScript(s,[],phase);}
 function appCode(input,apps,phase='stage'){
  const s=appState(input);checked(validateApps(s,apps));const prep=phase==='prepare',a=[];
  if(!prep&&C.repos(s).length)a.push(C.line({name:'Test-OSDStageRepositoryAvailability',params:{Name:C.repos(s).map(p=>p.id),SkipCacheRefresh:s.skipRefresh||s.mode==='offline',ThrowOnFailure:true}}));
  if(C.selected(s,apps).some(a=>a.Id==='Microsoft365Apps')&&s.officeMode!=='xml'&&(!prep||s.officeMode!=='matchos'))a.push("$officeXmlPath = Join-Path $env:TEMP ('OSDStage-Office-' + [guid]::NewGuid().ToString('N') + '.xml')",`[IO.File]::WriteAllText($officeXmlPath, ${C.ps(C.officeXml(s))}, [Text.UTF8Encoding]::new($false))`);
  if(prep&&C.selected(s,apps).some(a=>a.Id==='Microsoft365Apps')&&s.officeMode==='matchos')a.push('# Office MatchOS downloads on the target; it cannot be prepared using this PC\'s language.');
  a.push(...C.commands(s,apps,phase).map(c=>C.line(c)));
  return a.join('\r\n')+'\r\n';
 }
 function appFiles(input,apps){return C.requiredFiles(appState(input),apps);}
 function appPackage(input,apps){return {'Apps-Stage.ps1':appCode(input,apps,'stage'),'Apps-Prepare.ps1':appCode(input,apps,'prepare'),'README.txt':'These are components, not standalone scripts.\r\nPaste Apps-Stage.ps1 into your base staging script before Test-OSDStageDeployment.\r\nFor cache preparation, paste Apps-Prepare.ps1 after importing and configuring OSDStage in your own preparation script. Run preparation on full Windows.\r\nConfigure the same repository catalog and cache label in your base.\r\nFiles you supply yourself (not included):\r\n'+appFiles(input,apps).map(f=>f.path+' — '+f.purpose).join('\r\n')};}
 return {baseState,appState,validateBase,validateApps,baseCode,appCode,appFiles,appPackage};
})();if(typeof module!=='undefined'&&module.exports)module.exports=BuilderScopes;
