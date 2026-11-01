using System.Text;
using Thornswood.DeployAgent;
using Xunit;

namespace Thornswood.DeployAgent.Tests;

/// <summary>Files.Replace: the gamemode swap renames the new gamemode.js
/// over the running one while the server may be reading it. On Windows a
/// plain rename over an open file was refused ("Access to the path is
/// denied"), which failed the swap in the gate whenever the stand-in
/// server's 5 ms look landed on it (1 Nov). These hold the file open the way
/// the server and Files.OpenShared do, sharing read, write and delete, and
/// replace it.</summary>
public sealed class FilesTests : IDisposable
{
    readonly string dir = Directory.CreateTempSubdirectory("tw-files-").FullName;

    public void Dispose()
    {
        try { Directory.Delete(dir, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    [Fact]
    public void FilesReplaceGoesThroughWithTheFileOpen()
    {
        var at = Path.Combine(dir, "gamemode.js");
        var stage = Path.Combine(dir, "gamemode.js.new");
        File.WriteAllText(at, "// old gamemode\n");
        File.WriteAllText(stage, "// new gamemode\n");
        using (var reader = Files.OpenShared(at))
        {
            Files.Replace(stage, at);
            // The reader keeps the bytes it opened.
            using var r = new StreamReader(reader, Encoding.UTF8);
            Assert.Equal("// old gamemode\n", r.ReadToEnd());
        }
        Assert.Equal("// new gamemode\n", File.ReadAllText(at));
        Assert.False(File.Exists(stage));
    }

    [Fact]
    public void FilesReplacePutsAFileWhereNoneWas()
    {
        var at = Path.Combine(dir, "thornswood-build.json");
        var stage = Path.Combine(dir, "stage.json");
        File.WriteAllText(stage, "{}");
        Files.Replace(stage, at);
        Assert.Equal("{}", File.ReadAllText(at));
        Assert.False(File.Exists(stage));
    }

    [Fact]
    public void FilesReplaceSaysWhyWhenTheFileToMoveIsNotThere()
    {
        var e = Assert.ThrowsAny<IOException>(() => Files.Replace(Path.Combine(dir, "nothing.js"), Path.Combine(dir, "gamemode.js")));
        Assert.NotEmpty(e.Message);
    }

    [Fact]
    public void WriteWholeGoesThroughWithTheFileOpen()
    {
        var at = Path.Combine(dir, "news-dev.json");
        File.WriteAllText(at, "old");
        using (Files.OpenShared(at)) Files.WriteWhole(at, Encoding.UTF8.GetBytes("new"));
        Assert.Equal("new", File.ReadAllText(at));
    }
}
