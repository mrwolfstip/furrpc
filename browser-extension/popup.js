const api = chrome;
const sourceRoot = document.querySelector("#sources");
const hostInput = document.querySelector("#host");
const message = document.querySelector("#message");
const browsingCheck = document.querySelector("#show-browsing");
let enabled = [];
let custom = [];

function getSettings() {
  return new Promise(resolve => api.storage.local.get(["enabledHosts", "customHosts", "showBrowsing"], value => resolve(value)));
}

function save() {
  api.storage.local.set({ enabledHosts: enabled, customHosts: custom });
}

function normaliseHost(value) {
  let text = value.trim().toLowerCase();
  try { if (text.includes("://")) text = new URL(text).hostname; } catch (_) { return ""; }
  text = text.replace(/^www\./, "").replace(/^\.+|\.+$/g, "");
  return /^[a-z0-9.-]+\.[a-z]{2,}$/.test(text) ? text : "";
}

function row(name, host, isCustom) {
  const line = document.createElement("div");
  line.className = "source";
  const label = document.createElement("label");
  const check = document.createElement("input");
  check.type = "checkbox";
  check.checked = enabled.includes(host);
  check.addEventListener("change", () => {
    enabled = check.checked ? [...new Set([...enabled, host])] : enabled.filter(item => item !== host);
    save();
  });
  const title = document.createElement("span");
  title.textContent = name;
  const hostname = document.createElement("small");
  hostname.textContent = host;
  label.append(check, title, hostname);
  line.append(label);
  if (isCustom) {
    const remove = document.createElement("button");
    remove.className = "remove";
    remove.type = "button";
    remove.textContent = "remove";
    remove.addEventListener("click", () => {
      custom = custom.filter(item => item !== host);
      enabled = enabled.filter(item => item !== host);
      save(); render();
    });
    line.append(remove);
  }
  return line;
}

function section(title) {
  const heading = document.createElement("div");
  heading.className = "section";
  heading.textContent = title;
  sourceRoot.append(heading);
}

function render() {
  sourceRoot.replaceChildren();
  for (const kind of ["video", "music"]) {
    section(kind === "video" ? "video streaming" : "music streaming");
    for (const [name, host, type] of FURRPC_DEFAULT_SOURCES.filter(item => item[2] === kind)) {
      sourceRoot.append(row(name, host, false));
    }
  }
  if (custom.length) {
    section("your websites");
    for (const host of custom) sourceRoot.append(row(host, host, true));
  }
}

document.querySelector("#add-form").addEventListener("submit", event => {
  event.preventDefault();
  const host = normaliseHost(hostInput.value);
  if (!host) { message.textContent = "enter a hostname like example.com"; return; }
  message.textContent = "";
  if (!FURRPC_DEFAULT_HOSTS.includes(host) && !custom.includes(host)) custom.push(host);
  if (!enabled.includes(host)) enabled.push(host);
  hostInput.value = "";
  save(); render();
});

document.querySelector("#defaults").addEventListener("click", () => {
  enabled = [...FURRPC_DEFAULT_HOSTS];
  custom = [];
  save(); render();
});

browsingCheck.addEventListener("change", () => api.storage.local.set({ showBrowsing: browsingCheck.checked }));

getSettings().then(settings => {
  enabled = Array.isArray(settings.enabledHosts) ? settings.enabledHosts : [...FURRPC_DEFAULT_HOSTS];
  custom = Array.isArray(settings.customHosts) ? settings.customHosts : [];
  browsingCheck.checked = settings.showBrowsing === true;
  if (!Array.isArray(settings.enabledHosts)) save();
  render();
});
