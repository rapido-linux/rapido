// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2025 SUSE S.A.
use std::collections::HashMap;
use std::fs::File;
use std::io::{self, BufRead, BufReader};
use std::path::Path;
use std::path::PathBuf;

// --- Constants ---

pub const MODULE_DB_FILES: [&str; 15] = [
    "modules.dep",
    "modules.dep.bin",
    "modules.alias",
    "modules.alias.bin",
    "modules.softdep",
    "modules.weakdep",
    "modules.builtin",
    "modules.builtin.bin",
    "modules.builtin.alias.bin",
    "modules.builtin.modinfo",
    "modules.symbols",
    "modules.symbols.bin",
    "modules.order",
    "modules.fips",
    "modules.devname",
];

// --- Module Data Structures ---

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModuleStatus {
    Builtin,
    LoadableModule,
}

#[derive(Debug, Clone, PartialEq)]
pub struct KmodModule {
    pub status: ModuleStatus,
    // rel_path is relative to KmodContext.module_root
    pub rel_path: String,
    pub hard_deps_paths: Vec<String>,
    pub soft_deps_pre: Vec<String>,
    pub soft_deps_post: Vec<String>,
    pub weak_deps: Vec<String>,
}

// --- Context and APIs ---

pub struct KmodContext {
    modules_hash: HashMap<String, KmodModule>,
    alias_map: HashMap<String, String>,
    pub module_root: PathBuf,
}

fn read_lines(filename: &Path) -> io::Result<io::Lines<BufReader<File>>> {
    let file = File::open(filename)?;
    Ok(BufReader::new(file).lines())
}

// extract: from _path: 'kernel/sub/module.ko{.xz,.zst,.gz}' -> name: 'module'
fn extract_module_name(path_str: &str) -> String {
    let path = PathBuf::from(path_str);
    // file_stem: 'kernel/sub/module.ko{.xz,.zst,.gz}' -> file_stem: 'module{.ko}'
    let file_stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(path_str);

    // file_stem_strip_suffix: 'module{.ko}' -> name: 'module'
    let base_name = file_stem.strip_suffix(".ko").unwrap_or(file_stem);
    // aligns with libkmod: 'kmod_module_get_name' logic.
    // name is always normalized (dashes are replaced with underscores).
    base_name.replace('-', "_")
}

impl KmodModule {
    pub fn name(&self) -> String {
        extract_module_name(&self.rel_path)
    }

    pub fn hard_deps(&self) -> Vec<String> {
        self.hard_deps_paths.iter().map(|p| extract_module_name(&p)).collect()
    }
}

impl KmodContext {
    pub fn new(dirname: &Path) -> Result<Self, String> {
        let mut ctx = KmodContext {
            modules_hash: HashMap::new(),
            alias_map: HashMap::new(),
            module_root: PathBuf::from(dirname),
        };

        ctx.load_hard_dependencies()
            .map_err(|e| format!("Failed to load modules.dep: {}", e))?;

        ctx.load_soft_dependencies()
            .map_err(|e| format!("Failed to load modules.softdep: {}", e))?;

        if let Err(e) = ctx.load_weak_dependencies() {
            eprintln!("Old kernel? modules.weakdep load failure ignored: {}", e);
        }

        ctx.load_builtin_modules()
            .map_err(|e| format!("Failed to load modules.builtin: {}", e))?;

        ctx.load_aliases()
            .map_err(|e| format!("Failed to load modules.alias: {}", e))?;

        Ok(ctx)
    }

