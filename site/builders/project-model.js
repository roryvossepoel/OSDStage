const Deployment = (() => {
  const B = BuilderComponents, C = BuilderCore, S = BuilderScopes;
  const types = Object.keys(B.definitions);
  const title = key => key === 'apps' ? 'Apps' : B.definitions[key].title;
  function appsForBase(saved, base) {
    const apps = S.appState(saved);
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
    if (key === 'apps') return [...C.selected(item, APPS).map(a => a.DisplayName), ...C.repos(item).map(a => a.name)].join(', ');
    if (key === 'updates') return [item.scanOnly ? 'Scan only' : 'Install updates', item.drivers ? 'Include drivers' : '', item.updateTimeout + ' min'].filter(Boolean).join(' · ');
    if (key === 'wifi') return item.wifiMode === 'xml' ? item.wifiPath : item.wifiSSID;
    if (B.isRepository(key)) return C.list(item.repositoryIds).join(', ');
    if (key === 'desktop') return [item.startEnabled && 'Start menu', item.taskbarEnabled && 'Taskbar'].filter(Boolean).join(' · ');
    if (key === 'inbox') return [item.inboxMode === 'preset' ? 'Tested13' : 'Custom list', item.inboxDiagnose ? 'Inspect' : 'Remove'].join(' · ');
    const commands = B.commands(key, item);
    return commands.length === 1 ? '1 staging command' : commands.length + ' staging commands';
  }
  function build(project) {
    const base = S.baseState(project.base || {}), apps = project.parts.apps;
    const items = rows(project), files = [], issues = [];
    if (!items.length) issues.push('Add a component to your deployment.');
    if (apps?.mode === 'offline') base.mode = 'offline';
    issues.push(...S.validateBase(base).map(e => e.message));
    if (apps && C.selected(apps, APPS).length && !base.enableBuiltIns) issues.push('Enable built-in apps in Base settings.');
    if (items.some(([key]) => B.isRepository(key)) || (apps && C.repos(apps).length)) {
      if (base.source === 'builtin') issues.push('Enable your repository and set its catalog URL in Base settings.');
      else if (apps && C.repos(apps).length && apps.catalog.trim() !== base.catalog.trim()) issues.push('Choose the same catalog URL in Apps and Base settings.');
    }
    if (base.mode === 'offline' && (project.parts.updates || project.parts.capabilities && C.list(project.parts.capabilities.capabilitiesAdd).length)) issues.push('Windows Update and capability downloads require an online target.');
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
  return {types, title, rows, detail, appsForBase, build: project => C.withDeploymentFiles(() => build(project))};
})();
