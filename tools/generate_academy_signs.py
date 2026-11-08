"""Prepare bilingual wayfinding artwork using the bundled licensed typeface."""
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'uefn/Art/AcademySigns'
FONT=ROOT/'uefn/Art/Fonts/Heebo/Heebo.ttf'
SIGNS=[('Personal','מאמן אישי','PERSONAL COACH','01'),('Duel','אחד על אחד','1V1 ARENA','02'),('FreeBuild','בנייה חופשית','FREE BUILD','03'),('EditTraining','אימון עריכות','EDIT TRAINING','04'),('Return','חזרה ללובי','RETURN TO LOBBY',''),('Academy','האקדמיה לאימון אישי','PROCOACH ACADEMY','')]
def main():
    FOLDER.mkdir(parents=True,exist_ok=True)
    specs=[]
    def font(size):
        f=ImageFont.truetype(str(FONT),size);f.set_variation_by_name('Medium');return f
    for kind,hebrew,english,number in SIGNS:
        im=Image.new('RGB',(1024,512),(8,17,24));draw=ImageDraw.Draw(im)
        accent=(239,178,82) if kind in ['Duel','EditTraining'] else (57,219,218)
        draw.line([(56,52),(968,52)],fill=accent,width=4)
        draw.line([(56,456),(968,456)],fill=(40,59,68),width=2)
        if number:draw.text((512,130),number,font=font(40),fill=accent,anchor='mm')
        title_size=min(98,int(875/max(1,len(hebrew))/.56))
        draw.text((512,239),hebrew[::-1],font=font(title_size),fill=(242,246,246),anchor='mm')
        draw.text((512,346),english,font=font(35),fill=accent,anchor='mm')
        filename='PCL_Sign_'+kind+'.png';im.save(FOLDER/filename)
        specs.append({'name':'PCL_Sign_'+kind,'mode':kind,'file':filename,'hebrew':hebrew,'english':english})
    (FOLDER/'signs.json').write_text(json.dumps(specs,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Prepared bilingual wayfinding artwork',len(specs))
if __name__=='__main__':main()
