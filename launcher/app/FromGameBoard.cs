// Written by scripts\mods\Build-NoticeBoard.py, from its PARTS and the blocks it
// draws itself, on a machine with the game. Change the script and run it again;
// an edit here is lost and fails the launcher's byte for byte check (#2827).
namespace Thornswood
{
    public sealed partial class BoardRecipe
    {
        public static readonly BoardRecipe Shipped = new BoardRecipe
        {
            Archives = new[] { "Skyrim - Meshes0.bsa", "Skyrim - Meshes1.bsa" },
            // each of the game's meshes the two are made from, as this game had it
            Sources = new BoardSource[]
            {
                new BoardSource("meshes\\clutter\\signage\\windhelm\\signwhpost01.nif", 8793, "d815587bd88e2df62771f5fa44570e49f40110c50ca31b6f28ccf06535643978"),
                new BoardSource("meshes\\clutter\\stockade\\stockadefreewall01.nif", 8963, "3771d010d3f4d66749e1227424b87d8054851de0b40cb3897e5c05ffe357eb27"),
                new BoardSource("meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif", 6685, "299cad5fd2b6775b7485008a3b6c249e6d73dd7648a1a8802c0ba64d381b453d"),
                new BoardSource("meshes\\architecture\\shackkit\\shackroofside01.nif", 2182, "57c6cb595d214525a437d9751079e7cadab349204673a3b64f3b313259c728fd"),
                new BoardSource("meshes\\clutter\\common\\candlelanternwithcandle01.nif", 40217, "af936b61381d3771495a547e6f079848b41a84e26cd493dcbf7829cf0ce89f65"),
                new BoardSource("meshes\\clutter\\books\\note01.nif", 8159, "72baed7c6797855e68c29e1ba2f70c2cfbdb4762c09dda9ac67cca8c2c2ea9c4"),
                new BoardSource("meshes\\clutter\\books\\notetornpaper.nif", 6437, "47a637619c138d8a4e5ec360a3492b9d863ace637f5403b29af4ffc2c7eaa732"),
                new BoardSource("meshes\\clutter\\books\\note02.nif", 8528, "8faa14335d6fb2c609c40374bc2220204b2c9752dd85e2d61e79a39d2fd14d87"),
                new BoardSource("meshes\\clutter\\books\\note04.nif", 8159, "f73661e0c438b6e9941fde0461a163caa3718008621c7a1104bee1d00f39085c"),
                new BoardSource("meshes\\clutter\\books\\note03.nif", 8528, "ea028559d1f5b086f5723da3e7c1a0636d684525c991368307ef687a30d9e0bb"),
                new BoardSource("meshes\\clutter\\shipwreck\\shipwreckboards01.nif", 3282, "6e62c78cf2822b360b67b1cce0318f086ad1712dcfe7e8826ab03fbc2df9a0db"),
                new BoardSource("meshes\\architecture\\solitude\\clutter\\smarketstalltop.nif", 64299, "6407b5e7e4199b56a85ac83438b52587ee2e18756aa8b2fb0c1ae3abe135c2b2"),
                new BoardSource("meshes\\clutter\\common\\strongbox01.nif", 28235, "19dab7ec96df687f9dbb17e7c198c1eb0b52347f84278142921042363dcf3038"),
            },
            Parts = new[]
            {
                new BoardPart("Post", "meshes\\clutter\\signage\\windhelm\\signwhpost01.nif", // turned 0, 0, 0 degrees about x, y and z
                    new double[] { 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 1.05, 1.05, 1.18 }, new double[] { -92.0, 0.0, 0.0 }),
                new BoardPart("Post", "meshes\\clutter\\signage\\windhelm\\signwhpost01.nif", // turned 0, 0, 0 degrees about x, y and z
                    new double[] { 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 1.05, 1.05, 1.18 }, new double[] { 92.0, 0.0, 0.0 }),
                new BoardPart("Face", "meshes\\clutter\\stockade\\stockadefreewall01.nif", // turned 0, 0, 0 degrees about x, y and z
                    new double[] { 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 0.7, 0.7, 0.7 }, new double[] { -90.4146, 3.6651, 53.9283 }),
                new BoardPart("TopRail", "meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif", // turned 0, 0, 90 degrees about x, y and z
                    new double[] { 6.123233995736766e-17, -1.0, 0.0, 1.0, 6.123233995736766e-17, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 0.95, 1.4, 0.95 }, new double[] { 0.0, -11.6461, 187.876 }),
                new BoardPart("BottomRail", "meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif", // turned 0, 0, 90 degrees about x, y and z
                    new double[] { 6.123233995736766e-17, -1.0, 0.0, 1.0, 6.123233995736766e-17, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 0.95, 1.4, 0.95 }, new double[] { 0.0, -11.6461, 56.0 }),
                new BoardPart("Roof", "meshes\\architecture\\shackkit\\shackroofside01.nif", // turned 0, 0, 180 degrees about x, y and z
                    new double[] { -1.0, -1.2246467991473532e-16, 0.0, 1.2246467991473532e-16, -1.0, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 0.86, 0.52, 0.4 }, new double[] { 0.0, -1.8538, 116.9737 }),
                new BoardPart("Roof", "meshes\\architecture\\shackkit\\shackroofside01.nif", // turned 0, 0, 0 degrees about x, y and z
                    new double[] { 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 0.86, 0.52, 0.4 }, new double[] { 0.0, 1.8538, 116.9737 }),
                new BoardPart("LanternBracket", "meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif", // turned 0, 0, 90 degrees about x, y and z
                    new double[] { 6.123233995736766e-17, -1.0, 0.0, 1.0, 6.123233995736766e-17, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 0.55, 0.36, 0.55 }, new double[] { -113.8082, 0.0, 206.0 }),
                new BoardPart("Lantern", "meshes\\clutter\\common\\candlelanternwithcandle01.nif", // turned 0, 0, 0 degrees about x, y and z
                    new double[] { 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 1.0, 1.0, 1.0 }, new double[] { -130.6979, 0.2446, 159.4178 }),
                new BoardPart("Note", "meshes\\clutter\\books\\note01.nif", // turned 90, -4, 0 degrees about x, y and z
                    new double[] { 0.9975640502598242, -0.0697564737441253, -4.2713521145274716e-18, 0.0, 6.123233995736766e-17, -1.0, 0.0697564737441253, 0.9975640502598242, 6.108318105475815e-17 },
                    new double[] { 2.2, 2.2, 2.2 }, new double[] { -56.8055, -0.3503, 146.2702 }),
                new BoardPart("Note", "meshes\\clutter\\books\\notetornpaper.nif", // turned 90, 3, 0 degrees about x, y and z
                    new double[] { 0.9986295347545738, 0.052335956242943835, 3.204653064661855e-18, 0.0, 6.123233995736766e-17, -1.0, -0.052335956242943835, 0.9986295347545738, 6.114842316355997e-17 },
                    new double[] { 2.2, 2.2, 2.2 }, new double[] { -21.4435, -1.3009, 135.9732 }),
                new BoardPart("Note", "meshes\\clutter\\books\\note02.nif", // turned 90, -2, 0 degrees about x, y and z
                    new double[] { 0.9993908270190958, -0.03489949670250097, -2.136977846428571e-18, 0.0, 6.123233995736766e-17, -1.0, 0.03489949670250097, 0.9993908270190958, 6.119503887030809e-17 },
                    new double[] { 2.2, 2.2, 2.2 }, new double[] { 15.5093, -0.6503, 148.3532 }),
                new BoardPart("Note", "meshes\\clutter\\books\\note04.nif", // turned 90, 5, 0 degrees about x, y and z
                    new double[] { 0.9961946980917455, 0.08715574274765817, 5.336750069161486e-18, 0.0, 6.123233995736766e-17, -1.0, -0.08715574274765817, 0.9961946980917455, 6.099933241728101e-17 },
                    new double[] { 2.2, 2.2, 2.2 }, new double[] { 55.4836, -0.8003, 139.9631 }),
                new BoardPart("Note", "meshes\\clutter\\books\\note03.nif", // turned 90, 2, 0 degrees about x, y and z
                    new double[] { 0.9993908270190958, 0.03489949670250097, 2.136977846428571e-18, 0.0, 6.123233995736766e-17, -1.0, -0.03489949670250097, 0.9993908270190958, 6.119503887030809e-17 },
                    new double[] { 2.2, 2.2, 2.2 }, new double[] { -52.3024, -0.9503, 93.395 }),
                new BoardPart("Note", "meshes\\clutter\\books\\notetornpaper.nif", // turned 90, -3, 0 degrees about x, y and z
                    new double[] { 0.9986295347545738, -0.052335956242943835, -3.204653064661855e-18, 0.0, 6.123233995736766e-17, -1.0, 0.052335956242943835, 0.9986295347545738, 6.114842316355997e-17 },
                    new double[] { 2.2, 2.2, 2.2 }, new double[] { -12.6061, -1.9009, 96.4548 }),
                new BoardPart("Note", "meshes\\clutter\\books\\note01.nif", // turned 90, 4, 0 degrees about x, y and z
                    new double[] { 0.9975640502598242, 0.0697564737441253, 4.2713521145274716e-18, 0.0, 6.123233995736766e-17, -1.0, -0.0697564737441253, 0.9975640502598242, 6.108318105475815e-17 },
                    new double[] { 2.2, 2.2, 2.2 }, new double[] { 24.6941, -1.2503, 93.3798 }),
                new BoardPart("Note", "meshes\\clutter\\books\\note02.nif", // turned 90, -3, 0 degrees about x, y and z
                    new double[] { 0.9986295347545738, -0.052335956242943835, -3.204653064661855e-18, 0.0, 6.123233995736766e-17, -1.0, 0.052335956242943835, 0.9986295347545738, 6.114842316355997e-17 },
                    new double[] { 2.2, 2.2, 2.2 }, new double[] { 60.1875, -1.4003, 96.4912 }),
                new BoardPart("BoxShelf", "meshes\\clutter\\shipwreck\\shipwreckboards01.nif", // turned 0, 0, 90 degrees about x, y and z
                    new double[] { 6.123233995736766e-17, -1.0, 0.0, 1.0, 6.123233995736766e-17, 0.0, 0.0, 0.0, 1.0 },
                    new double[] { 3.4, 0.36, 1.6 }, new double[] { 132.5203, -4.0, 76.8 }),
                new BoardPart("Strut", "meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif", // turned -45, 0, 90 degrees about x, y and z
                    new double[] { 6.123233995736766e-17, -0.7071067811865476, -0.7071067811865476, 1.0, 4.329780281177467e-17, 4.329780281177467e-17, 0.0, -0.7071067811865476, 0.7071067811865476 },
                    new double[] { 0.45, 0.36, 0.45 }, new double[] { 117.3618, -4.0, 54.2656 }),
            },
            Box = new BoardPart("DropBox", "meshes\\clutter\\common\\strongbox01.nif", // turned 0, 0, 0 degrees about x, y and z
                new double[] { 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 },
                new double[] { 1.8, 1.8, 1.8 }, new double[] { 134.5203, -4.0, 79.9167 }),
            NailSource = "meshes\\architecture\\solitude\\clutter\\smarketstalltop.nif",
            NailTexture = "snail01",
            BodyBoard = "meshes\\clutter\\signage\\windhelm\\signwhpost01.nif",
            BodyBox = "meshes\\clutter\\common\\strongbox01.nif",
            BoardRoot = "ThornswoodNoticeBoard01",
            BoxRoot = "ThornswoodDropBox01",
            NailHeads = "IQAAAAAAAAD/////DgAIAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAgD//////" +
                "ghDFvwlHG0CJ0QJD5R2DQv////9rAAAA/////wgEZQcAsAMAYADAAEAaAAB8DF9CkvJMP9LaHUMAAAAAXDXPN4CA////gICA" +
                "/////xWmaEKS8kw/0todQwAAAAASN883gID///+AgID/////FaZoQnys2T/S2h1DAAAAABI3ADaAgP///4CAgP////98DF9C" +
                "fKzZP9LaHUMAAAAAXDUANoCA////gICA/////3wMX0J8rNk/bHQbQwAAAABcNc83gIAAAP+AgID/////FaZoQnys2T9sdBtD" +
                "AAAAABI3zzeAgAAA/4CAgP////8VpmhCkvJMP2x0G0MAAAAAEjcANoCAAAD/gICA/////3wMX0KS8kw/bHQbQwAAAABcNQA2" +
                "gIAAAP+AgID/////FaZoQpLyTD9sdBtDAAAAAFw1zzf/gICAgP+A//////8VpmhCfKzZP2x0G0MAAAAAEjfPN/+AgICA/4D/" +
                "/////xWmaEJ8rNk/0todQwAAAAASNwA2/4CAgID/gP//////FaZoQpLyTD/S2h1DAAAAAFw1ADb/gICAgP+A//////98DF9C" +
                "fKzZP2x0G0MAAAAAXDXPNwCAgICAAID//////3wMX0KS8kw/bHQbQwAAAAASN883AICAgIAAgP//////fAxfQpLyTD/S2h1D" +
                "AAAAABI3ADYAgICAgACA//////98DF9CfKzZP9LaHUMAAAAAXDUANgCAgICAAID//////xWmaEJ8rNk/bHQbQwAAAABcNc83" +
                "gP+AgACAgP//////fAxfQnys2T9sdBtDAAAAABI3zzeA/4CAAICA//////98DF9CfKzZP9LaHUMAAAAAEjcANoD/gIAAgID/" +
                "/////xWmaEJ8rNk/0todQwAAAABcNQA2gP+AgACAgP//////fAxfQpLyTD9sdBtDAAAAAFw1zzeAAICA/4CA//////8VpmhC" +
                "kvJMP2x0G0MAAAAAEjfPN4AAgID/gID//////xWmaEKS8kw/0todQwAAAAASNwA2gACAgP+AgP//////fAxfQpLyTD/S2h1D" +
                "AAAAAFw1ADaAAICA/4CA//////+K06JBbVEjQKZwH0MAAAAAXDXPN4CA////gICA/////70GtkFtUSNApnAfQwAAAAASN883" +
                "gID///+AgID/////vQa2QQfrXECmcB9DAAAAABI3ADaAgP///4CAgP////+K06JBB+tcQKZwH0MAAAAAXDUANoCA////gICA" +
                "/////4rTokEH61xAQAodQwAAAABcNc83gIAAAP+AgID/////vQa2QQfrXEBACh1DAAAAABI3zzeAgAAA/4CAgP////+9BrZB" +
                "bVEjQEAKHUMAAAAAEjcANoCAAAD/gICA/////4rTokFtUSNAQAodQwAAAABcNQA2gIAAAP+AgID/////vQa2QW1RI0BACh1D" +
                "AAAAAFw1zzf/gICAgP+A//////+9BrZBB+tcQEAKHUMAAAAAEjfPN/+AgICA/4D//////70GtkEH61xApnAfQwAAAAASNwA2" +
                "/4CAgID/gP//////vQa2QW1RI0CmcB9DAAAAAFw1ADb/gICAgP+A//////+K06JBB+tcQEAKHUMAAAAAXDXPNwCAgICAAID/" +
                "/////4rTokFtUSNAQAodQwAAAAASN883AICAgIAAgP//////itOiQW1RI0CmcB9DAAAAABI3ADYAgICAgACA//////+K06JB" +
                "B+tcQKZwH0MAAAAAXDUANgCAgICAAID//////70GtkEH61xAQAodQwAAAABcNc83gP+AgACAgP//////itOiQQfrXEBACh1D" +
                "AAAAABI3zzeA/4CAAICA//////+K06JBB+tcQKZwH0MAAAAAEjcANoD/gIAAgID//////70GtkEH61xApnAfQwAAAABcNQA2" +
                "gP+AgACAgP//////itOiQW1RI0BACh1DAAAAAFw1zzeAAICA/4CA//////+9BrZBbVEjQEAKHUMAAAAAEjfPN4AAgID/gID/" +
                "/////70GtkFtUSNApnAfQwAAAAASNwA2gACAgP+AgP//////itOiQW1RI0CmcB9DAAAAAFw1ADaAAICA/4CA///////7woTB" +
                "sN+MP4JkH0MAAAAAXDXPN4CA////gICA/////5AfY8Gw34w/gmQfQwAAAAASN883gID///+AgID/////kB9jwXEJAECCZB9D" +
                "AAAAABI3ADaAgP///4CAgP/////7woTBcQkAQIJkH0MAAAAAXDUANoCA////gICA//////vChMFxCQBAHP4cQwAAAABcNc83" +
                "gIAAAP+AgID/////kB9jwXEJAEAc/hxDAAAAABI3zzeAgAAA/4CAgP////+QH2PBsN+MPxz+HEMAAAAAEjcANoCAAAD/gICA" +
                "//////vChMGw34w/HP4cQwAAAABcNQA2gIAAAP+AgID/////kB9jwbDfjD8c/hxDAAAAAFw1zzf/gICAgP+A//////+QH2PB" +
                "cQkAQBz+HEMAAAAAEjfPN/+AgICA/4D//////5AfY8FxCQBAgmQfQwAAAAASNwA2/4CAgID/gP//////kB9jwbDfjD+CZB9D" +
                "AAAAAFw1ADb/gICAgP+A///////7woTBcQkAQBz+HEMAAAAAXDXPNwCAgICAAID///////vChMGw34w/HP4cQwAAAAASN883" +
                "AICAgIAAgP//////+8KEwbDfjD+CZB9DAAAAABI3ADYAgICAgACA///////7woTBcQkAQIJkH0MAAAAAXDUANgCAgICAAID/" +
                "/////5AfY8FxCQBAHP4cQwAAAABcNc83gP+AgACAgP//////+8KEwXEJAEAc/hxDAAAAABI3zzeA/4CAAICA///////7woTB" +
                "cQkAQIJkH0MAAAAAEjcANoD/gIAAgID//////5AfY8FxCQBAgmQfQwAAAABcNQA2gP+AgACAgP//////+8KEwbDfjD8c/hxD" +
                "AAAAAFw1zzeAAICA/4CA//////+QH2PBsN+MPxz+HEMAAAAAEjfPN4AAgID/gID//////5AfY8Gw34w/gmQfQwAAAAASNwA2" +
                "gACAgP+AgP//////+8KEwbDfjD+CZB9DAAAAAFw1ADaAAICA/4CA//////+ofWLC4xKgPzkKGEMAAAAAXDXPN4CA////gICA" +
                "/////w/kWMLjEqA/OQoYQwAAAAASN883gID///+AgID/////D+RYwgujCUA5ChhDAAAAABI3ADaAgP///4CAgP////+ofWLC" +
                "C6MJQDkKGEMAAAAAXDUANoCA////gICA/////6h9YsILowlA06MVQwAAAABcNc83gIAAAP+AgID/////D+RYwgujCUDToxVD" +
                "AAAAABI3zzeAgAAA/4CAgP////8P5FjC4xKgP9OjFUMAAAAAEjcANoCAAAD/gICA/////6h9YsLjEqA/06MVQwAAAABcNQA2" +
                "gIAAAP+AgID/////D+RYwuMSoD/ToxVDAAAAAFw1zzf/gICAgP+A//////8P5FjCC6MJQNOjFUMAAAAAEjfPN/+AgICA/4D/" +
                "/////w/kWMILowlAOQoYQwAAAAASNwA2/4CAgID/gP//////D+RYwuMSoD85ChhDAAAAAFw1ADb/gICAgP+A//////+ofWLC" +
                "C6MJQNOjFUMAAAAAXDXPNwCAgICAAID//////6h9YsLjEqA/06MVQwAAAAASN883AICAgIAAgP//////qH1iwuMSoD85ChhD" +
                "AAAAABI3ADYAgICAgACA//////+ofWLCC6MJQDkKGEMAAAAAXDUANgCAgICAAID//////w/kWMILowlA06MVQwAAAABcNc83" +
                "gP+AgACAgP//////qH1iwgujCUDToxVDAAAAABI3zzeA/4CAAICA//////+ofWLCC6MJQDkKGEMAAAAAEjcANoD/gIAAgID/" +
                "/////w/kWMILowlAOQoYQwAAAABcNQA2gP+AgACAgP//////qH1iwuMSoD/ToxVDAAAAAFw1zzeAAICA/4CA//////8P5FjC" +
                "4xKgP9OjFUMAAAAAEjfPN4AAgID/gID//////w/kWMLjEqA/OQoYQwAAAAASNwA2gACAgP+AgP//////qH1iwuMSoD85ChhD" +
                "AAAAAFw1ADaAAICA/4CA//////8fk0xCFkazP6cx0UIAAAAAXDXPN4CA////gICA/////7ksVkIWRrM/pzHRQgAAAAASN883" +
                "gID///+AgID/////uSxWQqU8E0CnMdFCAAAAABI3ADaAgP///4CAgP////8fk0xCpTwTQKcx0UIAAAAAXDUANoCA////gICA" +
                "/////x+TTEKlPBNA2mTMQgAAAABcNc83gIAAAP+AgID/////uSxWQqU8E0DaZMxCAAAAABI3zzeAgAAA/4CAgP////+5LFZC" +
                "FkazP9pkzEIAAAAAEjcANoCAAAD/gICA/////x+TTEIWRrM/2mTMQgAAAABcNQA2gIAAAP+AgID/////uSxWQhZGsz/aZMxC" +
                "AAAAAFw1zzf/gICAgP+A//////+5LFZCpTwTQNpkzEIAAAAAEjfPN/+AgICA/4D//////7ksVkKlPBNApzHRQgAAAAASNwA2" +
                "/4CAgID/gP//////uSxWQhZGsz+nMdFCAAAAAFw1ADb/gICAgP+A//////8fk0xCpTwTQNpkzEIAAAAAXDXPNwCAgICAAID/" +
                "/////x+TTEIWRrM/2mTMQgAAAAASN883AICAgIAAgP//////H5NMQhZGsz+nMdFCAAAAABI3ADYAgICAgACA//////8fk0xC" +
                "pTwTQKcx0UIAAAAAXDUANgCAgICAAID//////7ksVkKlPBNA2mTMQgAAAABcNc83gP+AgACAgP//////H5NMQqU8E0DaZMxC" +
                "AAAAABI3zzeA/4CAAICA//////8fk0xCpTwTQKcx0UIAAAAAEjcANoD/gIAAgID//////7ksVkKlPBNApzHRQgAAAABcNQA2" +
                "gP+AgACAgP//////H5NMQhZGsz/aZMxCAAAAAFw1zzeAAICA/4CA//////+5LFZCFkazP9pkzEIAAAAAEjfPN4AAgID/gID/" +
                "/////7ksVkIWRrM/pzHRQgAAAAASNwA2gACAgP+AgP//////H5NMQhZGsz+nMdFCAAAAAFw1ADaAAICA/4CA//////+q2zFB" +
                "07dJQNuL8EIAAAAAXDXPN4CA////gICA/////xBCWEHTt0lA24vwQgAAAAASN883gID///+AgID/////EEJYQbaogUDbi/BC" +
                "AAAAABI3ADaAgP///4CAgP////+q2zFBtqiBQNuL8EIAAAAAXDUANoCA////gICA/////6rbMUG2qIFADr/rQgAAAABcNc83" +
                "gIAAAP+AgID/////EEJYQbaogUAOv+tCAAAAABI3zzeAgAAA/4CAgP////8QQlhB07dJQA6/60IAAAAAEjcANoCAAAD/gICA" +
                "/////6rbMUHTt0lADr/rQgAAAABcNQA2gIAAAP+AgID/////EEJYQdO3SUAOv+tCAAAAAFw1zzf/gICAgP+A//////8QQlhB" +
                "tqiBQA6/60IAAAAAEjfPN/+AgICA/4D//////xBCWEG2qIFA24vwQgAAAAASNwA2/4CAgID/gP//////EEJYQdO3SUDbi/BC" +
                "AAAAAFw1ADb/gICAgP+A//////+q2zFBtqiBQA6/60IAAAAAXDXPNwCAgICAAID//////6rbMUHTt0lADr/rQgAAAAASN883" +
                "AICAgIAAgP//////qtsxQdO3SUDbi/BCAAAAABI3ADYAgICAgACA//////+q2zFBtqiBQNuL8EIAAAAAXDUANgCAgICAAID/" +
                "/////xBCWEG2qIFADr/rQgAAAABcNc83gP+AgACAgP//////qtsxQbaogUAOv+tCAAAAABI3zzeA/4CAAICA//////+q2zFB" +
                "tqiBQNuL8EIAAAAAEjcANoD/gIAAgID//////xBCWEG2qIFA24vwQgAAAABcNQA2gP+AgACAgP//////qtsxQdO3SUAOv+tC" +
                "AAAAAFw1zzeAAICA/4CA//////8QQlhB07dJQA6/60IAAAAAEjfPN4AAgID/gID//////xBCWEHTt0lA24vwQgAAAAASNwA2" +
                "gACAgP+AgP//////qtsxQdO3SUDbi/BCAAAAAFw1ADaAAICA/4CA//////+ZqM7BfKzZP4dW0kIAAAAAXDXPN4CA////gICA" +
                "/////2Z1u8F8rNk/h1bSQgAAAAASN883gID///+AgID/////ZnW7wdhvJkCHVtJCAAAAABI3ADaAgP///4CAgP////+ZqM7B" +
                "2G8mQIdW0kIAAAAAXDUANoCA////gICA/////5mozsHYbyZAu4nNQgAAAABcNc83gIAAAP+AgID/////ZnW7wdhvJkC7ic1C" +
                "AAAAABI3zzeAgAAA/4CAgP////9mdbvBfKzZP7uJzUIAAAAAEjcANoCAAAD/gICA/////5mozsF8rNk/u4nNQgAAAABcNQA2" +
                "gIAAAP+AgID/////ZnW7wXys2T+7ic1CAAAAAFw1zzf/gICAgP+A//////9mdbvB2G8mQLuJzUIAAAAAEjfPN/+AgICA/4D/" +
                "/////2Z1u8HYbyZAh1bSQgAAAAASNwA2/4CAgID/gP//////ZnW7wXys2T+HVtJCAAAAAFw1ADb/gICAgP+A//////+ZqM7B" +
                "2G8mQLuJzUIAAAAAXDXPNwCAgICAAID//////5mozsF8rNk/u4nNQgAAAAASN883AICAgIAAgP//////majOwXys2T+HVtJC" +
                "AAAAABI3ADYAgICAgACA//////+ZqM7B2G8mQIdW0kIAAAAAXDUANgCAgICAAID//////2Z1u8HYbyZAu4nNQgAAAABcNc83" +
                "gP+AgACAgP//////majOwdhvJkC7ic1CAAAAABI3zzeA/4CAAICA//////+ZqM7B2G8mQIdW0kIAAAAAEjcANoD/gIAAgID/" +
                "/////2Z1u8HYbyZAh1bSQgAAAABcNQA2gP+AgACAgP//////majOwXys2T+7ic1CAAAAAFw1zzeAAICA/4CA//////9mdbvB" +
                "fKzZP7uJzUIAAAAAEjfPN4AAgID/gID//////2Z1u8F8rNk/h1bSQgAAAAASNwA2gACAgP+AgP//////majOwXys2T+HVtJC" +
                "AAAAAFw1ADaAAICA/4CA//////8d93TCsN/sPzqc10IAAAAAXDXPN4CA////gICA/////4Rda8Kw3+w/OpzXQgAAAAASN883" +
                "gID///+AgID/////hF1rwnEJMEA6nNdCAAAAABI3ADaAgP///4CAgP////8d93TCcQkwQDqc10IAAAAAXDUANoCA////gICA" +
                "/////x33dMJxCTBAbc/SQgAAAABcNc83gIAAAP+AgID/////hF1rwnEJMEBtz9JCAAAAABI3zzeAgAAA/4CAgP////+EXWvC" +
                "sN/sP23P0kIAAAAAEjcANoCAAAD/gICA/////x33dMKw3+w/bc/SQgAAAABcNQA2gIAAAP+AgID/////hF1rwrDf7D9tz9JC" +
                "AAAAAFw1zzf/gICAgP+A//////+EXWvCcQkwQG3P0kIAAAAAEjfPN/+AgICA/4D//////4Rda8JxCTBAOpzXQgAAAAASNwA2" +
                "/4CAgID/gP//////hF1rwrDf7D86nNdCAAAAAFw1ADb/gICAgP+A//////8d93TCcQkwQG3P0kIAAAAAXDXPNwCAgICAAID/" +
                "/////x33dMKw3+w/bc/SQgAAAAASN883AICAgIAAgP//////Hfd0wrDf7D86nNdCAAAAABI3ADYAgICAgACA//////8d93TC" +
                "cQkwQDqc10IAAAAAXDUANgCAgICAAID//////4Rda8JxCTBAbc/SQgAAAABcNc83gP+AgACAgP//////Hfd0wnEJMEBtz9JC" +
                "AAAAABI3zzeA/4CAAICA//////8d93TCcQkwQDqc10IAAAAAEjcANoD/gIAAgID//////4Rda8JxCTBAOpzXQgAAAABcNQA2" +
                "gP+AgACAgP//////Hfd0wrDf7D9tz9JCAAAAAFw1zzeAAICA/4CA//////+EXWvCsN/sP23P0kIAAAAAEjfPN4AAgID/gID/" +
                "/////4Rda8Kw3+w/OpzXQgAAAAASNwA2gACAgP+AgP//////Hfd0wrDf7D86nNdCAAAAAFw1ADaAAICA/4CA//////8AAAEA" +
                "AgAAAAIAAwAEAAUABgAEAAYABwAIAAkACgAIAAoACwAMAA0ADgAMAA4ADwAQABEAEgAQABIAEwAUABUAFgAUABYAFwAYABkA" +
                "GgAYABoAGwAcAB0AHgAcAB4AHwAgACEAIgAgACIAIwAkACUAJgAkACYAJwAoACkAKgAoACoAKwAsAC0ALgAsAC4ALwAwADEA" +
                "MgAwADIAMwA0ADUANgA0ADYANwA4ADkAOgA4ADoAOwA8AD0APgA8AD4APwBAAEEAQgBAAEIAQwBEAEUARgBEAEYARwBIAEkA" +
                "SgBIAEoASwBMAE0ATgBMAE4ATwBQAFEAUgBQAFIAUwBUAFUAVgBUAFYAVwBYAFkAWgBYAFoAWwBcAF0AXgBcAF4AXwBgAGEA" +
                "YgBgAGIAYwBkAGUAZgBkAGYAZwBoAGkAagBoAGoAawBsAG0AbgBsAG4AbwBwAHEAcgBwAHIAcwB0AHUAdgB0AHYAdwB4AHkA" +
                "egB4AHoAewB8AH0AfgB8AH4AfwCAAIEAggCAAIIAgwCEAIUAhgCEAIYAhwCIAIkAigCIAIoAiwCMAI0AjgCMAI4AjwCQAJEA" +
                "kgCQAJIAkwCUAJUAlgCUAJYAlwCYAJkAmgCYAJoAmwCcAJ0AngCcAJ4AnwCgAKEAogCgAKIAowCkAKUApgCkAKYApwCoAKkA" +
                "qgCoAKoAqwCsAK0ArgCsAK4ArwCwALEAsgCwALIAswC0ALUAtgC0ALYAtwC4ALkAugC4ALoAuwC8AL0AvgC8AL4AvwAAAAAA",
            CoinSlotLip = "AwAAAAAAAAD/////DgAIAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAgD//////" +
                "AAAAAAAAAAD66A5CvN5RQf////8JAAAA/////wgEZQcAsAMADAAYAEgDAAAAAEDBAACowMe1EUIAAAAAHyX2O4CA////gICA" +
                "/////wAAQEEAAKjAx7URQgAAAADXO/Y7gID///+AgID/////AABAQQAAqEDHtRFCAAAAANc7PTuAgP///4CAgP////8AAEDB" +
                "AACoQMe1EUIAAAAAHyU9O4CA////gICA/////wAAQMEAAKhALhwMQgAAAAAfJfY7gIAAAP+AgID/////AABAQQAAqEAuHAxC" +
                "AAAAANc79juAgAAA/4CAgP////8AAEBBAACowC4cDEIAAAAA1zs9O4CAAAD/gICA/////wAAQMEAAKjALhwMQgAAAAAfJT07" +
                "gIAAAP+AgID/////AABAQQAAqMAuHAxCAAAAAB8l9jv/gICAgP+A//////8AAEBBAACoQC4cDEIAAAAA1zv2O/+AgICA/4D/" +
                "/////wAAQEEAAKhAx7URQgAAAADXOz07/4CAgID/gP//////AABAQQAAqMDHtRFCAAAAAB8lPTv/gICAgP+A//////8AAEDB" +
                "AACoQC4cDEIAAAAAHyX2OwCAgICAAID//////wAAQMEAAKjALhwMQgAAAADXO/Y7AICAgIAAgP//////AABAwQAAqMDHtRFC" +
                "AAAAANc7PTsAgICAgACA//////8AAEDBAACoQMe1EUIAAAAAHyU9OwCAgICAAID//////wAAQEEAAKhALhwMQgAAAAAfJfY7" +
                "gP+AgACAgP//////AABAwQAAqEAuHAxCAAAAANc79juA/4CAAICA//////8AAEDBAACoQMe1EUIAAAAA1zs9O4D/gIAAgID/" +
                "/////wAAQEEAAKhAx7URQgAAAAAfJT07gP+AgACAgP//////AABAwQAAqMAuHAxCAAAAAB8l9juAAICA/4CA//////8AAEBB" +
                "AACowC4cDEIAAAAA1zv2O4AAgID/gID//////wAAQEEAAKjAx7URQgAAAADXOz07gACAgP+AgP//////AABAwQAAqMDHtRFC" +
                "AAAAAB8lPTuAAICA/4CA//////8AAAEAAgAAAAIAAwAEAAUABgAEAAYABwAIAAkACgAIAAoACwAMAA0ADgAMAA4ADwAQABEA" +
                "EgAQABIAEwAUABUAFgAUABYAFwAAAAAA",
            CoinSlot = "BAAAAAAAAAD/////DgAIAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAgD//////" +
                "AAAAAAAAAABCyhFCc7QaQf////8MAAAA/////wgEZQcAsAMADAAYAEgDAAAAABjBZmbmv9zjEUIAAAAAHyX2O4CA////gICA" +
                "CAgI/wAAGEFmZua/3OMRQgAAAADXO/Y7gID///+AgIAICAj/AAAYQWZm5j/c4xFCAAAAANc7PTuAgP///4CAgAgICP8AABjB" +
                "ZmbmP9zjEUIAAAAAHyU9O4CA////gICACAgI/wAAGMFmZuY/qLARQgAAAAAfJfY7gIAAAP+AgIAICAj/AAAYQWZm5j+osBFC" +
                "AAAAANc79juAgAAA/4CAgAgICP8AABhBZmbmv6iwEUIAAAAA1zs9O4CAAAD/gICACAgI/wAAGMFmZua/qLARQgAAAAAfJT07" +
                "gIAAAP+AgIAICAj/AAAYQWZm5r+osBFCAAAAAB8l9jv/gICAgP+A/wgICP8AABhBZmbmP6iwEUIAAAAA1zv2O/+AgICA/4D/" +
                "CAgI/wAAGEFmZuY/3OMRQgAAAADXOz07/4CAgID/gP8ICAj/AAAYQWZm5r/c4xFCAAAAAB8lPTv/gICAgP+A/wgICP8AABjB" +
                "ZmbmP6iwEUIAAAAAHyX2OwCAgICAAID/CAgI/wAAGMFmZua/qLARQgAAAADXO/Y7AICAgIAAgP8ICAj/AAAYwWZm5r/c4xFC" +
                "AAAAANc7PTsAgICAgACA/wgICP8AABjBZmbmP9zjEUIAAAAAHyU9OwCAgICAAID/CAgI/wAAGEFmZuY/qLARQgAAAAAfJfY7" +
                "gP+AgACAgP8ICAj/AAAYwWZm5j+osBFCAAAAANc79juA/4CAAICA/wgICP8AABjBZmbmP9zjEUIAAAAA1zs9O4D/gIAAgID/" +
                "CAgI/wAAGEFmZuY/3OMRQgAAAAAfJT07gP+AgACAgP8ICAj/AAAYwWZm5r+osBFCAAAAAB8l9juAAICA/4CA/wgICP8AABhB" +
                "Zmbmv6iwEUIAAAAA1zv2O4AAgID/gID/CAgI/wAAGEFmZua/3OMRQgAAAADXOz07gACAgP+AgP8ICAj/AAAYwWZm5r/c4xFC" +
                "AAAAAB8lPTuAAICA/4CA/wgICP8AAAEAAgAAAAIAAwAEAAUABgAEAAYABwAIAAkACgAIAAoACwAMAA0ADgAMAA4ADwAQABEA" +
                "EgAQABIAEwAUABUAFgAUABYAFwAAAAAA",
            BoardHulls = new[]
            {
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAkBOVP5hoEr4AAAAAAAAAAEVsuz+YaBK+AAAAAAAAAACQE5U/" +
                    "omgSPgAAAAAAAAAARWy7P6JoEj4AAAAAAAAAAJATlT+YaBK+VfVPQAAAAABFbLs/mGgSvlX1T0AAAAAAkBOVP6JoEj5V9U9A" +
                    "AAAAAEVsuz+iaBI+VfVPQAAAAAAGAAAAAACAPwAAAAAAAAAARWy7vwAAgL8AAACAAAAAgJATlT8AAAAAAACAPwAAAACiaBK+" +
                    "AAAAgAAAgL8AAACAmGgSvgAAAAAAAAAAAACAP1X1T8AAAACAAAAAgAAAgL8AAACA",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAPGy7v5hoEr4AAAAAAAAAAIcTlb+YaBK+AAAAAAAAAAA8bLu/" +
                    "omgSPgAAAAAAAAAAhxOVv6JoEj4AAAAAAAAAADxsu7+YaBK+VfVPQAAAAACHE5W/mGgSvlX1T0AAAAAAPGy7v6JoEj5V9U9A" +
                    "AAAAAIcTlb+iaBI+VfVPQAAAAAAGAAAAAACAPwAAAAAAAAAAhxOVPwAAgL8AAACAAAAAgDxsu78AAAAAAACAPwAAAACiaBK+" +
                    "AAAAgAAAgL8AAACAmGgSvgAAAAAAAAAAAACAP1X1T8AAAACAAAAAgAAAgL8AAACA",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAxg+fvzHbtL0LJFQ/AAAAANEPnz8x27S9CyRUPwAAAADGD5+/" +
                    "nxDquwskVD8AAAAA0Q+fP58Q6rsLJFQ/AAAAAMYPn78x27S9tU4mQAAAAADRD58/Mdu0vbVOJkAAAAAAxg+fv58Q6ru1TiZA" +
                    "AAAAANEPnz+fEOq7tU4mQAAAAAAGAAAAAACAPwAAAAAAAAAA0Q+fvwAAgL8AAACAAAAAgMYPn78AAAAAAACAPwAAAACfEOo7" +
                    "AAAAgAAAgL8AAACAMdu0vQAAAAAAAAAAAACAP7VOJsAAAACAAAAAgAAAgL8LJFQ/",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAARIy3v2YWajz8eiNAAAAAAEWMtz9mFmo8/HojQAAAAABEjLe/" +
                    "bBKjPvx6I0AAAAAARYy3P2wSoz78eiNAAAAAAESMt79mFmo8chs0QAAAAABFjLc/ZhZqPHIbNEAAAAAARIy3v2wSoz5yGzRA" +
                    "AAAAAEWMtz9sEqM+chs0QAAAAAAGAAAAAACAPwAAAAAAAAAARYy3vwAAgL8AAACAAAAAgESMt78AAAAAAACAPwAAAABsEqO+" +
                    "AAAAgAAAgL8AAACAZhZqPAAAAAAAAAAAAACAP3IbNMAAAACAAAAAgAAAgL/8eiNA",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAARIy3v2YWajxskis/AAAAAEWMtz9mFmo8bJIrPwAAAABEjLe/" +
                    "bBKjPmySKz8AAAAARYy3P2wSoz5skis/AAAAAESMt79mFmo8RRRuPwAAAABFjLc/ZhZqPEUUbj8AAAAARIy3v2wSoz5FFG4/" +
                    "AAAAAEWMtz9sEqM+RRRuPwAAAAAGAAAAAACAPwAAAAAAAAAARYy3vwAAgL8AAACAAAAAgESMt78AAAAAAACAPwAAAABsEqO+" +
                    "AAAAgAAAgL8AAACAZhZqPAAAAAAAAAAAAACAP0UUbr8AAACAAAAAgAAAgL9skis/",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAdlDJP2TTIr2NPGFAAAAAAHZQyb9k0yK9jTxhQAAAAAB2UMk/" +
                    "K7uAPx9wMUAAAAAAdlDJvyu7gD8fcDFAAAAAAHZQyT8YdHW95G1fQAAAAAB2UMm/GHR1veRtX0AAAAAAdlDJP0xMfD92oS9A" +
                    "AAAAAHZQyb9MTHw/dqEvQAAAAAAGAAAAAACAvwAAAAAAAAAAdlDJvwAAgD8AAACAAAAAgHZQyb8AAAAAnU5QPyTPFL9bEks/" +
                    "AAAAgJ1OUL8kzxQ/OP8EwAAAAAAkzxS/nU5Qvy+TM0AAAACAJM8UP51OUD/FyzXA",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAdlDJv2TTIj2NPGFAAAAAAHZQyT9k0yI9jTxhQAAAAAB2UMm/" +
                    "K7uAvx9wMUAAAAAAdlDJPyu7gL8fcDFAAAAAAHZQyb8YdHU95G1fQAAAAAB2UMk/GHR1PeRtX0AAAAAAdlDJv0xMfL92oS9A" +
                    "AAAAAHZQyT9MTHy/dqEvQAAAAAAGAAAAAACAPwAAAAAAAAAAdlDJvwAAgL8AAACAAAAAgHZQyb8AAAAAnU5QvyTPFL9bEks/" +
                    "AAAAgJ1OUD8kzxQ/OP8EwAAAAAAkzxQ/nU5Qvy+TM0AAAACAJM8Uv51OUD/FyzXA",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAANe+gP4xZtL2qjTdAAAAAAJpU/z+MWbS9qo03QAAAAAA176A/" +
                    "mVm0PaqNN0AAAAAAmlT/P5lZtD2qjTdAAAAAADXvoD+MWbS97y1BQAAAAACaVP8/jFm0ve8tQUAAAAAANe+gP5lZtD3vLUFA" +
                    "AAAAAJpU/z+ZWbQ97y1BQAAAAAAGAAAAAACAPwAAAAAAAAAAmlT/vwAAgL8AAACAAAAAgDXvoD8AAAAAAACAPwAAAACZWbS9" +
                    "AAAAgAAAgL8AAACAjFm0vQAAAAAAAAAAAACAP+8tQcAAAACAAAAAgAAAgL+qjTdA",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAIiPeP3m8/b3qQBBAAAAAAAGb/z95vP296kAQQAAAAAAiI94/" +
                    "rrz9PepAEEAAAAAAAZv/P668/T3qQBBAAAAAACIj3j95vP29Xss3QAAAAAABm/8/ebz9vV7LN0AAAAAAIiPeP668/T1eyzdA" +
                    "AAAAAAGb/z+uvP09Xss3QAAAAAAGAAAAAACAPwAAAAAAAAAAAZv/vwAAgL8AAACAAAAAgCIj3j8AAAAAAACAPwAAAACuvP29" +
                    "AAAAgAAAgL8AAACAebz9vQAAAAAAAAAAAACAP17LN8AAAACAAAAAgAAAgL/qQBBA",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAA770YwHWsor6DmYY/AAAAAO84s791rKK+g5mGPwAAAADvvRjA" +
                    "/THdPoOZhj8AAAAA7zizv/0x3T6DmYY/AAAAAO+9GMB1rKK+1U2SPwAAAADvOLO/dayivtVNkj8AAAAA770YwP0x3T7VTZI/" +
                    "AAAAAO84s7/9Md0+1U2SPwAAAAAGAAAAAACAPwAAAAAAAAAA7zizPwAAgL8AAACAAAAAgO+9GMAAAAAAAACAPwAAAAD9Md2+" +
                    "AAAAgAAAgL8AAACAdayivgAAAAAAAAAAAACAP9VNkr8AAACAAAAAgAAAgL+DmYY/",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAS6uzv7OkGj78Ugc/AAAAAErb9L/0ANg9Ms6IPwAAAABwr7y/" +
                    "ErHFPWNL6j4AAAAAb9/9v0DRUD0Zb38/AAAAAD/Trr/IOoU9JJoOPwAAAAA+A/C/V8mfPMZxjD8AAAAAZNe3v6ATLTyy2fg+" +
                    "AAAAAGMH+b/9Sw+9IFuDPwAAAAAGAAAAZ0gvvzPUer146zk/LhcFwGdILz8z1Ho9eOs5v5f5qj/CUh6/DfP0vp6XH786iBS/" +
                    "wlIePw3z9D6elx8/4L/uPr1wxT42QWC/a1OUPt442D69cMW+NkFgP2tTlL7IOwW/",
            },
            BoardList = "CwAAAG0AAABuAAAAbwAAAHAAAABxAAAAcgAAAHMAAAB0AAAAdQAAAHYAAAB3AAAAEcbZHQAAAAAAAAAAAAAAgAAAAAAAAAAA" +
                "AAAAgAsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
            BoxHulls = new[]
            {
                "oybihArXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAoOy8voePe74AAAAAAAAAAKDsvD6Hj3u+AAAAAAAAAACg7Ly+" +
                    "h497PgAAAAAAAAAAoOy8PoePez4AAAAAAAAAAKDsvL6Hj3u+4mYFPwAAAACg7Lw+h497vuJmBT8AAAAAoOy8voePez7iZgU/" +
                    "AAAAAKDsvD6Hj3s+4mYFPwAAAAAGAAAAAACAPwAAAAAAAAAAoOy8vgAAgL8AAACAAAAAgKDsvL4AAAAAAACAPwAAAACHj3u+" +
                    "AAAAgAAAgL8AAACAh497vgAAAAAAAAAAAACAP+JmBb8AAACAAAAAgAAAgL8AAACA",
            },
            BoxList = null,
            BoardPath = "Data\\meshes\\thornswood\\noticeboard01.nif",
            BoardSize = 155907,
            BoardSha256 = "47cfe0f22bdf8db0c66ad059cf77c546aeba972ad694d20e6ad7318630918216",
            BoxPath = "Data\\meshes\\thornswood\\dropbox01.nif",
            BoxSize = 29665,
            BoxSha256 = "09d8ae9277b6006017ff82f21fa2081e63f6c2249ffe63300e1e8cffb299241e",
        };
    }
}
