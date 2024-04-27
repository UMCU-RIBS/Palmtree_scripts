"""
Functions to load Palmtree data
=====================================================



Copyright (C) 2024, Max van den Boom (Lab of Nick Ramsey, University Medical Center Utrecht, The Netherlands)

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.
"""
import os
import logging
import struct
from math import floor
import numpy as np


def load_data(filepath, read_data=True):
    """
    Read the source data (.src) or pipeline data (.dat) of a Palmtree run. The source data (.src) file contains
    the data as it is received by the source module. The pipeline data (.dat) file contains the data streams that
    went into the pipeline and - if enabled - the output of the filter modules and application modules.

    Args:
        filepath (str):                 path to a run data file
        read_data (bool):               If set to 1 (default), both the header and the data will be read
                                        If set to 0, only the header will be read.

    Returns:
        header (Dictionary):            The data header information as a struct, includes information such as the
                                        sampling rate, number of streams and stream names. Returns as much of the
                                        header as possible.
        data (ndarray):                 A matrix holding the data. The first column will be the sample-number, the
                                        second column holds the number of milliseconds that have passed since the last
                                        sample, and the remaining columns represent the sample values that streamed
                                        through the pipeline (the header information can be used to find the exact
                                        channel(s) and where in the pipeline. Returns None on failure.
    """

    # try to open the data file
    try:

        # create an empty header
        header = {}

        with open(filepath, "rb") as file:

            # retrieve the file size (in bytes)
            header['file_size'] = os.path.getsize(filepath)

            # read the version and check whether it is valid
            header['version'] = int.from_bytes(file.read(4), byteorder='little')
            if not header['version'] in (1, 2, 3):
                logging.error('Error: unknown data version ' + header['version'])
                return header, None

            # read the code
            header['code'] = file.read(3).decode('ascii')

            # retrieve the epochs (V2)
            if header['version'] in (2, 3):
                header['run_start_epoch'] = int.from_bytes(file.read(8), byteorder='little')
                header['file_start_epoch'] = int.from_bytes(file.read(8), byteorder='little')

            # retrieve whether source input time is included (only in source data-file & V3)
            if header['code'].lower() == 'src' and header['version'] == 3:
                header['includes_source_input_time'] = bool.from_bytes(file.read(1), byteorder='little')

            #
            header['sample_rate'] = struct.unpack('<d', file.read(8))[0]
            header['num_playback_streams'] = int.from_bytes(file.read(4), byteorder='little')

            # num-streams + streams details (V2)
            if header['version'] in (2, 3):
                header['num_streams'] = int.from_bytes(file.read(4), byteorder='little')
                header['stream_data_types'] = []
                header['stream_samples_per_package'] = []
                for iStream in range(0, header['num_streams']):
                    header['stream_data_types'].append(int.from_bytes(file.read(1), byteorder='little'))
                    header['stream_samples_per_package'].append(int.from_bytes(file.read(2), byteorder='little'))

            # num-columns + columns names
            header['num_columns'] = int.from_bytes(file.read(4), byteorder='little')
            header['column_names_size'] = int.from_bytes(file.read(4), byteorder='little')
            header['column_names'] = file.read(header['column_names_size']).decode('ascii').split('\t')

            # store the position where the data starts
            header['pos_data_start'] = file.tell()

            #
            # extra fields and reading the data
            #

            # determine the file type
            file_type = 2  # 0 = source, 1 = pipeline, 2 = plugin
            if header['code'].lower() == 'src':
                file_type = 0
            if header['code'].lower() == 'dat':
                file_type = 1

            #
            if header['version'] == 1:

                # determine the size of one row (in bytes)
                if file_type == 0 or file_type == 1:
                    # source or pipeline data
                    header['row_size'] = 4  # sample id
                    header['row_size'] += (header['num_columns'] - 1) * 8  # sample data

                else:
                    # plugin data
                    header['row_size'] = header['num_columns'] * 8

                # determine the number of rows
                header['num_rows'] = floor((header['file_size'] - header['pos_data_start']) / header['row_size'])

                # check whether to read the data
                if read_data:

                    # initialize an output matrix (samples x columns/streams)
                    data = _allocate_array((header['num_rows'], header['num_columns']))
                    if data is None:
                        return header, None

                    for iRow in range(0, header['num_rows']):
                        # read the sample-counter
                        data[iRow, 0] = int.from_bytes(file.read(4), byteorder='little')

                        # read the rest of the values
                        data[iRow, 1:header['num_columns']] = np.fromfile(file, dtype=np.dtype('<d'),
                                                                          count=header['num_columns'] - 1, sep='',
                                                                          offset=0)

                    # successfully read V1 data, return header and data
                    return header, data

            elif header['version'] in (2, 3):

                # counter for the number of samples
                header['total_samples'] = 0
                header['total_packages'] = 0

                # determine the highest number of samples that any source stream (.src) or any stream in the pipeline (.dat) would want to log
                header['max_samples_stream'] = max(header['stream_samples_per_package'])

                # read the headers of all the packages
                # Note: Needs to be performed first to establish .totalSamples. With .totalSamples calculated
                #       the readPackages can allocate a matrix big enough for the data on the second call)
                success, _ = __read_packages(file, header, file_type, False)
                if success:

                    # read the data (if needed)
                    if read_data:
                        success, data = __read_packages(file, header, file_type, True)

                        # successfully read V2 data, return header and data
                        if success == 1:
                            return header, data

            # only the header needed to be read (or data failed to be read), return only header
            return header, None

    except FileNotFoundError as e:
        logging.error('Could not locate file at: \'' + filepath + '\'')
        return None, None

    except IOError as e:
        logging.error('Could not access file at: \'' + filepath + '\'')
        return None, None

    except Exception as e:
        logging.error('Exception while reading data, message: ' + str(e))
        return None, None


