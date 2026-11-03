// SPDX-License-Identifier: GPL-3.0-or-later
//
// qmc2mp3: decrypt one QQ Music encrypted file and, when the decrypted
// payload is Ogg Vorbis, transcode it to MP3 (OpenSwim Pro does not play Ogg).
//
// Built against the qmc-decoder library (GPL-3.0):
// https://github.com/ownlight6/qmc-decoder
//
// usage: qmc2mp3 <file.mgg|file.mflac|file.qmc*> [output_dir]

use qmc_decoder::{decrypt_file, Format};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn usage() {
    eprintln!("usage: qmc2mp3 <file.mgg|file.mflac|file.qmc*> [output_dir]");
    eprintln!("  decrypts a QQ Music download; .mgg/.qmcogg output is converted to 320k MP3");
    eprintln!("  ekey is fetched automatically, so QQ Music must be logged in on this Mac");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 || args[1] == "-h" || args[1] == "--help" {
        usage();
        std::process::exit(if args.len() < 2 { 2 } else { 0 });
    }

    let input = PathBuf::from(&args[1]);
    if !input.is_file() {
        eprintln!("ERR input not found: {}", input.display());
        std::process::exit(2);
    }

    let ext = input
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    let format = match Format::from_extension(&ext) {
        Some(f) => f,
        None => {
            eprintln!("ERR unsupported extension: .{ext}");
            std::process::exit(2);
        }
    };

    let dec_ext = format.decrypted_extension();
    let out_dir = args
        .get(2)
        .map(PathBuf::from)
        .unwrap_or_else(|| input.parent().unwrap_or(Path::new(".")).to_path_buf());
    fs::create_dir_all(&out_dir).ok();

    let stem = input.file_stem().and_then(|s| s.to_str()).unwrap_or("output");
    let output = out_dir.join(format!("{stem}.{dec_ext}"));

    match decrypt_file(&input, &output, format, None, true) {
        Ok(r) => {
            println!("decrypted: {}", r.output_path.display());
            if dec_ext == "ogg" {
                let mp3 = output.with_extension("mp3");
                let status = Command::new("ffmpeg")
                    .args([
                        "-nostdin",
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-y",
                        "-i",
                    ])
                    .arg(&output)
                    .args([
                        "-codec:a",
                        "libmp3lame",
                        "-b:a",
                        "320k",
                        "-map_metadata",
                        "0",
                        "-id3v2_version",
                        "3",
                    ])
                    .arg(&mp3)
                    .status();
                match status {
                    Ok(s) if s.success() => {
                        println!("converted: {}", mp3.display());
                        fs::remove_file(&output).ok();
                    }
                    _ => {
                        eprintln!("ERR ffmpeg failed, kept {}", output.display());
                        std::process::exit(1);
                    }
                }
            }
        }
        Err(e) => {
            eprintln!("ERR {e}");
            std::process::exit(1);
        }
    }
}
