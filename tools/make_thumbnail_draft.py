"""Draft Discover thumbnail (spec v1 step 3.1): editor capture of the real 1V1 arena start
(two back-to-back ramps) with title text. 1920x1080, no weapons, no Epic art, no XP/AFK/coins."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageEnhance
ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / 'uefn/Art/Fonts/Heebo/Heebo.ttf'

def font(size, weight='Black'):
    f = ImageFont.truetype(str(FONT), size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        f.set_variation_by_name('Bold')
    return f

def main(source='C:/tmp/pcl_signs/duel_a.png', out=ROOT / 'docs/images/thumbnail-draft-v1.png'):
    im = Image.open(source).convert('RGB').resize((1920, 1080))
    im = ImageEnhance.Contrast(im).enhance(1.15)
    shade = Image.new('RGBA', im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(shade)
    for y in range(0, 470):
        d.line([(0, y), (1920, y)], fill=(6, 14, 22, int(215 * (1 - y / 470))))
    im = Image.alpha_composite(im.convert('RGBA'), shade)
    d = ImageDraw.Draw(im)
    def outlined(xy, text, f, fill):
        x, y = xy
        for dx in (-5, 0, 5):
            for dy in (-5, 0, 5):
                d.text((x + dx, y + dy), text, font=f, fill=(5, 10, 16), anchor='mm')
        d.text((x, y), text, font=f, fill=fill, anchor='mm')
    outlined((960, 150), '1V1 BUILD FIGHTS', font(150), (255, 255, 255))
    outlined((960, 290), 'COACH REVIEW AFTER EVERY ROUND', font(64, 'Bold'), (255, 196, 64))
    outlined((960, 1010), 'EDIT COURSES  •  FREE BUILD  •  PICK YOUR LOADOUT', font(48, 'Bold'), (120, 235, 230))
    im.convert('RGB').save(out, optimize=True)
    print('saved', out, Path(out).stat().st_size // 1024, 'KB')

if __name__ == '__main__':
    main()
