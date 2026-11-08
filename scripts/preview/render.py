#!/usr/bin/env python3
"""Box-rendered previews for the simplify-v2 (variant 1, Finder-style) UI.

Data (sectors, colours, label-fit, outline rows, high-risk flags, basket, confirm groups)
comes from scripts/preview/main.swift compiled with the real core sources; strings come
from Resources/zh-Hans.lproj/Localizable.strings and colours from Resources/DesignTokens.json.
Output is HTML rendered by headless Chrome at 1280x800. NOT a macOS screenshot.
Usage: scripts/preview/render.py dump.json OUTDIR
"""
import html, json, math, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
dump = json.load(open(sys.argv[1])); out = sys.argv[2]
os.makedirs(out, exist_ok=True)
STR = {}
for k, v in re.findall(r'^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)";', open(os.path.join(ROOT, "Resources/zh-Hans.lproj/Localizable.strings"), encoding="utf-8").read(), re.M):
    STR[k] = v.replace('\\"', '"').replace("\\n", "\n")
TOK = json.load(open(os.path.join(ROOT, "Resources/DesignTokens.json")))

def tr(key, *args):
    s = STR[key]; i = iter(args)
    def rep(m):
        return str(args[int(m.group(1)) - 1]) if m.group(1) else str(next(i))
    return re.sub(r"%(?:(\d)\$)?(?:@|ld|d)", rep, s)
E = html.escape

def arc(s, k):
    a0, a1, r0, r1 = s["a0"], s["a1"], s["r0"] * k, s["r1"] * k
    p = lambda a, r: (r * math.sin(a), -r * math.cos(a))
    if a1 - a0 >= 2 * math.pi - 1e-6:
        return f"M{-r1},0a{r1},{r1} 0 1,0 {2*r1},0a{r1},{r1} 0 1,0 {-2*r1},0M{-r0},0a{r0},{r0} 0 1,0 {2*r0},0a{r0},{r0} 0 1,0 {-2*r0},0"
    big = 1 if a1 - a0 > math.pi else 0
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = p(a0, r1), p(a1, r1), p(a1, r0), p(a0, r0)
    return f"M{x0:.2f},{y0:.2f}A{r1},{r1} 0 {big},1 {x1:.2f},{y1:.2f}L{x2:.2f},{y2:.2f}A{r0},{r0} 0 {big},0 {x3:.2f},{y3:.2f}Z"

def labels_svg(sectors, k, mode, outline_boxes=False):
    """Draws the labels exactly as LabelLayout placed them (tier, lines, centre, rotation, ink)."""
    g = []
    for s in sectors:
        L = s["lab"]; ink = L["inkLight"] if mode == "light" else L["inkDark"]
        x, y = L["cx"] * k, -L["cy"] * k; deg = -math.degrees(L["rot"])
        if s["prot"]:
            g.append(f'<text x="{x:.1f}" y="{y+4:.1f}" text-anchor="middle" font-size="11" fill="{ink}">🔒</text>'); continue
        if L["tier"] == "hidden" or not L["lines"]: continue
        tf = f' transform="rotate({deg:.2f} {x:.1f} {y:.1f})"' if abs(deg) > 0.01 else ""
        g.append(f'<g{tf}>')
        if outline_boxes:
            g.append(f'<rect x="{x-L["w"]*k/2:.1f}" y="{y-L["h"]*k/2:.1f}" width="{L["w"]*k:.1f}" height="{L["h"]*k:.1f}" fill="none" stroke="{ink}" stroke-opacity=".25" stroke-dasharray="2 2"/>')
        lines = L["lines"]; nf, sf = L["nameFont"] * k, L["sizeFont"] * k
        if len(lines) == 2:
            top = y - L["h"] * k / 2
            yn = top + L["nameLine"] * k / 2 + 0.35 * nf; ys = top + (L["nameLine"] + L["sizeLine"] / 2) * k + 0.35 * sf
            g.append(f'<text x="{x:.1f}" y="{yn:.1f}" text-anchor="middle" font-size="{nf:.2f}" font-weight="500" fill="{ink}">{E(lines[0])}</text>')
            g.append(f'<text x="{x:.1f}" y="{ys:.1f}" text-anchor="middle" font-size="{sf:.2f}" fill="{ink}" class="num">{E(lines[1])}</text>')
        else:
            fs = sf if L["isSize"] else nf
            g.append(f'<text x="{x:.1f}" y="{y + 0.35 * fs:.1f}" text-anchor="middle" font-size="{fs:.2f}" font-weight="{400 if L["isSize"] else 500}" fill="{ink}"{" class=\"num\"" if L["isSize"] else ""}>{E(lines[0])}</text>')
        g.append('</g>')
    return g

