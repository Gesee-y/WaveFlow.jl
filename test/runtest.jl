include(joinpath("..","src","WaveFlow.jl"))

using .WaveFlow
using Test

const SND1_PATH = joinpath("assets", "snd1.ogg")
const SND2_PATH = joinpath("assets", "snd2.ogg")

const LSND1_PATH = joinpath("assets", "long_snd1.ogg")
const LSND2_PATH = joinpath("assets", "long_snd2.ogg")

@testset "WaveFlow" begin
	@testset "WaveSystem Creation" begin
		sys = init_waves()

		@test sys isa WavesSystem
		@test samplerate(sys) == 44100
		@test buffersize(sys) == 1024
	end

	@testset "Audio loading" begin
	    sys = WavesSystem()
	    start!(sys)

	    bus = create_bus()
	    group = create_group()

	    add_bus!(sys, bus)
	    add_to_bus!(bus, group)
		snd1 = load_audio(SND1_PATH)

		@test snd1 isa AudioSource

		add_to_group!(group, snd1)
        
        println("You should hear a quick sound.")
		play!(snd1)
		sleep(2)

        snd2 = load_audio(SND2_PATH)
		add_to_group!(group, snd2)

        println("You should hear 2 quick sound playing at the same time.")
        play!(snd1)
        play!(snd2)
        sleep(3)

        close!(sys)
	end

	@testset "Audio streaming loading" begin
		sys = WavesSystem()
	    start!(sys)

	    bus = create_bus()
	    group = create_group()

	    add_bus!(sys, bus)
	    add_to_bus!(bus, group)
		snd1 = load_audio(LSND1_PATH; stream=true)

		@test snd1 isa StreamingAudioSource

		add_to_group!(group, snd1)

		println("You should hear a music")
		play!(snd1)

		@test snd1.state == Waves.PLAYING
		sleep(3)
		pause!(snd1)
		println("The music should have stopped")
		@test snd1.state == Waves.PAUSED
		sleep(2)

        snd2 = load_audio(LSND2_PATH; stream=true)
		add_to_group!(group, snd2)

        resume!(snd1)
        @test snd1.state == Waves.PLAYING

        play!(snd2)
        println("You should be hearing 2 music playing at the same time.")
        sleep(3)

        close!(sys)
	end

	@testset "Audio Effects" begin
		sys = WavesSystem()
	    start!(sys)

	    bus = create_bus()
	    group = create_group()

	    add_bus!(sys, bus)
	    add_to_bus!(bus, group)
		snd1 = load_audio(LSND1_PATH; stream=true)
		sine_snd = generate_sine_wave(5,3)

		add_to_group!(group, sine_snd)
		play!(sine_snd)
		sleep(3.2)

		noise_snd = generate_white_noise(3)
		add_to_group!(group, noise_snd)
		play!(noise_snd)
		sleep(3.2)

		rev = create_reverb()
		add_effect!(group, rev)
		add_to_group!(group, snd1)

		println("You should hear a familiar sound.")
		play!(snd1)

		sleep(5)

        close!(sys)
        sleep(5)
	end
end
