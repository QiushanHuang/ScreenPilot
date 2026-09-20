#!/usr/bin/env python3
"""Local synthetic bridge; never calls a display API and uses a public test key."""
from http.server import HTTPServer,BaseHTTPRequestHandler
import hashlib,hmac,subprocess,threading,os,time,json
host=subprocess.check_output(['ipconfig','getifaddr','en0'],text=True).strip()
key=bytes(range(32)); nonces=set(); results=[]
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def handle_request(self):
  stamp=self.headers.get('X-SP-Time',''); nonce=self.headers.get('X-SP-Nonce',''); signature=self.headers.get('X-SP-Signature','')
  canonical=f'{stamp}\n{nonce}\n{self.command}\n{self.path}'.encode()
  valid=hmac.compare_digest(hmac.new(key,canonical,hashlib.sha256).hexdigest(),signature) and nonce not in nonces and abs(int(stamp)-int(time.time()))<=60 and self.headers.get('Content-Length')=='0'
  if valid:nonces.add(nonce)
  status=200 if valid else 403
  body=(b'{"ok":true,"ready":true}' if self.path=='/health' else b'{"ok":true,"sent":true}') if valid else b'{"ok":false,"error":"authentication_failed"}'
  if valid and self.path=='/usb-arrival':body=b'{"ok":true,"ready":true,"arrivalID":"test-event","arrivalTime":123}'
  signed=hmac.new(key,f'{nonce}\n{status}\n'.encode()+body,hashlib.sha256).hexdigest()
  if len(results)==3:signed='0'*64
  self.send_response(status); self.send_header('Content-Length',str(len(body))); self.send_header('X-SP-Response',signed); self.end_headers(); self.wfile.write(body)
  results.append({'path':self.path,'valid':valid,'status':status})
 do_GET=handle_request
 do_POST=handle_request
server=HTTPServer((host,43872),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
try:
 env=dict(os.environ,SCREENPILOT_BRIDGE_TEST_HOST=host)
 p=subprocess.run(['swift','test','--filter','BridgeIntegrationTests'],env=env,capture_output=True,text=True,timeout=90)
 open('artifacts/bridge-integration.log','w').write(p.stdout+p.stderr)
 open('artifacts/bridge-fixture-results.json','w').write(json.dumps(results,indent=2))
 print(p.stdout[-1800:]+p.stderr[-500:]); assert p.returncode==0
 assert [r['status'] for r in results]==[200,200,403,200,200],results
finally:server.shutdown();server.server_close()
