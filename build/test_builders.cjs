'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const C=require('../site/builders/core.js'),B=require('../site/builders/components.js'),Z=require('../site/builders/zip.js');
const ctx={};vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../site/builders/apps.js'),'utf8')+';this.apps=APPS;',ctx);const apps=JSON.parse(JSON.stringify(ctx.apps));let tests=0;
function test(name,fn){fn();console.log('PASS '+name);tests++;}
const base=()=>({...C.defaults(),baseOnly:true});
test('base has no unsolicited apps and generates an explicit component insertion point',()=>{const s=base();assert.deepEqual(s.selected,[]);assert.equal(s.updates,false);const code=C.generate(s,apps,'stage');assert.ok(code.indexOf('Import-Module')<code.indexOf('# === ADD YOUR CONFIGURATION COMPONENTS HERE ==='));assert.doesNotMatch(code,/@destination|\$destination|Out-Host|Get-Command|\$requirements|function Resolve-/);assert.ok(code.indexOf('# === ADD YOUR CONFIGURATION COMPONENTS HERE ===')<code.indexOf('\r\nTest-OSDStageDeployment '));});
test('component state never carries apps, final action or other components',()=>{const input={...base(),selected:['7Zip'],final:'Shutdown',wifi:true,wifiPath:'Files\\WiFi.xml',registry:[{path:'HKLM:\\SOFTWARE\\X',name:'A',type:'String',view:'Registry64',value:'1'}]};const s=B.state('wifi',input);assert.deepEqual(s.selected,[]);assert.equal(s.final,'None');assert.deepEqual(s.registry,[]);const code=B.generate('wifi',input);assert.ok(!code.includes('Install-Module'));assert.ok(!code.includes('FinalAction'));assert.ok(!code.includes('Add-OSDStage7Zip'));});
test('file components use one cmdlet with a script-relative or absolute path',()=>{const code=B.generate('wifi',{wifiMode:'xml',wifiPath:'Files\\WiFi.xml'});assert.equal(code,"Add-OSDStageWiFiProfile -Path (Join-Path $PSScriptRoot 'Files\\WiFi.xml')\r\n");assert.equal(B.generate('certificates',{certificates:[{path:'E:\\root.cer',store:'Root'}]}),"Add-OSDStageCertificate -Path 'E:\\root.cer' -Store 'Root'\r\n");});
test('registry output is only the requested cmdlet with a short switch',()=>{assert.equal(B.generate('registry',{registry:[{path:'HKEY_LOCAL_MACHINE\\SOFTWARE\\Example',name:'Setting',type:'String',value:'Text',view:'Registry64'}]}),"Add-OSDStageRegistryValue -Path 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Example' -Name 'Setting' -Type 'String' -Value 'Text' -Registry64\r\n");});
test('Boolean parameters keep explicit values while false switches are omitted',()=>{assert.equal(C.line({name:'Set-OSDStageConfiguration',params:{EnableBuiltIns:true,EnableRepository:false}}),'Set-OSDStageConfiguration -EnableBuiltIns:$true -EnableRepository:$false');assert.equal(C.line({name:'Add-OSDStageWindowsUpdate',params:{IncludeDrivers:true,ScanOnly:false}}),'Add-OSDStageWindowsUpdate -IncludeDrivers');});
test('custom Windows target is explicit on every staging and validation command',()=>{const s={...base(),selected:['7Zip'],windowsPath:'D:\\'};const code=C.generate(s,apps,'stage');assert.match(code,/Add-OSDStage7Zip[^\r\n]+-WindowsPath 'D:\\'/);assert.match(code,/Test-OSDStageDeployment -ThrowOnFailure -WindowsPath 'D:\\'/);assert.doesNotMatch(code,/@destination|Out-Host/);});
test('repository preflight is retained before staging',()=>{const s={...base(),source:'both',catalog:'https://example.com/catalog.json',repoSelected:['ExampleApp'],repoItems:[{id:'ExampleApp',name:'Example app',architecture:'x64',status:'index',blocked:false}]};const code=C.generate(s,apps,'stage');assert.ok(code.indexOf('Test-OSDStageRepositoryAvailability')<code.indexOf('\r\nAdd-OSDStage -Name'));assert.match(code,/Test-OSDStageRepositoryAvailability -Name @\('ExampleApp'\) -ThrowOnFailure/);});
test('Wi-Fi password stays local and is not needed for an open network',()=>{let s={wifiMode:'settings',wifiSSID:"Rory's network",wifiSecurity:'WPA2Personal'};assert.match(B.generate('wifi',s),/Read-Host 'Wi-Fi password' -AsSecureString/);assert.match(B.generate('wifi',s),/-SSID 'Rory''s network'/);s.wifiSecurity='Open';assert.ok(!B.generate('wifi',s).includes('Read-Host'));});
test('HKCU and data injection are rejected or quoted',()=>{const s={registry:[{path:'HKCU:\\Software\\X',name:'X',type:'String',view:'Registry64',value:'1'}]};assert.throws(()=>B.generate('registry',s));s.registry[0].path='HKEY_LOCAL_MACHINE\\SOFTWARE\\X';s.registry[0].value="'; Stop-Computer; '";assert.match(B.generate('registry',s),/-Value '''; Stop-Computer; '''/);});
test('empty components cannot be downloaded',()=>{assert.throws(()=>B.generate('registry',{}));assert.throws(()=>B.generate('certificates',{}));assert.throws(()=>B.generate('wifi',{}));});
test('public certificates use only computer CA or Root stores',()=>{const s={certificates:[{path:'Files\\root.cer',store:'Root'}]};assert.match(B.generate('certificates',s),/-Store 'Root'/);s.certificates[0].store='CurrentUser';assert.throws(()=>B.generate('certificates',s));});
test('both .NET runtime variants remain distinct',()=>{const s={...base(),selected:['DotNetRuntime'],dotnetRuntime:true,dotnetDesktop:true};assert.deepEqual(C.commands(s,apps,'stage').map(c=>c.params.RuntimeType),['Runtime','Desktop']);});
test('MatchOS Office never downloads using the preparation host language',()=>{const s={...base(),selected:['Microsoft365Apps'],officeMode:'matchos'};assert.match(C.generate(s,apps,'stage'),/Language ID="MatchOS"/);assert.ok(!C.generate(s,apps,'prepare').includes('Sync-OSDStageMicrosoft365Apps'));});
test('unknown imported selections remain visible and block generation',()=>{const s={...base(),selected:['FutureApp']};const restored=C.importSettings(JSON.parse(JSON.stringify(s)),apps);assert.ok(restored.selected.includes('FutureApp'));assert.throws(()=>C.generate(restored,apps,'stage'));});
test('deployment export retains the two-script layout',()=>{const files=C.packageFiles(base(),apps);assert.ok(files['Stage-OSDStage.ps1'].includes('ADD YOUR CONFIGURATION COMPONENTS HERE'));assert.ok(files['Prepare-OSDStage.ps1']);assert.ok(files['Files/README.txt']);assert.ok(Z.create(files).length>100);});
test('component command and parameter contracts exist in module',()=>{const examples=[['wifi',{wifiMode:'settings',wifiSSID:'Example'}],['registry',{registry:[{path:'HKLM:\\SOFTWARE\\X',name:'A',type:'DWord',value:'1',view:'Registry64'}]}],['certificates',{certificates:[{path:'Files\\a.cer',store:'CA'}]}]];for(const [type,input]of examples)for(const c of C.commands(B.state(type,input),[],'stage')){const src=fs.readFileSync(path.join(__dirname,'../Public',c.name+'.ps1'),'utf8');for(const k of Object.keys(c.params))assert.ok(src.includes('$'+k),c.name+' -'+k);}});

