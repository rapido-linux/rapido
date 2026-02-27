// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2025 SUSE LLC
use std::collections::{HashMap, HashSet};
use std::convert::TryFrom;
use std::env;
use std::fs;
use std::io;
use std::io::BufRead;
use std::io::Seek;
use std::io::Write;
use std::path::{self, Path, PathBuf, Component};

use elf::abi;
use elf::ElfStream;
use elf::endian::AnyEndian;

use crosvm::argument::{self, Argument};
mod kmod;
use kmod::kmod_context::{KmodContext, ModuleStatus, MODULE_DB_FILES};
extern crate kv_conf;

// FIXME: We should allow default search paths to be set at build time.
// On usr-merge systems, /X may be a symlink to /usr/X .
const BIN_PATHS: [&str; 5] = ["/usr/bin", "/usr/sbin", "/usr/lib/systemd", "/bin", "/sbin"];
// Extra search paths may be added at runtime via ELF RUNPATH/LibRunPath.
// $ARCH-linux-gnu is for Debian/Ubuntu.
#[cfg(target_arch = "x86_64")]
const LIB_PATHS: [&str; 5] = ["/usr/lib64", "/usr/lib", "/lib64", "/lib", "/usr/lib/x86_64-linux-gnu"];
#[cfg(target_arch = "aarch64")]
const LIB_PATHS: [&str; 5] = ["/usr/lib64", "/usr/lib", "/lib64", "/lib", "/usr/lib/aarch64-linux-gnu"];
#[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
const LIB_PATHS: [&str; 4] = ["/usr/lib64", "/usr/lib", "/lib64", "/lib"];
// FIXME: don't assume cwd parent location
const MANIFEST_PATHS: [&str; 1] = ["manifest"];
// FIXME: we shouldn't assume rapido-init location
const RAPIDO_INIT_PATH: &str = "target/release/rapido-init";
// FIXME: don't assume cwd location
const RAPIDO_BASH_RC_PATH: &str = "vm_autorun.env";

const GATHER_ITEM_IGNORE_PARENT: u32 =  1<<0;

// Don't print debug messages on release builds...
#[cfg(debug_assertions)]
macro_rules! dout {
    ($($l:tt)*) => { println!($($l)*); }
}
#[cfg(not(debug_assertions))]
macro_rules! dout {
    ($($l:tt)*) => {};
}

pub const CPIO_AMD_DEFAULT: cpio::ArchiveMd = cpio::ArchiveMd {
    nlink: 1,
    mode: cpio::S_IFREG | 0o777,
    uid: 0,
    gid: 0,
    mtime: 0,
    rmajor: 0,
    rminor: 0,
    len: 0,
};

struct Fsent {
    path: PathBuf,
    md: fs::Metadata,
}

// TODO: merge with GatherEnt, with a static option too?
#[derive(PartialEq, Debug)]
struct GatherItem {
    src: PathBuf,
    dst: PathBuf,
    flags: u32,
}

#[derive(Eq, PartialEq, Ord, PartialOrd, Debug)]
enum GatherEnt {
    // Name String may be an absolute host-source-path or a relative path
    // resolved via path_stat(). BIN_PATHS are searched if @String lacks a
    // '/' path separator. The cpio archived path matches the source path.
    // ELF dependencies are gathered for all Name* types if an execute mode
    // flag is present on the source file.
    Name(String),
    NameStatic(&'static str),
    // Same as above, but destination is explicitly provided.
    NameDst(&'static str, &'static Path),
    // Ignore if missing, instead of aborting.
    NameTry(String),
    // Same as Name, but always treated as a local path (no BIN_PATHS lookup).
    Path(PathBuf),
    // Same as Name, except search LIB_PATHS. Lib* types trigger ELF dependency
    // gathering regardles of mode flags.
    Lib(String),
    // library with extra search path(s) from ELF RUNPATH
    LibRunPath(String, Vec<String>),
    // Same as Name, except search MANIFEST_PATHS
    Manifest(String),
}

// We *should* be running as an unprivileged process, so don't filter or block
// access to parent or special paths; this should all be handled by the OS.
fn path_stat(ent: &GatherEnt) -> Result<Fsent, io::Error> {
    let name: &str = match ent {
        GatherEnt::Path(p) => match fs::symlink_metadata(&p) {
            Ok(md) => return Ok(Fsent {path: p.clone(), md: md}),
            Err(e) => return Err(e),
        }
        GatherEnt::Name(n) => &n,
        GatherEnt::NameDst(n, _) => n,
        GatherEnt::NameStatic(n) => n,
        GatherEnt::NameTry(n) => &n,
        GatherEnt::Lib(n) => &n,
        // it might be cleaner to add an extra enum for paths with separator...
        GatherEnt::LibRunPath(n, _) if n.contains(path::MAIN_SEPARATOR_STR) => &n,
        GatherEnt::LibRunPath(n, paths) => {
            for dir in paths.iter() {
                let p = PathBuf::from(dir).join(n);
                if let Ok(md) = fs::symlink_metadata(&p) {
                    return Ok(Fsent {path: p, md: md});
                }
            }
            // fallback to LIB_PATHS search
            &n
        }
        GatherEnt::Manifest(n) => &n,
    };

    dout!("resolving path for {:?}", name);
    // if name has any separator in it then we should handle it as a relative
    // or absolute path. This should be close enough as a check.
    if name.contains(path::MAIN_SEPARATOR_STR) {
        dout!("using relative / absolute path {:?} as-is", name);
        return match fs::symlink_metadata(name) {
            Ok(md) => Ok(Fsent {
                path: path::absolute(name).expect("absolute failed for good path"),
                md: md
            }),
            Err(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("{} missing", name)
                ));
            }
        }
    }

    // TODO: set search_paths with name above. Tuple assignment didn't work for me.
    let search_paths: &[&str] = match ent {
        GatherEnt::LibRunPath(_, _) | GatherEnt::Lib(_) => &LIB_PATHS,
        GatherEnt::Manifest(_) => &MANIFEST_PATHS,
        _ => &BIN_PATHS,
    };

    for dir in search_paths.iter() {
        let p = PathBuf::from(dir).join(name);
        if let Ok(md) = fs::symlink_metadata(&p) {
            return Ok(Fsent {path: p, md: md});
        }
    }

    return Err(io::Error::new(
        io::ErrorKind::NotFound,
        match ent {
            GatherEnt::LibRunPath(_, p) => {
                format!("{} missing from: {:?} & {:?}", name, p, search_paths)
            }
            _ => format!("{} missing from: {:?}", name, search_paths),
        }
    ));
}

// Parse ELF DT_NEEDED entries to gather shared object dependencies.
// DT_RUNPATH entries are retained as extra library search paths.
// XXX NameTry bins result in Lib or LibRunPath entries; if a binary
// is installed then it's reasonable to require presence of libs.
fn elf_deps(
    f: &fs::File,
    path: &Path,
    dups_filter: &mut HashSet<String>
) -> Result<Vec<GatherEnt>, io::Error> {
    let mut ret: Vec<GatherEnt> = vec![];

    let mut file = match ElfStream::<AnyEndian, _>::open_stream(f) {
        Ok(f) => f,
        Err(_) => {
            // ParseError::BadOffset / ParseError::BadMagic is returned
            // immediately for empty / non-elf, which we want to ignore.
            dout!("file {:?} not an elf", path);
            return Err(io::Error::from(io::ErrorKind::InvalidInput));
        }
    };

    let dynamics = match file.dynamic() {
        Ok(d) => {
            if d.is_none() {
                eprintln!("Failed to find .dynamic for {:?}", path);
                return Ok(ret);
            }
            d.unwrap()
        },
        Err(e) => {
            eprintln!("{:?} elf .dynamic error: {:?}", path, e);
            return Err(io::Error::from(io::ErrorKind::InvalidData));
        },
    };

    let mut runpath_offs: Vec<usize> = vec!();
    let mut needed_offs: Vec<usize> = vec!();
    for dyna in dynamics.iter() {
        let v = match dyna.d_tag {
            abi::DT_NEEDED => &mut needed_offs,
            abi::DT_RUNPATH => &mut runpath_offs,
            _ => continue,
        };

        match usize::try_from(dyna.d_val()) {
            Err(_) => {
                eprintln!("{:?} bad elf dynamic off {:?}", path, dyna);
                return Err(io::Error::from(io::ErrorKind::InvalidData));
            }
            Ok(str_off) => v.push(str_off),
        }
    }

    let dynsyms_strs = match file.dynamic_symbol_table() {
        Err(e) => {
            eprintln!("{:?} bad elf dynamic sym table: {:?}", path, e);
            return Err(io::Error::from(io::ErrorKind::InvalidData));
        },
        Ok(tup) => {
            if tup.is_none() {
                dout!("no tables for {:?}", path);
                return Ok(ret);
            }
            let (_, strs) = tup.unwrap();
            strs
        },
    };

    // get full list of runpaths first
    let runpaths: Vec<String> = runpath_offs.into_iter().filter_map(|o| {
        match dynsyms_strs.get(o) {
            Err(_) => None,
            Ok(s) => Some(s.to_string()),
        }
    }).collect();

    for str_off in needed_offs {
        match dynsyms_strs.get(str_off) {
            Ok(sraw) => {
                let s = sraw.to_string();
                if dups_filter.insert(s.clone()) {
                    dout!("new elf dependency({:?}): {:?}", str_off, s);
                    if runpaths.len() > 0 {
                        // would be nice to avoid cloning for every lib here:
                        // perhaps add a single GatherEnt::PathPush/Pop pair?
                        // RUNPATH rare enough that it's prob not worth it.
                        ret.push(GatherEnt::LibRunPath(s, runpaths.clone()));
                    } else {
                        ret.push(GatherEnt::Lib(s));
                    }
                } else {
                    dout!("duplicate elf dependency({:?}): {:?}", str_off, sraw);
                }
            },
            Err(e) => {
                eprintln!("{:?} bad elf dynamic sym table: {:?}", path, e);
                return Err(io::Error::from(io::ErrorKind::InvalidData));
            },
        };
    }

    Ok(ret)
}

