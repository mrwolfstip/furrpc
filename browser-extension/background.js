const tabs = new Map();
let furrpcKey = "";

async function getKey() {
  if (furrpcKey) return furrpcKey;
  try {
    const response = await fetch("http://127.0.0.1:49193/pair");
    const data = await response.json();
    if (typeof data.key === "string") furrpcKey = data.key;
  } catch (_) {}
  return furrpcKey;
}

async function send(data) {
  try {
    const key = await getKey();
    if (!key) return;
    await fetch("http://127.0.0.1:49193/media", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Furrpc-Browser-Key": key },
      body: JSON.stringify(data)
    });
  } catch (_) { furrpcKey = ""; }
}

// every frame of every tab has its own entry, keyed "tabId:frameId", so an
// embedded player and its page do not overwrite each other. content scripts
// resend every 8 s at most, so an entry that stays silent is gone (a removed
// iframe, a navigation) and is ignored.
const staleAfter = 15000;
const frameKey = (tabId, frameId) => `${tabId}:${frameId || 0}`;

function chosen() {
  const now = Date.now();
  const values = [...tabs.values()].filter(value => now - value.stamp < staleAfter);
  return values.filter(value => value.playing).sort((a, b) => b.stamp - a.stamp)[0]
    || values.filter(value => value.browsing && value.active).sort((a, b) => b.stamp - a.stamp)[0]
    || values.filter(value => value.browsing).sort((a, b) => b.stamp - a.stamp)[0];
}

function publish() {
  const picked = chosen();
  if (!picked) return send({ playing: false, browsing: false });
  const { tabId, ...payload } = picked;
  return send(payload);
}

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message?.type !== "furrpc-media" || sender.tab?.id == null) return;
  const id = frameKey(sender.tab.id, sender.frameId);
  if (message.data.playing || message.data.browsing) {
    tabs.set(id, { ...message.data, tabId: sender.tab.id, active: sender.tab.active === true, stamp: Date.now() });
  } else if (!tabs.delete(id)) {
    return; // an idle frame we never tracked: nothing changed
  }
  publish();
});

chrome.tabs.onActivated.addListener(info => {
  for (const value of tabs.values()) value.active = value.tabId === info.tabId;
  publish();
});

chrome.tabs.onRemoved.addListener(id => {
  let removed = false;
  for (const [key, value] of tabs) {
    if (value.tabId === id) { tabs.delete(key); removed = true; }
  }
  if (removed) publish();
});
