def arch(cx,base,half,top):
    yk=top+(base-top)*.5; yc=top+(base-top)*.2
    return f"M{cx-half} {base} L{cx-half} {yk} Q{cx-half} {yc} {cx} {top} Q{cx+half} {yc} {cx+half} {yk} L{cx+half} {base}Z"
P={ # name: bg1,bg2,outer,gap,band3,band4,inner,crescent,base
"1-emerald-gold":("#0F4A3E","#051F1A","#E7B34A","#082A23","#1B8A70","#0F5847","#F6E7B8","#0F5847","#E7B34A"),
"2-midnight-silver":("#141E4D","#04081A","#C9D3F0","#070C22","#3B5BDB","#24378F","#EEF2FF","#24378F","#C9D3F0"),
"3-plum-rosegold":("#43207A","#1A0B38","#F2B8A2","#150826","#8A4FD6","#5A2FA0","#FCE9E0","#5A2FA0","#F2B8A2"),
"4-sand-terracotta":("#F6ECD9","#E0CBA6","#C0623A","#F6ECD9","#DE9366","#A8492B","#FFF7E8","#A8492B","#C0623A"),
"5-teal-coral":("#0E7686","#053840","#FF8A6B","#04262C","#19A3A8","#0C7480","#FFEBDD","#0C7480","#FF8A6B"),
"6-graphite":("#33333A","#0C0C0F","#F2F2F2","#111114","#6E6E78","#45454D","#FFFFFF","#45454D","#F2F2F2"),
}
for n,(b1,b2,o,g,c3,c4,inn,cr,base) in P.items():
    L=[(290,190,o),(262,218,g),(228,258,c3),(172,322,c4),(118,392,inn)]
    al="".join(f'<path d="{arch(512,810,h,t)}" fill="{c}"/>' for h,t,c in L)
    open(n+".svg","w").write(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{b1}"/><stop offset="1" stop-color="{b2}"/></linearGradient>
<mask id="cm"><rect width="1024" height="1024" fill="#fff"/><circle cx="538" cy="580" r="54" fill="#000"/></mask></defs>
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>{al}
<circle cx="512" cy="600" r="64" fill="{cr}" mask="url(#cm)"/>
<rect x="212" y="810" width="600" height="34" rx="17" fill="{base}"/></svg>''')
