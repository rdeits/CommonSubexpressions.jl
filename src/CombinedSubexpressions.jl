module CombinedSubexpressions

export @cse

immutable Cache
    name_to_symbol::Dict{Symbol, Symbol}
    symbol_to_name::Dict{Symbol, Symbol}
    setup::Vector{Expr}
end

Cache() = Cache(Dict{Symbol,Symbol}(), Dict{Symbol,Symbol}(), Vector{Expr}())

function add_element!(cache::Cache, name)
    cache.name_to_symbol[name] = name
    cache.symbol_to_name[name] = name
    name
end

function add_element!(cache::Cache, name, setup::Expr)
    sym = gensym(name)
    cache.name_to_symbol[name] = sym
    cache.symbol_to_name[sym] = name
    push!(cache.setup, :($sym = $(copy(setup))))
    sym
end

cacheify!(setup, expr) = expr

function cacheify!(cache::Cache, expr::Expr)
    if expr.head == :function
        # We can't continue CSE through a function definition, but we can
        # start over inside the body of the function:
        for i in 2:length(expr.args)
            expr.args[i] = cacheify(expr.args[i])
        end
        return expr
    elseif expr.head == :line
        return expr
    elseif expr.head == :call
        available = all([haskey(cache.symbol_to_name, arg) for arg in expr.args])
        if available
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

classify_symbols!(available, disqualified, expr, in_assignment) = nothing
classify_symbols!(available, disqualified, sym::Symbol, ::Val{true}) = push!(disqualified, sym)
classify_symbols!(available, disqualified, sym::Symbol, ::Val{false}) = push!(available, sym)

function classify_symbols!(available, disqualified, expr::Expr, in_assignment::Val)
    if expr.head == :line
        # do nothing
    elseif expr.head == :(=)
        # This is an assignment expression, so anything on the left hand
        # side (that is, expr.args[1]), will be marked as disqualified from caching.
        classify_symbols!(available, disqualified, expr.args[1], Val{true}())

        # The remaining arguments are the right hand side of the assignment,
        # so they can still be cached.
        for arg in expr.args[2:end]
            classify_symbols!(available, disqualified, arg, in_assignment)
        end
    elseif expr.head == :function
        # don't recurse further
    else
        for arg in expr.args
            classify_symbols!(available, disqualified, arg, in_assignment)
        end
    end
end

function find_input_symbols(expr)
    available = Set{Symbol}()
    disqualified = Set{Symbol}()
    classify_symbols!(available, disqualified, expr, Val{false}())
    setdiff!(available, disqualified)
end

function cacheify(expr::Expr)
    cache = Cache()
    for var in find_input_symbols(expr)
        add_element!(cache, var)
    end
    while true
        num_setup = length(cache.setup)
        expr = copy(expr)
        expr = cacheify!(cache, expr)
        if length(cache.setup) == num_setup
            break
        end
    end
    Expr(:block, cache.setup..., expr)
end

macro cse(expr)
    result = cacheify(expr)
    println(result)
    esc(result)
end

end
