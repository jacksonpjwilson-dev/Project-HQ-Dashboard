import copy,datetime,importlib.util,json,os,sqlite3,ssl,subprocess,sys,tempfile,threading,time,unittest,urllib.request,uuid
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from relay import RelayServer,EventStore
from push import APNsSender
from test_integrations import fixture
spec=importlib.util.spec_from_file_location('codex_transport',Path(__file__).resolve().parents[2]/'integrations/codex/bridge.py');bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
class CodexWireTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.certdir=tempfile.TemporaryDirectory();d=Path(cls.certdir.name)
        (d/'openssl.cnf').write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=localhost\n[ext]\nsubjectAltName=DNS:localhost\nbasicConstraints=critical,CA:TRUE\n')
        subprocess.run(['openssl','req','-x509','-nodes','-newkey','rsa:2048','-days','1','-keyout',str(d/'key.pem'),'-out',str(d/'cert.pem'),'-config',str(d/'openssl.cnf')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    @classmethod
    def tearDownClass(cls):cls.certdir.cleanup()
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.project,self.service,self.task=[str(uuid.uuid4()) for _ in range(3)]
        store=EventStore(str(Path(self.tmp.name)/'db'))
        self.server=RelayServer(('localhost',0),store,{(self.project,self.service)},'r'*32,'w'*32,sync_token='s'*32)
        ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.load_cert_chain(str(Path(self.certdir.name)/'cert.pem'),str(Path(self.certdir.name)/'key.pem'))
        self.server.socket=ctx.wrap_socket(self.server.socket,server_side=True)
        threading.Thread(target=self.server.serve_forever,daemon=True).start();self.addCleanup(self.server.server_close);self.addCleanup(self.server.shutdown)
        backup=fixture();p=backup['projects'][0];p['id']=self.project
        p['tasks']=[{'id':self.task,'title':'Preserve task title','notes':'Preserve notes','status':'Backlog','priority':3,'weight':2,'assignee':'','blocker':'','createdAt':'2026-01-01T00:00:00Z','dependencyIDs':[]}]
        self.server.workspace.save(backup,0)
        trusted=ssl.create_default_context(cafile=str(Path(self.certdir.name)/'cert.pem'))
        opener=urllib.request.build_opener(bridge.NoRedirects(),urllib.request.HTTPSHandler(context=trusted))
        self.adapter=bridge.Bridge(f'https://localhost:{self.server.server_port}',self.project,self.service,'thread','w'*32,str(Path(self.tmp.name)/'outbox'),self.task,'s'*32,opener=opener)
    def test_real_tls_signed_ingestion_and_remote_task_transition(self):
        for method,status in [('turn/started','inProgress'),('turn/completed','completed')]:
            self.adapter.observe({'method':method,'params':{'threadId':'thread','turn':{'id':'turn','status':status}}});self.adapter.flush()
        remote=self.server.workspace.fetch()['backup']['projects'][0]
        self.assertEqual(remote['tasks'][0]['status'],'Testing');self.assertEqual(remote['tasks'][0]['title'],'Preserve task title');self.assertEqual(remote['tasks'][0]['notes'],'Preserve notes')
        self.assertEqual(len(remote['events']),2)
        with sqlite3.connect(self.adapter.outbox) as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM outbox WHERE state="sent"').fetchone()[0],2)
    def test_completed_task_is_never_reopened_by_the_agent(self):
        value=self.server.workspace.fetch();value['backup']['projects'][0]['tasks'][0]['status']='Completed'
        self.server.workspace.save(value['backup'],value['revision'])
        self.adapter.observe({'method':'turn/started','params':{'threadId':'thread','turn':{'id':'turn','status':'inProgress'}}});self.adapter.flush()
        self.assertEqual(self.server.workspace.fetch()['backup']['projects'][0]['tasks'][0]['status'],'Completed')
    def test_newer_human_completion_survives_delayed_codex_event(self):
        self.adapter.observe({'method':'turn/completed','params':{'threadId':'thread','turn':{'id':'turn','status':'completed'}}})
        value=self.server.workspace.fetch();task=value['backup']['projects'][0]['tasks'][0];task['status']='Completed'
        task['modifiedAt']=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(seconds=60)).isoformat().replace('+00:00','Z')
        self.server.workspace.save(value['backup'],value['revision']);self.adapter.flush()
        self.assertEqual(self.server.workspace.fetch()['backup']['projects'][0]['tasks'][0]['status'],'Completed')

class APNsSigningTests(unittest.TestCase):
    def test_real_es256_signing_with_mocked_http2_only(self):
        try:
            import jwt,httpx
            from cryptography.hazmat.primitives.asymmetric import ec
            from cryptography.hazmat.primitives import serialization
        except ImportError:self.skipTest('Optional APNs dependencies are not installed')
        private=ec.generate_private_key(ec.SECP256R1());captured={}
        class Client:
            def __init__(self,**kwargs):captured['configuration']=kwargs
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def post(self,url,**kwargs):captured.update(kwargs);captured['url']=url;return type('Response',(),{'status_code':200,'http_version':'HTTP/2'})()
        with tempfile.TemporaryDirectory() as tmp:
            key=Path(tmp)/'key.p8';key.write_bytes(private.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()));key.chmod(0o600)
            sender=APNsSender('TEAM','KEY',str(key),'com.headquarter.app')
            with patch('httpx.Client',Client):self.assertEqual(sender.send({'token':'a'*64,'environment':'development'},{'aps':{'alert':'Test fixture'}},'incident'),'delivered')
            claims=jwt.decode(captured['headers']['authorization'][7:],private.public_key(),algorithms=['ES256'])
            self.assertEqual(claims['iss'],'TEAM');self.assertTrue(captured['configuration']['http2']);self.assertIn('api.sandbox.push.apple.com',captured['url'])

class FeedCriteriaTests(unittest.TestCase):
    def check(self,body):
        from relay import check_target
        class Response:
            status=200
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def read(self,*args):return body
        class Opener:
            def open(self,*args,**kwargs):return Response()
        with patch('relay.urllib.request.build_opener',return_value=Opener()):
            return check_target({'endpoint':'https://example.com/feed','timestampPath':'meta.updatedAt','evidenceExpirySeconds':300},1800000000)[0]
    def test_stale_feed_is_unknown_despite_http_200(self):self.assertEqual(self.check(b'{"meta":{"updatedAt":1799990000}}'),'unknown')
    def test_fresh_feed_is_healthy(self):self.assertEqual(self.check(b'{"meta":{"updatedAt":1800000000}}'),'healthy')
    def test_missing_timestamp_requires_help(self):self.assertEqual(self.check(b'{}'),'needsHelp')
    def test_future_timestamp_is_unknown(self):self.assertEqual(self.check(b'{"meta":{"updatedAt":1800010000}}'),'unknown')
    def test_nonfinite_timestamp_cannot_be_healthy(self):self.assertEqual(self.check(b'{"meta":{"updatedAt":NaN}}'),'needsHelp')
    def test_boolean_timestamp_cannot_be_healthy(self):self.assertEqual(self.check(b'{"meta":{"updatedAt":true}}'),'needsHelp')