def drill_labels(mode, d, W=900, H=760):
    t = TOK[mode]; k = d["k"]
    secs = d["sectors"]; hidden = [s for s in secs if s["tip"] and s["lab"]["tier"] == "hidden" and not s["prot"]]
    tipS = hidden[0] if hidden else None
    g = [f'<html><head><meta charset="utf-8"><style>body{{margin:0;background:{t["bg.content"]};font-family:-apple-system,"PingFang SC","Noto Sans CJK SC",sans-serif}}.num{{font-variant-numeric:tabular-nums}}</style></head><body>',
         f'<svg width="{W}" height="{H}" xmlns="http://www.w3.org/2000/svg"><g transform="translate({W/2},{H/2+10})">']
    for s in secs:
        g.append(f'<path d="{arc(s, k)}" fill="{s[mode]}" stroke="{t["bg.content"]}" stroke-width="1.5" stroke-linejoin="round"/>')
    if tipS: g.append(f'<path d="{arc(tipS, k)}" fill="none" stroke="{t["text.primary"]}" stroke-width="2"/>')
    g += labels_svg(secs, k, mode)
    c = d["center"]
    g.append(f'<text y="-24" text-anchor="middle" font-size="13" fill="{t["text.secondary"]}">{E(c["name"])}</text>')
    g.append(f'<text y="8" text-anchor="middle" font-size="26" font-weight="600" fill="{t["text.primary"]}" class="num">{E(c["size"])}</text>')
    g.append('</g>')
    g.append(f'<text x="16" y="24" font-size="13" font-weight="600" fill="{t["text.primary"]}">Users › tester — 分层标签 · k = {k:.2f}（档位 {d["tier"]:.2f}）</text>')
    g.append(f'<text x="{W-16}" y="24" text-anchor="end" font-size="12" fill="#D0342C" font-weight="600">仅供参考 · reference only (box render, not the app)</text>')
    cnt = {}
    for s in secs: cnt[s["lab"]["tier"]] = cnt.get(s["lab"]["tier"], 0) + 1
    g.append(f'<text x="16" y="{H-14}" font-size="11" fill="{t["text.tertiary"]}">a 名称+大小 {cnt.get("nameAndSize",0)} · b 仅大小 {cnt.get("sizeOnly",0)} · c 旋转 {cnt.get("rotated",0)} · d 隐藏 {cnt.get("hidden",0)} (悬停显示提示) · 屏幕字号 名 {max(10, 11*k):.1f}pt+ / 大小 {max(10, 10*k):.1f}pt+ · 不透明度 1.0</text></svg>')
    if tipS:
        a = (tipS["a0"] + tipS["a1"]) / 2; r = tipS["r1"] * k
        tx, ty = W/2 + r*math.sin(a) + 8, H/2 + 10 - r*math.cos(a) + 8
        tx = min(tx, W - 300)
        lines = "<br>".join(E(x) for x in tipS["tip"].split("\n"))
        g.append(f'<div style="position:absolute;left:{tx:.0f}px;top:{ty:.0f}px;max-width:290px;padding:5px 8px;font-size:11px;line-height:15px;background:{t["control"]};color:{t["text.primary"]};border:1px solid {t["separator"]};border-radius:5px;box-shadow:0 2px 8px rgba(0,0,0,.25)">{lines}</div>')
    g.append('</body></html>')
    return "".join(g)

