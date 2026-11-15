let connection, timer, lastError = '';
const handled = new Set();
async function readUpload(session, command) {
  const chunks = []; let fileName, size, mimeType;
  for (let index = 0; index <= 320; index++) {
    if (connection !== session) throw new Error('Upload cancelled.');
    const reply = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => { session.chunkWaiter = null; reject(new Error('Upload transfer timed out.')); }, 10000);
      session.chunkWaiter = result => { clearTimeout(timeout); session.chunkWaiter = null; resolve(result); };
      session.port.postMessage({kind:'uploadChunk',commandID:command.id,session:session.id,document:command.document,index});
    });
    const chunk = reply.chunk;
    if (!reply.ok || !chunk || chunk.commandID.toLowerCase() !== command.id.toLowerCase() || chunk.index !== index || typeof chunk.data !== 'string' || chunk.data.length > 88000) throw new Error(reply.message || 'Invalid upload transfer.');
    if (index === 0) { fileName = chunk.fileName; size = chunk.size; mimeType = chunk.mimeType; }
    if (size < 0 || size > 20*1024*1024 || chunk.size !== size || chunk.fileName !== fileName || chunk.mimeType !== mimeType) throw new Error('Upload metadata changed.');
    chunks.push(chunk.data);
    if (chunk.last) return {fileName,size,mimeType,chunks};
  }
  throw new Error('Upload exceeded its size limit.');
}
async function inspect(session) {
  await chrome.scripting.executeScript({target: {tabId: session.tabId}, files: ['driver.js']});
  const [{result}] = await chrome.scripting.executeScript({target: {tabId: session.tabId}, func: id => globalThis.__newtDriver.snapshot(id), args: [session.id]});
  return result;
}
function disconnect() {
  clearTimeout(timer);
  if (!connection) return;
  const old = connection; connection = undefined;
  try { old.port.postMessage({kind:'poll', session:old.id, connected:false, message:'Disconnected by you.', snapshot:null, result:null}); } catch (_) {}
  old.port.disconnect();
}
async function poll(session, result = null) {
  if (connection !== session) return;
  try {
    const snapshot = await inspect(session);
    session.port.postMessage({kind:'poll', session:session.id, connected:true, message:'Connected to one tab. Actions require review in Newtv1.', snapshot, result});
  } catch (error) {
    if (!lastError) lastError = error.message;
    session.error = 'Page access ended. Reconnect this tab from the extension. ' + error.message;
    try { session.port.postMessage({kind:'poll', session:session.id, connected:false, message:session.error.slice(0,1000), snapshot:null, result}); } catch (_) {}
    disconnect();
  }
}
async function connect(tabId) {
  disconnect(); handled.clear(); lastError = '';
  const session = {id:crypto.randomUUID(), tabId, port:chrome.runtime.connectNative('dev.newtv1.browser')};
  connection = session;
  session.port.onDisconnect.addListener(() => { const error = chrome.runtime.lastError; if (connection === session) { lastError = error?.message || 'Native host disconnected.'; connection = undefined; clearTimeout(timer); } });
  session.port.onMessage.addListener(async reply => {
    if (connection !== session) return;
    if (session.chunkWaiter) { session.chunkWaiter(reply); return; }
    clearTimeout(timer);
    let result = null;
    if (reply.command) {
      const c = reply.command;
      if (c.session.toLowerCase() !== session.id.toLowerCase() || handled.has(c.id)) return;
      handled.add(c.id);
      if (handled.size > 500) { disconnect(); return; }
      try {
        const upload = c.action.kind === 'upload' ? await readUpload(session, c) : null;
        if (connection !== session) throw new Error('Task disconnected.');
        const [{result:message}] = await chrome.scripting.executeScript({target:{tabId:session.tabId}, func: (command, upload) => {
          if (!globalThis.__newtDriver) throw new Error('The document changed. Observe again.');
          return globalThis.__newtDriver.act(command, upload);
        }, args:[c,upload]});
        // Let navigation/rendering settle. A failed observation never causes mutation replay.
        await new Promise(resolve => setTimeout(resolve, 350));
        let snapshot = null; try { snapshot = await inspect(session); } catch (_) {}
        result = {id:c.id, ok:true, message, snapshot:null};
      } catch (error) { result = {id:c.id, ok:false, message:error.message.slice(0,2000), snapshot:null}; }
    }
    timer = setTimeout(() => poll(session, result), result ? 0 : 1000);
  });
  await poll(session);
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id) return;
  if (message.kind === 'connect') { connect(message.tabId).then(() => respond({ok:!!connection,message:lastError})).catch(e => respond({ok:false,message:e.message})); return true; }
  if (message.kind === 'disconnect') { disconnect(); respond({ok:true}); }
  if (message.kind === 'status') respond({connected:!!connection, tabId:connection?.tabId});
});
chrome.tabs.onRemoved.addListener(tabId => { if (connection?.tabId === tabId) disconnect(); });
