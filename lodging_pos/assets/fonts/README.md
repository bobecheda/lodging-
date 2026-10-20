# Bundled fonts

Bundled as assets so the desk renders correctly offline (no `google_fonts`).
Every family is licensed under the SIL Open Font License 1.1; each folder
keeps its `OFL.txt` beside the font files. Manrope and IBM Plex Mono were
downloaded 2026-10-15; Pirata One and IM Fell English SC 2026-10-20.

## Manrope (interface text)

- Source: https://github.com/googlefonts/manrope (the official upstream that
  Google Fonts builds from; the original `sharanda/manrope` repo was deleted)
- Commit: `468c0dbe38efa331b80bfe9448256abe27be44c3` (2026-09-14)
- Path in repo: `fonts/ttf/`, licence `OFL.txt`

| File | Weight | SHA-256 |
|---|---|---|
| `manrope/manrope-medium.ttf` | 500 | `502ee33a6e140ad6ef10ef8b762a8e5cf01f33316f318800795725f4cfd539d9` |
| `manrope/manrope-semibold.ttf` | 600 | `f43edb46a08e1538413ea2383ef01ed93cdab191a2c57d2489d9590985858cf7` |
| `manrope/manrope-bold.ttf` | 700 | `484d10f0683e9e9f588de978f70cd3ad17cb3522bc0ca6efc4491c83429d323c` |
| `manrope/manrope-extrabold.ttf` | 800 | `c5c0faa3c3a1b1a184f6bb2e405931bdbf51d21c72d8162309118e91304988e0` |
| `manrope/OFL.txt` | licence | `58172e0c0fac2cda8a37b348164bb55e44b0e69051e557e92b1d3f6910141f7b` |

## IBM Plex Mono (receipt numbers, M-Pesa codes, money, counts)

- Source: https://github.com/google/fonts (`ofl/ibmplexmono/`)
- Commit: `b7c8331cf620346575487ef8db0e2c729f014675`

| File | Weight | SHA-256 |
|---|---|---|
| `ibm_plex_mono/IBMPlexMono-Medium.ttf` | 500 | `a9b4c49bb299e05b5f6c481e7fb5e78943d2793249a0c8874ab574a2d1ea6755` |
| `ibm_plex_mono/IBMPlexMono-SemiBold.ttf` | 600 | `d3c38e55c78f5b0f28009fddba4834ec503278936a5986032424c9bd2d23aa46` |
| `ibm_plex_mono/OFL.txt` | licence | `7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da` |

## Pirata One (the wordmark: the lodging name)

- Source: https://github.com/google/fonts (`ofl/pirataone/`)
- Commit: `47d54ca1ebb14fd864695f1d39dc734f39017c33`
- Reserved Font Name "Pirata" (see its `OFL.txt`): used unmodified.

| File | Weight | SHA-256 |
|---|---|---|
| `pirata_one/PirataOne-Regular.ttf` | 400 | `5347a2e155589ecf667d4b766613c8ee003edde9f83717fd24c09599a4b1ecc0` |
| `pirata_one/OFL.txt` | licence | `e8ad3f3de5baeff6bac6e711d8c406e0a6b8a61d2944741532d8965d893a2681` |

## IM Fell English SC (the wordmark: "Lodging")

- Source: https://github.com/google/fonts (`ofl/imfellenglishsc/`)
- Commit: `47d54ca1ebb14fd864695f1d39dc734f39017c33`

| File | Weight | SHA-256 |
|---|---|---|
| `im_fell_english_sc/IMFeENsc28P.ttf` | 400 | `102324fb5434bb5da7963533426b0ad44c85bbc9e7755067535c9d11464a176b` |
| `im_fell_english_sc/OFL.txt` | licence | `2a3ca501fc4d5efcad9798531e3e06962b1e20c60e464f6cbd6c17630112c773` |

To update: download from the same paths at a newer commit, replace the files,
and update the commit and hashes above.
