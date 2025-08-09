

# Génération de signaux de test
"""
    generate_sine_wave(frequency, duration, sample_rate=44100.0, amplitude=0.5)

Generate a sine wave audio source.

# Arguments
- `frequency::Float64`: Frequency in Hz.
- `duration::Float64`: Duration in seconds.
- `sample_rate::Float64`: Sample rate in Hz (default: 44100.0).
- `amplitude::Float64`: Amplitude (default: 0.5).

# Returns
- `AudioSource`: Sine wave audio source.
"""
function generate_sine_wave(frequency::Real, duration::Real,
                          sample_rate::Real=44100.0, amplitude::Real=0.5)
    samples = Int(duration * sample_rate)
    isodd(samples) && (samples -= 1)
    t = (0:samples-1)
    data = amplitude * sin.(2π * frequency * t)
    return AudioSource(reshape(data, samples÷2, 2), sample_rate)
end

"""
    generate_white_noise(duration, sample_rate=44100.0, amplitude=0.1)

Generate a white noise audio source.

# Arguments
- `duration::Float64`: Duration in seconds.
- `sample_rate::Float64`: Sample rate in Hz (default: 44100.0).
- `amplitude::Float64`: Amplitude (default: 0.1).

# Returns
- `AudioSource`: White noise audio source.
"""
function generate_white_noise(duration::Real, sample_rate::Real=44100.0,
                            amplitude::Real=0.1)
    samples = Int(duration * sample_rate)
    isodd(samples) && (samples -= 1)
    data = amplitude * (2 * rand(Float32, samples) .- 1)
    return AudioSource(reshape(data, samples÷2, 2), sample_rate)
end

"""
    create_reverb(room_size=0.5, damping=0.5, wet_level=0.3, dry_level=0.7)

Create a modulable reverb effect.

# Arguments
- `room_size::Float64`: Room size (0.0 to 1.0).
- `damping::Float64`: Damping factor (0.0 to 1.0).
- `wet_level::Float64`: Wet signal level (0.0 to 1.0).
- `dry_level::Float64`: Dry signal level (0.0 to 1.0).

# Returns
- `ModulableEffect`: Reverb effect with modulable parameters.
"""
function create_reverb(room_size::Float64=0.5, damping::Float64=0.5,
                      wet_level::Float64=0.3, dry_level::Float64=0.7)
    params = Dict(:room_size => room_size, :damping => damping, :wet_level => wet_level, :dry_level => dry_level)
    function reverb_effect(signal::SubArray{Float32, 1, Matrix{Float32}}, true},
        p::Dict{Symbol, Float32})
        delay_samples = Int[1323, 2205, 3087]
        decay_factors = [0.6 * (1-p[:damping]), 0.4 * (1-p[:damping]), 0.3 * (1-p[:damping])]
        out = copy(signal) * p[:dry_level]
        for (delay, decay) in zip(delay_samples, decay_factors)
            for i in 1:(length(signal)-delay)
                out[i+delay] += p[:wet_level] * decay * signal[i] * p[:room_size]
            end
        end
        return out
    end
    return ModulableEffect(reverb_effect, params)
end

"""
    create_delay(delay_time=0.3, feedback=0.3, wet_level=0.3, sample_rate=44100.0)

Create a modulable delay effect.

# Arguments
- `delay_time::Float64`: Delay time in seconds.
- `feedback::Float64`: Feedback level (0.0 to 1.0).
- `wet_level::Float64`: Wet signal level (0.0 to 1.0).
- `sample_rate::Float64`: Sample rate in Hz (default: 44100.0).

# Returns
- `ModulableEffect`: Delay effect with modulable parameters.
"""
function create_delay(delay_time::Float64=0.3, feedback::Float64=0.3,
                     wet_level::Float64=0.3, sample_rate::Float64=44100.0)
    params = Dict(:delay_time => delay_time, :feedback => feedback, :wet_level => wet_level, :sample_rate => sample_rate)
    function delay_effect(signal::SubArray{Float32, 1, Matrix{Float32}}, p::Dict{Symbol, Float32})
        delay_samples = Int(p[:delay_time] * p[:sample_rate])
        out = copy(signal)
        for i in 1:(length(signal)-delay_samples)
            out[i+delay_samples] += p[:wet_level] * p[:feedback] * signal[i]
        end
        return out
    end
    return ModulableEffect(delay_effect, params)