const componentExamples={
 wifi:{wifiMode:'settings',wifiSSID:"Rory's Wi-Fi"},
 registry:{registry:[{path:'HKLM:\\SOFTWARE\\Example',name:'Value',type:'QWord',value:'18446744073709551615',view:'Registry64'}]},
 certificates:{certificates:[{path:'Files\\root.cer',store:'Root'}]},
 variables:{variables:[{name:'Example',value:'%ProgramData%\\Example',expand:true,action:'Set'},{name:'OldExample',action:'Remove'}],appendPath:'C:\\Tools'},
 filesystem:{files:[{action:'Copy',source:'Files\\settings.json',path:'C:\\ProgramData\\Example\\settings.json',force:true},{action:'Content',path:'C:\\Example.txt',content:"'; Stop-Computer; '",encoding:'UTF8',force:false},{action:'Remove',path:'C:\\Old.txt',force:false}],directories:[{path:'C:\\Tools',action:'Create',force:false},{path:'C:\\OldTools',action:'Remove',recurse:true,force:true}]},
 services:{services:[{name:'Spooler',startup:'Manual',state:'Stopped',timeout:30}]},
 desktop:{startEnabled:true,startPins:[{kind:'desktopAppId',value:'Microsoft.Windows.Explorer'}],taskbarEnabled:true,taskbarPins:[{kind:'desktopAppLink',value:'%ProgramData%\\Microsoft\\Windows\\Start Menu\\Programs\\Example.lnk'}]},
 associations:{associations:[{identifiers:'.pdf',progId:'AcroExch.Document.DC',appName:'Adobe Acrobat'}]},
 features:{featuresEnable:'NetFx3',featuresDisable:'SMB1Protocol'},
 capabilities:{capabilitiesAdd:'OpenSSH.Client~~~~0.0.1.0',capabilitiesRemove:'OpenSSH.Server~~~~0.0.1.0'},
 inbox:{inboxMode:'custom',inboxRemove:'Microsoft.BingWeather',inboxDiagnose:true},
 updates:{drivers:true,driverClasses:'Firmware, Extension',scanOnly:true,updateTimeout:45},
 fonts:{repositoryIds:'CorporateFonts',repositorySkipRefresh:true},
 drivers:{repositoryIds:'RealtekDrivers'},
 scripts:{repositoryIds:'ExampleScript\nSecondScript'}
};
test('every catalog configuration item has a builder with the exact catalog icon',()=>{
 const metadata=JSON.parse(fs.readFileSync(path.join(__dirname,'../metadata/builtins.json'),'utf8'));
 const config=metadata.Packages.filter(p=>!apps.some(a=>a.Id===p.Id));
 const hub=fs.readFileSync(path.join(__dirname,'../site/builders/index.html'),'utf8');
 for(const item of config){const entry=Object.entries(B.definitions).find(([,d])=>d.catalogId===item.Id);assert.ok(entry,item.Id);const [type,d]=entry;assert.ok(item.IconUrl.endsWith('/'+d.icon+'.svg'),item.Id);assert.ok(hub.includes('component.html?type='+type));assert.ok(hub.includes('../metadata/icons/'+d.icon+'.svg'));}
 for(const d of Object.values(B.definitions))assert.ok(fs.existsSync(path.join(__dirname,'../metadata/icons',d.icon+'.svg')));
 assert.equal(Object.keys(componentExamples).length,Object.keys(B.definitions).length);
});
test('all fifteen builders emit only supported cmdlets and parameters',()=>{
 for(const [type,input]of Object.entries(componentExamples)){
  assert.deepEqual(B.validate(type,input),[],type);const code=B.generate(type,input);
  assert.doesNotMatch(code,/@destination|Out-Host|Get-Command|Install-Module|Set-OSDStageConfiguration/);
  for(const c of B.commands(type,input)){const src=fs.readFileSync(path.join(__dirname,'../Public',c.name+'.ps1'),'utf8');for(const k of Object.keys(c.params))assert.ok(new RegExp('\\$'+k+'\\b','i').test(src),type+': '+c.name+' -'+k);}
 }
});
test('every component ignores unrelated deployment settings',()=>{
 for(const [type,input]of Object.entries(componentExamples))assert.equal(B.generate(type,{...input,selected:['7Zip'],final:'Shutdown',modulePath:'X:\\invalid',windowsPath:'Z:\\',baseOnly:true}),B.generate(type,input),type);
 assert.throws(()=>B.generate('constructor',{}));assert.throws(()=>B.generate('__proto__',{}));
});
test('repository components preflight all IDs before staging and retain package-specific commands',()=>{
 for(const [type,command]of [['fonts','Add-OSDStageFont'],['drivers','Add-OSDStageDriver'],['scripts','Add-OSDStage'],['certificates','Add-OSDStageCertificate']]){
  const input={repositoryIds:'One\nTwo',certificateSource:'repository'},code=B.generate(type,input);
  assert.ok(code.startsWith("Test-OSDStageRepositoryAvailability -Name @('One', 'Two') -ThrowOnFailure"));assert.ok(code.indexOf('\r\n'+command+' ')>0);
  assert.throws(()=>B.generate(type,{...input,repositoryIds:''}));assert.throws(()=>B.generate(type,{...input,repositoryIds:'One\none'}));assert.throws(()=>B.generate(type,{...input,repositoryIds:"'; Stop-Computer; '"}));
 }
});
test('required source files are listed while generated text and repository packages need no local source',()=>{
 for(const [type,input,expected]of [
  ['filesystem',componentExamples.filesystem,['Files\\settings.json']],
  ['desktop',{startEnabled:true,startMode:'json',startJson:'Files\\Start.json'},['Files\\Start.json']],
  ['associations',{associationXml:'Files\\Defaults.xml'},['Files\\Defaults.xml']],
  ['certificates',{certificateSource:'repository',repositoryIds:'RootCA',certificates:componentExamples.certificates.certificates},[]]
 ])assert.deepEqual(C.requiredFiles(B.state(type,input),[]).map(f=>f.path),expected);
});
test('desktop areas are explicit and empty pin arrays deliberately clear only enabled areas',()=>{
 assert.throws(()=>B.generate('desktop',{}));assert.equal(B.generate('desktop',{startEnabled:true}),"Add-OSDStageStartPins -Pins @()\r\n");
 assert.match(B.generate('desktop',{taskbarEnabled:true}),/^Add-OSDStageTaskbarPins -Pins @\(\)/);
 assert.throws(()=>B.generate('desktop',{startEnabled:true,startMode:'json',startJson:'Files\\Start.txt'}));
});
test('conflicting or invalid configuration values cannot generate executable output',()=>{
 for(const [type,input]of [
  ['features',{featuresEnable:'NetFx3',featuresDisable:'netfx3'}],
  ['services',{services:[{name:'Spooler',startup:'Disabled',state:'Running',timeout:30}]}],
  ['services',{services:[{name:'Spooler',startup:'Manual',timeout:0}]}],
  ['variables',{variables:[{name:'PATH',action:'Set',value:'C:\\Tools'}]}],
  ['variables',{variables:[{name:'Example',action:'Typo',value:'Text'}]}],
  ['associations',{associationXml:'Files\\Defaults.txt'}],
  ['inbox',{inboxMode:'custom',inboxRemove:''}],
  ['updates',{updateTimeout:1}],
  ['filesystem',{files:[{action:'Copy',source:'Files\\..\\secret.txt',path:'C:\\target.txt'}]}]
 ])assert.throws(()=>B.generate(type,input),type);
});

