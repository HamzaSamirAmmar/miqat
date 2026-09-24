import math
H='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
TILE='<rect x="100" y="100" width="824" height="824" rx="185" fill="{}"/>'
CLIP='<clipPath id="c"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>'
def pt(cx,cy,r,a): return cx+r*math.cos(math.radians(a)), cy-r*math.sin(math.radians(a))
def sector(cx,cy,ro,ri,a0,a1):
    sw=1 if a1<a0 else 0; lg=1 if abs(a1-a0)>180 else 0
    p=lambda r,a:"%.1f %.1f"%pt(cx,cy,r,a)
    return f"M{p(ro,a0)} A{ro} {ro} 0 {lg} {sw} {p(ro,a1)} L{p(ri,a1)} A{ri} {ri} 0 {lg} {1-sw} {p(ri,a0)}Z"
def arc(cx,cy,r,frac,start=90):
    e=start-360*frac; lg=1 if frac>.5 else 0
    x0,y0=pt(cx,cy,r,start); x1,y1=pt(cx,cy,r,e)
    return f"M{x0:.1f} {y0:.1f} A{r} {r} 0 {lg} 1 {x1:.1f} {y1:.1f}"
def crescent(cx,cy,r,dx,dy,r2,fill,mid):
    return (f'<mask id="{mid}"><rect width="1024" height="1024" fill="#fff"/><circle cx="{cx+dx}" cy="{cy+dy}" r="{r2}" fill="#000"/></mask>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" mask="url(#{mid})"/>')
def crescent_def(cx,cy,r,dx,dy,r2,mid):
    return f'<mask id="{mid}"><rect width="1024" height="1024" fill="#fff"/><circle cx="{cx+dx}" cy="{cy+dy}" r="{r2}" fill="#000"/></mask>'
def w(n,s): open(n,"w").write(s)
def arch(cx,base,half,top):
    yk=top+(base-top)*.5; yc=top+(base-top)*.2
    return f"M{cx-half} {base} L{cx-half} {yk} Q{cx-half} {yc} {cx} {top} Q{cx+half} {yc} {cx+half} {yk} L{cx+half} {base}Z"

# ---------- 1 ARCHES ----------
cy=760
rings="".join(f'<path d="{sector(512,cy,ro,ri,180,0)}" fill="#EDEBE5" fill-opacity="{o}"/>' for ro,ri,o in [(320,270,.95),(250,200,.75),(180,130,.55)])
disc=f'<path d="M402 {cy} A110 110 0 0 1 622 {cy}Z" fill="#EDEBE5" fill-opacity=".4"/>'
gx,gy=pt(512,cy,600,132); hx,hy=pt(512,cy,600,110)
w("1-arches.svg",H+f'''<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4A5C82"/><stop offset="1" stop-color="#232D48"/></linearGradient>
<mask id="wm"><rect width="1024" height="1024" fill="#fff"/><polygon points="512,{cy} {gx:.0f},{gy:.0f} {hx:.0f},{hy:.0f}" fill="#000"/></mask>
{crescent_def(512,300,84,34,-26,70,"cm")}</defs>
{TILE.format("url(#bg)")}<g mask="url(#wm)">{rings}{disc}</g>
<circle cx="512" cy="300" r="84" fill="#F4F1EA" mask="url(#cm)"/></svg>''')
# menu 1: dome with ring cut + crescent
w("menu-1.svg",H+f'''<defs><mask id="m"><rect width="1024" height="1024" fill="#fff"/><path d="{sector(512,700,190,140,180,0)}" fill="#000"/>
<circle cx="546" cy="262" r="72" fill="#000"/></mask></defs>
<g mask="url(#m)"><path d="M232 700 A280 280 0 0 1 792 700Z"/><circle cx="512" cy="290" r="100"/></g>
<rect x="232" y="740" width="560" height="70" rx="35"/></svg>''')

# ---------- 2 DUSK LAYERS ----------
cy=740
cols=[(310,"#B8457A"),(250,"#F0644F"),(190,"#FF9E5B"),(130,"#FFD37A"),(70,"#FFF4CF")]
lay="".join(f'<path d="M{512-r} {cy} A{r} {r} 0 0 1 {512+r} {cy}Z" fill="{c}"/>' for r,c in cols)
stars="".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#fff" fill-opacity=".8"/>' for x,y,r in [(260,240,6),(730,215,8),(610,300,5),(420,190,5),(820,340,5),(200,380,4)])
w("2-dusk.svg",H+f'''<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#171240"/><stop offset="1" stop-color="#43227A"/></linearGradient>{CLIP}</defs>
<g clip-path="url(#c)"><rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>{stars}{lay}
<rect x="100" y="{cy}" width="824" height="200" fill="#0E0A2B"/><rect x="100" y="{cy}" width="824" height="6" fill="#FFD37A" fill-opacity=".7"/></g></svg>''')
# menu 2: sunrise
rays="".join('<line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="#000" stroke-width="72" stroke-linecap="round"/>'%(*pt(512,640,250,a),*pt(512,640,340,a)) for a in (160,125,90,55,20))
w("menu-2.svg",H+f'''<path d="M342 640 A170 170 0 0 1 682 640Z"/>{rays}
<line x1="200" y1="740" x2="824" y2="740" stroke="#000" stroke-width="72" stroke-linecap="round"/></svg>''')

