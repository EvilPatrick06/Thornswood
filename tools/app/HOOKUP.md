# Wiring Discord.cs into the launcher

`Discord.cs` is finished and compiles on its own. What is left is three small
changes to files I could not read while your computer was off the bridge, so
they are written out here rather than guessed at.

## 1. Add the file to the build

`tools\Build-Launcher.ps1` (or whatever gathers the sources) picks up
`tools\app\*.cs`, so dropping `Discord.cs` in there is the whole step. It is
31 source files now, so the build should say 32.

## 2. Tell it where the profile is

Once, wherever the launcher works out its own paths in `Shell.cs`:

```csharp
Discord.Folder = profileFolder;     // whatever holds launcher.log already
```

## 3. The panel on the main page

In `ui.xaml`, in the main page, beside where the server details sit:

```xml
<StackPanel x:Name="PanelDiscord" Orientation="Horizontal" Margin="0,10,0,0">
  <TextBlock x:Name="LabelDiscord" VerticalAlignment="Center" Margin="0,0,10,0"/>
  <Button   x:Name="ButtonDiscord" Content="Connect Discord" Padding="12,5"/>
</StackPanel>
```

and in `Shell.cs`, where the other buttons are wired:

```csharp
void RefreshDiscord()
{
    if (Discord.Linked)
    {
        LabelDiscord.Text = "Discord: " + (Discord.Name.Length > 0 ? Discord.Name : "linked");
        ButtonDiscord.Content = "Reconnect";
    }
    else
    {
        LabelDiscord.Text = "Discord: not linked";
        ButtonDiscord.Content = "Connect Discord";
    }
}

ButtonDiscord.Click += delegate
{
    ButtonDiscord.IsEnabled = false;
    LabelDiscord.Text = "Discord: waiting for your browser";
    System.Threading.ThreadPool.QueueUserWorkItem(delegate
    {
        Discord.Connect(delegate (bool ok, string who)
        {
            Dispatcher.Invoke(new Action(delegate
            {
                ButtonDiscord.IsEnabled = true;
                if (!ok) LabelDiscord.Text = "Discord: " + who;
                else RefreshDiscord();
            }));
        });
    });
};
```

## 4. The check before Play

Wherever Play currently reads the password out of `version.json` and writes it
into `Thornswood.ini`, that becomes:

```csharp
var st = Discord.Join();
if (!st.Ok)
{
    if (st.Why == "offline")
    {
        // The site is down, not the person's fault. Fall back to whatever
        // password is already in the ini and let them try.
    }
    else
    {
        ShowMessage(st.Message);           // your usual message box
        if (st.Why == "link") { /* point them at Connect Discord */ }
        if (st.Invite.Length > 0) { /* offer to open the invite */ }
        return;                            // do not start the game
    }
}
else
{
    WritePassword(st.Password);            // into Thornswood.ini as sPassword
}
```

`st.Why` is one of `link`, `guild`, `banned`, `role`, `offline`, and
`st.Message` is already a sentence worth showing.

## Order this has to happen in

1. Site goes up with the Discord side set up. Nothing breaks, nobody notices.
2. Launcher ships with this in it, still reading the old password as a
   fallback. Everybody links their Discord over the next few days.
3. Once `thornswood.net/linked` shows everybody, run
   `Rotate-ServerPassword.ps1`. From that moment the old password is dead and
   the only way in is through Discord.

Rotating before step 2 locks out everybody including you.
