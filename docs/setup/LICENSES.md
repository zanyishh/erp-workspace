# Source and license record

Verified on 12 November 2026 against the official repositories and downloaded source. Exact revisions, file counts and SHA-256 checksums for separate notice files are in `../../upstream.lock.json`.

| Component | Version | License | Preserved original |
| --- | --- | --- | --- |
| ERPNext | v16.54.0 | GNU GPL version 3 | `../../licenses/erpnext/license.txt` |
| Frappe Framework | v16.55.2 | MIT | `../../licenses/frappe/LICENSE` |
| Frappe Docker configuration | v4.2.0 | MIT | `../../licenses/frappe_docker/LICENSE` |

The complete source working trees are in `../../upstream/`. Only Git history is shallow to conserve disk space. Original copyright headers, bundled assets, license files, attribution reports and trademark policy remain intact. Separate copies of the notice files are also in `../../licenses/` with their original subdirectories. No upstream source was edited.

## Requirements to carry forward

ERPNext's GPLv3 permits use and modification. When conveying covered modified source, preserve copyright, license and warranty notices; identify modifications and their dates; and meet GPLv3's licensing requirements. When conveying covered binaries, provide corresponding source using a permitted mechanism. Preserve applicable interactive legal notices. A separate Flutter client communicating over the API requires its own licensing assessment based on the actual code and integration; do not assume its license from the choice of framework.

For MIT code, include the original copyright and permission notice in copies or substantial portions. Preserve warranty disclaimers. Keep bundled component notices, including Leaflet licenses and Font Awesome's font/code licensing. The Frappe attribution report also identifies Inter under SIL OFL 1.1. Asset licenses remain relevant when changing or redistributing fonts and icons.

The ERPNext name and logo have a separate trademark policy. Open source permission is not blanket permission to brand our future product as ERPNext. Keep the original name for this unmodified local evaluation; choose an independent product name for the redesigned app unless the trademark owner grants permission.

## Coverage and limits

This is a source and notice review of the three downloaded repositories, not an exhaustive dependency or release-distribution audit. Python/npm transitive dependencies, base OS packages, database and cache services, Flutter/Dart dependencies and any future AI providers retain their own terms. Before distributing the rebuilt product, generate and review its actual dependency and asset inventory and include all required notices and source offers. Do not replace this collection with a blanket proprietary license.

The evaluation deployment uses the official MariaDB 11.8 and Redis 6.2 images from the upstream deployment recipe. Colima is MIT licensed; the Docker client and Compose are Apache-2.0 licensed. This setup does not install Docker Desktop. Apple/Xcode and Android SDK tools have separate development terms and are not claims about the license of our application.

## Primary sources

- [ERPNext license](https://github.com/frappe/erpnext/blob/v16.54.0/license.txt)
- [ERPNext trademark policy](https://github.com/frappe/erpnext/blob/v16.54.0/TRADEMARK_POLICY.md)
- [Frappe MIT license](https://github.com/frappe/frappe/blob/v16.55.2/LICENSE)
- [Frappe bundled software attributions](https://github.com/frappe/frappe/blob/v16.55.2/attributions.md)
- [Frappe Docker MIT license](https://github.com/frappe/frappe_docker/blob/v4.2.0/LICENSE)
- [Colima source and license](https://github.com/abiosoft/colima)
