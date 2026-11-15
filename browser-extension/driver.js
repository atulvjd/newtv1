// Runs in Chrome's isolated world. No page-provided JavaScript is evaluated.
(() => {
  if (globalThis.__newtDriver) return;
  const uuid = () => crypto.randomUUID();
  const state = {document: uuid(), revision: 0, elements: [], snapshot: null, href: location.href};
  const changed = () => { state.revision++; state.snapshot = null; };
  new MutationObserver(changed).observe(document.documentElement, {subtree: true, childList: true, characterData: true, attributes: true,
    attributeFilter: ['aria-label', 'aria-hidden', 'aria-disabled', 'disabled', 'hidden', 'style', 'class', 'type', 'href', 'role']});
  addEventListener('input', changed, true);
  addEventListener('change', changed, true);
  const visible = e => {
    if (e.closest('[hidden],[aria-hidden="true"],[inert]')) return false;
    const s = getComputedStyle(e), r = e.getBoundingClientRect();
    return s.visibility !== 'hidden' && s.display !== 'none' && r.width > 0 && r.height > 0;
  };
  const secure = e => e.matches('input[type="password"],input[type="hidden"]') ||
    /password|one-time-code|cc-|credit-card/.test(e.autocomplete || '');
  const label = e => (e.getAttribute('aria-label') ||
    (e.getAttribute('aria-labelledby') || '').split(/\s+/).map(id => document.getElementById(id)?.textContent || '').join(' ').trim() ||
    (e.labels ? [...e.labels].map(x => x.textContent).join(' ') : '') ||
    e.getAttribute('placeholder') || e.innerText || e.getAttribute('title') || e.getAttribute('name') || e.tagName.toLowerCase()).trim().replace(/\s+/g, ' ').slice(0, 200);
  function snapshot(session) {
    if (state.href !== location.href) { state.href = location.href; state.document = uuid(); changed(); }
    if (state.snapshot && state.snapshot.session === session) return {...state.snapshot, page: {...state.snapshot.page, capturedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')}};
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let text = '', node, visited = 0;
    while ((node = walker.nextNode()) && text.length < 30000 && visited++ < 50000) {
      const p = node.parentElement;
      if (!p || p.closest('script,style,noscript,input,textarea,select,[contenteditable]') || !visible(p)) continue;
      const value = node.textContent.trim(); if (value) text += value + '\n';
    }
    const candidates = document.querySelectorAll('a[href],button,input,textarea,select,[role="button"],[role="link"],[role="textbox"],[contenteditable="true"]');
    state.elements = Array.from(candidates).slice(0, 5000).filter(e => visible(e) && !secure(e) && !e.disabled && e.getAttribute('aria-disabled') !== 'true').slice(0, 160);
    const controls = state.elements.map((e, i) => ({id: i + 1, role: e.tagName === 'INPUT' && e.type === 'file' ? 'file' : e.tagName.toLowerCase(), label: label(e),
      editable: e.matches('input:not([type="file"]):not([type="checkbox"]):not([type="radio"]):not([type="submit"]):not([type="button"]),textarea,[contenteditable="true"]') && !e.readOnly,
      options: e.tagName === 'SELECT' ? [...e.options].filter(o => !o.disabled).slice(0,50).map(o => o.text.slice(0,100)) : null}));
    const url = new URL(location.href); url.search = ''; url.hash = ''; url.username = ''; url.password = '';
    state.snapshot = {session, document: state.document, revision: state.revision, controls,
      page: {version: 1, title: document.title.slice(0, 500), url: url.href.slice(0, 4000), text: text.slice(0, 30000), capturedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')}};
    while (new TextEncoder().encode(JSON.stringify(state.snapshot)).length > 170000) {
      if (state.snapshot.page.text.length > 1000) state.snapshot.page.text = state.snapshot.page.text.slice(0, Math.floor(state.snapshot.page.text.length / 2));
      else { state.snapshot.controls.pop(); state.elements.pop(); }
    }
    return state.snapshot;
  }
  function act(command, upload = null) {
    const current = snapshot(command.session);
    if (command.document.toLowerCase() !== current.document.toLowerCase() || command.revision !== current.revision ||
        Date.parse(command.expiresAt) <= Date.now()) throw new Error('The page changed. Observe and review a new action.');
    const a = command.action;
    if (!['click','type','select','scroll','back','observe','upload'].includes(a.kind) || typeof a.value !== 'string' || a.value.length > 8000) throw new Error('Invalid action.');
    const e = state.elements[a.target - 1];
    if (['click','type','select','upload'].includes(a.kind)) {
      if (!e || !e.isConnected || !visible(e) || secure(e) || e.disabled || label(e) !== current.controls[a.target - 1].label) throw new Error('The target is no longer available.');
      if (e.type === 'file' && a.kind !== 'upload') throw new Error('File controls require an approved upload.');
      if (a.kind === 'upload') {
        if (e.tagName !== 'INPUT' || e.type !== 'file' || a.value !== '' || !upload || !Array.isArray(upload.chunks) || upload.size < 0 || upload.size > 20*1024*1024 || upload.chunks.length > 320 || typeof upload.fileName !== 'string') throw new Error('Invalid upload.');
        const bytes = upload.chunks.map(chunk => Uint8Array.from(atob(chunk), c => c.charCodeAt(0)));
        if (bytes.reduce((sum, chunk) => sum + chunk.byteLength, 0) !== upload.size) throw new Error('Incomplete upload.');
        const transfer = new DataTransfer();
        transfer.items.add(new File(bytes, upload.fileName, {type:upload.mimeType || 'application/octet-stream'}));
        e.files = transfer.files;
        if (e.files.length !== 1 || e.files[0].size !== upload.size) throw new Error('The page did not accept the file.');
        e.dispatchEvent(new Event('input', {bubbles:true})); e.dispatchEvent(new Event('change', {bubbles:true}));
      }
      if (a.kind === 'click') { e.scrollIntoView({block: 'center'}); e.click(); }
      if (a.kind === 'type') {
        if (!current.controls[a.target - 1].editable) throw new Error('This field is not editable.');
        e.focus();
        if (e.isContentEditable) e.textContent = a.value;
        else {
          const prototype = e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          Object.getOwnPropertyDescriptor(prototype, 'value').set.call(e, a.value);
        }
        e.dispatchEvent(new Event('input', {bubbles: true})); e.dispatchEvent(new Event('change', {bubbles: true}));
        if ((e.isContentEditable ? e.textContent : e.value) !== a.value) throw new Error('The page did not retain the entered text.');
      }
      if (a.kind === 'select') {
        if (e.tagName !== 'SELECT') throw new Error('This is not a selection control.');
        const matches = [...e.options].filter(o => !o.disabled && (o.text === a.value || o.value === a.value));
        if (matches.length !== 1) throw new Error('Select an exact, unique option.');
        e.value = matches[0].value; e.dispatchEvent(new Event('input', {bubbles:true})); e.dispatchEvent(new Event('change', {bubbles:true}));
      }
    } else if (a.kind === 'scroll') {
      if (!['up','down'].includes(a.value)) throw new Error('Invalid scroll.');
      window.scrollBy({top: (a.value === 'up' ? -1 : 1) * innerHeight * 0.8, behavior: 'instant'});
    } else if (a.kind === 'back') history.back();
    changed();
    return a.kind === 'upload' ? 'Selected file attached to the file control. Server receipt requires inspection.' : a.kind === 'type' ? 'Text entered and retained by the field.' : 'Action dispatched. Inspect the fresh page for its outcome.';
  }
  globalThis.__newtDriver = {snapshot, act};
})();
