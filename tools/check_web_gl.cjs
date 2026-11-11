// Exercise the actual exported bridge functions without needing a GPU.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync(process.argv[2]||'build/web/index.js','utf8');
function between(start,end){const a=source.indexOf(start),b=source.indexOf(end,a);assert(a>=0&&b>a,'Missing pinned bridge function');return source.slice(a,b)}
const state={GL:{counter:1,perfectoFreeIds:[],buffers:[],vaos:[],syncs:[],programs:[],recordError(){}},HEAP32:new Int32Array(16),GLctx:{createBuffer:()=>({}),createVertexArray:()=>({}),fenceSync:()=>({}),deleteBuffer(){},deleteVertexArray(){},deleteSync(){}}};
vm.createContext(state);
vm.runInContext('GL.getNewId='+between('getNewId:table=>','},genObject:').slice('getNewId:'.length)+'};',state);
vm.runInContext('GL.genObject='+between('genObject:(n,buffers,createFunction,objectTable)=>','},getSource:').slice('genObject:'.length)+'};',state);
for(const name of ['DeleteBuffers','DeleteVertexArrays','DeleteSync','FenceSync'])vm.runInContext(between('var _emscripten_gl'+name+'=',';var _gl'+name)+';',state);
const {GL,HEAP32}=state;const alive=new Set(),frames=[];
// A long-lived name in a different namespace must never be reused.
const program=GL.getNewId(GL.programs);GL.programs[program]={};alive.add(program);
for(let frame=0;frame<100000;frame++){
 const ids=[];
 GL.genObject(1,0,'createBuffer',GL.buffers);ids.push(HEAP32[0]);
 GL.genObject(1,0,'createVertexArray',GL.vaos);ids.push(HEAP32[0]);
 ids.push(state._emscripten_glFenceSync(0,0));
 for(const id of ids){assert(id>0&&!alive.has(id),'Duplicate live object name');alive.add(id)}
 frames.push(ids);
 if(frames.length>20){const [buffer,vao,sync]=frames.shift();
  HEAP32[0]=HEAP32[1]=buffer;state._emscripten_glDeleteBuffers(2,0);
  HEAP32[0]=HEAP32[1]=vao;state._emscripten_glDeleteVertexArrays(2,0);
  state._emscripten_glDeleteSync(sync);state._emscripten_glDeleteSync(sync);
  for(const id of [buffer,vao,sync])alive.delete(id);
 }
 assert(GL.counter<100,'Object name tables grew with elapsed frames');
}
assert(GL.buffers[0]===null&&GL.vaos[0]===null&&GL.syncs[0]===null,'Zero must stay reserved');
console.log('WEB_GL_NAMES_OK: 100000 frames, unique live names, bounded tables, duplicate deletion, zero reserved; high water '+GL.counter);
