import sys,json,base64
exec(open('lib.py').read())
svg=open('st/stevanini-favicon.svg').read()
cmd("WebDriver:Navigate",{"url":"about:blank"});time.sleep(1)
js="""
const [svg,N,bg,frac]=arguments;
return new Promise(res=>{const im=new Image();im.onload=()=>{const c=document.createElement('canvas');c.width=c.height=N;const x=c.getContext('2d');if(bg){x.fillStyle=bg;x.fillRect(0,0,N,N)}
const s=N*frac,r=im.width/im.height;let w=s,h=s;if(r>1)h=s/r;else w=s*r;x.drawImage(im,(N-w)/2,(N-h)/2,w,h);res(c.toDataURL('image/png'))};im.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)))})
"""
jobs={ 'favicon-16':(16,None,.95),'favicon-32':(32,None,.95),'favicon-48':(48,None,.95),'favicon-96':(96,None,.95),'favicon-144':(144,None,.95),
 'apple-180':(180,'#fbf6ec',.72),'icon-192':(192,'#fbf6ec',.72),'icon-512':(512,'#fbf6ec',.72),'maskable-192':(192,'#fbf6ec',.55),'maskable-512':(512,'#fbf6ec',.55)}
for k,(N,bg,fr) in jobs.items():
    r=cmd("WebDriver:ExecuteAsyncScript",{"script":"const cb=arguments[arguments.length-1];(async()=>{"+js.replace("const [svg,N,bg,frac]=arguments;","const [svg,N,bg,frac]=%s;"%json.dumps([svg,N,bg,fr])).replace("return new Promise(res=>","const v=await new Promise(res=>")+";cb(v)})()","args":[]})
    v=r[3]["value"]; open(f'png/{k}.png','wb').write(base64.b64decode(v.split(',')[1]))
p.kill()
