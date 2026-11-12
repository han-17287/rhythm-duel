const vm=require('vm'),fs=require('fs'),assert=require('assert');
let wall=0,decodes=0,active=0,created=0;
class Context {
 constructor(){created++;this.state='running';this.currentTime=0;this.baseLatency=.005;this.outputLatency=.015;this.destination={};Context.instance=this;}
 createGain(){return{gain:{setTargetAtTime(v){this.value=v}},connect(){},disconnect(){}}}
 createBufferSource(){let connected=false;return{buffer:null,playbackRate:{value:1},connect(){connected=true;active++},disconnect(){if(connected){active--;connected=false}},start(when,offset){this.when=when;this.offset=offset},stop(){}}}
 decodeAudioData(){decodes++;return Promise.resolve({duration:100})}
 resume(){this.state='running';return Promise.resolve()}
 getOutputTimestamp(){return{contextTime:Math.max(0,this.currentTime-.02),performanceTime:wall}}
}
const sandbox={window:{AudioContext:Context,addEventListener(){}},performance:{now:()=>wall},fetch:url=>url.includes('missing')?Promise.resolve({ok:false}):Promise.resolve({ok:true,arrayBuffer:()=>Promise.resolve(new ArrayBuffer(8))}),Map,Math,Error,AbortController,setTimeout,clearTimeout};
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
 music.dispose(1);console.log('WEB_MUSIC_OK audible-clock alignment, pause/resume, half-speed seek, gain, errors, source cleanup, shared context');
})().catch(e=>{console.error(e);process.exit(1)});
