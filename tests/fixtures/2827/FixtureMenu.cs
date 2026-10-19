// Written by scripts\mods\Build-StartMenu.py from the game's menu and Thornswood's,
// on a machine with the game. Run it again rather than editing this; an edit here
// fails the launcher's byte for byte check (#2827).
namespace Thornswood
{
    public sealed partial class MenuRecipe
    {
        public static readonly MenuRecipe Fixture = new MenuRecipe
        {
            Archive = "Skyrim - Interface.bsa",
            Source = "interface\\startmenu.swf",
            SourceSize = 293056,
            SourceSha256 = "4c8bf92c1edd0ab4e97f225740b5643ab5f610d2fac5142eee241da25ecb6f26",
            Path = "Data\\Interface\\startmenu.swf",
            Size = 87589,
            Sha256 = "2c53a54b65a5154a902e91b836921c2135c71233ee60c44f26b0ff15a680c466",
            Edits = new[]
            {
                new MenuEdit(4, 1, "9c"), // in the header
                new MenuEdit(6113, 1, "63"), // in DefineShape
                new MenuEdit(6118, 0, "01"), // in DefineShape
                new MenuEdit(6120, 1, "95"), // in DefineShape
                new MenuEdit(6122, 2, ""), // in DefineShape
                new MenuEdit(39707, 1, "62"), // in DefineShape
                new MenuEdit(39712, 0, "01"), // in DefineShape
                new MenuEdit(39714, 1, "b6"), // in DefineShape
                new MenuEdit(39716, 2, ""), // in DefineShape
                new MenuEdit(50768, 1, "48"), // in DefineShape
                new MenuEdit(50773, 0, "01"), // in DefineShape
                new MenuEdit(50775, 1, "28"), // in DefineShape
                new MenuEdit(50777, 2, ""), // in DefineShape
                new MenuEdit(56149, 1, "1f"), // in DefineShape
                new MenuEdit(56154, 0, "01"), // in DefineShape
                new MenuEdit(56156, 1, "4b"), // in DefineShape
                new MenuEdit(56158, 2, ""), // in DefineShape
                new MenuEdit(171570, 1, "13"), // in DefineShape
                new MenuEdit(171575, 0, "01"), // in DefineShape
                new MenuEdit(171577, 1, "f3"), // in DefineShape
                new MenuEdit(171579, 1, ""), // in DefineShape
                new MenuEdit(171593, 1, ""), // in DefineShape
            },
        };
    }
}
