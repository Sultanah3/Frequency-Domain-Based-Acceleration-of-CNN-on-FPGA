# Frequency-Domain-Based Acceleration of CNN on FPGA

Hermitian-symmetric OaA-FFT convolution accelerator for 2D CNN edge
inference.

## Editor setup (Windows)

Verilog format-on-save and symbol/variable references in Cursor / VS Code
need two local tools: [Verible](https://github.com/chipsalliance/verible)
(`verible-verilog-format`) and [Universal Ctags](https://github.com/universal-ctags/ctags).
The Verilog HDL extension (`mshr-h.veriloghdl`) uses them.

From a Command Prompt or PowerShell, run:

```bat
scripts\install_all.bat
```

That installs both tools into `%LOCALAPPDATA%` and adds them to your user
PATH. Restart Cursor / VS Code afterwards so the new PATH is picked up.

## Repository layout

### `docs/`

| Path | Contents |
|---|---|
| `docs/notes/` | Theory and study notes: DSP fundamentals, linear vs circular convolution, inference vs training. Background understanding, not implementation. |
| `docs/design/` | Stable design decisions and links to the Notion boards. |

### `src/matlab/` — Algorithmic verification

| Path | Contents |
|---|---|
| `scripts/` |  `.m` scripts. |
| `functions/` | Helper functions called by the scripts. |
| `results/` | Plots and numerical tables. |

### `src/hardware/` — RTL implementation

| Path | Contents |
|---|---|
| `hdl/` | Hand-written Verilog.  |
| `tb/` | Testbenches. |
| `generated/` | Tool output and the models that produce it. |
| `sim/` | Questa run scripts and waveform setups. |

### `src/software/`

C driver running on the ARM processor inside the SoC.

### `vectors/`

reference inputs and outputs produced in MATLAB or
Simulink, checked against by the testbenches.

### `scripts/`

Workflow helpers. Not part of the design itself. `install_all.bat`
installs Verible and Universal Ctags for formatting and variable
references (see [Editor setup](#editor-setup-windows)).