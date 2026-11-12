#!/usr/bin/env python3
"""Observe supported Codex app-server notifications; never scan private session files.

--proxy forwards stdio JSON-RPC to `codex app-server` for a real controlling client.
--stream consumes notifications copied by that client. --notify accepts the legacy
CLI agent-turn-complete JSON argument. No Codex/OpenAI credential is collected.
"""
import argparse
import hashlib
import hmac
import json
import os
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from contextlib import closing
from datetime import datetime,timezone

class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args):return None

def iso():return datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00','Z')
def event_from_notification(message,project,service,thread_id,current_turn=None,source='Codex app-server'):
    if not isinstance(message,dict) or 'id' in message:return None
    method=message.get('method'); params=message.get('params',{})
    if not isinstance(params,dict) or params.get('threadId')!=thread_id:return None
    turn=params.get('turn') or {}; turn_id=turn.get('id') or current_turn
    if not isinstance(turn_id,str) or not turn_id:return None
    if method=='turn/started':kind,state,status,detail='taskStarted','healthy','In Progress','Codex runner received a turn; development work is active'
    elif method=='turn/completed':
        outcome=turn.get('status')
        if outcome=='completed':kind,state,status,detail='manualReport','healthy','Testing','Codex turn completed; development work still requires verification'
        elif outcome=='failed':kind,state,status,detail='taskFailed','error','Failed','Codex turn failed; inspect the configured runner'
        elif outcome=='interrupted':kind,state,status,detail='approvalRequired','needsHelp','Blocked','Codex turn was interrupted; manual review required'
        else:return None
    elif method=='thread/status/changed' and 'waitingOnApproval' in (params.get('status') or {}).get('activeFlags',[]):
        kind,state,status,detail='approvalRequired','needsHelp','Blocked','Codex runner is waiting for approval'
    else:return None
    event_id=str(uuid.uuid5(uuid.NAMESPACE_URL,f'headquarter:codex:{thread_id}:{turn_id}:{kind}:{status}'))
    return {'version':1,'eventID':event_id,'projectID':project,'serviceID':service,'kind':kind,'evidence':{'state':state,'explanation':detail,'observedAt':iso(),'source':source}},status

class Bridge:
    def __init__(self,endpoint,project,service,thread_id,secret,outbox,task_id=None,sync_token=None):
        url=urllib.parse.urlsplit(endpoint)
        if url.scheme!='https' or not url.hostname or url.username or url.password:raise ValueError('Use an HTTPS relay URL without credentials')
        self.endpoint=endpoint.rstrip('/');self.project=str(uuid.UUID(project));self.service=str(uuid.UUID(service));self.thread_id=thread_id
        if not thread_id or len(secret)<32:raise ValueError('Explicit Codex thread ID and a relay write secret are required')
        self.secret=secret;self.outbox=outbox;self.task_id=task_id;self.sync_token=sync_token;self.current_turn=None;self.source='Codex app-server' 
        if task_id:uuid.UUID(task_id)
        if bool(task_id)!=bool(sync_token):raise ValueError('Task synchronization requires both HQ_TASK_ID and HQ_SYNC_TOKEN')
        with closing(sqlite3.connect(outbox)) as db,db:db.execute('CREATE TABLE IF NOT EXISTS outbox (id TEXT PRIMARY KEY, payload TEXT NOT NULL, task_status TEXT NOT NULL, state TEXT NOT NULL DEFAULT "pending")')
    def observe(self,message):
        mapped=event_from_notification(message,self.project,self.service,self.thread_id,self.current_turn,self.source)
        if not mapped:return False
        event,status=mapped
        if message.get('method')=='turn/started':self.current_turn=message['params']['turn']['id']
        with closing(sqlite3.connect(self.outbox)) as db,db:db.execute('INSERT OR IGNORE INTO outbox(id,payload,task_status) VALUES(?,?,?)',(event['eventID'],json.dumps(event,separators=(',',':')),status))
        return True
    def request(self,path,method='GET',payload=None,headers=None):
        data=None if payload is None else json.dumps(payload,separators=(',',':')).encode()
        request=urllib.request.Request(self.endpoint+path,data=data,method=method,headers=headers or {})
        if data is not None:request.add_header('Content-Type','application/json')
        with urllib.request.build_opener(NoRedirects()).open(request,timeout=30) as response:return json.load(response)
    def sync_task(self,event,status):
        if not self.task_id:return
        for attempt in range(3):
            remote=self.request('/v1/workspace',headers={'Authorization':'Bearer '+self.sync_token})
            backup=remote.get('backup')
            if not backup:raise ValueError('Synchronize the native workspace before enabling task updates')
            project=next((p for p in backup['projects'] if p['id'].lower()==self.project.lower()),None)
            if project is None:raise ValueError('Configured project is not in the remote workspace')
            task=next((t for t in project['tasks'] if t['id'].lower()==self.task_id.lower()),None)
            if task is None:raise ValueError('Configured task is not in the remote workspace')
            if any(e['id']==event['eventID'] for e in project['events']):return
            dependencies={t['id']:t for t in project['tasks']}
            if status in {'In Progress','Testing'} and any(dependencies.get(i,{}).get('status')!='Completed' for i in task.get('dependencyIDs',[])):status='Blocked'
            modified=task.get('modifiedAt') or task.get('completedAt')
            if modified and datetime.fromisoformat(modified.replace('Z','+00:00')) > datetime.fromisoformat(event['evidence']['observedAt'].replace('Z','+00:00')):return
            task['status']=status;task['assignee']='Codex';task['completedAt']=None;task['modifiedAt']=event['evidence']['observedAt']
            if status in {'Failed','Blocked'}:task['blocker']=task.get('blocker') or event['evidence']['explanation']
            project['events'].append({'id':event['eventID'],'kind':event['kind'],'message':event['evidence']['explanation'],'source':event['evidence']['source'],'timestamp':event['evidence']['observedAt'],'serviceID':self.service})
            backup['exportedAt']=iso()
            try:
                self.request('/v1/workspace','PUT',backup,{'Authorization':'Bearer '+self.sync_token,'If-Match':f'"{remote["revision"]}"'});return
            except urllib.error.HTTPError as error:
                if error.code!=409:raise
        raise ValueError('Remote task changed repeatedly; retry the outbox later')
    def flush(self):
        with closing(sqlite3.connect(self.outbox)) as db:rows=db.execute('SELECT id,payload,task_status FROM outbox WHERE state="pending" ORDER BY rowid').fetchall()
        for event_id,payload,status in rows:
            event=json.loads(payload)
            observed=datetime.fromisoformat(event['evidence']['observedAt'].replace('Z','+00:00')).timestamp()
            if time.time()-observed>86400:
                with closing(sqlite3.connect(self.outbox)) as db,db:db.execute('UPDATE outbox SET state="expired" WHERE id=?',(event_id,))
                continue
            body=payload.encode(); sent=str(int(time.time())); signature='sha256='+hmac.new(self.secret.encode(),sent.encode()+b'.'+body,hashlib.sha256).hexdigest()
            self.request('/v1/events','POST',event,{'X-HQ-Timestamp':sent,'X-HQ-Signature':signature})
            self.sync_task(event,status)
            with closing(sqlite3.connect(self.outbox)) as db,db:db.execute('UPDATE outbox SET state="sent" WHERE id=?',(event_id,))

