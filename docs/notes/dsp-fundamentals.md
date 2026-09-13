# Basics

## a. Continuous World

### 1. Fourier Series vs. Fourier Transform

These are the tools used to look at a signal's frequency (pitch/harmonics) instead of its time (the waveform).

- **Fourier Series:** Used for periodic signals (signals that repeat forever). It breaks a signal into a discrete list of "ingredients" (harmonics).
- **Fourier Transform (FT):** Used for aperiodic signals (single events, like a bang). It results in a smooth, continuous curve of frequencies.
- **The Key Difference:** Series = Discrete "Steps" (1Hz, 2Hz...); Transform = Continuous "Slide."

### 2. Impulse Response ($h$)

The Impulse Response is the "identity card" or "DNA" of a system.

- **Definition:** It is the output of a system when you hit it with an Impulse (a single, infinite spike of energy).
- **Importance:** If you know the impulse response, you can predict exactly how that system will react to any other signal through the process of convolution. It tells you if a system is "bassy," "echoey," or "distorted."
- **Why impulse?** $\delta(t)$ is just a very thin signal shape, its width is zero thus in the frequency domain it will cover the entire frequency range because $f = 1/T$ — if $T$ is zero, $f$ is $\infty$.

> **Note:** Impulse signal $\delta(t)$ is actually the derivative of a step function.

> **Note:** In the time domain, as the signal gets thinner, its frequency equivalent gets bigger and bigger until it reaches $\infty$ at $\delta(t)$.

### 3. Signal Addition vs. Multiplication

This explains how signals interact with one another.

- **Addition** ($x + h$): This is "Mixing." It's like two people talking at the same time; you hear both, but they don't change each other.
- **Multiplication** ($x \cdot h$): This is "Scaling" or "Modulating." It's like talking through a megaphone. One signal (your voice) is modified by the properties of the other (the megaphone).

### 4. Convolution

Convolution is the mathematical operation that calculates the final output when an input signal ($x$) passes through a system ($h$).

- **The Rule:** Output = Input Convolved with Impulse Response — $y = x * h$.
- **The Process:** You **Flip** the filter, **Slide** it across the input, **Multiply** the overlaps, and **Sum** the results.
- **The Shortcut:** To save time (like on an FPGA), we use the FFT to turn Convolution into simple Multiplication.

---

## b. Discrete World (Z-Transform)

The Z-Transform is essentially the "Laplace Transform for the digital world."

If the Fourier Transform is about frequency and the Impulse Response is about the system's personality, the Z-Transform is the algebraic tool that makes designing digital filters possible without going insane from complex math.

In continuous math, we use Calculus (integrals and derivatives). In digital systems, there is no "continuous time"; there are only samples ($n=0, 1, 2...$). Instead of differential equations, we use **Difference Equations**.

- **Continuous:** $y(t) = \frac{dx}{dt}$ (Needs Laplace)
- **Digital:** $y[n] = x[n] - x[n-1]$ (Needs Z-Transform)

The Z-Transform turns these "delay and subtract" operations into simple multiplication by a variable $z$.

### Why is it better than the Fourier Transform?

The Fourier Transform only works if a signal is "well-behaved" (it must eventually decay to zero). The Z-Transform can handle signals that grow or are unstable. It gives us a way to "fix" unstable systems by moving their poles back inside the unit circle.

### FPGA Relevance

When you are designing a CNN accelerator on an FPGA, the Z-Transform is how you define the **Latency**.

- Every $z^{-1}$ in your math is one register (FF) on your FPGA.
- If your Z-Transform is $H(z) = 1 + z^{-1}$, your FPGA circuit is just an adder that adds the current pixel to the previous one.