def __read_packages(file, header, file_type, read_data):
    data = None

    # determine whether source-input-timestamps are included
    includes_input_time = file_type == 0 and 'includes_source_input_time' in header and header['includes_source_input_time']

    # set the read cursor at the start of the data
    file.seek(header['pos_data_start'], 0)

    # determine the package header size
    if file_type == 0:
        if includes_input_time:
            package_header_size = 22  # .src = SamplePackageID <uint32> + elapsed <double> + source-input-time <double> + #samples <uint16> = 22 bytes
            data_num_header_columns = 3
        else:
            package_header_size = 14  # .src = SamplePackageID <uint32> + elapsed <double> + #samples <uint16> = 14 bytes
            data_num_header_columns = 2
    elif file_type == 1:
        package_header_size = 12  # .dat = SamplePackageID <uint32> + elapsed <double> = 12 bytes
        data_num_header_columns = 2
    else:
        logging.error('Error: could not determine package header size, not reading data')
        return False, None

    # when reading the data
    if read_data:

        # allocate a data matrix (based on the header information, make
        # sure .totalSamples is determined for efficient allocation)
        data = _allocate_array((header['total_samples'], header['num_streams'] + data_num_header_columns))
        if data is None:
            return False, None

        # start at the first row in matrix index
        row_index = 0

    # loop as long as there another sample-package header is available
    while file.tell() + package_header_size <= header['file_size']:

        # read the sample-package header
        if read_data:
            sample_id = int.from_bytes(file.read(4), byteorder='little')
            elapsed = struct.unpack('<d', file.read(8))[0]
            if includes_input_time:
                source_input_time = struct.unpack('<d', file.read(8))[0]

        else:
            if includes_input_time:
                file.seek((4 + 8 + 8), 1)
            else:
                file.seek((4 + 8), 1)

        #
        if file_type == 1 and header['max_samples_stream'] > 1:
            # pipeline data where at least one of the streams has more than one single sample

            # variable to store the current stream that is being read in this package
            stream_index = 0

            # loop as long as there are streams left for this sample-package and there is
            # another sample-chunk header available (uint16 + uint16 = 4 bytes)
            while stream_index < header['num_streams'] and file.tell() + 4 <= header['file_size']:

                # retrieve the number of streams from the sample-chunk header
                num_streams = int.from_bytes(file.read(2), byteorder='little')

                # retrieve the number of samples from the sample-chunk header
                num_samples = int.from_bytes(file.read(2), byteorder='little')

                # calculate the number of expected values
                num_values = num_streams * num_samples

                # check if all the sample-values are there
                if file.tell() + (num_values * 8) <= header['file_size']:

                    if read_data:

                        # store the samples in the output matrix
                        data[row_index:row_index + num_samples, data_num_header_columns + stream_index:data_num_header_columns + stream_index + num_streams] = \
                            np.reshape(np.fromfile(file, dtype=np.dtype('<d'), count=num_values, sep='', offset=0),
                                       (-1, num_streams))

                    else:

                        # move the read cursor
                        file.seek((num_values * 8), 1)

                else:
                    if not read_data:
                        logging.warning(
                            'Not all values in the last sample-chunk are written, discarding last sample-chunk and therefore sample-package. Stop reading.')
                        return True, None  # consider a partial read as successful, warning is enough

                # add to the number of streams
                stream_index += num_streams

            if not read_data:
                # when only determining the header

                # check if the expected number of streams were found
                if stream_index == header['num_streams']:

                    # count the samples
                    # Note: use the maximum number of samples per package. Packages are allowed to differ
                    # in size, so allocate to facilitate the stream with the largest number of samples
                    header['total_samples'] += num_samples

                    # count the packages
                    header['total_packages'] += 1

                else:
                    logging.warning(
                        'Not all streams in the last sample-package are written, discarding last sample-package. Stop reading.');
                    return True, None  # consider a partial read as successful, warning is enough

            else:
                # when reading the data

                # write the sample-ID and elapsed (for all the rows that are reserved for this package)
                # Note: this happens only here, so there are no unnecessary rows created in the scenario where
                #       sample-packages are discarded (which we can only know after all the sample-chunk header are read)
                data[row_index:row_index + num_samples, 0] = sample_id
                data[row_index:row_index + num_samples, 1] = elapsed

                # move the matrix write index
                row_index += num_samples

        else:
            # source data, or
            # pipeline data where each of the streams has just one single sample

            # read the rest of the sample-package
            if file_type == 0:
                # source

                # retrieve the number of samples from the sample-package header
                # and calculate the number of expected values
                num_samples = int.from_bytes(file.read(2), byteorder='little')
                num_values = header['num_streams'] * num_samples

            else:
                # pipeline data, each of the streams has just one single sample

                # set to one sample per package and set the number of values to be read to exactly the number of streams
                num_samples = 1
                num_values = header['num_streams']

            # check if all the sample-values are there
            if file.tell() + (num_values * 8) <= header['file_size']:

                if read_data == 1:

                    # store the sample-package ID and elapsed time
                    # store the samples in the output matrix
                    if num_samples == 1:

                        data[row_index, 0] = sample_id
                        data[row_index, 1] = elapsed
                        if includes_input_time:
                            data[row_index, 2] = source_input_time
                        data[row_index, data_num_header_columns:data_num_header_columns + header['num_streams']] = \
                            np.fromfile(file, dtype=np.dtype('<d'), count=num_values, sep='', offset=0)

                    else:

                        data[row_index:row_index + num_samples, 0] = sample_id
                        data[row_index:row_index + num_samples, 1] = elapsed
                        if includes_input_time:
                            data[row_index:row_index + num_samples, 2] = source_input_time
                        data[row_index:row_index + num_samples, data_num_header_columns:data_num_header_columns + header['num_streams']] = \
                            np.reshape(np.fromfile(file, dtype=np.dtype('<d'), count=num_values, sep='', offset=0),
                                       (-1, header['num_streams']))

                    # move the matrix write index
                    row_index = row_index + num_samples

                else:
                    # only reading header information

                    # count the samples and packages
                    header['total_samples'] += num_samples
                    header['total_packages'] += 1

                    # move the read cursor
                    file.seek((num_values * 8), 1)

            else:
                if not read_data:
                    logging.warning(
                        'Not all values in the last sample-package are written, discarding last sample-package. Stop reading.')
                return True, data  # consider a partial read as successful, warning is enough

    # return success
    return True, data


