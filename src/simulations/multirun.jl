Vector_or_Tuple = Union{AbstractArray, Tuple}

"""
    multirun!(models, agent_step!, model_step!, n; kwargs...) → agent_df, model_df
Call [`run!`](@ref) for the replicate `models`, which are (different) instances
of an ABM obeying the same rules `agent_step!, model_step!`.

Similarly to [`run!`](@ref) this function will collect data. It will furthermore
add one additional column to the dataframe called `:replicate`, which will have
integer values counting the replicate simulations.

The keyword `parallel=false` will run the simulations in parallel using Julia's
`Distributed.pmap` (you need to have loaded `Agents` with `@everywhere`, see
docs online).

All other keywords are propagated to [`run!`](@ref) as-is.
"""
function multirun!(
        models::Vector_or_Tuple, agent_step!, model_step!, n;
        parallel = false, kwargs...
    )
    if parallel
        return parallel_replicates(models, agent_step!, model_step!, n; kwargs...)
    else
        return series_replicates(models, agent_step!, model_step!, n; kwargs...)
    end
end

"""
    multirun!(generator, agent_step!, model_step!, n; kwargs...)
Generate many `ABM`s and propagate them into `multirun!(models, ...)` using the
the provided `generator` which is a one-argument function whose input is a seed.

This method has the keywords `replicates = 5, seeds = abs.(rand(Int, replicates))`
and the only thing it does is:
```julia
models = [generator(seed) for seed ∈ seeds]
multirun!(models, args...; kwargs...)
```
"""
function multirun!(
        generator, args...;
        replicates = 5, seeds = [abs(rand(Int)) for _ in 1:replicates], kwargs...
    )
    models = [generator(seed) for seed ∈ seeds]
    multirun!(models, args...; kwargs...)
end

"Run replicates of the same simulation"
function series_replicates(models, agent_step!, model_step!, n, replicates; kwargs...)

    df_agent, df_model = _run!(models[1], agent_step!, model_step!, n; kwargs...)
    replicate_col!(df_agent, 1)
    replicate_col!(df_model, 1)

    for rep in 2:length(models)
        df_agentTemp, df_modelTemp = _run!(models[rep], agent_step!, model_step!, n; kwargs...)
        replicate_col!(df_agentTemp, rep)
        replicate_col!(df_modelTemp, rep)
        append!(df_agent, df_agentTemp)
        append!(df_model, df_modelTemp)
    end
    return df_agent, df_model, models
end

"Run replicates of the same simulation in parallel"
function parallel_replicates(model::ABM, agent_step!, model_step!, n, replicates;
    seeds = [abs(rand(Int)) for _ in 1:replicates], kwargs...)

    models = [deepcopy(model) for _ in 1:replicates-1]
    push!(models, model) # no reason to make an additional copy
    if model.rng isa MersenneTwister
        for j in 1:replicates; seed!(models[j], seeds[j]); end
    end

    all_data = pmap(
        j -> _run!(models[j], agent_step!, model_step!, n; kwargs...), 1:replicates
    )

    df_agent = DataFrame()
    df_model = DataFrame()
    for (rep, d) in enumerate(all_data)
        replicate_col!(d[1], rep)
        replicate_col!(d[2], rep)
        append!(df_agent, d[1])
        append!(df_model, d[2])
    end

    return df_agent, df_model, models
end

function replicate_col!(df, rep)
    df[!, :replicate] = [rep for i in 1:size(df, 1)]
end
