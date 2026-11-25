import socket,json,time,base64,subprocess,sys,tempfile
prof=tempfile.mkdtemp()
p=subprocess.Popen(["firefox","--headless","--no-remote","--marionette","--profile",prof,"--width=1280","--height=800"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
for i in range(40):
    try: s=socket.create_connection(("127.0.0.1",2828));break
    except OSError: time.sleep(.5)
f=s.makefile("rwb",buffering=0)
def rd():
    n=b""
    while True:
        c=f.read(1)
        if c==b":":break
        n+=c
    k=int(n);b=b""
    while len(b)<k: b+=f.read(k-len(b))
    return json.loads(b)
n=[0]
def cmd(name,params=None):
    n[0]+=1
    m=json.dumps([0,n[0],name,params or {}]).encode()
    f.write(str(len(m)).encode()+b":"+m);return rd()
rd();cmd("WebDriver:NewSession",{"capabilities":{}})
cmd("WebDriver:SetWindowRect",{"width":1280,"height":800})
for out,url in zip(sys.argv[1::2],sys.argv[2::2]):
    cmd("WebDriver:Navigate",{"url":url});time.sleep(7)
    r=cmd("WebDriver:TakeScreenshot",{"full":False})
    open(out,"wb").write(base64.b64decode(r[3]["value"]))
p.kill()
