"""Makes every icon the site and the apps use from one drawing, docs/assets/uwuhere-icon.svg:

  main-site/HAT-main.png, HAT-192.png, HAT-512.png, favicon.ico    the site (manifest.json)
  android/app/src/main/res/mipmap-*/ic_launcher*.png               the launcher: square, round, and
                                                                   the adaptive icon's foreground
  android/app/src/main/res/drawable-nodpi/splash_icon.png          the launch screen's
  web/favicon.png, web/icons/*                                     the Playwright suite's browser build
  windows/runner/resources/app_icon.ico                            Windows, 16 to 256 px
  macos/Runner/Assets.xcassets/AppIcon.appiconset                  macOS's rounded square
  assets/images/icon-512.png, icon-256.png                         Linux, the welcome window, widgets
  assets/images/tray.ico, tray.png, tray_template*.png             the tray, and macOS's menu bar

The drawing keeps everything within 375 of 1000 from its centre, so a round crop keeps it all;
the adaptive foreground draws it at 80%, inside Android's 66 of 108 dp safe circle.

    python tool/make_icons.py        (from flutter/, after `npm install` in e2e/)
"""
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
repo = os.path.dirname(root)
svg = os.path.join(repo, 'docs', 'assets', 'uwuhere-icon.svg')
tmp = tempfile.mkdtemp()


def render(size, mode=''):
    out = os.path.join(tmp, f'icon-{size}-{mode or "full"}.png')
    if not os.path.exists(out):
        subprocess.run(['node', os.path.join(here, 'render_svg.mjs'), svg, out, str(size)] + ([mode] if mode else []), check=True)
    return Image.open(out).convert('RGBA')


def rounded(img, radius):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius, fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def circle(img):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, img.width - 1, img.height - 1), fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


big = render(2250)
full = render(1024)
fg = render(1024, 'fg')


def at(img, size):
    return img.resize((size, size), Image.LANCZOS)


# ---- The site ----
site = os.path.join(repo, 'main-site')
big.convert('RGB').save(os.path.join(site, 'HAT-main.png'), optimize=True)
at(full, 512).convert('RGB').save(os.path.join(site, 'HAT-512.png'), optimize=True)
at(full, 192).convert('RGB').save(os.path.join(site, 'HAT-192.png'), optimize=True)
at(full, 256).save(os.path.join(site, 'favicon.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

# ---- Android's launcher ----
res = os.path.join(root, 'android', 'app', 'src', 'main', 'res')
for density, scale in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
    d = os.path.join(res, f'mipmap-{density}')
    os.makedirs(d, exist_ok=True)
    legacy = round(48 * scale)
    at(full, legacy).save(os.path.join(d, 'ic_launcher.png'))
    circle(at(full, legacy)).save(os.path.join(d, 'ic_launcher_round.png'))
    at(fg, round(108 * scale)).save(os.path.join(d, 'ic_launcher_foreground.png'))
os.makedirs(os.path.join(res, 'drawable-nodpi'), exist_ok=True)
circle(at(full, 288)).save(os.path.join(res, 'drawable-nodpi', 'splash_icon.png'))

# ---- The browser build (the Playwright suite) ----
web = os.path.join(root, 'web')
at(full, 32).save(os.path.join(web, 'favicon.png'))
at(full, 192).save(os.path.join(web, 'icons', 'Icon-192.png'))
at(full, 512).save(os.path.join(web, 'icons', 'Icon-512.png'))
at(full, 192).save(os.path.join(web, 'icons', 'Icon-maskable-192.png'))
at(full, 512).save(os.path.join(web, 'icons', 'Icon-maskable-512.png'))

# ---- Windows ----
rounded(at(full, 256), 48).save(os.path.join(root, 'windows', 'runner', 'resources', 'app_icon.ico'),
                                sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

# ---- macOS: the rounded square on a transparent margin, as macOS icons are drawn (824 of 1024) ----
mac = os.path.join(root, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
shadow = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle((100, 112, 924, 936), radius=185, fill=(0, 0, 0, 70))
canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(12)))
inner = rounded(at(full, 824), 185)
canvas.paste(inner, (100, 100), inner)
for s in (16, 32, 64, 128, 256, 512, 1024):
    at(canvas, s).save(os.path.join(mac, f'app_icon_{s}.png'))

# ---- Linux, the welcome window, the widgets ----
images = os.path.join(root, 'assets', 'images')
rounded(at(full, 512), 96).save(os.path.join(images, 'icon-512.png'))
rounded(at(full, 256), 48).save(os.path.join(images, 'icon-256.png'))

# ---- The tray: the figure and its tick without the backdrop, which reads at 16 px ----
figure = render(1024, 'fg')
box = figure.getbbox()
side = max(box[2] - box[0], box[3] - box[1])
cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
tray = figure.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2))
at(tray, 256).save(os.path.join(images, 'tray.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64)])
at(tray, 64).save(os.path.join(images, 'tray.png'))

# macOS's menu bar: a template image, black where the figure is, which macOS tints to fit the bar.
# The face and the tick are cut out, so it's still the logo at 22 px.
t = at(tray, 88)
px = t.load()
tmpl = Image.new('RGBA', t.size, (0, 0, 0, 0))
tp = tmpl.load()
for y in range(t.height):
    for x in range(t.width):
        r, g, b, a = px[x, y]
        if a < 40:
            continue
        light = (r + g + b) / 3
        # The tick (near white) and the face's features stay clear; the rest is the shape.
        if light > 215 or (r < 180 and g < 110 and b < 80):
            continue
        tp[x, y] = (0, 0, 0, a)
at(tmpl, 44).save(os.path.join(images, 'tray_template.png'))
at(tmpl, 22).save(os.path.join(images, 'tray_template@1x.png'))
print('icons written')
