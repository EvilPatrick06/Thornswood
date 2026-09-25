{
  GourmetFishingVanilla.pas

  Repoints every recipe in GourmetFishing.esp from the Creation Club's fish to
  vanilla Skyrim's, so the plugin no longer needs ccBGSSSE001-Fish.esm and
  everybody can use it on plain Special Edition.

  HOW TO RUN IT

    1. The Creation Club fishing esm has to be present for xEdit to open the
       plugin at all, because it is still a master at this point. Yours is in
         Skyrim Special Edition\_DowngraderBackups\20260910-140530\Data\
       Copy ccBGSSSE001-Fish.esm into your Data folder and enable it.
    2. Put this file in  SSEEdit\Edit Scripts\
    3. Open SSEEdit, tick Skyrim.esm, Update.esm, ccBGSSSE001-Fish.esm,
       Gourmet.esp and GourmetFishing.esp. Nothing else is needed.
    4. Right click GourmetFishing.esp, Apply Script, pick this one.
    5. It prints what it changed. Save.
    6. In the file header, remove ccBGSSSE001-Fish.esm from the master list.
       xEdit will let you once the last reference is gone, which is what this
       script is for.
    7. Take ccBGSSSE001-Fish.esm back out of Data.

  WHAT IT DOES NOT DO

    It does not set the ESL flag. Do that yourself in the file header once you
    are happy, because flagging a plugin ESL renumbers its own records and is
    worth doing deliberately rather than in a script.
}
unit GourmetFishingVanilla;

var
  gSrc, gDst: TStringList;
  gChanged, gSkipped: integer;

function Initialize: integer;
begin
  gChanged := 0;
  gSkipped := 0;
  gSrc := TStringList.Create;
  gDst := TStringList.Create;

  // Creation Club ingredient  ->  the vanilla Skyrim record that replaces it.
  // Matched on editor id, so it does not matter where anything sits in the
  // load order when you run this.
  gSrc.Add('ccBGSSSE001_FoodSalmon');          gDst.Add('FoodSalmon [ALCH:00065C9F]');
  gSrc.Add('ccBGSSSE001_FoodSlaughterfish');   gDst.Add('FoodSlaughterfishCooked [ALCH:00064B3C]');
  gSrc.Add('ccBGSSSE001_FoodTunaSalmon');      gDst.Add('FoodSalmonCooked [ALCH:00064B3B]');
  gSrc.Add('ccBGSSSE001_FoodCrabMeat');        gDst.Add('FoodClamMeat [ALCH:000EBA03]');
  gSrc.Add('ccBGSSSE001_FoodCarp');            gDst.Add('CritterPondFish01Ingredient [INGR:00106E1C]');
  gSrc.Add('ccBGSSSE001_FoodCuckooCatfish');   gDst.Add('CritterPondFish02Ingredient [INGR:00106E1B]');
  gSrc.Add('ccBGSSSE001_FoodGlassCatfish');    gDst.Add('CritterPondFish03Ingredient [INGR:00106E1A]');
  gSrc.Add('ccBGSSSE001_FoodAtlanticCod');     gDst.Add('CritterPondFish04Ingredient [INGR:00106E19]');
  gSrc.Add('ccBGSSSE001_FoodArcticChar');      gDst.Add('CritterPondFish05Ingredient [INGR:00106E18]');
  gSrc.Add('ccBGSSSE001_FoodArcticGrayling');  gDst.Add('CritterPondFish01Ingredient [INGR:00106E1C]');
  gSrc.Add('ccBGSSSE001_FoodCabezon');         gDst.Add('CritterPondFish02Ingredient [INGR:00106E1B]');
  gSrc.Add('ccBGSSSE001_FoodDragonfish');      gDst.Add('CritterPondFish03Ingredient [INGR:00106E1A]');
  gSrc.Add('ccBGSSSE001_FoodAngler');          gDst.Add('CritterPondFish04Ingredient [INGR:00106E19]');
  gSrc.Add('ccBGSSSE001_FoodTripodFish');      gDst.Add('CritterPondFish05Ingredient [INGR:00106E18]');
  gSrc.Add('ccBGSSSE001_FoodBucketFish');      gDst.Add('CritterPondFish01Ingredient [INGR:00106E1C]');
  gSrc.Add('ccBGSSSE001_FoodVampireFish');     gDst.Add('CritterPondFish02Ingredient [INGR:00106E1B]');
  gSrc.Add('ccBGSSSE001_AngelfishIng');        gDst.Add('CritterPondFish01Ingredient [INGR:00106E1C]');
  gSrc.Add('ccBGSSSE001_PearlfishIng');        gDst.Add('CritterPondFish02Ingredient [INGR:00106E1B]');
  gSrc.Add('ccBGSSSE001_PygmySunfishIng');     gDst.Add('CritterPondFish03Ingredient [INGR:00106E1A]');
  gSrc.Add('ccBGSSSE001_GlassfishIng');        gDst.Add('CritterPondFish04Ingredient [INGR:00106E19]');
  gSrc.Add('ccBGSSSE001_GoldfishIng');         gDst.Add('CritterPondFish05Ingredient [INGR:00106E18]');
  gSrc.Add('ccBGSSSE001_LyretailAnthiasIng');  gDst.Add('CritterPondFish01Ingredient [INGR:00106E1C]');
  gSrc.Add('ccBGSSSE001_PinnateSpadefishIng'); gDst.Add('CritterPondFish02Ingredient [INGR:00106E1B]');
  gSrc.Add('ccBGSSSE001_AnglerLarvaeIng');     gDst.Add('SlaughterfishEgg01 [INGR:0007E8C5]');
  gSrc.Add('ccBGSSSE001_JuvenileMudcrabIng');  gDst.Add('SlaughterfishScales [INGR:0003AD70]');

  AddMessage('GourmetFishingVanilla: ' + IntToStr(gSrc.Count) + ' ingredient swaps loaded.');
  Result := 0;
end;

// Returns the replacement for whatever this reference currently points at,
// or an empty string when it is not one of ours and should be left alone.
function Replacement(cur: string): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to Pred(gSrc.Count) do
    if Pos(gSrc[i], cur) > 0 then begin
      Result := gDst[i];
      Exit;
    end;
end;

// Walks every element under a record and swaps any reference we recognise.
// Done by walking rather than by naming CNTO directly, so the perks, the
// loot lists and the food records get caught as well as the recipes.
procedure Walk(e: IInterface);
var
  i: integer;
  cur, rep: string;
begin
  cur := GetEditValue(e);
  if cur <> '' then begin
    rep := Replacement(cur);
    if rep <> '' then begin
      try
        SetEditValue(e, rep);
        AddMessage('  ' + Name(e) + '  ' + cur + '  ->  ' + rep);
        Inc(gChanged);
      except
        on E: Exception do begin
          AddMessage('  COULD NOT SET  ' + Name(e) + '  ' + cur + '  (' + E.Message + ')');
          Inc(gSkipped);
        end;
      end;
    end;
  end;
  for i := 0 to Pred(ElementCount(e)) do
    Walk(ElementByIndex(e, i));
end;

function Process(e: IInterface): integer;
begin
  Result := 0;
  if Signature(e) = 'TES4' then Exit;
  Walk(e);
end;

function Finalize: integer;
begin
  AddMessage('');
  AddMessage('GourmetFishingVanilla finished. ' + IntToStr(gChanged) + ' reference(s) repointed, '
             + IntToStr(gSkipped) + ' could not be set.');
  AddMessage('Now remove ccBGSSSE001-Fish.esm from the file header master list, then save.');
  gSrc.Free;
  gDst.Free;
  Result := 0;
end;

end.