end

"""
    create_compressor(threshold=0.7, ratio=4.0, attack=0.003, release=0.1)

Create a modulable compressor effect.

# Arguments
- `threshold::Float64`: Threshold level (0.0 to 1.0).
- `ratio::Float64`: Compression ratio (1.0 to inf).
- `attack::Float64`: Attack time in seconds.
- `release::Float64`: Release time in seconds.

# Returns
- `ModulableEffect`: Compressor effect with modulable parameters.
"""
function create_compressor(threshold::Float64=0.7, ratio::Float64=4.0,
                          attack::Float64=0.003, release::Float64=0.1)
    params = Dict(:threshold => threshold, :ratio => ratio, :attack => attack, :release => release)
    function compressor_effect(signal::SubArray{Float32, 1, Matrix{Float32}}, p::Dict{Symbol, Float32})
        out = copy(signal)
        envelope = 0.0
        for i in 1:length(signal)
            input_level = abs(signal[i])
            if input_level > envelope
                envelope += (input_level - envelope) * p[:attack]
            else
                envelope += (input_level - envelope) * p[:release]
            end
            if envelope > p[:threshold]
                reduction = (envelope - p[:threshold]) / p[:ratio]
                out[i] = signal[i] * (p[:threshold] + reduction) / envelope
            end
        end
        return out
    end
    return ModulableEffect(compressor_effect, params)
end

"""
    create_eq_filter(type::Symbol, frequency, gain=0.0, q=1.0, sample_rate=44100.0)

Create a modulable EQ filter effect.

# Arguments
- `type::Symbol`: Filter type (:lowpass, :highpass, :bandpass).
- `frequency::Float64`: Center frequency in Hz.
- `gain::Float64`: Gain in dB (default: 0.0).
- `q::Float64`: Q factor (default: 1.0).
- `sample_rate::Float64`: Sample rate in Hz (default: 44100.0).

# Returns
- `ModulableEffect`: EQ filter effect with modulable parameters.
"""
function create_eq_filter(type::Symbol, frequency::Float64, gain::Float64=0.0,
                         q::Float64=1.0, sample_rate::Float64=44100.0)
    params = Dict(:type => type, :frequency => frequency, :gain => gain, :q => q, :sample_rate => sample_rate)
    function eq_effect(signal::SubArray{Float32, 1, Matrix{Float32}}, p::Dict{Symbol, Float32})
        if p[:type] == :lowpass
            resp = Lowpass(p[:frequency]; fs=p[:sample_rate])
        elseif p[:type] == :highpass
            resp = Highpass(p[:frequency]; fs=p[:sample_rate])
        elseif p[:type] == :bandpass
            resp = Bandpass(p[:frequency]-p[:frequency]/p[:q], p[:frequency]+p[:frequency]/p[:q]; fs=p[:sample_rate])
        else
            error("Type de filtre non supporté: $(p[:type])")
        end
        filt = digitalfilter(resp, Butterworth(4))
        filtered = DSP.filt(filt, signal)
        return signal .+ (filtered .- signal) .* (10^(p[:gain]/20) - 1)
    end
    return ModulableEffect(eq_effect, params)
end

function apply_limiter!(signal::Matrix{Float32}, threshold::Float32=0.95)
    @inbounds for i in 1:length(signal)
        if abs(signal[i]) > threshold
            signal[i] = sign(signal[i]) * threshold
        end
    end
end