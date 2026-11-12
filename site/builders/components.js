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
 function generate(type,input){const s=state(type,input),errors=validate(type,input);if(errors.length)throw Error(errors.map(x=>x.message).join('\n'));const a=[];
 if(type==='wifi'&&s.wifiMode==='settings'&&s.wifiSecurity!=='Open')a.push("$wifiPassword = Read-Host 'Wi-Fi password' -AsSecureString");
 a.push(...C.commands(s,[],'stage').map(c=>C.line(c)));return a.join('\r\n')+'\r\n';
 }
 return {definitions,state,validate,generate};
})();if(typeof module!=='undefined'&&module.exports)module.exports=BuilderComponents;
