import sys
exec(open('lib.py').read())
cmd("WebDriver:Navigate",{"url":sys.argv[1]});time.sleep(7)
r=cmd("WebDriver:ExecuteScript",{"script":open(sys.argv[2]).read(),"args":[]})
print(json.dumps(r[3],indent=1,ensure_ascii=False)[:4000])
p.kill()
