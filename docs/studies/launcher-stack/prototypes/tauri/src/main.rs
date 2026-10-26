// The Tauri prototype for the launcher stack study (#3209): the window is
// web\index.html in the system web view (WebView2 on Windows). README.md has
// the contract every prototype keeps.
#![windows_subsystem = "windows"]

use std::process::Command;

fn ready_file() -> Option<String> {
    std::env::var("PROTO_READY").ok().filter(|s| !s.is_empty())
}

#[tauri::command]
fn ready() {
    if let Some(f) = ready_file() {
        let _ = std::fs::write(f, "ready");
    }
}

#[tauri::command]
fn play() {
    #[cfg(windows)]
    let child = {
        use std::os::windows::process::CommandExt;
        Command::new("cmd.exe").args(["/c", "exit", "0"]).creation_flags(0x0800_0000).spawn()
    };
    #[cfg(not(windows))]
    let child = Command::new("true").spawn();
    if let (Ok(_), Some(f)) = (child, ready_file()) {
        let _ = std::fs::write(f + ".active", "active");
    }
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![ready, play])
        .run(tauri::generate_context!())
        .expect("tauri failed to start");
}
