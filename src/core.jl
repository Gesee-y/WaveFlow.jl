##########################################################################################################################################
################################################################## CORE STRUCTURES #######################################################
##########################################################################################################################################

## Error handling
struct AudioError <: Exception
    msg::String
end

struct FileNotFoundError <: Exception
    path::String
end

struct UnsupportedFormatError <: Exception
    format::String
end

## Enumerations

@enum PlayState STOPPED PLAYING PAUSED
@enum FadeType FADE_IN FADE_OUT CROSS_FADE

# ─────────────────────────────────────────────
# Structures améliorées

"""
    AbstractAudioSource

Abstract type for audio sources, supporting both in-memory and streaming sources.
"""
abstract type AbstractAudioSource end

"""
    AudioSource

Represents an in-memory audio source with playback controls.

# Fields
- `data::Matrix{Float32}`: Audio data (channels × samples).
- `sample_rate::Float64`: Sample rate in Hz.
- `position::Float64`: Current playback position (in samples).
- `speed::Float64`: Playback speed multiplier.
- `volume::Float64`: Current volume (0.0 to 2.0).
- `target_volume::Float64`: Target volume for fades.
- `fade_samples::Int`: Number of samples for fade duration.
- `fade_counter::Int`: Current fade progress.
- `state::PlayState`: Playback state (STOPPED, PLAYING, PAUSED).
- `loop::Bool`: Whether to loop playback.
- `start_offset::Float64`: Loop start position (in samples).
- `end_offset::Float64`: Loop end position (in samples).
- `id::String`: Unique identifier.
- `lock::ReentrantLock`: Thread-safe lock for state changes.
"""
mutable struct AudioSource <: AbstractAudioSource
    data::Matrix{Float32}
    sample_rate::Float64
    position::Int
    speed::Float64
    volume::Float64
    target_volume::Float64
    fade_samples::Int
    fade_counter::Int
    state::PlayState
    loop::Bool
    buffer_start::Int
    id::String
    lock::ReentrantLock

    function AudioSource(data, sr, id="")
        new(data, sr, 0, 1.0, 1.0, 1.0, 0, 0, STOPPED, false, 0,
            isempty(id) ? string(hash(data)) : id, ReentrantLock())
    end
end

"""
    StreamingAudioSource

Represents a streaming audio source that loads data from disk in chunks.

# Fields
- `file_path::String`: Path to the audio file.
- `sample_rate::Float64`: Sample rate in Hz.
- `channels::Int`: Number of channels.
- `total_samples::Int`: Total number of samples in the file.
- `buffer::Matrix{Float32}`: Ring buffer for streaming (channels × buffer_samples).
- `buffer_start::Int`: Sample index where buffer starts.
- `buffer_samples::Int`: Size of the ring buffer (in samples).
- `position::Float64`: Current playback position (in samples).
- `speed::Float64`: Playback speed multiplier.
- `volume::Float64`: Current volume (0.0 to 2.0).
- `target_volume::Float64`: Target volume for fades.
- `fade_samples::Int`: Number of samples for fade duration.
- `fade_counter::Int`: Current fade progress.
- `state::PlayState`: Playback state (STOPPED, PLAYING, PAUSED).
- `loop::Bool`: Whether to loop playback.
- `start_offset::Float64`: Loop start position (in samples).
- `end_offset::Float64`: Loop end position (in samples).
- `id::String`: Unique identifier.
- `lock::ReentrantLock`: Thread-safe lock for state changes.
"""
mutable struct StreamingAudioSource <: AbstractAudioSource
    file_path::String
    source::LibSndFile.SndFileSource
    sample_rate::Float32
    channels::Int
    total_samples::Int
    buffer::Matrix{Float32}
    buffer_start::Int
    buffer_samples::Int
    position::Int
    speed::Float32
    volume::Float32
    target_volume::Float32
    fade_samples::Int
    fade_counter::Int
    state::PlayState
    loop::Bool
    start_offset::Float32
    end_offset::Float32
    id::String
    lock::ReentrantLock

    function StreamingAudioSource(file_path, sr, channels, total_samples, id="")
        buffer_samples = 65536  # ~1.5s at 44.1kHz
        buffer = zeros(Float32, buffer_samples, channels)
        new(file_path, loadstreaming(file_path), sr, channels, total_samples, buffer, 0, buffer_samples,
            1.0, 1.0, 1.0, 1.0, 0, 0, STOPPED, false, 1.0, total_samples,
            isempty(id) ? string(hash(file_path)) : id, ReentrantLock())
    end
end

"""
    AudioGroup

A group of audio sources with shared controls and effects.

# Fields
- `sources::Vector{AbstractAudioSource}`: List of audio sources.
- `volume::Float64`: Group volume (0.0 to 2.0).
- `target_volume::Float64`: Target volume for fades.
- `fade_samples::Int`: Number of samples for fade duration.
- `fade_counter::Int`: Current fade progress.
- `effects::Vector{Function}`: List of audio effects.
- `solo::Bool`: Whether the group is soloed.
- `mute::Bool`: Whether the group is muted.
- `id::String`: Unique identifier.
- `lock::ReentrantLock`: Thread-safe lock for state changes.
"""
mutable struct AudioGroup
    sources::Vector{AbstractAudioSource}
    volume::Float32
    target_volume::Float32
    fade_samples::Int
    fade_counter::Int
    effects::Vector{Function}
    solo::Bool
    mute::Bool
    id::String
    lock::ReentrantLock

    AudioGroup(id="") = new(AbstractAudioSource[], 1.0, 1.0, 0, 0, Function[],
                           false, false, isempty(id) ? "group_$(rand(UInt32))" : id, ReentrantLock())
