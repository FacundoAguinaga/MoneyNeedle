//! Módulo de seguridad y gestión de claves (Key Wrapping con BIP-39 y Argon2id).
//!
//! Genera la Master Key (MK) de 256 bits para SQLCipher y la envuelve usando
//! una clave (KEK) derivada con Argon2id a partir de 12 palabras BIP-39.

use aes_gcm::aead::{Aead, KeyInit, OsRng};
use aes_gcm::aead::rand_core::RngCore;
use aes_gcm::{Aes256Gcm, Nonce};
use argon2::{Algorithm, Argon2, Params, Version};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use bip39::{Language, Mnemonic};
use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, Zeroizing};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WrappedPayload {
    pub v: u32,
    pub salt_b64: String,
    pub nonce_b64: String,
    pub ciphertext_b64: String,
}

#[derive(Debug, Clone)]
pub struct VaultInitResult {
    pub raw_master_key_hex: String,
    pub recovery_phrase: String,
    pub wrapped_recovery_payload: String,
}

pub fn hex_encode(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        use std::fmt::Write;
        let _ = write!(s, "{:02x}", b);
    }
    s
}

fn derive_kek(passphrase: &str, salt: &[u8]) -> Result<Zeroizing<[u8; 32]>, String> {
    // Parámetros OWASP para Argon2id en mobile (m=19MB, t=2, p=1)
    let params = Params::new(19456, 2, 1, Some(32))
        .map_err(|e| format!("Parámetros Argon2 inválidos: {e}"))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut kek = [0u8; 32];
    argon2
        .hash_password_into(passphrase.as_bytes(), salt, &mut kek)
        .map_err(|e| format!("Error en derivación Argon2id: {e}"))?;

    Ok(Zeroizing::new(kek))
}

/// Genera una nueva Master Key aleatoria y la envuelve con 12 palabras BIP-39.
pub fn create_vault(custom_passphrase: Option<&str>) -> Result<VaultInitResult, String> {
    let mut master_key = [0u8; 32];
    OsRng.fill_bytes(&mut master_key);
    let raw_master_key_hex = hex_encode(&master_key);

    let recovery_phrase = match custom_passphrase {
        Some(phrase) if !phrase.trim().is_empty() => phrase.trim().to_string(),
        _ => {
            let mut entropy = [0u8; 16]; // 128 bits -> 12 palabras
            OsRng.fill_bytes(&mut entropy);
            let mnemonic = Mnemonic::from_entropy_in(Language::English, &entropy)
                .map_err(|e| format!("Error generando mnemónico BIP39: {e}"))?;
            mnemonic.to_string()
        }
    };

    let mut salt = [0u8; 16];
    OsRng.fill_bytes(&mut salt);

    let kek = derive_kek(&recovery_phrase, &salt)?;

    let cipher = Aes256Gcm::new_from_slice(&*kek)
        .map_err(|e| format!("Error inicializando AES-GCM: {e}"))?;

    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, master_key.as_ref())
        .map_err(|e| format!("Error cifrando Master Key: {e}"))?;

    master_key.zeroize();

    let payload = WrappedPayload {
        v: 1,
        salt_b64: BASE64.encode(salt),
        nonce_b64: BASE64.encode(nonce_bytes),
        ciphertext_b64: BASE64.encode(ciphertext),
    };

    let wrapped_recovery_payload = serde_json::to_string(&payload)
        .map_err(|e| format!("Error serializando payload: {e}"))?;

    Ok(VaultInitResult {
        raw_master_key_hex,
        recovery_phrase,
        wrapped_recovery_payload,
    })
}

/// Desenvuelve la Master Key a partir del payload y la frase de recuperación.
pub fn recover_master_key(
    wrapped_recovery_payload: &str,
    recovery_phrase: &str,
) -> Result<Zeroizing<String>, String> {
    let payload: WrappedPayload = serde_json::from_str(wrapped_recovery_payload)
        .map_err(|e| format!("Payload de recuperación inválido: {e}"))?;

    let salt = BASE64
        .decode(&payload.salt_b64)
        .map_err(|e| format!("Salt base64 inválido: {e}"))?;
    let nonce_bytes = BASE64
        .decode(&payload.nonce_b64)
        .map_err(|e| format!("Nonce base64 inválido: {e}"))?;
    let ciphertext = BASE64
        .decode(&payload.ciphertext_b64)
        .map_err(|e| format!("Ciphertext base64 inválido: {e}"))?;

    if nonce_bytes.len() != 12 {
        return Err("Tamaño de nonce inválido".into());
    }

    let kek = derive_kek(recovery_phrase.trim(), &salt)?;

    let cipher = Aes256Gcm::new_from_slice(&*kek)
        .map_err(|e| format!("Error inicializando cipher: {e}"))?;
    let nonce = Nonce::from_slice(&nonce_bytes);

    let mut decrypted = cipher
        .decrypt(nonce, ciphertext.as_ref())
        .map_err(|_| "Frase de recuperación incorrecta o payload alterado".to_string())?;

    if decrypted.len() != 32 {
        return Err("Tamaño de clave recuperada inválido".into());
    }

    let hex_key = hex_encode(&decrypted);
    decrypted.zeroize();

    Ok(Zeroizing::new(hex_key))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_and_recover_vault() {
        let vault = create_vault(None).unwrap();
        assert_eq!(vault.raw_master_key_hex.len(), 64);
        assert_eq!(vault.recovery_phrase.split_whitespace().count(), 12);

        // Recuperar con las palabras correctas
        let recovered = recover_master_key(
            &vault.wrapped_recovery_payload,
            &vault.recovery_phrase,
        )
        .unwrap();

        assert_eq!(*recovered, vault.raw_master_key_hex);
    }

    #[test]
    fn test_recover_vault_with_wrong_phrase_fails() {
        let vault = create_vault(None).unwrap();
        let wrong_phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

        let res = recover_master_key(&vault.wrapped_recovery_payload, wrong_phrase);
        assert!(res.is_err());
    }
}
