// The egui prototype for the launcher stack study (#3209): an immediate mode
// window drawn by eframe. README.md has the contract every prototype keeps.
#![windows_subsystem = "windows"]

use eframe::egui;
use std::process::Command;
use std::time::{Duration, Instant};

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

struct Proto {
    art_loaded: bool,
    frames: u32,
    shown: Option<Instant>,
    started: bool,
    state: String,
}

impl Proto {
    fn start_game(&mut self) {
        #[cfg(windows)]
        let child = {
            use std::os::windows::process::CommandExt;
            Command::new("cmd.exe").args(["/c", "exit", "0"]).creation_flags(0x0800_0000).spawn()
        };
        #[cfg(not(windows))]
        let child = Command::new("true").spawn();
        if let Ok(c) = child {
            self.state = format!("Started {}", c.id());
            if let Some(f) = ready_file() {
                let _ = std::fs::write(f + ".active", "active");
            }
        }
    }
}

impl eframe::App for Proto {
    fn ui(&mut self, root: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = root.ctx().clone();
        egui::CentralPanel::default().frame(egui::Frame::NONE.fill(egui::Color32::from_rgb(0x14, 0x11, 0x0e))).show(root, |ui| {
            let rect = ui.max_rect();
            let uri = format!("file://{}", here().join("art.png").display());
            let art = egui::Image::new(uri);
            self.art_loaded = matches!(art.load_for_size(ui.ctx(), rect.size()), Ok(egui::load::TexturePoll::Ready { .. }));
            art.paint_at(ui, rect);
            let area = egui::Rect::from_min_size(egui::pos2(rect.left() + 48.0, rect.bottom() - 180.0), egui::vec2(260.0, 140.0));
            ui.scope_builder(egui::UiBuilder::new().max_rect(area), |ui| {
                ui.label(egui::RichText::new("THORNSWOOD").size(40.0).color(egui::Color32::from_rgb(0xea, 0xdf, 0xc8)));
                if ui.add_sized([220.0, 56.0], egui::Button::new(egui::RichText::new("Play").size(20.0))).clicked() {
                    music();
                    self.start_game();
                }
                ui.label(egui::RichText::new(&self.state).color(egui::Color32::WHITE));
            });
        });
        // Counted from the first frame that painted the art: the one after it
        // is the first the window has shown with the art on it.
        if self.art_loaded || self.frames > 0 {
            self.frames += 1;
        }
        if self.frames == 2 {
            self.shown = Some(Instant::now());
            if let Some(f) = ready_file() {
                let _ = std::fs::write(f, "ready");
            }
        }
        match self.shown {
            Some(t) if !self.started && t.elapsed() >= Duration::from_secs(4) => {
                self.started = true;
                music();
                self.start_game();
            }
            Some(_) if !self.started => ctx.request_repaint_after(Duration::from_millis(100)),
            _ => ctx.request_repaint(),
        }
    }
}

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_title("Thornswood egui").with_inner_size([1220.0, 800.0]),
        ..Default::default()
    };
    eframe::run_native("Thornswood egui", options, Box::new(|cc| {
        egui_extras::install_image_loaders(&cc.egui_ctx);
        Ok(Box::new(Proto { art_loaded: false, frames: 0, shown: None, started: false, state: "Ready to launch".into() }))
    }))
}
