// Text export retains every allowed scalar field; no audio/base64 or URL queries.
export function diagnosticLabel(e, fallback = "") {
  const identity = [e.run ? `run=${e.run.slice(0,8)}` : "",e.slot ? `slot=${e.slot}` : "",
    e.request ? `req=${e.request}` : ""].filter(Boolean).join(" ");
  const traceTypes = new Set(["client-stage","prefetch-received","prefetch-retry","audio-delivered",
    "backend-request","backend-headers","backend-body","backend-error","server-status","bridge-send","bridge-reply","bridge-timeout"]);
  const detail = traceTypes.has(e.type) ? [e.type,e.quest?`q${e.quest}`:e.hash?`book:${e.hash}`:"",
    e.kind,e.locale,e.stage,e.attempt?`attempt=${e.attempt}`:"",e.status!==undefined?`HTTP ${e.status}`:"",
    e.bytes!==undefined?`${e.bytes} B`:"",e.ms!==undefined?`${e.ms} ms`:"",e.detail,e.error].filter(Boolean).join(" · ") : fallback;
  return [identity,detail || [e.type,e.error,e.detail,e.path].filter(Boolean).join(" · ")].filter(Boolean).join(" · ");
}
export function exportDiagnostics(events, version) {
  const lines = ["CatQuest extension diagnostic report v1",`exported=${new Date().toISOString()} ext=${version} events=${events.length}`,
    "Downloaded, served to VFS and Lua API returned are separate stages. Audible playback is not confirmed by these APIs.",
    "Client trace requires addon 0.10.92+ and extension 0.6.58+. Match game bridge contactPage to run; then slot + quest/kind.",""];
  const tracks = new Map();
  for (const e of events) if (e.slot) {
    const key = `${e.run || "?"}/${e.slot}`;
    const track = tracks.get(key) || {quest:e.quest,kind:e.kind,ready:false,font:false,play:false};
    if(e.quest) track.quest=e.quest;
    if(e.kind) track.kind=e.kind;
    if(e.type === "prefetch" && e.ok) track.ready=true;
    if(e.type === "client-stage" && e.stage?.startsWith("font-ready")) track.font=true;
    if(e.type === "client-stage" && e.stage?.startsWith("playing")) track.play=true;
    if(e.type === "client-stage" && e.stage === "preload") track.preload=true;
    track.last=e.type === "client-stage" ? e.stage : e.type; track.at=e.at;
    tracks.delete(key);tracks.set(key,track);
  }
  lines.push("LATEST TRACKS (not observed may mean cached file reads or a truncated log):");
  for(const [key,t] of [...tracks].slice(-20)) lines.push(`${key} q${t.quest || 0} ${t.kind || "?"} `+
    `download=${t.ready?"ready":"not observed"} clientFont=${t.font?"confirmed":"not observed"} `+
    `clientPlay=${t.play?"API returned":"not observed"} preload=${!!t.preload} last=${t.last} age=${Math.max(0,Math.round((Date.now()-t.at)/1000))}s`);
  lines.push("","EVENTS oldest first:");
  for (const event of events) {
    const safe = Object.fromEntries(Object.entries(event).filter(([key,v]) =>
      !["body64","url","token","text","player"].includes(key) && ["string","number","boolean"].includes(typeof v))
      .map(([key,v])=>[key,typeof v === "string" ? v.slice(0,640) : v]));
    lines.push(`${new Date(event.at || 0).toISOString()}\t${JSON.stringify(safe)}`);
  }
  return lines.join("\n");
}
