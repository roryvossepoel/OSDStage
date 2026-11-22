const AppCatalog = (() => {
  async function json(url, signal) {
    const timeout = AbortSignal.timeout(15000);
    let response;
    try {
      response = await fetch(url, {
        signal: AbortSignal.any([signal, timeout]),
        credentials: 'omit', referrerPolicy: 'no-referrer', cache: 'no-store'
      });
    } catch (error) {
      if (timeout.aborted) throw Error('Request timed out.');
      if (signal.aborted) throw error;
      throw Error('Check the URL, network connection and repository CORS settings.');
    }
    if (!response.ok) throw Error('HTTP ' + response.status);
    const body = await response.text();
    if (body.length > 5000000) throw Error('The JSON file exceeds 5 MB.');
    return JSON.parse(body);
  }

  async function load(catalogUrl, signal, read = json, index = null) {
    const catalog = BuilderCore.url(catalogUrl);
    const items = BuilderCore.parseCatalog(index ?? await read(catalog, signal));
    let next = 0;
    async function worker() {
      while (next < items.length && !signal.aborted) {
        const pos = next++, item = items[pos];
        if (item.blocked || item.status === 'incompatible') continue;
        let manifest;
        try {
          const url = BuilderCore.url(item.manifest.replaceAll('\\', '/'), catalog);
          manifest = await read(url, signal);
        } catch (error) {
          // A manually supplied catalog can still be used by ID when browser access is unavailable.
          items[pos] = {...item, status:index ? 'index' : 'error', error:error.message};
          continue;
        }
        try { items[pos] = BuilderCore.manifest(item, manifest); }
        catch (error) { items[pos] = {...item, status:'error', error:error.message}; }
      }
    }
    await Promise.all(Array.from({length:Math.min(4, items.length)}, worker));
    signal.throwIfAborted();
    return items;
  }
  function selectable(item) {
    return !item.blocked && (item.status === 'index' || (item.status === 'ready' && item.type === 'App'));
  }
  return {load, selectable};
})();
