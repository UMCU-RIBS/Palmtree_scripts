%   
%   Generate a vector in which each sample is placed on a theoretical
%   timeline. Can be used on source-data (.src) or pipeline-data (.dat)
%
%   [timeStamps] = pt_genTimelineVector(header, data, method)
%
%       header          = the source or pipeline header struct
%       data            = the source or pipeline data matrix
%       method          = The method that is used to generate a timeline vector, options:
%
%           - "ElapsedAndSamplerate": (only for V2) use the sample elapsed timestamp and theoretical 
%                                     samplerate of source- or pipeline-data. Will construct a 
%                                     timeline by assuming an equal distribution of samples counted
%                                     backwards from the last sample given the theoretical samplerate.
%                                     Recommended for accurate timestamping of pipeline-data or when
%                                     data has gaps that are not filled out by nans.
%                                     > Do not use when sample-packages arrive at irregular intervals
%                                       (e.g. Nexus time-domain source data) or are not received in
%                                       chronogical order.
%
%           - "ZeroLinearSamplerate": generate a timeline starting from 0, assign timestamps per 
%                                     sample couting forward using the theoretical samplerate.
%                                     Recommended for source-data with packages that come in at an 
%                                     irregular interval (e.g. nexus time-domain source data)
%                                     > Do not use when there are gaps in the sample data that are 
%                                       not filled out by nans. The elapsed time is used to warn for
%                                       gaps, but might not be fully accurate.
%
%           - "WallClock": TODO, Summit
%
%   Note: To compare the time of source and pipeline data that belong to the same run, make sure to
%         use the same method to generate a timeline vector. Even then, timing differences can occur
%         when the source module does not send the data straight through (e.g. delay in the Nexus
%         source module when set to time-domain)
%
%
%   Returns: 
%       timeStamps   = A vector, equal in size to the number of samples in the data matrix, with
%                      a timestamp per sample. Empty on failure.
%   
%   Copyright (C) 2021, Max van den Boom (Lab of Nick Ramsey, University Medical Center Utrecht, The Netherlands)

%   This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
%   as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
%   This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied 
%   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
%   You should have received a copy of the GNU General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.
%
function [timeStamps] = pt_genTimelineVector(header, data, method)
    timeStamps = [];
                
    % TODO: check header and data
    if isempty(data)
        fprintf(2, 'Error: empty data matrix\n');
        return;        
    end
    % TODO: check required columns

    % check the method argument
    if isempty(method)
        fprintf(2, 'Error: no ''method'' argument specified in call to function\n');
        return;
    end
    if ~strcmpi(method, 'ElapsedAndSamplerate') && ~strcmpi(method, 'ZeroLinearSamplerate')
        fprintf(2, ['Error: unknown ''method'' argument ''', method, ''' in call to function\n']);
        return;        
    end
    if strcmpi(method, 'ElapsedAndSamplerate') && header.version == 1   
        fprintf(2, 'Error: cannot apply the ''ElapsedAndSamplerate'' method to data in the version 1 format.\nThe elapsed time in this version indicates the time inbetween samples and is not precise enough to base timestamps on.\nUse the ''ZeroLinearSamplerate'' method instead.\n');
        return;
    end
    
    % extra checks in pipeline data
    if strcmpi(header.code, 'dat')
        
        % pipeline streams
        if header.numPlaybackStreams == 0   % quick way to check whether the pipeline input streams were not recorded
            fprintf(2, 'Error: pipeline input stream are required to build a reliable timeline, make sure LogPipelineInputStreams is enabled in the data-configuration.\n');
            return;
        end
        
        % with multiple samples per package
        if header.version == 2 && header.maxSamplesStream > 1
            
            % check for uneual #samples per package between streams
            if any([header.streams.samplesPerPackage] ~= [header.streams(1).samplesPerPackage])
                
                % determine whether there is any stream with more samples per package than the pipeline stream
                % Note: if streams are logged, then the first stream must be a pipeline stream
                % Note: we could work something out when any stream exceeds the #samples in the 
                %       pipeline stream, but it is very unlikely and a lot of effort
                if header.maxSamplesStream > header.streams(1).samplesPerPackage
                    fprintf(2, 'Error: at least one stream has a higher number of samples per package than the pipeline stream.\nBecause timestamping is based on pipeline input streams, having more samples will cause incorrect timestamping.\n');
                    return;
                end
                    
                % only unequal #samples per package per stream (less than pipeline)
                warning off backtrace;
                warning('Not all streams have the same number of samples/values per package. Be aware that the timestamps are based on the pipeline input stream, the sample timestamps might not be correct for the other streams.');
                
            end
                       
        end

    end
    
    % determine the time inbetween samples, based on the theoretical sampling-rate (in ms)
    timeBetweenSamples = 1 / header.sampleRate * 1000;
    
    % TODO: reason, what if irregular number of samples per package (could happen with source)
    %       the data driven number of samples per package is already calculated below, if we care to use it
    
    % timestamp according to method
    if strcmpi(method, 'ElapsedAndSamplerate') 
        % ElapsedAndSamplerate method (=V2, already checked)
        
        % is only one sample per package, then the elapsed times do not
        % need to be interpolated and can be returned as the stamps
        if header.maxSamplesStream == 1
            timeStamps = data(:, 2);
            return
        end
        
        % TODO: try to detect (by elapsed V2) and warn if sample-packages come in at an irregular interval
        %       if so, advice against and use ZeroLinearSamplerate instead
        
        % determine the last sample of each package based on the ID
        lastSamples = find(diff(data(:, 1)) > 0);
        lastSamples = [lastSamples; size(data, 1)];
        
        % determine the number of samples for each package
        numSamplesPerPackage = diff([0; lastSamples]);
        
        % initialize an output array
        timeStamps = nan(size(data, 1), 1);
        
        % loop over the packages
        % Note: per package, to deal with irregular numbers of samples per package
        sampleIndex = 1;
        for iPackage = 1:length(lastSamples)
            timeStamps(sampleIndex:sampleIndex + numSamplesPerPackage(iPackage) - 1) = ...
                data(sampleIndex:sampleIndex + numSamplesPerPackage(iPackage) - 1, 2) - ...
                ((numSamplesPerPackage(iPackage) - 1:-1:0) * timeBetweenSamples)';
            sampleIndex = sampleIndex + numSamplesPerPackage(iPackage);
        end
        
    elseif strcmpi(method, 'ZeroLinearSamplerate')
        % ZeroLinearSamplerate method 
        
        % TODO: try to detect (by elapsed, both V1 and V2) whether there are gaps in the data
        %       if so, then advice against; if V2 then also advuce to use ElapsedAndSamplerate instead
        
        % initialize an output array
        timeStamps = ((0:(size(data, 1) - 1)) * timeBetweenSamples)';
        
    end

end
