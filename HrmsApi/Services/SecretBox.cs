using System.Security.Cryptography;
using System.Text;

namespace HrmsApi.Services;

/// <summary>
/// Encrypts small secrets stored in a company's database (e.g. the company's own AI API key)
/// with AES-256-GCM. The key is derived from the server's JWT secret (config "Jwt:Key"), which
/// is stable across restarts and deploys, so nothing extra has to be configured. If that secret
/// changes, stored values can no longer be read (<see cref="TryDecrypt"/> returns null) and the
/// admin enters them again.
/// </summary>
public static class SecretBox
{
    private const int NonceSize = 12, TagSize = 16;
    private const byte Version = 1;

    private static byte[] DeriveKey(string serverSecret, string purpose) =>
        HKDF.DeriveKey(HashAlgorithmName.SHA256, Encoding.UTF8.GetBytes(serverSecret), 32,
            salt: Encoding.UTF8.GetBytes("mars-hrms/secret-box"), info: Encoding.UTF8.GetBytes(purpose));

    /// <summary>"v1:" + base64(version | nonce | ciphertext | tag).</summary>
    public static string Encrypt(string plain, string serverSecret, string purpose)
    {
        if (string.IsNullOrEmpty(serverSecret)) throw new InvalidOperationException("No server secret to encrypt with.");
        var key = DeriveKey(serverSecret, purpose);
        var nonce = RandomNumberGenerator.GetBytes(NonceSize);
        var data = Encoding.UTF8.GetBytes(plain);
        var cipher = new byte[data.Length];
        var tag = new byte[TagSize];
        using (var aes = new AesGcm(key, TagSize)) aes.Encrypt(nonce, data, cipher, tag);

        var blob = new byte[1 + NonceSize + cipher.Length + TagSize];
        blob[0] = Version;
        nonce.CopyTo(blob, 1);
        cipher.CopyTo(blob, 1 + NonceSize);
        tag.CopyTo(blob, 1 + NonceSize + cipher.Length);
        return "v1:" + Convert.ToBase64String(blob);
    }

    /// <summary>The plain text, or null when the value is missing, damaged or was encrypted with another secret.</summary>
    public static string? TryDecrypt(string? stored, string serverSecret, string purpose)
    {
        if (string.IsNullOrEmpty(stored) || !stored.StartsWith("v1:") || string.IsNullOrEmpty(serverSecret)) return null;
        try
        {
            var blob = Convert.FromBase64String(stored[3..]);
            if (blob.Length < 1 + NonceSize + TagSize || blob[0] != Version) return null;
            var nonce = blob.AsSpan(1, NonceSize);
            var cipher = blob.AsSpan(1 + NonceSize, blob.Length - 1 - NonceSize - TagSize);
            var tag = blob.AsSpan(blob.Length - TagSize);
            var plain = new byte[cipher.Length];
            using var aes = new AesGcm(DeriveKey(serverSecret, purpose), TagSize);
            aes.Decrypt(nonce, cipher, tag, plain);
            return Encoding.UTF8.GetString(plain);
        }
        catch (Exception ex) when (ex is FormatException or CryptographicException)
        {
            return null;
        }
    }
}
