# Inference vs Training for Frequency-Domain Convolution Acceleration (FFT / OaA / OLS)

> **Paper:** [\[1601.06815\] Very Efficient Training of Convolutional Neural Networks...](https://arxiv.org/abs/1601.06815)

---

## 1) What computation happens in each case?

###  Inference (Forward pass only)

For each Conv layer:
- Input feature maps $x$
- Fixed weights $w$
- Output $y = x * w$, then Activation/BN/Pooling (in spatial domain)
- No gradients, no weight updates, minimal intermediate storage.

**Key point:** Number of convolution operations $\approx$ *#Conv layers only*.

---

###  Training (Forward + Backward + Update)

For each Conv layer you typically compute **~3 convolutions**:

**1. Forward convolution**

$$y = x * w$$

**2. Gradient w.r.t input** (backprop to previous layer)

$$\frac{\partial L}{\partial x} = \frac{\partial L}{\partial y} * \text{rot180}(w)$$

**3. Gradient w.r.t weights** (for weight update)

$$\frac{\partial L}{\partial w} = x * \frac{\partial L}{\partial y}$$

Then update (SGD example):

$$w \leftarrow w - \eta \frac{\partial L}{\partial w}$$

**Key point:** Training cost per Conv layer $\approx$ *3× inference cost* (sometimes more due to batch accumulation and optimizer).

---

## 2) FFT-based acceleration: why it helps more in inference than training?

### (A) Kernel FFT precomputation

- During **inference**, weights $w$ are **fixed** → compute $\hat{W} = \text{FFT}(w)$ **once**, reuse across all inputs/batches.
- During **training**, weights $w$ **change every step** → must recompute $\hat{W}$ at every iteration. No savings from precomputation.

### (B) FFT reuse across input channels

Given input $x$ with $C_{in}$ channels and $C_{out}$ output channels:

- **Inference:** $\hat{X}$ computed once per input, reused for all $C_{out}$ filters.
- **Training:** Need $\hat{X}$, $\hat{W}$, and $\widehat{\partial L / \partial y}$ — all three FFTs must be recomputed or stored.

### (C) Memory overhead in training

- Forward pass must **cache activations** $x$ for use in the backward pass.
- This adds memory pressure that doesn't exist during inference.

---

## 3) OaA (Overlap-and-Add) vs OLS (Overlap-and-Save)

Both are techniques for computing **linear convolution via FFT** on long signals by breaking them into overlapping blocks.

| Property | OaA (Overlap-and-Add) | OLS (Overlap-and-Save) |
|---|---|---|
| Input blocks | Zero-padded, non-overlapping | Overlapping (with previous block) |
| Output handling | Add overlapping output regions | Discard the first $P-1$ samples per block |
| Equivalent? |  Yes, mathematically |  Yes, mathematically |
| Preferred for | Some filter implementations | Most practical FFT-conv implementations |

Both require the FFT size $N \geq L + P - 1$ where:
- $L$ = input block length
- $P$ = filter (kernel) length

**Complexity per output sample:**

$$O\!\left(\frac{N \log N}{L}\right) \approx O(\log P) \quad \text{when } L \approx P$$

---

## 4) When does FFT convolution beat direct convolution?

Direct (spatial) convolution cost per output: $O(P^2)$ (for a 2D $P \times P$ kernel).

FFT convolution cost per output: $O(N \log N / L)$.

**FFT wins when:**

$$P^2 \gg \frac{N \log N}{L}$$

i.e., for **large kernels**. For small kernels (e.g., $3\times3$), direct convolution is often faster due to FFT overhead.

---

## 5) Summary Table

| | Inference | Training |
|---|---|---|
| # Convolutions per layer | $\approx 1$ | $\approx 3$ |
| Kernel FFT precomputable? |  Yes (fixed weights) |  No (weights change) |
| Activation caching needed? |  No |  Yes |
| FFT speedup potential | **High** | **Lower** |
| OaA / OLS applicable? |  Yes |  Yes (with overhead) |

**Bottom line:** FFT/OaA/OLS-based convolution acceleration gives the **largest benefit during inference** because kernels are fixed and can be pre-transformed. During training, the constant weight updates and extra backward-pass convolutions significantly reduce the relative gain.


## For our scope, the most practical and measurable target is:
Frequency-domain convolution acceleration for CNN inference.  
