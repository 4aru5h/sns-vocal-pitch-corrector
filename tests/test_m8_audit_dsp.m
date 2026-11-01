function tests = test_m8_audit_dsp
%TEST_M8_AUDIT_DSP Comprehensive audit verification suite for preprocessing,
%   noise reduction, vocal conditioning, YIN accuracy, hysteresis contour,
%   TD-PSOLA resynthesis, multi-sample-rate support, and dark studio UI.
    tests = functiontests(localfunctions);
end

function testCleanSineAndDenoiseBypass(testCase)
    fs = 44100;
    t = (0:fs-1)' / fs;
    x = 0.8 * sin(2 * pi * 440 * t);
    cfg = pc_default_config();

    [xClean, info] = pc_preprocess(x, fs, cfg);
    testCase.verifyFalse(info.silent);
    % Studio-clean sine wave (SNR > 40 dB) must bypass spectral gating
    testCase.verifyFalse(info.denoiseApplied);
    testCase.verifyEqual(max(abs(xClean)), 0.95, 'AbsTol', 1e-12);
    testCase.verifyEqual(mean(xClean), 0, 'AbsTol', 1e-12);
end

function testNoiseReductionAtMultipleSnrLevels(testCase)
    fs = 44100;
    N = round(1.5 * fs);
    f0 = 220 * ones(N, 1);
    % Include brief leading/trailing quiet regions like a real vocal recording
    f0(1:round(0.18*fs)) = NaN;
    f0(end-round(0.18*fs)+1:end) = NaN;

    xCleanRef = pc_synth_voice(fs, f0);
    % Zero out the unvoiced leading/trailing segments so only stationary noise is there
    quietMask = false(N, 1);
    quietMask(1:round(0.15*fs)) = true;
    quietMask(end-round(0.15*fs)+1:end) = true;
    xCleanRef(quietMask) = 0;

    snrLevelsDb = [8, 15, 22];
    sigRms = sqrt(mean(xCleanRef(~quietMask).^2));

    for k = 1:numel(snrLevelsDb)
        rng(100 + k);
        targetSnr = snrLevelsDb(k);
        noiseRms = sigRms / (10^(targetSnr / 20));
        noise = noiseRms * randn(N, 1);
        xNoisy = xCleanRef + noise;

        cfg = pc_default_config();
        cfg.denoiseEnable = true;
        cfg.denoiseStrength = 1.0;

        [xOut, info] = pc_preprocess(xNoisy, fs, cfg);
        testCase.verifyTrue(info.denoiseApplied, ...
            sprintf('Expected denoiseApplied=true at %d dB SNR', targetSnr));
        testCase.verifyGreaterThan(info.snrImproveDb, 3.0, ...
            sprintf('Expected >3 dB SNR improvement at %d dB SNR (got %.2f dB)', targetSnr, info.snrImproveDb));

        % Verify quiet-segment noise RMS is significantly reduced relative to active vocal RMS
        inRatio  = sqrt(mean(xNoisy(quietMask).^2)) / sqrt(mean(xNoisy(~quietMask).^2));
        outRatio = sqrt(mean(xOut(quietMask).^2))   / sqrt(mean(xOut(~quietMask).^2));
        testCase.verifyLessThan(outRatio, inRatio * 0.65);

        % Verify YIN still tracks 220 Hz accurately on the cleaned signal
        yin = pc_yin(xOut, fs, cfg);
        medF0 = median(yin.f0(yin.voiced), 'omitnan');
        centsErr = 1200 * abs(log2(medF0 / 220));
        testCase.verifyLessThan(centsErr, 8.0);
    end
end

function testVocalFilterRumbleAndHissRejection(testCase)
    fs = 44100;
    t = (0:fs-1)' / fs;
    % 220 Hz vocal fundamental + 20 Hz sub-bass rumble + 14 kHz ultrasonic hiss
    xVocal  = 0.7 * sin(2 * pi * 220 * t) + 0.3 * sin(2 * pi * 440 * t);
    xRumble = 0.5 * sin(2 * pi * 20 * t);
    xHiss   = 0.4 * sin(2 * pi * 14000 * t);
    xMix    = xVocal + xRumble + xHiss;

    y = pc_vocal_filter(xMix, fs, struct('enableHighPass', true, 'enableLowPass', true, ...
                                         'highPassHz', 55, 'lowPassHz', 10000));

    % Compute FFT magnitude at 20 Hz, 220 Hz, and 14000 Hz
    Y = abs(fft(y));
    X = abs(fft(xMix));
    bin20    = round(20 * fs / fs) + 1;
    bin220   = round(220 * fs / fs) + 1;
    bin14000 = round(14000 * fs / fs) + 1;

    rumbleAttenDb = 20 * log10(Y(bin20) / X(bin20));
    vocalPassDb   = 20 * log10(Y(bin220) / X(bin220));
    hissAttenDb   = 20 * log10(Y(bin14000) / X(bin14000));

    testCase.verifyLessThan(rumbleAttenDb, -20.0, 'Sub-bass 20 Hz rumble must be attenuated by >20 dB');
    testCase.verifyGreaterThan(vocalPassDb, -0.5, '220 Hz fundamental must pass with <0.5 dB loss');
    testCase.verifyLessThan(hissAttenDb, -10.0, '14 kHz hiss must be attenuated by >10 dB');
