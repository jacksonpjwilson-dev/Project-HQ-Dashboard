import copy,hashlib,hmac,http.client,importlib.util,json,sqlite3,sys,tempfile,threading,time,unittest,uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from relay import RelayServer,EventStore
from workspace import WorkspaceStore,RevisionConflict
from push import PushStore
spec=importlib.util.spec_from_file_location('codex_bridge',Path(__file__).resolve().parents[2]/'integrations/codex/bridge.py');bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
def fixture():
    return {'version':1,'exportedAt':'2026-11-12T12:00:00Z','projects':[{'id':str(uuid.uuid4()),'name':'Project','summary':'','icon':'building.2','phase':'Planning','priority':2,'order':0,'requireAllChecks':True,'createdAt':'2026-11-12T12:00:00Z','tasks':[],'services':[],'events':[],'incidents':[],'milestones':[]}]}
class SyncTests(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.store=WorkspaceStore(str(Path(self.tmp.name)/'db'))
    def test_initial_workspace_empty(self):self.assertEqual(self.store.fetch(),{'version':1,'revision':0,'backup':None})
    def test_cas_conflict_preserves_remote_data(self):
        original=fixture();self.store.save(original,0)
        changed=copy.deepcopy(original);changed['projects'][0]['name']='Stale overwrite'
        with self.assertRaises(RevisionConflict):self.store.save(changed,0)
        self.assertEqual(self.store.fetch()['backup'],original)
    def test_revision_survives_restart(self):self.store.save(fixture(),0);self.assertEqual(WorkspaceStore(self.store.path).fetch()['revision'],1)
    def test_invalid_workspace_rejected(self):
        with self.assertRaises(ValueError):self.store.save({'version':1,'projects':[{}]},0)
    def test_http_sync_requires_separate_token_and_revision(self):
        events=EventStore(self.store.path);server=RelayServer(('127.0.0.1',0),events,set(),'r'*32,'w'*32,sync_token='s'*32)
        threading.Thread(target=server.serve_forever,daemon=True).start();self.addCleanup(server.server_close);self.addCleanup(server.shutdown)
        c=http.client.HTTPConnection(*server.server_address);self.addCleanup(c.close)
        c.request('GET','/v1/workspace',headers={'Authorization':'Bearer '+'r'*32});r=c.getresponse();self.assertEqual(r.status,401);r.read()
        headers={'Authorization':'Bearer '+'s'*32,'Content-Type':'application/json','If-Match':'"0"'}
        c.request('PUT','/v1/workspace',json.dumps(fixture()),headers);r=c.getresponse();self.assertEqual(r.status,200);self.assertEqual(json.loads(r.read())['revision'],1)
        c.request('PUT','/v1/workspace',json.dumps(fixture()),headers);r=c.getresponse();self.assertEqual(r.status,409);r.read()
class CodexTests(unittest.TestCase):
    def setUp(self):self.project=str(uuid.uuid4());self.service=str(uuid.uuid4())
    def event(self,method,status='completed',thread='thread'):
        return {'method':method,'params':{'threadId':thread,'turn':{'id':'turn-1','status':status}}}
    def test_turn_complete_requires_verification_not_completed_task(self):
        event,status=bridge.event_from_notification(self.event('turn/completed'),self.project,self.service,'thread')
        self.assertEqual(status,'Testing');self.assertNotEqual(status,'Completed')
    def test_wrong_thread_is_not_reported(self):self.assertIsNone(bridge.event_from_notification(self.event('turn/started',thread='other'),self.project,self.service,'thread'))
    def test_failed_turn_is_error(self):self.assertEqual(bridge.event_from_notification(self.event('turn/completed','failed'),self.project,self.service,'thread')[0]['evidence']['state'],'error')
    def test_duplicate_notifications_have_stable_ids(self):
        a=bridge.event_from_notification(self.event('turn/started'),self.project,self.service,'thread')[0]
        b=bridge.event_from_notification(self.event('turn/started'),self.project,self.service,'thread')[0];self.assertEqual(a['eventID'],b['eventID'])
    def test_approval_wait_is_explicit(self):
        msg={'method':'thread/status/changed','params':{'threadId':'thread','status':{'type':'active','activeFlags':['waitingOnApproval']}}}
        self.assertEqual(bridge.event_from_notification(msg,self.project,self.service,'thread','turn-1')[1],'Blocked')
    def test_outbox_deduplicates_and_survives_restart(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=str(Path(tmp)/'outbox');b=bridge.Bridge('https://example.com',self.project,self.service,'thread','w'*32,path)
            b.observe(self.event('turn/started'));b.observe(self.event('turn/started'))
            with sqlite3.connect(path) as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM outbox').fetchone()[0],1)
    def test_insecure_relay_rejected(self):
        with self.assertRaises(ValueError):bridge.Bridge('http://example.com',self.project,self.service,'thread','w'*32,':memory:')
class PushTests(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.path=str(Path(self.tmp.name)/'db');self.store=PushStore(self.path);self.project=str(uuid.uuid4());self.service=str(uuid.uuid4())
    def device(self,quiet=False):return {'id':str(uuid.uuid4()),'token':'a'*64,'environment':'development','timezone':'America/Toronto','preferences':{'enabled':True,'threshold':2,'quietEnabled':quiet,'quietStart':0,'quietEnd':0,'recovery':True,'builds':True,'milestones':True}}
    def event(self,state):return(str(uuid.uuid4()),self.project,self.service,'healthCheckFailed' if state!='healthy' else 'serviceRecovered',state,'Observed response',time.time(),'Monitor')
    def count(self):
        with sqlite3.connect(self.path) as db:return db.execute('SELECT COUNT(*) FROM push_queue').fetchone()[0]
    def test_incident_deduplication_and_recovery(self):
        self.store.register(self.device());self.store.observe(self.event('down'),600,time.time());self.store.observe(self.event('down'),600,time.time());self.assertEqual(self.count(),1)
        self.store.observe(self.event('healthy'),600,time.time());self.assertEqual(self.count(),2)
    def test_unknown_does_not_create_or_resolve_incident(self):
        self.store.register(self.device());self.store.observe(self.event('unknown'),600,time.time());self.assertEqual(self.count(),0)
    def test_quiet_hours_suppress_delivery(self):self.store.register(self.device(True));self.store.observe(self.event('down'),600,time.time());self.assertEqual(self.count(),0)
    def test_stale_failure_not_pushed(self):
        self.store.register(self.device());event=list(self.event('down'));event[6]-=1000;self.store.observe(tuple(event),60,time.time());self.assertEqual(self.count(),0)
    def test_invalid_token_revoked_after_apns_rejection(self):
        self.store.register(self.device());self.store.observe(self.event('down'),600,time.time())
        class Fake:
            def send(self,*args):return 'invalid'
        self.store.deliver(Fake(),time.time())
        with sqlite3.connect(self.path) as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM devices').fetchone()[0],0)
    def test_unconfigured_sender_does_not_claim_delivery(self):
        self.store.register(self.device());self.store.observe(self.event('down'),600,time.time());self.store.deliver(None,time.time())
        with sqlite3.connect(self.path) as db:self.assertEqual(db.execute('SELECT state FROM push_queue').fetchone()[0],'pending')
