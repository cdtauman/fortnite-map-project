"""Expose the authored UI alphabet to Verse asset reflection."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    data=json.loads((ROOT/'uefn/Art/HebrewUI/glyphs.json').read_text(encoding='utf-8'))
    lines=['# Metrics correspond to the licensed artwork in Art/HebrewUI.','coach_font := class:','    Glyphs : [string]coach_font_glyph = map{']
    for glyph in data['glyphs']:
        symbol=json.dumps(glyph['char'],ensure_ascii=False).replace('{','\\{').replace('}','\\}')
        lines.append('        '+symbol+' => coach_font_glyph{Symbol := '+symbol+', Image := option{Art.HebrewUI.'+glyph['name']+'}, Advance := '+format(glyph['advance'],'.6f')+', RTL := '+str(glyph['rtl']).lower()+', Latin := '+str(glyph['latin']).lower()+'},')
    lines+=['        "\\n" => coach_font_glyph{Symbol := "\\n", BreakLine := true}','    }','']
    (ROOT/'uefn/Verse/coach_font_catalog.verse').write_text('\n'.join(lines),encoding='utf-8')
    (ROOT/'uefn/Verse/coach_asset_modules.verse').write_text('Art := module:\n    HebrewUI<public> := module{}\n    GridKit<public> := module{}\n    TrainingKit<public> := module{}\n    TeachingKit<public> := module{}\n    CoachTools<public> := module{}\n',encoding='utf-8')
    print('Prepared Verse font catalog',len(data['glyphs']))
if __name__=='__main__':main()
