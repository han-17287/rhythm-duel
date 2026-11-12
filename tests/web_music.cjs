const vm=require('vm'),fs=require('fs'),assert=require('assert');
let wall=0,decodes=0,active=0,created=0,resumeMode='ok',initialState='running';const resumeWaiters=[],gestures={};
const document={nodes:[],body:{appendChild(){}},createElement(){const node={style:{},children:[],events:{},setAttribute(){},appendChild(child){this.children.push(child)},addEventListener(type,fn){this.events[type]=fn}};this.nodes.push(node);return node;}};
class Context {
 constructor(){created++;this.state=initialState;this.events={};this.currentTime=0;this.baseLatency=.005;this.outputLatency=.015;this.destination={};Context.instance=this;}
 createGain(){return{gain:{setTargetAtTime(v){this.value=v}},connect(){},disconnect(){}}}
 createBufferSource(){let connected=false;return{buffer:null,playbackRate:{value:1},connect(){connected=true;active++},disconnect(){if(connected){active--;connected=false}},start(when,offset){this.when=when;this.offset=offset},stop(){}}}
 decodeAudioData(){decodes++;return Promise.resolve({duration:100})}
 addEventListener(type,fn){this.events[type]=fn}
 emit(){this.events.statechange?.()}
 resume(){if(resumeMode==='pending')return new Promise(resolve=>resumeWaiters.push(resolve));if(resumeMode==='reject')return Promise.reject(Error('gesture required'));this.state='running';this.emit();for(const resolve of resumeWaiters.splice(0))resolve();return Promise.resolve()}
 getOutputTimestamp(){return{contextTime:Math.max(0,this.currentTime-.02),performanceTime:wall}}
}
const sandbox={window:{AudioContext:Context,addEventListener(type,fn){gestures[type]=fn}},document,performance:{now:()=>wall},fetch:url=>url.includes('missing')?Promise.resolve({ok:false}):Promise.resolve({ok:true,arrayBuffer:()=>Promise.resolve(new ArrayBuffer(8))}),Map,Math,Error,AbortController,setTimeout,clearTimeout};
vm.createContext(sandbox);vm.runInContext(fs.readFileSync('tools/web_music.js','utf8'),sandbox);const music=sandbox.window.PerfectoMusic;
const flush=async()=>{for(let i=0;i<12;i++)await Promise.resolve()};const advance=value=>{Context.instance.currentTime=value;wall=value*1000};
(async()=>{
 music.create(1);music.prepare(1,'audio/music/calibration.ogg',1);music.start(1,0);music.pause(1,true);await flush();assert.equal(music.state(1),'ready');assert.equal(active,0);music.pause(1,false);assert.equal(music.state(1),'playing');music.stop(1);music.prepare(1,'audio/ranker/r01.ogg',1);music.start(1,0);await flush();assert.equal(music.state(1),'playing');
 advance(.60);assert(Math.abs(music.time(1)-.5)<1e-9,'Use audible hardware time, not a render-frame timer');
 music.pause(1,true);const paused=music.time(1);advance(4);assert.equal(music.time(1),paused);music.pause(1,false);advance(4.60);assert(Math.abs(music.time(1)-(paused+.5))<1e-9);
 music.prepare(1,'audio/ranker/r01.ogg',.5);music.start(1,20);await flush();advance(5.20);assert(Math.abs(music.time(1)-20.25)<1e-9,'Half-speed seek must scale elapsed time without scaling the seek offset');
 music.volume(1,.3);assert.equal(music.create(1).gain.gain.value,.3);
 music.prepare(1,'audio/music/calibration.ogg',1);music.start(1,0);await flush();assert.equal(music.state(1),'playing');
 music.prepare(1,'audio/music/missing.ogg',1);await flush();assert.equal(music.state(1),'error');assert(music.error(1));
 music.stop(1);assert.equal(music.create(1).buffer,null,'Stopped tracks release decoded player memory');assert.equal(music.state(1),'idle');assert.equal(active,0);
 for(let i=2;i<18;i++){music.create(i);music.prepare(i,'audio/ranker/r'+i+'.ogg',1);music.start(i,0);await flush();music.dispose(i)}
 const beforeReload=decodes;music.prepare(1,'audio/ranker/r2.ogg',1);await flush();assert.equal(decodes,beforeReload+1,'Old full-song buffers are evicted from the one-track cache');music.stop(1);
 assert.equal(active,0);assert.equal(created,1,'One shared context across all tracks and scenes');
 music.dispose(1);
 // A denied resume stays recoverable and visible, rather than waiting READY silently.
 Context.instance.state='suspended';resumeMode='pending';music.prepare(40,'audio/ranker/locked.ogg',1);music.start(40,0);await flush();
 assert.equal(music.state(40),'locked');assert.equal(music.error(40),'');assert.equal(music.time(40),0);assert.equal(active,0);
 const prompt=document.nodes.find(node=>node.id==='perfecto-sound-unlock');assert(prompt);assert.equal(prompt.style.display,'block');
 wall+=5000;assert.equal(music.time(40),0,'A locked song must not advance its gameplay clock');
 resumeMode='ok';prompt.children[0].events.click();await flush();assert.equal(music.state(40),'playing');assert.equal(prompt.style.display,'none');assert.equal(active,1);
 Context.instance.state='interrupted';Context.instance.emit();assert.equal(music.state(40),'locked');gestures.pointerdown();await flush();assert.equal(music.state(40),'playing');assert.equal(active,1,'Interruption recovery must reuse the current source');
 music.stop(40);Context.instance.state='suspended';resumeMode='reject';music.prepare(40,'audio/ranker/rejected.ogg',1);music.start(40,0);await flush();
 assert.equal(music.state(40),'locked');assert.equal(music.error(40),'');assert.equal(await music.unlock(),false);resumeMode='ok';assert.equal(await music.unlock(),true);await flush();assert.equal(music.state(40),'playing');
 music.volume(40,.27);Context.instance.currentTime+=1;const beforeClose=music.time(40);Context.instance.state='closed';Context.instance.emit();initialState='suspended';
 assert.equal(await music.unlock(),true);await flush();assert.equal(created,2);assert.equal(music.state(40),'playing');assert.equal(active,1);assert.equal(music.create(40).gain.gain.value,.27);assert(music.time(40)>=beforeClose,'Closed context recreation preserves song position');
 music.stop(40);Context.instance.state='suspended';resumeMode='pending';music.prepare(40,'audio/ranker/stopped.ogg',1);music.start(40,0);await flush();assert.equal(music.state(40),'locked');music.stop(40);resumeMode='ok';await music.unlock();await flush();assert.equal(music.state(40),'idle');assert.equal(active,0,'A late resume may not resurrect a stopped song');music.dispose(40);
 // Engine-created contexts keep native constructor behavior and share gesture recovery.
 const musicContext=Context.instance,Wrapped=sandbox.window.AudioContext;initialState='suspended';const engineContext=new Wrapped();
 assert(engineContext instanceof Context);assert(engineContext instanceof Wrapped);assert.equal(Wrapped.prototype,Context.prototype);
 musicContext.state='suspended';engineContext.state='interrupted';resumeMode='ok';await music.unlock();await flush();
 assert.equal(musicContext.state,'running');assert.equal(engineContext.state,'running');assert.equal(music.contextStates().length,2);
 engineContext.state='closed';engineContext.emit();assert.equal(music.contextStates().length,1,'Closed SFX contexts are removed from the registry');
 console.log('WEB_MUSIC_OK audible-clock alignment, pause/resume, half-speed seek, gain, errors, source cleanup, shared context, visible unlock, interrupted/closed/rejected/pending resume recovery, native-compatible multi-context SFX/music unlock');
})().catch(e=>{console.error(e);process.exit(1)});
