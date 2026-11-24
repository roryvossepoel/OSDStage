const Deployment = (() => {
  const B = BuilderComponents, C = BuilderCore, S = BuilderScopes;
  const types = Object.keys(B.definitions);
  const title = key => key === 'apps' ? 'Apps' : B.definitions[key].title;
  function onlineProject(project) {
    const parts = {...project.parts};
    if (parts.apps) parts.apps = {...parts.apps, mode:'online', skipRefresh:false};
    for (const key of Object.keys(parts)) {
      if (B.isRepository(key)) parts[key] = {...parts[key], repositorySkipRefresh:false};
    }
    return {base:project.base ? {...project.base, mode:'online'} : null, parts};
  }
  function appsForBase(saved, base) {
    const apps = S.appState({...saved, mode:'online', skipRefresh:false});
    const catalog = base.source === 'builtin' ? '' : base.catalog.trim();
    if (!base.enableBuiltIns) apps.selected = [];
    if (!catalog || apps.catalog.trim() !== catalog) {
      apps.repoSelected = [];
      apps.repoItems = [];
    }
    apps.catalog = catalog;
    apps.source = apps.repoSelected.length ? (apps.selected.length ? 'both' : 'repository') : 'builtin';
    return apps;
  }
  function rows(project) {
    // Match the staging flow in the module's builder. Check updates after the other workloads.
    return Object.entries(project.parts).sort(([a],[b]) => Number(a === 'updates') - Number(b === 'updates'));
  }
  function detail(key, item) {
    if (key === 'updates') return [item.scanOnly ? 'Scan only' : 'Install updates', item.drivers ? 'Include drivers' : '', item.updateTimeout + ' min'].filter(Boolean).join(' · ');
    if (key === 'wifi') return item.wifiMode === 'xml' ? item.wifiPath : item.wifiSSID;
    if (B.isRepository(key)) return C.list(item.repositoryIds).join(', ');
    if (key === 'desktop') return [item.startEnabled && 'Start menu', item.taskbarEnabled && 'Taskbar'].filter(Boolean).join(' · ');
    if (key === 'inbox') return [item.inboxMode === 'preset' ? 'Tested13' : 'Custom list', item.inboxDiagnose ? 'Inspect' : 'Remove'].join(' · ');
    const commands = B.commands(key, item);
    return commands.length === 1 ? '1 staging command' : commands.length + ' staging commands';
  }
  function selections(project) {
    const result=[];
    for (const [type,state] of rows(project)) {
      if (type === 'apps') {
        for (const id of state.selected) {
          const app=APPS.find(a=>a.Id===id);
          result.push({key:'builtin:'+id, type:'builtin', id, name:app?.DisplayName || id, detail:'Built-in app', editable:!!app});
        }
        for (const id of state.repoSelected) {
          const app=state.repoItems.find(p=>p.id===id);
          result.push({key:'repo:'+id, type:'repo', id, name:app?.name || id, detail:'Repository app', editable:!!app});
        }
      } else if (B.isRepository(type)) {
        for (const id of C.list(state.repositoryIds)) {
          result.push({key:type+':'+id, type, id, name:id, detail:B.definitions[type].repositoryType+' package', editable:true});
        }
      } else {
        result.push({key:type, type, name:title(type), detail:detail(type,state), editable:true});
      }
    }
    return result;
  }

  function removeComponent(parts, item) {
    if (B.isRepository(item.type)) {
      const current=parts[item.type];
      const remaining=C.list(current.repositoryIds).filter(id=>id!==item.id);
      if (remaining.length) {
        parts[item.type]={...current,repositoryIds:remaining.join('\n')};
        return;
      }
    }
    delete parts[item.type];
  }
  function build(project) {
    const base = S.baseState(project.base || {}), apps = project.parts.apps;
    const items = rows(project), files = [], issues = [];
    if (!items.length) issues.push('Add a component to your deployment.');
    issues.push(...S.validateBase(base).map(e => e.message));
    if (apps && C.selected(apps, APPS).length && !base.enableBuiltIns) issues.push('Enable built-in apps in Deployment settings.');
    if (items.some(([key]) => B.isRepository(key)) || (apps && C.repos(apps).length)) {
      if (base.source === 'builtin') issues.push('Enable your repository and set its catalog URL in Deployment settings.');
      else if (apps && C.repos(apps).length && apps.catalog.trim() !== base.catalog.trim()) issues.push('Choose the same catalog URL in Apps and Deployment settings.');
    }
    const blocks = [];
    files.push(...C.requiredFiles(base, []));
    for (const [key, state] of items) {
      const errors = key === 'apps' ? S.validateApps(state, APPS) : B.validate(key, state);
      issues.push(...errors.map(e => title(key) + ' · ' + e.message));
      if (errors.length) continue;
      const cfg = key === 'apps' ? state : B.state(key, state);
      files.push(...C.requiredFiles(cfg, key === 'apps' ? APPS : []));
      const block = key === 'apps' ? S.appCode(state, APPS) : B.generate(key, state);
      blocks.push('# ' + title(key) + '\r\n' + block.trimEnd());
    }
    if (issues.length) return {issues, files, code:''};
    let script = C.renderScript({...base, baseOnly:base.moduleSource !== 'local'}, [], 'stage', blocks);
    const needsFilesRoot = files.some(f => !/^[a-z]:\\/i.test(f.path));
    const header = ['# WinPE · after Windows is applied, before the first reboot.', '& {', "$ErrorActionPreference = 'Stop'"];
    if (needsFilesRoot) header.push('$stageFilesRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }');
    return {issues, files, code:header.join('\r\n')+'\r\n\r\n'+script.replace(/^#requires[^\r\n]*\r?\n/gmi,'').trimEnd()+'\r\n}\r\n'};
  }
  return {types, title, rows, selections, removeComponent, onlineProject, appsForBase, build: project => C.withDeploymentFiles(() => build(onlineProject(project)))};
})();
