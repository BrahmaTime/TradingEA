# AGENTS.md

## Cursor Cloud specific instructions

### What this project is
This repo (`TradingEA`) is a single **MetaTrader 5 (MT5) Expert Advisor written in MQL5**.
There is **no Node/Python/etc. package layer** — no `package.json`, `requirements.txt`,
lockfiles, or web/API services. The whole product is one `.mq5` file compiled to an
`.ex5` and run inside MT5.

- The application source (`Experts/IndexOpeningRangeGuardian.mq5`) currently lives on the
  open PR branch, **not on `main`** (`main` only has `README.md`). Use
  `git show <branch>:Experts/IndexOpeningRangeGuardian.mq5` if you need it while on `main`.

### Toolchain (already installed & persisted in the VM snapshot)
- **Wine 11 (winehq-stable)** + **MetaTrader 5** (terminal + MetaEditor), installed under
  `WINEPREFIX=$HOME/.mt5` in **portable** mode.
- MT5 data folder (portable): `"$HOME/.mt5/drive_c/Program Files/MetaTrader 5"`.
  MQL5 tree (Experts/Include/etc.) is under `.../MetaTrader 5/MQL5`.
- A **MetaQuotes-Demo** account is already created in the terminal profile, so the
  Strategy Tester has an account/connection. If it's missing, recreate it via the GUI
  (`File > Open an Account`): **you must pick a Country in the form** or the phone field
  validation blocks the wizard.

Always export before running Wine commands:
`export WINEPREFIX=$HOME/.mt5 WINEARCH=win64 WINEDEBUG=-all`

### Build (compile MQL5 -> .ex5)
Run MetaEditor's headless compiler from the MT5 folder:
```
cd "$HOME/.mt5/drive_c/Program Files/MetaTrader 5"
wine MetaEditor64.exe /compile:"MQL5\Experts\<File>.mq5" /log:"C:\compile.log"
iconv -f UTF-16 -t UTF-8 "$HOME/.mt5/drive_c/compile.log"   # log is UTF-16
```
Gotchas:
- **Paths with spaces silently fail** to compile (no `.ex5`, empty log). Compile from a
  space-free path, e.g. copy the source to `MQL5\Experts\<NoSpaces>.mq5` first.
- `MetaEditor64.exe` often returns a **non-zero exit code even on success**; trust the log
  line `Result: N errors, M warnings`, not `$?`.
- The current PR EA does **not** compile cleanly (real code bug: `const` vars
  `trendRejectedLong`/`trendRejectedShort` reassigned). That is a source-code bug to fix in
  the EA, not an environment problem — the compiler correctly reports it.

### Run (Strategy Tester backtest = the "hello world" for this product)
The MT5 GUI must run on display **`:1`** (the TigerVNC/XFCE desktop that the screenshot/
computer-use tooling captures). `Xvfb :99` also exists but the GUI tools do not see it.
```
DISPLAY=:1 wine terminal64.exe /portable
```
Then drive the Strategy Tester in the GUI (`Ctrl+R` / `View > Strategy Tester`): pick a
compiled Expert, a symbol (e.g. EURUSD), timeframe, and click Start. First run downloads
history from the MQL5 Cloud / MetaQuotes-Demo (be patient). Headless tester runs are also
possible via `wine terminal64.exe /portable /config:C:\tester.ini`, but the `[Tester]`
config must reference a valid account (`tester not started because the account is not
specified` otherwise).

### Misc
- `wineboot` can pop a "install Wine Mono" dialog that **hangs headlessly**. The prefix is
  already initialized so normal use avoids it; if you re-init, kill the
  `control.exe appwiz.cpl install_mono` process by PID.
- MT5 is single-instance per data folder — don't launch a headless tester while the GUI
  terminal is already running on the same portable folder.