// XXX: symlinks in parent ancestry will be archived as dirs
// FIXME: how does this handle relative "" parents?
// @child_amd provides the child metadata, which is used to mock up metadata
// for parent directories.
fn gather_archive_dirs<W: Seek + Write>(
    path: Option<&Path>,
    child_amd: &cpio::ArchiveMd,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    // path may come from parent(), hence Option
    let p = match path {
        None => return Ok(()),
        // don't canonicalize dirs: dest path may not match host
        Some(p) => p,
    };

    // path_stat() and dst assignment call absolute()
    if !p.is_absolute() {
        panic!("non-absolute path, check path_stat and dst paths");
    }

    if paths_seen.contains(p) {
        dout!("ignoring seen directory and parents: {:?}", p);
        return Ok(());
    }

    // mock up md to use for any parent directories. 0111: allow traversal
    let parent_dirs_amd = cpio::ArchiveMd{
        mode: match child_amd.mode & cpio::S_IFMT {
            cpio::S_IFDIR => child_amd.mode,
            _ => (child_amd.mode & !cpio::S_IFMT) | cpio::S_IFDIR | 0111,
        },
        nlink: 2,
        rmajor: 0,
        rminor: 0,
        len: 0,
        ..*child_amd
    };

    // order is important: parent dirs must be archived before children
    let mut here = PathBuf::from("/");
    for comp in p.components() {
        match comp {
            Component::RootDir => continue,
            Component::CurDir | Component::ParentDir => {
                // FIXME: absolute() does leave ParentDir components!
                panic!("got CurDir or ParentDir after canonicalization");
            },
            Component::Prefix(_) => {
                eprintln!("non-Unix path prefixes not supported");
                return Err(io::Error::from(io::ErrorKind::InvalidInput));
            },
            Component::Normal(c) => here.push(c),
        }

        if !paths_seen.insert(here.clone()) {
            dout!("ignoring seen directory: {:?}", here);
            continue;
        }

        cpio::archive_path(cpio_state, &here, &parent_dirs_amd, &mut cpio_writer)?;
        dout!("archived dir: {:?}", here);
    }

    Ok(())
}

fn gather_archive_elfs<W: Seek + Write>(
    mut elfs: Vec<GatherEnt>,
    libs_seen: &mut HashSet<String>,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    while let Some(ent) = elfs.pop() {
        let got = match path_stat(&ent) {
            Err(e) => {
                if let GatherEnt::NameTry(_) = ent {
                    continue;
                }
                return Err(e);
            }
            Ok(g) => g,
        };

        let dst: PathBuf;
        let (src, lib_ent): (&Path, bool) = match ent {
            GatherEnt::NameDst(_, d) => {
                dst = PathBuf::from(d);
                // we only have one internal NameDst user
                assert!(dst.is_absolute());
                (&got.path, false)
            }
            GatherEnt::LibRunPath(_, _) | GatherEnt::Lib(_) => {
                dst = got.path;
                (&dst, true)
            }
            _ => {
                dst = got.path;
                (&dst, false)
            }
        };

        // TODO: benchmark: insert(dst.clone()) vs contains(dst)+insert(dst)
        if paths_seen.contains(&dst) {
            dout!("ignoring seen elf: {:?}", &dst);
            continue;
        }

        let amd = cpio::ArchiveMd::from(&cpio_state, &got.md)?;
        gather_archive_dirs(
            dst.parent(),
            &amd,
            paths_seen,
            cpio_state,
            &mut cpio_writer
        )?;
        match amd.mode & cpio::S_IFMT {
            cpio::S_IFLNK => {
                // symlinks are tricky, so provide some restrictions:
                // - the host path must match the initramfs dest path
                // - targets be resolvable; no dangling / arbitrary links
                // - multiple indirect links will be collapsed
                if let GatherEnt::NameDst(_, _) = ent {
                    eprintln!("symlink source and cpio dest paths must match");
                    return Err(io::Error::from(io::ErrorKind::InvalidInput));
                }
                let canon_tgt = match src.canonicalize() {
                    Err(e) => {
                        eprintln!("{:?} canonicalize failed: {:?}", src, e);
                        continue;
                    },
                    Ok(t) => t,
                };
                cpio::archive_symlink(
                    cpio_state,
                    &dst,
                    &amd,
                    &canon_tgt,
                    &mut cpio_writer
                )?;
                dout!("archived symlink: {:?} ({:?})", &dst, canon_tgt);

                // could add a Path ent type to avoid String conversion here...
                if let Ok(t) = canon_tgt.into_os_string().into_string() {
                    let tgtent = match lib_ent {
                        true => GatherEnt::Lib(t),
                        false => GatherEnt::Name(t),
                    };
                    elfs.push(tgtent);
                } else {
                    eprintln!("non utf-8 symlink target {:?}", src);
                    return Err(io::Error::from(io::ErrorKind::InvalidInput));
                }
            }
            cpio::S_IFREG if amd.len > 0 => {
                let mut f = fs::OpenOptions::new().read(true).open(src)?;

                if amd.mode & 0o111 != 0 || lib_ent {
                    // ignore elf_deps errors: file is non-elf or malformed
                    if let Ok(mut d) = elf_deps(&f, src, libs_seen) {
                        elfs.append(&mut d);
                    }
                    // don't check for '#!' interpreters like Dracut, it's messy

                    f.seek(io::SeekFrom::Start(0))?;
                }
                cpio::archive_file(cpio_state, &dst, &amd, &f, &mut cpio_writer)?;
                dout!("archived elf: {:?}→{:?}", src, &dst);
            }
            cpio::S_IFDIR => {
                cpio::archive_path(
                    cpio_state,
                    &dst,
                    &amd,
                    &mut cpio_writer
                )?;
                dout!("archived elf dir: {:?}→{:?}", src, &dst);

                let mut entries = fs::read_dir(src)?
                    .map(|res| res.map(
                            |e| GatherEnt::Path(src.join(e.file_name()))
                        ))
                    .collect::<Result<Vec<_>, io::Error>>()?;
                // sort for reproducibility
                entries.sort();

                for entry in entries {
                    // "." and ".." are filtered by fs::read_dir()
                    // TODO: GATHER_ITEM_IGNORE_PARENT? paths_seen works for now
                    elfs.push(entry);
                }
            }
            _ => {
                cpio::archive_path(cpio_state, &dst, &amd, &mut cpio_writer)?;
                dout!("archived other: {:?}→{:?}", src, &dst);
            }
        };
        paths_seen.insert(dst);
    }

    Ok(())
}

fn archive_kmod_path<W: Seek + Write>(
    src: &Path,
    dst: &Path,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    let md = fs::symlink_metadata(src)?;
    let amd = cpio::ArchiveMd::from(cpio_state, &md)?;
    gather_archive_dirs(
        dst.parent(),
        &amd,
        paths_seen,
        cpio_state,
        &mut cpio_writer
    )?;

    let kmod_f = fs::File::open(src)?;
    cpio::archive_file(
        cpio_state,
        dst,
        &amd,
        &kmod_f,
        cpio_writer,
    )?;
    dout!("archived kmod: {:?} -> {:?}", src, dst);
    Ok(())
}

