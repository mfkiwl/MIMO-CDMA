% Advanced Wireless Receivers - Final Project:
%
% CDMA IS 95 standard simulation
%
% Brian Odermatt, Francesco Gallo
%
% May 2020

function BER = simulator(P)

    if P.CDMAUsers > P.HamLen
       error('More users than available sequences')
    end
    
    % Initial values and constants
    
    Users = P.CDMAUsers;
    
    HadamardMatrix = hadamard(P.HamLen)/sqrt(P.HamLen);
    SpreadSequence = HadamardMatrix;
    SeqLen         = P.HamLen;
    
    NumberOfBits   = P.BitsPerUser * P.Modulation * Users; % per Frame
    
    NumberOfEncodedBits = NumberOfBits/P.ConvRate; % per Frame
    
    NumberOfChips  = P.BitsPerUser/P.ConvRate * P.Modulation * SeqLen; % per user, per Frame
    
    % PN spreading polynomials
    % in-phase (I)
    iPwrs = [15; 13; 9; 8; 7; 5; 0];
    iGen = zeros(16, 1);
    iGen(16-iPwrs) = ones(size(iPwrs));     % Gi = [ 1 0 1 0 0 0 1 1 1 0 1 0 0 0 0 1]';
    iState = [zeros(length(iGen)-1, 1); 1]; % Initial State
    % quadrature-phase (Q)
    qPwrs = [15; 12; 11; 10; 6; 5; 4; 3; 0];
    qGen = zeros(16, 1);
    qGen(16-qPwrs) = ones(size(qPwrs));     % Gq = [ 1 0 0 1 1 1 0 0 0 1 1 1 1 0 0 1]';
    qState = [zeros(length(qGen)-1, 1); 1]; % Initial State
    % PN spreading (quadrature spread length 2^15)
    [iPN, ~] = lsfrPN(iGen, iState, NumberOfChips);
    [qPN, ~] = lsfrPN(qGen, qState, NumberOfChips);
    
    % IQ modulated PN sequence
    PNSequence = - sign(iPN-1/2) - 1i*sign(qPN-1/2);

    % Convolutional encoder
    encoder = comm.ConvolutionalEncoder(...
        'TerminationMethod', 'Continuous',...
        'TrellisStructure', poly2trellis(9, [753 561])...
    );
    
%     % Convolutional decoder
%     decoder = comm.ViterbiDecoder(...
%         'TerminationMethod', 'Continuous',...
%         'TracebackDepth', 5*9,...
%         'TrellisStructure', poly2trellis(9, [753 561])...
%     );
%     

    % Channel
    switch P.ChannelType
        case 'Multipath'
            NumberOfChipsRX = NumberOfChips+P.ChannelLength-1;
        otherwise
            NumberOfChipsRX = NumberOfChips;
    end
    
    
    Results = zeros(1,length(P.SNRRange));


for ii = 1:P.NumberOfFrames
    
    ii

    Bits = randi([0 1], NumberOfBits/Users, Users); % Random Data
 
    % Convolutional encoding: rate 1/2
    EncBits = zeros(NumberOfEncodedBits/Users, Users);
    for i = 1:Users
        EncBits(:,i) = step(encoder, Bits(:,i));
    end
    EncBits = EncBits.';
        
    % Modulation
    switch P.Modulation % Modulate Symbols
        case 1 % BPSK
            symbols = -(2*EncBits - 1);
        otherwise
            error('Modulation not supported')
    end
        
    % Orthogonal spreading
    txsymbols = SpreadSequence(:,1:Users) * symbols;
        
    % apply PN sequence
    waveform = txsymbols(:).*PNSequence;

    % reshape to add multi RX antenna suppport
    waveform  = reshape(waveform,1,NumberOfChips);
    mwaveform = repmat(waveform,[1 1 Users]);
    
    % Channel
    switch P.ChannelType
        case 'Bypass'
            himp = ones(Users,1);
        case 'AWGN'
            himp = ones(Users,1);
        case 'Multipath'
            himp = sqrt(1/2)* ( randn(Users,P.ChannelLength) + 1i * randn(Users,P.ChannelLength) );
        otherwise
            error('Channel not supported')
    end
    
    %%%
    % Simulation
    snoise = randn(1,NumberOfChipsRX,Users) + 1i* randn(1,NumberOfChipsRX,Users);
    
    % SNR Range
    for ss = 1:length(P.SNRRange)
        SNRdb  = P.SNRRange(ss);
        SNRlin = 10^(SNRdb/10);
        noise  = 1/sqrt(2*SeqLen*SNRlin) *snoise;
        
        % Channel
        switch P.ChannelType
            case 'Bypass'
                y = mwaveform;
            case 'AWGN'
                y = mwaveform + noise;
            case 'Multipath'     
                y = zeros(1,NumberOfChips+P.ChannelLength-1,Users);
                for i = 1:Users
                    y(1,:,i) = conv(mwaveform(1,:,i),himp(i,:)) + noise(1,:,i); 
                end
            otherwise
                error('Channel not supported')
        end
        
 
        % Receiver
        switch P.ReceiverType
            case 'Rake'
                
                %RxBits = zeros(Users,NumberOfBits/Users);
                
                RxEncBits = zeros(Users,NumberOfEncodedBits/Users);
                
                for rr=1:Users
                    UserSequence = SpreadSequence(:,rr);
                    
                    FrameLength = P.BitsPerUser/P.ConvRate * SeqLen;
                    
                    fingers = zeros(P.ChannelLength,P.BitsPerUser/P.ConvRate);
                
                    for i=1:P.ChannelLength
                        data    =  y(1,i:i+FrameLength-1,rr)./PNSequence.'; 
                        rxvecs  = reshape(data,SeqLen,P.BitsPerUser/P.ConvRate);
                        fingers(i,:) = 1/SeqLen * UserSequence.' * rxvecs;
                    end
                    mrc = (1/norm(himp(rr,:))) * conj(himp(rr,:)) * fingers;
                    % Symbols for soft decoder
                    %RxBits(rr,:) = step(decoder, real(mrc).');
                    RxEncBits(rr,:) = real(mrc) < 0;
                end
                
            otherwise
                error('Receiver not supported')
        end
        
%         RxBits = reshape(RxBits,1,NumberOfBits);
%         Bits = reshape(Bits,1,NumberOfBits);
%         
%         % BER count
%         errors =  sum(RxBits ~= Bits);
        
        RxEncBits = reshape(RxEncBits,1,NumberOfEncodedBits);
        EncBits = reshape(EncBits,1,NumberOfEncodedBits);
        
        % BER count
        errors =  sum(RxEncBits ~= EncBits);
        
        Results(ss) = Results(ss) + errors;
        
    end
end

%     BER = Results/(NumberOfBits*P.NumberOfFrames);

BER = Results/(NumberOfBits/P.ConvRate*P.NumberOfFrames);
end