#####################################################################################################################
####################################################### OPERATIONS ##################################################
#####################################################################################################################

export add_bus!, resume!

"""
    load_audio(file_path::String, id::String="", stream::Bool=false)

Load an audio file into an `AudioSource` or `StreamingAudioSource`.

# Arguments
- `file_path::String`: Path to the audio file.
- `id::String`: Optional unique identifier (default: auto-generated).
- `stream::Bool`: Whether to stream from disk (default: false).

# Returns
- `AbstractAudioSource`: Either `AudioSource` (in-memory) or `StreamingAudioSource`.

# Throws
- `FileNotFoundError`: If the file does not exist.
- `UnsupportedFormatError`: If the file format is unsupported.

# Example
```julia
source = load_audio("example.wav", "track1", true)  # Stream from disk
```
"""
function load_audio(file_path::String, id::String=""; stream::Bool=false)
    if !isfile(file_path)
        throw(FileNotFoundError(file_path))
    end

    try
        if stream
            info = loadstreaming(file_path).sfinfo
            return StreamingAudioSource(file_path, info.samplerate, info.channels, info.frames)
        else
            audio = load(file_path)
            if size(audio, 2) > 8
                @warn "File with $(size(audio, 2)) channels, reduced to stereo"
                audio = audio[:, 1:min(2, size(audio, 2))]
            end
            data = convert(Matrix{Float32}, audio.data)#')

            max_val = maximum(abs.(data))

            if max_val > 1.0
                @warn "Clipped audio detected, normalization applied"
                data ./= max_val
            end
            return AudioSource(data, SampledSignals.samplerate(audio), id)
        end
    catch e
        #if isa(e, LibSndFile.LibSndFileError)
        #    throw(UnsupportedFormatError(splitext(file_path)[2]))
        #else
            rethrow(e)
        #end
    end
end


"""
    play!(src::AbstractAudioSource, fade_time::Float64=0.0)

Start playback of an audio source.

# Arguments
- `src::AbstractAudioSource`: The audio source.
- `fade_time::Float64`: Fade-in duration in seconds (default: 0.0).
"""
function play!(src::AbstractAudioSource, fade_time::Float64=0.0)
    lock(src.lock)
    try
        src.state = PLAYING
        reset(src)
        if fade_time > 0
            fade_in!(src, fade_time)
        end
    finally
        unlock(src.lock)
    end
end

function resume!(src::AbstractAudioSource, fade_time::Float64=0.0)
    lock(src.lock)
    try
        src.state = PLAYING
        if fade_time > 0
            fade_in!(src, fade_time)
        end
    finally
        unlock(src.lock)
    end
end

"""
    pause!(src::AbstractAudioSource, fade_time::Float64=0.0)

Pause playback of an audio source.

# Arguments
- `src::AbstractAudioSource`: The audio source.
- `fade_time::Float64`: Fade-out duration in seconds (default: 0.0).
"""
function pause!(src::AbstractAudioSource, fade_time::Float64=0.0)
    lock(src.lock)
    try
        if fade_time > 0
            fade_out!(src, fade_time)
        else
            src.state = PAUSED
        end
    finally
        unlock(src.lock)
    end
end

"""
    stop!(src::AbstractAudioSource, fade_time::Float64=0.0)

Stop playback of an audio source and reset position.

# Arguments
- `src::AbstractAudioSource`: The audio source.
- `fade_time::Float64`: Fade-out duration in seconds (default: 0.0).
"""
function stop!(src::AbstractAudioSource, fade_time::Float64=0.0)
    lock(src.lock)
    try
        if fade_time > 0
            fade_out!(src, fade_time)
        else
            src.state = STOPPED
            src.position = src.start_offset
        end
    finally
        unlock(src.lock)
    end
end

"""
    reset!(src::AbstractAudioSource)

Reset an audio source to its initial state without reallocating memory.

# Arguments
- `src::AbstractAudioSource`: The audio source.
"""
function reset!(src::AbstractAudioSource)
    lock(src.lock)
    try
        src.position = src.start_offset
        src.speed = 1.0
        src.volume = 1.0
        src.target_volume = 1.0
        src.fade_samples = 0
        src.fade_counter = 0
        src.state = STOPPED
        src.loop = false
    finally
        unlock(src.lock)
    end