end

function testLowAmplitudeAndIdleNoiseHandling(testCase)
    fs = 44100;
    N = fs;
    % 1. Valid low-amplitude vocal (-54 dBFS, peak = 0.002) must be recovered & corrected
    xQuietVocal = 0.002 * pc_synth_voice(fs, 215 * ones(N, 1));
    cfg = pc_default_config();
    resQuiet = pc_process(xQuietVocal, fs, cfg);
    testCase.verifyFalse(resQuiet.info.silent);
    testCase.verifyEqual(max(abs(resQuiet.x)), 0.95, 'AbsTol', 1e-12);
    testCase.verifyLessThan(resQuiet.metrics.meanAbsCentsOut, 10.0);

    % 2. 16-bit ADC idle quantization noise (1 LSB = 3.05e-5) must be gated as silent
    rng(99);
    xIdleAdc = (randi([0, 1], N, 1) * 2 - 1) * (1 / 32768);
    resIdle = pc_process(xIdleAdc, fs, cfg);
    testCase.verifyTrue(resIdle.info.silent);
    testCase.verifyEqual(max(abs(resIdle.y)), 0);
end

function testMultipleSampleRates(testCase)
    sampleRates = [16000, 22050, 44100, 48000];
    for sr = sampleRates
        N = round(0.8 * sr);
        % Detuned A3 (215 Hz -> should snap to 220 Hz in A minor / C major)
        x = pc_synth_voice(sr, 215 * ones(N, 1));
        cfg = pc_default_config();
        cfg.key = 'C';
        cfg.scale = 'major';
        cfg.strength = 1.0;
        cfg.retuneMs = 0;

        res = pc_process(x, sr, cfg);
        testCase.verifyEqual(numel(res.y), N);
        testCase.verifyTrue(all(isfinite(res.y)));
        testCase.verifyLessThan(res.metrics.meanAbsCentsOut, 10.0, ...
            sprintf('Failed pitch correction accuracy at fs=%d Hz', sr));
    end
end

function testMultiNoteTransitionsAndHysteresis(testCase)
    fs = 44100;
    N = round(1.6 * fs);
    % 4 notes in C major with detuning: C4(+35ct), D4(-30ct), E4(+25ct), G4(-35ct)
    notesMidi = [60.35, 61.70, 64.25, 66.65];
    f0Track = zeros(N, 1);
    seg = floor(N / 4);
    for k = 1:4
        idx = (k-1)*seg + 1 : min(N, k*seg);
        f0Track(idx) = pc_midi2hz(notesMidi(k));
    end

    x = pc_synth_voice(fs, f0Track);
    cfg = pc_default_config();
    cfg.key = 'C';
    cfg.scale = 'major';
    cfg.strength = 1.0;
    cfg.retuneMs = 0;

    res = pc_process(x, fs, cfg);
    testCase.verifyEqual(numel(res.y), N);
    testCase.verifyLessThan(res.metrics.meanAbsCentsOut, 0.35 * res.metrics.meanAbsCentsIn);
    testCase.verifyLessThanOrEqual(max(abs(res.y)), 1.0);

    % Verify boundary hysteresis prevents note chatter when hovering near 61.0 (midpoint of 60 and 62)
    hoverMidi = 61.0 + 0.04 * sin(2 * pi * 8 * (0:0.005:0.5)');
    hoverMidi(1) = 60.85; % starts slightly closer to 60 (C4)
    yinHover = struct('f0', pc_midi2hz(hoverMidi), 'voiced', true(size(hoverMidi)), ...
                      'tFrames', (0:0.005:0.5)');
    cHover = pc_correction_contour(yinHover, cfg);
    % Because oscillation is +-4 cents around 61.0 and hysteresis is 15 cents,
    % target note must remain locked at 60 without flipping to 62!
    testCase.verifyTrue(all(cHover.midiTarget == 60));
end

function testGuiNoEmojisAndFullWorkflow(testCase)
    app = PitchCorrectorApp('Visible', 'off');
    c1 = onCleanup(@() delete(app.fig));

    % Verify no UI control string contains emojis (all chars <= 127)
    allControls = findall(app.fig, 'Type', 'uicontrol');
    for k = 1:numel(allControls)
        str = get(allControls(k), 'String');
        if ischar(str)
            testCase.verifyTrue(all(double(str) <= 127), ...
                sprintf('Found non-ASCII/emoji char in control: %s', str));
        elseif iscell(str)
            for j = 1:numel(str)
                testCase.verifyTrue(all(double(str{j}) <= 127));
            end
        end
    end

    % Test workflow hooks: loadAudio -> preprocessAudio -> process -> resetDefaults
    fs = 44100;
    x = pc_synth_voice(fs, 215 * ones(round(0.6 * fs), 1));
    app.loadAudio(x, fs);
    app.preprocessAudio();
    app.process();

    res = app.getResult();
    testCase.verifyNotEmpty(res);
    testCase.verifyEqual(numel(res.y), numel(x));
    testCase.verifyEqual(res.metrics.targetNote, 'A3');
end