# ---------- 3 EMERALD MIHRAB ----------
L=[(290,190,"#E7B34A"),(262,218,"#082A23"),(228,258,"#1B8A70"),(172,322,"#0F5847"),(118,392,"#F6E7B8")]
al="".join(f'<path d="{arch(512,810,h,t)}" fill="{c}"/>' for h,t,c in L)
w("3-mihrab.svg",H+f'''<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#0F4A3E"/><stop offset="1" stop-color="#051F1A"/></linearGradient>
{crescent_def(512,600,64,26,-20,54,"cm")}</defs>{TILE.format("url(#bg)")}{al}
<circle cx="512" cy="600" r="64" fill="#0F5847" mask="url(#cm)"/>
<rect x="212" y="810" width="600" height="34" rx="17" fill="#E7B34A"/></svg>''')
w("menu-3.svg",H+f'''<defs>{crescent_def(512,560,110,44,-30,92,"cm")}</defs>
<path d="{arch(512,800,260,220)}" fill="none" stroke="#000" stroke-width="84" stroke-linejoin="round"/>
<circle cx="512" cy="560" r="110" mask="url(#cm)"/></svg>''')

# ---------- 4 MOON & DUNES ----------
w("4-dunes.svg",H+f'''<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B1B45"/><stop offset="1" stop-color="#34549F"/></linearGradient>{CLIP}
{crescent_def(512,360,190,74,-48,160,"cm")}</defs>
<g clip-path="url(#c)"><rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>
<circle cx="512" cy="360" r="190" fill="#FFF3D0" mask="url(#cm)"/>
<g fill="#fff" fill-opacity=".8"><circle cx="270" cy="250" r="6"/><circle cx="780" cy="300" r="7"/><circle cx="700" cy="200" r="5"/></g>
<path d="M100 700 Q300 600 520 690 T924 650 V924 H100Z" fill="#2A4488"/>
<path d="M100 770 Q330 690 560 770 T924 740 V924 H100Z" fill="#1A2F6B"/>
<path d="M100 850 Q300 790 520 850 T924 830 V924 H100Z" fill="#0C1A4A"/></g></svg>''')
w("menu-4.svg",H+f'''<defs>{crescent_def(512,410,240,96,-64,206,"cm")}</defs>
<circle cx="512" cy="410" r="240" mask="url(#cm)"/>
<path d="M190 730 Q351 640 512 730 T834 730" fill="none" stroke="#000" stroke-width="80" stroke-linecap="round"/></svg>''')

# ---------- 5 PRAYER RINGS ----------
rc=[(330,"#7FB4FF",.92),(272,"#FFD84D",.78),(214,"#FFA24D",.64),(156,"#FF5D73",.5),(98,"#B18CFF",.36)]
tr="".join(f'<circle cx="512" cy="512" r="{r}" fill="none" stroke="{c}" stroke-opacity=".14" stroke-width="42"/>' for r,c,f in rc)
ar="".join(f'<path d="{arc(512,512,r,f)}" fill="none" stroke="{c}" stroke-width="42" stroke-linecap="round"/>' for r,c,f in rc)
w("5-rings.svg",H+f'''<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1A1A22"/><stop offset="1" stop-color="#08080C"/></linearGradient></defs>
{TILE.format("url(#bg)")}{tr}{ar}</svg>''')
mr="".join(f'<path d="{arc(512,512,r,f)}" fill="none" stroke="#000" stroke-width="72" stroke-linecap="round"/>' for r,f in [(300,.8),(190,.62),(90,.4)])
w("menu-5.svg",H+mr+"</svg>")

# ---------- 6 MINARET DAWN ----------
w("6-minaret.svg",H+f'''<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2A2F8F"/><stop offset=".6" stop-color="#D9648F"/><stop offset="1" stop-color="#FFB877"/></linearGradient>{CLIP}
{crescent_def(512,262,44,18,-14,37,"cm")}</defs>
<g clip-path="url(#c)"><rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>
<circle cx="512" cy="640" r="230" fill="#FFF0CC" fill-opacity=".92"/>
<g fill="#100F35"><rect x="474" y="440" width="76" height="500"/><rect x="446" y="418" width="132" height="34" rx="6"/>
<path d="M474 418 Q474 350 512 316 Q550 350 550 418Z"/><rect x="509" y="290" width="6" height="34"/>
<path d="M100 800 Q300 740 512 790 T924 780 V924 H100Z"/></g>
<circle cx="512" cy="262" r="44" fill="#F5C86B" mask="url(#cm)"/></g></svg>''')
w("menu-6.svg",H+f'''<defs>{crescent_def(512,215,90,36,-26,76,"cm")}</defs>
<rect x="462" y="470" width="100" height="360"/><rect x="420" y="430" width="184" height="52" rx="10"/>
<path d="M462 430 Q462 340 512 300 Q562 340 562 430Z"/>
<circle cx="512" cy="215" r="90" mask="url(#cm)" transform="translate(0 -10)"/>
<rect x="300" y="790" width="424" height="64" rx="32"/></svg>''')
