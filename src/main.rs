use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::exit;

use clap::Parser;
use silk_rs::{decode_silk, encode_silk};

const TARGETS: &[&str] = &["dingdong.pcm", "dingdong1.pcm"];
const DEFAULT_DIR: &str = "/Applications/zoom.us.app/Contents/Resources";
// Zoom's .pcm chimes are SILK v3 streams ("#!SILK_V3\n" magic), not raw PCM.
const SILK_MAGIC: &[u8] = b"#!SILK_V3";
const SAMPLE_RATE: i32 = 24000;
const BIT_RATE: i32 = 24000;
const FRAME_SAMPLES: usize = (SAMPLE_RATE as usize / 1000) * 40; // 40 ms encoder frame

/// Silence Zoom's doorbell chime — or replace it with something better.
///
/// Zoom plays a "ding dong" doorbell (dingdong.pcm / dingdong1.pcm) when
/// someone enters the waiting room or joins a meeting. This tool overwrites
/// those files with silence, a fart, or the classic AIM buddy-in sound.
///
/// The originals are backed up next to the files (*.pcm.bak) the first time
/// you run it, so --restore can always put the doorbell back. Zoom's sound
/// files are SILK v3 streams despite the .pcm extension; replacements are
/// encoded with the real SILK codec so Zoom plays them natively.
///
/// Zoom's files are owned by root, so apply/restore need sudo. Zoom app
/// updates reinstall the original sounds — just run the tool again.
#[derive(Parser)]
#[command(name = "dingdong-ditch", version, about, verbatim_doc_comment)]
#[command(after_help = "\
EXAMPLES:
  sudo dingdong-ditch                    silence the doorbell
  sudo dingdong-ditch --fart             make it fart
  sudo dingdong-ditch --aim              party like it's 1999
  sudo dingdong-ditch --restore          bring back the dingdong
  dingdong-ditch --fart --preview f.wav  listen before you commit (no sudo)
")]
struct Cli {
    /// Replace the chime with a fart instead of silence
    #[arg(long, conflicts_with_all = ["aim", "restore"])]
    fart: bool,

    /// Replace the chime with the classic AIM buddy-in door sound
    #[arg(long, conflicts_with = "restore")]
    aim: bool,

    /// Restore the original chime from the *.pcm.bak backups
    #[arg(long)]
    restore: bool,

    /// Don't touch Zoom; write the replacement audio to a WAV file instead.
    /// The audio is round-tripped through the SILK codec first, so the file
    /// is exactly what Zoom would play.
    #[arg(long, value_name = "OUT_WAV", conflicts_with = "restore")]
    preview: Option<PathBuf>,

    /// Directory holding Zoom's sound files
    #[arg(long, value_name = "DIR", env = "DINGDONG_DIR", default_value = DEFAULT_DIR)]
    dir: PathBuf,
}

fn main() {
    let cli = Cli::parse();
    let sound = if cli.fart {
        Sound::Fart
    } else if cli.aim {
        Sound::Aim
    } else {
        Sound::Silence
    };

    let result = if let Some(path) = &cli.preview {
        write_preview(path, sound)
    } else {
        if !cli.dir.is_dir() {
            eprintln!("error: {} not found — is Zoom installed?", cli.dir.display());
            exit(1);
        }
        if cli.restore {
            restore_backups(&cli.dir)
        } else {
            ditch(&cli.dir, sound)
        }
    };

    if let Err(e) = result {
        if e.kind() == ErrorKind::PermissionDenied {
            if is_root() {
                eprintln!("error: permission denied even though you're root.");
                eprintln!();
                eprintln!("macOS App Management is blocking changes inside Zoom.app. Grant your");
                eprintln!("terminal app the permission, then re-run:");
                eprintln!();
                eprintln!("  System Settings → Privacy & Security → App Management → enable your terminal");
                eprintln!();
                eprintln!("shortcut to that pane:");
                eprintln!("  open \"x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles\"");
            } else {
                eprintln!("error: permission denied — Zoom's files are owned by root.");
                eprintln!("try: sudo dingdong-ditch{}", sound.flag());
            }
        } else {
            eprintln!("error: {e}");
        }
        exit(1);
    }
}

fn is_root() -> bool {
    unsafe extern "C" {
        fn geteuid() -> u32;
    }
    unsafe { geteuid() == 0 }
}

#[derive(Clone, Copy, PartialEq)]
enum Sound {
    Silence,
    Fart,
    Aim,
}

impl Sound {
    fn verb(self) -> &'static str {
        match self {
            Sound::Silence => "silenced",
            Sound::Fart => "farted",
            Sound::Aim => "buddy'd",
        }
    }

    fn flag(self) -> &'static str {
        match self {
            Sound::Silence => "",
            Sound::Fart => " --fart",
            Sound::Aim => " --aim",
        }
    }
}

