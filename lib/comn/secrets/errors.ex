defmodule Comn.Secrets.Errors do
  @moduledoc """
  Registered error codes for the `Comn.Secrets` subsystem.
  """

  use Comn.Errors.Registry

  register_error "secrets/invalid_key",          :auth,        message: "Key structure is malformed or does not match the expected algorithm"
  register_error "secrets/wrong_key",            :auth,        message: "Key does not match the one used to lock this blob"
  register_error "secrets/authentication_failed", :auth,       message: "AEAD tag verification failed — data may have been tampered with"
  register_error "secrets/invalid_container",    :validation,  message: "Deserialized data is not a valid container structure"
  register_error "secrets/invalid_vault_config", :validation,  message: "Key metadata is missing required Vault fields (vault_addr, vault_token, vault_key_name)"
  register_error "secrets/vault_unavailable",    :network,     message: "Could not connect to Vault server"
  register_error "secrets/vault_error",          :internal,    message: "Vault returned an unexpected error"
  register_error "secrets/invalid_ciphertext",   :validation,  message: "Vault returned ciphertext that could not be decoded"
  register_error "secrets/network_error",        :network,     message: "HTTP request to Vault failed"
end