end

"""
    seek!(src::AbstractAudioSource, pos::Float64)

Seek to a specific position in an audio source.

# Arguments
- `src::AbstractAudioSource`: The audio source.
- `pos::Float64`: Position in samples.
"""
function seek!(src::AbstractAudioSource, pos::Float64)
    lock(src.lock)
    try
        src.position = clamp(pos, src.start_offset, src.end_offset)
    finally
        unlock(src.lock)
    end
end
function seek!(src::StreamingAudioSource, pos::Float64)
    lock(src.lock)
    try
        src.position = clamp(pos, src.start_offset, src.end_offset)
        seek(src.source, sample_position(src))
    finally
        unlock(src.lock)
    end
end

"""
    set_speed!(src::AbstractAudioSource, speed::Float64)

Set the playback speed of an audio source.

# Arguments
- `src::AbstractAudioSource`: The audio source.
- `speed::Float64`: Speed multiplier (0.1 to 4.0).
"""
function set_speed!(src::AbstractAudioSource, speed::Float64)
    lock(src.lock)
    try
        src.speed = clamp(speed, 0.1, 4.0)
    finally
        unlock(src.lock)
    end
end

"""
    set_volume!(src::AbstractAudioSource, v::Float64, fade_time::Float64=0.0)

Set the volume of an audio source.

# Arguments
- `src::AbstractAudioSource`: The audio source.
- `v::Float64`: Volume (0.0 to 2.0).
- `fade_time::Float64`: Fade duration in seconds (default: 0.0).
"""
function set_volume!(src::AbstractAudioSource, v::Float64, fade_time::Float64=0.0)
    lock(src.lock)
    try
        if fade_time > 0
            src.target_volume = clamp(v, 0.0, 2.0)
            src.fade_samples = Int(fade_time * 44100)
            src.fade_counter = 0
        else
            src.volume = clamp(v, 0.0, 2.0)
            src.target_volume = src.volume
        end
    finally
        unlock(src.lock)
    end
end

"""
    set_loop!(src::AbstractAudioSource, loop::Bool, start_pos::Float64=0.0, end_pos::Float64=0.0)

Enable or disable looping for an audio source.

# Arguments
- `src::AbstractAudioSource`: The audio source.
- `loop::Bool`: Whether to loop.
- `start_pos::Float64`: Loop start position in samples (default: 0.0).
- `end_pos::Float64`: Loop end position in samples (default: 0.0).
"""
function set_loop!(src::AbstractAudioSource, loop::Bool, start_pos::Float64=0.0, end_pos::Float64=0.0)
    lock(src.lock)
    try
        src.loop = loop
        if start_pos > 0
            src.start_offset = start_pos
        end
        if end_pos > 0
            src.end_offset = min(end_pos, src isa AudioSource ? size(src.data, 2) : src.total_samples)
        end
    finally
        unlock(src.lock)
    end
end

"""
    fade_in!(src::AbstractAudioSource, time::Float64)

Apply a fade-in effect to an audio source.

# Arguments
- `src::AbstractAudioSource`: The audio source.
- `time::Float64`: Fade duration in seconds.
"""
function fade_in!(src::AbstractAudioSource, time::Float64)
    lock(src.lock)
    try
        src.volume = 0.0
        src.target_volume = 1.0
        src.fade_samples = Int(time * 44100)
        src.fade_counter = 0
    finally
        unlock(src.lock)
    end
end

"""
    fade_out!(src::AbstractAudioSource, time::Float64)

Apply a fade-out effect to an audio source.

# Arguments
- `src::AbstractAudioSource`: The audio source.
- `time::Float64`: Fade duration in seconds.
"""
function fade_out!(src::AbstractAudioSource, time::Float64)
    lock(src.lock)
    try
        src.target_volume = 0.0
        src.fade_samples = Int(time * 44100)
        src.fade_counter = 0
    finally
        unlock(src.lock)
    end
