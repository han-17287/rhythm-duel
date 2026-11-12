/* Preserve physical event time while Godot waits for its next render frame. */
window.PerfectoInput = (() => {
  const queues = Object.create(null), pointers = [];
  const keys = new Set(['Space', 'KeyD', 'KeyF', 'KeyJ', 'KeyK']);
  function age(stamp) { return stamp > 1e12 ? Date.now() - stamp : performance.now() - stamp; }
  function take(queue, pressed) {
    if (!queue) return 0;
    while (queue.length && age(queue[0].stamp) > 500) queue.shift();
    const index = queue.findIndex(item => item.pressed === pressed);
    if (index < 0) return 0;
    const item = queue[index]; queue.splice(0, index + 1);
    const lag = age(item.stamp); return lag >= 0 && lag <= 500 ? lag : 0;
  }
  for (const type of ['keydown', 'keyup']) window.addEventListener(type, event => {
    if (!keys.has(event.code) || event.repeat) return;
    const q = queues[event.code] || (queues[event.code] = []);
    q.push({pressed:type === 'keydown', stamp:event.timeStamp});
    if (q.length > 24) q.shift();
  }, true);
  for (const type of ['pointerdown', 'pointerup', 'pointercancel']) window.addEventListener(type, event => {
    pointers.push({pressed:type === 'pointerdown', stamp:event.timeStamp});
    if (pointers.length > 48) pointers.shift();
  }, {capture:true, passive:true});
  return {take:(code, pressed) => take(queues[code], pressed), takePointer:pressed => take(pointers, pressed), clearPointers:() => {pointers.length = 0;}};
})();
