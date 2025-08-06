# WaveFlow : An audio system in Julia

Julia has been a rising promising language these past years. It has a growing community and wide variety of tools for science. However, the audio ecosystem is quite incomplete. The pieces are there but no one has connected them.
So here is waves who reuse the existing tools ([LibSndFile.jl](), [PortAudio.jl](), [DSP.jl]() and [SampledSignals.jl]()) to make a ready-to-use audio system, just plug and play.

## Installation

```julia
julia> ]add WaveFlow
```

For the development version

```julia
julia> ]add https://github.com/Gesee-y/WaveFlow.jl
```

## Features

* **File loading**: Waves can load a wide variety of format such as ogg, wav, mpeg and soon mp3
* **Streaming**: Waves use a circular buffer to let you play long audio without comsuming too much memory and processing power.
* **Groups and Bus**: Waves let you create sound groups and sound bus for more granular control over you sounds
* **Mixing**: You are not limited to one sound at a time.
* **Configurable**: You can manage volume, panning, pitch, speed as you want.
* **Effects**: Add reverb, equalizer, compressor or even you custom effect on your sounds!
* **Metrics**: Track CPU usage, signal peaks, and more — updated in real-time
* **Real-time audio**: Powered by PortAudio for low-latency playback

## Example

```julia
snd = load_audio("audio.ogg"; stream=true)
sys = WaveSystem()

bus = create_bus("main")
group = create_group("sfx")

add_bus!(sys, bus)
add_to_bus!(bus, group)
add_to_group!(group, snd)

play!(snd)
```

## Requirement

If you have some expensive computations going at the same time as WaveFlow, you will have to have at least 2 Julia threads enabled to avoid audio lag.

## License

This package is under the MIT license.
But note that it rely on some external library with their own license, so you should check the license of the dependencies and accomodate to them.

## Bug report

Feel free to leave an issue if you encounter a bug.