end

"""
    create_group(id::String="")

Create a new audio group.

# Arguments
- `id::String`: Optional unique identifier (default: auto-generated).

# Returns
- `AudioGroup`: New audio group.
"""
create_group(id::String="") = AudioGroup(id)

"""
    add_to_group!(group::AudioGroup, src::AbstractAudioSource)

Add an audio source to a group.

# Arguments
- `group::AudioGroup`: The target group.
- `src::AbstractAudioSource`: The audio source to add.
"""
add_to_group!(group::AudioGroup, src::AbstractAudioSource) = push!(group.sources, src)

"""
    remove_from_group!(group::AudioGroup, src_id::String)

Remove an audio source from a group by ID.

# Arguments
- `group::AudioGroup`: The target group.
- `src_id::String`: The ID of the source to remove.
"""
remove_from_group!(group::AudioGroup, src_id::String) =
    filter!(s -> s.id != src_id, group.sources)

"""
    create_bus(id::String="")

Create a new audio bus.

# Arguments
- `id::String`: Optional unique identifier (default: auto-generated).

# Returns
- `AudioBus`: New audio bus.
"""
create_bus(id::String="") = AudioBus(id)

add_bus!(sys::WavesSystem, bus::AudioBus) = push!(sys.buses, bus)

"""
    add_to_bus!(bus::AudioBus, group::AudioGroup)

Add an audio group to a bus.

# Arguments
- `bus::AudioBus`: The target bus.
- `group::AudioGroup`: The group to add.
"""
add_to_bus!(bus::AudioBus, group::AudioGroup) = push!(bus.groups, group)

"""
    remove_from_bus!(bus::AudioBus, group_id::String)

Remove an audio group from a bus by ID.

# Arguments
- `bus::AudioBus`: The target bus.
- `group_id::String`: The ID of the group to remove.
"""
remove_from_bus!(bus::AudioBus, group_id::String) =
    filter!(g -> g.id != group_id, bus.groups)

"""
    add_send!(bus::AudioBus, aux_bus_id::String, level::Float64)

Add a send from a bus to an auxiliary bus.

# Arguments
- `bus::AudioBus`: The source bus.
- `aux_bus_id::String`: The ID of the auxiliary bus.
- `level::Float64`: Send level (0.0 to 1.0).
"""
function add_send!(bus::AudioBus, aux_bus_id::String, level::Float64)
    lock(bus.lock)
    try
        bus.sends[aux_bus_id] = clamp(level, 0.0, 1.0)
    finally
        unlock(bus.lock)
    end
end

"""
    remove_send!(bus::AudioBus, aux_bus_id::String)

Remove a send from a bus to an auxiliary bus.

# Arguments
- `bus::AudioBus`: The source bus.
- `aux_bus_id::String`: The ID of the auxiliary bus.
"""
function remove_send!(bus::AudioBus, aux_bus_id::String)
    lock(bus.lock)
    try
        delete!(bus.sends, aux_bus_id)
    finally
        unlock(bus.lock)
    end
end

"""
    solo!(target::Union{AudioGroup, AudioBus}, enable::Bool=true)

Enable or disable solo for a group or bus.

# Arguments
- `target::Union{AudioGroup, AudioBus}`: The target group or bus.
- `enable::Bool`: Whether to enable solo (default: true).
"""
function solo!(target::Union{AudioGroup, AudioBus}, enable::Bool=true)
    lock(target.lock)
    try
        target.solo = enable
    finally
        unlock(target.lock)
    end
end

"""
    mute!(target::Union{AudioGroup, AudioBus}, enable::Bool=true)

Enable or disable mute for a group or bus.

# Arguments
- `target::Union{AudioGroup, AudioBus}`: The target group or bus.
- `enable::Bool`: Whether to enable mute (default: true).
"""
function mute!(target::Union{AudioGroup, AudioBus}, enable::Bool=true)
    lock(target.lock)
    try
        target.mute = enable
    finally
        unlock(target.lock)
    end
end

