// The Slint prototype for the launcher stack study (#3209): a native window
// drawn by Slint's own renderer. README.md has the contract every prototype
// keeps.
#![windows_subsystem = "windows"]

use std::cell::Cell;
use std::process::Command;
use std::rc::Rc;
use std::time::Duration;

slint::slint! {
    import { Button } from "std-widgets.slint";
    export component Proto inherits Window {
        title: "Thornswood slint";
        preferred-width: 1220px;
        preferred-height: 800px;
        background: rgb(20, 17, 14);
        in property <image> art;
        in-out property <string> state: "Ready to launch";
        callback play();
        Image { source: art; width: parent.width; height: parent.height; image-fit: cover; }
        VerticalLayout {
            x: 48px; y: parent.height - self.preferred-height - 48px;
            width: 260px; spacing: 12px;
            Text { text: "THORNSWOOD"; font-size: 40px; color: rgb(234, 223, 200); }
            Button { text: "Play"; height: 56px; clicked => { root.play(); } }
            Text { text: root.state; color: white; }
        }
    }
}

fn here() -> std::path::PathBuf {
    std::env::current_exe().unwrap().parent().unwrap().to_path_buf()
}

fn ready_file() -> Option<String> {
    std::env::var("PROTO_READY").ok().filter(|s| !s.is_empty())
}

fn music() {
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::Media::Audio::{PlaySoundW, SND_ASYNC, SND_FILENAME, SND_LOOP};
        let wide: Vec<u16> = here().join("loop.wav").as_os_str().to_string_lossy().encode_utf16().chain(Some(0)).collect();
        PlaySoundW(wide.as_ptr(), std::ptr::null_mut(), SND_ASYNC | SND_LOOP | SND_FILENAME);
    }
}

fn start_game(ui: &Proto) {
    #[cfg(windows)]
    let child = {
        use std::os::windows::process::CommandExt;
        Command::new("cmd.exe").args(["/c", "exit", "0"]).creation_flags(0x0800_0000).spawn()
    };
    #[cfg(not(windows))]
    let child = Command::new("true").spawn();
    if let Ok(c) = child {
        ui.set_state(format!("Started {}", c.id()).into());
        if let Some(f) = ready_file() {
            let _ = std::fs::write(f + ".active", "active");
        }
    }
}

fn main() {
    let ui = Proto::new().unwrap();
    if let Ok(img) = slint::Image::load_from_path(&here().join("art.png")) {
        ui.set_art(img);
    }
    let weak = ui.as_weak();
    ui.on_play(move || {
        music();
        start_game(&weak.unwrap());
    });
    let fired = Rc::new(Cell::new(false));
    let weak = ui.as_weak();
    ui.window()
        .set_rendering_notifier(move |state, _| {
            if let slint::RenderingState::AfterRendering = state {
                if !fired.replace(true) {
                    if let Some(f) = ready_file() {
                        let _ = std::fs::write(f, "ready");
                    }
                    let weak = weak.clone();
                    slint::Timer::single_shot(Duration::from_secs(4), move || {
                        music();
                        start_game(&weak.unwrap());
                    });
                }
            }
        })
        .unwrap();
    ui.run().unwrap();
}
