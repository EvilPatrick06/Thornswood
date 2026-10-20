// Written by scripts\mods\Build-NoticeBoard.py, from its PARTS and the blocks it
// draws itself, on a machine with the game. Change the script and run it again;
// an edit here is lost and fails the launcher's byte for byte check (#2827).
namespace Thornswood
{
    public sealed partial class BoardRecipe
    {
        public static readonly BoardRecipe Fixture = new BoardRecipe
        {
            Archives = new[] { "Skyrim - Meshes0.bsa", "Skyrim - Meshes1.bsa" },
            // each of the game's meshes the two are made from, as this game had it
            Sources = new BoardSource[]
            {
                new BoardSource("meshes\\clutter\\signage\\windhelm\\signwhpost01.nif", 2443, "f78b63c3c46055f86dedafae9320cb73209ea88a16672038f217e59f45634719"),
                new BoardSource("meshes\\clutter\\stockade\\stockadefreewall01.nif", 2100, "6a3ce6dd9ad35983bb496d58bb5fd3f9eff1fd496d6601e83831ccde6c297432"),
                new BoardSource("meshes\\clutter\\stockade\\stockadewoodbeamshort01.nif", 1427, "a1aa182e9a694ff0cdfed7e98cd2266c0e45a80df57cf9a30a8a40d1d372346f"),
                new BoardSource("meshes\\architecture\\shackkit\\shackroofside01.nif", 1873, "8c2a70e6b72cdb67245ea25d5bd0f9f2feeebbb71833edd9aed122a359ae7300"),
                new BoardSource("meshes\\clutter\\common\\candlelanternwithcandle01.nif", 1644, "37fbf4920fc21db20d804a33b9bac12dd41d72d5529119dbc84baaea9693a698"),
                new BoardSource("meshes\\clutter\\books\\note01.nif", 906, "b745bdcd3fe59678e6e20eb4772751967ae9b3647c4958a5ae326c6007adf160"),
                new BoardSource("meshes\\clutter\\books\\notetornpaper.nif", 1542, "250b1d1fc713b4a30437ac3a9cfab30e7444ac5dd808c7dfc504a2b865f2d488"),
                new BoardSource("meshes\\clutter\\books\\note02.nif", 2234, "0e13e6db2b77d408988cfa3a99e7c975d9ef50805c975e6c3e876528919670ba"),
                new BoardSource("meshes\\clutter\\books\\note04.nif", 1900, "be53a2df2cabf79f238fda3be8b650f1f308e5ee061a8ed6fb4857ded90bf374"),
                new BoardSource("meshes\\clutter\\books\\note03.nif", 1160, "cff990e7cbd097eaf883b3d54640c333151072f6b48f8bca54c5f24a99cd7cac"),
                new BoardSource("meshes\\clutter\\shipwreck\\shipwreckboards01.nif", 1220, "9d69c23181468d4cad522bb8c6256dc80b6baf3c6817587579deb3e16591b0ec"),
                new BoardSource("meshes\\architecture\\solitude\\clutter\\smarketstalltop.nif", 2356, "c56827c75893f5f1715c0e8ce3014b4cd4b9806ce33fc2cffd6c79abeb0c9bbd"),
                new BoardSource("meshes\\clutter\\common\\strongbox01.nif", 2084, "2be87fa72a44a88e07028c53fd48bb04b577c436bae01a16323c3dfffe51c8e7"),
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
                    new double[] { 6.123233995736766e-17, -0.7071067811865476, -0.7071067811865475, 1.0, 4.329780281177467e-17, 4.329780281177466e-17, 0.0, -0.7071067811865475, 0.7071067811865476 },
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
            NailHeads = "GAAAAAAAAAD/////DgAIAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAgD//////" +
                "eGZOwL8Fi0IPoztDv32UQv////9KAAAA/////wgEZQcAsAMAYADAAEAaAAC2WWRCBHxkQkDNRkMAAAAAXDXPN4CA////gICA" +
                "/////1DzbUIEfGRCQM1GQwAAAAASN883gID///+AgID/////UPNtQp4VaEJAzUZDAAAAABI3ADaAgP///4CAgP////+2WWRC" +
                "nhVoQkDNRkMAAAAAXDUANoCA////gICA/////7ZZZEKeFWhC2mZEQwAAAABcNc83gIAAAP+AgID/////UPNtQp4VaELaZkRD" +
                "AAAAABI3zzeAgAAA/4CAgP////9Q821CBHxkQtpmREMAAAAAEjcANoCAAAD/gICA/////7ZZZEIEfGRC2mZEQwAAAABcNQA2" +
                "gIAAAP+AgID/////UPNtQgR8ZELaZkRDAAAAAFw1zzf/gICAgP+A//////9Q821CnhVoQtpmREMAAAAAEjfPN/+AgICA/4D/" +
                "/////1DzbUKeFWhCQM1GQwAAAAASNwA2/4CAgID/gP//////UPNtQgR8ZEJAzUZDAAAAAFw1ADb/gICAgP+A//////+2WWRC" +
                "nhVoQtpmREMAAAAAXDXPNwCAgICAAID//////7ZZZEIEfGRC2mZEQwAAAAASN883AICAgIAAgP//////tllkQgR8ZEJAzUZD" +
                "AAAAABI3ADYAgICAgACA//////+2WWRCnhVoQkDNRkMAAAAAXDUANgCAgICAAID//////1DzbUKeFWhC2mZEQwAAAABcNc83" +
                "gP+AgACAgP//////tllkQp4VaELaZkRDAAAAABI3zzeA/4CAAICA//////+2WWRCnhVoQkDNRkMAAAAAEjcANoD/gIAAgID/" +
                "/////1DzbUKeFWhCQM1GQwAAAABcNQA2gP+AgACAgP//////tllkQgR8ZELaZkRDAAAAAFw1zzeAAICA/4CA//////9Q821C" +
                "BHxkQtpmREMAAAAAEjfPN4AAgID/gID//////1DzbUIEfGRCQM1GQwAAAAASNwA2gACAgP+AgP//////tllkQgR8ZEJAzUZD" +
                "AAAAAFw1ADaAAICA/4CA//////8mZdNBFCygQuIsW0MAAAAAXDXPN4CA////gICA/////1mY5kEULKBC4ixbQwAAAAASN883" +
                "gID///+AgID/////WZjmQeD4oULiLFtDAAAAABI3ADaAgP///4CAgP////8mZdNB4PihQuIsW0MAAAAAXDUANoCA////gICA" +
                "/////yZl00Hg+KFCfMZYQwAAAABcNc83gIAAAP+AgID/////WZjmQeD4oUJ8xlhDAAAAABI3zzeAgAAA/4CAgP////9ZmOZB" +
                "FCygQnzGWEMAAAAAEjcANoCAAAD/gICA/////yZl00EULKBCfMZYQwAAAABcNQA2gIAAAP+AgID/////WZjmQRQsoEJ8xlhD" +
                "AAAAAFw1zzf/gICAgP+A//////9ZmOZB4PihQnzGWEMAAAAAEjfPN/+AgICA/4D//////1mY5kHg+KFC4ixbQwAAAAASNwA2" +
                "/4CAgID/gP//////WZjmQRQsoELiLFtDAAAAAFw1ADb/gICAgP+A//////8mZdNB4PihQnzGWEMAAAAAXDXPNwCAgICAAID/" +
                "/////yZl00EULKBCfMZYQwAAAAASN883AICAgIAAgP//////JmXTQRQsoELiLFtDAAAAABI3ADYAgICAgACA//////8mZdNB" +
                "4PihQuIsW0MAAAAAXDUANgCAgICAAID//////1mY5kHg+KFCfMZYQwAAAABcNc83gP+AgACAgP//////JmXTQeD4oUJ8xlhD" +
                "AAAAABI3zzeA/4CAAICA//////8mZdNB4PihQuIsW0MAAAAAEjcANoD/gIAAgID//////1mY5kHg+KFC4ixbQwAAAABcNQA2" +
                "gP+AgACAgP//////JmXTQRQsoEJ8xlhDAAAAAFw1zzeAAICA/4CA//////9ZmOZBFCygQnzGWEMAAAAAEjfPN4AAgID/gID/" +
                "/////1mY5kEULKBC4ixbQwAAAAASNwA2gACAgP+AgP//////JmXTQRQsoELiLFtDAAAAAFw1ADaAAICA/4CA///////7IIXB" +
                "l+KnQrukZUMAAAAAXDXPN4CA////gICA/////5DbY8GX4qdCu6RlQwAAAAASN883gID///+AgID/////kNtjwWSvqUK7pGVD" +
                "AAAAABI3ADaAgP///4CAgP/////7IIXBZK+pQrukZUMAAAAAXDUANoCA////gICA//////sghcFkr6lCVT5jQwAAAABcNc83" +
                "gIAAAP+AgID/////kNtjwWSvqUJVPmNDAAAAABI3zzeAgAAA/4CAgP////+Q22PBl+KnQlU+Y0MAAAAAEjcANoCAAAD/gICA" +
                "//////sghcGX4qdCVT5jQwAAAABcNQA2gIAAAP+AgID/////kNtjwZfip0JVPmNDAAAAAFw1zzf/gICAgP+A//////+Q22PB" +
                "ZK+pQlU+Y0MAAAAAEjfPN/+AgICA/4D//////5DbY8Fkr6lCu6RlQwAAAAASNwA2/4CAgID/gP//////kNtjwZfip0K7pGVD" +
                "AAAAAFw1ADb/gICAgP+A///////7IIXBZK+pQlU+Y0MAAAAAXDXPNwCAgICAAID///////sghcGX4qdCVT5jQwAAAAASN883" +
                "AICAgIAAgP//////+yCFwZfip0K7pGVDAAAAABI3ADYAgICAgACA///////7IIXBZK+pQrukZUMAAAAAXDUANgCAgICAAID/" +
                "/////5DbY8Fkr6lCVT5jQwAAAABcNc83gP+AgACAgP//////+yCFwWSvqUJVPmNDAAAAABI3zzeA/4CAAICA///////7IIXB" +
                "ZK+pQrukZUMAAAAAEjcANoD/gIAAgID//////5DbY8Fkr6lCu6RlQwAAAABcNQA2gP+AgACAgP//////+yCFwZfip0JVPmND" +
                "AAAAAFw1zzeAAICA/4CA//////+Q22PBl+KnQlU+Y0MAAAAAEjfPN4AAgID/gID//////5DbY8GX4qdCu6RlQwAAAAASNwA2" +
                "gACAgP+AgP//////+yCFwZfip0K7pGVDAAAAAFw1ADaAAICA/4CA//////8P4IPC2O6lQn2yYEMAAAAAXDXPN4CA////gICA" +
                "/////4UmfsLY7qVCfbJgQwAAAAASN883gID///+AgID/////hSZ+wqW7p0J9smBDAAAAABI3ADaAgP///4CAgP////8P4IPC" +
                "pbunQn2yYEMAAAAAXDUANoCA////gICA/////w/gg8Klu6dCFkxeQwAAAABcNc83gIAAAP+AgID/////hSZ+wqW7p0IWTF5D" +
                "AAAAABI3zzeAgAAA/4CAgP////+FJn7C2O6lQhZMXkMAAAAAEjcANoCAAAD/gICA/////w/gg8LY7qVCFkxeQwAAAABcNQA2" +
                "gIAAAP+AgID/////hSZ+wtjupUIWTF5DAAAAAFw1zzf/gICAgP+A//////+FJn7CpbunQhZMXkMAAAAAEjfPN/+AgICA/4D/" +
                "/////4UmfsKlu6dCfbJgQwAAAAASNwA2/4CAgID/gP//////hSZ+wtjupUJ9smBDAAAAAFw1ADb/gICAgP+A//////8P4IPC" +
                "pbunQhZMXkMAAAAAXDXPNwCAgICAAID//////w/gg8LY7qVCFkxeQwAAAAASN883AICAgIAAgP//////D+CDwtjupUJ9smBD" +
                "AAAAABI3ADYAgICAgACA//////8P4IPCpbunQn2yYEMAAAAAXDUANgCAgICAAID//////4UmfsKlu6dCFkxeQwAAAABcNc83" +
                "gP+AgACAgP//////D+CDwqW7p0IWTF5DAAAAABI3zzeA/4CAAICA//////8P4IPCpbunQn2yYEMAAAAAEjcANoD/gIAAgID/" +
                "/////4UmfsKlu6dCfbJgQwAAAABcNQA2gP+AgACAgP//////D+CDwtjupUIWTF5DAAAAAFw1zzeAAICA/4CA//////+FJn7C" +
                "2O6lQhZMXkMAAAAAEjfPN4AAgID/gID//////4UmfsLY7qVCfbJgQwAAAAASNwA2gACAgP+AgP//////D+CDwtjupUJ9smBD" +
                "AAAAAFw1ADaAAICA/4CA///////I3ltCN7hVQlANNEMAAAAAXDXPN4CA////gICA/////2F4ZUI3uFVCUA00QwAAAAASN883" +
                "gID///+AgID/////YXhlQtBRWUJQDTRDAAAAABI3ADaAgP///4CAgP/////I3ltC0FFZQlANNEMAAAAAXDUANoCA////gICA" +
                "/////8jeW0LQUVlC6qYxQwAAAABcNc83gIAAAP+AgID/////YXhlQtBRWULqpjFDAAAAABI3zzeAgAAA/4CAgP////9heGVC" +
                "N7hVQuqmMUMAAAAAEjcANoCAAAD/gICA/////8jeW0I3uFVC6qYxQwAAAABcNQA2gIAAAP+AgID/////YXhlQje4VULqpjFD" +
                "AAAAAFw1zzf/gICAgP+A//////9heGVC0FFZQuqmMUMAAAAAEjfPN/+AgICA/4D//////2F4ZULQUVlCUA00QwAAAAASNwA2" +
                "/4CAgID/gP//////YXhlQje4VUJQDTRDAAAAAFw1ADb/gICAgP+A///////I3ltC0FFZQuqmMUMAAAAAXDXPNwCAgICAAID/" +
                "/////8jeW0I3uFVC6qYxQwAAAAASN883AICAgIAAgP//////yN5bQje4VUJQDTRDAAAAABI3ADYAgICAgACA///////I3ltC" +
                "0FFZQlANNEMAAAAAXDUANgCAgICAAID//////2F4ZULQUVlC6qYxQwAAAABcNc83gP+AgACAgP//////yN5bQtBRWULqpjFD" +
                "AAAAABI3zzeA/4CAAICA///////I3ltC0FFZQlANNEMAAAAAEjcANoD/gIAAgID//////2F4ZULQUVlCUA00QwAAAABcNQA2" +
                "gP+AgACAgP//////yN5bQje4VULqpjFDAAAAAFw1zzeAAICA/4CA//////9heGVCN7hVQuqmMUMAAAAAEjfPN4AAgID/gID/" +
                "/////2F4ZUI3uFVCUA00QwAAAAASNwA2gACAgP+AgP//////yN5bQje4VUJQDTRDAAAAAFw1ADaAAICA/4CA///////wwoJB" +
                "R1+hQmEYNkMAAAAAXDXPN4CA////gICA/////yP2lUFHX6FCYRg2QwAAAAASN883gID///+AgID/////I/aVQRQso0JhGDZD" +
                "AAAAABI3ADaAgP///4CAgP/////wwoJBFCyjQmEYNkMAAAAAXDUANoCA////gICA//////DCgkEULKNC+7EzQwAAAABcNc83" +
                "gIAAAP+AgID/////I/aVQRQso0L7sTNDAAAAABI3zzeAgAAA/4CAgP////8j9pVBR1+hQvuxM0MAAAAAEjcANoCAAAD/gICA" +
                "//////DCgkFHX6FC+7EzQwAAAABcNQA2gIAAAP+AgID/////I/aVQUdfoUL7sTNDAAAAAFw1zzf/gICAgP+A//////8j9pVB" +
                "FCyjQvuxM0MAAAAAEjfPN/+AgICA/4D//////yP2lUEULKNCYRg2QwAAAAASNwA2/4CAgID/gP//////I/aVQUdfoUJhGDZD" +
                "AAAAAFw1ADb/gICAgP+A///////wwoJBFCyjQvuxM0MAAAAAXDXPNwCAgICAAID///////DCgkFHX6FC+7EzQwAAAAASN883" +
                "AICAgIAAgP//////8MKCQUdfoUJhGDZDAAAAABI3ADYAgICAgACA///////wwoJBFCyjQmEYNkMAAAAAXDUANgCAgICAAID/" +
                "/////yP2lUEULKNC+7EzQwAAAABcNc83gP+AgACAgP//////8MKCQRQso0L7sTNDAAAAABI3zzeA/4CAAICA///////wwoJB" +
                "FCyjQmEYNkMAAAAAEjcANoD/gIAAgID//////yP2lUEULKNCYRg2QwAAAABcNQA2gP+AgACAgP//////8MKCQUdfoUL7sTND" +
                "AAAAAFw1zzeAAICA/4CA//////8j9pVBR1+hQvuxM0MAAAAAEjfPN4AAgID/gID//////yP2lUFHX6FCYRg2QwAAAAASNwA2" +
                "gACAgP+AgP//////8MKCQUdfoUJhGDZDAAAAAFw1ADaAAICA/4CA//////99YK3BnhVoQskHFEMAAAAAXDXPN4CA////gICA" +
                "/////0otmsGeFWhCyQcUQwAAAAASN883gID///+AgID/////Si2awTiva0LJBxRDAAAAABI3ADaAgP///4CAgP////99YK3B" +
                "OK9rQskHFEMAAAAAXDUANoCA////gICA/////31grcE4r2tCYqERQwAAAABcNc83gIAAAP+AgID/////Si2awTiva0JioRFD" +
                "AAAAABI3zzeAgAAA/4CAgP////9KLZrBnhVoQmKhEUMAAAAAEjcANoCAAAD/gICA/////31grcGeFWhCYqERQwAAAABcNQA2" +
                "gIAAAP+AgID/////Si2awZ4VaEJioRFDAAAAAFw1zzf/gICAgP+A//////9KLZrBOK9rQmKhEUMAAAAAEjfPN/+AgICA/4D/" +
                "/////0otmsE4r2tCyQcUQwAAAAASNwA2/4CAgID/gP//////Si2awZ4VaELJBxRDAAAAAFw1ADb/gICAgP+A//////99YK3B" +
                "OK9rQmKhEUMAAAAAXDXPNwCAgICAAID//////31grcGeFWhCYqERQwAAAAASN883AICAgIAAgP//////fWCtwZ4VaELJBxRD" +
                "AAAAABI3ADYAgICAgACA//////99YK3BOK9rQskHFEMAAAAAXDUANgCAgICAAID//////0otmsE4r2tCYqERQwAAAABcNc83" +
                "gP+AgACAgP//////fWCtwTiva0JioRFDAAAAABI3zzeA/4CAAICA//////99YK3BOK9rQskHFEMAAAAAEjcANoD/gIAAgID/" +
                "/////0otmsE4r2tCyQcUQwAAAABcNQA2gP+AgACAgP//////fWCtwZ4VaEJioRFDAAAAAFw1zzeAAICA/4CA//////9KLZrB" +
                "nhVoQmKhEUMAAAAAEjfPN4AAgID/gID//////0otmsGeFWhCyQcUQwAAAAASNwA2gACAgP+AgP//////fWCtwZ4VaELJBxRD" +
                "AAAAAFw1ADaAAICA/4CA//////9J63fCl2KpQsuMMUMAAAAAXDXPN4CA////gICA/////7BRbsKXYqlCy4wxQwAAAAASN883" +
                "gID///+AgID/////sFFuwmQvq0LLjDFDAAAAABI3ADaAgP///4CAgP////9J63fCZC+rQsuMMUMAAAAAXDUANoCA////gICA" +
                "/////0nrd8JkL6tCZSYvQwAAAABcNc83gIAAAP+AgID/////sFFuwmQvq0JlJi9DAAAAABI3zzeAgAAA/4CAgP////+wUW7C" +
                "l2KpQmUmL0MAAAAAEjcANoCAAAD/gICA/////0nrd8KXYqlCZSYvQwAAAABcNQA2gIAAAP+AgID/////sFFuwpdiqUJlJi9D" +
                "AAAAAFw1zzf/gICAgP+A//////+wUW7CZC+rQmUmL0MAAAAAEjfPN/+AgICA/4D//////7BRbsJkL6tCy4wxQwAAAAASNwA2" +
                "/4CAgID/gP//////sFFuwpdiqULLjDFDAAAAAFw1ADb/gICAgP+A//////9J63fCZC+rQmUmL0MAAAAAXDXPNwCAgICAAID/" +
                "/////0nrd8KXYqlCZSYvQwAAAAASN883AICAgIAAgP//////Set3wpdiqULLjDFDAAAAABI3ADYAgICAgACA//////9J63fC" +
                "ZC+rQsuMMUMAAAAAXDUANgCAgICAAID//////7BRbsJkL6tCZSYvQwAAAABcNc83gP+AgACAgP//////Set3wmQvq0JlJi9D" +
                "AAAAABI3zzeA/4CAAICA//////9J63fCZC+rQsuMMUMAAAAAEjcANoD/gIAAgID//////7BRbsJkL6tCy4wxQwAAAABcNQA2" +
                "gP+AgACAgP//////Set3wpdiqUJlJi9DAAAAAFw1zzeAAICA/4CA//////+wUW7Cl2KpQmUmL0MAAAAAEjfPN4AAgID/gID/" +
                "/////7BRbsKXYqlCy4wxQwAAAAASNwA2gACAgP+AgP//////Set3wpdiqULLjDFDAAAAAFw1ADaAAICA/4CA//////8AAAEA" +
                "AgAAAAIAAwAEAAUABgAEAAYABwAIAAkACgAIAAoACwAMAA0ADgAMAA4ADwAQABEAEgAQABIAEwAUABUAFgAUABYAFwAYABkA" +
                "GgAYABoAGwAcAB0AHgAcAB4AHwAgACEAIgAgACIAIwAkACUAJgAkACYAJwAoACkAKgAoACoAKwAsAC0ALgAsAC4ALwAwADEA" +
                "MgAwADIAMwA0ADUANgA0ADYANwA4ADkAOgA4ADoAOwA8AD0APgA8AD4APwBAAEEAQgBAAEIAQwBEAEUARgBEAEYARwBIAEkA" +
                "SgBIAEoASwBMAE0ATgBMAE4ATwBQAFEAUgBQAFIAUwBUAFUAVgBUAFYAVwBYAFkAWgBYAFoAWwBcAF0AXgBcAF4AXwBgAGEA" +
                "YgBgAGIAYwBkAGUAZgBkAGYAZwBoAGkAagBoAGoAawBsAG0AbgBsAG4AbwBwAHEAcgBwAHIAcwB0AHUAdgB0AHYAdwB4AHkA" +
                "egB4AHoAewB8AH0AfgB8AH4AfwCAAIEAggCAAIIAgwCEAIUAhgCEAIYAhwCIAIkAigCIAIoAiwCMAI0AjgCMAI4AjwCQAJEA" +
                "kgCQAJIAkwCUAJUAlgCUAJYAlwCYAJkAmgCYAJoAmwCcAJ0AngCcAJ4AnwCgAKEAogCgAKIAowCkAKUApgCkAKYApwCoAKkA" +
                "qgCoAKoAqwCsAK0ArgCsAK4ArwCwALEAsgCwALIAswC0ALUAtgC0ALYAtwC4ALkAugC4ALoAuwC8AL0AvgC8AL4AvwAAAAAA",
            CoinSlotLip = "AwAAAAAAAAD/////DgAIAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAgD//////" +
                "AAAAAAAAAACEpAVDvN5RQf////8JAAAA/////wgEZQcAsAMADAAYAEgDAAAAAEDBAACowLdXBkMAAAAAHyX2O4CA////gICA" +
                "/////wAAQEEAAKjAt1cGQwAAAADXO/Y7gID///+AgID/////AABAQQAAqEC3VwZDAAAAANc7PTuAgP///4CAgP////8AAEDB" +
                "AACoQLdXBkMAAAAAHyU9O4CA////gICA/////wAAQMEAAKhAUfEEQwAAAAAfJfY7gIAAAP+AgID/////AABAQQAAqEBR8QRD" +
                "AAAAANc79juAgAAA/4CAgP////8AAEBBAACowFHxBEMAAAAA1zs9O4CAAAD/gICA/////wAAQMEAAKjAUfEEQwAAAAAfJT07" +
                "gIAAAP+AgID/////AABAQQAAqMBR8QRDAAAAAB8l9jv/gICAgP+A//////8AAEBBAACoQFHxBEMAAAAA1zv2O/+AgICA/4D/" +
                "/////wAAQEEAAKhAt1cGQwAAAADXOz07/4CAgID/gP//////AABAQQAAqMC3VwZDAAAAAB8lPTv/gICAgP+A//////8AAEDB" +
                "AACoQFHxBEMAAAAAHyX2OwCAgICAAID//////wAAQMEAAKjAUfEEQwAAAADXO/Y7AICAgIAAgP//////AABAwQAAqMC3VwZD" +
                "AAAAANc7PTsAgICAgACA//////8AAEDBAACoQLdXBkMAAAAAHyU9OwCAgICAAID//////wAAQEEAAKhAUfEEQwAAAAAfJfY7" +
                "gP+AgACAgP//////AABAwQAAqEBR8QRDAAAAANc79juA/4CAAICA//////8AAEDBAACoQLdXBkMAAAAA1zs9O4D/gIAAgID/" +
                "/////wAAQEEAAKhAt1cGQwAAAAAfJT07gP+AgACAgP//////AABAwQAAqMBR8QRDAAAAAB8l9juAAICA/4CA//////8AAEBB" +
                "AACowFHxBEMAAAAA1zv2O4AAgID/gID//////wAAQEEAAKjAt1cGQwAAAADXOz07gACAgP+AgP//////AABAwQAAqMC3VwZD" +
                "AAAAAB8lPTuAAICA/4CA//////8AAAEAAgAAAAIAAwAEAAUABgAEAAYABwAIAAkACgAIAAoACwAMAA0ADgAMAA4ADwAQABEA" +
                "EgAQABIAEwAUABUAFgAUABYAFwAAAAAA",
            CoinSlot = "BAAAAAAAAAD/////DgAIAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAgD//////" +
                "AAAAAAAAAADWXAZDc7QaQf////8MAAAA/////wgEZQcAsAMADAAYAEgDAAAAABjBZmbmvzxjBkMAAAAAHyX2O4CA////gICA" +
                "CAgI/wAAGEFmZua/PGMGQwAAAADXO/Y7gID///+AgIAICAj/AAAYQWZm5j88YwZDAAAAANc7PTuAgP///4CAgAgICP8AABjB" +
                "ZmbmPzxjBkMAAAAAHyU9O4CA////gICACAgI/wAAGMFmZuY/b1YGQwAAAAAfJfY7gIAAAP+AgIAICAj/AAAYQWZm5j9vVgZD" +
                "AAAAANc79juAgAAA/4CAgAgICP8AABhBZmbmv29WBkMAAAAA1zs9O4CAAAD/gICACAgI/wAAGMFmZua/b1YGQwAAAAAfJT07" +
                "gIAAAP+AgIAICAj/AAAYQWZm5r9vVgZDAAAAAB8l9jv/gICAgP+A/wgICP8AABhBZmbmP29WBkMAAAAA1zv2O/+AgICA/4D/" +
                "CAgI/wAAGEFmZuY/PGMGQwAAAADXOz07/4CAgID/gP8ICAj/AAAYQWZm5r88YwZDAAAAAB8lPTv/gICAgP+A/wgICP8AABjB" +
                "ZmbmP29WBkMAAAAAHyX2OwCAgICAAID/CAgI/wAAGMFmZua/b1YGQwAAAADXO/Y7AICAgIAAgP8ICAj/AAAYwWZm5r88YwZD" +
                "AAAAANc7PTsAgICAgACA/wgICP8AABjBZmbmPzxjBkMAAAAAHyU9OwCAgICAAID/CAgI/wAAGEFmZuY/b1YGQwAAAAAfJfY7" +
                "gP+AgACAgP8ICAj/AAAYwWZm5j9vVgZDAAAAANc79juA/4CAAICA/wgICP8AABjBZmbmPzxjBkMAAAAA1zs9O4D/gIAAgID/" +
                "CAgI/wAAGEFmZuY/PGMGQwAAAAAfJT07gP+AgACAgP8ICAj/AAAYwWZm5r9vVgZDAAAAAB8l9juAAICA/4CA/wgICP8AABhB" +
                "Zmbmv29WBkMAAAAA1zv2O4AAgID/gID/CAgI/wAAGEFmZua/PGMGQwAAAADXOz07gACAgP+AgP8ICAj/AAAYwWZm5r88YwZD" +
                "AAAAAB8lPTuAAICA/4CA/wgICP8AAAEAAgAAAAIAAwAEAAUABgAEAAYABwAIAAkACgAIAAoACwAMAA0ADgAMAA4ADwAQABEA" +
                "EgAQABIAEwAUABUAFgAUABYAFwAAAAAA",
            BoardHulls = new[]
            {
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAuL+sPnZAV7/tmWy/AAAAAB6V9z92QFe/7ZlsvwAAAAC4v6w+" +
                    "hVUgP+2ZbL8AAAAAHpX3P4VVID/tmWy/AAAAALi/rD52QFe/JzpjPwAAAAAelfc/dkBXvyc6Yz8AAAAAuL+sPoVVID8nOmM/" +
                    "AAAAAB6V9z+FVSA/JzpjPwAAAAAGAAAAAACAPwAAAAAAAAAAHpX3vwAAgL8AAACAAAAAgLi/rD4AAAAAAACAPwAAAACFVSC/" +
                    "AAAAgAAAgL8AAACAdkBXvwAAAAAAAAAAAACAPyc6Y78AAACAAAAAgAAAgL/tmWy/",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAA76cSwHZAV7/tmWy/AAAAAFzVMb92QFe/7ZlsvwAAAADvpxLA" +
                    "hVUgP+2ZbL8AAAAAXNUxv4VVID/tmWy/AAAAAO+nEsB2QFe/JzpjPwAAAABc1TG/dkBXvyc6Yz8AAAAA76cSwIVVID8nOmM/" +
                    "AAAAAFzVMb+FVSA/JzpjPwAAAAAGAAAAAACAPwAAAAAAAAAAXNUxPwAAgL8AAACAAAAAgO+nEsAAAAAAAACAPwAAAACFVSC/" +
                    "AAAAgAAAgL8AAACAdkBXvwAAAAAAAAAAAACAPyc6Y78AAACAAAAAgAAAgL/tmWy/",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAA1FV2P8yt476p0Ks+AAAAANsD2T/MreO+qdCrPgAAAADUVXY/" +
                    "zGStPqnQqz4AAAAA2wPZP8xkrT6p0Ks+AAAAANRVdj/MreO+At6OPwAAAADbA9k/zK3jvgLejj8AAAAA1FV2P8xkrT4C3o4/" +
                    "AAAAANsD2T/MZK0+At6OPwAAAAAGAAAAAACAPwAAAAAAAAAA2wPZvwAAgL8AAACAAAAAgNRVdj8AAAAAAACAPwAAAADMZK2+" +
                    "AAAAgAAAgL8AAACAzK3jvgAAAAAAAAAAAACAPwLejr8AAACAAAAAgAAAgL+p0Ks+",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAjsjtvhP/4r2BNSVAAAAAANYE7D4T/+K9gTUlQAAAAACOyO2+" +
                    "ovkGP4E1JUAAAAAA1gTsPqL5Bj+BNSVAAAAAAI7I7b4T/+K9f8JHQAAAAADWBOw+E//ivX/CR0AAAAAAjsjtvqL5Bj9/wkdA" +
                    "AAAAANYE7D6i+QY/f8JHQAAAAAAGAAAAAACAPwAAAAAAAAAA1gTsvgAAgL8AAACAAAAAgI7I7b4AAAAAAACAPwAAAACi+Qa/" +
                    "AAAAgAAAgL8AAACAE//ivQAAAAAAAAAAAACAP3/CR8AAAACAAAAAgAAAgL+BNSVA",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAjsjtvhP/4r2AfDI/AAAAANYE7D4T/+K9gHwyPwAAAACOyO2+" +
                    "ovkGP4B8Mj8AAAAA1gTsPqL5Bj+AfDI/AAAAAI7I7b4T/+K9PViePwAAAADWBOw+E//ivT1Ynj8AAAAAjsjtvqL5Bj89WJ4/" +
                    "AAAAANYE7D6i+QY/PViePwAAAAAGAAAAAACAPwAAAAAAAAAA1gTsvgAAgL8AAACAAAAAgI7I7b4AAAAAAACAPwAAAACi+Qa/" +
                    "AAAAgAAAgL8AAACAE//ivQAAAAAAAAAAAACAPz1Ynr8AAACAAAAAgAAAgL+AfDI/",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAxe4tPxavnT7mYNQ/AAAAAGtACr/s2+U+vMzOPwAAAACYEB8/" +
                    "qIuGvk0VuD8AAAAAmB4Zv0R7+b0kgbI/AAAAABt9Jj9reS0+b5MBQAAAAAAUshG/jOmePrWS/T8AAAAA754XPwh+zb5G2+Y/" +
                    "AAAAAEGQIL8xUYW+HUfhPwAAAAAGAAAAeyV+v00H6z3mVBG9zcMHv3slfj9NB+u95lQRPUWyMr9/dcG9SKdtv2gWuL7E5Kk+" +
                    "f3XBPUinbT9oFrg+Z1dyvzH2l73gCbW+NrVuP33N478x9pc94Am1Pja1br8dpLE/",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAxe4tvxavnb7mYNQ/AAAAAGtACj/s2+W+vMzOPwAAAACYEB+/" +
                    "qIuGPk0VuD8AAAAAmB4ZP0R7+T0kgbI/AAAAABt9Jr9reS2+b5MBQAAAAAAUshE/jOmevrWS/T8AAAAA754Xvwh+zT5G2+Y/" +
                    "AAAAAEGQID8xUYU+HUfhPwAAAAAGAAAAeyV+P00H673mVBG9zcMHv3slfr9NB+s95lQRPUWyMr9/dcE9SKdtP2gWuL7E5Kk+" +
                    "f3XBvUinbb9oFrg+Z1dyvzH2lz3gCbU+NrVuP33N478x9pe94Am1vja1br8dpLE/",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAq9jAP8paJL7cjThAAAAAABpO3z/KWiS+3I04QAAAAACr2MA/" +
                    "xu1VPtyNOEAAAAAAGk7fP8btVT7cjThAAAAAAKvYwD/KWiS+pY5MQAAAAAAaTt8/ylokvqWOTEAAAAAAq9jAP8btVT6ljkxA" +
                    "AAAAABpO3z/G7VU+pY5MQAAAAAAGAAAAAACAPwAAAAAAAAAAGk7fvwAAgL8AAACAAAAAgKvYwD8AAAAAAACAPwAAAADG7VW+" +
                    "AAAAgAAAgL8AAACAylokvgAAAAAAAAAAAACAP6WOTMAAAACAAAAAgAAAgL/cjThA",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAFvmoP+X7C79pLt8/AAAAALe5GkDl+wu/aS7fPwAAAAAW+ag/" +
                    "rsQIP2ku3z8AAAAAt7kaQK7ECD9pLt8/AAAAABb5qD/l+wu/iRgzQAAAAAC3uRpA5fsLv4kYM0AAAAAAFvmoP67ECD+JGDNA" +
                    "AAAAALe5GkCuxAg/iRgzQAAAAAAGAAAAAACAPwAAAAAAAAAAt7kawAAAgL8AAACAAAAAgBb5qD8AAAAAAACAPwAAAACuxAi/" +
                    "AAAAgAAAgL8AAACA5fsLvwAAAAAAAAAAAACAP4kYM8AAAACAAAAAgAAAgL9pLt8/",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAMsYBwOad579Gi10+AAAAAI/l27/mnee/RotdPgAAAAAyxgHA" +
                    "/bW2P0aLXT4AAAAAj+Xbv/21tj9Gi10+AAAAADLGAcDmnee/F4/3PwAAAACP5du/5p3nvxeP9z8AAAAAMsYBwP21tj8Xj/c/" +
                    "AAAAAI/l27/9tbY/F4/3PwAAAAAGAAAAAACAPwAAAAAAAAAAj+XbPwAAgL8AAACAAAAAgDLGAcAAAAAAAACAPwAAAAD9tba/" +
                    "AAAAgAAAgL8AAACA5p3nvwAAAAAAAAAAAACAPxeP978AAACAAAAAgAAAgL9Gi10+",
                "EcbZHQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAqvi0v5208D3Uu2k/AAAAACaG0r/ugQ6+hJhMPwAAAABQX8q/" +
                    "TdNgPmPTgj8AAAAAzOznv7wjGL13g2g/AAAAAK7/uL8nTU8+cAxJPwAAAAAqjda/UzxevSDpKz8AAAAAU2bOvxPjmz5i92Q/" +
                    "AAAAAM/z67+op0M9EtRHPwAAAAAGAAAAJJYiv7nENL8FTqC+GYJkvySWIj+5xDQ/BU6gPq5xBz+i7T6/PQPpPlYR+T4FXeO/" +
                    "ou0+Pz0D6b5WEfm+J6vGPyHWTb7g3go/KNBQv0gDdj4h1k0+4N4KvyjQUD8YJsu+",
            },
            BoardList = "CwAAAEwAAABNAAAATgAAAE8AAABQAAAAUQAAAFIAAABTAAAAVAAAAFUAAABWAAAAEcbZHQAAAAAAAAAAAAAAgAAAAAAAAAAA" +
                "AAAAgAsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
            BoxHulls = new[]
            {
                "RDMiEQrXIzwAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAIAIAAAAGp1Wvzs9WL8AAAAAAAAAABqdVj87PVi/AAAAAAAAAAAanVa/" +
                    "Oz1YPwAAAAAAAAAAGp1WPzs9WD8AAAAAAAAAABqdVr87PVi/o8T1PwAAAAAanVY/Oz1Yv6PE9T8AAAAAGp1Wvzs9WD+jxPU/" +
                    "AAAAABqdVj87PVg/o8T1PwAAAAAGAAAAAACAPwAAAAAAAAAAGp1WvwAAgL8AAACAAAAAgBqdVr8AAAAAAACAPwAAAAA7PVi/" +
                    "AAAAgAAAgL8AAACAOz1YvwAAAAAAAAAAAACAP6PE9b8AAACAAAAAgAAAgL8AAACA",
            },
            BoxList = null,
            BoardPath = "Data\\meshes\\thornswood\\noticeboard01.nif",
            BoardSize = 33383,
            BoardSha256 = "8463cb49eb41d972070b60bc3954c772c3fe3e1d243475154d9d1de3a77ff0b4",
            BoxPath = "Data\\meshes\\thornswood\\dropbox01.nif",
            BoxSize = 4761,
            BoxSha256 = "f65a0cf5bb3e7e5207488b5e389841945b150745f4779edeeb6fd7ea7a011c20",
        };
    }
}
