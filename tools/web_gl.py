"""Bound Godot 4.7.2's Emscripten GL object-name tables during long sessions.

The upstream bridge uses one ever-increasing counter for all object tables.
Godot creates/deletes buffers, VAOs, and syncs every frame; their null slots
therefore grow indefinitely. Recycle only names actually deleted by the bridge,
preserving uniqueness across all live namespaces and keeping 0 reserved.
This patch deliberately fails closed if the pinned template changes.
"""
from pathlib import Path

REPLACEMENTS = (
    ('var GL={counter:1,', 'var GL={counter:1,perfectoFreeIds:[],'),
    ('getNewId:table=>{var ret=GL.counter++;',
     'getNewId:table=>{var ret=GL.perfectoFreeIds.length?GL.perfectoFreeIds.pop():GL.counter++;'),
    ('buffer.name=0;GL.buffers[id]=null;',
     'buffer.name=0;GL.buffers[id]=null;GL.perfectoFreeIds.push(id);'),
    ('GLctx.deleteVertexArray(GL.vaos[id]);GL.vaos[id]=null',
     'if(GL.vaos[id]){GLctx.deleteVertexArray(GL.vaos[id]);GL.vaos[id]=null;GL.perfectoFreeIds.push(id)}'),
    ('sync.name=0;GL.syncs[id]=null',
     'sync.name=0;GL.syncs[id]=null;GL.perfectoFreeIds.push(id)'),
)

def patched_source(source: str) -> str:
    for before, after in REPLACEMENTS:
        if source.count(before) != 1:
            raise RuntimeError('Unexpected Godot Web bridge; review GL name recycling before exporting')
        source = source.replace(before, after, 1)
    return source

def patch(path: Path) -> None:
    path.write_text(patched_source(path.read_text()))
