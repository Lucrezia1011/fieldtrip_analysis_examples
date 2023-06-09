ftpath   = '/home/liuzzil2/fieldtrip-20190812/';
addpath(ftpath)
ft_defaults

roothpath = '/data/EDB/MEG_AXCPT_Flanker/';

addpath ~/matlab_utils/

sublist = {'24531';'24563';'24590';'24580';'24626';'24581';'24482';...
    '24640';'24592';'24667';'24678' };

lowf  = 13; % above 1Hz
highf = 30; % up to 50HZ 

for ss = 1:length(sublist)
    sub = sublist{ss};
    
    if strcmp(sub,'24531')
        datapath = [roothpath,'data/sub-',sub,'/ses-02/meg/'];
        processingfolder = [roothpath,'derivatives/sub-',sub,'/ses-02/'];
        mri_name = [roothpath,'/data/sub-',sub,'/ses-01/anat/sub-',sub,'_acq-mprage_T1w.nii'];
    else
        datapath = [roothpath,'data/sub-',sub,'/meg/'];
        processingfolder = [roothpath,'derivatives/sub-',sub,'/'];
        mri_name = [roothpath,'data/sub-',sub,'/anat/sub-',sub,'_acq-mprage_T1w.nii'];
    end
    
    if ~exist(processingfolder,'dir')
        mkdir(processingfolder)
    end
    
    d = dir(datapath);
    filenames = cell(1,2);
    n = 0;
    for ii = 3:length(d)
        if  contains(d(ii).name,'meg.ds') && contains(d(ii).name,'task-axcpt')
            n = n+1;
            filenames{n} = d(ii).name;
        end
        
    end
    
    fids_name = ['sub-',sub,'_fiducials.tag'];
    
    close all
    
    %% Empty rooms
    
    
    cd(datapath)
    cd(filenames{1})
    fileID = fopen([filenames{1}(1:end-2),'infods'],'r');
    TaskDate = [];
    while isempty(TaskDate)
        tline = fscanf(fileID,'%s',1);
        %     tline = fgetl(fileID);
        if contains(tline,'DATASET_COLLECTIONDATETIME')
            tline = fscanf(fileID,'%s',1);
            
            ind20 = strfind(tline,'20'); % find start of date, i.e. 2019 or 2020
            TaskDate = tline(ind20(1)+[0:13]);
        end
    end
    fclose(fileID);
    
    d = dir([roothpath,'data/emptyroom/']);
    emptyroom = []; jj = 0;
    for ii = 3:length(d)
        if contains(d(ii).name, TaskDate(1:8))
            jj = jj + 1;
            emptyroom{jj} = [roothpath,'data/emptyroom/',d(ii).name];
        end
    end
    
    
    highpass = 1;
    lowpass = 120;
    icaopt = 1;
    plotopt = 0;
    
    % Data header info
    hdr = ft_read_header(emptyroom{1});
    % Get Bad channel names
    fid = fopen([emptyroom{1},'/BadChannels']);
    BadChannels = textscan(fid,'%s');
    fclose(fid);
    
    % get MEG channel names
    channels = hdr.label(strcmp(hdr.chantype,'meggrad'));
    % Delete Bad channels
    chanInd = zeros(size(channels));
    for iiC = 1:length(BadChannels{1})
        chanInd = chanInd | strcmp(channels,BadChannels{1}{iiC});
    end
    channels(find(chanInd)) = [];
    
    noiseC = zeros(length(channels),length(channels),length(emptyroom));
    noiseCbp = zeros(length(channels),length(channels),length(emptyroom));
    for ii = 1:length(emptyroom)
        
        
        cfg = [];
        cfg.dataset = emptyroom{ii};
        cfg.continuous = 'yes';
        cfg.channel = channels;
        cfg.demean = 'yes';
        cfg.detrend = 'no';
        cfg.bpfilter = 'yes';
        cfg.bpfreq = [lowpass, highpass]; % With notch filter 60Hz
        cfg.bsfilter = 'yes';
        cfg.bsfreq = [58 62; 118 122; 178 182]; % With notch filter 60Hz
        
        data_empty = ft_preprocessing(cfg);
        emptyC = zeros(length(channels),length(channels),length(data_empty.trial));
        for t = 1:length(data_empty.trial)
            emptyC = cov(data_empty.trial{t}');
        end
        noiseC(:,:,ii) = mean(emptyC,3);
        
        
        cfg.bpfreq = [lowf highf]; % With notch filter 60Hz
        data_empty = ft_preprocessing(cfg);
        emptyC = zeros(length(channels),length(channels),length(data_empty.trial));
        for t = 1:length(data_empty.trial)
            emptyC = cov(data_empty.trial{t}');
        end
        noiseCbp(:,:,ii) = mean(emptyC,3);
        
    end
    
    noiseCbp = mean(noiseCbp,3);
    noiseC = mean(noiseC,3);
    
    %% Standard pre-processing
    
    cd(datapath)
    
    if ~exist(mri_name,'file')
        mri_name = [mri_name,'.gz'];
    end
    fids_file =  [datapath(1:end-4),'anat/',fids_name];
    if ~exist(fids_file,'file')
        fids_file =  [datapath(1:end-4),'anat/sub-',sub,'_fiducials_axcpt.tag'];
    end
    mri = fids2ctf(mri_name,fids_file,0);
    
    
    for ii = 1:length(filenames)
        filename = filenames{ii};
        sub = filename(5:9);
        
        %     if ~exist([processingfolder,'/',filename(1:end-3),'/ICA_artifacts.mat'], 'file')
        
        [data,BadSamples] = preproc_bids(filename,processingfolder,highpass,lowpass,icaopt,plotopt);
        % eyelink
        if any(strcmp(data.hdr.label,'UADC009'))
            cfg = [];
            cfg.dataset = filename;
            cfg.continuous = 'yes';
            cfg.channel = {'UADC009';'UADC010';'UADC013'};
            eyed = ft_preprocessing(cfg);
            eyelink = eyed.trial{1};
            eyelink(:,BadSamples) = [];
        end
        
        % Read events
        [samples_T,trig_sample,buttonpress] = matchTriggers( filename, BadSamples);
        
        trig_sample.sample = samples_T(trig_sample.sample);
        trig_sample.type(trig_sample.sample == 0) = [];
        trig_sample.value(trig_sample.sample == 0) = [];
        trig_sample.sample(trig_sample.sample == 0) = [];
        
        buttonpress.left = samples_T(buttonpress.UADC006);
        buttonpress.left(buttonpress.left == 0) = [];
        buttonpress.right = samples_T(buttonpress.UADC007);
        buttonpress.right(buttonpress.right == 0) = [];
        
        if data.hdr.nSamplesPre == 0
            time=  1:length(samples_T);
            time(samples_T == 0) =[];
        else
            time= repmat( ((1:data.hdr.nSamples) - data.hdr.nSamplesPre),[1,data.hdr.nTrials] );
            
        end
        
        
        %% Find samples
        cue = 'A';
        % buttonpress to cue
        cuesampA = trig_sample.sample(strcmp(trig_sample.type, cue) ) ;
        
        [buttonsampA,rtA] = match_responses(cuesampA, buttonpress, 'left', data.fsample);
        cuesampA(buttonsampA==0) = [];
        
        cue = 'B';
        % buttonpress to cue
        cuesampB = trig_sample.sample(strcmp(trig_sample.type, cue) ) ;
        [buttonsampB,rtB] = match_responses(cuesampB, buttonpress, 'left', data.fsample);
        cuesampB(buttonsampB==0) = [];
        
        probe = 'AY';
        %buttonpress to probe
        probesampAY = trig_sample.sample(strcmp(trig_sample.type, probe)) ;
        
        buttonsampAYcomm = match_responses(probesampAY, buttonpress, 'right', data.fsample);
        [buttonsampAYcorr, rtAY] = match_responses(probesampAY, buttonpress, 'left', data.fsample);
        probesampAY( buttonsampAYcomm == 0 & buttonsampAYcorr == 0 ) = [];
        
        
        probe = 'AX';
        %buttonpress to probe
        probesampAX = trig_sample.sample(strcmp(trig_sample.type, probe)) ;
        
        buttonsampAXcorr = match_responses(probesampAX, buttonpress, 'right', data.fsample);
        buttonsampAXcomm = match_responses(probesampAX, buttonpress, 'left', data.fsample);
        probesampAX( buttonsampAXcomm == 0 & buttonsampAXcorr == 0 ) = [];
        
        probe = 'BX';
        %buttonpress to probe
        probesampBX = trig_sample.sample(strcmp(trig_sample.type, probe)) ;
        
        buttonsampBXcomm = match_responses(probesampBX, buttonpress, 'right', data.fsample);
        buttonsampBXcorr = match_responses(probesampBX, buttonpress, 'left', data.fsample);
        probesampBX( buttonsampBXcomm == 0 & buttonsampBXcorr == 0 ) = [];
        
        probe = 'BY';
        %buttonpress to probe
        probesampBY = trig_sample.sample(strcmp(trig_sample.type, probe)) ;
        
        buttonsampBYcomm = match_responses(probesampBY, buttonpress, 'right', data.fsample);
        buttonsampBYcorr = match_responses(probesampBY, buttonpress, 'left', data.fsample);
        probesampBY( buttonsampBYcomm == 0 & buttonsampBYcorr == 0 ) = [];
        
        %% Beamfomer leadfields
        % Co-register MRI
        
        gridres = 5; % 5mm grid
        gridl =mniLeadfields_multiSpheres(filenames{ii},processingfolder,gridres,mri); % calculate leadfields on MNI grid
        
        % For power
        % Load standard brain for plotting
        %     mri_mni = ft_read_mri('~/fieldtrip-20190812/external/spm8/templates/T1.nii','dataformat','nifti');
        mri_mni = ft_read_mri('~/MNI152_T1_2009c.nii'); % in mni coordinates
        mri_mni.coordsys = 'mni';
        
        load(fullfile(ftpath, ['template/sourcemodel/standard_sourcemodel3d',num2str(gridres),'mm']));
        sourcemodel.coordsys = 'mni';
        
        %% Beamfomer
        if isfield(data.cfg,'component')
            icacomps = length(data.cfg.component);
        else
            icacomps = 0;
        end
        C = cov(data.trial{1}');
        
        nchans = length(data.label);
        % E = svd(C);
        % noiseSVD = eye(nchans)*E(end-icacomps); % ICA eliminates from 2 to 4 components
        E = svd(noiseC);
        noiseSVD = eye(nchans)*E(end);
        mu  =4;
        Cr = C + mu*noiseSVD; % old normalization
        %     Cr = C + 0.05*eye(nchans)*E(1); % 5% max singular value
        
        L = gridl.leadfield(gridl.inside);
        
        weigths_file = sprintf('%s%s/weights_multiSpheres_%dmm_regmu%d.mat',processingfolder,filename(1:end-3),gridres,mu);
        if ~exist(weigths_file,'file')
            W = cell(size(L));
            Wdc = cell(size(L));
            parfor l = 1:length(L)
                
                lf = L{l}; % Unit 1Am
                
                % G O'Neill method, equivalent to fieldtrip
                [v,d] = svd(lf'/Cr*lf);
                d = diag(d);
                jj = 2;
                
                lfo = lf*v(:,jj); % Lead field with selected orientation
                
                w = Cr\lfo / sqrt(lfo'/(Cr^2)*lfo) ;
                Wdc{l} = w;
                % no depth correction as we later divide by noise
                w = Cr\lfo / (lfo'/Cr*lfo) ; % weights
                W{l} = w;
                
                if mod(l,300) == 0
                    clc
                    fprintf('SAM running %.1f\n',...
                        l/length(L)*100)
                end
                
            end
            save(weigths_file,'W','Wdc')
        else
            load(weigths_file)
        end
        
        
        
        %% Oscillatory power
        
        freq = [lowf highf];
        filt_order = []; % default
        
        dataf = data;
        data_filt = ft_preproc_bandpassfilter(data.trial{1}, data.fsample,freq,filt_order,'but');
        dataf.trial{1} = data_filt;
        clear data_filt
        
        twind = [0.0 0.5];
        [dataprobeAY,~] = define_trials(probesampAY ,dataf,time,twind,1);
        [dataprobeAX,~] = define_trials(probesampAX,dataf,time,twind,1);
        [dataprobeBY,~] = define_trials(probesampBY ,dataf,time,twind,1);
        [dataprobeBX,~] = define_trials(probesampBX,dataf,time,twind,1);
        [datacueA,~] = define_trials(cuesampA,dataf,time,twind,1);
        [datacueB,~] = define_trials(cuesampB,dataf,time,twind,1);
        
        CA = cov(cell2mat(datacueA.trial)');
        CB = cov(cell2mat(datacueB.trial)');
        CAX = cov(cell2mat(dataprobeAX.trial)');
        CAY = cov(cell2mat(dataprobeAY.trial)');
        CBX = cov(cell2mat(dataprobeBX.trial)');
        CBY = cov(cell2mat(dataprobeBY.trial)');
        
        
        PprobeAX = cell(size(L));
        PprobeAY = cell(size(L));
        PprobeBX = cell(size(L));
        PprobeBY = cell(size(L));
        PcueA = cell(size(L));
        PcueB = cell(size(L));
        for l = 1:length(L)
            w = W{l};
            PprobeAY{l} = (w'*CAY*w)  / (w'*noiseCbp*w);
            PprobeAX{l} = (w'*CAX*w)  / (w'*noiseCbp*w);
            PprobeBY{l} = (w'*CBY*w)  / (w'*noiseCbp*w);
            PprobeBX{l} = (w'*CBX*w)  / (w'*noiseCbp*w);
            PcueA{l} = (w'*CA*w) / (w'*noiseCbp*w);
            PcueB{l} = (w'*CB*w) / (w'*noiseCbp*w);
        end
        
        PprobeAX  = cell2mat(PprobeAX)';
        PprobeAY  = cell2mat(PprobeAY)';
        PprobeBX  = cell2mat(PprobeBX)';
        PprobeBY  = cell2mat(PprobeBY)';
        PcueA  = cell2mat(PcueA)';
        PcueB  = cell2mat(PcueB)';
        
        save( sprintf('%s%s/Pow%d-%dHz_multiSpheres_%dmm_regmu%d.mat',...
            processingfolder,filename(1:end-3),lowf,highf,gridres,mu) ,...
            'PprobeAX','PprobeAY','PprobeBX','PprobeBY','PcueA','PcueB');
    end
end