def main():
    parser=argparse.ArgumentParser(description=__doc__); group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--stream',action='store_true');group.add_argument('--proxy',action='store_true');group.add_argument('--flush',action='store_true');group.add_argument('--notify')
    parser.add_argument('--outbox',default='codex-outbox.sqlite3');args=parser.parse_args()
    bridge=Bridge(os.environ['HQ_RELAY_URL'],os.environ['HQ_PROJECT_ID'],os.environ['HQ_SERVICE_ID'],os.environ['HQ_CODEX_THREAD_ID'],os.environ['HQ_WRITE_SECRET'],args.outbox,os.environ.get('HQ_TASK_ID'),os.environ.get('HQ_SYNC_TOKEN'))
    wake=threading.Event();stop=threading.Event()
    def flush_worker():
        while not stop.is_set():
            wake.wait(15);wake.clear()
            try:bridge.flush()
            except Exception:print('Head Quarter: delivery pending; credentials and payload were not logged.',file=sys.stderr)
    threading.Thread(target=flush_worker,daemon=True).start()
    def observe(line):
        try:
            if bridge.observe(json.loads(line)):wake.set()
        except Exception:print('Head Quarter: event retained locally or rejected; inspect configuration and retry --flush. No payload or credential was logged.',file=sys.stderr)
    if args.flush:bridge.flush();return
    if args.notify:
        bridge.source='Codex CLI notify'
        message=json.loads(args.notify)
        if message.get('type')=='agent-turn-complete':observe(json.dumps({'method':'turn/completed','params':{'threadId':message.get('thread-id'),'turn':{'id':message.get('turn-id'),'status':'completed'}}}))
        bridge.flush();return
    if args.proxy:
        proc=subprocess.Popen(['codex','app-server'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1)
        def forward():
            try:
                for line in sys.stdin:proc.stdin.write(line);proc.stdin.flush()
            except BrokenPipeError:pass
            finally:proc.stdin.close()
        threading.Thread(target=forward,daemon=True).start()
        for line in proc.stdout:
            sys.stdout.write(line);sys.stdout.flush();observe(line)
        raise SystemExit(proc.wait())
    for line in sys.stdin:observe(line)

if __name__=='__main__':main()
