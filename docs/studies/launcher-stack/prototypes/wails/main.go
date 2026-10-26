// The Wails prototype for the launcher stack study (#3209): the window is
// index.html in the system web view (WebView2 on Windows). README.md has
// the contract every prototype keeps.
package main

import (
	"embed"
	"os"
	"os/exec"
	"runtime"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
)

//go:embed all:frontend
var assets embed.FS

type App struct{}

func (a *App) Ready() {
	if f := os.Getenv("PROTO_READY"); f != "" {
		os.WriteFile(f, []byte("ready"), 0o644)
	}
}

func (a *App) Play() {
	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		cmd = exec.Command("cmd.exe", "/c", "exit", "0")
		hide(cmd)
	} else {
		cmd = exec.Command("true")
	}
	if cmd.Start() == nil {
		if f := os.Getenv("PROTO_READY"); f != "" {
			os.WriteFile(f+".active", []byte("active"), 0o644)
		}
	}
}

func main() {
	app := &App{}
	err := wails.Run(&options.App{
		Title:            "Thornswood wails",
		Width:            1220,
		Height:           800,
		BackgroundColour: &options.RGBA{R: 20, G: 17, B: 14, A: 255},
		AssetServer:      &assetserver.Options{Assets: assets},
		Bind:             []interface{}{app},
	})
	if err != nil {
		println(err.Error())
	}
}
