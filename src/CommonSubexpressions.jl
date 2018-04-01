__precompile__()

module CommonSubexpressions

export @cse, cse

struct Cache
    args_to_symbol::Dict{Symbol, Symbol}
    disqualified_symbols::Set{Symbol}
    setup::Vector{Expr}
end

Cache() = Cache(Dict{Symbol,Symbol}(), Set{Symbol}(), Vector{Expr}())

function add_element!(cache::Cache, name, expr::Expr)
    sym = gensym(expr.args[1])
    cache.args_to_symbol[name] = sym
    push!(cache.setup, :($sym = $(expr)))
    sym
end

disqualify!(cache::Cache, x) = nothing
disqualify!(cache::Cache, s::Symbol) = push!(cache.disqualified_symbols, s)
disqualify!(cache::Cache, expr::Expr) = foreach(arg -> disqualify!(cache, arg), expr.args)

# fallback for non-Expr arguments
combine_subexprs!(setup, expr, warn_enabled::Bool) = expr

const standard_expression_forms = Set{Symbol}(
    (:call,
     :block,
     :comprehension,
     :(=>),
     :(:),
     :(&),
     :(&&),
     :(|),
     :(||),
     :tuple,
     :for,
     :ref,
     :macrocall,
     Symbol("'")))

const assignment_expression_forms = Set{Symbol}(
    (:(=),
     :(+=),
     :(-=),
     :(*=),
     :(/=)))

function combine_subexprs!(cache::Cache, expr::Expr, warn_enabled::Bool)
    if expr.head == :function
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
            if all(!isa(arg, Expr) && !(arg in cache.disqualified_symbols) for arg in expr.args)
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
        warn_enabled && warn("CommonSubexpressions can't yet handle expressions of this form: $(expr.head)")
    end
    return expr
end

combine_subexprs!(x, warn_enabled::Bool = true) = x

function combine_subexprs!(expr::Expr, warn_enabled::Bool)
    cache = Cache()
    expr = combine_subexprs!(cache, expr, warn_enabled)
    Expr(:block, cache.setup..., expr)
end

macro cse(expr, warn_enabled::Bool = true)
    result = combine_subexprs!(expr, warn_enabled)
    # println(result)
    esc(result)
end

cse(expr, warn_enabled::Bool = true) = combine_subexprs!(copy(expr), warn_enabled)

end