def _allocate_array(dimensions, fill_value=np.nan, dtype='float64', check_mem=False):
    """
    Create and immediately allocate the memory for an x-dimensional array

    Before allocating the memory, this function can check if is enough memory is available (this can be helpful when a
    numpy array is allocated and there is not enough memory, python crashes without the chance to catch an error).

    Args:
        dimensions (int or tuple):
        fill_value (any numeric):
        dtype (str):
        check_mem (bool)

    Returns:
        data (ndarray):             An initialized x-dimensional array, or None if insufficient memory available

    """
    # initialize a data buffer (channel x trials/epochs x time)
    try:

        # create a ndarray object (no memory is allocated here)
        data = np.empty(dimensions, dtype=dtype)
        data_bytes_needed = data.nbytes

        # check if there is enough memory available
        if check_mem:
            from psutil import virtual_memory
            mem = virtual_memory()
            if mem.available <= data_bytes_needed:
                raise MemoryError()

        # allocate the memory
        data.fill(fill_value)

        #
        return data

    except MemoryError:
        logging.error('Not enough memory available to create array.\nAt least ' + str(int((mem.used + data_bytes_needed) / (1024.0 ** 2))) + ' MB is needed, most likely more.\n(for docker users: extend the memory resources available to the docker service)')
        return None