fn replacement_silk(sound: Sound) -> std::io::Result<Vec<u8>> {
    let samples = match sound {
        Sound::Silence => vec![0i16; FRAME_SAMPLES * 10],
        Sound::Fart => embedded(FART_PCM),
        Sound::Aim => embedded(BUDDYIN_PCM),
    };
    to_zoom_silk(&samples)
}

fn ditch(dir: &Path, sound: Sound) -> std::io::Result<()> {
    let payload = replacement_silk(sound)?;
    for name in TARGETS {
        let path = dir.join(name);
        let original = fs::read(&path)?;

        let backup = path.with_extension("pcm.bak");
        if !backup.exists() && original.starts_with(SILK_MAGIC) {
            fs::write(&backup, &original)?;
        }

        fs::write(&path, &payload)?;
        println!("{} {} ({} bytes)", sound.verb(), path.display(), payload.len());
    }
    Ok(())
}

fn restore_backups(dir: &Path) -> std::io::Result<()> {
    for name in TARGETS {
        let path = dir.join(name);
        let backup = path.with_extension("pcm.bak");
        if !backup.exists() {
            eprintln!(
                "no backup for {} — reinstall Zoom to get the original back",
                path.display()
            );
            continue;
        }
        fs::copy(&backup, &path)?;
        println!("restored {}", path.display());
    }
    Ok(())
}

/// Encode s16 samples to a SILK v3 stream laid out like Zoom's: the magic is
/// followed by a newline that the stock encoder doesn't emit.
fn to_zoom_silk(samples: &[i16]) -> std::io::Result<Vec<u8>> {
    let mut pcm = Vec::with_capacity(samples.len() * 2);
    for s in samples {
        pcm.extend_from_slice(&s.to_le_bytes());
    }
    let silk = encode_silk(pcm, SAMPLE_RATE, BIT_RATE, false)
        .map_err(|e| std::io::Error::other(format!("SILK encode failed: {e:?}")))?;
    let mut out = Vec::with_capacity(silk.len() + 1);
    out.extend_from_slice(SILK_MAGIC);
    out.push(b'\n');
    out.extend_from_slice(&silk[SILK_MAGIC.len()..]);
    Ok(out)
}

/// Round-trip the replacement through the SILK codec and write it as a WAV,
/// so the preview is exactly what Zoom will play.
fn write_preview(path: &Path, sound: Sound) -> std::io::Result<()> {
    let silk = replacement_silk(sound)?;
    let mut stripped = Vec::with_capacity(silk.len());
    stripped.extend_from_slice(SILK_MAGIC);
    stripped.extend_from_slice(&silk[SILK_MAGIC.len() + 1..]); // drop Zoom's '\n'
    let pcm = decode_silk(stripped, SAMPLE_RATE)
        .map_err(|e| std::io::Error::other(format!("SILK decode failed: {e:?}")))?;
    write_wav(path, &pcm)?;
    println!("wrote {} — try: afplay {}", path.display(), path.display());
    Ok(())
}

fn write_wav(path: &Path, pcm: &[u8]) -> std::io::Result<()> {
    let sr = SAMPLE_RATE as u32;
    let mut wav = Vec::with_capacity(44 + pcm.len());
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + pcm.len() as u32).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16u32.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes()); // PCM
    wav.extend_from_slice(&1u16.to_le_bytes()); // mono
    wav.extend_from_slice(&sr.to_le_bytes());
    wav.extend_from_slice(&(sr * 2).to_le_bytes());
    wav.extend_from_slice(&2u16.to_le_bytes());
    wav.extend_from_slice(&16u16.to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&(pcm.len() as u32).to_le_bytes());
    wav.extend_from_slice(pcm);
    fs::write(path, wav)
}

/// Real recordings, embedded as trimmed/normalized 24 kHz mono s16le.
/// Regenerate an asset from a new source WAV with:
///   afconvert -f WAVE -d LEI16@24000 -c 1 <source.wav> tmp.wav
/// then strip the WAV header (and ideally trim silence / normalize).
const FART_PCM: &[u8] = include_bytes!("../assets/fart.pcm");
const BUDDYIN_PCM: &[u8] = include_bytes!("../assets/buddyin.pcm");

fn embedded(pcm: &[u8]) -> Vec<i16> {
    let n = pcm.len() / 2;
    let padded = n.div_ceil(FRAME_SAMPLES) * FRAME_SAMPLES;
    let mut samples = vec![0i16; padded];
    for (i, chunk) in pcm.chunks_exact(2).enumerate() {
        samples[i] = i16::from_le_bytes([chunk[0], chunk[1]]);
    }
    samples
}
