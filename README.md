# FIFA 13 Local FUT

Localhost-only FIFA 13 Ultimate Team revival for the verified **CL1298564** PC build.

The current `v0.14.1.2` ship candidate restores the FUT hub, Store, pack opening, club search, squad chemistry/link updates and local persistence without contacting EA FUT services. The game still supplies the UI, card art and native card database; this project supplies the local Blaze/HTTP services and local FUT state.

## What works

- FUT login and hub on the verified FIFA 13 PC build.
- Store catalogue and pack purchasing/opening.
- Base players plus FIFA 13 special variants including IF/TOTW, TOTY, TOTS, MOTM and Record Breaker cards.
- FIFA 13 duplicate detection in New Items.
- Squad editing with the working retail link-colour path and live chemistry refresh.
- Persistent local coins, club inventory, unassigned items, trade pile, squad slots and client data through SQLite.
- Normal Bronze/Silver/Gold packs contain the native FIFA 13 mix of players and non-player cards: contracts, healing, training, coin/pack cards, kits, badges, stadiums, balls, managers and staff.
- Player-only promo packs remain player-only.
- Automatic trace ZIP generation when the game closes or crashes.

## Fresh-save behaviour

The repository does **not** ship the old 12,115-card test club as owned inventory.

On first run, `save/fut13-local.sqlite3` is created locally with:

- empty club inventory;
- empty active squad slots;
- empty unassigned/trade piles;
- **100,000,000 local test coins**;
- no FIFA Points.

The complete player catalogue is still generated as the pack/search reference pool, but cards only become owned when they are actually acquired and moved into the club.

Use `RESET_LOCAL_SAVE.cmd` to return to this fresh state. Close FIFA first.

## Requirements

- Windows 10/11 x64.
- A legitimate FIFA 13 installation through the EA App/compatible installation.
- A working FIFA 13 PC installation. This release does **not** enforce a `fifa13.exe` SHA-256 allow-list.
- The matched retail `CardsDLLzf.dll` from **CL1298564**, SHA-256:

  `35BDAC6BB2F37F4E3F674C5BB979BCB607FEB11CD09105631796D566590FFC06`

- Administrator permission for the localhost hosts redirect and local networking setup.

Python, Frida, Capstone, pefile and OpenSSL setup are handled by the prerequisite installer.

## First run

For somebody opening the repository for the first time:

1. Extract/clone the repository somewhere writable.
2. Run **`INSTALL_PREREQUISITES.cmd`** once. It checks or installs Python 3.10+, the required Python packages, Git/OpenSSL, and generates the localhost certificate files.
3. Run **`RUN_LOCAL_FUT13.cmd`**. The launcher locates FIFA 13 automatically (or asks for the `Game` directory if needed). There is **no `fifa13.exe` hash allow-list**.
4. The launcher checks the installed `CardsDLLzf.dll`. The Store build requires the exact CL1298564 DLL with SHA-256 `35BDAC6BB2F37F4E3F674C5BB979BCB607FEB11CD09105631796D566590FFC06`.
5. If that DLL is already installed, setup continues automatically. If it is not, the public GitHub repository cannot supply the EA DLL: run **`IMPORT_MATCHED_CARDSDLL.cmd`**, select a legally obtained matching copy, then run `RUN_LOCAL_FUT13.cmd` again. The launcher backs up the currently installed DLL and swaps the verified imported copy in automatically.
6. Wait for `LOCAL FUT13 READY`.
7. Launch FIFA 13 **through the EA App**.
8. Wait for the green `RE TRACE ALWAYS ON` line, then enter Ultimate Team.

After the one-time prerequisite/DLL setup, normal use is simply **`RUN_LOCAL_FUT13.cmd` → launch FIFA 13 through EA App → enter FUT**.

The launcher automatically:

