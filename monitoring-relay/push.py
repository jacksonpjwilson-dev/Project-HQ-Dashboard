"""Optional APNs provider. Imported without dependencies until a configured send.

Apple keys and device registrations remain on the private relay. No success is
reported when APNs is unconfigured or rejects a token.
"""
import hashlib
import json
import os
import sqlite3
import time
import uuid
from contextlib import closing
from datetime import datetime
from zoneinfo import ZoneInfo

class APNsSender:
    def __init__(self,team,key_id,key_path,topic):self.team=team;self.key_id=key_id;self.key_path=key_path;self.topic=topic;self.jwt=None;self.issued=0
    @classmethod
    def configured(cls):
        values=[os.environ.get(k) for k in ['APNS_TEAM_ID','APNS_KEY_ID','APNS_KEY_PATH','APNS_TOPIC']]
        return cls(*values) if all(values) else None
    def send(self,device,payload,collapse_id):
        import jwt
        import httpx
        if time.time()-self.issued>3000 or not self.jwt:
            if os.stat(self.key_path).st_mode & 0o077:raise ValueError('APNs signing key must be accessible only to its owner')
            with open(self.key_path,'rb') as key:self.jwt=jwt.encode({'iss':self.team,'iat':int(time.time())},key.read(),algorithm='ES256',headers={'kid':self.key_id})
            self.issued=time.time()
        host='api.sandbox.push.apple.com' if device['environment']=='development' else 'api.push.apple.com'
        headers={'authorization':'bearer '+self.jwt,'apns-topic':self.topic,'apns-push-type':'alert','apns-priority':'10','apns-collapse-id':collapse_id,'apns-expiration':str(int(time.time()+3600))}
        with httpx.Client(http2=True,timeout=20,follow_redirects=False) as client:
            try: response=client.post(f'https://{host}/3/device/{device["token"]}',headers=headers,json=payload)
            except httpx.TransportError: raise OSError('APNs transport unavailable') from None
        if response.http_version!='HTTP/2':raise ValueError('APNs requires HTTP/2')
        if response.status_code==200:return 'delivered'
        if response.status_code==410:return 'invalid'
        if response.status_code in {429,500,503}:raise OSError('APNs temporarily unavailable')
        raise ValueError(f'APNs rejected notification (HTTP {response.status_code})')

class PushStore:
    def __init__(self,path):
        self.path=path
        with closing(sqlite3.connect(path)) as db,db:
            db.executescript('''CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS push_incidents(project TEXT, service TEXT, id TEXT NOT NULL, severity INTEGER NOT NULL, PRIMARY KEY(project,service));
                CREATE TABLE IF NOT EXISTS push_queue(id TEXT PRIMARY KEY, device TEXT NOT NULL, payload TEXT NOT NULL, expires REAL NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_attempt REAL NOT NULL DEFAULT 0);''')
    def register(self,value):
        if not isinstance(value,dict):raise ValueError('Invalid device')
        value['id']=str(uuid.UUID(value['id']))
        token=value.get('token','')
        if not isinstance(token,str) or len(token)<32 or len(token)>512 or any(c not in '0123456789abcdef' for c in token):raise ValueError('Invalid APNs token')
        if value.get('environment') not in {'development','production'}:raise ValueError('Invalid APNs environment')
        prefs=value.get('preferences',{})
        if prefs.get('threshold') not in {2,3,4} or not isinstance(prefs.get('enabled'),bool):raise ValueError('Invalid preferences')
        for key in ['quietStart','quietEnd']:
            if not isinstance(prefs.get(key),int) or not 0<=prefs[key]<=23:raise ValueError('Invalid quiet hours')
        ZoneInfo(value['timezone'])
        with closing(sqlite3.connect(self.path)) as db,db:db.execute('INSERT INTO devices VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',(value['id'],json.dumps(value)))
    def unregister(self,device_id):
        device_id=str(uuid.UUID(device_id))
        with closing(sqlite3.connect(self.path)) as db,db:
            db.execute('DELETE FROM devices WHERE id=?',(device_id,));db.execute('UPDATE push_queue SET state="revoked" WHERE device=? AND state="pending"',(device_id,))
    def observe(self,event,expiry,now):
        event_id,project,service,kind,state,explanation,observed,source=event
        if observed+expiry<now:return
        severity={'healthy':1,'unknown':0,'needsHelp':2,'error':3,'down':4}[state]
        with closing(sqlite3.connect(self.path)) as db,db:
            row=db.execute('SELECT id,severity FROM push_incidents WHERE project=? AND service=?',(project,service)).fetchone()
            if severity==0:return
            if severity==1:
                if row is None:return
                incident=row[0];category='recovery';db.execute('DELETE FROM push_incidents WHERE project=? AND service=?',(project,service))
            else:
                incident=row[0] if row else str(uuid.uuid4());category='build' if kind=='buildFailed' else 'milestone' if kind=='milestoneCompleted' else 'incident'
                db.execute('INSERT INTO push_incidents VALUES(?,?,?,?) ON CONFLICT(project,service) DO UPDATE SET severity=excluded.severity',(project,service,incident,severity))
            for device_id,data in db.execute('SELECT id,payload FROM devices').fetchall():
                device=json.loads(data);prefs=device['preferences'];hour=datetime.fromtimestamp(now,ZoneInfo(device['timezone'])).hour
                start,end=prefs['quietStart'],prefs['quietEnd'];quiet=prefs.get('quietEnabled') and (start==end or (start<=hour<end if start<end else hour>=start or hour<end))
                if not prefs['enabled'] or (category!='recovery' and severity<prefs['threshold']) or quiet:continue
                if category=='recovery' and not prefs.get('recovery',True):continue
                if category=='build' and not prefs.get('builds',True):continue
                if category=='milestone' and not prefs.get('milestones',True):continue
                key=hashlib.sha256(f'{device_id}:{incident}:{category}:{severity}'.encode()).hexdigest()
                # Payload intentionally contains no endpoint URLs or credentials.
                payload={'aps':{'alert':{'title':'Head Quarter · '+('Service recovered' if category=='recovery' else 'Monitoring alert'),'body':explanation},'sound':'default'},'projectID':project,'relayIncidentID':incident}
                db.execute('INSERT OR IGNORE INTO push_queue(id,device,payload,expires,state) VALUES(?,?,?,?,"pending")',(key,device_id,json.dumps(payload),observed+expiry))
    def deliver(self,sender,now):
        if sender is None:return
        with closing(sqlite3.connect(self.path)) as db:
            rows=db.execute('SELECT q.id,q.device,q.payload,q.expires,q.attempts,d.payload FROM push_queue q JOIN devices d ON q.device=d.id WHERE q.state="pending" AND q.next_attempt<=? ORDER BY q.rowid LIMIT 50',(now,)).fetchall()
        for key,device_id,payload,expires,attempts,device in rows:
            state='expired' if expires<now else None
            try:
                if state is None:state=sender.send(json.loads(device),json.loads(payload),key)
            except OSError:state='pending' if attempts<4 else 'failed'
            except Exception:state='failed'
            with closing(sqlite3.connect(self.path)) as db,db:
                db.execute('UPDATE push_queue SET state=?,attempts=?,next_attempt=? WHERE id=?',(state,attempts+1,now+min(900,30*2**attempts),key))
                if state=='invalid':db.execute('DELETE FROM devices WHERE id=?',(device_id,))
