"""Integer-only oracle, independent of RTL scheduling and implementation."""

def signed(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def dot(activations, weights, seed=0, unsigned=False):
    products = [(a & 255 if unsigned else signed(a, 8)) * signed(w, 8)
                for a, w in zip(activations, weights)]
    return signed(seed + sum(products), 20)


def convolution_at(image, kernel, y, x):
    return signed(sum(image[y + r][x + s] * kernel[r][s]
                      for r in range(len(kernel))
                      for s in range(len(kernel[0]))), 20)
