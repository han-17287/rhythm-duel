"""Bounded asset cache and conditional GET for the exported Web game."""
import asyncio
from collections import OrderedDict
cache=OrderedDict()
cache_bytes=0
cache_limit=64*1024*1024
lock=None
loop=None
async def read_asset(path,stat):
    global cache_bytes,lock,loop
    current=asyncio.get_running_loop()
    if loop is not current:loop=current;lock=asyncio.Lock()
    signature=(stat.st_mtime_ns,stat.st_size)
    async with lock:
        existing=cache.get(path)
        if existing and existing[0]==signature:
            cache.move_to_end(path);return existing[1]
        if existing:
            cache_bytes-=len(existing[1]);cache.pop(path)
        body=await asyncio.to_thread(path.read_bytes)
        if len(body)<=cache_limit:
            while cache and cache_bytes+len(body)>cache_limit:
                _,(_,old)=cache.popitem(last=False);cache_bytes-=len(old)
            cache[path]=(signature,body);cache_bytes+=len(body)
        return body


def accepts_gzip(header):
    preferences={}
    for part in header.split(','):
        fields=[x.strip() for x in part.split(';')]
        quality=1.0
        for field in fields[1:]:
            if field.startswith('q='):
                try:quality=float(field[2:])
                except ValueError:quality=0
        preferences[fields[0].lower()]=quality
    return preferences.get('gzip',preferences.get('*',0))>0
