# go-vuln-releases

This Go repository is designed for **testing vulnerability scanners**.  
It has **10 releases** (v0.1.0–v1.0.0) where only dependencies change between versions.  
Releases **R1–R5** and **R8** include modules with known CVEs in their `go.mod`.

---

## 🔄 Changelog

| Tag | Summary |
|-----|----------|
| **v1.0.0 (R10)** | Safe bump of `x/crypto` to v0.36.0 – ✅ Clean |
| **v0.9.0 (R9)** | Fix `jwt/v4` to v4.5.2 – ✅ Clean |
| **v0.8.0 (R8)** | Downgrade `jwt/v4` to v4.5.1 – ❌ Vulnerable (CVE-2025-30204) |
| **v0.7.0 (R7)** | Safe bump `x/net` to v0.39.0 – ✅ Clean |
| **v0.6.0 (R6)** | Upgrade to fixed dependency versions – ✅ Clean |
| **v0.5.0 (R5)** | Change `x/crypto` to v0.33.0 – ❌ Vulnerable |
| **v0.4.0 (R4)** | Change `x/net` to v0.36.0 – ❌ Vulnerable |
| **v0.3.0 (R3)** | Change `gin` to v1.6.3 – ❌ Vulnerable |
| **v0.2.0 (R2)** | Change `x/text` to v0.3.5 – ❌ Vulnerable |
| **v0.1.0 (R1)** | Initial vulnerable baseline – ❌ Vulnerable |

---

## 🧩 Vulnerability Matrix

| Release | x/text | gorilla/websocket | x/net | x/crypto | gin | golang-jwt/jwt/v4 |
|----------|--------|-------------------|--------|-----------|-----|-------------------|
| **v1.0.0 (R10)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.39.0 | ✅ v0.36.0 | ✅ v1.9.1 | ✅ v4.5.2 |
| **v0.9.0 (R9)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.39.0 | ✅ v0.35.0 | ✅ v1.9.1 | ✅ v4.5.2 |
| **v0.8.0 (R8)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.39.0 | ✅ v0.35.0 | ✅ v1.9.1 | ❌ v4.5.1 (CVE-2025-30204) |
| **v0.7.0 (R7)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.39.0 | ✅ v0.35.0 | ✅ v1.9.1 | ✅ v4.5.2 |
| **v0.6.0 (R6)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.38.0 | ✅ v0.35.0 | ✅ v1.9.1 | ✅ v4.5.2 |
| **v0.5.0 (R5)** | ❌ v0.3.5 (CVE-2021-38561) | ❌ v1.4.0 (CVE-2020-27813) | ❌ v0.36.0 (CVE-2025-22872) | ❌ v0.33.0 (CVE-2025-22869) | ❌ v1.6.3 (CVE-2023-26125) | ✅ v4.5.2 |
| **v0.4.0 (R4)** | ❌ v0.3.5 | ❌ v1.4.0 | ❌ v0.36.0 | ❌ v0.34.0 | ❌ v1.6.3 | ✅ v4.5.2 |
| **v0.3.0 (R3)** | ❌ v0.3.5 | ❌ v1.4.0 | ❌ v0.37.0 | ❌ v0.34.0 | ❌ v1.6.3 | ✅ v4.5.2 |
| **v0.2.0 (R2)** | ❌ v0.3.5 | ❌ v1.4.0 | ❌ v0.37.0 | ❌ v0.34.0 | ❌ v1.8.1 | ✅ v4.5.2 |
| **v0.1.0 (R1)** | ❌ v0.3.6 | ❌ v1.4.0 | ❌ v0.37.0 | ❌ v0.34.0 | ❌ v1.8.1 | ✅ v4.5.2 |

### CVE References
- `golang.org/x/text` — CVE-2021-38561 (fixed in ≥ v0.3.7)  
- `github.com/gorilla/websocket` — CVE-2020-27813 (fixed in ≥ v1.4.1)  
- `golang.org/x/net` — CVE-2025-22872 (fixed in ≥ v0.38.0)  
- `golang.org/x/crypto` — CVE-2025-22869 (fixed in ≥ v0.35.0)  
- `github.com/gin-gonic/gin` — CVE-2023-26125 (fixed in ≥ v1.9.0)  
- `github.com/golang-jwt/jwt/v4` — CVE-2025-30204 (fixed in ≥ v4.5.2)
