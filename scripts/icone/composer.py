# Compose les icônes macOS (toile 1024, squircle 824) à partir des rendus Blender transparents.
import sys, json, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops
D = os.path.dirname(os.path.abspath(__file__))
S = 4  # sur-échantillonnage

def squircle_mask(size, body, n=5.0):
    big = size * S; r = body * S / 2; c = big / 2
    import numpy as np
    ys, xs = np.mgrid[0:big, 0:big]
    v = (np.abs(xs + 0.5 - c) / r) ** n + (np.abs(ys + 0.5 - c) / r) ** n
    m = Image.fromarray(((v <= 1) * 255).astype('uint8'), 'L')
    return m.resize((size, size), Image.LANCZOS)

def gradient(size, top, bot):
    g = Image.new('RGB', (size, size))
    px = []
    for y in range(size):
        t = y / (size - 1)
        px.append(tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    col = Image.new('RGB', (1, size)); col.putdata(px)
    return col.resize((size, size))

def perso(path, target=620):
    im = Image.open(path).convert('RGBA')
    a = im.getchannel('A').point(lambda v: 255 if v > 140 else 0)  # sans la douce ombre, pour cadrer
    bb = a.getbbox(); im = im.crop(bb)
    k = target / max(im.size); im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    return im

def icone(rendu, fond, out, size=1024, body=824):
    mask = squircle_mask(size, body)
    if fond == 'noir':
        base = gradient(size, (0x32, 0x32, 0x35), (0x07, 0x07, 0x08))
    else:
        base = gradient(size, (0xFF, 0xFF, 0xFF), (0xEC, 0xEE, 0xF3))
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    # ombre portée du corps
    sh = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    sh.putalpha(mask.point(lambda v: int(v * 0.30)))
    sh = sh.filter(ImageFilter.GaussianBlur(14)); sh = ImageChops.offset(sh, 0, 10)
    canvas.alpha_composite(sh)
    body_im = base.convert('RGBA'); body_im.putalpha(mask)
    if fond == 'blanc':  # fine bordure
        edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(5)))
        border = Image.new('RGBA', (size, size), (0xC9, 0xCC, 0xD6, 255)); border.putalpha(edge)
        body_im.alpha_composite(border)
    else:
        edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(3)))
        border = Image.new('RGBA', (size, size), (255, 255, 255, 28)); border.putalpha(edge.point(lambda v: v * 28 // 255))
        body_im.alpha_composite(border)
    canvas.alpha_composite(body_im)
    p = perso(rendu)
    shadow_full = Image.open(rendu).convert('RGBA')
    x = (size - p.width) // 2; y = (size - p.height) // 2 + 16
    # ombre de contact fournie par Blender : on recadre pareil que le perso, avec marge
    a = shadow_full.getchannel('A').point(lambda v: 255 if v > 140 else 0); bb = a.getbbox()
    k = p.width / (bb[2] - bb[0])
    full = shadow_full.resize((round(1024 * k), round(1024 * k)), Image.LANCZOS)
    ox = x - round(bb[0] * k); oy = y - round(bb[1] * k)
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0)); layer.alpha_composite(full, (max(ox, 0), max(oy, 0)), (max(-ox, 0), max(-oy, 0))) if False else None
    tmp = Image.new('RGBA', (size, size), (0, 0, 0, 0)); tmp.paste(full, (ox, oy))
    # l'ombre de contact reste dans le corps
    if fond == 'blanc':  # ombre de sol plus légère sur fond clair
        tmp.putalpha(tmp.getchannel('A').point(lambda v: v if v >= 200 else int(v * 0.45)))
    tmp.putalpha(ImageChops.multiply(tmp.getchannel('A'), mask))
    canvas.alpha_composite(tmp)
    canvas.save(out)
    return canvas

if __name__ == '__main__':
    # rendu Blender (modele.py) -> maître de l'icône, fond blanc ; puis swift scripts/icone.swift
    rendu = sys.argv[1] if len(sys.argv) > 1 else f'{D}/tmp/rendu.png'
    icone(rendu, 'blanc', f'{D}/icone-1024.png')