def chart_svg(mode, w, h):
    t = TOK[mode]; k = max(0.75, min(1.15, min(w, h - 40) / 600))
    ink = "#1D1D1F" if mode == "light" else "#FFFFFF"
    hatch_bg, hatch_fg = ("#BEBEBE", "#A9A9A9") if mode == "light" else ("#3D3D3D", "#4C4C4C")
    sel = dump["selected"]; secs = {s["i"]: s for s in dump["sectors"]}
    g = [f'<svg width="{w}" height="{h}" xmlns="http://www.w3.org/2000/svg"><defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="6" height="6" fill="{hatch_bg}"/><line x1="0" y1="0" x2="0" y2="6" stroke="{hatch_fg}" stroke-width="2"/></pattern></defs>',
         f'<g transform="translate({w/2},{h/2 - 10})">']
    for s in dump["sectors"]:
        fill = "url(#hatch)" if s["role"] == "protected" else s[mode]
        g.append(f'<path d="{arc(s, k)}" fill="{fill}" stroke="{t["bg.content"]}" stroke-width="1.5" stroke-linejoin="round"/>')
    g.append(f'<path d="{arc(secs[sel], k)}" fill="none" stroke="{t["text.primary"]}" stroke-width="2" stroke-linejoin="round"/>')
    g += labels_svg(dump["sectors"], k, mode)
    c = dump["center"]
    g.append(f'<text y="-24" text-anchor="middle" font-size="13" fill="{t["text.secondary"]}">{E(c["name"])}</text>')
    g.append(f'<text y="8" text-anchor="middle" font-size="26" font-weight="600" fill="{t["text.primary"]}" class="num">{E(c["size"])}</text>')
    g.append(f'<text y="28" text-anchor="middle" font-size="11" fill="{t["text.tertiary"]}">{E(tr("chart.itemCount", c["items"]))}</text>')
    g.append(f'</g><text x="16" y="{h-12}" font-size="11" fill="{t["text.tertiary"]}">{E(tr("chart.hint"))}</text></svg>')
    return "".join(g)

def badge(kind, t):
    if kind == "risk":
        return f'<span class="badge" style="color:{t["warn.text"]}">⚠ {E(tr("badge.highRisk"))}</span>'
    return f'<span class="badge" style="color:{t["text.secondary"]}">🔒 {E(tr("badge.protected"))}</span>'

FOLDER = '<svg width="14" height="12" viewBox="0 0 14 12"><path d="M1 2.5h4l1.2 1.3H13V11H1z" fill="#5AA9F0"/></svg>'
FILE = '<svg width="11" height="13" viewBox="0 0 11 13"><path d="M1 1h6l3 3v8H1z" fill="none" stroke="#9A9AA0"/></svg>'

def outline(mode):
    t = TOK[mode]; secs = {s["i"]: s for s in dump["sectors"]}; rows = []
    for r in dump["rows"]:
        s = secs[r["sector"]]; selected = r["sector"] == dump["selected"]
        fg = "#FFFFFF" if selected else t["text.primary"]; sub = "#FFFFFF" if selected else t["text.secondary"]
        dot = "url(#)" if False else s[mode]
        tri = ("▾" if r["expanded"] else "▸") if r["expandable"] else ""
        icon = FOLDER if r["dir"] else ("⋯" if r["other"] else FILE)
        b = badge("prot", t) if r["prot"] else (badge("risk", t) if r["risk"] else "")  # app: one badge, protected wins
        if selected: b = b.replace(f'color:{t["warn.text"]}', 'color:#FFFFFF').replace(f'color:{t["text.secondary"]}', 'color:#FFFFFF')
        bg = t["brand"] if selected else "transparent"
        rows.append(f'<div class="row" style="background:{bg};color:{fg}"><span class="name" style="padding-left:{8 + r["depth"]*16}px">'
                    f'<span class="tri" style="color:{sub}">{tri}</span><span class="dot" style="background:{dot}"></span>{icon} <span class="nm">{E(r["name"])}</span>{b}</span>'
                    f'<span class="num c1">{E(r["size"])}</span><span class="num c2" style="color:{sub}">{r["share"]:.1f}%</span></div>')
    head = (f'<div class="head" style="color:{t["text.secondary"]};border-bottom:1px solid {t["separator"]}"><span class="name" style="padding-left:24px">{E(tr("column.name"))}</span>'
            f'<span class="c1">{E(tr("column.size"))} ▾</span><span class="c2">{E(tr("column.share"))}</span></div>')
    foot = (f'<div class="foot" style="color:{t["text.tertiary"]};display:flex;gap:6px;align-items:center"><span>{E(tr("outline.hidden", dump["hidden"]))}</span>'
            f'<span style="color:{t["brand.text"]}">{E(tr("outline.show"))}</span><span style="flex:1"></span>'
            f'<span class="btn" style="background:{t["control"]};color:{t["text.primary"]};border:1px solid {t["separator"]}">{E(tr("button.addToBasket"))}</span></div>')
    return head + "".join(rows) + foot

