(() => {
  let last = "";

  const serviceName = () => {
    const host = location.hostname.replace(/^www\./, "");
    const known = {
      "youtube.com": "YouTube", "music.youtube.com": "YouTube Music",
      "netflix.com": "Netflix", "soundcloud.com": "SoundCloud",
      "open.spotify.com": "Spotify", "twitch.tv": "Twitch",
      "disneyplus.com": "Disney+", "primevideo.com": "Prime Video",
      "amazon.com": "Amazon Music", "music.apple.com": "Apple Music",
      "max.com": "Max", "hulu.com": "Hulu", "paramountplus.com": "Paramount+",
      "peacocktv.com": "Peacock", "crunchyroll.com": "Crunchyroll",
      "bandcamp.com": "Bandcamp", "mixcloud.com": "Mixcloud", "vimeo.com": "Vimeo"
    };
    return known[host] || host.split(".").slice(0, -1).join(" ").replace(/\b\w/g, c => c.toUpperCase()) || "Browser Media";
  };

  const cleanTitle = (service) => {
    let title = document.title || service;
    for (const suffix of [" - YouTube", " | Netflix", " | SoundCloud", " - Twitch", " | Spotify"]) {
      if (title.endsWith(suffix)) title = title.slice(0, -suffix.length);
    }
    return title.trim().slice(0, 128) || service;
  };

  const report = () => {
    const media = [...document.querySelectorAll("video, audio")];
    const active = media.find(m => !m.paused && !m.ended && m.readyState >= 2);
    const service = serviceName();
    const data = {
      playing: !!active,
      service,
      title: cleanTitle(service),
      kind: active?.tagName?.toLowerCase() === "audio" ? "audio" : "video",
      position: active && Number.isFinite(active.currentTime) ? active.currentTime : 0,
      duration: active && Number.isFinite(active.duration) ? active.duration : 0
    };
    const signature = JSON.stringify(data);
    if (signature !== last) {
      last = signature;
      try {
        const pending = chrome.runtime.sendMessage({ type: "furrpc-media", data });
        if (pending && pending.catch) pending.catch(() => {});
      } catch (_) {}
    }
  };

  addEventListener("play", report, true);
  addEventListener("pause", report, true);
  addEventListener("ended", report, true);
  addEventListener("popstate", report, true);
  setInterval(report, 4000);
  report();
})();
