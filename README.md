# Frequency-Domain-Based Acceleration of CNN on FPGA

Hermitian-symmetric OaA-FFT convolution accelerator for 2D CNN edge
inference, targeting the Terasic DE10-Standard (Intel Cyclone V SoC).

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
| `results/` | Plots and numerical tables. Small files only; anything large is regenerated rather than committed. |

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

Workflow helpers. Not part of the design itself.