CSS = """*{box-sizing:border-box;margin:0}body{width:var(--W);height:var(--H);overflow:hidden;font-family:-apple-system,Inter,'Noto Sans CJK SC',sans-serif;font-size:13px}
.num{font-variant-numeric:tabular-nums}.win{position:absolute;inset:0;display:flex;flex-direction:column}
.tb{height:52px;display:flex;align-items:center;gap:10px;padding:0 14px 0 84px}.lights{position:absolute;left:18px;top:19px;display:flex;gap:8px}.lights i{width:12px;height:12px;border-radius:6px;display:block}
.seg,.btn{height:24px;border-radius:6px;display:flex;align-items:center;padding:0 9px;font-size:13px}.crumb{flex:1;display:flex;gap:6px;align-items:center}
.search{width:180px;height:24px;border-radius:6px;padding:0 8px;display:flex;align-items:center}
.main{flex:1;display:flex;min-height:0}.list{flex:none;width:436px;overflow:hidden}.head,.row{display:flex;height:24px;align-items:center;padding-right:12px}
.head{font-size:11px;height:26px}.name{flex:1;display:flex;align-items:center;gap:5px;min-width:0;white-space:nowrap}.nm{overflow:hidden;text-overflow:ellipsis}
.tri{width:10px;font-size:10px}.dot{width:9px;height:9px;border-radius:3px;flex:none}.c1{width:70px;text-align:right}.c2{width:56px;text-align:right}
.badge{font-size:10px;border-radius:4px;padding:0 4px;line-height:15px;margin-left:4px}.foot{font-size:11px;padding:8px 12px}
.bar{height:56px;display:flex;align-items:center;gap:8px;padding:0 14px}.tok{height:24px;border-radius:12px;padding:0 10px;display:flex;align-items:center;gap:5px;font-size:12px}
.cap{position:relative}.capbar{position:relative;border-radius:3px;overflow:hidden}.capbar i{position:absolute;top:0;bottom:0;display:block}.leg{display:flex;gap:14px;font-size:11px;white-space:nowrap;margin-top:8px}.leg span{display:flex;align-items:center;gap:5px}.leg b{width:8px;height:8px;border-radius:4px;display:inline-block}.wm{position:absolute;left:14px;font-size:10px;opacity:.55}
.dim{position:absolute;inset:0;background:rgba(0,0,0,.28)}.sheet{position:absolute;top:52px;width:600px;border-radius:10px;padding:18px 20px;box-shadow:0 18px 50px rgba(0,0,0,.35)}
.grp{border-radius:8px;margin-top:10px;overflow:hidden}.gh{font-size:11px;font-weight:600;padding:6px 10px}.it{display:flex;align-items:center;gap:8px;padding:5px 10px;font-size:12px}
.radio{display:flex;align-items:center;gap:6px;margin:4px 0}.rb{width:14px;height:14px;border-radius:7px;display:inline-block}"""

def hatch_css(mode):
    a, b = ("#BEBEBE", "#A9A9A9") if mode == "light" else ("#3D3D3D", "#4C4C4C")
    return f"repeating-linear-gradient(45deg,{b} 0 1.5px,{a} 1.5px 4.2px)"