"""
    add_effect!(target::Union{AudioGroup, AudioBus}, effect::Union{Function, ModulableEffect})

Add an effect to a group or bus.

# Arguments
- `target::Union{AudioGroup, AudioBus}`: The target group or bus.
- `effect::Union{Function, ModulableEffect}`: The effect to add.
"""
add_effect!(target::Union{AudioGroup, AudioBus}, effect::Union{Function, ModulableEffect}) =
    push!(target.effects, effect isa ModulableEffect ? x -> effect.effect(x, effect.params) : effect)

"""
    remove_effect!(target::Union{AudioGroup, AudioBus}, index::Int)

Remove an effect from a group or bus by index.

# Arguments
- `target::Union{AudioGroup, AudioBus}`: The target group or bus.
- `index::Int`: The index of the effect to remove.
"""
function remove_effect!(target::Union{AudioGroup, AudioBus}, index::Int)
    lock(target.lock)
    try
        if 1 <= index <= length(target.effects)
            deleteat!(target.effects, index)
        end
    finally
        unlock(target.lock)
    end
end

"""
    update_effect_params!(effect::ModulableEffect, new_params::Dict{Symbol, Float64}, time::Float64=0.0)

Update parameters of a modulable effect with interpolation.

# Arguments
- `effect::ModulableEffect`: The effect to update.
- `new_params::Dict{Symbol, Float64}`: New parameter values.
- `time::Float64`: Interpolation duration in seconds (default: 0.0).
"""
function update_effect_params!(effect::ModulableEffect, new_params::Dict{Symbol, Float64}, time::Float64=0.0)
    effect.target_params = copy(new_params)
    effect.interp_samples = Int(time * 44100)
    effect.interp_counter = 0
end

function cubic_interpolate(y0::Float32, y1::Float32, y2::Float32, y3::Float32, t::Float32)
    a0 = y3 - y2 - y0 + y1
    a1 = y0 - y1 - a0
    a2 = y2 - y0
    a3 = y1
    return a0 * t^3 + a1 * t^2 + a2 * t + a3
end

function interpolate_sample(data::Matrix{Float32}, channel::Int)
    idx = src.position
    _, total_samples = size(data)
    if idx < 2 || idx > total_samples - 2
        if idx >= total_samples
            return 0.0f0
        end
        s1 = data[channel, idx]
        return s1
    else
        return cubic_interpolate(
            data[channel, idx-1],
            data[channel, idx],
            data[channel, idx+1],
            data[channel, idx+2],
            0
        )
    end
end

function load_streaming_buffer!(src::StreamingAudioSource, position::Int)
    lock(src.lock)
    try
        file = src.source
        samples_to_read = min(src.buffer_samples, src.total_samples - src.buffer_start)
        
        data = read(file, samples_to_read)
        
        src.buffer_start = 0
        src.buffer = data.data
    catch e
        showerror(stdout, e)
    finally
        unlock(src.lock)
    end
end

function get_streaming_buffer!(src::StreamingAudioSource, buffer_size)
    if iszero(src.buffer_start) || src.buffer_start >= src.buffer_samples
        load_streaming_buffer!(src, src.position)
    end
    return src.buffer
end
function get_streaming_buffer!(src::AudioSource, buffer_size)
    return src.data
end

function get_streaming_sample(src::StreamingAudioSource)
    idx = src.position
    if iszero(src.buffer_start) || src.buffer_start >= src.buffer_samples
        load_streaming_buffer!(src, idx)
    end
    buffer_idx = src.buffer_start + 1
    src.buffer_start += 1
    @view src.buffer[buffer_idx, :]
end

get_buffer(src::AudioSource) = src.data
get_buffer(src::StreamingAudioSource) = src.buffer
sample_position(src::StreamingAudioSource) = src.position*1024
sample_position(src::StreamingAudioSource) = src.buffer_start
eof(src::StreamingAudioSource) = sample_position(src) >= nframes(src.source)
reset(src::StreamingAudioSource) = begin
    src.position = 0
    seek(src.source, 1)
end
reset(src::AudioSource) = begin
    src.position = 0
    src.buffer_start = 0
end