// XXX: Tumbleweed kmod is patched to use "/usr/lib/modules", while
// mainline kernel and Leap 15 use "/lib/modules". Worse still, there's no
// easy way to specify the directory for modprobe, so we use symlinks. Booo.
// See https://src.opensuse.org/pool/kmod/src/branch/factory/README.usrmerge
fn archive_kmods_symlink<W: Seek + Write>(
    paths_seen: &HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    let libp = Path::new("/lib");
    let (p, tgt) = match paths_seen.contains(libp) {
        false => (libp, Path::new("/usr/lib")),
        true => (Path::new("/lib/modules"), Path::new("/usr/lib/modules")),
    };
    let amd = cpio::ArchiveMd{
        nlink: 1,
        mode: cpio::S_IFLNK | 0o777,
        uid: 0,
        gid: 0,
        mtime: 0,
        rmajor: 0,
        rminor: 0,
        len: 0,
    };
    cpio::archive_symlink(cpio_state, &p, &amd, &tgt, &mut cpio_writer)?;
    dout!("archived kmod symlink {:?} ({:?})", p, tgt);
    Ok(())
}

fn gather_archive_kmod_and_deps<W: Seek + Write>(
    name: &str,
    kmod_dst_root: &Path,
    context: &KmodContext,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    let root_mod = match context.find(name) {
        None => return Err(io::Error::from(io::ErrorKind::NotFound)),
        Some(m) if m.status == ModuleStatus::Builtin => {
            dout!("{} builtin", name);
            return Ok(());
        },
        Some(m) => m,
    };

    // Fail if root mod or hard deps are missing.
    // No recursive checking here; modules.dep entry is complete
    // and doesn't contain Builtins.
    let kmod_dst = kmod_dst_root.join(&root_mod.rel_path);
    if paths_seen.insert(kmod_dst.clone()) {
        let kmod_src = context.module_root.join(&root_mod.rel_path);
        archive_kmod_path(
            &kmod_src,
            &kmod_dst,
            paths_seen,
            cpio_state,
            &mut cpio_writer
        )?;
    } else {
        dout!("skipping duplicate kmod {:?} and all deps", &kmod_dst);
        return Ok(());
    }

    for dep_path in root_mod.hard_deps_paths.iter() {
        let kmod_dst = kmod_dst_root.join(&dep_path);
        if paths_seen.insert(kmod_dst.clone()) {
            let kmod_src = context.module_root.join(&dep_path);
            archive_kmod_path(
                &kmod_src,
                &kmod_dst,
                paths_seen,
                cpio_state,
                &mut cpio_writer
            )?;
        } else {
            dout!("skipping duplicate kmod {:?}", &kmod_dst);
        }
    }

    // Attempt to pull in soft and weak dependencies for root_mod.
    // Not sure if we should be checking root_mod dependents.
    for soft_mod in root_mod.soft_deps_pre.iter()
        .chain(root_mod.soft_deps_post.iter())
        .chain(root_mod.weak_deps.iter()) {
        let m = match context.find(soft_mod) {
            None => {
                dout!("{:?} soft / weak kernel dep not found", soft_mod);
                continue;
            },
            Some(m) if m.status == ModuleStatus::Builtin => continue,
            Some(m) => m,
        };
        let kmod_dst = kmod_dst_root.join(&m.rel_path);
        if paths_seen.insert(kmod_dst.clone()) {
            let kmod_src = context.module_root.join(&m.rel_path);
            match archive_kmod_path(
                &kmod_src,
                &kmod_dst,
                paths_seen,
                cpio_state,
                &mut cpio_writer
            ) {
                Err(e) if e.kind() == io::ErrorKind::NotFound => {
                    dout!("{:?} soft / weak kernel dep missing", &kmod_src);
                    continue;
                },
                Err(e) => return Err(e),
                Ok(_) => {},
            }
        } else {
            dout!("skipping duplicate kmod {:?}", &kmod_dst);
        }
    }
    Ok(())
}

struct GatherKmods {
    kmod_dst_root: PathBuf,
    kmod_ctx: KmodContext,
}

impl GatherKmods {
    pub fn init<W: Seek + Write>(
        conf: &HashMap<String, String>,
        paths_seen: &mut HashSet<PathBuf>,
        cpio_state: &mut cpio::ArchiveState,
        mut cpio_writer: W,
    ) -> io::Result<Self> {
        let krel = rapido::conf_src_or_host_kernel_vers(&conf)?;
        let kmod_dst_root = PathBuf::from("/usr/lib/modules/").join(&krel);
        let kmod_ctx = match conf.get("KERNEL_INSTALL_MOD_PATH") {
            // should assert that KERNEL_SRC is set?
            Some(kmp) if !kmp.is_empty() => {
                KmodContext::new(
                    &PathBuf::from(kmp).join(format!("lib/modules/{krel}"))
                )
            }
            None | Some(_) if kmod_dst_root.exists() => {
                KmodContext::new(&kmod_dst_root)
            }
            None | Some(_) => {
                // assume that we have a non-Tumbleweed system
                KmodContext::new(&PathBuf::from("/lib/modules/").join(&krel))
            }
        };

        let kmod_ctx = match kmod_ctx {
            Err(e) => return Err(io::Error::new(io::ErrorKind::InvalidInput, e)),
            Ok(ctx) => ctx,
        };

        // XXX this should probably only be done *after* kmod gathering...
        // add module_data_paths inside initrd
        for file_name in MODULE_DB_FILES.iter() {
            let data_dst_path = kmod_dst_root.join(file_name);
            if paths_seen.insert(data_dst_path.clone()) {
                let data_src_path = kmod_ctx.module_root.join(file_name);
                match archive_kmod_path(
                    &data_src_path,
                    &data_dst_path,
                    paths_seen,
                    cpio_state,
                    &mut cpio_writer
                ) {
                    Err(e) if e.kind() == io::ErrorKind::NotFound => {
                        dout!("Module data path {:?} missing", data_src_path);
                        // TODO: only install required, and return error if missing
                    },
                    Err(e) => return Err(e),
                    Ok(_) => {},
                }
            }
        }

        Ok(GatherKmods{
            kmod_dst_root,
            kmod_ctx,
        })
    }
}

fn gather_archive_kmods<W: Seek + Write>(
    conf: &HashMap<String, String>,
    gk: &mut Option<GatherKmods>,
    kmods: &Vec<String>,
    ignore_missing: bool,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    if gk.is_none() {
        *gk = Some(
            GatherKmods::init(conf, paths_seen, cpio_state, &mut cpio_writer)?
        );
    }
    let kmod_dst_root = &gk.as_ref().unwrap().kmod_dst_root;
    let kmod_ctx = &gk.as_ref().unwrap().kmod_ctx;

    for name in kmods.iter() {
        match gather_archive_kmod_and_deps(
            &name,
            &kmod_dst_root,
            &kmod_ctx,
            paths_seen,
            cpio_state,
            &mut cpio_writer
        ) {
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                if ignore_missing {
                    dout!("ignoring missing kmod: {}", &name);
                    continue;
                }
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("{} missing from: {:?}", name, kmod_ctx.module_root)
                ));
            }
            Err(e) => return Err(e),
            Ok(_) => {},
        };
    }

    Ok(())
}

