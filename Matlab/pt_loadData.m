%   
%   Read the source data (.src) or pipeline data (.dat) of a Palmtree run. 
%   The source data (.src) file contains the data as it is received by the source module. The
%   pipeline data (.dat) file contains the data streams that went into the pipeline and - if 
%   enabled - the output of the filter modules and application modules.
%
%   [header, data] = pt_loadData(filepath, readData)
%
%       filepath            = path to a run data file
%       readData (optional) = If set to 0 (default), only the header will be read.
%                             If set to 1, both the header and the data will be read
%
%   Returns: 
%       header       = The data header information as a struct, includes information such as the sampling
%                      rate, number of streams and stream names. Returns as much of the header as possible
% 		data         = A matrix holding the data. The first column will be the sample-number, the second
%                      column holds the number of milliseconds that have passed since the last sample, and the 
%                      remaining columns represent the sample values that streamed through the pipeline (the header
%                      information can be used to find the exact channel(s) and where in the pipeline.
%                      Returns empty on failure
%   
%   Copyright (C) 2021, Max van den Boom (Lab of Nick Ramsey, University Medical Center Utrecht, The Netherlands)

%   This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
%   as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
%   This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied 
%   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
%   You should have received a copy of the GNU General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.
%
function [header, data] = pt_loadData(inputFilepath, readData)
    if ~exist('readData', 'var') || isempty(readData),  readData = [];   end    

    % default return values
    header = [];
    data = [];
    
    % check if the dat input file exist
    if exist(inputFilepath, 'file') == 0
        fprintf(2, ['Error: data file ', strrep(inputFilepath, '\', '\\'), ' does not exist\n']);
        return;
    end

    % open the file
    fileID = fopen(inputFilepath, 'rb', 'l');
    if fileID == -1
        fprintf(2, ['Error: could not open data file ', inputFilepath, '\n']);
        return;
    end
    
    % create an empty header
    header = struct;
    
    % retrieve the filesize
    fileSize = dir(inputFilepath);
    header.filesize = fileSize.bytes;
    clear fileSize;
    
    % read the version and check whether it is valid
    header.version = fread(fileID, 1, 'int32');
    if (header.version ~= 1 && header.version ~= 2)
        fprintf(2, ['Error: unknown data version ', num2str(header.version), '\n']);
        return;
    end
    
    % read the code
    header.code = fread(fileID, 3, '*char')';
    
    % retrieve the epochs (V2)
    if (header.version == 2)
        header.runStartEpoch                = fread(fileID, 1, 'int64');
        header.fileStartEpoch               = fread(fileID, 1, 'int64');
    end
    
    % 
    header.sampleRate                       = fread(fileID, 1, 'double');
    header.numPlaybackStreams               = fread(fileID, 1, 'int32');
    
    % #streams + streams details (V2)
    if (header.version == 2)
        header.numStreams                   = fread(fileID, 1, 'int32');
        for iStream = 1:header.numStreams
            streamStruct                    = struct;
            streamStruct.type               = fread(fileID, 1, 'uint8');
            streamStruct.samplesPerPackage  = fread(fileID, 1, 'uint16');
            header.streams(iStream)         = streamStruct;
        end
    end
    
    % #columns + columns names
    header.numColumns                       = fread(fileID, 1, 'int32');
    header.columnNamesSize                  = fread(fileID, 1, 'int32');
    header.columnNames                      = fread(fileID, header.columnNamesSize, '*char')';
    header.columnNames                      = strsplit(header.columnNames,'\t');

    % store the position where the data starts
    header.posDataStart = ftell(fileID);
    
    
    %
    % extra fields and reading the data
    %
    
    % determine the file type
    fileType = 2;           % 0 = source, 1 = pipeline, 2 = plugin
    if strcmpi(header.code, 'src'),      fileType = 0;   end
    if strcmpi(header.code, 'dat'),      fileType = 1;   end
	
    %
    if (header.version == 1)
        
        % determine the size of one row (in bytes)
        if (fileType == 0 || fileType == 1)
            % source or pipeline data
            
            header.rowSize = 4;                                             % sample id
            header.rowSize = header.rowSize + (header.numColumns - 1) * 8;  % sample data
            
        else
            % plugin data
            
            header.rowSize = header.numColumns * 8;
            
        end
        
        % determine the number of rows
        header.numRows = floor((header.filesize - header.posDataStart) / header.rowSize);
    
        % check whether to read the data
        if readData == 1

            % read the samples
            data = nan(header.numRows, header.numColumns);
            for iRow = 1:header.numRows

                % read the samplecounter
                data(iRow, 1) = fread(fileID, 1, 'uint32');

                % read the rest of the values
                data(iRow, 2:header.numColumns) = fread(fileID, header.numColumns - 1, 'double');

            end
            clear iRow;

        end
        
    elseif (header.version == 2)
    
        % counter for the number of samples
        header.totalSamples     = 0;
        header.totalPackages    = 0;

        % determine the highest number of samples that any source stream (.src) or any stream in the pipeline (.dat) would want to log
        header.maxSamplesStream = max([header.streams.samplesPerPackage]);
        
        % read the headers of all the packages
        % Note: Needs to be performed first to establish .totalSamples. With .totalSamples calculated
        %       the readPackages can allocate a matrix big enough for the data on the second call)
        [success, header] = readPackages(fileID, header, fileType, 0);
        if success == 1

            % read the data (if needed)
            if readData == 1
                [success, header, data] = readPackages(fileID, header, fileType, 1);
                if success == 0,    data = [];       end
            end
            
        end
        
    end
    
    % close the file
    fclose(fileID);
    clear fileID;
    
end

% Note: if readData == 1, then assumes header.totalSamples is set and correct
function [success, header, data] = readPackages(fileID, header, fileType, readData)
    success = 0;
    data = [];
    
    % set the read cursor at the start of the data
    fseek(fileID, header.posDataStart, 'bof');
    
    % when reading the data
    if readData
        
        % allocate a data matrix (based on the header information, make
        % sure .totalSamples is determined for efficient allocation)
        data = nan(header.totalSamples, header.numStreams + 2);
        
        % start at the first row in matrix index
        rowIndex = 1;
        
    end

    % determine the package header size
    if fileType == 0
        packageHeaderSize = 14;     % .src = SamplePackageID <uint32> + elapsed <double> + #samples <uint16> = 14 bytes
    elseif fileType == 1
        packageHeaderSize = 12;     % .dat = SamplePackageID <uint32> + elapsed <double> = 12 bytes
    else
        fprintf(2, 'Error: could not determine package header size, not reading data\n');
        return;
    end

    % loop as long as there another sample-package header is available
    while ftell(fileID) + packageHeaderSize <= header.filesize

        % read the sample-package header
        if readData == 1
            sampleId    = fread(fileID, 1, 'uint32');
            elapsed     = fread(fileID, 1, 'double');
        else
            fseek(fileID, (4 + 8), 'cof');
        end
        
        % 
        if fileType == 1 && header.maxSamplesStream > 1
            % pipeline data where at least one of the streams has more than one single sample
                        
            % variable to store the current stream that is being read in this package
            streamIndex = 0;
            
            % loop as long as there are streams left for this sample-package and there is
            % another sample-chunk header available (uint16 + uint16 = 4 bytes)
            while streamIndex < header.numStreams && ftell(fileID) + 4 <= header.filesize

                % retrieve the number of streams from the sample-chunk header
                numStreams          = fread(fileID, 1, 'uint16');

                % retrieve the number of samples from the sample-chunk header
                numSamples          = fread(fileID, 1, 'uint16');
                
                % calculate the number of expected values
                numValues           = numStreams * numSamples;
                
                % check if all the sample-values are there
                if ftell(fileID) + (numValues * 8) <= header.filesize

                    %
                    if readData == 1
                    
                        % store the samples in the output matrix
                        data(rowIndex:rowIndex + numSamples - 1, 3 + streamIndex:3 + streamIndex + numStreams - 1) = ...
                            reshape(fread(fileID, numValues, 'double'), numStreams, [])';
                        
                    else

                        % move the read cursor
                        fseek(fileID, (numValues * 8), 'cof');
                        
                    end
                else
                    if readData == 0
                        warning('Not all values in the last sample-chunk are written, discarding last sample-chunk and therefore sample-package. Stop reading.');
                    end
                    success = 1;    % consider a partial read as successful, warning is enough
                    return;
                end

                % add to the number of streams
                streamIndex = streamIndex + numStreams;
                
            end

            
            if readData == 0
                % when only determining the header
                
                % check if the expected number of streams were found
                if  streamIndex == header.numStreams
                    
                    % count the samples
                    % Note: use the maximum number of samples per package. Packages are allowed to differ
                    %       in size, so allocate to facilitate the stream with the largest number of samples
                    header.totalSamples = header.totalSamples + header.maxSamplesStream;
                    
                    % count the packages
                    header.totalPackages = header.totalPackages + 1;                
                
                else
                    warning('Not all streams in the last sample-package are written, discarding last sample-package. Stop reading.');
                    success = 1;    % consider a partial read as successful, warning is enough
                    return;
                end
                
            else
                % when reading the data
                
                % write the sampleID and elapsed (for all the rows that are reserved for this package)
                % Note: this happens only here, so there are no unnecessary rows created in the scenario where
                %       sample-packages are discarded (which we can only know after all the sample-chunk header are read)
                data(rowIndex:rowIndex + header.maxSamplesStream - 1, 2) = elapsed;

                % move the matrix write index
                rowIndex = rowIndex + header.maxSamplesStream;

            end
            
        else
            % source data, or
            % pipeline data where each of the streams has just one single sample
            
            % read the rest of the sample-package
            if fileType == 0
                % source

                % retrieve the number of samples from the sample-package header
                % and calculate the number of expected values
                numSamples          = fread(fileID, 1, 'uint16');
                numValues           = header.numStreams * numSamples;

            else
                % pipeline data, each of the streams has just one single sample

                % set to one sample per package
                % and set the number of values to be read to exactly the number of streams
                numSamples          = 1;
                numValues           = header.numStreams;
                
            end            

            % check if all the sample-values are there
            if ftell(fileID) + (numValues * 8) <= header.filesize

                if readData == 1
                    
                    % store the sample-package ID and elapsed time
                    % store the samples in the output matrix
                    if numSamples == 1
                        
                        data(rowIndex, 1) = sampleId;
                        data(rowIndex, 2) = elapsed;
                        data(rowIndex, 3:3 + header.numStreams - 1) = fread(fileID, numValues, 'double');
                        
                    else
                        
                        data(rowIndex:rowIndex + numSamples - 1, 1) = repmat(sampleId, numSamples, 1);
                        data(rowIndex:rowIndex + numSamples - 1, 2) = elapsed;
                        data(rowIndex:rowIndex + numSamples - 1, 3:3 + header.numStreams - 1) = ...
                            reshape(fread(fileID, numValues, 'double'), header.numStreams, [])';

                    end

                    % move the matrix write index
                    rowIndex = rowIndex + numSamples;

                else
                    % only reading header information

                    % count the samples and packages
                    header.totalSamples = header.totalSamples + numSamples;
                    header.totalPackages = header.totalPackages + 1;

                    % move the read cursor
                    fseek(fileID, (numValues * 8), 'cof');

                end

            else
                if readData == 0
                    warning('Not all values in the last sample-package are written, discarding last sample-package. Stop reading.');
                end
                success = 1;    % consider a partial read as successful, warning is enough
                return;
            end
                        
        end
    
    end     % end sample-packages loop    

    % return success
    success = 1;

end