    // Parses **modules.dep** (hard dependencies and module paths).
    fn load_hard_dependencies(&mut self) -> io::Result<()> {
        let path = self.module_root.join("modules.dep");

        for line in read_lines(&path)? {
            let line = line?;
            let parts: Vec<&str> = line.splitn(2, ':').collect();
            if parts.len() != 2 {
                continue;
            }

            let module_path_str = parts[0].trim();
            let module_name = extract_module_name(module_path_str);

            let dep_paths: Vec<String> = parts[1]
                .trim()
                .split_whitespace()
                .map(|p| p.to_string())
                .collect();

            match self.modules_hash.insert(
                module_name,
                KmodModule {
                    status: ModuleStatus::LoadableModule,
                    rel_path: String::from(module_path_str),
                    hard_deps_paths: dep_paths,
                    soft_deps_pre: Vec::new(),
                    soft_deps_post: Vec::new(),
                    weak_deps: Vec::new(),
                },
            ) {
                // modules.dep and modules.builtin entries should be unique
                Some(_) => {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        format!("duplicate entry: {:?}", module_path_str),
                    ))
                }
                None => {}
            };
        }

        Ok(())
    }

    // Parses **modules.softdep**
    fn load_soft_dependencies(&mut self) -> io::Result<()> {
        let path = self.module_root.join("modules.softdep");

        for line in read_lines(&path)? {
            let line = line?;
            // softdep mod_name pre: pre_mod1 pre_mod2 post: post_mod1
            let parts: Vec<&str> = line.split_whitespace().collect();

            if parts.len() < 3 || parts[0] != "softdep" {
                continue;
            }

            let module_name = parts[1].to_string();

            if let Some(module) = self.modules_hash.get_mut(&module_name) {
                let mut current_list = &mut module.soft_deps_pre;

                for &part in parts.iter().skip(2) {
                    match part {
                        "pre:" => current_list = &mut module.soft_deps_pre,
                        "post:" => current_list = &mut module.soft_deps_post,
                        _ => current_list.push(part.to_string()),
                    }
                }
            }
        }

        Ok(())
    }

    // Parses **modules.weakdep**.
    fn load_weak_dependencies(&mut self) -> io::Result<()> {
        let path = self.module_root.join("modules.weakdep");

        for line in read_lines(&path)? {
            let line = line?;
            // Format: as per depmod::output_weakdeps()
            // weakdep mod_name dep1
            // weakdep mod_name dep2
            let parts: Vec<&str> = line.split_whitespace().collect();

            if parts.len() != 3 || parts[0] != "weakdep" {
                continue;
            }

            let module_name = parts[1].to_string();
            let dep_name = parts[2].to_string();

            // Update the existing module
            if let Some(module) = self.modules_hash.get_mut(&module_name) {
                module.weak_deps.push(dep_name);
            }
        }

        Ok(())
    }

    // Parses **modules.builtin**.
    fn load_builtin_modules(&mut self) -> io::Result<()> {
        let path = self.module_root.join("modules.builtin");

        for line in read_lines(&path)? {
            let line = line?;
            let path_str = line.trim();

            if path_str.is_empty() {
                continue;
            }

            let module_name = extract_module_name(path_str);
            match self.modules_hash.insert(
                module_name,
                KmodModule {
                    status: ModuleStatus::Builtin,
                    rel_path: String::new(),
                    hard_deps_paths: Vec::new(),
                    soft_deps_pre: Vec::new(),
                    soft_deps_post: Vec::new(),
                    weak_deps: Vec::new(),
                },
            ) {
                // modules.dep and modules.builtin entries should be unique
                Some(_) => {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        format!("duplicate entry: {:?}", path_str),
                    ))
                }
                None => {}
            };
        }
        Ok(())
    }

    fn load_aliases(&mut self) -> io::Result<()> {
        let path = self.module_root.join("modules.alias");
        if !path.exists() {
            // missing aliases not considered an error
            return Ok(());
        }

        for line in read_lines(&path)? {
            let line = line?;
            let parts: Vec<&str> = line.split_whitespace().collect();
            // Format: alias <alias_name> <module_name>
            if parts.len() >= 3 && parts[0] == "alias" {
                let alias = parts[1].to_string();
                let module_name = parts[2].to_string();
                // A -> B
                self.alias_map.insert(alias.clone(), module_name.clone());
            }
        }
        Ok(())
    }

    pub fn find(&self, name: &str) -> Option<&KmodModule> {
        if let Some(module) = self.modules_hash.get(name) {
            return Some(module);
        }

        if let Some(actual_name) = self.alias_map.get(name) {
            if let Some(module) = self.modules_hash.get(actual_name) {
                return Some(module);
            }
        }

        // fallback once in case caller requested non-normalized name
        let normname = name.replace('-', "_");
        if normname != name {
            return self.find(&normname);
        }

        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    const TEST_ROOT_DIR: &str = "target/kmod_test_root";

    fn setup_test_dir(test_name: &str) -> PathBuf {
        let root_path = PathBuf::from(TEST_ROOT_DIR).join(test_name);
        if root_path.exists() {
            fs::remove_dir_all(&root_path).unwrap();
        }
        fs::create_dir_all(&root_path).unwrap();
        root_path
    }

    fn cleanup_test_dir(root_path: &PathBuf) {
        if root_path.exists() {
            fs::remove_dir_all(root_path).unwrap();
        }
    }

    fn write_test_file(base_path: &Path, filename: &str, content: &str) -> PathBuf {
        let path = base_path.join(filename);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(&path, content).unwrap();
        path
    }

    fn set_context(root_path: &Path) -> KmodContext {
        KmodContext {
            modules_hash: HashMap::new(),
            alias_map: HashMap::new(),
            module_root: root_path.to_path_buf(),
        }
    }

    #[test]
    fn test_new_with_valid_dir() {
        let root_path = setup_test_dir("test_new_success");
        write_test_file(&root_path, "modules.dep", "");
        write_test_file(&root_path, "modules.softdep", "");
        write_test_file(&root_path, "modules.weakdep", "");
        write_test_file(&root_path, "modules.builtin", "");

        match KmodContext::new(&root_path) {
            Ok(context) => {
                assert_eq!(context.module_root, root_path, "Module root path mismatch");
            }
            Err(e) => panic!("KmodContext::new failed unexpectedly on valid input: {}", e),
        }

        cleanup_test_dir(&root_path);
    }

    #[test]
    fn test_kmod_context_new_error() {
        let root_path = setup_test_dir("missing_dep_dir");
        // modules.*dep is missing (first hit load_hard_dependencies)
        match KmodContext::new(&root_path) {
            Ok(_) => panic!("Context should fail because modules.dep is missing"),
            Err(e) => assert!(e.contains("Failed to load modules.dep")),
        }
        cleanup_test_dir(&root_path);
    }

    #[test]
    fn test_extract_module_name() {
        // direct case
        assert_eq!(
            extract_module_name("drivers/sub1/sub2/sub3/module_name.ko.zst"),
            "module_name"
        );
        // different compression extensions
        assert_eq!(
            extract_module_name("drivers/sub1/sub2/sub3/module_name.ko.xz"),
            "module_name"
        );
        assert_eq!(
            extract_module_name("drivers/sub1/sub2/sub3/module_name.ko.zst"),
            "module_name"
        );
        // normalization
        assert_eq!(
            extract_module_name("drivers/sub1/sub2/sub3/module-name.ko.zst"),
            "module_name"
        );
        // No path and .ko suffix
        assert_eq!(extract_module_name("module_name"), "module_name");
        // full path provided
        assert_eq!(
            extract_module_name("/lib/modules/x.y.z/drivers/sub1/sub2/sub3/module-name.ko.zst"),
            "module_name"
        );
    }

    #[test]
    fn test_load_harddeps() {
        let root_path = setup_test_dir("harddeps");
        let mut ctx = set_context(&root_path);

        // define modules and hard dependencies
        let modules_dep_content = format!(
            "kernel/mod_a.ko: kernel/dep1.ko kernel/dep2.ko.xz\n\
             kernel/mod-b.ko:\n" // mod-b => mod_b
        );
        write_test_file(&root_path, "modules.dep", &modules_dep_content);
        write_test_file(&root_path, "kernel/dep1.ko", "");

        ctx.load_hard_dependencies().unwrap();

        // Check mod_a
        let mod_a = ctx.modules_hash.get("mod_a").expect("mod_a not found");
        assert_eq!(mod_a.status, ModuleStatus::LoadableModule);
        assert_eq!(mod_a.rel_path, "kernel/mod_a.ko");
        assert_eq!(
            mod_a.hard_deps_paths,
            vec!["kernel/dep1.ko", "kernel/dep2.ko.xz"],
            "Hard deps paths for mod_a incorrect"
        );
        assert_eq!(
            mod_a.hard_deps(),
            vec!["dep1", "dep2"],
            "Hard deps for mod_a incorrect"
        );

        // Check mod_b (normalization and no deps)
        let mod_b = ctx.modules_hash.get("mod_b").expect("mod_b not found");
        assert_eq!(mod_b.status, ModuleStatus::LoadableModule);
        assert_eq!(mod_b.rel_path, "kernel/mod-b.ko");
        assert!(mod_b.hard_deps().is_empty(), "mod_b should have no hard deps");

        cleanup_test_dir(&root_path);
    }

    #[test]
    fn test_load_harddeps_dup() {
        let root_path = setup_test_dir("harddeps_dup");
        let mut ctx = set_context(&root_path);

        // define modules and hard dependencies
        let modules_dep_content = format!(
            "kernel/mod_a.ko: kernel/dep1.ko kernel/dep2.ko.xz\n\
             kernel/mod_b.ko: kernel/dep1.ko\n\
             kernel/mod-a.ko:\n" // duplicate entry for mod_a
        );
        write_test_file(&root_path, "modules.dep", &modules_dep_content);
        assert_eq!(
            ctx.load_hard_dependencies().unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
    }

    #[test]
    fn test_load_softdeps() {
        let root_path = setup_test_dir("softdeps");
        let mut ctx = set_context(&root_path);

        // setup KmodContext with the KmodModule(direct|harddep) that will receive softdeps
        ctx.modules_hash.insert(
            "mod_a".to_string(),
            KmodModule {
                status: ModuleStatus::LoadableModule,
                rel_path: String::new(),
                hard_deps_paths: Vec::new(),
                soft_deps_pre: Vec::new(),
                soft_deps_post: Vec::new(),
                weak_deps: Vec::new(),
            },
        );

        // Define soft dependencies
        let modules_softdep_content = format!(
            "softdep mod_a pre: softdep_pre_1 softdep_pre_2 post: softdep_post_1\n\
             softdep mod_b pre: softdep_b_pre post: softdep_b_post\n" // mod_b should be None as it's not setup with KmodModule
        );
        write_test_file(&root_path, "modules.softdep", &modules_softdep_content);

        ctx.load_soft_dependencies().unwrap();

        // Check mod_a
        let mod_a = ctx.modules_hash.get("mod_a").expect("mod_a not found");
        assert_eq!(
            mod_a.soft_deps_pre,
            vec!["softdep_pre_1", "softdep_pre_2"],
            "Soft pre-deps incorrect"
        );
        assert_eq!(
            mod_a.soft_deps_post,
            vec!["softdep_post_1"],
            "Soft post-deps incorrect"
        );

        // check that mod_b is None (as it was not setup with KmodModule struct)
        assert!(ctx.modules_hash.get("mod_b").is_none());

        cleanup_test_dir(&root_path);
    }

    #[test]
    fn test_load_weakdeps() {
        let root_path = setup_test_dir("weakdeps");
        let mut ctx = set_context(&root_path);

        // Setup KmodContext with the module that will receive weakdeps
        ctx.modules_hash.insert(
            "mod_a".to_string(),
            KmodModule {
                status: ModuleStatus::LoadableModule,
                rel_path: String::new(),
                hard_deps_paths: Vec::new(),
                soft_deps_pre: Vec::new(),
                soft_deps_post: Vec::new(),
                weak_deps: Vec::new(),
            },
        );
        ctx.modules_hash.insert(
            "mod_b".to_string(),
            KmodModule {
                status: ModuleStatus::LoadableModule,
                rel_path: String::new(),
                hard_deps_paths: Vec::new(),
                soft_deps_pre: Vec::new(),
                soft_deps_post: Vec::new(),
                weak_deps: Vec::new(),
            },
        );

        // Define weak dependencies
        let modules_weakdep_content = format!(
            "weakdep mod_a weakdep_1\n\
             weakdep mod_a weakdep_2\n\
             weakdep mod_b weakdep_3\n"
        );
        write_test_file(&root_path, "modules.weakdep", &modules_weakdep_content);

        ctx.load_weak_dependencies().unwrap();

        // Check mod_a
        let mod_a = ctx.modules_hash.get("mod_a").expect("mod_a not found");
        assert_eq!(
            mod_a.weak_deps,
            vec!["weakdep_1", "weakdep_2"],
            "Weak deps for mod_a incorrect"
        );

        // Check mod_b
        let mod_b = ctx.modules_hash.get("mod_b").expect("mod_b not found");
        assert_eq!(
            mod_b.weak_deps,
            vec!["weakdep_3"],
            "Weak deps for mod_b incorrect"
        );

        cleanup_test_dir(&root_path);
    }

    #[test]
    fn test_load_builtin() {
        let root_path = setup_test_dir("builtin");
        let mut ctx = set_context(&root_path);

        // Define builtin modules
        let modules_builtin_content = format!(
            "kernel/builtin_mod1.ko\n\
             kernel/builtin-mod2.ko\n" // builtin-mod2 => builtin_mod2
        );
        write_test_file(&root_path, "modules.builtin", &modules_builtin_content);

        ctx.load_builtin_modules().unwrap();

        // Check builtin_mod1
        let mod1 = ctx
            .modules_hash
            .get("builtin_mod1")
            .expect("builtin_mod1 not found");
        assert_eq!(
            mod1.status,
            ModuleStatus::Builtin,
            "builtin_mod1 status incorrect"
        );
        assert!(
            mod1.rel_path.is_empty(),
            "Builtin path should be empty"
        );

        // Check builtin_mod2 (normalization)
        let mod2 = ctx
            .modules_hash
            .get("builtin_mod2")
            .expect("builtin_mod2 not found");
        assert_eq!(
            mod2.status,
            ModuleStatus::Builtin,
            "builtin_mod2 status incorrect"
        );

        cleanup_test_dir(&root_path);
    }

    #[test]
    fn test_load_harddeps_builtin_dup() {
        let root_path = setup_test_dir("harddeps_builtin_dup");
        let mut ctx = set_context(&root_path);

        let modules_dep_content = format!(
            "kernel/mod_a.ko: kernel/dep1.ko kernel/dep2.ko.xz\n\
             kernel/mod_b.ko: kernel/dep1.ko\n"
        );
        write_test_file(&root_path, "modules.dep", &modules_dep_content);

        // builtin mod_b collides with modules.dep entry
        let modules_builtin_content = format!(
            "kernel/builtin_mod1.ko\n\
             kernel/mod_b.ko\n"
        );
        write_test_file(&root_path, "modules.builtin", &modules_builtin_content);

        ctx.load_hard_dependencies().unwrap();
        assert_eq!(
            ctx.load_builtin_modules().unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
    }

    #[test]
    fn test_load_aliases() {
        let root_path = setup_test_dir("aliases");
        let mut ctx = set_context(&root_path);

        // Define module for alias to point to
        ctx.modules_hash.insert(
            "mod_target".to_string(),
            KmodModule {
                status: ModuleStatus::LoadableModule,
                rel_path: String::new(),
                hard_deps_paths: Vec::new(),
                soft_deps_pre: Vec::new(),
                soft_deps_post: Vec::new(),
                weak_deps: Vec::new(),
            },
        );

        // Define aliases
        let modules_alias_content = format!(
            "alias alias_1 mod_target\n\
             alias alias_2 mod_target\n\
             # this line should be ignored: alias bad_line mod_target\n\
             alias complex_alias:v*d* mod_target\n\
             alias mod_name_is_alias mod_target\n"
        );
        write_test_file(&root_path, "modules.alias", &modules_alias_content);

        ctx.load_aliases().unwrap();

        // Check alias map contents
        assert_eq!(ctx.alias_map.get("alias_1").unwrap(), "mod_target");
        assert_eq!(ctx.alias_map.get("alias_2").unwrap(), "mod_target");
        assert_eq!(
            ctx.alias_map.get("complex_alias:v*d*").unwrap(),
            "mod_target"
        );
        assert!(ctx.alias_map.get("bad_line").is_none());

        cleanup_test_dir(&root_path);
    }

    #[test]
    fn test_find() {
        let mut ctx = set_context(&PathBuf::new());

        // setup KmodModule for find calls
        let target_module = KmodModule {
            status: ModuleStatus::LoadableModule,
            rel_path: String::from("kernel/target.ko"),
            hard_deps_paths: vec!["kernel/dep1.ko".to_string()],
            soft_deps_pre: Vec::new(),
            soft_deps_post: Vec::new(),
            weak_deps: Vec::new(),
        };
        ctx.modules_hash
            .insert("mod_target".to_string(), target_module.clone());
        ctx.alias_map
            .insert("alias_target".to_string(), "mod_target".to_string());
        ctx.modules_hash.insert(
            "builtin_mod".to_string(),
            KmodModule {
                status: ModuleStatus::Builtin,
                rel_path: String::new(),
                hard_deps_paths: Vec::new(),
                soft_deps_pre: Vec::new(),
                soft_deps_post: Vec::new(),
                weak_deps: Vec::new(),
            },
        );

        // Direct hit (Loadable Module)
        let found_direct = ctx
            .find("mod_target")
            .expect("Should find mod_target directly");
        assert_eq!(found_direct.status, ModuleStatus::LoadableModule);
        assert_eq!(found_direct.hard_deps_paths.len(), 1);

        // alias hit
        let found_alias = ctx
            .find("alias_target")
            .expect("Should find mod_target via alias");
        assert_eq!(*found_alias, target_module);

        // Builtin Module
        let found_builtin = ctx.find("builtin_mod").expect("Should find builtin_mod");
        assert_eq!(found_builtin.status, ModuleStatus::Builtin);

        // Not Found
        assert!(
            ctx.find("non_existent").is_none(),
            "Should not find non_existent module"
        );

        // alias that points to a non-existent module (should fail gracefully)
        ctx.alias_map
            .insert("bad_alias".to_string(), "ghost_mod".to_string());
        assert!(
            ctx.find("bad_alias").is_none(),
            "alias pointing to a ghost module should return None"
        );
    }

    #[test]
    fn test_kmod_context_full_load() {
        // -- SETUP --
        let root_path = setup_test_dir("full_load");

        // create module files
        // mod_a and mod_b are loadable modules.
        write_test_file(&root_path, "kernel/mod_a.ko", "");
        write_test_file(&root_path, "kernel/mod_b.ko.xz", "");

        // modules.dep (hard deps)
        let modules_dep_content = format!(
            "kernel/mod_a.ko: kernel/mod_b.ko.xz kernel/mod_c.ko\n\
             kernel/mod_b.ko.xz:\n"
        );
        write_test_file(&root_path, "modules.dep", &modules_dep_content);

        // modules.softdep (soft deps)
        let modules_softdep_content = "softdep mod_a pre: mod_d post: mod_e mod_f\n";
        write_test_file(&root_path, "modules.softdep", modules_softdep_content);

        // modules.weakdep (weak deps)
        let modules_weakdep_content =
            "weakdep mod_a mod_g\nweakdep mod_a mod_h\nweakdep mod_b mod_i\nweakdep mod_b mod_j\n";
        write_test_file(&root_path, "modules.weakdep", modules_weakdep_content);

        // modules.builtin
        let modules_builtin_content = "kernel/mod_builtin.ko\n";
        write_test_file(&root_path, "modules.builtin", modules_builtin_content);

        // modules.alias
        let modules_alias_content =
            "alias alias_for_b mod_b\nalias mod-b mod_b\nalias mod-intel-b mod_b\n";
        write_test_file(&root_path, "modules.alias", modules_alias_content);

        // -- LOAD KmodContext --

        let context = KmodContext::new(&root_path).unwrap();

        // -- ASSERTIONS --

        // Check mod_a (loadable-module, hard/soft/weak dependencies)
        let mod_a = context.find("mod_a").expect("mod_a should be found");
        assert_eq!(mod_a.status, ModuleStatus::LoadableModule);
        assert_eq!(
            mod_a.rel_path,
            "kernel/mod_a.ko",
            "Path should point to the module file"
        );
        assert_eq!(
            mod_a.hard_deps_paths,
            vec!["kernel/mod_b.ko.xz", "kernel/mod_c.ko"],
            "hard dependencies check failed"
        );
        assert_eq!(
            mod_a.hard_deps(),
            vec!["mod_b", "mod_c"],
            "hard dependencies check failed"
        );
        assert_eq!(
            mod_a.soft_deps_pre,
            vec!["mod_d"],
            "soft pre-dependencies check failed"
        );
        assert_eq!(
            mod_a.soft_deps_post,
            vec!["mod_e", "mod_f"],
            "soft post-dependencies check failed"
        );
        assert_eq!(
            mod_a.weak_deps,
            vec!["mod_g", "mod_h"],
            "weak dependencies check failed"
        );

        // Check mod_b (loadable-module, weak dep)
        let mod_b = context.find("mod_b").expect("mod_b should be found");
        assert_eq!(mod_b.status, ModuleStatus::LoadableModule);
        assert_eq!(
            mod_b.rel_path,
            "kernel/mod_b.ko.xz",
            "Path should point to the compressed module file"
        );
        assert_eq!(
            mod_b.hard_deps_paths.len(),
            0,
            "mod_b should have no hard dependencies"
        );
        assert_eq!(
            mod_b.weak_deps,
            vec!["mod_i", "mod_j"],
            "mod_b weak dependency check failed"
        );

        // Check builtin
        let builtin_mod = context
            .find("mod_builtin")
            .expect("mod_builtin should be found");
        assert_eq!(
            builtin_mod.status,
            ModuleStatus::Builtin,
            "Builtin status check failed"
        );

        // Check alias Lookup
        let aliased_mod = context
            .find("alias_for_b")
            .expect("alias_for_b should resolve");
        assert_eq!(
            aliased_mod, mod_b,
            "alias should resolve to the correct module"
        );

        // Check ModuleNotFound
        assert!(
            context.find("non_existent_mod").is_none(),
            "non-existent module should return None"
        );

        // -- CLEANUP --
        cleanup_test_dir(&root_path);
    }

    #[test]
    fn test_kmod_context_complex_alias_resolve() {
        // -- SETUP --
        let root_path = setup_test_dir("alias_test");

        // Path: kernel/arch/x86/sub/mod32c-intel.ko.zst -> name: mod32c_intel
        write_test_file(&root_path, "kernel/arch/x86/sub/mod32c-intel.ko.zst", "");

        // write module file (the one with the softdep)
        // Path: kernel/fs/fsmodule/fsmodule.ko.zst -> name: fsmodule
        write_test_file(&root_path, "kernel/fs/fsmodule/fsmodule.ko.zst", "");

        // modules.dep: contains all loadable modules
        let modules_dep_content = format!(
            "kernel/fs/fsmodule/fsmodule.ko.zst: kernel/lib/other_dep.ko\n\
             kernel/arch/x86/sub/mod32c-intel.ko.zst:\n\
             kernel/drivers/char/hw_random/virtio-rng.ko.zst:\n\
             kernel/lib/other_dep.ko:\n"
        );
        write_test_file(&root_path, "modules.dep", &modules_dep_content);

        // modules.softdep: fsmodule has a soft dependency 'mod32c' (the alias)
        let modules_softdep_content = "softdep fsmodule pre: mod32c\n";
        write_test_file(&root_path, "modules.softdep", modules_softdep_content);

        // modules.alias: alias 'mod32c' points to 'mod32c_intel'
        let modules_alias_content = format!(
            "alias sub-mod32c-intel mod32c_intel\n\
             alias mod32c-intel mod32c_intel\n\
             alias sub-mod32c mod32c_intel\n\
             alias mod32c mod32c_intel\n\
             alias cpu:type:x86,ven*fam*mod*:feature:*1234* mod32c_intel\n"
        );
        write_test_file(&root_path, "modules.alias", &modules_alias_content);

        // modules.builtin is empty. modules.weakdep is omitted (like Leap 15.6).
        write_test_file(&root_path, "modules.builtin", "");

        // -- LOAD KmodContext --
        let context = KmodContext::new(&root_path).unwrap();

        // -- ASSERTIONS --

        // fsmodule soft dependency
        let fsmodule = context.find("fsmodule").expect("fsmodule should be found");
        assert_eq!(
            fsmodule.soft_deps_pre,
            vec!["mod32c"],
            "fsmodule should softdep on 'mod32c' (the alias name)"
        );

        // Check alias_map for expected entry
        assert_eq!(
            context.alias_map.get("mod32c").unwrap(),
            "mod32c_intel",
            "alias 'mod32c' should map to 'mod32c_intel'"
        );

        // finding alias "mod32c" should resolve to the real module
        let aliased_mod = context
            .find("mod32c")
            .expect("Finding by alias 'mod32c' should resolve");

        // The returned module should be the actual module, mod32c_intel
        assert_eq!(
            aliased_mod.name(),
            "mod32c_intel",
            "alias lookup should return the real module name"
        );
        assert_eq!(
            aliased_mod.status,
            ModuleStatus::LoadableModule,
            "Resolved module status should be LoadableModule"
        );
        assert_eq!(
            aliased_mod.rel_path,
            "kernel/arch/x86/sub/mod32c-intel.ko.zst",
            "Resolved module path is incorrect"
        );

        // find() performs normalization, so handles either - or _ form
        assert_eq!(
            context.find("virtio_rng").unwrap().rel_path,
            "kernel/drivers/char/hw_random/virtio-rng.ko.zst",
        );
        assert_eq!(
            context.find("virtio-rng").unwrap().rel_path,
            "kernel/drivers/char/hw_random/virtio-rng.ko.zst",
        );

        cleanup_test_dir(&root_path);
    }
}
