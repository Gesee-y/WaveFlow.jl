# WaveFlow.jl — Julia Audio Engine

WaveFlow is a full-featured real-time audio engine written in Julia. It provides flexible tools to load, play, stream, and generate audio signals with support for effect processing, multi-channel mixing, and real-time audio metrics. WaveFlow is designed for interactive applications such as games, multimedia projects, sound design, and procedural audio generation.

---

## Table of Contents

1. [Getting Started: WavesSystem](#getting-started-wavessystem)
2. [Buses and Groups](#buses-and-groups)
3. [Loading and Playing Audio](#loading-and-playing-audio)
4. [Streaming Audio](#streaming-audio)
5. [Playback Controls](#playback-controls)
6. [Procedural Audio Generation](#procedural-audio-generation)
7. [Audio Effects](#audio-effects)
8. [Audio Metrics and Monitoring](#audio-metrics-and-monitoring)
9. [Utility Functions](#utility-functions)
10. [Managing the Audio System Lifecycle](#managing-the-audio-system-lifecycle)
11. [Performance Tips](#performance-tips)

---

## Getting Started: WavesSystem

The `WavesSystem` is the central object managing all audio operations. It handles audio streams, mixing, effects, and playback scheduling.

```julia
using WaveFlow

# Create an audio system with default sample rate (44.1 kHz) and buffer size (1024 samples)
sys = WavesSystem()

# You can customize sample rate and buffer size:
sys_custom = WavesSystem(sample_rate=48000, buffer_size=2048)

# On Linux running pulse (e.g. Ubuntu) you connect to pulse like this:
sys = WavesSystem(input_device = "pulse", output_device = "pulse")
```

* **Sample rate:** Number of audio samples per second. Higher rates increase quality but also CPU load.
* **Buffer size:** Number of samples processed per audio callback. Smaller buffers reduce latency but increase CPU overhead and risk underruns.

### Starting and Stopping the System

Start the audio system processing loop (runs on a dedicated thread):

```julia
start!(sys)
```

Pause audio processing temporarily:

```julia
stop!(sys)
```

Resume audio processing after stop:

```julia
start!(sys)
```

Close the system and release all audio resources:

```julia
close!(sys)
```

> **Important:** Once closed, a `WavesSystem` cannot be restarted. You must create a new instance to use audio again.

---

## Buses and Groups

WaveFlow organizes audio sources using **buses** and **groups**, similar to professional audio middleware.

* **AudioBus:** Acts like a mixer channel. Can contain multiple groups and effects.
* **AudioGroup:** A collection of audio sources. Effects can be applied at the group level.

### Creating and Adding Buses and Groups

```julia
bus = create_bus()
add_bus!(sys, bus)

group = create_group()
add_to_bus!(bus, group)
```

You can create multiple groups per bus to separate different audio categories (e.g., music, sound effects, voices) and apply different processing.

---

## Loading and Playing Audio

Load an audio file into the system:

```julia
snd = load_audio("path/to/audio.ogg"; stream=false)
```

* `stream=false` (default) loads the entire file into memory for quick access (best for short sounds).
* `stream=true` loads audio progressively, suitable for long music tracks or large files.

Add the loaded audio source to a group:

```julia
add_to_group!(group, snd)
```

### Playback

Start playback:

```julia
play!(snd)
```

Pause playback:

```julia
pause!(snd)
```

Resume playback:

```julia
resume!(snd)
```

Stop playback:

```julia
stop!(snd)
```

Seek to a position in seconds:

```julia
seek!(snd, 30.0)  # Jump to 30 seconds
```

Check playback state:

```julia
snd.state == WaveFlow.PLAYING
snd.state == WaveFlow.PAUSED
```

---

## Streaming Audio

For long audio files, streaming prevents loading the entire file into memory:

```julia
long_snd = load_audio("path/to/long_audio.ogg"; stream=true)
add_to_group!(group, long_snd)
play!(long_snd)
```

Streaming audio sources behave like regular sources but manage internal buffers to fetch data on demand.

---

## Playback Controls

All audio sources share the same control API:

| Function          | Description                |
| ----------------- | -------------------------- |
| `play!(src)`      | Start playback             |
| `pause!(src)`     | Pause playback             |
| `resume!(src)`    | Resume playback            |
| `stop!(src)`      | Stop playback              |
| `seek!(src, pos)` | Seek to position (seconds) |

You can safely call these functions on any loaded audio source.

---

## Procedural Audio Generation

WaveFlow can generate synthetic audio signals in real-time:

### Generate a sine wave

```julia
sine = generate_sine_wave(frequency=440.0, duration=3.0, amplitude=0.5)
add_to_group!(group, sine)
play!(sine)
```

* Generates a pure tone at given frequency (Hz), duration (seconds), amplitude (0.0 to 1.0).

### Generate white noise

```julia
noise = generate_white_noise(duration=3.0, amplitude=0.1)
add_to_group!(group, noise)
play!(noise)
```

Useful for sound design or testing.

---

## Audio Effects

WaveFlow supports real-time audio effects implemented as functions processing audio buffers. Effects are modulable and can be added to buses or groups.

### Creating and Applying Effects

#### Reverb

```julia
rev = create_reverb(room_size=0.6, damping=0.4, wet_level=0.3, dry_level=0.7)
add_effect!(group, rev)
```

#### Delay

```julia
delay = create_delay(delay_time=0.3, feedback=0.4, wet_level=0.5)
add_effect!(bus, delay)
```

#### Compressor

```julia
comp = create_compressor(threshold=0.7, ratio=4.0, attack=0.005, release=0.1)
add_effect!(group, comp)
```

#### EQ Filter

```julia
eq = create_eq_filter(:bandpass, frequency=1000.0, gain=3.0, q=1.0)
add_effect!(bus, eq)
```

### Effect Chaining

Multiple effects can be added to a single group or bus and are applied in the order added.

---

## Audio Metrics and Monitoring

You can retrieve detailed audio metrics to monitor playback quality and system performance:

```julia
metrics = get_metrics(sys)

println("Peak Left: ", metrics.peak_left)
println("Peak Right: ", metrics.peak_right)
println("RMS Left: ", metrics.rms_left)
println("RMS Right: ", metrics.rms_right)
println("Clips: ", metrics.clip_count)
println("Underruns: ", metrics.underrun_count)
println("CPU Usage: ", metrics.cpu_usage)
```

Reset metrics counters:

```julia
reset_metrics!(sys)
```

These metrics help detect clipping, underruns, and monitor CPU load during playback.

---

## Utility Functions

* Find an audio source by ID:

```julia
src = find_source(sys, "source_id")
```

* List all loaded sources:

```julia
all_sources = list_all_sources(sys)
println(all_sources)
```

* Apply limiter to a signal to prevent clipping:

```julia
apply_limiter!(signal_matrix, threshold=0.95)
```

---

## Managing the Audio System Lifecycle

1. Create the `WavesSystem`.
2. Start the system with `start!`.
3. Create buses and groups, add audio sources.
4. Play, pause, and control audio as needed.
5. Monitor metrics for stability and performance.
6. When finished, stop with `stop!` or close with `close!`.

---

## Performance Tips

* Use sufficient Julia threads (`JULIA_NUM_THREADS`) to allow the audio thread to run smoothly alongside other computations.
* Choose buffer sizes balancing latency and CPU load: smaller buffers reduce latency but may increase underrun risk.
* Stream long audio files rather than loading fully to save memory.
* Monitor audio metrics regularly to detect performance issues early.

---

# Summary

WaveFlow.jl provides a powerful, flexible audio system with:

* Real-time audio playback and streaming
* Procedural signal generation
* Effect processing with reverb, delay, compressor, EQ
* Multi-layer mixing via buses and groups
* Real-time metrics and monitoring
* A clean, Julian API designed for interactive and game development contexts
