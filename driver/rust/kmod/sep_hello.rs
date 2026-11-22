// SPDX-License-Identifier: GPL-2.0
//! sep_hello : module Rust minimal, sert seulement à prouver la chaîne de build Rust hors arbre sur ALARM.
//! Ne parle à AUCUN périphérique, ni au SEP : un message au chargement, un au déchargement.
use kernel::prelude::*;

module! {
    type: SepHello,
    name: "sep_hello",
    authors: ["Albert Braimi"],
    description: "Rust toolchain check for the j314c Touch ID driver (touches no hardware)",
    license: "GPL",
}

struct SepHello;

impl kernel::Module for SepHello {
    fn init(_module: &'static ThisModule) -> Result<Self> {
        pr_info!("sep_hello: chaîne Rust OK (aucun accès matériel)\n");
        Ok(SepHello)
    }
}

impl Drop for SepHello {
    fn drop(&mut self) {
        pr_info!("sep_hello: déchargé\n");
    }
}
