"""Author isolated native-pool layer and sequences without evaluation or gameplay.

New owned assets only. No playback, upload or production enable.
"""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
M='/eda26a53-42c0-4b9e-8f62-31719aef6889'
S='animation_toolset.toolsets.sequencer.SequencerTools'
FOLDER=M+'/Art/NativePool'

async def main():
    path=ROOT/'native-pool188-runtime-assets.json'
    if path.exists():raise RuntimeError('Record exists; inspect actual stage before resuming')
    report={'scope':__doc__,'sequences':{},'gameplay_launched':False}
    def save():path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected level')
        report['existing_game']=await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})
        report['layer']=await call(c,'EditorToolset.LevelToolset','CreateDataLayerAsset',{'assetPath':FOLDER+'/PCL_DL_NativePool','bIsRuntime':True});save()
        for kind,states in [('Unload',[('UNLOADED',0,90)]),('Load',[('LOADED',0,60),('ACTIVATED',60,90)])]:
            seq={'asset':await call(c,S,'create_level_sequence',{'package_path':FOLDER,'asset_name':'PCL_LS_NativePool'+kind}),'sections':[]}
            report['sequences'][kind]=seq;save()
            await call(c,S,'set_display_rate',{'sequence':seq['asset'],'numerator':30,'denominator':1})
            await call(c,S,'set_playback_range',{'sequence':seq['asset'],'start_frame':0,'end_frame':90})
            seq['track']=await call(c,S,'add_track_to_sequence',{'sequence':seq['asset'],'track_type':{'refPath':'/Script/MovieSceneTracks.MovieSceneDataLayerTrack'}});save()
            for state,start,end in states:
                section={'state':state,'start':start,'end':end,'ref':await call(c,S,'add_section',{'track':seq['track']})}
                seq['sections'].append(section);save()
                await call(c,S,'set_section_range',{'section':section['ref'],'start_frame':start,'end_frame':end})
                code='SECTION='+repr(section['ref']['refPath'])+'\nLAYER='+repr(report['layer']['refPath'])+'\nSTATE='+repr(state)+'''\nimport unreal,json
section=unreal.find_object(None,SECTION)
layer=unreal.EditorAssetLibrary.load_asset(LAYER)
if section is None or layer is None:raise RuntimeError('Missing owned section or layer')
section.modify()
section.set_data_layer_assets([layer])
section.set_desired_state(getattr(unreal.DataLayerRuntimeState,STATE))
section.set_preroll_state(getattr(unreal.DataLayerRuntimeState,STATE))
section.set_flush_on_activated(False)
section.set_flush_on_unload(True)
section.set_completion_mode(unreal.MovieSceneCompletionMode.KEEP_STATE)
print(json.dumps({'layers':[x.get_path_name() for x in section.get_data_layer_assets()],'desired':str(section.get_desired_state()),'completion':str(section.get_completion_mode())}))
'''
                section['readback']=json.loads(await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':code,'language':'Python'}}));save()
            await call(c,'EditorToolset.AssetToolset','SaveAsset',{'assetPath':seq['asset']['refPath']})
        await call(c,'EditorToolset.AssetToolset','SaveAsset',{'assetPath':report['layer']['refPath']})
        report['finished']=True;save()
    print(json.dumps({'finished':True,'layer':report['layer'],'sequences':len(report['sequences']),'gameplay_launched':False}),flush=True)

if __name__=='__main__':asyncio.run(main())
