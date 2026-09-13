# Linear vs Circular Convolution

---

## What is Circular Convolution?

In discrete-time signal processing, circular convolution assumes that the finite-length sequences are periodically extended.
So when the convolution reaches the end of the signal, it wraps around to the beginning. 
That is what we call **wrapping**, and this wrapping causes what is called:

> **Aliasing**

### Mathematically (for a discrete-time sequence defined over N samples):
Let the sequence be:
$$n=0,1,…,N−1$$

Then circular convolution is:
$$y[n] = \sum_{k=0}^{N-1} x[k] \cdot h[(n - k) \mod N]$$

Notice the modulo $\mod N$,it forces the indices to wrap around.
This is what makes it **circular**.

![Circular Convolution](images/circular-convolution.png)
---

## How Does the Image Look in Circular Convolution?

Because Fourier assumes periodicity:

- The **right edge** appears again on the left.
- The **bottom** appears again on the top.

So the image is treated as an **infinite periodic repetition**, not a finite piece.

Mathematically, we are not convolving two finite matrices.
We are convolving their periodic extensions:
$$\ldots \text{ periodic image} * \text{periodic kernel} \ldots$$

Because of this periodic extension, parts of the convolution result overlap at the boundaries.
---

## Why Do We Get Circular Convolution Using FFT?

The DFT of a finite-length sequence corresponds mathematically to the Fourier Series coefficients of its periodic extension.

Therefore, when we compute:
$$\text{DFT}(x) \cdot \text{DFT}(h)$$

after inverse DFT gives:

$$x[n] \circledast h[n]$$

which is **circular convolution**, not linear.

So:

$$IDFT(DFT(x)⋅DFT(h))=x[n]⊛h[n]$$

The reason is again: **Fourier assumes the signal is periodic**.

---

## What is Linear Convolution?

When the convolution result length is:

$$N + M - 1$$

We call it **Linear Convolution**, where:

- $N$ = input length (or input height in image)
- $M$ = kernel length (or kernel height)

### Mathematically:

$$y[n] = \sum_{k=0}^{M-1} x[k] \cdot h[n - k]$$

There is no modulo operation, so no wrapping occurs.

At the edges:

- We boarder the image with **zeros**.
- The signal does **not** wrap or repeat. 
- The result **expands**.

That is why the output becomes $N + M - 1$.

![Linear convolution](images/linear-convolution.png)
---

## Why Circular Convolution Causes Aliasing?

We can say:

$$\text{Circular Convolution} = \text{Linear Convolution} + \text{Aliasing}$$

Which means the part of the linear convolution that exceeds length $$𝑁$$ wraps around and overlaps with the beginning.

So the overlapping (due to periodic assumption) **is the aliasing**.

---

## How Do We Solve It?

Simple! we expand the image using **Zero Padding**.

The padded length must be:

$$N + M - 1$$

Then:

$$\text{Circular Convolution (after padding)} = \text{Linear Convolution}$$

Because now the linear result fits inside **one period**, so no wrapping happens.

We can say:

> We subtract the aliasing by expanding the image.

---

## Final Intuition

- **DFT** always produces circular convolution.
- The **DFT** works on periodic extensions of finite sequences.
- **Circular convolution** assumes periodic signals.
- **Periodicity** causes wrapping.
- **Wrapping** causes aliasing.
- **Zero padding** removes aliasing.
- When padding size $\geq N + M - 1$, we recover **linear convolution**.
