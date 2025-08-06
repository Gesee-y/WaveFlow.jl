

"""
    get_metrics(system::WavesSystem)

Get current audio metrics.

# Arguments
- `system::WavesSystem`: The audio system.

# Returns
- Named tuple with metrics (peak_left, peak_right, rms_left, rms_right, clip_count, underrun_count, cpu_usage).
"""
function get_metrics(system::WavesSystem)
    return (
        peak_left = system.metrics.peak_levels[1],
        peak_right = system.metrics.peak_levels[2],
        rms_left = system.metrics.rms_levels[1],
        rms_right = system.metrics.rms_levels[2],
        clip_count = system.metrics.clip_count,
        underrun_count = system.metrics.underrun_count,
        cpu_usage = system.metrics.cpu_usage
    )
end

"""
    reset_metrics!(system::WavesSystem)

Reset audio metrics.

# Arguments
- `system::WavesSystem`: The audio system.
"""
function reset_metrics!(system::WavesSystem)
    system.metrics.clip_count = 0
    system.metrics.underrun_count = 0
    system.metrics.peak_levels .= 0.0
end

"""
    find_source(system::WavesSystem, id::String)

Find an audio source by ID.

# Arguments
- `system::WavesSystem`: The audio system.
- `id::String`: The source ID.

# Returns
- `AbstractAudioSource` or `nothing` if not found.
"""
function find_source(system::WavesSystem, id::String)
    for bus in system.buses
        for group in bus.groups
            for src in group.sources
                if src.id == id
                    return src
                end
            end
        end
    end
    return nothing
end

"""
    list_all_sources(system::WavesSystem)

List all audio sources in the system.

# Arguments
- `system::WavesSystem`: The audio system.

# Returns
- `Vector{String}`: List of source paths (bus_id/group_id/source_id).
"""
function list_all_sources(system::WavesSystem)
    sources = String[]
    for bus in system.buses
        for group in bus.groups
            for src in group.sources
                push!(sources, "$(bus.id)/$(group.id)/$(src.id)")
            end
        end
    end
    return sources
end

function update_metrics!(metrics::AudioMetrics, signal::Matrix{Float32})
    for ch in 1:2
        channel_data = @view signal[ch, :]
        metrics.peak_levels[ch] = max(metrics.peak_levels[ch] * 0.95, maximum(abs.(channel_data)))
        metrics.rms_levels[ch] = sqrt(sum(channel_data.^2) / length(channel_data))
        if maximum(abs.(channel_data)) >= 1.0
            metrics.clip_count += 1
        end
    end
end

function sleep_ns(v::Real;sec=true)
    factor = sec ? 10 ^ 9 : 1
    t = UInt(floor(v * factor))
    
    t1 = time_ns()
    while true
        if time_ns() - t1 >= t
            break
        end
        yield()
    end
end