- locates the installed FIFA 13 game directory without enforcing an EXE hash;
- verifies the CardsDLL build;
- backs up and swaps an incompatible CardsDLL when an optional verified copy has been imported into `required/`;
- extracts the native player and non-player FUT catalogues from your own `cards0.big`;
- generates localhost-only TLS certificate material if needed;
- creates/loads the SQLite save;
- starts the local Blaze, RS4, DIME, EASW, POW and trace services;
- installs/updates the required localhost hosts entries.

## CardsDLL handling

The **public GitHub source package intentionally does not redistribute EA's `CardsDLLzf.dll`**.

If your installed game already contains the verified CL1298564 DLL, nothing is copied. If it does not, you can run:

`IMPORT_MATCHED_CARDSDLL.cmd`

Select a legally obtained copy of the DLL. The importer refuses any hash other than the exact CL1298564 hash above. On the next launch, the launcher backs up the installed DLL to `backups/game-files/`, swaps the verified copy in, and verifies the result.

`RESTORE_ORIGINAL_CARDSDLL.cmd` restores the newest backup created by the launcher.

A private/local test package may contain `required/CardsDLLzf.dll` for convenience. **Do not publish that file unless you have the right to redistribute it.**

## Packs and native item pool

At startup the project reads the game's own `cards0.big` / `cards_ng_db` rather than inventing EA resource IDs.

Normal packs use the FIFA 13-style distribution model:

| Pack | Items | Guaranteed rare | Player behaviour |
|---|---:|---:|---|
| Bronze | 12 | 1 | mixed |
| Premium Bronze | 12 | 3 | mixed |
| Silver | 12 | 1 | mixed |
| Premium Silver | 12 | 3 | mixed |
| Gold | 12 | 1 | mixed |
| Premium Gold | 12 | 3 | mixed |
| Premium Gold Players | 12 | 3 | players only |
| Prime Gold Players | 12 | 6 | players only |
| Rare Players | 12 | 12 | players only |
| Jumbo Rare Players | 24 | 24 | players only |

Mixed packs can contain contracts, healing, training, coin/pack consumables, kits, badges, stadiums, balls, managers and coaches/staff. Known unusable/missing-art shipped rows are filtered from the pack pool.

## Local save

SQLite is provided by Python's standard library; no separate SQLite installation is required.

Save file:

`save/fut13-local.sqlite3`

Runtime/generated files such as the save, card catalogues, local certificates, traces and machine-specific settings are ignored by Git and are not part of the public source archive.

## GitHub publishing

Before publishing, use the **GitHub source ZIP** rather than the private/local ZIP. It excludes:

- EA `CardsDLLzf.dll`;
- generated TLS private keys/certificates;
- the SQLite save;
- generated card catalogues;
- logs/traces/backups;
- machine-specific `local.settings.json`.

`PUBLISH_TO_GITHUB.cmd` can initialize the extracted source as a Git repository, show exactly what is staged, and optionally push it to a repository URL you provide.

A Windows GitHub Actions workflow performs Python compilation, PowerShell parser checks and release-hygiene checks on every push/PR.

## Troubleshooting

If FUT fails, Store/pack flow errors, or FIFA crashes, close the game normally if possible. The launcher packages an automatic `fut13-trace-*.zip`; include that ZIP when reporting the issue.

There is intentionally no `fifa13.exe` hash gate. If a particular executable revision proves incompatible, report the trace rather than adding an EXE allow-list.

If the launcher reports a wrong CardsDLL hash, do not bypass the check. Repair/update FIFA through the EA App or import the exact verified CL1298564 DLL.

## Scope

This is a local preservation/revival project. Online matchmaking, EA commerce and the original live FUT infrastructure are not restored by this release.

Protocol, item-model and persistence behaviour was cross-checked against the `fut13-revival` reference project supplied during development. Its preserved reference data retains its original license under `reference/donor-fut13-revival/LICENSE`.

## Legal

This repository is not affiliated with or endorsed by Electronic Arts. FIFA, FIFA 13 and Ultimate Team are trademarks/properties of their respective owners. The public source package does not include FIFA game executables, the EA CardsDLL, locally generated private keys, or your locally generated save/catalogue data.