fn gather_archive_data<W: Seek + Write>(
    mut items: Vec<GatherItem>,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    // walk each src entry and append any newly found dirs for later traversal
    while let Some(item) = items.pop() {
        let src_md = match fs::symlink_metadata(&item.src) {
            Ok(md) => md,
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("{:?} missing", item.src)
                ));
            }
            Err(e) => return Err(e),
        };
        let src_amd = cpio::ArchiveMd::from(cpio_state, &src_md)?;

        if !paths_seen.insert(item.dst.clone()) {
            dout!("ignoring seen data path: {:?}", &item.dst);
            continue;
        }
        if item.flags & GATHER_ITEM_IGNORE_PARENT == 0 {
            gather_archive_dirs(
                item.dst.parent(),
                &src_amd,
                paths_seen,
                cpio_state,
                &mut cpio_writer
            )?;
        }

        match src_amd.mode & cpio::S_IFMT {
            // add any subdirs to gather list
            cpio::S_IFDIR => {
                cpio::archive_path(
                    cpio_state,
                    &item.dst,
                    &src_amd,
                    &mut cpio_writer
                )?;
                dout!("archived data dir: {:?}→{:?}", item.src, item.dst);

                let mut entries = fs::read_dir(&item.src)?
                    .map(|res| res.map(|e| e.file_name()))
                    .collect::<Result<Vec<_>, io::Error>>()?;
                // sort for reproducibility
                entries.sort();

                for entry in entries {
                    // "." and ".." are filtered by fs::read_dir()
                    items.push(GatherItem {
                        src: item.src.join(&entry),
                        dst: item.dst.join(&entry),
                        // we don't need to check for parent dir existence, as
                        // we just archived it.
                        flags: GATHER_ITEM_IGNORE_PARENT,
                    });
                }
            },
            // dataless files can use archive_path
            cpio::S_IFREG if src_amd.len > 0 => {
                let f = fs::OpenOptions::new().read(true).open(&item.src)?;
                cpio::archive_file(
                    cpio_state,
                    &item.dst,
                    &src_amd,
                    &f,
                    &mut cpio_writer
                )?;
                dout!("archived data file: {:?}→{:?}", item.src, item.dst);
            },
            cpio::S_IFLNK => {
                let tgt = fs::read_link(&item.src)?;
                // XXX don't follow data symlinks to archive their targets
                cpio::archive_symlink(
                    cpio_state,
                    &item.dst,
                    &src_amd,
                    &tgt,
                    &mut cpio_writer
                )?;
                dout!("archived data symlink: {:?}→{:?}", item.src, item.dst);
            },
            _ => {
                cpio::archive_path(
                    cpio_state,
                    &item.dst,
                    &src_amd,
                    &mut cpio_writer
                )?;
                dout!("archived data path: {:?}→{:?}", item.src, item.dst);
            },
        };
    }

    Ok(())
}

fn populate_default_symlinks<W: Seek + Write>(
    paths_seen: &HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    let amd = cpio::ArchiveMd{
            nlink: 1,
            mode: cpio::S_IFLNK | 0o777,
            uid: 0,
            gid: 0,
            mtime: 0,
            rmajor: 0,
            rminor: 0,
            len: 0,
    };

    // on Tumbleweed, bash won't start without this symlink. /lib64 may already
    // exist (e.g. it's a regular dir on Leap), so conditionally create it.
    let p = Path::new("/lib64");
    if !paths_seen.contains(p) {
        let tgt = Path::new("/usr/lib64");
        cpio::archive_symlink(cpio_state, p, &amd, tgt, &mut cpio_writer)?;
    }
    // xfstests (and others) hardcode /bin/bash
    let p = Path::new("/bin");
    if !paths_seen.contains(p) {
        let tgt = Path::new("/usr/bin");
        cpio::archive_symlink(cpio_state, p, &amd, tgt, &mut cpio_writer)?;
    }
    // kernel request_module() runs CONFIG_MODPROBE_PATH. On 15.6 it's under...
    let p = Path::new("/sbin");
    if !paths_seen.contains(p) {
        let tgt = Path::new("/usr/sbin");
        cpio::archive_symlink(cpio_state, p, &amd, tgt, &mut cpio_writer)?;
    } else {
        let p = Path::new("/sbin/modprobe");
        let tgt = Path::new("/usr/sbin/modprobe");
        if !paths_seen.contains(p) && paths_seen.contains(tgt) {
            cpio::archive_symlink(cpio_state, p, &amd, tgt, &mut cpio_writer)?;
        }
    }

    // TODO: should only need this if we actually installed kmods
    archive_kmods_symlink(paths_seen, cpio_state, &mut cpio_writer)?;
    Ok(())
}

struct ArgsState {
    cpio_output_arg: Option<PathBuf>,
    manifests: Vec<io::BufReader<fs::File>>,
}

// loosely based on the Linux kernel's gen_init_cpio format
const MANIFEST_FORMAT: &str = "\nManifest format:\n\
    # a comment\n\
    bin ELF\n\
    try-bin ELF\n\
    kmod MODULE\n\
    try-kmod MODULE\n\
    dir NAME\n\
    file NAME LOCATION\n\
    autorun LOCATION [LOCATION ...]\n\
    tree NAME LOCATION\n\
    slink NAME TARGET\n\
    include MANIFEST\n\
    \n\
    ELF:      ELF executable, archived with all needed dependencies.\n\
              Directory paths are traversed, with child paths handled as ELFs.\n\
    MODULE:   kernel module, archived with dependencies\n\
    NAME:     name of the file or directory in the archive\n\
    LOCATION: local path to obtain data, user, group, mode etc. for this item\n\
    MANIFEST: file containing entries described above\n";


fn args_usage(params: &[Argument]) {
    argument::print_help("rapido-cut", "", params);
    print!("{}", MANIFEST_FORMAT);
}

fn args_process_one(name: &str, value: Option<&str>, state: &mut ArgsState) -> argument::Result<()> {
    // unwrap: callers ensure value is Some if arg requires one
    match name {
        "output" => state.cpio_output_arg = Some(PathBuf::from(value.unwrap())),
        "manifest" => {
            // TODO: avoid to_string()
            match path_stat(&GatherEnt::Manifest(value.unwrap().to_string())) {
                Err(e) => {
                    return Err(
                        argument::Error::InvalidValue {
                            value: value.unwrap().to_string(),
                            expected: format!("failed to stat: {:?}", e),
                        }
                    );
                }
                Ok(fs) => {
                    match fs::OpenOptions::new().read(true).open(&fs.path) {
                        Err(e) => {
                            return Err(
                                argument::Error::InvalidValue {
                                    value: value.unwrap().to_string(),
                                    expected: format!("failed to open: {:?}", e),
                                }
                            );
                        }
                        Ok(f) => state.manifests.push(io::BufReader::new(f)),
                    };
                }
            }
        }
        "help" => return Err(argument::Error::PrintHelp),
        _ => unreachable!(),
    };
    Ok(())
}

fn args_process() -> argument::Result<ArgsState> {
    let mut state = ArgsState {
        cpio_output_arg: None,
        manifests: vec!(),
    };
    let params = &[
        Argument::value(
            "output",
            "INITRAMFS",
            "Write initramfs archive to this file path."
        ),
        Argument::value(
            "manifest",
            "FILE",
            "Manifest file describing initramfs contents",
        ),
        Argument::short_flag('h', "help", "Print help message."),
    ];

    let args = env::args().skip(1); // skip binary name
    let match_res = argument::set_arguments(args, params, |name, value| {
        args_process_one(name, value, &mut state)
    });

    if let Err(e) = match_res {
        args_usage(params);
        Err(e)
    } else {
        Ok(state)
    }
}

// open the arguments-specified output file, or fallback to conf(DRACUT_OUT).
// If DRACUT_OUT is used then the path will be stashed in args_out. I.e.
// args_out will always be Some(cpio_output_path) on success.
fn cpio_out_open(
    args_out: &mut Option<PathBuf>,
    conf: &HashMap<String, String>
) -> io::Result<io::BufWriter<fs::File>> {
    let mut fops = fs::OpenOptions::new();
    // for rapido we normally want to truncate any existing output file
    fops.read(false).write(true).create(true).truncate(true);
    let f = match args_out {
        Some(p) => fops.open(p),
        None => {
            // unwrap: DRACUT_OUT set in conf_defaults()
            let p = PathBuf::from(&conf.get("DRACUT_OUT").unwrap());
            let f = fops.open(&p);
            // stash path for info msg
            *args_out = Some(p);
            f
        }
    };

    match f {
        Err(e) => {
            eprintln!("failed to open cpio output: {}", e);
            Err(e)
        }
        Ok(f) => Ok(io::BufWriter::new(f)),
    }
}

