# los

Repozytorium robocze (m.in. CI do budowy obrazu OPNsense dla Mono Gateway).

## Build obrazu OPNsense dla Mono Gateway (aarch64)

- `ci/build-opnsense.yml` – workflow GitHub Actions (FreeBSD 14.3 w `vmactions/freebsd-vm@v1`).
- `scripts/build-gateway.sh` – skrypt budowy uruchamiany wewnątrz VM FreeBSD.

**Aktywacja:** przenieś `ci/build-opnsense.yml` do `.github/workflows/build-opnsense.yml`
(GitHub App integracji nie ma uprawnienia `workflows`, więc nie mógł utworzyć pliku w `.github/workflows`).
Na GitHubie: *Add file → Create new file* → nazwa `.github/workflows/build-opnsense.yml` → wklej zawartość → commit.
Push zmieniający workflow lub skrypt uruchomi build; ręcznie: *Actions → Build OPNsense image → Run workflow*.

Wynik: artefakt `OPNsense-<wersja>-arm-aarch64-GATEWAY` (`.img.gz`, `mono-gateway-*.pkg`, `SHA256SUMS`).
Wgrywanie: `curl http://<serwer>/OPNsense-*-GATEWAY.img.gz | gunzip | dd of=/dev/mmcblk0 bs=1M` (z Recovery Linux).
