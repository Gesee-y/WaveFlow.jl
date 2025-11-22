module WaveFlow

using FileIO: load, loadstreaming
using LibSndFile
using SampledSignals
using PortAudio

export WavesSystem, AbstractAudioSource, AudioSource, StreamingAudioSource, AudioGroup, AudioBus,
       AudioError, FileNotFoundError, UnsupportedFormatError, PlayState, STOPPED, PLAYING, PAUSED,
       ModulableEffect, init_waves, load_audio, generate_sine_wave, generate_white_noise,
       play!, pause!, stop!, reset!, seek!, set_speed!, set_volume!, set_loop!, fade_in!, fade_out!,
       create_group, add_to_group!, remove_from_group!, create_bus, add_to_bus!, remove_from_bus!,
       add_send!, remove_send!, solo!, mute!, add_effect!, remove_effect!, update_effect_params!,
       create_reverb, create_delay, create_compressor, create_eq_filter,
       start!, stop!, close!, get_metrics, reset_metrics!, find_source, list_all_sources, samplerate,
       buffersize

const BUFFER_SIZE = 512
const STREAM_CHUNK_SIZE = 2^14
const MAX_CHANNEL_SIZE = 8

include("core.jl")
include("operations.jl")
include("effects.jl")
include("mixer.jl")
include("utils.jl")

"""
    init_waves(sample_rate=44100.0, buffer_size=1024)

Initialize the audio system.

# Arguments
- `sample_rate::Float64`: Sample rate in Hz (default: 44100.0).
- `buffer_size::Int`: Buffer size in samples (default: 1024).

# Returns
- `WavesSystem`: Initialized audio system.

# Throws
- `AudioError`: If initialization fails.

# Example
```julia
ws = init_waves(44100.0, 1024)
```
"""
function init_waves(sample_rate::Float64=44100.0, buffer_size::Int=1024)
    try
        PortAudio.initialize()
        return WavesSystem(;sample_rate=sample_rate, buffer_size=buffer_size)
    catch e
        throw(AudioError("Failed to initialize the audio system: $(showerror(stdout,e))"))
    end
end

"""
    start!(system::WavesSystem)

Start the audio system.

# Arguments
- `system::WavesSystem`: The audio system to start.
"""
function start!(system::WavesSystem)
    if system.is_running
        @warn "Audio system is already running"
        return
    end

    system.is_running = true

    audio_task = Threads.@spawn begin
        stream = system.stream
        sample_time = (system.buffer_size) / system.sample_rate
        while system.is_running
            play_chunk(system)
        end
    end
    

    system.audio_thread = Threads.@spawn begin
        try
            while system.is_running
                sample_time = system.buffer_size / system.sample_rate
                start_time = time()
                
                mix_sources!(system)

                process_time = time() - start_time
                system.metrics.cpu_usage = process_time / sample_time * 100
                
            end
        catch e
            @error "In audio thread: $(showerror(stdout, e))"
            system.is_running = false
        end
    end

    @info "Audio system lauched."
end

"""
    stop!(system::WavesSystem)

Stop the audio system.

# Arguments
- `system::WavesSystem`: The audio system to stop.
"""
function stop!(system::WavesSystem)
    system.is_running = false
    if system.audio_thread !== nothing
        system.audio_thread = nothing
    end
    @info "Audio system stopped."
end

"""
    close!(system::WavesSystem)

Close the audio system and release resources.

# Arguments
- `system::WavesSystem`: The audio system to close.
"""
function close!(system::WavesSystem)
    stop!(system)
    close(system.stream)
    @info "Audio system closed"
end

function play_chunk(system)
    output = take!(system.writing_channel)
    write_to_stream(system, output)
end

function write_to_stream(system, output)
    try
        stream = system.stream
        write(stream, output[])
    catch e
        system.metrics.underrun_count += 1
        @warn "Audio underrun detected"
        rethrow(e)
    end
end

samplerate(sys::WavesSystem) = sys.sample_rate
buffersize(sys::WavesSystem) = sys.buffer_size

end # module

