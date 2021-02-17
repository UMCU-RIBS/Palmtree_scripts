"""
Miscellaneous functions and classes
=====================================================
A variety of helper functions and classes


Copyright 2020, Max van den Boom (Multimodal Neuroimaging Lab, Mayo Clinic, Rochester MN)

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.
"""
import logging
import numpy as np
from psutil import virtual_memory


def allocate_array(dimensions, fill_value=np.nan, dtype='float64'):
    """
    Create and immediately allocate the memory for an x-dimensional array

    Before allocating the memory, this function checks if is enough memory is available (this is needed since when a
    numpy array is allocated and there is not enough memory, python crashes without the chance to catch an error).

    Args:
        dimensions (int or tuple):
        fill_value (any numeric):
        dtype (str):

    Returns:
        data (ndarray):             An initialized x-dimensional array, or None if insufficient memory available

    """
    # initialize a data buffer (channel x trials/epochs x time)
    try:

        # create a ndarray object (no memory is allocated here)
        data = np.empty(dimensions, dtype=dtype)
        data_bytes_needed = data.nbytes

        # check if there is enough memory available
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

