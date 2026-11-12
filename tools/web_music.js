/* Accurate, bounded Web Audio music transport. Godot continues to own gameplay. */
window.PerfectoMusic = (() => {
  let context = null;
  const players = new Map();
  const buffers = new Map();
  const audio = () => context || (context = new (window.AudioContext || window.webkitAudioContext)({latencyHint:'interactive'}));
  function create(id) {
    if (players.has(id)) return players.get(id);
    const gain = audio().createGain(); gain.connect(audio().destination);
    const player = {gain, phase:'idle', source:null, buffer:null, seq:0, rate:1, offset:0, when:0, position:0, pending:null, paused:false, error:''};
    players.set(id, player); return player;
  }
  function audibleTime() {
    const ctx = audio();
    const stamp = ctx.getOutputTimestamp?.();
    if (stamp && stamp.contextTime > 0 && stamp.performanceTime > 0) {
      return Math.min(ctx.currentTime, stamp.contextTime + (performance.now() - stamp.performanceTime) / 1000);
    }
    return ctx.currentTime - (ctx.baseLatency || 0) - (ctx.outputLatency || 0);
  }
  function disconnect(player) {
    if (!player.source) return;
    player.source.onended = null;
    try { player.source.stop(); } catch (_) {}
    player.source.disconnect(); player.source = null;
  }
  function load(url) {
    if (buffers.has(url)) {
      const value = buffers.get(url); buffers.delete(url); buffers.set(url, value); return value;
    }
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), 30000);
    const promise = fetch(url, {signal:abort.signal}).then(response => {
      if (!response.ok) throw new Error('Music download failed');
      return response.arrayBuffer();
    }).then(data => audio().decodeAudioData(data)).catch(error => { buffers.delete(url); throw error; }).finally(() => clearTimeout(timeout));
    buffers.set(url, promise);
    while (buffers.size > 1) buffers.delete(buffers.keys().next().value);
    return promise;
  }
  function begin(player, position) {
    const seq = player.seq;
    const run = () => {
      if (seq !== player.seq || !player.buffer || player.paused) return;
      disconnect(player);
      const source = audio().createBufferSource(); source.buffer = player.buffer;
      source.playbackRate.value = player.rate; source.connect(player.gain);
      player.source = source; player.offset = Math.min(player.buffer.duration, Math.max(0, position));
      player.position = player.offset; player.when = audio().currentTime + .08; player.phase = 'playing'; player.pending = null;
      source.onended = () => {
        if (seq !== player.seq || player.source !== source || player.phase !== 'playing') return;
        player.position = player.buffer.duration; player.endedAt = audibleTime(); player.phase = 'ended';
        source.disconnect(); player.source = null;
      };
      source.start(player.when, player.offset);
    };
    if (audio().state === 'running') run();
    else audio().resume().then(run).catch(() => { player.phase = 'error'; player.error = 'Audio permission required'; });
  }
  function stop(id) {
    const player = players.get(id); if (!player) return;
    player.seq++; disconnect(player); player.buffer = null; player.phase = 'idle'; player.position = 0; player.pending = null; player.paused = false; player.error = '';
  }
  for (const type of ['pointerdown', 'keydown']) window.addEventListener(type, () => {
    if (context?.state === 'suspended') context.resume().catch(() => {});
  }, {capture:true, passive:true});
  return {
    create,
    prepare(id, url, rate) {
      const player = create(id); stop(id); const seq = player.seq;
      player.rate = rate; player.phase = 'loading';
      load(url).then(buffer => {
        if (seq !== player.seq) return;
        player.buffer = buffer; player.phase = 'ready';
        if (player.pending !== null && !player.paused) begin(player, player.pending);
      }).catch(() => { if (seq === player.seq) { player.phase = 'error'; player.error = 'Music could not be loaded'; } });
    },
    start(id, at) {
      const player = create(id); player.pending = at;
      if (player.phase === 'ready' && !player.paused) begin(player, at);
    },
    time(id) {
      const player = players.get(id); if (!player) return 0;
      if (player.phase === 'playing') return Math.max(player.offset, player.offset + (audibleTime() - player.when) * player.rate);
      if (player.phase === 'ended') return player.position + Math.max(0, audibleTime() - player.endedAt) * player.rate;
      return player.position || player.pending || 0;
    },
    pause(id, value) {
      const player = players.get(id); if (!player) return;
      player.paused = value;
      if (value && player.phase === 'playing') {
        player.position = Math.max(player.offset, Math.min(player.buffer.duration, player.offset + (audio().currentTime - player.when) * player.rate));
        player.phase = 'paused'; disconnect(player);
      } else if (!value && player.phase === 'paused') begin(player, player.position);
      else if (!value && player.phase === 'ready' && player.pending !== null) begin(player, player.pending);
    },
    volume(id, value) {
      const player = create(id); player.gain.gain.setTargetAtTime(Math.max(0, Math.min(1, value)), audio().currentTime, .01);
    },
    state(id) { return players.get(id)?.phase || 'idle'; },
    error(id) { return players.get(id)?.error || ''; },
    stop,
    dispose(id) { const player = players.get(id); if (!player) return; stop(id); player.gain.disconnect(); players.delete(id); },
  };
})();