def capacity(mode, W, compact=False, drill=False):
    t = TOK[mode]; c = dump["capacity"]; dr = c["drill"]
    other = "#CACACA" if mode == "light" else "#484848"
    bw = W - 48 if not compact else W - 40 - 140 - 230
    bh = 8 if compact else 10
    segs = []
    for i, sg in enumerate(c["segments"]):
        inscope = dr["inScope"][i] if drill else True
        fill = other if not inscope else (hatch_css(mode) if sg["kind"] == "protected" else (other if sg["kind"] in ("other", "systemGap") else sg[mode]))
        x0 = sg["start"] * bw; x1 = sg["end"] * bw
        segs.append(f'<i style="left:{x0:.2f}px;width:{max(1, x1 - x0 - 1.5):.2f}px;background:{fill};opacity:{1 if inscope else .55}"></i>')
    bar = (f'<div class="capbar" style="width:{bw}px;height:{bh}px;background:{t["token"]};box-shadow:inset 0 0 0 .5px {t["separator"]}">{"".join(segs)}</div>')
    if drill:
        x0 = dr["lo"] * bw + .75; x1 = dr["hi"] * bw - .75
        bar += f'<div style="position:absolute;left:{x0:.1f}px;width:{x1-x0:.1f}px;top:{bh+2}px;height:5px;border:1.5px solid {t["text.primary"]};border-top:none;opacity:.7"></div>'
    used = tr("capacity.used", c["used"], c["total"])
    if compact:
        return (f'<div class="cap" style="height:36px;display:flex;align-items:center;gap:28px;padding:0 20px;border-bottom:1px solid {t["separator"]}">'
                f'<b style="font-size:13px;font-weight:600">Macintosh HD</b><div style="position:relative">{bar}</div><span class="num" style="margin-left:auto;color:{t["text.secondary"]}">{E(used)}</span></div>')
    def dot(it):
        k = it["kind"]
        if k == "branch":
            sg = c["segments"][it["seg"]]; return sg[mode], sg["name"]
        return {"protected": (hatch_css(mode), tr("capacity.protected")), "other": (other, tr("capacity.other")),
                "folded": (None, tr("capacity.more", it.get("n", 0))), "system": (other, tr("capacity.system")),
                "free": (t["token"], tr("capacity.free"))}[k]
    if drill:
        leg = (f'<div class="leg"><span><b style="display:none"></b><strong style="font-weight:600">{E(tr("capacity.current", dr["name"], dr["size"], dr["share"]))}</strong>'
               f'<span style="color:{t["text.secondary"]}">{E(tr("capacity.scopeHint"))}</span></span></div>')
    else:
        items = []
        for it in c["legendFitted"]:
            col, name = dot(it)
            d = (f'<b style="background:{col}' + (f';box-shadow:0 0 0 0.5px {t["separator"]}' if it["kind"] == "free" else "") + '"></b>') if col else ""
            if it["kind"] == "folded": name = f'<span style="color:{t["text.secondary"]}">{E(name)}</span>'
            items.append(f'<span>{d}{name if it["kind"] == "folded" else E(name)} <span class="num" style="color:{t["text.secondary"]}">{E(it["size"])}</span></span>')
        leg = f'<div class="leg">{"".join(items)}</div>'
    return (f'<div class="cap" style="height:76px;padding:13px 24px 0;border-bottom:1px solid {t["separator"]}">'
            f'<div style="display:flex;justify-content:space-between;font-size:13px"><b style="font-weight:600">Macintosh HD</b><span class="num" style="color:{t["text.secondary"]}">{E(used)}</span></div>'
            f'<div style="position:relative;margin-top:6px">{bar}</div>{leg}</div>')

