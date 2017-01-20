module CombinedSubexpressions

export @cse

immutable Cache
    name_to_symbol::Dict{Symbol, Symbol}
    disqualified_symbols::Set{Symbol}
    setup::Vector{Expr}
end

Cache() = Cache(Dict{Symbol,Symbol}(), Set{Symbol}(), Vector{Expr}())

function add_element!(cache::Cache, name)
    cache.name_to_symbol[name] = name
    name
end

function add_element!(cache::Cache, name, setup::Expr)
    sym = gensym(name)
    cache.name_to_symbol[name] = sym
    push!(cache.setup, :($sym = $(copy(setup))))
    sym
end

disqualify!(cache::Cache, x) = nothing
disqualify!(cache::Cache, s::Symbol) = push!(cache.disqualified_symbols, s)
disqualify!(cache::Cache, expr::Expr) = foreach(arg -> disqualify!(cache, arg), expr.args)

# fallback for non-Expr arguments
cacheify!(setup, expr) = expr

function cacheify!(cache::Cache, expr::Expr)
    if expr.head == :function
        # We can't continue CSE through a function definition, but we can
        # start over inside the body of the function:
        for i in 2:length(expr.args)
            expr.args[i] = cacheify!(expr.args[i])
        end
        return expr
    elseif expr.head == :line
        return expr
    elseif expr.head == :(=)
        disqualify!(cache, expr.args[1])
    elseif expr.head == :call
        if all(!isa(arg, Expr) && !(arg in cache.disqualified_symbols) for arg in expr.args)
            cached_name = Symbol(expr.args...)
            if !haskey(cache.name_to_symbol, cached_name)
                sym = add_element!(cache, cached_name, expr)
            else
                sym = cache.name_to_symbol[cached_name]
            end
            return sym
        end
    end
    for (i, child) in enumerate(expr.args)
        expr.args[i] = cacheify!(cache, child)
    end
    return expr
end

function cacheify!(expr::Expr)
    cache = Cache()
    while true
        num_setup = length(cache.setup)
        cacheify!(cache, expr)
        if length(cache.setup) == num_setup
            break
        end
    end
    Expr(:block, cache.setup..., expr)
end

macro cse(expr)
    result = cacheify!(expr)
    println(result)
    esc(result)
end

end
