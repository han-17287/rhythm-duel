/* Track both Godot SFX and music contexts before the engine creates either. */
window.PerfectoAudioUnlock = (() => {
  const contexts=new Set(),constructors=new Map();
  function track(ctx) {
    if(ctx.state==='closed' || contexts.has(ctx))return ctx;
    contexts.add(ctx);
    ctx.addEventListener?.('statechange',()=>{if(ctx.state==='closed')contexts.delete(ctx);});
    return ctx;
  }
  for(const name of ['AudioContext','webkitAudioContext']) {
    const Native=window[name];if(typeof Native!=='function')continue;
    if(!constructors.has(Native))constructors.set(Native,new Proxy(Native,{
      construct(target,args,newTarget){return track(Reflect.construct(target,args,newTarget));}
    }));
    try{window[name]=constructors.get(Native);}catch(_){}
  }
  function resumeAll() {
    const attempts=new Map();
    for(const ctx of contexts) {
      if(ctx.state==='closed'){contexts.delete(ctx);continue;}
      if(ctx.state==='running'){attempts.set(ctx,Promise.resolve(true));continue;}
      try{attempts.set(ctx,Promise.resolve(ctx.resume()).then(()=>ctx.state==='running').catch(()=>false));}
      catch(_){attempts.set(ctx,Promise.resolve(false));}
    }
    return attempts;
  }
  return {track,resumeAll,blocked(){for(const ctx of contexts){if(ctx.state==='closed')contexts.delete(ctx);else if(ctx.state!=='running')return true;}return false;},states(){for(const ctx of contexts)if(ctx.state==='closed')contexts.delete(ctx);return [...contexts].map(ctx=>ctx.state);}};
})();