def window(mode, overlay="", W=1280, H=800, compact=False, drill=False):
    t = TOK[mode]; b = dump["basket"]
    capH = 36 if compact else 76
    LW = 436 if W > 1000 else 360
    chart = chart_svg(mode, W - LW, H - 52 - capH - 56)
    toks = "".join(f'<span class="tok" style="background:{t["token.warn"] if c["risk"] else t["token"]};color:{t["text.primary"]}">'
                   f'{"<span style=color:" + t["warn.icon"] + ">⚠</span>" if c["risk"] else ""}{E(c["name"])} <span class="num" style="color:{t["text.secondary"]}">{E(c["size"])}</span> <span style="color:{t["text.tertiary"]}">✕</span></span>' for c in b["chips"] if not compact or c["risk"])
    if compact and len(b["chips"]) > sum(1 for c in b["chips"] if c["risk"]):
        toks += f'<span class="tok" style="background:{t["token"]};color:{t["text.secondary"]}">{E(tr("basket.more", len(b["chips"]) - sum(1 for c in b["chips"] if c["risk"])))}</span>'
    risk = tr("basket.riskSummary", b["high"]) if b["high"] else tr("basket.safeSummary")
    bar = (f'<div class="bar" style="background:{t["danger.tint"]};border-top:2px solid {t["danger.line"]}"><span style="color:{t["danger.text"]}">🗑</span><b style="color:{t["danger.text"]}">{E(tr("basket.title"))}</b>'
           f'<span class="num" style="color:{t["text.secondary"]}">{E(tr("basket.summary", b["count"], b["total"]))}</span>{toks}'
           f'<span style="flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:{t["warn.text"]};font-size:11px;padding-left:6px">{E(risk)}</span>'
           f'<span class="btn" style="background:{t["control"]};color:{t["danger.text"]};border:1px solid {t["separator"]}">{E(tr("button.deletePermanently"))}</span>'
           f'<span class="btn" style="background:{t["brand"]};color:#fff">{E(tr("button.moveToTrash"))} <span style="opacity:.75">⌘⌫</span></span></div>')
    ctl = f'background:{t["control"]};color:{t["text.primary"]};border:1px solid {t["separator"]}'
    return f"""<html><head><meta charset="utf-8"><style>{CSS}</style></head><body style="--W:{W}px;--H:{H}px;background:{t['bg.window']};color:{t['text.primary']}"><div class="win">
<div class="tb" style="border-bottom:1px solid {t['separator']}"><div class="lights"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></div>
<span class="seg" style="{ctl}">‹ &nbsp;│&nbsp; ›</span><span class="crumb">💽 Macintosh HD <span style="color:{t['text.tertiary']}">›</span> Data</span>
<span class="btn" style="{ctl}" title="{E(tr('toolbar.rescan.lastScan', '今天 10:02'))}">↻</span><span class="btn" style="{ctl}">{E(tr('menu.reveal'))}</span><span class="search" style="{ctl};color:{t['text.tertiary']}">🔍 {E(tr('search.placeholder'))}</span></div>
{capacity(mode, W, compact, drill)}<div class="main"><div style="background:{t['bg.window']}">{chart}</div><div class="list" style="width:{LW}px;background:{t['bg.content']};border-left:1px solid {t['separator']}">{outline(mode)}</div></div>
{bar}
<div class="wm" style="top:{52 + capH + 8}px;color:{t['text.secondary']}">Box-rendered preview from real layout/colour/strings/tokens — not a macOS screenshot · 示例数据</div>
<div style="position:absolute;right:14px;top:60px;padding:3px 10px;border-radius:5px;background:#D70015;color:#fff;font-size:13px;font-weight:700;z-index:9">仅供参考 · reference only</div></div>{overlay}</body></html>"""

