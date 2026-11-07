let page;
const $ = (id) => document.getElementById(id);
$('capture').addEventListener('click', async () => {
  $('send').disabled = true; page = undefined;
  try {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    if (!tab || !/^https?:\/\//i.test(tab.url || '')) throw new Error('Open a normal HTTP or HTTPS page first.');
    const [{result}] = await chrome.scripting.executeScript({target: {tabId: tab.id}, func: () => {
      // Walk visible text nodes, without reading input values or HTML markup.
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      let text = '', node, visited = 0;
      while ((node = walker.nextNode()) && text.length < 30000 && visited++ < 50000) {
        const parent = node.parentElement;
        if (!parent || parent.closest('script,style,noscript,input,textarea,select,[contenteditable],[hidden],[aria-hidden="true"]')) continue;
        const style = getComputedStyle(parent);
        if (style.visibility === 'hidden' || style.display === 'none' || !parent.getClientRects().length) continue;
        const value = node.textContent.trim();
        if (value) text += value + '\n';
      }
      const url = new URL(location.href); url.username = ''; url.password = '';
      // Query strings and fragments often carry tokens; omit them from context.
      url.search = ''; url.hash = '';
      return {version: 1, title: document.title.slice(0, 500), url: url.href.slice(0, 4000), text: text.slice(0, 30000), capturedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')};
    }});
    page = result;
    $('title').textContent = page.title; $('url').textContent = page.url; $('preview').value = page.text;
    $('status').textContent = 'Check the preview before saving it locally.'; $('send').disabled = false;
  } catch (error) { $('status').textContent = error.message; }
});
$('send').addEventListener('click', async () => {
  if (!page) return;
  $('send').disabled = true;
  try {
    const result = await chrome.runtime.sendNativeMessage('dev.newtv1.browser', page);
    if (!result?.ok) throw new Error(result?.message || 'Newtv1 could not receive the preview.');
    $('status').textContent = result.message;
  } catch (error) { $('status').textContent = error.message + ' Check the native-host installation instructions.'; }
  finally { $('send').disabled = false; }
});
