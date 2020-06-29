module CommonSubexpressions

using MacroTools: @capture, postwalk, MacroTools
using Base.Iterators: drop

export @cse, cse, @binarize

struct Cache
    args_to_symbol::Dict{Symbol, Symbol}
    disqualified_symbols::Set{Symbol}
    setup::Vector{Expr}
end

Cache() = Cache(Dict{Symbol,Symbol}(), Set{Symbol}(), Vector{Expr}())

function add_element!(cache::Cache, name, expr::Expr)
    sym = gensym()
    cache.args_to_symbol[name] = sym
    push!(cache.setup, :($sym = $(expr)))
    sym
end

disqualify!(cache::Cache, x) = nothing
disqualify!(cache::Cache, s::Symbol) = push!(cache.disqualified_symbols, s)
disqualify!(cache::Cache, expr::Expr) = foreach(arg -> disqualify!(cache, arg), expr.args)

# fallback for non-Expr arguments
combine_subexprs!(setup, x, warn_enabled::Bool) = x

const standard_expression_forms = Set{Symbol}(
    (:call,
     :block,
     :comprehension,
     :.,
     :(=>),
     :(:),
     :(&),
     :(&&),
     :(|),
     :(||),
     :tuple,
     :for,
     :ref,
     Symbol("'")))

const assignment_expression_forms = Set{Symbol}(
    (:(=),
     :(+=),
     :(-=),
     :(*=),
     :(/=)))

function combine_subexprs!(cache::Cache, expr::Expr, warn_enabled::Bool)
    if expr.head == :macrocall
        # We don't recursively expand other macros, but we can perform CSE on
        # the expression inside the macro call.
        for i in 2:length(expr.args)
            expr.args[i] = combine_subexprs!(expr.args[i], warn_enabled)
        end
    elseif expr.head == :function
        # We can't continue CSE through a function definition, but we can
        # start over inside the body of the function:
        for i in 2:length(expr.args)
            expr.args[i] = combine_subexprs!(expr.args[i], warn_enabled)
        end
    elseif expr.head == :line
        # nothing
    elseif expr.head in assignment_expression_forms
        disqualify!(cache, expr.args[1])
        for i in 2:length(expr.args)
            expr.args[i] = combine_subexprs!(cache, expr.args[i], warn_enabled)
        end
    elseif expr.head == :generator
        for i in vcat(2:length(expr.args), 1)
            expr.args[i] = combine_subexprs!(cache, expr.args[i], warn_enabled)
        end
    elseif expr.head in standard_expression_forms
        for (i, child) in enumerate(expr.args)
            expr.args[i] = combine_subexprs!(cache, child, warn_enabled)
        end
        if expr.head == :call
            for (i, child) in enumerate(expr.args)
                expr.args[i] = combine_subexprs!(cache, child, warn_enabled)
            end
            if all(!isa(arg, Expr) && !(arg in cache.disqualified_symbols) for arg in drop(expr.args, 1))
                combined_args = Symbol(expr.args...)
                if !haskey(cache.args_to_symbol, combined_args)
                    sym = add_element!(cache, combined_args, expr)
                else
                    sym = cache.args_to_symbol[combined_args]
                end
                return sym
            else
            end
        end
    else
        warn_enabled && @warn("CommonSubexpressions can't yet handle expressions of this form: $(expr.head)")
    end
    return expr
end

combine_subexprs!(x, warn_enabled::Bool = true) = x

function combine_subexprs!(expr::Expr, warn_enabled::Bool)
    cache = Cache()
    expr = combine_subexprs!(cache, expr, warn_enabled)
    Expr(:block, cache.setup..., expr)
end

function parse_cse_args(args)
    params = Dict(:warn => true, :binarize => false)
    for (i, arg) in enumerate(args)
        if @capture(arg, key_Symbol = val_Bool)
            if key in keys(params)
                params[key] = val
            else
                error("Unrecognized key: $key")
            end
        elseif i == 1 && arg isa Bool
            Base.depwarn("The `warn_enabled` positional argument is deprecated. Please use `warn=true` or `warn=false` instead", :cse_kwargs)
        else
            error("Unrecognized argument: $arg. Expected `warn=<bool>` or `binarize=<bool>`")

        end
    end
    params
end

"""
    @cse(expr; warn=true, binarize=false)

Perform naive common subexpression elimination under the assumption
that all functions called withing the body of the macro are pure,
meaning that they have no side effects. See [Readme.md](https://github.com/rdeits/CommonSubexpressions.jl/blob/master/Readme.md)
for more details.

This macro will not recursively expand macro calls within the resulting expression.

If the macro encounters an expression which it does not know how to handle,
it will return that expression unmodified. If `warn=true`, then it
will also log a warning in that event.

If `binarize=true` is given, then all n-ary expressions will be recursively
converted into nested binary expressions. See `@binarize` for more information.
"""
macro cse(expr, args...)
    params = parse_cse_args(args)
    if params[:binarize]
        expr = binarize(expr)
    end
    result = combine_subexprs!(expr, params[:warn])
    esc(result)
end

cse(expr, warn_enabled::Bool = true) = combine_subexprs!(copy(expr), warn_enabled)

function _binarize(expr::Expr)
    if @capture(expr, f_(a_, b_, c_, args__))
        _binarize(:($f($f($a, $b), $c, $(args...))))
    else
        expr
    end
end

_binarize(x) = x

binarize(expr::Expr) = postwalk(_binarize, expr)
binarize(x) = x

"""
    @binarize(expr::Expr)

Convery all n-ary function calls within the given expression to nested binary
calls to the same function. That is, convert all calls of the form `f(a, b, c)`
to `f(f(a, b), c)` with as many layers of nesting as necessary. Operators like
`+` and `*` are handled just like any other function call, so

    @binarize a + b + c + d

will produce:

    ((a + b) + c) + d

This is intended to make subexpression elimination easier for long chained
function calls, such as https://github.com/rdeits/CommonSubexpressions.jl/issues/14
"""
macro binarize(expr::Expr)
    esc(binarize(expr))
end


end
