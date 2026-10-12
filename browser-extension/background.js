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

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message?.type !== "furrpc-media" || sender.tab?.id == null) return;
  const id = sender.tab.id;
  if (message.data.playing) tabs.set(id, { ...message.data, stamp: Date.now() });
  else tabs.delete(id);
  const active = [...tabs.values()].sort((a, b) => b.stamp - a.stamp)[0];
  send(active || { playing: false });
});

chrome.tabs.onRemoved.addListener(id => {
  if (!tabs.delete(id)) return;
  const active = [...tabs.values()].sort((a, b) => b.stamp - a.stamp)[0];
  send(active || { playing: false });
});
