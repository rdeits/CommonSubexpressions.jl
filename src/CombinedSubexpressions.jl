module CombinedSubexpressions

export @cse

immutable Cache
    name_to_symbol::Dict{Symbol, Symbol}
    disqualified_symbols::Set{Symbol}
    setup::Vector{Expr}
end

Cache() = Cache(Dict{Symbol,Symbol}(), Set{Symbol}(), Vector{Expr}())

function add_element!(cache::Cache, name, setup::Expr)
    sym = gensym(name)
    cache.name_to_symbol[name] = sym
    push!(cache.setup, :($sym = $(setup)))
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
    elseif expr.head == :line
        # nothing
    elseif expr.head == :(=)
        disqualify!(cache, expr.args[1])
        for i in 2:length(expr.args)
            expr.args[i] = cacheify!(cache, expr.args[i])
        end
    elseif expr.head == :generator
        for i in vcat(2:length(expr.args), 1)
            expr.args[i] = cacheify!(cache, expr.args[i])
        end
    else
        for (i, child) in enumerate(expr.args)
            expr.args[i] = cacheify!(cache, child)
        end
        if expr.head == :call
            for (i, child) in enumerate(expr.args)
                expr.args[i] = cacheify!(cache, child)
            end
            if all(!isa(arg, Expr) && !(arg in cache.disqualified_symbols) for arg in expr.args)
                cached_name = Symbol(expr.args...)
                if !haskey(cache.name_to_symbol, cached_name)
                    sym = add_element!(cache, cached_name, expr)
                else
                    sym = cache.name_to_symbol[cached_name]
                end
                return sym
            else
            end
        end
    end
    return expr
end

cacheify!(x) = x

function cacheify!(expr::Expr)
    cache = Cache()
    expr = cacheify!(cache, expr)
    Expr(:block, cache.setup..., expr)
end

macro cse(expr)
    result = cacheify!(expr)
    println(result)
    esc(result)
end

end
