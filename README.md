# Frequency-Domain-Based Acceleration of CNN on FPGA

Hermitian-symmetric OaA-FFT convolution accelerator for 2D CNN edge
inference, targeting the Terasic DE10-Standard (Intel Cyclone V SoC).

## Repository layout

| Path | Contents |
|---|---|
| `docs/notes/` | Background study notes on DSP and frequency-domain convolution |
| `docs/design/` | Design decisions and links to the Notion tracking boards |
| `phase1_matlab/` | MATLAB verification of the algorithm |
| `phase2_rtl/` | Simulink model, Verilog sources, testbenches, Quartus project |
| `hps/` | HPS-side C driver |