fn main() -> io::Result<()> {
    let mut cpio_state = cpio::ArchiveState::new(cpio::ArchiveProperties{
        // Attempt 4K file data alignment within archive for Btrfs/XFS reflinks
        data_align: 4096,
        ..cpio::ArchiveProperties::default()
    });
    let mut args_state = match args_process() {
        Ok(state) => state,
        Err(argument::Error::PrintHelp) => return Ok(()),
        Err(e) => return Err(io::Error::new(io::ErrorKind::InvalidInput, e.to_string())),
    };

    let (conf, mut cpio_writer) = match rapido::host_rapido_conf_open(
        rapido::RAPIDO_CONF_PATH
    ) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            eprintln!("no rapido.conf, using defaults");
            let c = rapido::conf_defaults();
            let mut w = cpio_out_open(&mut args_state.cpio_output_arg, &c)?;
            // archive empty rapido.conf
            cpio::archive_path(
                &mut cpio_state,
                &Path::new("/rapido.conf"),
                &CPIO_AMD_DEFAULT,
                &mut w
            )?;
            (c, w)
        }
        Err(e) => {
            eprintln!("failed to open rapido.conf: {:?}", e);
            return Err(e);
        }
        Ok((f, p)) => {
            let mut c = rapido::conf_defaults();
            let cf_md = f.metadata()?;
            let cf_amd = cpio::ArchiveMd::from(&cpio_state, &cf_md)?;
            let mut cf_rd = io::BufReader::new(f);
            if let Err(e) = kv_conf::kv_conf_process_append(&mut cf_rd, &mut c) {
                eprintln!("failed to process {:?}: {:?}", p, e);
                return Err(e);
            }

            let mut w = cpio_out_open(&mut args_state.cpio_output_arg, &c)?;
            // archive rapido.conf while still open here
            cf_rd.seek(io::SeekFrom::Start(0))?;
            cpio::archive_file(
                &mut cpio_state,
                &Path::new("/rapido.conf"),
                &cf_amd,
                &mut cf_rd,
                &mut w
            )?;
            (c, w)
        }
    };

    let mut libs_seen: HashSet<String> = HashSet::new();
    let mut paths_seen: HashSet<PathBuf> = HashSet::new();
    let mut gk: Option<GatherKmods> = None;
    manifest_parse(
        &conf,
        &mut gk,
        &mut libs_seen,
        &mut paths_seen,
        &mut cpio_state,
        &mut cpio_writer,
        &mut args_state.manifests
    )?;

    match fs::OpenOptions::new().read(true).open(RAPIDO_BASH_RC_PATH) {
        Err(e) => {
            eprintln!("failed to open {}: {:?}", RAPIDO_BASH_RC_PATH, e);
            return Err(e);
        }
        Ok(f) => {
            let f_md = f.metadata()?;
            let f_amd = cpio::ArchiveMd::from(&cpio_state, &f_md)?;
            cpio::archive_file(
                &mut cpio_state,
                &Path::new("/rapido.rc"),
                &f_amd,
                &f,
                &mut cpio_writer
            )?;
        }
    };

    let core_elfs = vec!(
        // this will only install if /rdinit isn't already provided by manifest
        GatherEnt::NameDst(RAPIDO_INIT_PATH, Path::new("/rdinit")),
        // rapido-init core deps
        GatherEnt::NameStatic("mount"),
        GatherEnt::NameStatic("setsid"),
        GatherEnt::NameStatic("bash"),
        GatherEnt::NameStatic("stty"),
        // TODO only install if we have non-builtin kmods!
        GatherEnt::NameStatic("modprobe")
    );
    gather_archive_elfs(
        core_elfs,
        &mut libs_seen,
        &mut paths_seen,
        &mut cpio_state,
        &mut cpio_writer
    )?;

    // TODO avoid stringify
    let conf_kmods = rapido::conf_kmod_deps(&conf)
        .into_iter()
        .map(|s| s.to_string())
        .collect();
    gather_archive_kmods(
        &conf,
        &mut gk,
        &conf_kmods,
        false,
        &mut paths_seen,
        &mut cpio_state,
        &mut cpio_writer
    )?;

    populate_default_symlinks(&paths_seen, &mut cpio_state, &mut cpio_writer)?;

    let len = cpio::archive_trailer(&mut cpio_state, &mut cpio_writer)?;
    cpio_writer.flush()?;
    println!(
        "initramfs {} written ({} bytes)",
        // unwrap: cpio_out_open() ensures Some(out_path)
        args_state.cpio_output_arg.unwrap().display(),
        len
    );

    Ok(())
}

// var replacement mostly copied from kv-conf
fn sub_path_vars(
    conf: &HashMap<String, String>,
    p: &str
) -> Result<String, &'static str> {
    // TODO: fastpath if no '$'
    let mut unquoted_val = String::new();
    let mut var_next = false;
    for mut quoteblock in p.split_inclusive('$') {
        if var_next {
            var_next = false;
            let mut varblock = quoteblock.split_inclusive(&['{', '}']);
            if varblock.next() != Some("{") {
                return Err("variables must be wrapped in {} braces");
            }
            let var = varblock.next();
            if var.is_none() || !var.unwrap().ends_with("}") {
                return Err("no closing brace for variable");
            }
            let key = var.unwrap().strip_suffix("}").unwrap();

            match conf.get(key) {
                Some(val) => unquoted_val.push_str(val),
                None => return Err("invalid variable substitution: not seen"),
            };
            match varblock.next() {
                // retain any post-var content
                Some(t) => quoteblock = &t,
                None => continue,
            };
        }

        if quoteblock.ends_with("$") {
            var_next = true;
            unquoted_val.push_str(quoteblock.strip_suffix("$").unwrap());
        } else {
            unquoted_val.push_str(quoteblock);
        }
    }

    Ok(unquoted_val)
}

fn manifest_name_sub(conf: &HashMap<String, String>, name: Option<&str>) -> io::Result<String> {
    match name {
        None => {
            // TODO: move up+up to caller to print full manifest line
            eprintln!("manifest line missing path");
            Err(io::Error::from(io::ErrorKind::InvalidData))
        }
        Some(p) => match sub_path_vars(conf, p) {
            Err(emsg) => {
                eprintln!("{}", emsg);
                Err(io::Error::from(io::ErrorKind::InvalidData))
            }
            Ok(p) => Ok(p),
        }
    }
}

fn manifest_name_sub_abs_path(
    conf: &HashMap<String, String>,
    name: Option<&str>
) -> io::Result<PathBuf> {
    let p = manifest_name_sub(conf, name)?;
    match path::absolute(p) {
        Err(_) => {
            eprintln!("invalid path for absolute conversion");
            Err(io::Error::from(io::ErrorKind::InvalidData))
        }
        Ok(p) => Ok(p),
    }
    // check / store path_seen here?
}

fn manifest_dir<W: Seek + Write>(
    conf: &HashMap<String, String>,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
    name: Option<&str>
) -> io::Result<()> {
    let dir = manifest_name_sub_abs_path(conf, name)?;
    let amd = cpio::ArchiveMd { mode: cpio::S_IFDIR | 0o777, ..CPIO_AMD_DEFAULT };
    gather_archive_dirs(
        dir.parent(),
        &amd,
        paths_seen,
        cpio_state,
        &mut cpio_writer
    )?;
    cpio::archive_path(cpio_state, &dir, &amd, &mut cpio_writer)
}

fn manifest_slink<W: Seek + Write>(
    conf: &HashMap<String, String>,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
    name: Option<&str>,
    slink_tgt: Option<&str>
) -> io::Result<()> {
    let p = manifest_name_sub_abs_path(conf, name)?;
    let tgt = manifest_name_sub_abs_path(conf, slink_tgt)?;
    let amd = cpio::ArchiveMd { mode: cpio::S_IFLNK | 0o777, ..CPIO_AMD_DEFAULT };
    gather_archive_dirs(
        p.parent(),
        &amd,
        paths_seen,
        cpio_state,
        &mut cpio_writer
    )?;
    cpio::archive_symlink(cpio_state, &p, &amd, &tgt, &mut cpio_writer)
}

fn manifest_file<W: Seek + Write>(
    conf: &HashMap<String, String>,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
    name: Option<&str>,
    src: Option<&str>
) -> io::Result<()> {
    let p = manifest_name_sub_abs_path(conf, name)?;
    // TODO: we could prob make the src file optional (for empty files)
    let src = manifest_name_sub(conf, src)?;

    let f = fs::File::open(src)?;
    let src_md = f.metadata()?;
    // XXX unlike others, amd is based on the src file.
    let src_amd = cpio::ArchiveMd::from(cpio_state, &src_md)?;

    gather_archive_dirs(
        p.parent(),
        &src_amd,
        paths_seen,
        cpio_state,
        &mut cpio_writer
    )?;
    cpio::archive_file(cpio_state, &p, &src_amd, &f, &mut cpio_writer)
}

