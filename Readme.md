# CommonSubexpressions.jl

[![Build Status](https://travis-ci.org/rdeits/CommonSubexpressions.jl.svg?branch=master)](https://travis-ci.org/rdeits/CommonSubexpressions.jl)
[![codecov.io](https://codecov.io/github/rdeits/CommonSubexpressions.jl/coverage.svg?branch=master)](https://codecov.io/github/rdeits/CommonSubexpressions.jl?branch=master)

This Julia package provides the `@cse` macro, which performs common subexpression elimination. That means that, given a piece of code like:

```julia
for i in 1:10
    x[i] = foo(1) + i
end
```

in which the function `foo(1)` is evaluated 10 times, the `@cse` macro will produce code that moves that expression out of the loop:

```julia
foo_1 = foo(1)
for i in 1:10
    x[i] = foo_1 + i
end
```

and thus only evaluates `foo(1)` once.

Arbitrarily complex nested expressions can be handled, and should result in more efficient code:

```julia
@cse inv(H) * (G + W) - (G + W)' * inv(H)
```

becomes:

```julia
inv_H = inv(H)
G_plus_W = G + W
inv_H * G_plus_W - G_plus_W' * inv_H
```

You can also wrap entire function definitions or code blocks:

```julia
@cse function foo(x)
    [f(x) == i for i in 1:5]
end
```

# Caveats

*This package is very new and its results may not be correct. Please use it carefully and report any issues you find.*

Any function called within a block wrapped in the `@cse` macro *must be pure*. That is to say, the function must have no side-effects. The `@cse` macro *can not enforce or verify this*. If your function has side-effects, then the common subexpression elimination may change the behavior of your program, since those side-effects will not happen as often as you had expected.

### Brief aside on function purity

A pure function is one with no side-effects. When we say that a function has side-effects, we mean that calling it somehow changes the state of your program, beyond just the value that it returns. A trivial function that does have a side-effect is:

```
f_counter = 0
function f(x)
    global f_counter
    f_counter += 1
    2 * x
end
```

which increases a counter `f_counter` every time it is called.

In addition, any function that mutates its input arguments can not be pure, since changing its input arguments constitutes a side effect.