end

"""
    AudioBus

A bus for mixing audio groups with effects and sends.

# Fields
- `groups::Vector{AudioGroup}`: List of audio groups.
- `volume::Float64`: Bus volume (0.0 to 2.0).
- `target_volume::Float64`: Target volume for fades.
- `fade_samples::Int`: Number of samples for fade duration.
- `fade_counter::Int`: Current fade progress.
- `effects::Vector{Function}`: List of audio effects.
- `sends::Dict{String, Float64}`: Send levels to auxiliary buses (bus_id => send_level).
- `solo::Bool`: Whether the bus is soloed.
- `mute::Bool`: Whether the bus is muted.
- `id::String`: Unique identifier.
- `lock::ReentrantLock`: Thread-safe lock for state changes.
"""
mutable struct AudioBus
    groups::Vector{AudioGroup}
    volume::Float32
    target_volume::Float32
    fade_samples::Int
    fade_counter::Int
    effects::Vector{Function}
    sends::Dict{String, Float32}
    solo::Bool
    mute::Bool
    id::String
    lock::ReentrantLock

    AudioBus(id="") = new(AudioGroup[], 1.0, 1.0, 0, 0, Function[],
                         Dict{String, Float64}(), false, false,
                         isempty(id) ? "bus_$(rand(UInt32))" : id, ReentrantLock())
end

"""
    AudioMetrics

Stores audio performance metrics.

# Fields
- `peak_levels::Vector{Float64}`: Peak levels per channel.
- `rms_levels::Vector{Float64}`: RMS levels per channel.
- `clip_count::Int`: Number of clipping events.
- `underrun_count::Int`: Number of audio underruns.
- `cpu_usage::Float64`: CPU usage percentage.
"""
mutable struct AudioMetrics
    peak_levels::Vector{Float32}
    rms_levels::Vector{Float32}
    clip_count::Int
    underrun_count::Int
    cpu_usage::Float64

    AudioMetrics() = new(Float32[0.0, 0.0], Float32[0.0, 0.0], 0, 0, 0.0)
end

"""
    ModulableEffect

An audio effect with dynamic parameters.

# Fields
- `effect::Function`: The effect processing function.
- `params::Dict{Symbol, Float64}`: Current parameter values.
- `target_params::Dict{Symbol, Float64}`: Target parameter values for interpolation.
- `interp_samples::Int`: Number of samples for parameter interpolation.
- `interp_counter::Int`: Current interpolation progress.
"""
mutable struct ModulableEffect
    effect::Function
    params::Dict{Symbol, Float32}
    target_params::Dict{Symbol, Float32}
    interp_samples::Int
    interp_counter::Int

    ModulableEffect(effect, params) = new(effect, params, copy(params), 0, 0)
end

"""
    WavesSystem

The main audio system managing buses, streams, and playback.

# Fields
- `buses::Vector{AudioBus}`: List of main buses.
- `auxiliary_buses::Dict{String, AudioBus}`: Auxiliary buses for effects.
- `stream::PortAudioStream`: Audio output stream.
- `master_volume::Float64`: Master volume (0.0 to 2.0).
- `sample_rate::Float64`: System sample rate in Hz.
- `buffer_size::Int`: Audio buffer size in samples.
- `is_running::Bool`: Whether the system is running.
- `audio_thread::Union{Task, Nothing}`: Audio processing thread.
- `pre_allocated_buffers::Dict{String, Matrix{Float32}}`: Pre-allocated buffers for mixing.
- `metrics::AudioMetrics`: Performance metrics.
- `limiter_enabled::Bool`: Whether the limiter is active.
- `limiter_threshold::Float64`: Limiter threshold (0.0 to 1.0).
"""
mutable struct WavesSystem
    buses::Vector{AudioBus}
    io::IOBuffer
    auxiliary_buses::Dict{String, AudioBus}
    stream::PortAudioStream
    master_volume::Float32
    sample_rate::Float32
    buffer_size::Int
    is_running::Bool
    audio_thread::Union{Task, Nothing}
    pre_allocated_buffers::Dict{String, Matrix{Float32}}
    metrics::AudioMetrics
    limiter_enabled::Bool
    limiter_threshold::Float32
    writing_channel::Channel{Ref}
    lock::ReentrantLock
    delay::Float32

    function WavesSystem(;sample_rate=44100.0, buffer_size=1024, delay=0.0001, max_chunk_buffer = 64,
                         input_device = PortAudio.devices()[1],
                         output_device = PortAudio.get_device(PortAudio.get_default_output_index()))
        # input_device = PortAudio.devices()[device_number]
        # output_device = PortAudio.get_device(PortAudio.get_default_output_index())
        #dev = filter(x -> x.maxinchans == 2 && x.maxoutchans == 2, devices)[1]
        stream = PortAudioStream(input_device, output_device,0; warn_xruns=false)
        buffers = Dict(
            "master" => zeros(Float32, buffer_size, 2),
            "bus_temp" => zeros(Float32, buffer_size, 2),
            "group_temp" => zeros(Float32, buffer_size, 2),
            "aux_temp" => zeros(Float32, buffer_size, 2)
        )
        wc = Channel{Ref}(max_chunk_buffer)
        write(stream, buffers["master"])
        new(AudioBus[], IOBuffer(), Dict{String, AudioBus}(), stream, 1.0, sample_rate,
            buffer_size, false, nothing, buffers, AudioMetrics(), true, 0.95, wc, ReentrantLock(), delay)
    end
end
