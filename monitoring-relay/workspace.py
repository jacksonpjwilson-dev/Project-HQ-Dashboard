"""Single-user, authenticated, optimistic workspace synchronization."""
import json
import sqlite3
import uuid
from contextlib import closing

MAX_WORKSPACE = 20 * 1024 * 1024
class RevisionConflict(Exception): pass

def validate_workspace(value):
    if not isinstance(value, dict) or value.get('version') != 1 or not isinstance(value.get('projects'), list): raise ValueError('Invalid workspace envelope')
    if len(value['projects']) > 10000: raise ValueError('Too many projects')
    identifiers = set()
    def register(item):
        if not isinstance(item, dict): raise ValueError('Invalid record')
        key_value = item.get('id')
        if not isinstance(key_value,str):raise ValueError('Identifier required')
        key = str(uuid.UUID(key_value))
        if key in identifiers: raise ValueError('Duplicate identifiers')
        identifiers.add(key)
    def cyclic(graph):
        degrees={k:len(v) for k,v in graph.items()}; dependents={}
        for key,edges in graph.items():
            for edge in edges: dependents.setdefault(edge,[]).append(key)
        queue=[k for k,v in degrees.items() if v==0]; index=0
        while index<len(queue):
            key=queue[index];index+=1
            for nxt in dependents.get(key,[]):
                degrees[nxt]-=1
                if degrees[nxt]==0:queue.append(nxt)
        return len(queue)!=len(graph)
    statuses={'Backlog','Ready','In Progress','Blocked','Testing','Completed','Failed'}
    for project in value['projects']:
        register(project)
        if not isinstance(project.get('name'),str) or not project['name'].strip(): raise ValueError('Project name required')
        for field in ['tasks','services','events','incidents','milestones']:
            if not isinstance(project.get(field),list):raise ValueError('Missing collection')
            for record in project[field]:register(record)
        tasks={t['id']:t for t in project['tasks']}; milestones={m['id'] for m in project['milestones']}
        for task in tasks.values():
            if task.get('status') not in statuses or not isinstance(task.get('title'),str) or not task['title'].strip():raise ValueError('Invalid task')
            weight=task.get('weight')
            if isinstance(weight,bool) or not isinstance(weight,(int,float)) or not 0<weight<float('inf'):raise ValueError('Invalid weight')
            if not isinstance(task.get('dependencyIDs'),list) or any(i not in tasks for i in task['dependencyIDs']):raise ValueError('Invalid dependency')
            if task.get('parentID') is not None and task['parentID'] not in tasks:raise ValueError('Invalid parent')
            if task.get('milestoneID') is not None and task['milestoneID'] not in milestones:raise ValueError('Invalid milestone')
        if cyclic({k:v['dependencyIDs'] for k,v in tasks.items()}) or cyclic({k:[v['parentID']] if v.get('parentID') else [] for k,v in tasks.items()}):raise ValueError('Cyclic tasks')
    # Reject non-finite values even when the Python JSON decoder accepted them.
    json.dumps(value,allow_nan=False)

class WorkspaceStore:
    def __init__(self,path):
        self.path=path
        with closing(sqlite3.connect(path)) as db,db:
            db.execute('CREATE TABLE IF NOT EXISTS workspace (singleton INTEGER PRIMARY KEY CHECK(singleton=1), revision INTEGER NOT NULL, payload TEXT NOT NULL)')
    def fetch(self):
        with closing(sqlite3.connect(self.path,timeout=10)) as db:
            row=db.execute('SELECT revision,payload FROM workspace WHERE singleton=1').fetchone()
        return {'version':1,'revision':row[0] if row else 0,'backup':json.loads(row[1]) if row else None}
    def save(self,backup,expected):
        validate_workspace(backup)
        payload=json.dumps(backup,separators=(',',':'),allow_nan=False)
        if len(payload.encode())>MAX_WORKSPACE:raise ValueError('Workspace too large')
        with closing(sqlite3.connect(self.path,timeout=10)) as db,db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT revision FROM workspace WHERE singleton=1').fetchone()
            current=row[0] if row else 0
            if expected!=current:raise RevisionConflict()
            revision=current+1
            db.execute('INSERT INTO workspace VALUES(1,?,?) ON CONFLICT(singleton) DO UPDATE SET revision=excluded.revision,payload=excluded.payload',(revision,payload))
        return {'version':1,'revision':revision,'backup':backup}