def sheet(mode, permanent, left):
    t = TOK[mode]; sh = dump["sheet"]; n = sh["count"]
    def items(lst, kind):
        rows = []
        for it in lst:
            detail = tr(it["consequence"]) if kind == "high" else (tr("confirm.detail.cache") if it["cache"] else E(it["path"]))
            dc = t["danger.text"] if kind == "high" else t["text.secondary"]
            cb = "☐" if kind == "ex" else "☑"
            rows.append(f'<div class="it"><span style="color:{t["brand.text"]}">{cb}</span><span style="flex:none;font-weight:500">{E(it["name"])}</span>'
                        f'<span style="flex:1;color:{dc};font-size:11px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">{E(detail)}</span><span class="num">{E(it["size"])}</span></div>')
        return "".join(rows)
    allcache = all(i["cache"] for i in sh["normal"])
    groups = (f'<div class="grp" style="border:1px solid {t["danger.line"]};background:{t["danger.tint"]}"><div class="gh" style="color:{t["danger.text"]}">⚠ {E(tr("confirm.group.highRisk", len(sh["high"])))}</div>{items(sh["high"], "high")}</div>'
              f'<div class="grp" style="border:1px solid {t["separator"]};background:{t["bg.group"]}"><div class="gh" style="color:{t["text.secondary"]}">{E(tr("confirm.group.rebuildable" if allcache else "confirm.group.normal", len(sh["normal"])))}</div>{items(sh["normal"], "n")}</div>'
              + (f'<div class="grp" style="border:1px solid {t["separator"]};background:{t["bg.group"]};opacity:.75"><div class="gh" style="color:{t["text.tertiary"]}">{E(tr("confirm.group.excluded", len(sh["excluded"])))}</div>'
              + "".join(f'<div class="it"><span>🔒</span><b style="font-weight:500">{E(e["name"])}</b><span style="flex:1;font-size:11px;color:{t["text.tertiary"]}">{E(tr("confirm.excluded.sip"))}</span><span class="num">{E(e["size"])}</span></div>' for e in sh["excluded"]) + "</div>" if sh["excluded"] else ""))
    def radio(on, label, detail, color):
        rb = f'background:{t["brand"]};box-shadow:inset 0 0 0 4px {t["brand"]},inset 0 0 0 7px #fff' if on else f'border:1px solid {t["separator"]};background:{t["control"]}'
        return f'<div class="radio"><span class="rb" style="{rb}"></span><span style="color:{color}">{E(label)}</span><span style="color:{t["text.tertiary"]}">{E(detail)}</span></div>'
    title = tr("confirm.title.permanent" if permanent else "confirm.title.trash", n)
    subtitle = tr("confirm.subtitle.permanent" if permanent else "confirm.subtitle.trash", sh["bytes"])
    perm = ""
    if permanent:
        perm = (f'<div style="margin-top:8px;padding:10px;border-radius:8px;background:{t["danger.tint"]};border:1px solid {t["danger.line"]};color:{t["danger.text"]};font-size:12px">'
                f'{E(tr("confirm.warning.risk", sh["bytes"], sh["highCount"]))}<div style="margin-top:8px;display:flex;align-items:center;gap:8px;color:{t["text.primary"]}">{E(tr("confirm.type.prompt", sh["phrase"]))}'
                f'<span style="flex:1;height:24px;border-radius:5px;padding:2px 8px;background:{t["control"]};border:2px solid {t["brand"]}">{E(sh["phrase"])}</span><span style="color:#2BA84A">✓ {E(tr("confirm.type.matched"))}</span></div></div>')
    primary = (f'<span class="btn" style="background:{t["danger"]};color:#fff">{E(tr("confirm.primary.permanent", n))}</span>' if permanent
               else f'<span class="btn" style="background:{t["brand"]};color:#fff">{E(tr("confirm.primary.trash"))}</span>')
    foot = tr("confirm.footer.permanent" if permanent else "confirm.footer.trash")
    return (f'<div class="sheet" style="left:{left}px;background:{t["bg.window"]};color:{t["text.primary"]};font-size:13px">'
            f'<div style="font-size:15px;font-weight:600">{E(title)}</div><div style="color:{t["text.secondary"]};margin-top:4px;font-size:12px">{E(subtitle)}</div>{groups}'
            f'<div style="margin-top:12px;color:{t["text.secondary"]}">{E(tr("confirm.method.label"))}</div>'
            + radio(not permanent, tr("confirm.method.trash"), tr("confirm.method.trashDetail"), t["text.primary"])
            + radio(permanent, tr("confirm.method.permanent"), tr("confirm.method.permanentDetail"), t["danger.text"]) + perm +
            f'<div style="display:flex;align-items:center;gap:8px;margin-top:14px"><span style="flex:1;font-size:11px;color:{t["text.tertiary"]}">{E(foot)}</span>'
            f'<span class="btn" style="background:{t["control"]};border:1px solid {t["separator"]}">{E(tr("button.cancel"))}</span>{primary}</div></div>')

def shoot(htmltext, png, W=1280, H=800):
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
        f.write(htmltext); path = f.name
    subprocess.run(["google-chrome", "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--window-size={W},{H}", f"--screenshot={png}", "file://" + path], check=True, capture_output=True)
    os.unlink(path); print(png)

for mode in ("light", "dark"):
    shoot(window(mode), os.path.join(out, f"simplify-v2-zh-{mode}.png"))
    overlay = '<div class="dim"></div>' + sheet(mode, False, 30) + sheet(mode, True, 650)
    shoot(window(mode, overlay), os.path.join(out, f"delete-confirm-zh-{mode}.png"))
    shoot(window(mode, W=960, H=640, compact=True), os.path.join(out, f"simplify-v2-zh-compact-960x640-{mode}.png"), 960, 640)
    for d in dump["drillCharts"]:
        shoot(drill_labels(mode, d), os.path.join(out, f"drill-labels-k{int(round(d['k'] * 100)):03d}-zh-{mode}.png"), 900, 760)
