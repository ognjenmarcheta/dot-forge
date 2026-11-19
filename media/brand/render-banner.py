import re, sys, html
logo = open(sys.argv[1]).read().rstrip("\n").split("\n")
cls = {"f1":"c1","f2":"c2","f3":"c3"}
out=[]
for line in logo:
    parts = re.split(r"(\{[a-z0-9]+\})", line); cur=None; s=""
    for p in parts:
        m = re.fullmatch(r"\{([a-z0-9]+)\}", p)
        if m:
            t=m.group(1)
            if cur: s+="</span>"; cur=None
            if t in cls: s+=f'<span class="{cls[t]}">'; cur=t
        else: s+=html.escape(p)
    if cur: s+="</span>"
    out.append(s)
art="\n".join(out)
page = open(sys.argv[2]).read().replace("@@ART@@", art)
open(sys.argv[3],"w").write(page)
