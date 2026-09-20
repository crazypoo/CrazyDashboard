//
//  PTPitWallWebUI.swift
//  CrazyDashboard
//
//  EN: Embedded, dependency-free read-only Pit Wall browser interface.
//  ES: Interfaz de navegador Pit Wall integrada, sin dependencias y de solo lectura.
//  中文：内嵌、无依赖、只读的 Pit Wall 浏览器界面。
//

import Foundation

public enum PTPitWallWebUI {
    public static func html(token: String) -> Data {
        let safeToken = token.filter { $0.isLetter || $0.isNumber }
        let page = #"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'">
          <title>PTSpeed Pit Wall</title>
          <style>
            :root { color-scheme: dark; --bg:#0b0e12; --card:#151a21; --line:#26313d; --blue:#4da3ff; --green:#4ee58b; --orange:#ffad4d; --muted:#8b9aaa; }
            * { box-sizing:border-box; }
            body { margin:0; background:radial-gradient(circle at 15% 0,#17283a 0,#0b0e12 42%); color:#f5f7fa; font:15px -apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif; }
            main { max-width:1180px; margin:0 auto; padding:24px; }
            header { display:flex; justify-content:space-between; align-items:center; gap:16px; margin-bottom:18px; }
            h1 { font-size:26px; margin:0; letter-spacing:.03em; } h2 { font-size:16px; margin:0 0 12px; color:#dbe9f8; }
            .status { color:var(--muted); } .online { color:var(--green); } .offline { color:var(--orange); }
            .grid { display:grid; grid-template-columns:1.25fr 1fr 1fr; gap:14px; }
            .card { background:rgba(21,26,33,.9); border:1px solid var(--line); border-radius:16px; padding:16px; box-shadow:0 12px 28px rgba(0,0,0,.2); }
            .wide { grid-column:span 2; } .full { grid-column:1/-1; }
            .metrics { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:10px; }
            .metric { background:#0f141a; border-radius:12px; padding:12px; min-height:76px; } .label { color:var(--muted); font-size:12px; }
            .value { font-size:25px; font-weight:650; margin-top:8px; color:var(--blue); } .small { font-size:14px; color:#e9eef5; }
            #twin { width:100%; min-height:170px; display:grid; place-items:center; background:linear-gradient(180deg,#111b25,#0e1217); border-radius:12px; }
            #bike { width:min(90%,430px); height:150px; } .wheel { fill:none; stroke:#95a6b7; stroke-width:5; } .frame { fill:none; stroke:var(--blue); stroke-width:6; stroke-linecap:round; stroke-linejoin:round; }
            #track { width:100%; height:200px; background:#0f141a; border-radius:12px; } canvas { width:100%; height:200px; display:block; }
            .events { max-height:220px; overflow:auto; margin:0; padding:0; list-style:none; } .events li { border-bottom:1px solid #202832; padding:9px 0; color:#c6d1dc; }
            .events time { color:var(--muted); margin-right:8px; } .footer { color:var(--muted); font-size:12px; margin-top:18px; }
            @media (max-width:800px) { .grid { grid-template-columns:1fr; } .wide,.full { grid-column:auto; } main { padding:14px; } }
          </style>
        </head>
        <body>
          <main>
            <header><div><h1>PTSpeed Pit Wall</h1><div class="status" id="connection">Waiting for vehicle data</div></div><div class="status" id="updated">—</div></header>
            <section class="grid">
              <article class="card wide"><h2>Digital Twin</h2><div id="twin"><svg id="bike" viewBox="0 0 430 150" aria-label="Simplified motorcycle digital twin"><circle class="wheel" cx="92" cy="108" r="30"/><circle class="wheel" cx="338" cy="108" r="30"/><path class="frame" d="M92 108 L156 69 L241 108 L338 108 M156 69 L190 108 M241 108 L270 62 L338 108 M270 62 L303 48"/><path class="frame" d="M178 50 L202 50 M202 50 L218 70"/></svg></div></article>
              <article class="card"><h2>Live Telemetry</h2><div class="metrics"><div class="metric"><div class="label">Speed</div><div class="value" id="speed">—</div></div><div class="metric"><div class="label">RPM</div><div class="value" id="rpm">—</div></div><div class="metric"><div class="label">Fuel</div><div class="value" id="fuel">—</div></div><div class="metric"><div class="label">Voltage</div><div class="value" id="voltage">—</div></div></div></article>
              <article class="card"><h2>Vehicle State</h2><div class="metrics"><div class="metric"><div class="label">Context</div><div class="small" id="context">—</div></div><div class="metric"><div class="label">Freshness</div><div class="small" id="freshness">—</div></div><div class="metric"><div class="label">ABS</div><div class="small" id="abs">—</div></div><div class="metric"><div class="label">TCS</div><div class="small" id="tcs">—</div></div><div class="metric"><div class="label">Lean</div><div class="small" id="lean">—</div></div><div class="metric"><div class="label">Engine</div><div class="small" id="engine">—</div></div></div></article>
              <article class="card wide"><h2>Live Track</h2><div id="track"><canvas id="map"></canvas></div></article>
              <article class="card"><h2>Speed / RPM</h2><div id="chart"><canvas id="series"></canvas></div></article>
              <article class="card full"><h2>Event Stream</h2><ul class="events" id="events"><li>No events yet</li></ul></article>
            </section>
            <div class="footer">Read-only LAN session · No BLE, OBD, OTA or vehicle-control commands are exposed.</div>
          </main>
          <script>
            const token = "__TOKEN__";
            const url = "/api/snapshot?token=" + encodeURIComponent(token);
            const text = (id, value) => { const node=document.getElementById(id); if (node) node.textContent = value == null ? "—" : String(value); };
            const fmt = (value, digits=1, suffix="") => value == null ? "—" : Number(value).toFixed(digits) + suffix;
            const date = value => value ? new Date(value).toLocaleTimeString() : "—";
            function drawSeries(samples) {
              const canvas=document.getElementById("series"), rect=canvas.getBoundingClientRect(), ratio=window.devicePixelRatio||1;
              canvas.width=Math.max(1,rect.width*ratio); canvas.height=Math.max(1,rect.height*ratio); const ctx=canvas.getContext("2d"); ctx.scale(ratio,ratio);
              const w=rect.width,h=rect.height; ctx.clearRect(0,0,w,h); ctx.strokeStyle="#26313d"; ctx.lineWidth=1;
              for(let i=1;i<4;i++){ctx.beginPath();ctx.moveTo(0,h*i/4);ctx.lineTo(w,h*i/4);ctx.stroke();}
              if(!samples || samples.length<2) return; const maxSpeed=Math.max(40,...samples.map(s=>s.speedKmh||0)); const maxRPM=Math.max(4000,...samples.map(s=>s.rpm||0));
              const line=(key,max,color,maxValue)=>{ctx.strokeStyle=color;ctx.lineWidth=2;ctx.beginPath();samples.forEach((s,i)=>{const x=w*i/(samples.length-1),y=h-(Number(s[key]||0)/max)*h*.9-5;i?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.stroke();};
              line("speedKmh",maxSpeed,"#4da3ff",maxSpeed); line("rpm",maxRPM,"#ffad4d",maxRPM);
            }
            function drawMap(samples) {
              const canvas=document.getElementById("map"), rect=canvas.getBoundingClientRect(), ratio=window.devicePixelRatio||1;
              canvas.width=Math.max(1,rect.width*ratio); canvas.height=Math.max(1,rect.height*ratio); const ctx=canvas.getContext("2d"); ctx.scale(ratio,ratio); ctx.clearRect(0,0,rect.width,rect.height);
              const points=(samples||[]).filter(s=>s.coordinate); if(points.length<2){ctx.fillStyle="#8b9aaa";ctx.font="13px sans-serif";ctx.fillText("Waiting for location",16,28);return;}
              const lats=points.map(p=>p.coordinate.latitude),lons=points.map(p=>p.coordinate.longitude),minLat=Math.min(...lats),maxLat=Math.max(...lats),minLon=Math.min(...lons),maxLon=Math.max(...lons),dx=Math.max(maxLon-minLon,0.00001),dy=Math.max(maxLat-minLat,0.00001);
              ctx.strokeStyle="#4ee58b";ctx.lineWidth=3;ctx.beginPath();points.forEach((p,i)=>{const x=16+(p.coordinate.longitude-minLon)/dx*(rect.width-32),y=rect.height-16-(p.coordinate.latitude-minLat)/dy*(rect.height-32);i?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.stroke();
            }
            function render(snapshot) {
              const connected=snapshot.dashboardConnected||snapshot.obdConnected; text("connection",connected?"Vehicle connected":"Vehicle disconnected"); document.getElementById("connection").className="status "+(connected?"online":"offline");
              text("updated",date(snapshot.updatedAt)); text("speed",fmt(snapshot.speedKmh,1," km/h")); text("rpm",snapshot.rpm==null?"—":snapshot.rpm.toLocaleString()); text("fuel",fmt(snapshot.fuelPercent,1," %")); text("voltage",fmt(snapshot.voltage,2," V"));
              text("context",snapshot.context); text("freshness",snapshot.freshness); text("abs",snapshot.absState); text("tcs",snapshot.tcsState); text("lean",fmt(snapshot.leanDegrees,1,"°")); text("engine",snapshot.engineState);
              drawSeries(snapshot.samples); drawMap(snapshot.samples); const list=document.getElementById("events"); list.replaceChildren(); (snapshot.events||[]).slice().reverse().forEach(event=>{const item=document.createElement("li"),time=document.createElement("time");time.textContent=date(event.occurredAt);item.append(time,document.createTextNode(event.kind+" · "+event.context));list.append(item);}); if(!snapshot.events||snapshot.events.length===0){const item=document.createElement("li");item.textContent="No events yet";list.append(item);}
            }
            async function poll(){try{const response=await fetch(url,{cache:"no-store"});if(!response.ok)throw new Error("HTTP "+response.status);render(await response.json());}catch(error){text("connection","Pit Wall waiting for iPhone");document.getElementById("connection").className="status offline";}setTimeout(poll,750);} poll();
          </script>
        </body>
        </html>
        """#
        return Data(page.replacingOccurrences(of: "__TOKEN__", with: safeToken).utf8)
    }
}