const S=require('../site/builders/scopes.js');
test('foundation configures module and repository without requiring or emitting workloads',()=>{
 const input={...C.defaults(),source:'both',catalog:'https://example.org/catalog.json',selected:['Microsoft365Apps'],updates:true,final:'Reboot'};
 assert.deepEqual(S.validateBase(input),[]);assert.match(S.baseCode({}),/-FinalAction 'None'/);
 const code=S.baseCode(input);assert.match(code,/Install-Module/);assert.match(code,/-CatalogUri 'https:\/\/example.org\/catalog.json'/);assert.match(code,/-FinalAction 'Reboot'/);
 assert.doesNotMatch(code,/Add-OSDStage|Sync-OSDStage|Test-OSDStageRepositoryAvailability|AllowPrerelease/);
 assert.ok(code.indexOf('ADD YOUR CONFIGURATION COMPONENTS HERE')<code.indexOf('Test-OSDStageDeployment'));
});
test('an updates-only deployment needs no app selection',()=>{
 const input={final:'Reboot'};const code=S.baseCode(input).replace('# === ADD YOUR CONFIGURATION COMPONENTS HERE ===',B.generate('updates',{}));
 assert.match(code,/Add-OSDStageWindowsUpdate/);assert.doesNotMatch(code,/Add-OSDStageMicrosoft|Office/);
 assert.ok(code.indexOf('Add-OSDStageWindowsUpdate')<code.indexOf('Test-OSDStageDeployment'));
});
test('offline base loads the supplied module and provides an independent preparation marker',()=>{
 assert.throws(()=>S.baseCode({mode:'offline'}));const input={mode:'offline',moduleSource:'local',modulePath:'Files\\OSDStage\\OSDStage.psd1'};
 assert.match(S.baseCode(input),/Import-Module \(Join-Path \$PSScriptRoot 'Files\\OSDStage\\OSDStage.psd1'\)/);
 assert.match(S.baseCode(input),/-RequireOfflineReady/);
 assert.match(S.baseCode(input,'prepare'),/ADD YOUR CACHE PREPARATION COMPONENTS HERE/);
 assert.doesNotMatch(S.baseCode(input,'prepare'),/Test-OSDStageDeployment|FinalAction|Add-OSDStage/);
});
test('apps output is a component with independent preparation and no module settings or updates',()=>{
 const input={selected:['7Zip'],final:'Shutdown',updates:true,cache:'Other',moduleVersion:'invalid'};
 assert.match(S.appCode(input,apps),/^Add-OSDStage7Zip/);
 for(const phase of ['stage','prepare'])assert.doesNotMatch(S.appCode(input,apps,phase),/Import-Module|Install-Module|Set-OSDStageConfiguration|FinalAction|WindowsUpdate|Test-OSDStageDeployment/);
 assert.match(S.appCode(input,apps,'prepare'),/^Sync-OSDStage7Zip/);assert.throws(()=>S.appCode({},apps));
});
test('Office component preserves generated XML, languages and target-language behavior',()=>{
 const input={selected:['Microsoft365Apps'],officeLanguages:['de-de','nl-nl']};
 for(const phase of ['stage','prepare']){const code=S.appCode(input,apps,phase);assert.match(code,/WriteAllText/);assert.match(code,/Language ID="de-de"/);assert.match(code,/Language ID="nl-nl"/);assert.match(code,/-ConfigurationXml \$officeXmlPath/);}
 const match={...input,officeMode:'matchos'};assert.match(S.appCode(match,apps),/Language ID="MatchOS"/);assert.doesNotMatch(S.appCode(match,apps,'prepare'),/Sync-OSDStageMicrosoft365Apps|WriteAllText/);assert.throws(()=>S.appCode({...match,mode:'offline'},apps));
 const custom={...input,officeMode:'xml',officeXmlPath:'Files\\Office.xml'};assert.deepEqual(S.appFiles(custom,apps).map(f=>f.path),['Files\\Office.xml']);
});
test('repository app components retain availability checks before staging',()=>{
 const input={source:'repository',catalog:'https://example.org/catalog.json',repoSelected:['App'],repoItems:[{id:'App',name:'App',architecture:'x64',status:'index',blocked:false}]};
 const code=S.appCode(input,apps);assert.ok(code.indexOf('Test-OSDStageRepositoryAvailability')<code.indexOf('\r\nAdd-OSDStage -Name'));
 assert.doesNotMatch(code,/CatalogUri|Set-OSDStageConfiguration/);assert.match(S.appCode(input,apps,'prepare'),/^Sync-OSDStageRepository/);
});
test('application export has component filenames and instructions, not duplicate base scripts',()=>{
 const files=S.appPackage({selected:['7Zip']},apps);assert.deepEqual(Object.keys(files),['Apps-Stage.ps1','Apps-Prepare.ps1','README.txt']);assert.match(files['README.txt'],/not standalone scripts/);
});
if(process.env.BUILDER_FIXTURE_DIR){const dir=process.env.BUILDER_FIXTURE_DIR;fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(path.join(dir,'base-only.ps1'),S.baseCode({source:'both',catalog:'https://example.org/catalog.json'}));fs.writeFileSync(path.join(dir,'updates-only.ps1'),S.baseCode({}).replace('# === ADD YOUR CONFIGURATION COMPONENTS HERE ===',B.generate('updates',{})));for(const phase of ['stage','prepare'])fs.writeFileSync(path.join(dir,'apps-'+phase+'.ps1'),S.appCode({selected:['Microsoft365Apps','7Zip','DotNetRuntime'],dotnetRuntime:true,dotnetDesktop:true},apps,phase));for(const [type,input]of Object.entries(componentExamples))fs.writeFileSync(path.join(dir,'component-'+type+'.ps1'),B.generate(type,input));fs.writeFileSync(path.join(dir,'commands.json'),JSON.stringify(Object.entries(componentExamples).flatMap(([type,input])=>B.commands(type,input))));let code=C.generate(base(),apps,'stage');const blocks=[B.generate('wifi',{wifiMode:'xml',wifiPath:'Files\\WiFi.xml'}),B.generate('registry',{registry:[{path:'HKLM:\\SOFTWARE\\X',name:'A',type:'DWord',value:'1',view:'Registry64'}]}),B.generate('certificates',{certificates:[{path:'Files\\root.cer',store:'Root'}]})];code=code.replace('# === ADD YOUR CONFIGURATION COMPONENTS HERE ===',blocks.join('\r\n'));fs.writeFileSync(path.join(dir,'combined-stage.ps1'),code);fs.writeFileSync(path.join(dir,'prepare.ps1'),C.generate(base(),apps,'prepare'));}
console.log(tests+' builder checks passed.');