fn manifest_autorun<W: Seek + Write>(
    conf: &HashMap<String, String>,
    paths_seen: &mut HashSet<PathBuf>,
    autorun_idx: &mut u32,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
    name: Option<&str>
) -> io::Result<()> {
    let src = manifest_name_sub_abs_path(conf, name)?;
    let dst = match src.file_name() {
        None => return Err(io::Error::from(io::ErrorKind::InvalidInput)),
        Some(n) if n.to_str().is_none() => {
            return Err(io::Error::from(io::ErrorKind::InvalidInput));
        }
        Some(n) => PathBuf::from(&format!(
            "/rapido_autorun/{:03}-{}",
            autorun_idx,
            n.to_str().unwrap()
        )),
    };
    *autorun_idx += 1;

    let f = fs::File::open(src)?;
    let src_md = f.metadata()?;
    let src_amd = cpio::ArchiveMd::from(cpio_state, &src_md)?;

    gather_archive_dirs(
        // TODO: could shortcut for single /rapido_autorun
        dst.parent(),
        &src_amd,
        paths_seen,
        cpio_state,
        &mut cpio_writer
    )?;
    cpio::archive_file(cpio_state, &dst, &src_amd, &f, &mut cpio_writer)
}

fn manifest_tree<W: Seek + Write>(
    conf: &HashMap<String, String>,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
    name: Option<&str>,
    src: Option<&str>
) -> io::Result<()> {
    let dst = manifest_name_sub_abs_path(conf, name)?;
    if !dst.is_absolute() {
        eprintln!("tree DEST paths must be absolute");
        return Err(io::Error::from(io::ErrorKind::InvalidInput));
    }
    let src = manifest_name_sub(conf, src)?;
    gather_archive_data(
        vec!(GatherItem { src: PathBuf::from(src), dst, flags: 0, }),
        paths_seen,
        cpio_state,
        &mut cpio_writer
    )
}

fn manifest_parse_one<W: Seek + Write>(
    conf: &HashMap<String, String>,
    gk: &mut Option<GatherKmods>,
    libs_seen: &mut HashSet<String>,
    paths_seen: &mut HashSet<PathBuf>,
    autorun_idx: &mut u32,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
    line: &mut String,
    fests: &mut Vec<io::BufReader<fs::File>>
) -> io::Result<()> {
    let mut iter = line.split_whitespace();
    let etype = match iter.next() {
        None => return Ok(()),
        Some(t) if t.starts_with('#') => return Ok(()),
        Some(t) => t,
    };

    match etype {
        "dir" => {
            manifest_dir(conf,
                paths_seen,
                cpio_state,
                cpio_writer,
                iter.next()
            )
        }
        "slink" => {
            manifest_slink(
                conf,
                paths_seen,
                cpio_state,
                cpio_writer,
                iter.next(),
                iter.next()
            )
        }
        "include" => {
            let p = manifest_name_sub(conf, iter.next())?;
            // should we skip already-seen manifests completely?
            let fs = path_stat(&GatherEnt::Manifest(p))?;
            let f = fs::OpenOptions::new().read(true).open(&fs.path)?;
            fests.push(io::BufReader::new(f));
            Ok(())
        }
        "file" => {
            manifest_file(
                conf,
                paths_seen,
                cpio_state,
                cpio_writer,
                iter.next(),
                iter.next()
            )
        }
        // bin <name>
        // <name> is used for source and archive destination path.
        // <name> paths not containing a '/' are searched for under BIN_PATHS,
        // otherwise they're treated as relative or absolute paths.
        // If path resolution finds a symlink then the symlink will be archived
        // and the symlink target will be handled as a "bin" file.
        //
        // FIXME: if a symlink target doesn't contain a '/' then it should *not*
        // trigger BIN_PATHS search.
        "bin" => {
            let src = manifest_name_sub(conf, iter.next())?;
            gather_archive_elfs(
                vec!(GatherEnt::Name(src)),
                libs_seen,
                paths_seen,
                cpio_state,
                cpio_writer
            )
        }
        "try-bin" => {
            let src = manifest_name_sub(conf, iter.next())?;
            gather_archive_elfs(
                vec!(GatherEnt::NameTry(src)),
                libs_seen,
                paths_seen,
                cpio_state,
                cpio_writer
            )
        }
        "kmod" => {
            match iter.next() {
                None => Err(io::Error::from(io::ErrorKind::InvalidData)),
                Some(kmod) => {
                    gather_archive_kmods(
                        conf,
                        gk,
                        &mut vec!(kmod.to_string()),
                        false,
                        paths_seen,
                        cpio_state,
                        cpio_writer
                    )
                }
            }
        }
        "try-kmod" => {
            match iter.next() {
                None => Err(io::Error::from(io::ErrorKind::InvalidData)),
                Some(kmod) => {
                    gather_archive_kmods(
                        conf,
                        gk,
                        &mut vec!(kmod.to_string()),
                        // ignore_missing:
                        true,
                        paths_seen,
                        cpio_state,
                        cpio_writer
                    )
                }
            }
        }
        "autorun" => {
            let autorun_idx_before = *autorun_idx;
            // old cut script "$*" legacy: autorun supports multiple LOCATIONs
            while let Some(autorun_path) = iter.next() {
                manifest_autorun(
                    conf,
                    paths_seen,
                    autorun_idx,
                    cpio_state,
                    &mut cpio_writer,
                    Some(autorun_path)
                )?;
            }
            match autorun_idx_before == *autorun_idx {
                true => Err(io::Error::from(io::ErrorKind::InvalidData)),
                false => Ok(()),
            }
        }
        "tree" => {
            manifest_tree(
                conf,
                paths_seen,
                cpio_state,
                cpio_writer,
                iter.next(),
                iter.next()
            )
        }

        // from kernel gen_init_cpio. not needed (yet)...
        // nod <name> <mode> <uid> <gid> <dev_type> <maj> <min>
        // pipe <name> <mode> <uid> <gid>
        // sock <name> <mode> <uid> <gid>
        _ => Err(io::Error::from(io::ErrorKind::Unsupported)),
    }?;

    if let Some(trail) = iter.next() {
        eprintln!("error: unhandled parameter: {}", trail);
        return Err(io::Error::from(io::ErrorKind::InvalidInput));
    }
    Ok(())
}

