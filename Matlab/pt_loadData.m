%   
%   Read the source data (.src) or pipeline data (.dat) of a Palmtree run. 
%   The source data (.src) file contains the data as it is received by the source module. The
%   pipeline data (.dat) file contains the data streams that went into the pipeline and - if 
%   enabled - the output of the filter modules and application modules.
%
%   [header, samples] = pt_loadData(filepath, readSource)
%
%       filepath     = path (with or without file-extension) to any of the run's data files
%		readSource   = if set to 0, the pipeline data (.dat) will be read; 
%                      if set to 1, the source data (.src) will be read
%
%   Returns: 
%       header       = The data header information as a struct, includes information such as
%                      the sampling rate, number of streams and stream names
% 		samples      = A matrix holding the data. The first column will be the sample-number, the second
%                      column holds the number of milliseconds that have passed since the last sample, and the 
%                      remaining columns represent the sample values that streamed through the pipeline (the header
%                      information can be used to find the exact channel(s) and where in the pipeline.
%   
%   Copyright (C) 2017, Max van den Boom (Lab of Nick Ramsey, University Medical Center Utrecht, The Netherlands)

%   This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
%   as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
%   This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied 
%   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
%   You should have received a copy of the GNU General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.
%
function [header, samples] = pt_loadData(filepath, readSource)
    
    % remove the extension from the filepath if there is one
    [pathstr,name] = fileparts(filepath);
    filepath = [pathstr, filesep, name];
    clear pathstr pathstr;
    
    % build the seperate filepaths
    prmFilepath = [filepath, '.prm'];
	srcFilepath = [filepath, '.src'];
    datFilepath = [filepath, '.dat'];
    
	inputFilepath = datFilepath;
	if (readSource == 1)
		inputFilepath = srcFilepath;
	end
	
    % check if the dat input file exist
    if exist(inputFilepath, 'file') == 0
        fprintf(2, ['Error: data file ', inputFilepath, ' does not exist\n']);
        return;
    end

    % create an empty header
    header = struct;
    header.version = 0;
    header.code = '';
    header.sampleRate = 0.0;
    header.numPlaybackStreams = 0;
    header.numColumns = 0;
    header.columnNamesSize = 0;
    header.columnNames = {};
    header.rowSize = 0;
    header.numRows = 0;
    header.posDataStart = 0;
    header.filesize = 0;

    % retrieve the filesize
    fileSize = dir(inputFilepath);
    header.filesize = fileSize.bytes;
    clear fileSize;

    % open the file
    fileID = fopen(inputFilepath);

    if fileID == -1
        fprintf(2, ['Error: could not open data file ', inputFilepath, '\n']);
        return;
    end

    % read header properties
    header.version = fread(fileID, 1, 'int');
    if header.version == 1

        header.code = fread(fileID, 3, '*char')';
        header.sampleRate = fread(fileID, 1, 'double');
        header.numPlaybackStreams = fread(fileID, 1, 'int');
        header.numColumns = fread(fileID, 1, 'int');
        header.columnNamesSize = fread(fileID, 1, 'int');
        header.columnNames = fread(fileID, header.columnNamesSize, '*char')';
        header.columnNames = strsplit(header.columnNames,'\t');

        % determine the size of one row (in bytes)
        header.rowSize = 4;                                             % sample id
        header.rowSize = header.rowSize + (header.numColumns - 1) * 8;  % sample data

        % store the position where the data starts
        header.posDataStart = ftell(fileID);

        % determine the number of rows
        header.numRows = floor((header.filesize - header.posDataStart) / header.rowSize);

        % read the samples
        sampleCount = zeros(header.numRows, 1);
        samples = zeros(header.numRows, header.numColumns - 1);
        for i = 1:header.numRows

            % read the samplecounter
            sampleCount(i) = fread(fileID, 1, 'uint');

            % read the rest of the values
            samples(i, 1:header.numColumns - 1) = fread(fileID, header.numColumns - 1, 'double');

        end
        clear i;

        % concatenate count and other columns
        samples = horzcat(sampleCount, samples);
        clear sampleCount;

    end

    % close the file
    status = fclose(fileID);
    clear fileID;
    clear status;

end
