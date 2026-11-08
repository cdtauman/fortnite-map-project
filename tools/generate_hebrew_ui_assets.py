"""Prepare licensed, resolution-independent source typography for the island UI."""
import hashlib,json,string,urllib.request
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'uefn/Art/HebrewUI'
FONT_DIR=ROOT/'uefn/Art/Fonts/Heebo'
SOURCE='https://raw.githubusercontent.com/google/fonts/main/ofl/heebo/'

def main():
    FOLDER.mkdir(parents=True,exist_ok=True);FONT_DIR.mkdir(parents=True,exist_ok=True)
    for local,remote in [('Heebo.ttf','Heebo%5Bwght%5D.ttf'),('OFL.txt','OFL.txt')]:
        target=FONT_DIR/local
        if not target.exists():
            with urllib.request.urlopen(SOURCE+remote,timeout=30) as response:
                target.write_bytes(response.read())
    font=ImageFont.truetype(str(FONT_DIR/'Heebo.ttf'),64)
    font.set_variation_by_name('Medium')
    chars=string.ascii_letters+string.digits+string.punctuation+' '+''.join(chr(n) for n in range(0x5D0,0x5EB))+'׳״־–—…’‘“”×'
    chars=list(dict.fromkeys(chars))
    glyphs=[]
    for char in chars:
        advance=font.getlength(char)
        name='PCL_Glyph_'+format(ord(char),'04X')
        # Fixed baseline and line height keep final letters, numbers and capitals aligned.
        # Texture imports use power-of-two dimensions; layout uses the advance, not this padding.
        width=128
        img=Image.new('RGBA',(width,128),(255,255,255,0))
        ImageDraw.Draw(img).text((1,64),char,font=font,fill='white',anchor='ls')
        img.save(FOLDER/(name+'.png'))
        glyphs.append(dict(char=char,name=name,advance=advance,width=width,height=128,rtl=0x5D0<=ord(char)<=0x5EA,latin=char.isascii() and char.isalnum()))
    manifest={'reference_size':64,'line_height':84,'font_source':SOURCE+'Heebo%5Bwght%5D.ttf','font_sha256':hashlib.sha256((FONT_DIR/'Heebo.ttf').read_bytes()).hexdigest(),'license':'../Fonts/Heebo/OFL.txt','glyphs':glyphs}
    (FOLDER/'glyphs.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'glyphs':len(glyphs),'artwork_bytes':sum(p.stat().st_size for p in FOLDER.glob('*.png')),'game_launched':False}))

if __name__=='__main__':main()