fn manifest_parse<W: Seek + Write>(
    conf: &HashMap<String, String>,
    gk: &mut Option<GatherKmods>,
    libs_seen: &mut HashSet<String>,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_out: W,
    fests: &mut Vec<io::BufReader<fs::File>>,
) -> io::Result<()> {
    let mut autorun_idx: u32 = 0;
    let mut lbuf = String::new();
    // "include" appends to @fests for immediate handling as .last()
    loop {
        let fest: &mut io::BufReader<fs::File> = match fests.last_mut() {
            None => return Ok(()),
            Some(fest) => fest,
        };

        match fest.read_line(&mut lbuf) {
            Err(e) => {
                eprintln!("failed to read manifest line: {}", e);
                return Err(io::Error::from(io::ErrorKind::BrokenPipe));
            }
            Ok(n) if n > 16 * 1024 => {
                eprintln!("line too long: {}", n);
                return Err(io::Error::from(io::ErrorKind::InvalidInput));
            }
            Ok(n) if n == 0 => {
                // EOF returns 0, leave lbuf empty
                fests.pop();
                continue;
            }
            Ok(_) => {},
        }

        if let Err(e) = manifest_parse_one(
            &conf,
            gk,
            libs_seen,
            paths_seen,
            &mut autorun_idx,
            cpio_state,
            &mut cpio_out,
            &mut lbuf,
            fests
        ) {
            eprintln!("failed to parse manifest line: {}", lbuf);
            return Err(e);
        }
        lbuf.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    use std::ffi::OsString;
    use std::os::unix::fs::OpenOptionsExt;

    struct TempDir {
        pub dir: PathBuf,
        pub dirname: String,
    }
    impl TempDir {
        pub fn new() -> TempDir {
            let mut b = [0u8; 16];
            let mut dirname = String::from("test-rapido-cut-");
            fs::File::open("/dev/urandom").unwrap().read_exact(&mut b).unwrap();
            for i in &b {
                dirname.push_str(&format!("{:02x}", i));
            }
            fs::create_dir(&dirname).unwrap();
            TempDir { dir: PathBuf::from(&dirname), dirname }
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            assert!(self.dir.is_dir());
            fs::remove_dir_all(&self.dir).unwrap();
        }
    }

    fn test_manifest_parse<W: Seek + Write>(
        conf: &HashMap<String, String>,
        cpio_state: &mut cpio::ArchiveState,
        mut cpio_out: W,
        fest_rdr: io::BufReader<fs::File>,
    ) -> io::Result<()> {
        let mut libs_seen: HashSet<String> = HashSet::new();
        let mut paths_seen: HashSet<PathBuf> = HashSet::new();
        let mut gk: Option<GatherKmods> = None;
        let mut fests = vec!(fest_rdr);
        manifest_parse(
            conf,
            &mut gk,
            &mut libs_seen,
            &mut paths_seen,
            cpio_state,
            &mut cpio_out,
            &mut fests,
        )
    }

    #[test]
    fn test_manifest_include() {
        let conf = rapido::conf_defaults();
        let td = TempDir::new();
        let ifest = format!("{}/readthis.fest", td.dirname);
        fs::write(&ifest, "dir /frominclude\n").unwrap();

        let basefest = format!("{}/base.fest", td.dirname);
        fs::write(
            &basefest,
            format!("dir /basefirst\ninclude {}\ndir /baseafter", ifest)
        ).unwrap();

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());

        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&basefest).unwrap()
        );

        test_manifest_parse(&conf, &mut cpio_state, &mut cpio_out, rdr)
            .expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();
        let ae = aw.next().unwrap().unwrap();
        // cpio::path_trim_prefixes() drops the '/' prefix
        assert_eq!(ae.name_str(), "basefirst");
        let ae = aw.next().unwrap().unwrap();
        assert_eq!(ae.name_str(), "frominclude");
        let ae = aw.next().unwrap().unwrap();
        assert_eq!(ae.name_str(), "baseafter");
    }

    #[test]
    fn test_manifest_symlink() {
        let conf = rapido::conf_defaults();
        let td = TempDir::new();
        let fest = format!("{}/test.fest", td.dirname);
        fs::write(&fest, "dir /a\nslink /b /a").unwrap();

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());

        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&fest).unwrap()
        );
        test_manifest_parse(&conf, &mut cpio_state, &mut cpio_out, rdr)
            .expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();
        let ae = aw.next().unwrap().unwrap();
        // cpio::path_trim_prefixes() drops the '/' prefix
        assert_eq!(ae.name_str(), "a");
        assert_eq!(ae.md.mode & cpio::S_IFMT, cpio::S_IFDIR);
        let ae = aw.next().unwrap().unwrap();
        assert_eq!(ae.name_str(), "b");
        assert_eq!(ae.md.mode & cpio::S_IFMT, cpio::S_IFLNK);
        assert_eq!(ae.md.len, 2);
    }

    #[test]
    fn test_manifest_vars() {
        let conf = HashMap::from([
            ("KEY1".to_string(), "VAL1".to_string()),
            ("KEY2".to_string(), "VAL2".to_string()),
        ]);
        let td = TempDir::new();
        let fest = format!("{}/test.fest", td.dirname);
        fs::write(&fest, "dir /a${KEY1}x\nslink /${KEY2} /a${KEY1}x").unwrap();

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());

        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&fest).unwrap()
        );
        test_manifest_parse(&conf, &mut cpio_state, &mut cpio_out, rdr)
            .expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();
        let ae = aw.next().unwrap().unwrap();
        // cpio::path_trim_prefixes() drops the '/' prefix
        assert_eq!(ae.name_str(), "aVAL1x");
        assert_eq!(ae.md.mode & cpio::S_IFMT, cpio::S_IFDIR);
        let ae = aw.next().unwrap().unwrap();
        assert_eq!(ae.name_str(), "VAL2");
        assert_eq!(ae.md.mode & cpio::S_IFMT, cpio::S_IFLNK);
        assert_eq!(ae.md.len, 7);   // /aVAL1x
    }

    #[test]
    fn test_manifest_file() {
        let conf = rapido::conf_defaults();
        let td = TempDir::new();
        let data = b"this is some data";
        let file = format!("{}/test.data", td.dirname);
        fs::write(&file, &data).unwrap();
        let fest = format!("{}/test.fest", td.dirname);
        fs::write(&fest, format!("file /a/b {}", file)).unwrap();

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());

        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&fest).unwrap()
        );
        test_manifest_parse(&conf, &mut cpio_state, &mut cpio_out, rdr)
            .expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();
        let ae = aw.next().unwrap().unwrap();
        // parent dirs are automatically added
        assert_eq!(ae.name_str(), "a");
        assert_eq!(ae.md.mode & cpio::S_IFMT, cpio::S_IFDIR);
        let ae = aw.next().unwrap().unwrap();
        assert_eq!(ae.name_str(), "a/b");
        assert_eq!(ae.md.mode & cpio::S_IFMT, cpio::S_IFREG);
        assert_eq!(ae.md.len, data.len() as u32);
    }

    #[test]
    fn test_manifest_bin() {
        let conf = rapido::conf_defaults();
        let td = TempDir::new();
        let fest = format!("{}/test.fest", td.dirname);
        // unlike "bin", "try-bin" ignores missing files
        fs::write(&fest, "bin bash\ntry-bin th1s-doe5-not-ex1st").unwrap();

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());

        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&fest).unwrap()
        );
        test_manifest_parse(&conf, &mut cpio_state, &mut cpio_out, rdr)
            .expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();

        // archive should carry:
        // + parent directories
        // + bash (binary)
        // + bash (symlink) *if* BIN_PATHS resolved a symlink before binary
        // + any elf dependencies
        let mut got_bash = false;
        while let Some(ae) = aw.next() {
            assert!(ae.is_ok());
            let ae = ae.unwrap();
            let an = ae.name_str();
            if ae.md.mode & cpio::S_IFMT == cpio::S_IFREG && an.ends_with("/bash") {
                got_bash = true;
            }
        }
        assert!(got_bash);
    }

    #[test]
    fn test_manifest_elf_dir_traverse() {
        let conf = rapido::conf_defaults();
        let td = TempDir::new();

        fs::create_dir_all(&format!("{}/this/is/a/tree", td.dirname)).unwrap();
        fs::File::create(&format!("{}/this/file", td.dirname)).unwrap();
        fs::create_dir_all(&format!("{}/this/is/dir/child", td.dirname)).unwrap();

        // copy bash into our directory tree
        let src = path_stat(&GatherEnt::NameStatic("bash")).unwrap();
        let mut inf = fs::OpenOptions::new().read(true).open(&src.path)
            .unwrap();
        let mut outf_ops = fs::OpenOptions::new();
        // need to set exec mode to trigger ELF parsing...
        outf_ops.write(true).create(true).mode(0o777);
        let mut outf = outf_ops.open(&format!("{}/this/is/bash", td.dirname))
            .unwrap();
        io::copy(&mut inf, &mut outf).expect("copy failed");

        // get a list of bash ELF NEEDED dependencies
        inf.seek(io::SeekFrom::Start(0)).unwrap();
        let deps = elf_deps(&inf, &src.path, &mut HashSet::new()).unwrap();

        let fest = format!("{}/test.fest", td.dirname);
        // XXX needs a '/' separator, otherwise will trigger BIN_PATH lookup!
        // TODO: fix this by using a bin-tree manifest directive instead?
        fs::write(&fest, format!("bin ./{}", td.dirname)).unwrap();

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());

        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&fest).unwrap()
        );
        test_manifest_parse(&conf, &mut cpio_state, &mut cpio_out, rdr)
            .expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();

        // archive should carry
        // + parent dirs
        // + full directory tree
        // + bash bin (copied into tree)
        // + bash ELF dependencies
        //
        // check for files only
        let mut got_files: Vec<OsString> = vec!();

        while let Some(ae) = aw.next() {
            assert!(ae.is_ok());
            let ae = ae.unwrap();
            let an = ae.name_str();
            match ae.md.mode & cpio::S_IFMT {
                cpio::S_IFREG | cpio::S_IFLNK => {
                    let p = Path::new(an).file_name().unwrap().to_os_string();
                    got_files.push(p);
                },
                _ => {},
            };
        }

        [
            OsString::from("file"),
            OsString::from("bash"),
            OsString::from("test.fest"),
        ].iter().for_each(
            |e| assert!(
                got_files.contains(&e), "{:?} missing from {:?}", e, got_files
            )
        );
        deps.iter().filter_map(|e| match e {
            GatherEnt::LibRunPath(n, _) => Some(OsString::from(n)),
            GatherEnt::Lib(n) => Some(OsString::from(n)),
            _ => panic!("got non lib in ELF deps"),
        })
        .for_each(
            |e| assert!(
                got_files.contains(&e), "{:?} missing from {:?}", e, got_files
            )
        );
    }

    // based on test_kmod_context_full_load()
    fn test_kmods_populate(kmods_root: &str) {
        fs::create_dir_all(&kmods_root).unwrap();

        fs::create_dir(&format!("{kmods_root}/kernel")).unwrap();
        fs::File::create(&format!("{kmods_root}/kernel/mod_a.ko")).unwrap();
        fs::File::create(&format!("{kmods_root}/kernel/mod_b.ko.xz")).unwrap();
        fs::File::create(&format!("{kmods_root}/kernel/mod_c.ko")).unwrap();

        fs::write(
            &format!("{kmods_root}/modules.dep"),
            concat!(
                "kernel/mod_a.ko: kernel/mod_b.ko.xz kernel/mod_c.ko\n",
                "kernel/mod_b.ko.xz:\n"
            )
        ).unwrap();
        fs::write(
            &format!("{kmods_root}/modules.softdep"),
            "softdep mod_a pre: mod_d post: mod_e mod_f\n"
        ).unwrap();
        fs::write(
            &format!("{kmods_root}/modules.weakdep"),
            concat!(
                "weakdep mod_a mod_g\nweakdep mod_a mod_h\n",
                "weakdep mod_b mod_i\nweakdep mod_b mod_j\n"
            )
        ).unwrap();
        fs::write(
            &format!("{kmods_root}/modules.builtin"),
            "kernel/mod_builtin.ko\n"
        ).unwrap();
        fs::write(
            &format!("{kmods_root}/modules.alias"),
            "alias alias_for_b mod_b\nalias mod-b mod_b\nalias mod-intel-b mod_b\n"
        ).unwrap();
    }

    #[test]
    fn test_manifest_kmods() {
        let td = TempDir::new();

        let conf = HashMap::from([
            ("KERNEL_INSTALL_MOD_PATH".to_string(), format!("{}/mods", td.dirname)),
            ("KERNEL_RELEASE".to_string(), "6.66".to_string()),
        ]);

        let kmods_root_dir = format!("{}/mods/lib/modules/6.66", td.dirname);
        test_kmods_populate(&kmods_root_dir);

        let fest = format!("{}/test.fest", td.dirname);
        fs::write(&fest, "kmod mod_a\nkmod mod-builtin\ntry-kmod mod-no").unwrap();

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());

        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&fest).unwrap()
        );
        test_manifest_parse(&conf, &mut cpio_state, &mut cpio_out, rdr)
            .expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();

        // archive should carry:
        // + parent directories
        // + mod_a.ko
        // + mod_a hard dependencies: mod_b and mod_c
        // + Linux kmod dependencies: modules.dep, etc.
        let mut got_mods: HashSet<OsString> = HashSet::new();

        while let Some(ae) = aw.next() {
            assert!(ae.is_ok());
            let ae = ae.unwrap();
            let an = ae.name_str();
            if ae.md.mode & cpio::S_IFMT == cpio::S_IFREG {
                let p = Path::new(an).file_name().unwrap().to_os_string();
                assert!(got_mods.insert(p));
            }
        }
        assert_eq!(
            got_mods,
            HashSet::from([
                OsString::from("modules.dep"),
                OsString::from("modules.softdep"),
                OsString::from("modules.alias"),
                OsString::from("modules.builtin"),
                OsString::from("modules.weakdep"),
                OsString::from("mod_a.ko"),
                OsString::from("mod_b.ko.xz"),
                OsString::from("mod_c.ko"),
            ])
        );
    }

    #[test]
    fn test_manifest_autorun() {
        let conf = rapido::conf_defaults();
        let td = TempDir::new();

        let inc_autorun = format!("{}/inc_autorun.sh", td.dirname);
        fs::write(&inc_autorun, "echo second\n").unwrap();

        let last_autorun = format!("{}/last_autorun.sh", td.dirname);
        fs::write(&last_autorun, "echo third\n").unwrap();

        // multiple autorun locations can be placed on one line
        let inc_fest = format!("{}/included.fest", td.dirname);
        fs::write(
            &inc_fest,
            format!("autorun {} {}\n", inc_autorun, last_autorun)
        ).unwrap();

        let autorun = format!("{}/autorun.sh", td.dirname);
        fs::write(&autorun, "echo first\n").unwrap();

        let fest = format!("{}/test.fest", td.dirname);
        fs::write(
            &fest,
            format!("autorun {}\ninclude {}\ndir /baseafter", autorun, inc_fest)
        ).unwrap();

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());

        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&fest).unwrap()
        );
        test_manifest_parse(&conf, &mut cpio_state, &mut cpio_out, rdr)
            .expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();

        // archive should carry:
        // + parent directories
        // + autorun files, prefixed with an incrementing index
        let mut got_files: HashSet<OsString> = HashSet::new();

        while let Some(ae) = aw.next() {
            assert!(ae.is_ok());
            let ae = ae.unwrap();
            let an = ae.name_str();
            if ae.md.mode & cpio::S_IFMT == cpio::S_IFREG {
                let p = Path::new(an).file_name().unwrap().to_os_string();
                assert!(got_files.insert(p));
            }
        }
        assert_eq!(
            got_files,
            HashSet::from([
                OsString::from("000-autorun.sh"),
                OsString::from("001-inc_autorun.sh"),
                OsString::from("002-last_autorun.sh"),
            ])
        )
    }

    #[test]
    fn test_manifest_tree() {
        let conf = rapido::conf_defaults();
        let td = TempDir::new();

        fs::create_dir_all(&format!("{}/this/is/a/tree", td.dirname)).unwrap();
        fs::File::create(&format!("{}/this/file", td.dirname)).unwrap();
        fs::File::create(&format!("{}/this/is/file", td.dirname)).unwrap();
        fs::create_dir_all(&format!("{}/this/is/dir/child", td.dirname)).unwrap();

        let fest = format!("{}/test.fest", td.dirname);
        fs::write(&fest, format!("tree / {}", td.dirname)).unwrap();

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());

        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&fest).unwrap()
        );
        test_manifest_parse(&conf, &mut cpio_state, &mut cpio_out, rdr)
            .expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();

        let mut got_paths: Vec<String> = vec!();

        while let Some(ae) = aw.next() {
            assert!(ae.is_ok());
            let ae = ae.unwrap();
            let an = ae.name_str();
            got_paths.push(an.to_string());
        }
        assert_eq!(
            got_paths,
            vec!(
                // TODO: we don't need '/' archived in initramfs
                String::from("/"),
                String::from("this"),
                String::from("this/is"),
                String::from("this/is/file"),
                String::from("this/is/dir"),
                String::from("this/is/dir/child"),
                String::from("this/is/a"),
                String::from("this/is/a/tree"),
                String::from("this/file"),
                String::from("test.fest"),
            )
        )
    }

    #[test]
    fn test_paths_seen() {
        let conf = rapido::conf_defaults();
        let td = TempDir::new();
        fs::create_dir_all(&format!("{}/this/is/dir", td.dirname)).unwrap();

        let fest = format!("{}/test.fest", td.dirname);
        fs::write(&fest, format!("bin bash\ntree / {}", td.dirname)).unwrap();
        let rdr = io::BufReader::new(
            fs::OpenOptions::new().read(true).open(&fest).unwrap()
        );

        let props = cpio::ArchiveProperties{
            data_align: 4096,
            ..cpio::ArchiveProperties::default()
        };
        let mut cpio_state = cpio::ArchiveState::new(props);
        let mut cpio_out = io::Cursor::new(Vec::new());
        let mut libs_seen: HashSet<String> = HashSet::new();
        let mut paths_seen: HashSet<PathBuf> = HashSet::new();
        let mut gk: Option<GatherKmods> = None;
        manifest_parse(
            &conf,
            &mut gk,
            &mut libs_seen,
            &mut paths_seen,
            &mut cpio_state,
            &mut cpio_out,
            &mut vec!(rdr),
        ).expect("bad manifest");

        cpio_out.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = cpio::archive_walk(cpio_out).unwrap();

        while let Some(ae) = aw.next() {
            assert!(ae.is_ok());
            let ae = ae.unwrap();
            // we (currently) archive "/" when provided as tree dest, while
            // cpio::archive_X strips a '/' prefix for non-root.
            let p = match ae.name_str() {
                "/" => PathBuf::from("/"),
                nonroot => PathBuf::from(&format!("/{}", nonroot)),
            };

            assert_eq!(
                paths_seen.contains(&p),
                true,
                "{:?} missing from paths_seen: {:?}", p, paths_seen);
        }
    }
}