/* Accurate, bounded Web Audio transport with explicit browser sound recovery. */
window.PerfectoMusic = (() => {
  let context = null, prompt = null, promptCaption = null, unlockError = '';
  const players = new Map(), buffers = new Map();
  function disconnect(player) {
    if (!player.source) return;
    player.source.onended = null;
    try { player.source.stop(); } catch (_) {}
    player.source.disconnect(); player.source = null;
  }
  function needsUnlock(player) {
    return !player.paused && !['idle','error','ended'].includes(player.phase) &&
      (player.pending !== null || player.phase === 'playing') && context?.state !== 'running';
  }
  function refreshPrompt() {
    const blocked = [...players.values()].some(needsUnlock);
    if (typeof document === 'undefined') return;
    if (blocked && !prompt && document.body) {
      prompt = document.createElement('div'); prompt.id = 'perfecto-sound-unlock';
      prompt.setAttribute('role','dialog'); prompt.setAttribute('aria-label','음악 재생 켜기');
      prompt.style.cssText='position:fixed;left:50%;top:45%;transform:translate(-50%,-50%);z-index:2147483000;width:min(360px,82vw);padding:24px;border:1px solid #6fffe0;border-radius:18px;background:#111b2af2;color:#eef8ff;text-align:center;font:15px/1.7 sans-serif;box-shadow:0 12px 64px #000b';
      const button=document.createElement('button'); button.textContent='♪ 음악 켜기';
      button.style.cssText='width:100%;padding:14px;border:0;border-radius:10px;background:#68ffe0;color:#102832;font:bold 18px sans-serif;cursor:pointer';
      button.addEventListener('click',()=>{unlock();});
      promptCaption=document.createElement('div');promptCaption.style.cssText='margin-top:12px;color:#bdcadd';
      promptCaption.setAttribute('aria-live','polite');prompt.appendChild(button);prompt.appendChild(promptCaption);document.body.appendChild(prompt);
    }
    if (prompt) {
      prompt.style.display = blocked ? 'block' : 'none';
      promptCaption.textContent = unlockError ? '소리를 켜지 못했어요. 다시 눌러 주세요.' : '브라우저가 음악 재생을 기다리고 있어요. 눌러서 소리를 켜 주세요.';
    }
  }
  function startPending() {
    if (context?.state !== 'running') return;
    for (const player of players.values()) {
      if (player.pending !== null && player.buffer && !player.paused && player.phase !== 'playing') begin(player,player.pending);
    }
  }
  function audio() {
    if (context && context.state !== 'closed') return context;
    const previous=context;
    context=window.PerfectoAudioUnlock.track(new (window.AudioContext || window.webkitAudioContext)({latencyHint:'interactive'}));
    for (const player of players.values()) {
      if (player.phase === 'playing') {
        player.position=Math.max(player.offset,Math.min(player.buffer?.duration || 0,player.offset+((previous?.currentTime || 0)-player.when)*player.rate));
        player.pending=player.position;player.phase='ready';
      }
      disconnect(player);player.startSeq++;
      try { player.gain.disconnect(); } catch (_) {}
      player.gain=context.createGain();player.gain.gain.value=player.volume;player.gain.connect(context.destination);
    }
    context.addEventListener?.('statechange',()=>{
      if (context.state === 'running') {unlockError='';startPending();}
      refreshPrompt();
    });
    Promise.resolve().then(()=>{startPending();refreshPrompt();});
    return context;
  }
  function unlock() {
    let ctx;
    try {ctx=audio();} catch (_) {unlockError='unavailable';refreshPrompt();return Promise.resolve(false);}
    // Called directly by trusted DOM gestures; this resumes the separate Godot
    // effects context as well as music without changing either volume setting.
    const attempts=window.PerfectoAudioUnlock.resumeAll();
    const resumed=attempts.get(ctx) || Promise.resolve(ctx.state==='running');
    refreshPrompt();
    return resumed.then(ready=>{
      if(ctx!==context)return false;
      if(ready && ctx.state==='running'){unlockError='';startPending();refreshPrompt();return true;}
      unlockError='permission';refreshPrompt();return false;
    });
  }
  function create(id) {
    if (players.has(id)) return players.get(id);
    const ctx=audio(),gain=ctx.createGain();gain.connect(ctx.destination);
    const player={gain,volume:1,phase:'idle',source:null,buffer:null,seq:0,startSeq:0,rate:1,offset:0,when:0,position:0,pending:null,paused:false,error:''};
    players.set(id,player);return player;
  }
  function audibleTime() {
    const ctx=audio(),stamp=ctx.getOutputTimestamp?.();
    if(stamp && stamp.contextTime>0 && stamp.performanceTime>0)return Math.min(ctx.currentTime,stamp.contextTime+(performance.now()-stamp.performanceTime)/1000);
    return ctx.currentTime-(ctx.baseLatency || 0)-(ctx.outputLatency || 0);
  }
  function load(url) {
    if(buffers.has(url)){const value=buffers.get(url);buffers.delete(url);buffers.set(url,value);return value;}
    const abort=new AbortController(),timeout=setTimeout(()=>abort.abort(),30000);
    const promise=fetch(url,{signal:abort.signal}).then(response=>{
      if(!response.ok)throw new Error('Music download failed');return response.arrayBuffer();
    }).then(data=>audio().decodeAudioData(data)).catch(error=>{buffers.delete(url);throw error;}).finally(()=>clearTimeout(timeout));
    buffers.set(url,promise);while(buffers.size>1)buffers.delete(buffers.keys().next().value);return promise;
  }
  function begin(player,position) {
    const ctx=audio(),seq=player.seq,attempt=++player.startSeq;
    player.pending=position;
    const run=()=>{
      const ctx=audio();
      if(seq!==player.seq || attempt!==player.startSeq || !player.buffer || player.paused)return;
      if(ctx.state!=='running'){refreshPrompt();return;}
      disconnect(player);const source=ctx.createBufferSource();source.buffer=player.buffer;
      source.playbackRate.value=player.rate;source.connect(player.gain);
      player.source=source;player.offset=Math.min(player.buffer.duration,Math.max(0,position));
      player.position=player.offset;player.when=ctx.currentTime+.08;player.phase='playing';player.pending=null;
      source.onended=()=>{
        if(seq!==player.seq || player.source!==source || player.phase!=='playing')return;
        player.position=player.buffer.duration;player.endedAt=audibleTime();player.phase='ended';source.disconnect();player.source=null;refreshPrompt();
      };
      source.start(player.when,player.offset);refreshPrompt();
    };
    if(ctx.state==='running')run();
    else {
      refreshPrompt();
      // A blocked resume may stay pending until a real gesture. The visible prompt
      // and exported locked state remain usable instead of silently waiting READY.
      let resumed;try{resumed=ctx.resume();}catch(_){unlockError='permission';refreshPrompt();return;}
      Promise.resolve(resumed).then(run).catch(()=>{if(seq===player.seq && attempt===player.startSeq){unlockError='permission';refreshPrompt();}});
    }
  }
  function stop(id) {
    const player=players.get(id);if(!player)return;
    player.seq++;player.startSeq++;disconnect(player);player.buffer=null;player.phase='idle';player.position=0;player.pending=null;player.paused=false;player.error='';refreshPrompt();
  }
  for(const type of ['pointerdown','keydown','touchend'])window.addEventListener(type,()=>{
    if(!context || context.state!=='running' || window.PerfectoAudioUnlock.blocked())unlock();
  },{capture:true,passive:true});
  return {
    create,unlock,
    contextState(){return context?.state || 'uninitialized';},
    contextStates(){return window.PerfectoAudioUnlock.states();},
    prepare(id,url,rate){
      const player=create(id);stop(id);const seq=player.seq;player.rate=rate;player.phase='loading';
      load(url).then(buffer=>{
        if(seq!==player.seq)return;player.buffer=buffer;player.phase='ready';
        if(player.pending!==null && !player.paused)begin(player,player.pending);else refreshPrompt();
      }).catch(()=>{if(seq===player.seq){player.phase='error';player.error='Music could not be loaded';refreshPrompt();}});
    },
    start(id,at){const player=create(id);player.pending=at;if(player.phase==='ready' && !player.paused)begin(player,at);else refreshPrompt();},
    time(id){
      if(context?.state==='closed')audio();
      const player=players.get(id);if(!player)return 0;
      if(player.phase==='playing')return Math.max(player.offset,player.offset+(audibleTime()-player.when)*player.rate);
      if(player.phase==='ended')return player.position+Math.max(0,audibleTime()-player.endedAt)*player.rate;
      return player.position || player.pending || 0;
    },
    pause(id,value){
      const player=players.get(id);if(!player)return;player.paused=value;
      if(value && player.phase==='playing'){
        player.position=Math.max(player.offset,Math.min(player.buffer.duration,player.offset+(audio().currentTime-player.when)*player.rate));player.phase='paused';disconnect(player);
      }else if(!value && player.phase==='paused')begin(player,player.position);
      else if(!value && player.phase==='ready' && player.pending!==null)begin(player,player.pending);
      refreshPrompt();
    },
    volume(id,value){const player=create(id);player.volume=Math.max(0,Math.min(1,value));player.gain.gain.setTargetAtTime(player.volume,audio().currentTime,.01);},
    state(id){const player=players.get(id);return player ? (needsUnlock(player) ? 'locked' : player.phase) : 'idle';},
    error(id){return players.get(id)?.error || '';},
    stop,
    dispose(id){const player=players.get(id);if(!player)return;stop(id);player.gain.disconnect();players.delete(id);refreshPrompt();}
  };
})();
